import 'package:flutter/material.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'guided_damage_capture_screen.dart';
import 'photo_preview_screen.dart';
import 'CaseSubmittedScreen.dart';
import 'CaseFailureScreen.dart';
import '../home/home_screen.dart';
import 'cloudinary_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../NavBar/nav_bar.dart';
import 'dart:ui';

// ─────────────────────────────────────────────
// VehicleItem — now includes docId from Firestore
// ─────────────────────────────────────────────
class VehicleItem {
  final String docId;
  final String name;
  final String plate;

  const VehicleItem({
    required this.docId,
    required this.name,
    required this.plate,
  });
}

class SubmitCaseScreen extends StatefulWidget {
  const SubmitCaseScreen({super.key});
  @override
  State<SubmitCaseScreen> createState() => _SubmitCaseScreenState();
}

class _SubmitCaseScreenState extends State<SubmitCaseScreen> {
  // ── State ─────────────────────────────────────────────────────────
  List<File> capturedPhotos = [];
  int _currentIndex = 1;

  // ── Vehicle ───────────────────────────────────────────────────────
  List<VehicleItem> _vehicles = [];
  VehicleItem? selectedVehicle;
  bool _loadingVehicles = true;

  // ── Najm PDF ──────────────────────────────────────────────────────
  String? najmFileName;
  String? najmFilePath;
  int? najmFileBytes;

  // ── Submission state ──────────────────────────────────────────────
  bool _isSubmitting = false;
  String _submitStatus = '';

  // ── Validation ────────────────────────────────────────────────────
  bool get canSubmit =>
      selectedVehicle != null &&
      najmFileName != null &&
      capturedPhotos.isNotEmpty &&
      !_isSubmitting;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  // ─────────────────────────────────────────────────────────────────
  // Load vehicles from Firestore
  // ─────────────────────────────────────────────────────────────────
  Future<void> _loadVehicles() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('ownerId', isEqualTo: uid)
          .where('isArchived', isEqualTo: false)
          .get();

      final vehicles = snapshot.docs.map((doc) {
        final data = doc.data();
        final make = data['make'] ?? '';
        final model = data['model'] ?? '';
        final plate = data['plateNumber'] ?? '';
        return VehicleItem(
          docId: doc.id,
          name: '$make $model'.trim(),
          plate: plate,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _vehicles = vehicles;
          _loadingVehicles = false;
        });
      }
    } catch (e) {
      print('❌ Error loading vehicles: $e');
      if (mounted) setState(() => _loadingVehicles = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Pick Najm PDF
  // ─────────────────────────────────────────────────────────────────
  Future<void> pickNajmPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null) return;
    final picked = result.files.single;
    setState(() {
      najmFileName = picked.name;
      najmFilePath = picked.path;
      najmFileBytes = picked.size;
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // Full submit flow
  // ─────────────────────────────────────────────────────────────────
  Future<void> _submitCase() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _isSubmitting = true;
      _submitStatus = 'Uploading PDF...';
    });

    try {
      // ── Step 1: Generate a case ID ───────────────────────────────
      final caseRef = FirebaseFirestore.instance
          .collection('accidentCase')
          .doc();
      final caseId = caseRef.id;

      // ── Step 2: Read PDF as base64 and store in Firestore ───────
      // Cloudinary blocks raw file delivery on free accounts,
      // so we store the PDF as base64 directly in Firestore.
      // Switch to Firebase Storage when billing is available.
      String pdfBase64 = '';
      if (najmFilePath != null) {
        final pdfFile = File(najmFilePath!);
        final pdfBytes = await pdfFile.readAsBytes();

        // ✅ Size check — Firestore document limit is 1MB
        // A Najm PDF is typically 50–200KB, but we guard against large files
        final sizeKB = pdfBytes.length / 1024;
        print('📄 PDF size: ${sizeKB.toStringAsFixed(0)} KB');

        if (pdfBytes.length > 900 * 1024) {
          throw Exception(
            'PDF file is too large (${sizeKB.toStringAsFixed(0)} KB). '
            'Maximum allowed size is 900 KB. Please use a smaller file.',
          );
        }

        pdfBase64 = base64Encode(pdfBytes);
        print('📦 PDF encoded successfully');
      }

      // ── Step 3: Upload all photos to Cloudinary ──────────────────
      setState(() => _submitStatus = 'Uploading photos...');
      final imageUrls = await CloudinaryService.uploadAllImages(
        images: capturedPhotos,
        caseId: caseId,
      );

      // ✅ Fail early if all photo uploads failed
      if (imageUrls.isEmpty) {
        throw Exception('Photo upload failed — check your internet connection');
      }

      // ── Step 4: Write case document to Firestore ─────────────────
      setState(() => _submitStatus = 'Saving case...');
      await caseRef.set({
        'caseID': caseId,
        'ownerId': uid,
        'vehicleId': selectedVehicle!.docId,
        'status': 'submitted',
        'createdAt': FieldValue.serverTimestamp(),
        // ✅ pdfBase64 stored at top level — Firestore rejects large
        // strings inside nested maps
        'pdfBase64': pdfBase64,
        'najimReport': {
          'pdfUrl': '', // reserved for future Firebase Storage URL
          'accidentDate': '', // filled later by Najm OCR
          'accidentNumber': '', // filled later by Najm OCR
          'damageLocation': '', // filled later by Najm OCR
        },
      });

      // ── Step 5: Write each image as a subcollection document ─────
      for (int i = 0; i < imageUrls.length; i++) {
        await caseRef.collection('images').add({
          'downloadUrl': imageUrls[i],
          'label': 'damage${i + 1}',
          'storagePath': 'accident_cases/$caseId/image_$i',
          'uploadedAt': FieldValue.serverTimestamp(),
        });
      }

      // ── Step 6: Call Najm OCR backend to extract PDF fields ──────
      // This runs in background — we don't block the user waiting for it
      // If it fails, the case is still submitted successfully
      _callNajmOcr(caseId);

      // ── Step 7: Lock National ID if this is the first case ──────
      final allCases = await FirebaseFirestore.instance
          .collection('accidentCase')
          .where('ownerId', isEqualTo: uid)
          .get();

      // If only one case exists (the one we just created), lock the ID
      if (allCases.docs.length == 1) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'nationalIDLocked': true,
        });
      }

      // ── Step 7: Navigate to success screen ───────────────────────
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CaseSubmittedScreen()),
        );
      }
    } catch (e) {
      print('❌ Submit error: $e');
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitStatus = '';
        });
        // ✅ Navigate to failure screen instead of showing a snackbar
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CaseFailedScreen()),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Call Najm OCR backend — runs in background after submission
  // ─────────────────────────────────────────────────────────────────
  void _callNajmOcr(String caseId) async {
    // ⚠️ Replace with your deployed backend URL when available
    // For local testing use your machine's IP e.g. http://192.168.1.x:8000
    const backendUrl = 'http://YOUR_BACKEND_URL:8000';

    try {
      print('🔍 Calling Najm OCR for case: $caseId');
      final response = await http
          .post(Uri.parse('$backendUrl/ocr/najm/$caseId'))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          print('✅ Najm OCR success: ${data['data']}');
        } else {
          print('⚠️ Najm OCR returned error: ${data['message']}');
        }
      } else {
        print('⚠️ Najm OCR HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      // OCR failure does NOT affect the case submission
      // The fields will just remain empty until OCR runs
      print('⚠️ Najm OCR call failed (non-critical): $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Confirm dialog
  // ─────────────────────────────────────────────────────────────────
  Future<void> _showConfirmDialog() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // ✅ Check nationalIDLocked directly from Firestore
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final isLocked = userDoc.data()?['nationalIDLocked'] ?? false;

    // ✅ Only show National ID dialog on first case (when not yet locked)
    if (!isLocked) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Confirm National ID',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Please confirm that your National ID is correct. Once submitted, it cannot be edited.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B4A7D),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 4,
                        ),
                        child: const Text('Confirm'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          'cancel',
                          style: TextStyle(color: Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      // User cancelled — do not proceed
      if (confirmed != true || !mounted) return;
    }

    // ✅ Proceed to submit — either first case confirmed, or ID already locked
    await _submitCase();
  }

  // ─────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────
  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    if (index == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => _currentIndex = index);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Tab ${index + 1} coming soon')));
  }

  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      bottomNavigationBar: _bottomNav(),
      body: Stack(
        children: [
          // ── Main scrollable content ───────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      'Submit A Case',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 30),

                    // ── Grey card ─────────────────────────────────
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Vehicle dropdown ──────────────────
                              const Text('Select vehicle'),
                              const SizedBox(height: 8),
                              _loadingVehicles
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  : _vehicles.isEmpty
                                  ? Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      child: const Text(
                                        'No vehicles found. Please add a vehicle first.',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    )
                                  : DropdownButtonFormField<VehicleItem>(
                                      value: selectedVehicle,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: Colors.white,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 14,
                                            ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF2F6FED),
                                            width: 1.5,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.grey.shade300,
                                            width: 1.2,
                                          ),
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                      ),
                                      hint: const Text('Select'),
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down,
                                      ),
                                      items: _vehicles.map((v) {
                                        return DropdownMenuItem<VehicleItem>(
                                          value: v,
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  v.name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                v.plate,
                                                style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: _isSubmitting
                                          ? null
                                          : (value) => setState(
                                              () => selectedVehicle = value,
                                            ),
                                    ),

                              // ── Najm report ───────────────────────
                              const SizedBox(height: 40),
                              const Text('Upload najm report'),
                              const SizedBox(height: 8),
                              if (najmFileName == null) ...[
                                InkWell(
                                  onTap: _isSubmitting ? null : pickNajmPdf,
                                  borderRadius: BorderRadius.circular(12),
                                  child: DottedBorder(
                                    color: const Color(0xFF2F6FED),
                                    dashPattern: const [6, 4],
                                    strokeWidth: 1.5,
                                    borderType: BorderType.RRect,
                                    radius: const Radius.circular(12),
                                    child: const SizedBox(
                                      height: 130,
                                      width: double.infinity,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.upload_file,
                                            size: 36,
                                            color: Colors.black54,
                                          ),
                                          SizedBox(height: 6),
                                          Text(
                                            'upload file',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'supported format: PDF',
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F5F5),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF5F5F5),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.picture_as_pdf,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              najmFileName!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'just now',
                                              style: TextStyle(
                                                color: Colors.grey.shade500,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          najmFileBytes == null
                                              ? ''
                                              : formatBytes(najmFileBytes!),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      InkWell(
                                        onTap: _isSubmitting
                                            ? null
                                            : () {
                                                setState(() {
                                                  najmFileName = null;
                                                  najmFilePath = null;
                                                  najmFileBytes = null;
                                                });
                                              },
                                        child: const Icon(
                                          Icons.close,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // ── Take Damage Photos ─────────────────
                              const SizedBox(height: 40),
                              const Text('Take Damage Photos'),
                              const Text(
                                '10 images maximum',
                                style: TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 12),

                              if (capturedPhotos.isEmpty)
                                Center(
                                  child: ElevatedButton.icon(
                                    onPressed: _isSubmitting
                                        ? null
                                        : () async {
                                            final result =
                                                await Navigator.push<
                                                  List<File>
                                                >(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const GuidedDamageCaptureScreen(),
                                                  ),
                                                );
                                            if (result == null ||
                                                result.isEmpty)
                                              return;
                                            setState(
                                              () => capturedPhotos = result,
                                            );
                                          },
                                    icon: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      'Take Photos',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0B4A7D),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      elevation: 6,
                                    ),
                                  ),
                                ),

                              if (capturedPhotos.isNotEmpty)
                                SizedBox(
                                  height: 80,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: capturedPhotos.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 10),
                                    itemBuilder: (context, index) {
                                      return Stack(
                                        children: [
                                          InkWell(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      PhotoPreviewScreen(
                                                        imageFile:
                                                            capturedPhotos[index],
                                                      ),
                                                ),
                                              );
                                            },
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Image.file(
                                                capturedPhotos[index],
                                                width: 70,
                                                height: 70,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: InkWell(
                                              onTap: _isSubmitting
                                                  ? null
                                                  : () => setState(
                                                      () => capturedPhotos
                                                          .removeAt(index),
                                                    ),
                                              child: Container(
                                                width: 18,
                                                height: 18,
                                                decoration: const BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.close,
                                                  size: 14,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),

                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── Submit button ─────────────────────────────
                    if (canSubmit) ...[
                      const SizedBox(height: 24),
                      Center(
                        child: ElevatedButton(
                          onPressed: _showConfirmDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0B4A7D),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 6,
                          ),
                          child: const Text(
                            'Submit Case',
                            style: TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),

          // ── Loading overlay ───────────────────────────────────────
          if (_isSubmitting)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF0B4A7D)),
                      const SizedBox(height: 16),
                      Text(
                        _submitStatus,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Bottom Nav
  // ─────────────────────────────────────────────────────────────────
  Widget _bottomNav() {
    return AppBottomNav(currentIndex: _currentIndex, onTap: _onNavTap);
  }
}

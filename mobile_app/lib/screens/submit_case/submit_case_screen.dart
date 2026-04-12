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
import 'cloudinary_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../NavBar/nav_bar.dart';
import 'dart:ui';
import 'imageValidator.dart';

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
  bool _infoConfirmed = false;
  bool _isValidating = false;
  DateTime _najmUploadedAt = DateTime.now();
  // ── Validation state ─────────────────────────────────────────────
  int _validationProgress = 0;
  List<ImageValidationResult> _validationResults = [];

  bool get _hasValidationResults =>
      _validationResults.isNotEmpty &&
      _validationResults.length == capturedPhotos.length;

  bool get _allUncertain =>
      _hasValidationResults && ImageValidator.allUncertain(_validationResults);

  // ── Validation ────────────────────────────────────────────────────
  bool get canSubmit =>
      selectedVehicle != null &&
      najmFileName != null &&
      capturedPhotos.isNotEmpty &&
      _infoConfirmed &&
      !_isSubmitting &&
      !_isValidating;

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

  // ────────────────────validation function ───────────────────────────────
  Future<void> _validateCapturedImages(List<File> images) async {
    setState(() {
      _isValidating = true;
      _validationProgress = 0;
      _validationResults = List.generate(
        images.length,
        (i) => ImageValidationResult.pending(images[i]),
      );
    });

    await ImageValidator.validateAll(
      images: images,
      onProgress: (index, result) {
        if (!mounted) return;
        setState(() {
          _validationResults[index] = result;
          _validationProgress = index + 1;
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _isValidating = false;
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // Pick Najm PDF — checks size before accepting
  // ─────────────────────────────────────────────────────────────────
  Future<void> pickNajmPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null) return;
    final picked = result.files.single;

    // ✅ Reject files over 5MB — same limit as Firestore check in _submitCase
    if (picked.size > 5 * 1024 * 1024) {
      if (!mounted) return;
      await _showFileSizeDialog(picked.size);
      return;
    }

    setState(() {
      najmFileName = picked.name;
      najmFilePath = picked.path;
      najmFileBytes = picked.size;
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // File size warning dialog
  // Same visual style as the National ID confirmation dialog
  // ─────────────────────────────────────────────────────────────────
  Future<void> _showFileSizeDialog(int fileSize) async {
    final sizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(1);

    // Get screen dimensions
    final size = MediaQuery.of(context).size;
    final double screenWidth = size.width;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          // Keeps the dialog from stretching too wide on tablets
          constraints: BoxConstraints(
            maxWidth: screenWidth > 600 ? 400 : screenWidth * 0.9,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(screenWidth * 0.06), // Responsive padding
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment
                        .center, // Centers the group horizontally
                    crossAxisAlignment: CrossAxisAlignment
                        .center, // Aligns icon and text vertically
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red,
                        size: screenWidth * 0.07,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        // Flexible allows the text to only take the space it needs
                        child: Text(
                          'File Too Large',
                          textAlign: TextAlign
                              .center, // Ensures text lines center if they wrap
                          style: TextStyle(
                            fontSize: screenWidth * 0.045,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenWidth * 0.04),

                  // ── Body ──────────────────────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'The selected PDF is $sizeMB MB, which exceeds the 5 MB limit.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: screenWidth * 0.035, // Responsive font
                          color: Colors.black87,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Please compress the file before uploading ',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: screenWidth * 0.035, // Responsive font
                          color: Colors.black87,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenWidth * 0.06),

                  // ── Button ────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4A7D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 4,
                      ),
                      child: Text(
                        'Got it',
                        style: TextStyle(fontSize: screenWidth * 0.04),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────all uncertain dialog ──────────────────────────────
  Future<bool> _showAllUncertainWarning() async {
    final size = MediaQuery.of(context).size;
    final double screenWidth = size.width;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenWidth > 600 ? 400 : screenWidth * 0.9,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(screenWidth * 0.06),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                        size: screenWidth * 0.07,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        // Replaced Expanded with Flexible for better centering
                        child: Text(
                          'Images Could Not Be Verified',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: screenWidth * 0.045,
                            fontWeight: FontWeight.bold,
                          ),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenWidth * 0.04),
                  Text(
                    'None of the captured images could be confirmed as vehicle-related. Please ensure your photos clearly show vehicle damage.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: screenWidth * 0.035,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: screenWidth * 0.06),
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
                          child: Text(
                            'Submit Anyway',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: screenWidth * 0.032),
                          ),
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
                          child: Text(
                            'Retake Photos',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: screenWidth * 0.032,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return result ?? false;
  }

  // ─────────────────────────────────────────────────────────────────
  // Upload Najm PDF to Firebase Storage and return the download URL
  //-─────────────────────────────────────────────────────────────────
  Future<Map<String, String>> _uploadNajmPdfToStorage({
    required String caseId,
    required String filePath,
  }) async {
    final file = File(filePath);
    final ref = FirebaseStorage.instance
        .ref()
        .child('najm reports')
        .child(caseId)
        .child('report.pdf');

    final task = await ref.putFile(file);
    final downloadUrl = await task.ref.getDownloadURL();

    return {'pdfPath': ref.fullPath, 'pdfUrl': downloadUrl};
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Upload damage photos to Firebase Storage and return list of download URLs
  //───────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, String>>> _uploadImagesToStorage({
    required String caseId,
    required List<File> images,
  }) async {
    final List<Map<String, String>> uploaded = [];

    for (int i = 0; i < images.length; i++) {
      final file = images[i];
      final extension = file.path.split('.').last.toLowerCase();
      final ref = FirebaseStorage.instance
          .ref()
          .child('case images')
          .child(caseId)
          .child('image_$i.$extension');

      final task = await ref.putFile(file);
      final downloadUrl = await task.ref.getDownloadURL();

      uploaded.add({'storagePath': ref.fullPath, 'downloadUrl': downloadUrl});
    }

    return uploaded;
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

      // ── Step 2: Upload Najm PDF to Firebase Storage ──────────────
      setState(() => _submitStatus = 'Uploading PDF...');

      String pdfPath = '';
      String pdfUrl = '';

      if (najmFilePath != null) {
        final pdfFile = File(najmFilePath!);
        final pdfBytes = await pdfFile.readAsBytes();

        final sizeMB = pdfBytes.length / (1024 * 1024);
        print('📄 PDF size: ${sizeMB.toStringAsFixed(2)} MB');

        if (pdfBytes.length > 5 * 1024 * 1024) {
          throw Exception(
            'PDF file is too large (${sizeMB.toStringAsFixed(2)} MB). '
            'Maximum allowed size is 5 MB.',
          );
        }

        final uploadedPdf = await _uploadNajmPdfToStorage(
          caseId: caseId,
          filePath: najmFilePath!,
        );

        pdfPath = uploadedPdf['pdfPath']!;
        pdfUrl = uploadedPdf['pdfUrl']!;
        print('✅ PDF uploaded to Firebase Storage');
      }

      // ── Step 3: Upload all photos to Firebase Storage ────────────
      setState(() => _submitStatus = 'Uploading photos...');

      final uploadedImages = await _uploadImagesToStorage(
        caseId: caseId,
        images: capturedPhotos,
      );

      if (uploadedImages.isEmpty) {
        throw Exception('Photo upload failed — check your internet connection');
      }

      // ── Step 4: Write case document to Firestore ─────────────────
      setState(() => _submitStatus = 'Saving case...');

      await caseRef.set({
        'caseID': caseId,
        'ownerId': uid,
        'vehicleId': selectedVehicle!.docId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'najimReport': {
          'pdfPath': pdfPath,
          'pdfUrl': pdfUrl,
          'accidentDate': '',
          'accidentNumber': '',
          'damageLocation': '',
        },
      });

      // ── Step 5: Write each image as a subcollection document ─────
      for (int i = 0; i < uploadedImages.length; i++) {
        await caseRef.collection('images').add({
          'downloadUrl': uploadedImages[i]['downloadUrl'],
          'label': 'damage${i + 1}',
          'storagePath': uploadedImages[i]['storagePath'],
          'uploadedAt': FieldValue.serverTimestamp(),
        });
      }
      // ── Step 6: Trigger Najm OCR backend in background ───────────
      // Case is created with status = pending
      // Backend will update Firestore to:
      // - under_analysis on OCR success
      // - ocr_failed on OCR failure
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
  Future<void> _callNajmOcr(String caseId) async {
    const backendUrl = 'http://172.20.10.2:8000';

    try {
      print('🔍 Calling Najm OCR for case: $caseId');

      final response = await http
          .post(Uri.parse('$backendUrl/ocr/najm/$caseId'))
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Najm OCR job triggered: $data');
      } else {
        print('⚠️ OCR trigger failed: HTTP ${response.statusCode}');

        // 🔥 NEW: mark as failed
        await FirebaseFirestore.instance
            .collection('accidentCase')
            .doc(caseId)
            .update({
              'status': 'ocr_failed',
              'ocrError': 'Failed to trigger OCR (HTTP ${response.statusCode})',
            });
      }
    } catch (e) {
      print('⚠️ Failed to trigger Najm OCR: $e');

      // 🔥 NEW: mark as failed
      await FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(caseId)
          .update({
            'status': 'ocr_failed',
            'ocrError': 'OCR request failed (network/timeout)',
          });
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Confirm dialog
  // ─────────────────────────────────────────────────────────────────
  Future<void> _showConfirmDialog() async {
    if (!_hasValidationResults) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for image validation to complete'),
        ),
      );
      return;
    }
    if (_allUncertain) {
      final proceed = await _showAllUncertainWarning();
      if (!proceed || !mounted) return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final isLocked = userDoc.data()?['nationalIDLocked'] ?? false;

    if (!isLocked) {
      // Get screen dimensions for responsiveness
      final size = MediaQuery.of(context).size;
      final double screenWidth = size.width;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            // Limits width on tablets so the dialog doesn't look stretched
            constraints: BoxConstraints(
              maxWidth: screenWidth > 600 ? 400 : screenWidth * 0.9,
            ),
            child: SingleChildScrollView(
              // Prevents overflow on small screens
              child: Padding(
                padding: EdgeInsets.all(
                  screenWidth * 0.06,
                ), // Responsive padding
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment
                          .center, // Centers the group horizontally
                      crossAxisAlignment: CrossAxisAlignment
                          .center, // Aligns icon and text vertically
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red,
                          size: screenWidth * 0.07, // Responsive icon
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Confirm National ID',
                            style: TextStyle(
                              fontSize: screenWidth * 0.045, // Responsive font
                              fontWeight: FontWeight.bold,
                            ),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: screenWidth * 0.04),
                    Text(
                      'Please confirm that your National ID is correct. Once submitted, it cannot be edited.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: screenWidth * 0.035, // Responsive font
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: screenWidth * 0.06),
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
                              'Cancel', // Fixed lowercase 'c'
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
          ),
        ),
      );

      if (confirmed != true || !mounted) return;
    }

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

  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),

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
                                              'uploaded',
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
                                    onPressed: _isSubmitting || _isValidating
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

                                            setState(() {
                                              capturedPhotos = result;
                                              _validationResults = [];
                                            });

                                            await _validateCapturedImages(
                                              result,
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
                              if (_isValidating) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF0B4A7D),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Validating images... ($_validationProgress/${capturedPhotos.length})',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (capturedPhotos.isNotEmpty)
                                SizedBox(
                                  height: 80,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: capturedPhotos.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 10),
                                    itemBuilder: (context, index) {
                                      final hasResult =
                                          index < _validationResults.length;
                                      final result = hasResult
                                          ? _validationResults[index]
                                          : null;

                                      return Stack(
                                        clipBehavior: Clip.none,
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

                                          if (result != null &&
                                              !result.isPending)
                                            Positioned(
                                              top: -4,
                                              left: -4,
                                              child: Container(
                                                width: 20,
                                                height: 20,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: result.isValid
                                                      ? const Color(0xFF2EAB5F)
                                                      : Colors.orange,
                                                  border: Border.all(
                                                    color: Colors.white,
                                                    width: 1.5,
                                                  ),
                                                ),
                                                child: Icon(
                                                  result.isValid
                                                      ? Icons.check
                                                      : Icons.warning_rounded,
                                                  size: 12,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),

                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: InkWell(
                                              onTap:
                                                  _isSubmitting || _isValidating
                                                  ? null
                                                  : () => setState(() {
                                                      capturedPhotos.removeAt(
                                                        index,
                                                      );

                                                      if (index <
                                                          _validationResults
                                                              .length) {
                                                        _validationResults
                                                            .removeAt(index);
                                                      }
                                                    }),
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
                              if (_hasValidationResults &&
                                  !_isValidating &&
                                  ImageValidator.countUncertain(
                                        _validationResults,
                                      ) >
                                      0) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.orange.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.info_outline,
                                        color: Colors.orange,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${ImageValidator.countUncertain(_validationResults)} image(s) could not be confirmed as vehicle-related. Please ensure they clearly show vehicle damage.',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black87,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Checkbox(
                                      value: _infoConfirmed,
                                      activeColor: const Color(0xFF0B4A7D),
                                      onChanged: _isSubmitting || _isValidating
                                          ? null
                                          : (value) {
                                              setState(() {
                                                _infoConfirmed = value ?? false;
                                              });
                                            },
                                    ),
                                    const SizedBox(width: 4),
                                    const Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(top: 10),
                                        child: Text(
                                          'I confirm that all submitted information are correct.',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            color: Colors.black87,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

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

                    const SizedBox(height: 120),
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
}

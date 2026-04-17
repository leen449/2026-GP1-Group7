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
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../NavBar/nav_bar.dart';
import 'read_only_info_field.dart';
import 'dart:ui';

// ─────────────────────────────────────────────
// VehicleItem — includes docId from Firestore
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
  // ── Step tracking (1 = vehicle+PDF, 2 = photos+submit) ───────────
  int _currentStep = 1;

  // ── State ─────────────────────────────────────────────────────────
  List<File> capturedPhotos = [];
  String? _caseId;
  // ── User info ─────────────────────────────────────────────────────
  String? _userDocId;
  String _userName = '';
  String _nationalID = '';
  String _phoneNumber = '';
  bool _loadingUser = true;

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

  // ── OCR state ─────────────────────────────────────────────────────
  bool _isRunningOcr = false;

  // ── Step 1 validation ─────────────────────────────────────────────
  bool get _canProceedToStep2 =>
      selectedVehicle != null && najmFileName != null && !_isRunningOcr;

  // ── Step 2 submit validation ──────────────────────────────────────
  bool get canSubmit =>
      capturedPhotos.isNotEmpty && _infoConfirmed && !_isSubmitting;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  // ─────────────────────────────────────────────────────────────────
  // Load user info from Firestore
  // ─────────────────────────────────────────────────────────────────
  Future<void> _loadUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingUser = false);
      return;
    }

    final phone = user.phoneNumber;
    if (phone == null) {
      if (mounted) setState(() => _loadingUser = false);
      return;
    }

    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: phone)
          .limit(1)
          .get();

      if (mounted && query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final data = doc.data();
        print('📱 Auth phone: $phone');
        print('👤 User query docs count: ${query.docs.length}');
        if (query.docs.isNotEmpty) {
          print('🆔 Firestore user doc id: ${query.docs.first.id}');
        }
        setState(() {
          _userName = data['name'] ?? '';
          _nationalID = data['nationalID'] ?? '';
          _phoneNumber = data['phoneNumber'] ?? '';
          _userDocId = doc.id;
          _loadingUser = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _loadingUser = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading user info: $e');
      if (mounted) {
        setState(() => _loadingUser = false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  //If _loadVehicles() runs before _loadUserInfo() finishes, then _userDocId will still be null. To prevent this, we can chain the calls so that _loadVehicles() only runs after _loadUserInfo() has completed and set the _userDocId. Here's how you can modify the initState to ensure this:
  // ─────────────────────────────────────────────────────────────────
  Future<void> _initializeData() async {
    await _loadUserInfo();
    await _loadVehicles();
  }

  // ─────────────────────────────────────────────────────────────────
  // Load vehicles from Firestore
  // ─────────────────────────────────────────────────────────────────
  Future<void> _loadVehicles() async {
    if (_userDocId == null || _userDocId!.isEmpty) {
      print('❌ _userDocId is null or empty. Cannot load vehicles.');
      if (mounted) setState(() => _loadingVehicles = false);
      return;
    }
    print('🚗 Loading vehicles for _userDocId: $_userDocId');
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('ownerId', isEqualTo: _userDocId!)
          .where('isArchived', isEqualTo: false)
          .get();
      print('🚙 Vehicles found: ${snapshot.docs.length}');
      for (final doc in snapshot.docs) {
        print('Vehicle doc: ${doc.id}, ownerId: ${doc.data()['ownerId']}');
      }
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
      if (mounted) {
        setState(() => _loadingVehicles = false);
      }
    }
  }

  Future<String> _waitForCaseStatus({
    required String caseId,
    Duration timeout = const Duration(seconds: 60),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    final start = DateTime.now();

    while (DateTime.now().difference(start) < timeout) {
      final doc = await FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(caseId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final status = (data['status'] ?? '').toString();

        print('🔍 OCR status for case $caseId: $status');

        if (status == 'under_analysis') return 'approved';
        if (status == 'ocr_failed') return 'ocr_failed';
      }

      await Future.delayed(pollInterval);
    }

    return 'timeout';
  }

  void _showBackendConnectionDialog() {
    final size = MediaQuery.of(context).size;
    final double screenWidth = size.width;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenWidth > 600 ? 400 : screenWidth * 0.85,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(screenWidth * 0.06),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        color: Colors.red,
                        size: screenWidth * 0.08,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Connection Failed',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: screenWidth * 0.045,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenWidth * 0.04),
                  Text(
                    'We could not connect to the OCR server.Please make sure the connection details are correct and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: screenWidth * 0.035,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: screenWidth * 0.06),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4A7D),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: screenWidth * 0.03,
                        ),
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
  // ─────────────────────────────────────────────────────────────────
  Future<void> _showFileSizeDialog(int fileSize) async {
    final sizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(1);
    final size = MediaQuery.of(context).size;
    final double screenWidth = size.width;

    await showDialog<void>(
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
                        color: Colors.red,
                        size: screenWidth * 0.07,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'File Too Large',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: screenWidth * 0.045,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenWidth * 0.04),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'The selected PDF is $sizeMB MB, which exceeds the 5 MB limit.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: screenWidth * 0.035,
                          color: Colors.black87,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Please compress the file before uploading.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: screenWidth * 0.035,
                          color: Colors.black87,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenWidth * 0.06),
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

  // ─────────────────────────────────────────────────────────────────
  // OCR failed dialog (reused from home page)
  // ─────────────────────────────────────────────────────────────────
  void _showOcrFailedDialog() {
    final size = MediaQuery.of(context).size;
    final double screenWidth = size.width;
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenWidth > 600 ? 400 : screenWidth * 0.85,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(screenWidth * 0.06),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red,
                        size: screenWidth * 0.08,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Verification Failed',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: screenWidth * 0.045,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenWidth * 0.04),
                  Text(
                    'We could not verify the uploaded PDF as a valid Najm accident report.\n\nPlease upload the correct Najm accident report file.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: screenWidth * 0.035,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: screenWidth * 0.06),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4A7D),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: screenWidth * 0.03,
                        ),
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

  // ─────────────────────────────────────────────────────────────────
  // OCR success dialog
  // ─────────────────────────────────────────────────────────────────
  Future<void> _showOcrSuccessDialog() async {
    final size = MediaQuery.of(context).size;
    final double screenWidth = size.width;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenWidth > 600 ? 400 : screenWidth * 0.85,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(screenWidth * 0.06),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: const Color(0xFF2EAB5F),
                        size: screenWidth * 0.08,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Report Verified',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: screenWidth * 0.045,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenWidth * 0.04),
                  Text(
                    'Your Najm accident report has been successfully verified. You may now proceed to take the damage photos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: screenWidth * 0.035,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: screenWidth * 0.06),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4A7D),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: screenWidth * 0.03,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 4,
                      ),
                      child: Text(
                        'Continue',
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

  // ─────────────────────────────────────────────────────────────────
  // Handle "Next" — upload PDF to storage, run OCR, then advance step
  // ─────────────────────────────────────────────────────────────────
  Future<void> _handleNext() async {
    if (_userDocId == null || _userDocId!.isEmpty) {
      print('❌ _userDocId is null or empty.');
      return;
    }

    if (selectedVehicle == null || najmFilePath == null) {
      print('❌ Vehicle or Najm PDF missing.');
      return;
    }

    setState(() => _isRunningOcr = true);

    try {
      final pdfFile = File(najmFilePath!);
      final pdfBytes = await pdfFile.readAsBytes();

      if (pdfBytes.length > 5 * 1024 * 1024) {
        setState(() => _isRunningOcr = false);
        await _showFileSizeDialog(pdfBytes.length);
        return;
      }

      // 1) Create case doc early
      final caseRef = FirebaseFirestore.instance
          .collection('accidentCase')
          .doc();

      final caseId = caseRef.id;

      // 2) Upload PDF to the real case path
      final uploadedPdf = await _uploadNajmPdfToStorage(
        caseId: caseId,
        filePath: najmFilePath!,
      );

      final pdfPath = uploadedPdf['pdfPath']!;
      final pdfUrl = uploadedPdf['pdfUrl']!;

      // 3) Save initial case document with pending OCR status
      await caseRef.set({
        'caseID': caseId,
        'ownerId': _userDocId!,
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

      // keep case id for later final submission
      _caseId = caseId;

      // 4) Trigger OCR using caseId
      const backendUrl = 'http://192.168.0.11:8000';
      final response = await http
          .post(Uri.parse('$backendUrl/ocr/najm/$caseId'))
          .timeout(const Duration(seconds: 60));

      if (!mounted) return;

      if (response.statusCode != 200) {
        await caseRef.update({
          'status': 'ocr_failed',
          'ocrError': 'Failed to trigger OCR (HTTP ${response.statusCode})',
        });

        setState(() => _isRunningOcr = false);
        _showOcrFailedDialog();
        return;
      }

      // 5) Poll Firestore for OCR result
      final result = await _waitForCaseStatus(caseId: caseId);

      if (!mounted) return;

      if (result == 'approved') {
        setState(() => _isRunningOcr = false);
        await _showOcrSuccessDialog();
        if (!mounted) return;

        final photos = await Navigator.push<List<File>>(
          context,
          MaterialPageRoute(builder: (_) => const GuidedDamageCaptureScreen()),
        );

        if (!mounted) return;

        if (photos != null && photos.isNotEmpty) {
          setState(() {
            capturedPhotos = photos;
            _currentStep = 2;
          });
        }
      } else {
        setState(() => _isRunningOcr = false);
        _showOcrFailedDialog();
      }
    } catch (e) {
      print('❌ OCR error: $e');
      if (mounted) {
        setState(() => _isRunningOcr = false);
        _showBackendConnectionDialog();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Upload Najm PDF to Firebase Storage and return download URL
  // ─────────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────────
  // Upload damage photos to Firebase Storage
  // ─────────────────────────────────────────────────────────────────
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
    if (_userDocId == null || _userDocId!.isEmpty) {
      print('❌ _userDocId is null or empty. Cannot submit case.');
      return;
    }

    if (_caseId == null || _caseId!.isEmpty) {
      print('❌ _caseId is null or empty. OCR step must finish first.');
      return;
    }

    if (selectedVehicle == null) {
      print('❌ No vehicle selected.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitStatus = 'Uploading photos...';
    });

    try {
      final caseRef = FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(_caseId!);

      final uploadedImages = await _uploadImagesToStorage(
        caseId: _caseId!,
        images: capturedPhotos,
      );

      if (uploadedImages.isEmpty) {
        throw Exception('Photo upload failed — check your internet connection');
      }

      setState(() => _submitStatus = 'Saving case...');

      await caseRef.update({
        'ownerId': _userDocId!,
        'vehicleId': selectedVehicle!.docId,
      });

      for (int i = 0; i < uploadedImages.length; i++) {
        await caseRef.collection('images').add({
          'downloadUrl': uploadedImages[i]['downloadUrl'],
          'label': 'damage${i + 1}',
          'storagePath': uploadedImages[i]['storagePath'],
          'uploadedAt': FieldValue.serverTimestamp(),
        });
      }

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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CaseFailedScreen()),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Confirm dialog before final submission
  // ─────────────────────────────────────────────────────────────────
  Future<void> _showConfirmDialog() async {
    if (_userDocId == null || _userDocId!.isEmpty) {
      print('❌ _userDocId is null or empty. Cannot confirm submission.');
      return;
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
  // Build
  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Stack(
        children: [
          // ── Main scrollable content ─────────────────────────────
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

                    // ── User info card ──────────────────────────────

                    // ── Main form card ──────────────────────────────
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
                              // ── User info section inside same card ─────────────────
                              _loadingUser
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Submitting as',
                                          style: TextStyle(
                                            fontSize: 20,
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 15),
                                        ReadOnlyInfoField(
                                          label: 'Name',
                                          value: _userName,
                                          icon: Icons.person_outline,
                                        ),
                                        const SizedBox(height: 14),
                                        ReadOnlyInfoField(
                                          label: 'National ID',
                                          value: _nationalID,
                                          icon: Icons.badge_outlined,
                                        ),
                                        const SizedBox(height: 14),
                                        ReadOnlyInfoField(
                                          label: 'Phone Number',
                                          value: _phoneNumber,
                                          icon: Icons.phone_outlined,
                                        ),
                                      ],
                                    ),
                              const SizedBox(height: 30),
                              // ════════════════════════════════════
                              // STEP 1: Vehicle + PDF
                              // ════════════════════════════════════

                              // ── Vehicle dropdown ─────────────────
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
                                      // Disable dropdown after step 1 is done
                                      onChanged:
                                          (_currentStep > 1 || _isSubmitting)
                                          ? null
                                          : (value) => setState(
                                              () => selectedVehicle = value,
                                            ),
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
                                        disabledBorder: OutlineInputBorder(
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
                                    ),

                              // ── Najm report ──────────────────────
                              const SizedBox(height: 40),
                              const Text('Upload najm report'),
                              const SizedBox(height: 8),
                              if (najmFileName == null) ...[
                                InkWell(
                                  onTap: (_currentStep > 1 || _isSubmitting)
                                      ? null
                                      : pickNajmPdf,
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
                                      // Only allow removing PDF on step 1
                                      if (_currentStep == 1)
                                        InkWell(
                                          onTap: _isRunningOcr
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

                              // ── Next button (step 1 only) ─────────
                              if (_currentStep == 1) ...[
                                const SizedBox(height: 24),
                                Center(
                                  child: ElevatedButton(
                                    onPressed: _canProceedToStep2
                                        ? _handleNext
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0B4A7D),
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          Colors.grey.shade300,
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
                                      'Next',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              // ════════════════════════════════════
                              // STEP 2: Photos + Submit
                              // ════════════════════════════════════
                              if (_currentStep == 2) ...[
                                // ── Take Damage Photos ───────────
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

                                              setState(() {
                                                capturedPhotos = result;
                                              });
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
                                        backgroundColor: const Color(
                                          0xFF0B4A7D,
                                        ),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
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
                                            Positioned(
                                              top: 4,
                                              right: 4,
                                              child: InkWell(
                                                onTap: _isSubmitting
                                                    ? null
                                                    : () => setState(() {
                                                        capturedPhotos.removeAt(
                                                          index,
                                                        );
                                                      }),
                                                child: Container(
                                                  width: 18,
                                                  height: 18,
                                                  decoration:
                                                      const BoxDecoration(
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

                                // ── Confirmation checkbox ─────────
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Checkbox(
                                        value: _infoConfirmed,
                                        activeColor: const Color(0xFF0B4A7D),
                                        onChanged: _isSubmitting
                                            ? null
                                            : (value) {
                                                setState(() {
                                                  _infoConfirmed =
                                                      value ?? false;
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
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── Submit button (step 2 only) ─────────────────
                    if (_currentStep == 2 && canSubmit) ...[
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

          // ── OCR loading overlay ────────────────────────────────────
          if (_isRunningOcr)
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
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF0B4A7D)),
                      SizedBox(height: 16),
                      Text(
                        'Verifying Najm report...',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Submission loading overlay ─────────────────────────────
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
}

// ─────────────────────────────────────────────────────────────────
// Helper widget — single row in the user info card
// ─────────────────────────────────────────────────────────────────
class _UserInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _UserInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0B4A7D)),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 13,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

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
import 'NajmCardInfo.dart';
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
  String? _verifiedVehicleId;

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
  String _extractedAccidentNumber = '';
  String _extractedAccidentDate = '';
  String _extractedDamageLocation = '';
  bool _showExtractedNajmDetails = false;
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

  Future<void> _loadExtractedNajmDetails(String caseId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(caseId)
          .get();

      if (!doc.exists) return;

      final data = doc.data() ?? {};
      final najmReport = (data['najimReport'] as Map<String, dynamic>?) ?? {};

      if (mounted) {
        setState(() {
          _extractedAccidentNumber = najmReport['accidentNumber'] ?? '';
          _extractedAccidentDate = najmReport['accidentDate'] ?? '';
          _extractedDamageLocation = najmReport['damageLocation'] ?? '';
          _showExtractedNajmDetails = true;
        });
      }
    } catch (e) {
      print('❌ Failed to load extracted Najm details: $e');
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
                          'فشل الاتصال',
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
                    'تعذر الاتصال بخادم التحقق. يرجى التأكد من إعدادات الاتصال والمحاولة مرة أخرى.',
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
                        'حسنًا',
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

      _extractedAccidentNumber = '';
      _extractedAccidentDate = '';
      _extractedDamageLocation = '';
      _showExtractedNajmDetails = false;
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
                          'حجم الملف كبير',
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
                        'حجم ملف PDF المحدد هو $sizeMB ميجابايت، ويتجاوز الحد المسموح 5 ميجابايت.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: screenWidth * 0.035,
                          color: Colors.black87,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'يرجى ضغط الملف قبل رفعه.',
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
                        'حسنًا',
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
                          'فشل التحقق',
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
                    'تعذر التحقق من ملف PDF المرفوع كتقرير نجم صحيح.\n\nيرجى رفع تقرير نجم الصحيح.',
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
                        'حسنًا',
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
                          'تم التحقق من التقرير',
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
                    'تم التحقق من تقرير نجم بنجاح. يمكنك الآن المتابعة لالتقاط صور الأضرار.',
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
                        'متابعة',
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
  // Cleanup function to delete case document and PDF if OCR fails or user cancels
  // ─────────────────────────────────────────────────────────────────

  Future<void> _cleanupFailedCase({required String caseId}) async {
    try {
      // Delete PDF from Firebase Storage
      await FirebaseStorage.instance
          .ref()
          .child('najm reports')
          .child(caseId)
          .child('report.pdf')
          .delete();

      print('🧹 Deleted PDF from storage');
    } catch (e) {
      print('⚠️ Failed to delete PDF: $e');
    }

    try {
      // Delete Firestore document
      await FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(caseId)
          .delete();

      print('🧹 Deleted case document');
    } catch (e) {
      print('⚠️ Failed to delete case doc: $e');
    }
  }

  bool get _hasVerifiedNajmReport {
    return _caseId != null &&
        _caseId!.isNotEmpty &&
        _extractedAccidentNumber.trim().isNotEmpty &&
        _extractedAccidentDate.trim().isNotEmpty &&
        _extractedDamageLocation.trim().isNotEmpty;
  }

  Future<void> _goToDamageCapture() async {
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
    if (_hasVerifiedNajmReport) {
      await _goToDamageCapture();
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
      final caseRef = _caseId == null || _caseId!.isEmpty
          ? FirebaseFirestore.instance.collection('accidentCase').doc()
          : FirebaseFirestore.instance.collection('accidentCase').doc(_caseId!);

      final caseId = caseRef.id;
      _caseId = caseId;

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
        'isSubmitted': false,
        'createdAt': FieldValue.serverTimestamp(),
        'ocrError': FieldValue.delete(),
        'najimReport': {
          'pdfPath': pdfPath,
          'pdfUrl': pdfUrl,
          'accidentDate': '',
          'accidentNumber': '',
          'damageLocation': '',
        },
      }, SetOptions(merge: true));

      // keep case id for later final submission
      _caseId = caseId;

      // 4) Trigger OCR using caseId
      const backendUrl = 'http://192.168.0.250:8000';
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
      await _loadExtractedNajmDetails(caseId);
      if (!mounted) return;

      if (result == 'approved') {
        setState(() => _isRunningOcr = false);
        _verifiedVehicleId = selectedVehicle!.docId;

        await _showOcrSuccessDialog();
        if (!mounted) return;

        await _goToDamageCapture();
      } else {
        await caseRef.update({
          'status': 'ocr_failed',
          'ocrError': 'OCR validation failed',
        });

        setState(() => _isRunningOcr = false);
        _showOcrFailedDialog();
      }
    } catch (e) {
      print('❌ OCR error: $e');

      if (_caseId != null && _caseId!.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('accidentCase')
              .doc(_caseId!)
              .update({
                'status': 'ocr_failed',
                'ocrError': 'Connection to OCR server failed: $e',
              });
        } catch (updateError) {
          print(
            '⚠️ Failed to update case after OCR connection error: $updateError',
          );
        }
      }

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
      _submitStatus = 'جاري رفع الصور...';
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

      setState(() => _submitStatus = 'جاري حفظ الطلب...');

      await caseRef.update({
        'ownerId': _userDocId!,
        'vehicleId': selectedVehicle!.docId,
        'isSubmitted': true,
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
        _caseId = null;
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
    return Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
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
                      'طلب تقدير',
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
                                          'ارسال باسم',
                                          style: TextStyle(
                                            fontSize: 20,
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 15),
                                        ReadOnlyInfoField(
                                          label: 'الاسم',
                                          value: _userName,
                                          icon: Icons.person_outline,
                                        ),
                                        const SizedBox(height: 14),
                                        ReadOnlyInfoField(
                                          label: 'الهوية/ الاقامة',
                                          value: _nationalID,
                                          icon: Icons.badge_outlined,
                                        ),
                                        const SizedBox(height: 14),
                                        ReadOnlyInfoField(
                                          label: 'رقم الجوال',
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
                              const Text('اختر المركبة'),
                              const SizedBox(height: 8),
                              if (_userDocId == null || _userDocId!.isEmpty)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else
                                StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('vehicles')
                                      .where('ownerId', isEqualTo: _userDocId!)
                                      .where('isArchived', isEqualTo: false)
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(12),
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                    }

                                    if (snapshot.hasError) {
                                      return Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        child: const Text(
                                          'تعذر تحميل المركبات',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      );
                                    }

                                    final docs = snapshot.data?.docs ?? [];

                                    final vehicles = docs.map((doc) {
                                      final data =
                                          doc.data() as Map<String, dynamic>;
                                      final make = data['make'] ?? '';
                                      final model = data['model'] ?? '';
                                      final plate = data['plateNumber'] ?? '';

                                      return VehicleItem(
                                        docId: doc.id,
                                        name: '$make $model'.trim(),
                                        plate: plate,
                                      );
                                    }).toList();

                                    // keep selected vehicle valid if the list changes
                                    if (selectedVehicle != null &&
                                        !vehicles.any(
                                          (v) =>
                                              v.docId == selectedVehicle!.docId,
                                        )) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (mounted) {
                                              setState(() {
                                                selectedVehicle = null;
                                              });
                                            }
                                          });
                                    }

                                    if (vehicles.isEmpty) {
                                      return Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        child: const Text(
                                          'لا توجد مركبات، يرجى إضافة مركبة أولاً',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      );
                                    }

                                    final currentSelected =
                                        selectedVehicle != null &&
                                            vehicles.any(
                                              (v) =>
                                                  v.docId ==
                                                  selectedVehicle!.docId,
                                            )
                                        ? vehicles.firstWhere(
                                            (v) =>
                                                v.docId ==
                                                selectedVehicle!.docId,
                                          )
                                        : null;

                                    return DropdownButtonFormField<VehicleItem>(
                                      value: currentSelected,
                                      isExpanded: true,
                                      onChanged:
                                          (_currentStep > 1 || _isSubmitting)
                                          ? null
                                          : (value) => setState(() {
                                              selectedVehicle = value;

                                              _verifiedVehicleId = null;
                                              _extractedAccidentNumber = '';
                                              _extractedAccidentDate = '';
                                              _extractedDamageLocation = '';
                                              _showExtractedNajmDetails = false;
                                            }),
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
                                      hint: const Text('اختيار'),
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down,
                                      ),
                                      items: vehicles.map((v) {
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
                                    );
                                  },
                                ),
                              // ── Najm report ──────────────────────
                              const SizedBox(height: 40),
                              const Text('رفع تقرير نجم'),
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
                                            'رفع ملف',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'الصيغة المدعومة: PDF',
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
                                              'تم الرفع',
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

                                                    _extractedAccidentNumber =
                                                        '';
                                                    _extractedAccidentDate = '';
                                                    _extractedDamageLocation =
                                                        '';
                                                    _showExtractedNajmDetails =
                                                        false;
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
                              if (_showExtractedNajmDetails) ...[
                                const SizedBox(height: 20),
                                const Text(
                                  'البيانات المستخرجة',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                NajmInfoRow(
                                  label: 'رقم الحادث',
                                  value: _extractedAccidentNumber,
                                  icon: Icons.confirmation_number_outlined,
                                ),
                                const SizedBox(height: 10),

                                NajmInfoRow(
                                  label: 'تاريخ الحادث',
                                  value: _extractedAccidentDate,
                                  icon: Icons.calendar_today_outlined,
                                ),
                                const SizedBox(height: 10),

                                NajmInfoRow(
                                  label: 'موقع الضرر',
                                  value: _extractedDamageLocation,
                                  icon: Icons.car_repair_outlined,
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
                                      'التالي',
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
                                const Text('التقاط صور الأضرار'),
                                const Text(
                                  'الحد الأقصى 10 صور',
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
                                        'التقاط الصور',
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
                                            'أقر بأن جميع المعلومات المدخلة صحيحة.',
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
                            'ارسال الطلب',
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
                        'جاري التحقق من تقرير نجم...',
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

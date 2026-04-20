import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../home/home_screen.dart';
import '../../services/ocr_service.dart';

class VerifyDetailsScreen extends StatefulWidget {
  // Receives the cropped image path from PreviewPhotoScreen
  final String? imagePath;

  const VerifyDetailsScreen({super.key, this.imagePath});

  @override
  State<VerifyDetailsScreen> createState() => _VerifyDetailsScreenState();
}

class _VerifyDetailsScreenState extends State<VerifyDetailsScreen> {
  // Text controllers — auto-filled by OCR, editable by the user
  final _plateController   = TextEditingController();
  final _makeController    = TextEditingController();
  final _modelController   = TextEditingController();
  final _yearController    = TextEditingController();
  final _colorController   = TextEditingController();
  final _chassisController = TextEditingController();

  // Tracks validation error messages per field
  final Map<String, String?> _fieldErrors = {
    'plateNumber':   null,
    'make':          null,
    'model':         null,
    'year':          null,
    'color':         null,
    'chassisNumber': null,
  };

  bool _isLoading = true;  // true while OCR API call is in progress
  bool _isSaving  = false; // true while saving to Firestore
  String? _errorMsg;       // shown if OCR fails, prompts manual entry

  @override
  void initState() {
    super.initState();
    // Start OCR as soon as the screen opens
    _loadOcrData();
  }

  // ── Calls the OCR API and fills in the form fields automatically ──
  Future<void> _loadOcrData() async {
    if (widget.imagePath == null) {
      print('OCR: imagePath is null');
      setState(() => _isLoading = false);
      return;
    }

    print('OCR: starting scan for path: ${widget.imagePath}');

    try {
      final data = await OcrService.scanCard(widget.imagePath!);
      print('OCR: response received: $data');

      if (mounted) {
        setState(() {
          _plateController.text   = data['plateNumber']   ?? '';
          _makeController.text    = data['make']          ?? '';
          _modelController.text   = data['model']         ?? '';
          _yearController.text    = data['year']          ?? '';
          _colorController.text   = data['color']         ?? '';
          _chassisController.text = data['chassisNumber'] ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('OCR: failed with error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = 'Could not read card automatically. Please fill manually.';
        });
      }
    }
  }

  // ── Validate all fields before saving ──
  bool _validateFields() {
    final errors = <String, String?>{};

    // Plate Number — must contain letters and numbers
    final plate = _plateController.text.trim();
    if (plate.isEmpty) {
      errors['plateNumber'] = 'Plate number is required';
    } else if (!RegExp(r'[A-Za-z\u0600-\u06FF]').hasMatch(plate) ||
               !RegExp(r'[0-9]').hasMatch(plate)) {
      errors['plateNumber'] = 'Plate number must contain both letters and numbers';
    } else {
      errors['plateNumber'] = null;
    }

    // Make — required
    final make = _makeController.text.trim();
    errors['make'] = make.isEmpty ? 'Make is required' : null;

    // Model — required
    final model = _modelController.text.trim();
    errors['model'] = model.isEmpty ? 'Model is required' : null;

    // Year — required, between 1900 and 2027
    final yearStr = _yearController.text.trim();
    if (yearStr.isEmpty) {
      errors['year'] = 'Year is required';
    } else {
      final year = int.tryParse(yearStr);
      if (year == null) {
        errors['year'] = 'Year must be a number';
      } else if (year < 1900 || year > 2027) {
        errors['year'] = 'Year must be between 1900 and 2027';
      } else {
        errors['year'] = null;
      }
    }

    // Color — required
    final color = _colorController.text.trim();
    errors['color'] = color.isEmpty ? 'Color is required' : null;

    // Chassis Number — required, exactly 17 alphanumeric characters
    final chassis = _chassisController.text.trim();
    if (chassis.isEmpty) {
      errors['chassisNumber'] = 'Chassis number is required';
    } else if (!RegExp(r'^[A-Za-z0-9]{17}$').hasMatch(chassis)) {
      errors['chassisNumber'] = 'Chassis number must be exactly 17 letters and numbers';
    } else {
      errors['chassisNumber'] = null;
    }

    setState(() => _fieldErrors
      ..clear()
      ..addAll(errors));

    return errors.values.every((e) => e == null);
  }

  // ── Saves the verified vehicle data to Firestore ──
  Future<void> _saveToFirebase() async {
    // Validate first — show errors if any field is invalid
    if (!_validateFields()) return;

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      // ✅ نجيب الـ UID القديم من Firestore بالرقم
      final phone = user.phoneNumber;
      String ownerId = user.uid;

      if (phone != null) {
        final query = await FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', isEqualTo: phone)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          ownerId = query.docs.first.id;
        }
      }

      await FirebaseFirestore.instance.collection('vehicles').add({
        'ownerId':       ownerId,
        'plateNumber':   _plateController.text.trim(),
        'make':          _makeController.text.trim(),
        'model':         _modelController.text.trim(),
        'year':          _yearController.text.trim(),
        'color':         _colorController.text.trim(),
        'chassisNumber': _chassisController.text.trim(),
        'isArchived':    false,
        'createdAt':     FieldValue.serverTimestamp(),
        'updatedAt':     FieldValue.serverTimestamp(),
      });

      if (mounted) _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Shows a success dialog then navigates back to HomeScreen ──
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Green check icon
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF22C55E),
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 20),
              const Text(
                'Your vehicle has been successfully added to your account',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF333333),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // close dialog
                    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A6E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Ok',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Always dispose controllers to avoid memory leaks
    _plateController.dispose();
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _colorController.dispose();
    _chassisController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            // Show loading spinner while OCR is running
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF1E3A6E)),
                    SizedBox(height: 16),
                    Text(
                      'Reading your card...',
                      style: TextStyle(color: Color(0xFF888888), fontSize: 15),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  const SizedBox(height: 12),

                  // Title
                  const Text(
                    'Verify Details',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Subtitle
                  const Text(
                    'Verify or edit details if needed.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF2563EB)),
                  ),

                  // Warning banner shown if OCR failed
                  if (_errorMsg != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3CD),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFFE082)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFF59E0B),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMsg!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF7A5000),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Scrollable form with all vehicle fields
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildField('Plate Number',   _plateController, fieldKey: 'plateNumber'),
                          _buildField('Make',           _makeController,  fieldKey: 'make'),
                          _buildField('Model',          _modelController, fieldKey: 'model'),
                          _buildField('Year',           _yearController,  fieldKey: 'year',
                              keyboardType: TextInputType.number),
                          _buildField('Color',          _colorController, fieldKey: 'color'),
                          _buildField('Chassis Number', _chassisController, fieldKey: 'chassisNumber'),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),

                  // Add Vehicle button — disabled while saving
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveToFirebase,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A6E),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        // Show spinner inside button while saving
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                '+ Add Vehicle',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Reusable labeled text field widget ──
  Widget _buildField(
    String label,
    TextEditingController controller, {
    required String fieldKey,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final errorText = _fieldErrors[fieldKey];
    final hasError  = errorText != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Field label
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: hasError ? Colors.red : const Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 6),
          // Input field
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            // Clear error when user starts typing
            onChanged: (_) {
              if (_fieldErrors[fieldKey] != null) {
                setState(() => _fieldErrors[fieldKey] = null);
              }
            },
            style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A2E)),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: hasError ? Colors.red : const Color(0xFF2563EB),
                  width: hasError ? 1.8 : 1.2,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: hasError ? Colors.red : const Color(0xFF1E3A6E),
                  width: 1.8,
                ),
              ),
              filled: true,
              fillColor: hasError ? const Color(0xFFFFF5F5) : Colors.white,
              // Error message below the field
              errorText: errorText,
              errorStyle: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../home/home_screen.dart';
import '../../services/ocr_service.dart';
import 'package:flutter/services.dart';

class VerifyDetailsScreen extends StatefulWidget {
  // Receives the cropped image path from PreviewPhotoScreen
  final String? imagePath;

  const VerifyDetailsScreen({super.key, this.imagePath});

  @override
  State<VerifyDetailsScreen> createState() => _VerifyDetailsScreenState();
}

class _VerifyDetailsScreenState extends State<VerifyDetailsScreen> {
  // Text controllers — auto-filled by OCR, editable by the user
  final _plateController = TextEditingController();
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _colorController = TextEditingController();
  final _chassisController = TextEditingController();

  // Form key drives validation state (mirrors add_vehicle_screen.dart)
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true; // true while OCR API call is in progress
  bool _isSaving = false; // true while saving to Firestore
  String? _errorMsg; // shown if OCR fails, prompts manual entry

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
          _plateController.text = data['plateNumber'] ?? '';
          _makeController.text = data['make'] ?? '';
          _modelController.text = data['model'] ?? '';
          _yearController.text = data['year'] ?? '';
          _colorController.text = data['color'] ?? '';
          _chassisController.text = data['chassisNumber'] ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('OCR: failed with error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg =
              'تعذر قراءة البطاقة تلقائيًا. يرجى تعبئة البيانات يدويًا ';
        });
      }
    }
  }

  // Converts English numbers (0-9) to Arabic numbers (٠-٩)
  String _convertToArabicNumbers(String input) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

    for (int i = 0; i < 10; i++) {
      input = input.replaceAll(english[i], arabic[i]);
    }

    return input;
  }

  // ── Format plate number to standard format: "1234 A B C" ──
  String _formatPlateNumber(String raw) {
    // Convert any English digits to Arabic first
    final converted = _convertToArabicNumbers(raw);
    final cleaned = converted.replaceAll(' ', '').toUpperCase();

    final digits = cleaned.replaceAll(RegExp(r'[^0-9٠-٩۰-۹]'), '');
    final letters = cleaned.replaceAll(
      RegExp(r'[^ء-ي]'),
      '',
    ); // Basic validation
    if (digits.isEmpty ||
        digits.length > 4 ||
        letters.isEmpty ||
        letters.length > 3) {
      return converted;
    }
    // Add space between each letter
    final spacedLetters = letters.split('').join(' ');

    return '$digits $spacedLetters';
  }

  // ── Per-field validators, same rules/messages as before, now in the
  //    shape TextFormField.validator expects: String? Function(String?) ──
  String? _validatePlateNumber(String? value) {
    final plate = (value ?? '').trim();
    if (plate.isEmpty) return 'يرجى إدخال رقم اللوحة';
    final cleaned = _convertToArabicNumbers(
      plate,
    ).replaceAll(' ', '').toUpperCase();
    final digits = cleaned.replaceAll(RegExp(r'[^0-9٠-٩۰-۹]'), '');
    final letters = cleaned.replaceAll(RegExp(r'[^ء-ي]'), '');
    if (digits.isEmpty ||
        digits.length > 4 ||
        letters.isEmpty ||
        letters.length > 3) {
      return 'رقم اللوحة يجب أن يحتوي على 1-4 أرقام و 1-3 أحرف';
    }
    return null;
  }

  String? _validateMake(String? value) {
    return (value ?? '').trim().isEmpty ? 'يرجى إدخال ماركة المركبة' : null;
  }

  String? _validateModel(String? value) {
    return (value ?? '').trim().isEmpty ? 'يرجى إدخال طراز المركبة' : null;
  }

  String? _validateYear(String? value) {
    // Required, between 1900 and next year
    final yearStr = (value ?? '').trim();
    if (yearStr.isEmpty) return 'يرجى إدخال السنة';
    if (!RegExp(r'^\d+$').hasMatch(yearStr)) {
      return 'سنة الصنع يجب أن تحتوي على أرقام فقط';
    }
    final year = int.tryParse(yearStr);
    final currentYear = DateTime.now().year;
    final maxYear = currentYear + 1;
    if (year == null) return 'سنة الصنع غير صحيحة';
    if (year < 1900 || year > maxYear) {
      return 'سنة الصنع يجب أن تكون بين 1900 و $maxYear';
    }
    return null;
  }

  String? _validateColor(String? value) {
    return (value ?? '').trim().isEmpty ? 'يرجى إدخال لون المركبة' : null;
  }

  String? _validateChassisNumber(String? value) {
    // Required, exactly 17 alphanumeric characters
    final chassis = (value ?? '').trim();
    if (chassis.isEmpty) return 'يرجى إدخال رقم الهيكل';
    if (!RegExp(r'^[A-Za-z0-9]{17}$').hasMatch(chassis)) {
      return 'رقم الهيكل يجب أن يتكون من 17 حرفًا أو رقمًا';
    }
    return null;
  }

  // ── Saves the verified vehicle data to Firestore ──
  Future<void> _saveToFirebase() async {
    // Validate first — show errors if any field is invalid
    if (!_formKey.currentState!.validate()) return;

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

      // Format plate before saving to ensure consistent format in DB
      final formattedPlate = _formatPlateNumber(_plateController.text.trim());

      await FirebaseFirestore.instance.collection('vehicles').add({
        'ownerId': ownerId,
        'plateNumber': formattedPlate,
        'make': _makeController.text.trim(),
        'model': _modelController.text.trim(),
        'year': _yearController.text.trim(),
        'color': _colorController.text.trim(),
        'chassisNumber': _chassisController.text.trim().toUpperCase(),
        'isArchived': false,
        'createdAt': FieldValue.serverTimestamp(),
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
    final size = MediaQuery.of(context).size;
    final double screenWidth = size.width;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenWidth > 600 ? 400 : screenWidth * 0.85,
          ),
          child: Padding(
            padding: EdgeInsets.all(screenWidth * 0.06),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: screenWidth * 0.15,
                  height: screenWidth * 0.15,
                  constraints: const BoxConstraints(
                    minWidth: 56,
                    minHeight: 56,
                    maxWidth: 68,
                    maxHeight: 68,
                  ),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 34),
                ),

                SizedBox(height: screenWidth * 0.05),

                Text(
                  'تمت إضافة المركبة بنجاح',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: screenWidth * 0.04,
                    color: const Color(0xFF071A3D),
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                SizedBox(height: screenWidth * 0.06),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/home', (route) => false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A6E),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: screenWidth * 0.035,
                      ),
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'حسنًا',
                      style: TextStyle(
                        fontSize: screenWidth * 0.04,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
    return Directionality(
      // Force RTL layout for Arabic
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
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
                        ' يقوم النظام بقراءة الصورة الخاصة بك.\nعادةً ما يستغرق ذلك بضع ثوانٍ...', // Loading state
                        style: TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    const SizedBox(height: 12),

                    // Title
                    const Text(
                      'تأكيد البيانات',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Subtitle
                    const Text(
                      'تأكد من البيانات أو عدّلها عند الحاجة',
                      style: TextStyle(fontSize: 15, color: Color(0xFF2563EB)),
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
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFFE082)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFF9A825),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMsg!,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Color(0xFF7A6000),
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
                        child: Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildField(
                                'رقم اللوحة',
                                _plateController,
                                validator: _validatePlateNumber,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[ء-ي0-9٠-٩۰-۹\s]'),
                                  ),
                                ],
                              ),
                              _buildField(
                                'ماركة المركبة',
                                _makeController,
                                validator: _validateMake,
                              ),
                              _buildField(
                                'طراز المركبة',
                                _modelController,
                                validator: _validateModel,
                              ),
                              _buildField(
                                'السنه',
                                _yearController,
                                validator: _validateYear,
                                keyboardType: TextInputType.number,
                              ),
                              _buildField(
                                'اللون',
                                _colorController,
                                validator: _validateColor,
                              ),
                              _buildField(
                                'رقم الهيكل',
                                _chassisController,
                                validator: _validateChassisNumber,
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
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
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 0,
                          ),

                          // Loading spinner
                          child: _isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '+ إضافة مركبة',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
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

  // ── Reusable labeled text field widget ──
  Widget _buildField(
    String label,
    TextEditingController controller, {
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Field label
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 6),
          // Input field
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            validator: validator,
            // Live Arabic-digit conversion. Error display/timing is now
            // owned by Form (autovalidateMode.onUserInteraction).
            onChanged: (val) {
              final converted = _convertToArabicNumbers(val);
              // If user typed English numbers → convert to Arabic instantly
              if (val != converted) {
                controller.value = TextEditingValue(
                  text: converted,
                  selection: TextSelection.collapsed(offset: converted.length),
                );
              }
            },
            style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A2E)),
            decoration: InputDecoration(
              errorMaxLines: 3,

              hintText: hint,

              // Inner padding for the input field
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),

              // Default border
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),

              // Normal state border
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300, width: 1.4),
              ),

              // Focused state (darker blue or red if error)
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Color(0xFF2563EB), width: 1.8),
              ),

              // Border when validation error exists (no focus)
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.red, width: 1.6),
              ),

              // Border when focused + error
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.red, width: 1.8),
              ),

              // Fill background
              filled: true,
              fillColor: Colors.white,

              errorStyle: const TextStyle(fontSize: 11, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

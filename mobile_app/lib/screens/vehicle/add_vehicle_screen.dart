import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _arabicPlateController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _makeController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _chassisController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _arabicPlateController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _makeController.dispose();
    _yearController.dispose();
    _chassisController.dispose();
    super.dispose();
  }

  Future<void> _addVehicle() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
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
        'plateNumber': _normalizeArabicPlateNumber(_arabicPlateController.text),
        'arabicPlateNumber': _normalizeArabicPlateNumber(
          _arabicPlateController.text,
        ),
        'model': _modelController.text.trim(),
        'color': _colorController.text.trim(),
        'make': _makeController.text.trim(),
        'year': _yearController.text.trim(),
        'chassisNumber': _chassisController.text.trim(),
        'ownerId': ownerId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isArchived': false,
      });

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => const _SuccessDialog(
          message: 'تمت إضافة المركبة بنجاح',
        ),
      );

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add vehicle: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _fieldDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDDE7F3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 1.4),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    String? hintText,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF071A3D),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          textDirection: textDirection,
          decoration: _fieldDecoration().copyWith(
            hintText: hintText,
          ),
        ),
      ],
    );
  }

  String _normalizePlateNumber(String input) {
    final value = input.trim().toUpperCase().replaceAll(' ', '');

    final lettersOnly = value.replaceAll(RegExp(r'[^A-Z]'), '');
    final numbersOnly = value.replaceAll(RegExp(r'[^0-9]'), '');

    return '${numbersOnly} ${lettersOnly}'.trim();
  }

  String _normalizeArabicPlateNumber(String input) {
    final value = input.trim().replaceAll(' ', '');

    final lettersOnly = value.replaceAll(RegExp(r'[^ء-ي]'), '');
    final numbersOnly = value.replaceAll(RegExp(r'[^0-9٠-٩]'), '');

    return '${numbersOnly} ${lettersOnly}'.trim();
  }

  String? _validatePlateNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'هذا الحقل مطلوب';
    }

    final input = value.trim().toUpperCase().replaceAll(' ', '');

    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(input)) {
      return 'Use English letters and digits only';
    }

    final letters = input.replaceAll(RegExp(r'[^A-Z]'), '');
    final numbers = input.replaceAll(RegExp(r'[^0-9]'), '');

    if (letters.isEmpty || numbers.isEmpty) {
      return 'لازم تحتوي اللوحة على حروف وأرقام';
    }

    if (letters.length > 3) {
      return 'الحد الأقصى 3 حروف';
    }

    if (numbers.length > 4) {
      return 'الحد الأقصى 4 أرقام';
    }

    return null;
  }

  String? _validateArabicPlateNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'هذا الحقل مطلوب';
    }

    final input = value.trim().replaceAll(' ', '');

    if (!RegExp(r'^[ء-ي0-9٠-٩]+$').hasMatch(input)) {
      return 'استخدم حروف عربية وأرقام فقط';
    }

    final letters = input.replaceAll(RegExp(r'[^ء-ي]'), '');
    final numbers = input.replaceAll(RegExp(r'[^0-9٠-٩]'), '');

    if (letters.isEmpty || numbers.isEmpty) {
      return 'لازم تحتوي اللوحة على حروف وأرقام';
    }

    if (letters.length > 3) {
      return 'الحد الأقصى 3 حروف';
    }

    if (numbers.length > 4) {
      return 'الحد الأقصى 4 أرقام';
    }

    return null;
  }

  String? _validateYear(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'هذا الحقل مطلوب';
    }

    final input = value.trim();

    if (!RegExp(r'^\d+$').hasMatch(input)) {
      return 'السنة يجب أن تحتوي على أرقام فقط';
    }

    final year = int.tryParse(input);
    final currentYear = DateTime.now().year;
    final maxYear = currentYear + 1;

    if (year == null) {
      return 'السنة غير صحيحة';
    }

    if (year < 1900 || year > maxYear) {
      return 'السنة يجب أن تكون بين 1900 و $maxYear';
    }

    return null;
  }

  String? _validateChassisNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'هذا الحقل مطلوب';
    }

    final input = value.trim().toUpperCase();

    if (input.length != 17) {
      return 'رقم الهيكل يجب أن يكون 17 خانة بالضبط';
    }

    if (!RegExp(r'^[A-Z0-9]{17}$').hasMatch(input)) {
      return 'استخدم حروف إنجليزية وأرقام فقط';
    }

    return null;
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'هذا الحقل مطلوب';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF2563EB);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: const Color(0xFFF7FAFF),
          centerTitle: true,
          surfaceTintColor: const Color(0xFFF7FAFF),
          title: const Text(
            'إضافة مركبة',
            style: TextStyle(
              color: Color(0xFF071A3D),
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          iconTheme: const IconThemeData(color: Color(0xFF071A3D)),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: ListView(
                children: [
                  
                  _buildField(
                    label: 'رقم اللوحة بالعربي',
                    controller: _arabicPlateController,
                    validator: _validateArabicPlateNumber,
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 14),
                  _buildField(
                    label: 'الشركة',
                    controller: _makeController,
                    validator: _validateRequired,
                  ),
                  const SizedBox(height: 14),
                  _buildField(
                    label: 'الطراز',
                    controller: _modelController,
                    validator: _validateRequired,
                  ),
                  const SizedBox(height: 14),
                  _buildField(
                    label: 'السنة',
                    controller: _yearController,
                    keyboardType: TextInputType.number,
                    validator: _validateYear,
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 14),
                  _buildField(
                    label: 'اللون',
                    controller: _colorController,
                    validator: _validateRequired,
                  ),
                  const SizedBox(height: 14),
                  _buildField(
                    label: 'رقم الهيكل',
                    controller: _chassisController,
                    validator: _validateChassisNumber,
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _addVehicle,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: primaryBlue.withOpacity(0.7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'إضافة المركبة',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
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
}

class _SuccessDialog extends StatelessWidget {
  final String message;

  const _SuccessDialog({required this.message});

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF2563EB);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFDDE7F3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 26,
              backgroundColor: Color(0xFF0B8F2F),
              child: Icon(Icons.check, color: Colors.white, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF071A3D),
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 114,
              height: 40,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                child: const Text(
                  'حسنًا',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

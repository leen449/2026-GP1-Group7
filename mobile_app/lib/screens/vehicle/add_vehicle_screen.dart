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

  final TextEditingController _plateController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _makeController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _chassisController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _plateController.dispose();
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
'plateNumber': _normalizePlateNumber(_plateController.text),
      'model': _modelController.text.trim(),
      'color': _colorController.text.trim(),
      'make': _makeController.text.trim(),
      'year': _yearController.text.trim(),
      'chassisNumber': _chassisController.text.trim(),
      'ownerId': ownerId, // ✅
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isArchived': false,
    });

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => const _SuccessDialog(
        message: 'Your vehicle has been successfully added to your account',
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
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF8AA3B8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF8AA3B8), width: 1.2),
      ),
    );
  }

  Widget _buildField({
  required String label,
  required TextEditingController controller,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
  String? hintText,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.black87,
          fontWeight: FontWeight.w400,
        ),
      ),
      const SizedBox(height: 6),
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
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
String? _validatePlateNumber(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }

  final input = value.trim().toUpperCase().replaceAll(' ', '');

  if (!RegExp(r'^[A-Z0-9]+$').hasMatch(input)) {
    return 'Use English letters and digits only';
  }

  final letters = input.replaceAll(RegExp(r'[^A-Z]'), '');
  final numbers = input.replaceAll(RegExp(r'[^0-9]'), '');

  if (letters.isEmpty || numbers.isEmpty) {
    return 'Plate must contain letters and numbers';
  }

  if (letters.length > 3) {
    return 'Maximum 3 letters';
  }

  if (numbers.length > 4) {
    return 'Maximum 4 digits';
  }

  return null;
}

String? _validateYear(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }

  final input = value.trim();

  if (!RegExp(r'^\d+$').hasMatch(input)) {
    return 'Year must contain numbers only';
  }

  final year = int.tryParse(input);
  final currentYear = DateTime.now().year;

  if (year == null) {
    return 'Invalid year';
  }

  if (year < 1900 || year > currentYear) {
    return 'Year must be between 1900 and $currentYear';
  }

  return null;
}

String? _validateChassisNumber(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }

  final input = value.trim().toUpperCase();

  if (input.length != 17) {
    return 'Chassis number must be exactly 17 characters';
  }

  // اختياري: السماح فقط بحروف إنجليزية وأرقام
  if (!RegExp(r'^[A-Z0-9]{17}$').hasMatch(input)) {
    return 'Use English letters and numbers only';
  }

  return null;
}

String? _validateRequired(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }
  return null;
}

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D4D8B);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Add Vehicle',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            child: ListView(
       children: [
  _buildField(
    label: 'Plate Number',
    controller: _plateController,
    validator: _validatePlateNumber,
      hintText: 'Example: 6987 GTJ',

  ),
  const SizedBox(height: 14),

  _buildField(
    label: 'Make',
    controller: _makeController,
    validator: _validateRequired,
  ),
  const SizedBox(height: 14),

  _buildField(
    label: 'Model',
    controller: _modelController,
    validator: _validateRequired,
  ),
  const SizedBox(height: 14),

  _buildField(
    label: 'Year',
    controller: _yearController,
    keyboardType: TextInputType.number,
    validator: _validateYear,
  ),
  const SizedBox(height: 14),

  _buildField(
    label: 'Color',
    controller: _colorController,
    validator: _validateRequired,
  ),
  const SizedBox(height: 14),

  _buildField(
    label: 'Chassis Number',
    controller: _chassisController,
    validator: _validateChassisNumber,
  ),
  const SizedBox(height: 28),

  SizedBox(
    height: 44,
    child: ElevatedButton(
      onPressed: _isLoading ? null : _addVehicle,
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: primaryBlue.withOpacity(0.7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
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
              '+ Add Vehicle',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
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
}

class _SuccessDialog extends StatelessWidget {
  final String message;

  const _SuccessDialog({required this.message});

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0D4D8B);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFB9C3CF)),
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
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
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
                  'Ok',
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
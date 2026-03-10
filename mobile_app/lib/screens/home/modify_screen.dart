import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ModifyScreen extends StatefulWidget {
  const ModifyScreen({super.key});

  @override
  State<ModifyScreen> createState() => _ModifyScreenState();
}

class _ModifyScreenState extends State<ModifyScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nationalIdController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  static const Color _pageBg = Color(0xFFF6F6F6);
  static const Color _textDark = Color(0xFF1E1E1E);
  static const Color _primaryBlue = Color(0xFF0B3B66);
  static const Color _cardGrey = Color(0xFFFFFFFF);

  bool _isLoading = false;
  bool _nationalIdLocked = false;

  String? _nameError;
  String? _nationalIdError;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nationalIdController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists || !mounted) return;

    final data = doc.data()!;
    setState(() {
      _nameController.text = data['name'] ?? '';
      _nationalIdController.text = data['nationalID'] ?? '';
      // نزيل +966 من الرقم عشان يظهر بدونها
      final phone = data['phoneNumber'] ?? '';
      _phoneController.text = phone.replaceFirst('+966', '');
      _nationalIdLocked = data['nationalIDLocked'] ?? false;
    });
  }

  // ── Validation ──
  String? _validateName(String val) {
    if (val.trim().isEmpty) return 'Please enter your name';
    if (val.trim().length < 2) return 'Name must be at least 2 characters';
    return null;
  }

  String? _validateNationalId(String val) {
    if (val.trim().isEmpty) return 'Please enter your National/Residence ID';
    if (val.length != 10) return 'ID must be exactly 10 digits';
    if (!RegExp(r'^[0-9]+$').hasMatch(val)) return 'ID must contain digits only';
    if (!val.startsWith('1') && !val.startsWith('2')) {
      return 'ID must start with 1 (Saudi) or 2 (Resident)';
    }
    return null;
  }

  String? _validatePhone(String val) {
    if (val.trim().isEmpty) return 'Please enter your phone number';
    if (!RegExp(r'^[0-9]+$').hasMatch(val)) return 'Phone must contain digits only';
    if (val.length != 9) return 'Phone number must be 9 digits';
    if (!val.startsWith('5')) return 'Phone number must start with 5';
    return null;
  }

  bool _validate() {
    final nameErr = _validateName(_nameController.text);
    final idErr = _nationalIdLocked ? null : _validateNationalId(_nationalIdController.text);
    final phoneErr = _validatePhone(_phoneController.text);

    setState(() {
      _nameError = nameErr;
      _nationalIdError = idErr;
      _phoneError = phoneErr;
    });

    return nameErr == null && idErr == null && phoneErr == null;
  }

  Future<void> _saveChanges() async {
    if (!_validate()) return;

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final phone = '+966${_phoneController.text.trim()}';

      // تحقق إن الرقم الجديد مو مسجل عند حساب ثاني
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: phone)
          .get();

      final isOwnNumber = query.docs.length == 1 && query.docs.first.id == uid;
      final isNewNumber = query.docs.isEmpty;

      if (!isOwnNumber && !isNewNumber) {
        setState(() {
          _isLoading = false;
          _phoneError = 'This phone number is already used by another account';
        });
        return;
      }

      final Map<String, dynamic> updates = {
        'name': _nameController.text.trim(),
        'phoneNumber': phone,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!_nationalIdLocked) {
        updates['nationalID'] = _nationalIdController.text.trim();
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).update(updates);

      if (!mounted) return;
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Changes saved successfully ✅'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An error occurred. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Personal Information',
          style: TextStyle(
            color: _textDark,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // صورة البروفايل
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.shade200,
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/icons/profile.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _nameController.text,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _textDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // الفورم
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _cardGrey,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('Full Name'),
                    _inputField(
                      controller: _nameController,
                      hint: 'Name',
                      errorText: _nameError,
                    ),
                    const SizedBox(height: 18),

                    _fieldLabel('National / Residence ID'),
                    _inputField(
                      controller: _nationalIdController,
                      hint: 'ID',
                      keyboardType: TextInputType.number,
                      errorText: _nationalIdError,
                      maxLength: 10,
                      enabled: !_nationalIdLocked,
                    ),
                    if (_nationalIdLocked)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(
                              'Cannot be changed after submitting a case',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),

                    _fieldLabel('Phone Number'),
                    _inputField(
                      controller: _phoneController,
                      hint: 'Your Phone Number',
                      keyboardType: TextInputType.phone,
                      errorText: _phoneError,
                      maxLength: 9,
                      prefix: '+966 ',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // زر الحفظ
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
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

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _textDark,
        ),
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    String? errorText,
    int? maxLength,
    bool enabled = true,
    String? prefix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLength: maxLength,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            filled: true,
            fillColor: enabled ? const Color(0xFFF6F6F6) : Colors.grey.shade100,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: errorText != null
                  ? const BorderSide(color: Colors.red, width: 1.5)
                  : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF0B3B66), width: 1.5),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (_) {
            setState(() {
              _nameError = null;
              _nationalIdError = null;
              _phoneError = null;
            });
          },
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 4),
            child: Text(
              errorText,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
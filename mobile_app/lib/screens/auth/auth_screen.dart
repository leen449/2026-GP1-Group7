import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import './verification_screen.dart';
import '../NavBar/nav_bar.dart';
import './change_phone_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;

  final TextEditingController _loginPhoneController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _nationalIdController = TextEditingController();
  final TextEditingController _signupPhoneController = TextEditingController();
  DateTime? _selectedDate;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _firstNameError;
  String? _lastNameError;
  String? _nationalIdError;
  String? _phoneError;
  String? _dateError;

  @override
  void dispose() {
    _loginPhoneController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _nationalIdController.dispose();
    _signupPhoneController.dispose();
    super.dispose();
  }

  // ✅ دالة مشتركة للـ SnackBar
  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Text(msg)],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 800),
      ),
    );
  }

  String _convertToEnglishNumbers(String val) {
    return val
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9');
  }

  String? _validateFirstName(String val) {
    if (val.trim().isEmpty) return 'يرجى إدخال الاسم الأول';
    if (val.trim().length < 2)
      return 'يجب أن يكون الاسم الأول مكون من حرفين على الأقل';
    return null;
  }

  String? _validateLastName(String val) {
    if (val.trim().isEmpty) return 'يرجى إدخال اسم العائلة';
    if (val.trim().length < 2)
      return 'يجب أن يكون اسم العائلة مكون من حرفين على الأقل';
    return null;
  }

  String? _validateNationalId(String val) {
    if (val.trim().isEmpty) return 'يرجى إدخال رقم الهوية / الإقامة';
    if (val.length != 10) return 'يجب أن يكون رقم الهوية مكون من 10 أرقام';
    if (!RegExp(r'^[0-9]+$').hasMatch(val))
      return 'يجب أن يحتوي رقم الهوية على أرقام فقط';
    if (!val.startsWith('1') && !val.startsWith('2')) {
      return 'يجب أن يبدأ الرقم بـ 1 (سعودي) أو 2 (مقيم)';
    }
    return null;
  }

  String? _validatePhone(String val) {
    if (val.trim().isEmpty) return 'يرجى إدخال رقم الجوال';
    if (!RegExp(r'^[0-9]+$').hasMatch(val))
      return 'يجب أن يحتوي رقم الجوال على أرقام فقط';
    if (val.startsWith('0')) return 'يجب ألا يبدأ رقم الجوال بـ 0';
    if (val.length != 9) return 'يجب أن يكون رقم الجوال 9 أرقام';
    if (!val.startsWith('5')) return 'يجب أن يبدأ رقم الجوال بـ 5';
    return null;
  }

  String? _validateDate() {
    if (_selectedDate == null) return 'يرجى اختيار تاريخ الميلاد';
    final age = DateTime.now().difference(_selectedDate!).inDays ~/ 365;
    if (age < 18) return 'يجب أن يكون عمرك 18 سنة على الأقل';
    return null;
  }

  bool _validateSignup() {
    _nationalIdController.text = _convertToEnglishNumbers(
      _nationalIdController.text,
    );
    _signupPhoneController.text = _convertToEnglishNumbers(
      _signupPhoneController.text,
    );

    final firstErr = _validateFirstName(_firstNameController.text);
    final lastErr = _validateLastName(_lastNameController.text);
    final idErr = _validateNationalId(_nationalIdController.text);
    final phoneErr = _validatePhone(_signupPhoneController.text);
    final dateErr = _validateDate();

    setState(() {
      _firstNameError = firstErr;
      _lastNameError = lastErr;
      _nationalIdError = idErr;
      _phoneError = phoneErr;
      _dateError = dateErr;
    });

    return firstErr == null &&
        lastErr == null &&
        idErr == null &&
        phoneErr == null &&
        dateErr == null;
  }

  bool _validateLogin() {
    _loginPhoneController.text = _convertToEnglishNumbers(
      _loginPhoneController.text,
    );
    final phoneErr = _validatePhone(_loginPhoneController.text);
    setState(() => _phoneError = phoneErr);
    return phoneErr == null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF2563EB)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateError = _validateDate();
      });
    }
  }

  Future<void> _sendOTP({required bool isSignUp}) async {
    final phone = isSignUp
        ? '+966${_signupPhoneController.text.trim()}'
        : '+966${_loginPhoneController.text.trim()}';

    // ✅ تحقق من الرقم في Firestore قبل الإرسال
    if (!isSignUp) {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: phone)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        if (!mounted) return;
        _showSnackBar('لا يوجد حساب بهذا الرقم، يرجى التسجيل أولاً');
        return;
      }
    }

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,

      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await _auth.signInWithCredential(credential);
          final user = _auth.currentUser;
          if (user == null) return;

          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (isSignUp) {
            if (!userDoc.exists) await _saveUserToFirestore(phone);
          } else {
            if (!userDoc.exists) {
              await _auth.signOut();
              if (!mounted) return;
              _showSnackBar('لا يوجد حساب، يرجى التسجيل أولاً');
              return;
            }
          }

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AppBottomNav()),
          );
        } catch (e) {
          if (!mounted) return;
          _showSnackBar('فشل التحقق: $e');
        }
      },

      verificationFailed: (FirebaseAuthException e) {
        String msg = 'حدث خطأ، حاول مرة أخرى';
        if (e.code == 'invalid-phone-number') msg = 'رقم الجوال غير صحيح';
        if (e.code == 'too-many-requests')
          msg = 'تم تجاوز الحد المسموح من المحاولات. حاول لاحقًا';
        if (!mounted) return;
        _showSnackBar(msg);
      },

      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VerificationScreen(
              verificationId: verificationId,
              resendToken: resendToken,
              phone: phone,
              isSignUp: isSignUp,
              name: isSignUp
                  ? '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
                  : '',
              nationalId: isSignUp ? _nationalIdController.text.trim() : '',
              dateOfBirth: isSignUp
                  ? (_selectedDate != null
                      ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
                      : '')
                  : '',
            ),
          ),
        );
      },

      codeAutoRetrievalTimeout: (_) {},
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> _saveUserToFirestore(String phone) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'userID': user.uid,
      'name':
          '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
      'nationalID': _nationalIdController.text.trim(),
      'phoneNumber': phone,
      'dateOfBirth': _selectedDate != null
          ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
          : '',
      'nationalIDLocked': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  TextStyle _textStyle({double fontSize = 14, Color color = Colors.black}) {
    return TextStyle(fontSize: fontSize, color: color);
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: _textStyle(fontSize: 14, color: Colors.black87),
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
    bool isNationalId = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLength: maxLength,
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: errorText != null
                  ? const BorderSide(color: Colors.red, width: 1.5)
                  : const BorderSide(color: Color(0xFFDDE7F3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: errorText != null
                  ? const BorderSide(color: Colors.red, width: 1.5)
                  : const BorderSide(color: Color(0xFF2563EB), width: 1.4),
            ),
          ),
          onChanged: (val) {
            if (isNationalId) {
              setState(
                () => _nationalIdError =
                    'يجب أن يبدأ الرقم بـ 1 (سعودي) أو 2 (مقيم) ويكون مكون من 10 أرقام',
              );
              if (val.length == 10 &&
                  (val.startsWith('1') || val.startsWith('2'))) {
                setState(() => _nationalIdError = null);
              }
            } else if (keyboardType == TextInputType.phone &&
                val.isNotEmpty &&
                val[0] == '0') {
              setState(() => _phoneError = 'يجب ألا يبدأ رقم الجوال بـ 0');
            } else if (keyboardType == TextInputType.phone &&
                val.isNotEmpty &&
                val[0] != '5') {
              setState(() => _phoneError = 'يجب أن يبدأ رقم الجوال بـ 5');
            } else {
              setState(() {
                _firstNameError = null;
                _lastNameError = null;
                _nationalIdError = null;
                _phoneError = null;
              });
            }
          },
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 4),
            child: Text(
              errorText,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _dateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: _dateError != null
                  ? Border.all(color: Colors.red, width: 1.5)
                  : Border.all(color: const Color(0xFFDDE7F3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _selectedDate != null
                        ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
                        : 'يوم - شهر - سنة',
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedDate != null
                          ? Colors.black87
                          : Colors.black38,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: Color(0xFF2563EB),
                ),
              ],
            ),
          ),
        ),
        if (_dateError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 4),
            child: Text(
              _dateError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _primaryButton({required String text, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E3A6E),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          minimumSize: const Size(0, 48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            style: _textStyle(
              fontSize: 15,
              color: Colors.white,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _toggleBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEDED),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() {
                isLogin = false;
                _firstNameError = null;
                _lastNameError = null;
                _nationalIdError = null;
                _phoneError = null;
                _dateError = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isLogin ? Colors.transparent : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'إنشاء حساب',
                  style: _textStyle(
                    fontSize: 14,
                    color: isLogin ? Colors.black54 : Colors.black87,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() {
                isLogin = true;
                _firstNameError = null;
                _lastNameError = null;
                _nationalIdError = null;
                _phoneError = null;
                _dateError = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isLogin ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'تسجيل الدخول',
                  style: _textStyle(
                    fontSize: 14,
                    color: isLogin ? Colors.black87 : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('رقم الجوال'),
        _inputField(
          controller: _loginPhoneController,
          hint: '5XXXXXXXX',
          keyboardType: TextInputType.phone,
          errorText: _phoneError,
          maxLength: 9,
        ),
        const SizedBox(height: 24),
        _primaryButton(
          text: 'تسجيل دخول',
          onTap: () {
            if (_validateLogin()) _sendOTP(isSignUp: false);
          },
        ),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChangePhoneScreen()),
              );
            },
            child: const Text(
              'لا يمكنك الوصول لرقمك؟ قم بتغييره',
              style: TextStyle(
                color: Color(0xFF2563EB),
                fontSize: 16,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _signupContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('الاسم الأول'),
        _inputField(
          controller: _firstNameController,
          hint: 'الاسم الأول',
          errorText: _firstNameError,
        ),
        const SizedBox(height: 14),
        _label('اسم العائلة'),
        _inputField(
          controller: _lastNameController,
          hint: 'اسم العائلة',
          errorText: _lastNameError,
        ),
        const SizedBox(height: 14),
        _label('رقم الهوية / الإقامة'),
        _inputField(
          controller: _nationalIdController,
          hint: 'كما هو موضح في بطاقة الهوية',
          keyboardType: TextInputType.number,
          errorText: _nationalIdError,
          maxLength: 10,
          isNationalId: true,
        ),
        const SizedBox(height: 14),
        _label('تاريخ الميلاد'),
        _dateField(),
        const SizedBox(height: 14),
        _label('رقم الجوال'),
        _inputField(
          controller: _signupPhoneController,
          hint: '5XXXXXXXX',
          keyboardType: TextInputType.phone,
          errorText: _phoneError,
          maxLength: 9,
        ),
        const SizedBox(height: 40),
        _primaryButton(
          text: 'إنشاء حساب',
          onTap: () {
            if (_validateSignup()) _sendOTP(isSignUp: true);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Column(
            children: [
              const SizedBox(height: 18),
              SizedBox(
                height: 140,
                child: Center(
                  child: isLogin
                      ? Text(
                          'مرحبًا بعودتك',
                          style: _textStyle(fontSize: 34, color: Colors.black),
                        )
                      : Image.asset(
                          'assets/icons/logo.png',
                          height: 120,
                          fit: BoxFit.contain,
                        ),
                ),
              ),
              const SizedBox(height: 18),
              _toggleBar(),
              const SizedBox(height: 50),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isLogin ? _loginContent() : _signupContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
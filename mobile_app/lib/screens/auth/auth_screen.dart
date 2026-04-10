import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import './verification_screen.dart';
import '../home/home_screen.dart';
import '../NavBar/nav_bar.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;

  // Controllers (Login)
  final TextEditingController _loginPhoneController = TextEditingController();

  // Controllers (Sign up)
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nationalIdController = TextEditingController();
  final TextEditingController _signupPhoneController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;

  // Error messages
  String? _nameError;
  String? _nationalIdError;
  String? _phoneError;

  @override
  void dispose() {
    _loginPhoneController.dispose();
    _nameController.dispose();
    _nationalIdController.dispose();
    _signupPhoneController.dispose();
    super.dispose();
  }

  // ── Validation ──────────────────────────────────────────────

  String? _validateName(String val) {
    if (val.trim().isEmpty) return 'Please enter your name';
    if (val.trim().length < 2) return 'Name must be at least 2 characters';
    return null;
  }

  String? _validateNationalId(String val) {
    if (val.trim().isEmpty) return 'Please enter your National/Residence ID';
    if (val.length != 10) return 'ID must be exactly 10 digits';
    if (!RegExp(r'^[0-9]+$').hasMatch(val))
      return 'ID must contain digits only';
    if (!val.startsWith('1') && !val.startsWith('2')) {
      return 'ID must start with 1 (Saudi) or 2 (Resident)';
    }
    return null;
  }

  String? _validatePhone(String val) {
    if (val.trim().isEmpty) return 'Please enter your phone number';
    if (!RegExp(r'^[0-9]+$').hasMatch(val))
      return 'Phone must contain digits only';
    if (val.length != 9) return 'Phone number must be 9 digits';
    if (!val.startsWith('5')) return 'Phone number must start with 5';
    return null;
  }

  bool _validateSignup() {
    final nameErr = _validateName(_nameController.text);
    final idErr = _validateNationalId(_nationalIdController.text);
    final phoneErr = _validatePhone(_signupPhoneController.text);

    setState(() {
      _nameError = nameErr;
      _nationalIdError = idErr;
      _phoneError = phoneErr;
    });

    return nameErr == null && idErr == null && phoneErr == null;
  }

  bool _validateLogin() {
    final phoneErr = _validatePhone(_loginPhoneController.text);
    setState(() => _phoneError = phoneErr);
    return phoneErr == null;
  }

  // ── Firebase: إرسال OTP ──────────────────────────────────────

  Future<void> _sendOTP({required bool isSignUp}) async {
    final phone = isSignUp
        ? '+966${_signupPhoneController.text.trim()}'
        : '+966${_loginPhoneController.text.trim()}';

    setState(() => _isLoading = true);

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,

      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await _auth.signInWithCredential(credential);
          final user = _auth.currentUser;
          if (user == null) {
            setState(() => _isLoading = false);
            return;
          }

          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (isSignUp) {
            if (!userDoc.exists) {
              await _saveUserToFirestore(phone);
            }
          } else {
            if (!userDoc.exists) {
              await _auth.signOut();
              setState(() => _isLoading = false);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No account found. Please sign up first.'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
          }

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AppBottomNav()),
          );
        } catch (e) {
          setState(() => _isLoading = false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Authentication failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },

      verificationFailed: (FirebaseAuthException e) {
        setState(() => _isLoading = false);
        String msg = 'An error occurred. Please try again.';
        if (e.code == 'invalid-phone-number') msg = 'Invalid phone number.';
        if (e.code == 'too-many-requests')
          msg = 'Too many requests. Try again later.';
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      },

      codeSent: (String verificationId, int? resendToken) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VerificationScreen(
              verificationId: verificationId,
              resendToken: resendToken,
              phone: phone,
              isSignUp: isSignUp,
              name: isSignUp ? _nameController.text.trim() : '',
              nationalId: isSignUp ? _nationalIdController.text.trim() : '',
            ),
          ),
        );
      },

      codeAutoRetrievalTimeout: (_) {},
      timeout: const Duration(seconds: 60),
    );
  }
  // ── حفظ بيانات المستخدم في Firestore ────────────────────────

  Future<void> _saveUserToFirestore(String phone) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'userID': user.uid,
      'name': _nameController.text.trim(),
      'nationalID': _nationalIdController.text.trim(),
      'phoneNumber': phone,
      'nationalIDLocked': false,
      'role': 'user',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── UI Helpers (نفس الشكل الأصلي) ───────────────────────────

  TextStyle _textStyle({double fontSize = 14, Color color = Colors.black}) {
    return TextStyle(fontSize: fontSize, color: color);
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: _textStyle(fontSize: 14, color: Colors.black87)),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    String? errorText,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLength: maxLength,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
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
              borderSide: errorText != null
                  ? const BorderSide(color: Colors.red, width: 1.5)
                  : const BorderSide(color: Color(0xFF0B3B66), width: 1.5),
            ),
          ),
          onChanged: (val) {
            if (keyboardType == TextInputType.phone && val.startsWith('0')) {
              setState(
                () => _phoneError = 'Phone number should not start with 0',
              );
            } else {
              setState(() {
                _nameError = null;
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
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _primaryButton({required String text, required VoidCallback onTap}) {
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0B3B66),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(text, style: _textStyle(fontSize: 16, color: Colors.white)),
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
                _nameError = null;
                _nationalIdError = null;
                _phoneError = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isLogin ? Colors.transparent : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Sign up',
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
                _nameError = null;
                _nationalIdError = null;
                _phoneError = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isLogin ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Log in',
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
        _label('Phone Number'),
        _inputField(
          controller: _loginPhoneController,
          hint: '5XXXXXXXX',
          keyboardType: TextInputType.phone,
          errorText: _phoneError,
          maxLength: 9,
        ),
        const SizedBox(height: 90),
        _primaryButton(
          text: 'Log in',
          onTap: () {
            if (_validateLogin()) {
              _sendOTP(isSignUp: false);
            }
          },
        ),
      ],
    );
  }

  Widget _signupContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Name'),
        _inputField(
          controller: _nameController,
          hint: 'Name',
          errorText: _nameError,
        ),
        const SizedBox(height: 14),
        _label('National / Residence ID'),
        _inputField(
          controller: _nationalIdController,
          hint: 'ID',
          keyboardType: TextInputType.number,
          errorText: _nationalIdError,
          maxLength: 10,
        ),
        const SizedBox(height: 14),
        _label('Phone Number'),
        _inputField(
          controller: _signupPhoneController,
          hint: '5XXXXXXXX',
          keyboardType: TextInputType.phone,
          errorText: _phoneError,
          maxLength: 9,
        ),
        const SizedBox(height: 40),
        _primaryButton(
          text: 'Sign in',
          onTap: () {
            if (_validateSignup()) {
              _sendOTP(isSignUp: true);
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
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
                          'Welcome Back',
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

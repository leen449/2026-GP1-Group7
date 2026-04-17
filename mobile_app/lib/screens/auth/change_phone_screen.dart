import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import './verification_screen.dart';

class ChangePhoneScreen extends StatefulWidget {
final bool returnToHome;
const ChangePhoneScreen({super.key, this.returnToHome = false});

  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  final TextEditingController _nationalIdController = TextEditingController();
  final TextEditingController _newPhoneController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _nationalIdError;
  String? _phoneError;
  String? _userId;

  @override
  void dispose() {
    _nationalIdController.dispose();
    _newPhoneController.dispose();
    super.dispose();
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
    if (val.trim().isEmpty) return 'Please enter your new phone number';
    if (!RegExp(r'^[0-9]+$').hasMatch(val)) return 'Phone must contain digits only';
    if (val.startsWith('0')) return 'Phone number should not start with 0';
    if (val.length != 9) return 'Phone number must be 9 digits';
    if (!val.startsWith('5')) return 'Phone number must start with 5';
    return null;
  }

  bool _validate() {
    final idErr = _validateNationalId(_nationalIdController.text);
    final phoneErr = _validatePhone(_newPhoneController.text);
    setState(() {
      _nationalIdError = idErr;
      _phoneError = phoneErr;
    });
    return idErr == null && phoneErr == null;
  }

  Future<void> _verifyAndSendOTP() async {
    if (!_validate()) return;

    final nationalId = _nationalIdController.text.trim();
    final newPhone = '+966${_newPhoneController.text.trim()}';

    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('nationalID', isEqualTo: nationalId)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      setState(() => _nationalIdError = 'No account found with this ID');
      return;
    }

    _userId = query.docs.first.id;

    await _auth.verifyPhoneNumber(
      phoneNumber: newPhone,

      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
        await _updatePhone(newPhone);
      },

      verificationFailed: (FirebaseAuthException e) {
        String msg = 'An error occurred. Please try again.';
        if (e.code == 'invalid-phone-number') msg = 'Invalid phone number.';
        if (e.code == 'too-many-requests') msg = 'Too many requests. Try again later.';
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      },

      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VerificationScreen(
              verificationId: verificationId,
              resendToken: resendToken,
              phone: newPhone,
              isSignUp: false,
              name: '',
              nationalId: nationalId,
              onVerified: () => _updatePhone(newPhone),
            ),
          ),
        );
      },

      codeAutoRetrievalTimeout: (_) {},
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> _updatePhone(String newPhone) async {
  if (_userId == null) return;

  await FirebaseFirestore.instance.collection('users').doc(_userId).update({
    'phoneNumber': newPhone,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Phone number updated successfully!'),
      backgroundColor: Colors.green,
    ),
  );

  if (widget.returnToHome) {
    Navigator.pop(context);
    Navigator.pop(context); // يرجع للموديفاي
  } else {
    Navigator.popUntil(context, (route) => route.isFirst); // يرجع للوق إن
  }
}
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
    bool isNationalId = false, // ✅
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
              borderSide: errorText != null
                  ? const BorderSide(color: Colors.red, width: 1.5)
                  : const BorderSide(color: Color(0xFF0B3B66), width: 1.5),
            ),
          ),
          onChanged: (val) {
            if (isNationalId) {
              setState(() => _nationalIdError =
                'ID must start with 1 (Saudi) or 2 (Resident) and be 10 digits');
              if (val.length == 10 && (val.startsWith('1') || val.startsWith('2'))) {
                setState(() => _nationalIdError = null);
              }
            } else if (keyboardType == TextInputType.phone && val.startsWith('0')) {
              setState(() => _phoneError = 'Phone number should not start with 0');
            } else {
              setState(() {
                _nationalIdError = null;
                _phoneError = null;
              });
            }
          },
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 4),
            child: Text(errorText, style: const TextStyle(color: Colors.red, fontSize: 12)),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ هيدر بدون AppBar
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF0B3B66)),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Change Phone Number',
                    style: _textStyle(fontSize: 18, color: const Color(0xFF0B3B66)),
                  ),
                ],
              ),
              const SizedBox(height: 70),
              Text(
                'Enter your National ID and new phone number to update your account.',
                style: _textStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 50),
              _label('National / Residence ID'),
              _inputField(
                controller: _nationalIdController,
                hint: 'As shown on your ID card',
                keyboardType: TextInputType.number,
                errorText: _nationalIdError,
                maxLength: 10,
                isNationalId: true, // ✅
              ),
              const SizedBox(height: 40),
              _label('New Phone Number'),
              _inputField(
                controller: _newPhoneController,
                hint: '5XXXXXXXX',
                keyboardType: TextInputType.phone,
                errorText: _phoneError,
                maxLength: 9,
              ),
              const SizedBox(height: 85),
              SizedBox(
                height: 54,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _verifyAndSendOTP,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B3B66),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Send Verification Code',
                    style: _textStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
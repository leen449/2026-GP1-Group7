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

  // ✅ تحويل الأرقام العربية لإنجليزية
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
    if (val.trim().isEmpty) return 'يرجى إدخال رقم الجوال الجديد';
    if (!RegExp(r'^[0-9]+$').hasMatch(val))
      return 'يجب أن يحتوي رقم الجوال على أرقام فقط';
    if (val.startsWith('0')) return 'يجب ألا يبدأ رقم الجوال بـ 0';
    if (val.length != 9) return 'يجب أن يكون رقم الجوال 9 أرقام';
    if (!val.startsWith('5')) return 'يجب أن يبدأ رقم الجوال بـ 5';
    return null;
  }

  bool _validate() {
    // ✅ تحويل الأرقام العربية لإنجليزية قبل التحقق
    _nationalIdController.text = _convertToEnglishNumbers(
      _nationalIdController.text,
    );
    _newPhoneController.text = _convertToEnglishNumbers(
      _newPhoneController.text,
    );

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
      setState(() => _nationalIdError = 'لا يوجد حساب بهذا الرقم');
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
        String msg = 'حدث خطأ، حاول مرة أخرى';
        if (e.code == 'invalid-phone-number') msg = 'رقم الجوال غير صحيح';
        if (e.code == 'too-many-requests')
          msg = 'تم تجاوز الحد المسموح من المحاولات. حاول لاحقًا';
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
        content: Text('تم تحديث رقم الجوال بنجاح!'),
        backgroundColor: Colors.green,
      ),
    );

    if (widget.returnToHome) {
      Navigator.pop(context);
      Navigator.pop(context);
    } else {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  TextStyle _textStyle({
    double fontSize = 14,
    Color color = Colors.black,
    FontWeight fontWeight = FontWeight.w600,
    double height = 1.2,
  }) {
    return TextStyle(
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      height: height,
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerRight, // ✅
        child: Text(
          text,
          textAlign: TextAlign.right, // ✅
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLength: maxLength,
          textAlign: TextAlign.right, // ✅
          textDirection: TextDirection.rtl, // ✅
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ), // ✅
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), // ✅
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), // ✅
              borderSide: errorText != null
                  ? const BorderSide(color: Colors.red, width: 1.5)
                  : const BorderSide(color: Color(0xFFDDE7F3)), // ✅
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), // ✅
              borderSide: errorText != null
                  ? const BorderSide(color: Colors.red, width: 1.5)
                  : const BorderSide(color: Color(0xFF2563EB), width: 1.4), // ✅
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF), // ✅
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Color(0xFF071A3D),
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),

                  const SizedBox(width: 10),

                  Text(
                    'تغيير رقم الجوال',
                    style: _textStyle(
                      fontSize: 18,
                      color: const Color(0xFF071A3D),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'أدخل رقم هويتك ورقم الجوال الجديد لتحديث حسابك.',
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  style: _textStyle(
                    fontSize: 22,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              _label('رقم الهوية / الإقامة'), // ✅
              _inputField(
                controller: _nationalIdController,
                hint: 'كما هو موضح في بطاقة الهوية', // ✅
                keyboardType: TextInputType.number,
                errorText: _nationalIdError,
                maxLength: 10,
                isNationalId: true,
              ),
              const SizedBox(height: 40),
              _label('رقم الجوال الجديد'), // ✅
              _inputField(
                controller: _newPhoneController,
                hint: '5XXXXXXXX',
                keyboardType: TextInputType.phone,
                errorText: _phoneError,
                maxLength: 9,
              ),
              const SizedBox(height: 85),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _verifyAndSendOTP,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A6E),
                    foregroundColor: Colors.white,

                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),

                    minimumSize: const Size(0, 48),

                    elevation: 0,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),

                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'إرسال رمز التحقق',
                      style: _textStyle(
                        fontSize: 15,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
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
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../NavBar/nav_bar.dart';

class VerificationScreen extends StatefulWidget {
  final String verificationId;
  final int? resendToken;
  final String phone;
  final bool isSignUp;
  final String name;
  final String nationalId;
  final VoidCallback? onVerified;
  final String dateOfBirth;

  const VerificationScreen({
    super.key,
    required this.verificationId,
    this.resendToken,
    required this.phone,
    required this.isSignUp,
    this.name = '',
    this.nationalId = '',
    this.onVerified,
    this.dateOfBirth = '',
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  late String _verificationId;
  int? _resendToken;

  bool _isLoading = false;
  bool _canResend = false;
  int _seconds = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes[0].requestFocus();
    });
    _startTimer();
    // Update UI when OTP field focus changes
    for (final node in _focusNodes) {
      node.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  void _startTimer() {
    _seconds = 60;
    _canResend = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_seconds == 0) {
        t.cancel();
        setState(() => _canResend = true);
      } else {
        setState(() => _seconds--);
      }
    });
  }

  String get _otpCode => _controllers.map((c) => c.text).join();

  void _navigateAfterVerification() {
    if (widget.onVerified != null) {
      widget.onVerified!();
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AppBottomNav()),
      );
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpCode.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إدخال الرمز المكون من 6 أرقام'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: _otpCode,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      if (widget.isSignUp) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (!userDoc.exists) {
          await _saveUserToFirestore();
        }
      } else if (widget.onVerified == null) {
        final query = await FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', isEqualTo: widget.phone)
            .limit(1)
            .get();

        if (query.docs.isEmpty) {
          await FirebaseAuth.instance.signOut();
          setState(() => _isLoading = false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يوجد حساب بهذا الرقم. الرجاء إنشاء حساب جديد'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      if (!mounted) return;
      _navigateAfterVerification();
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      String msg = 'رمز غير صحيح. حاول مرة أخرى';
      if (e.code == 'session-expired') {
        msg = 'انتهت صلاحية الرمز. اطلب رمزاً جديداً';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  Future<void> _saveUserToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'userID': user.uid,
      'name': widget.name,
      'nationalID': widget.nationalId,
      'phoneNumber': widget.phone,
      'dateOfBirth': widget.dateOfBirth,
      'nationalIDLocked': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _resendOTP() async {
    if (!_canResend) return;
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: widget.phone,
      forceResendingToken: _resendToken,
      verificationCompleted: (credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
        if (widget.isSignUp) await _saveUserToFirestore();
        if (!mounted) return;
        _navigateAfterVerification();
      },
      verificationFailed: (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'حدث خطأ. حاول مرة أخرى'),
            backgroundColor: Colors.red,
          ),
        );
      },
      codeSent: (newId, newToken) {
        setState(() {
          _verificationId = newId;
          _resendToken = newToken;
        });
        _startTimer();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إعادة إرسال الرمز بنجاح ✅')),
        );
      },
      codeAutoRetrievalTimeout: (_) {},
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboard = keyboardH > 0;
    final boxSize = ((sw - 44 - 50) / 6).clamp(40.0, 56.0);
    final boxGap = (boxSize * 0.2).clamp(6.0, 12.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  sh -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: sw * 0.06),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: isKeyboard ? 6 : 12),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      padding: EdgeInsets.zero,
                    ),
                    SizedBox(height: isKeyboard ? 10 : 18),
                    Center(
                      child: Text(
                        'تحقق من رقم\nجوالك',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: (sw * 0.082).clamp(26.0, 38.0),
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                          height: 1.1,
                        ),
                      ),
                    ),
                    SizedBox(height: isKeyboard ? 8 : 14),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'تم إرسال رمز التحقق',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: (sw * 0.036).clamp(12.0, 16.0),
                              height: 1.35,
                              color: Colors.black.withOpacity(0.55),
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            textDirection: TextDirection.rtl,
                            children: [
                              Text(
                                'إلى رقم جوالك  ',
                                style: TextStyle(
                                  fontSize: (sw * 0.036).clamp(12.0, 16.0),
                                  color: Colors.black.withOpacity(0.55),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(
                                  widget.phone,
                                  style: TextStyle(
                                    fontSize: (sw * 0.036).clamp(12.0, 16.0),
                                    color: Colors.black.withOpacity(0.55),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isKeyboard ? 16 : 28),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          6,
                          (i) => _otpBox(i, boxSize, boxGap),
                        ),
                      ),
                    ),
                    SizedBox(height: isKeyboard ? 14 : 26),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        textDirection: TextDirection.rtl,
                        children: [
                          Text(
                            'لم يصلك الرمز؟',
                            style: TextStyle(
                              fontSize: (sw * 0.036).clamp(12.0, 15.0),
                              color: Colors.black.withOpacity(0.55),
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          const SizedBox(width: 8),

                          GestureDetector(
                            onTap: _canResend ? _resendOTP : null,
                            child: Text(
                              _canResend
                                  ? 'إعادة الإرسال'
                                  : 'إعادة الإرسال (00:${_seconds.toString().padLeft(2, '0')})',
                              style: TextStyle(
                                fontSize: (sw * 0.036).clamp(12.0, 15.0),
                                fontWeight: FontWeight.w700,
                                color: _canResend
                                    ? const Color(0xFF2563EB)
                                    : Colors.black38,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isKeyboard ? 14 : 26),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _verifyOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B4A7D),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'تحقق',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _otpBox(int index, double size, double gap) {
    return Container(
      width: size,
      height: size * 1.15,
      margin: EdgeInsets.only(right: index == 5 ? 0 : gap),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focusNodes[index].hasFocus
              ? const Color(0xFF2563EB)
              : Colors.black.withOpacity(0.08),
          width: _focusNodes[index].hasFocus ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        onTap: () {
          setState(() {}); // Rebuild to update focused border color
        },

        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center, // Center number vertically
        style: TextStyle(
          fontSize: size * 0.44,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (val) {
          if (val.isNotEmpty) {
            if (index < 5) {
              _focusNodes[index + 1].requestFocus();
            } else {
              _focusNodes[index].unfocus();
              _verifyOtp();
            }
          } else {
            if (index > 0) _focusNodes[index - 1].requestFocus();
          }
        },
      ),
    );
  }
}

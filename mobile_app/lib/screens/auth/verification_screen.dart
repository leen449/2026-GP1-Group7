import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../home/home_screen.dart';

class VerificationScreen extends StatefulWidget {
  final String verificationId;
  final int? resendToken;
  final String phone;
  final bool isSignUp;
  final String name;
  final String nationalId;

  const VerificationScreen({
    super.key,
    required this.verificationId,
    this.resendToken,
    required this.phone,
    required this.isSignUp,
    this.name = '',
    this.nationalId = '',
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

  Future<void> _verifyOtp() async {
    if (_otpCode.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the complete 6-digit code.'),
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
      if (widget.isSignUp) await _saveUserToFirestore();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      String msg = 'Incorrect code. Please try again.';
      if (e.code == 'session-expired') {
        msg = 'Code expired. Please request a new one.';
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
      'nationalIDLocked': false,
      'role': 'user',
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      },
      verificationFailed: (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Error resending code.'),
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
          const SnackBar(content: Text('Code resent successfully ✅')),
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
    // ✅ When keyboard opens viewInsets.bottom > 0 — shrink content
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboard = keyboardH > 0;

    // ✅ OTP box size scales with screen width
    // 6 boxes + 5 gaps must fit within sw - 44 (horizontal padding)
    final boxSize = ((sw - 44 - 50) / 6).clamp(40.0, 56.0);
    final boxGap = (boxSize * 0.2).clamp(6.0, 12.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      // ✅ resizeToAvoidBottomInset: true (default) — content shifts up
      // with keyboard. We handle this via SingleChildScrollView.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          // ✅ Wrap in scroll so keyboard never causes overflow
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            // Minimum height = screen height so Spacer works
            // Maximum = unconstrained so scroll works with keyboard
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

                    // Back button
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      padding: EdgeInsets.zero,
                    ),

                    SizedBox(height: isKeyboard ? 10 : 18),

                    // Title
                    Center(
                      child: Text(
                        'Verify your phone\nnumber',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          // ✅ Responsive font size
                          fontSize: (sw * 0.082).clamp(26.0, 38.0),
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                          height: 1.1,
                        ),
                      ),
                    ),

                    SizedBox(height: isKeyboard ? 8 : 14),

                    // Subtitle
                    Center(
                      child: Text(
                        "We've sent an SMS with an activation\n"
                        "code to your phone  ${widget.phone}",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: (sw * 0.036).clamp(12.0, 16.0),
                          height: 1.35,
                          color: Colors.black.withOpacity(0.55),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    SizedBox(height: isKeyboard ? 16 : 28),

                    // ✅ OTP boxes — responsive size and gap
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

                    // Resend row
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                            "I didn't receive a code",
                            style: TextStyle(
                              fontSize: (sw * 0.036).clamp(12.0, 15.0),
                              color: Colors.black.withOpacity(0.55),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          GestureDetector(
                            onTap: _canResend ? _resendOTP : null,
                            child: Text(
                              _canResend
                                  ? 'Resend'
                                  : 'Resend (00:${_seconds.toString().padLeft(2, '0')})',
                              style: TextStyle(
                                fontSize: (sw * 0.036).clamp(12.0, 15.0),
                                fontWeight: FontWeight.w700,
                                color: _canResend
                                    ? Colors.black87
                                    : Colors.black38,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: isKeyboard ? 14 : 26),

                    // Verify button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _verifyOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0A3D62),
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
                                'Verify',
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
      height: size * 1.15, // slightly taller than wide
      margin: EdgeInsets.only(right: index == 5 ? 0 : gap),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
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
          contentPadding: EdgeInsets.only(bottom: 2),
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

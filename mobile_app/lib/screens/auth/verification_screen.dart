import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final List<TextEditingController> _controllers =
      List.generate(5, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(5, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    // يفتح الكيبورد على طول
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _goHome() {
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),

              // Back arrow
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              ),

              const SizedBox(height: 18),

              // Title
              Center(
                child: Text(
                  'Verify your phone\nnumber',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                    height: 1.1,
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Subtitle
              Center(
                child: Text(
                  "We've sent an SMS with an activation\n"
                  "code to your phone  +33 2 94 27 84 11",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: Colors.black.withOpacity(0.55),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // OTP boxes (5)
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => _otpBox(i)),
                ),
              ),

              const SizedBox(height: 26),

              // Resend row
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "I didn't receive a code",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black.withOpacity(0.55),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Resend tapped')),
                        );
                      },
                      child: const Text(
                        'Resend',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 26),

              // Verify button
              Center(
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _goHome,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A3D62),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Verify',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
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
    );
  }

  Widget _otpBox(int index) {
    return Container(
      width: 56,
      height: 56,
      margin: EdgeInsets.only(right: index == 4 ? 0 : 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 22,
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
            // إذا كتب رقم ينتقل للي بعده
            if (index < 4) {
              _focusNodes[index + 1].requestFocus();
            } else {
              _focusNodes[index].unfocus();
            }
          } else {
            // إذا مسح يرجع للي قبله
            if (index > 0) _focusNodes[index - 1].requestFocus();
          }
        },
      ),
    );
  }
}
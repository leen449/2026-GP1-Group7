import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:io';
import 'guided_camera_screen.dart';

class GuidedDamageCaptureScreen extends StatefulWidget {
  const GuidedDamageCaptureScreen({super.key});

  @override
  State<GuidedDamageCaptureScreen> createState() =>
      _GuidedDamageCaptureScreenState();
}

class _GuidedDamageCaptureScreenState extends State<GuidedDamageCaptureScreen> {
  List<File> capturedPhotos = [];

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final sw = media.size.width;
    final sh = media.size.height;
    final topPad = media.padding.top;
    final bottomPad = media.padding.bottom;
    final available = sh - topPad - bottomPad;

    final titleSize = (sw * 0.055).clamp(18.0, 26.0);
    final subtitleSize = (sw * 0.036).clamp(12.0, 16.0);
    final buttonTextSize = (sw * 0.042).clamp(14.0, 18.0);

    return Scaffold(
      // ✅ extendBody ensures scaffold content goes behind system nav bar
      // This keeps the blur consistent all the way to the bottom edge
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background — fills ENTIRE screen including nav bar area ──
          Container(color: const Color(0xFFCDD9E2)),

          // Top-right dark blob
          Positioned(
            top: -sw * 0.08,
            right: -sw * 0.23,
            child: Container(
              width: sw * 0.80,
              height: sw * 0.80,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color.fromARGB(255, 66, 91, 129),
              ),
            ),
          ),

          // Bottom-left dark blob — extended to cover nav bar area
          Positioned(
            bottom: -sw * 0.32,
            left: -sw * 0.30,
            child: Container(
              width: sw * 1.20,
              height: sw * 1.15,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color.fromARGB(255, 89, 121, 147),
              ),
            ),
          ),

          // ✅ Blur layer — StackFit.expand makes it cover full screen
          // including behind the system navigation bar
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Container(color: Colors.transparent),
          ),

          // ── UI content — SafeArea keeps content above system bars ──
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: sw * 0.05),
              child: Column(
                children: [
                  const SizedBox(height: 8),

                  // Back button
                  Align(
                    alignment: Alignment.topLeft,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.20),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.6),
                            width: 1.2,
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.black,
                          size: 20,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: available * 0.008),

                  Expanded(
                    child: Transform.translate(
                      offset: Offset(0, -available * 0.04),
                      child: Column(
                        children: [
                          // ── Illustration ────────────────────────
                          Expanded(
                            flex: 46,
                            child: SizedBox(
                              width: double.infinity,
                              child: Stack(
                                alignment: Alignment.center,
                                clipBehavior: Clip.none,
                                children: [
                                  // Oval platform
                                  Positioned(
                                    bottom: available * 0.05,
                                    child: Container(
                                      width: sw * 1.0,
                                      height: sw * 0.24,
                                      decoration: const ShapeDecoration(
                                        shape: OvalBorder(),
                                        shadows: [
                                          BoxShadow(
                                            color: Color.fromARGB(
                                              66,
                                              26,
                                              26,
                                              26,
                                            ),
                                            offset: Offset(0, 10),
                                            blurRadius: 10,
                                          ),
                                        ],
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0xFFFFFFFF),
                                            Color(0xFFC8D8E4),
                                            Color(0xFF91B1C9),
                                          ],
                                          stops: [0.0, 0.67, 1.0],
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Illustration image
                                  Positioned(
                                    top: available * 0.12,
                                    child: Image.asset(
                                      'assets/images/ChatGPT Image Mar 2, 2026, 01_20_39 AM.png',
                                      width: sw * 1.22,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // ── Text ────────────────────────────────
                          Expanded(
                            flex: 18,
                            child: Padding(
                              padding: EdgeInsets.only(top: available * 0.001),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Guided Damage Capture',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      shadows: const [
                                        Shadow(
                                          offset: Offset(0, 4),
                                          blurRadius: 6,
                                          color: Color.fromARGB(66, 26, 26, 26),
                                        ),
                                      ],
                                      color: Colors.white,
                                      fontSize: titleSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: available * 0.012),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: sw * 0.06,
                                    ),
                                    child: Text(
                                      'Capture Photos Of The Damage, Make Sure To Take One Image Per Damage For Accurate Assessment',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                        fontSize: subtitleSize,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          SizedBox(height: available * 0.01),

                          // ── Button ───────────────────────────────
                          Expanded(
                            flex: 10,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: sw * 0.56,
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const GuidedCameraScreen(),
                                        ),
                                      );
                                      if (result != null &&
                                          result is List<File>) {
                                        setState(() => capturedPhotos = result);
                                        if (!mounted) return;
                                        Navigator.pop(context, result);
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0B4A7D),
                                      foregroundColor: Colors.white,
                                      elevation: 8,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                    ),
                                    child: Text(
                                      'next',
                                      style: TextStyle(
                                        fontSize: buttonTextSize,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: available * 0.001),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

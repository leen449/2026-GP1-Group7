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
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── 1. BASE: light blue-grey ──────────────────────────────
          Container(color: const Color(0xFFCDD9E2)),

          // ── 2. DARK NAVY BLOB — top right ────────────────────────
          Positioned(
            top: -sh * 0.000,
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

          // ── 3. DARK NAVY BLOB — bottom left ──────────────────────
          Positioned(
            bottom: sh * 0.001,
            left: -sw * 0.22,
            child: Container(
              width: sw * 1,
              height: sw * 0.9,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color.fromARGB(255, 89, 121, 147),
              ),
            ),
          ),

          // ── 4. BLUR over blobs ────────────────────────────────────
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Container(color: Colors.transparent),
          ),

          // ── 5. UI ─────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Back button
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 12),
                  child: Align(
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
                            color: const Color.fromARGB(
                              255,
                              0,
                              0,
                              0,
                            ).withOpacity(0.6),
                            width: 1.2,
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Color.fromARGB(255, 0, 0, 0),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),

                // Illustration with oval
                Expanded(
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // White oval platform
                        Positioned(
                          top: sw * 0.53,
                          child: Container(
                            width: sw * 0.99,
                            height: sw * 0.35,
                            decoration: const ShapeDecoration(
                              shape: OvalBorder(),
                              shadows: [
                                BoxShadow(
                                  color: Color.fromARGB(66, 26, 26, 26),
                                  offset: Offset(0, 8),
                                  blurRadius: 6,
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
                        // Cars illustration
                        Positioned(
                          top: sw * 0.1,
                          child: Image.asset(
                            'assets/images/ChatGPT Image Mar 2, 2026, 01_20_39 AM.png',
                            width: sw * 1.1,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Text section
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: sw * 0.08),
                  child: Column(
                    children: [
                      const Text(
                        'Guided Damage Capture',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          shadows: [
                            Shadow(
                              offset: Offset(0, 4),
                              blurRadius: 6,
                              color: Color.fromARGB(66, 26, 26, 26),
                            ),
                          ],
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 110),
                      Transform.translate(
                        offset: const Offset(0, -90),
                        child: const Text(
                          'Capture Photos Of The Damage , Make Sure\n'
                          'To Take One Image Per Damage For Accurate\n'
                          'Assessment',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Next button
                Padding(
                  padding: EdgeInsets.only(top: sh * 0.043, bottom: sh * 0.045),
                  child: SizedBox(
                    width: sw * 0.50,
                    child: ElevatedButton(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const GuidedCameraScreen(),
                          ),
                        );

                        if (result != null && result is List<File>) {
                          // ✅ FIXED: Navigator.pop is now outside setState
                          setState(() => capturedPhotos = result);
                          Navigator.pop(context, result);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4A7D),
                        foregroundColor: Colors.white,
                        elevation: 8,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        'next',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

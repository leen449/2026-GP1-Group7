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
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background base
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

          // Bottom-left dark blob
          Positioned(
            bottom: -sw * 0.18,
            left: -sw * 0.22,
            child: Container(
              width: sw * 1.02,
              height: sw * 0.95,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color.fromARGB(255, 89, 121, 147),
              ),
            ),
          ),

          // Blur layer
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Container(color: Colors.transparent),
          ),

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

                  SizedBox(height: available * 0.015),

                  // Illustration section
                  Expanded(
                    flex: 48,
                    child: SizedBox(
                      width: double.infinity,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Oval platform
                          Positioned(
                            bottom: available * 0.01,
                            child: Container(
                              width: sw * 0.84,
                              height: sw * 0.24,
                              decoration: const ShapeDecoration(
                                shape: OvalBorder(),
                                shadows: [
                                  BoxShadow(
                                    color: Color.fromARGB(66, 26, 26, 26),
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

                          // Illustration
                          Positioned(
                            top: available * 0.20,
                            child: Image.asset(
                              'assets/images/ChatGPT Image Mar 2, 2026, 01_20_39 AM.png',
                              width: sw * 0.95,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Text section
                  Expanded(
                    flex: 22,
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
                        SizedBox(height: available * 0.015),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: sw * 0.06),
                          child: Text(
                            'Capture Photos Of The Damage , Make Sure\n'
                            'To Take One Image Per Damage For Accurate\n'
                            'Assessment',
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

                  // Button section
                  Expanded(
                    flex: 14,
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
                                  builder: (_) => const GuidedCameraScreen(),
                                ),
                              );

                              if (result != null && result is List<File>) {
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

                  SizedBox(height: available * 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

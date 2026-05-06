import 'dart:io';
import 'package:flutter/material.dart';
import 'VerifyDetailsScreen.dart';

class PreviewPhotoScreen extends StatelessWidget {
  // The file path of the cropped image taken from ScanScreen
  final String imagePath;

  const PreviewPhotoScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),

            // Screen title
            const Text(
              'معاينة الصورة',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),

            // Subtitle instruction
            const Text(
              'تأكد أن الصورة واضحة وقابلة للقراءة',
              style: TextStyle(fontSize: 15, color: Color(0xFF8899AA)),
            ),

            const SizedBox(height: 24),

            // ── Cropped image preview ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    // Display the captured image — width fills the screen
                    Image.file(
                      File(imagePath),
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                    ),

                    // Dark gradient overlay at the bottom for badge visibility
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withOpacity(0.4),
                              Colors.transparent,
                            ],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                        ),
                      ),
                    ),

                    // Label badge at the bottom-left corner
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.photo_camera_outlined,
                              color: Colors.white,
                              size: 13,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'استمارة المركبة',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Quality warning banner ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFE082)),
                ),
                child: const Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Color(0xFFF9A825),
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تأكد ان جميع النصوص واضحه قبل المتابعة.',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF7A6000),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Push buttons to the bottom
            const Spacer(),

            // ── Action buttons ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Row(
                children: [
                  // Retake
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.refresh_rounded,
                        size: 18,
                        color: Color(0xFF1A1A2E),
                      ),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'إعادة الالتقاط',
                          style: TextStyle(
                            color: Color(0xFF1A1A2E),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1A1A2E),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        minimumSize: const Size(0, 48),
                        side: const BorderSide(
                          color: Color(0xFFDDE3EE),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Use photo
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                VerifyDetailsScreen(imagePath: imagePath),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'استخدام الصورة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A6E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

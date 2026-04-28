import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'preview_photos_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _cameraController;
  bool _isInitialized = false;
  bool _isCapturing = false;
  bool _flashOn = false;

  // نسبة الإطار بالنسبة للشاشة
  final double _frameWidthRatio = 0.92;
  final double _frameHeightRatio = 0.38;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (mounted) setState(() => _isInitialized = true);
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;
    setState(() => _flashOn = !_flashOn);
    await _cameraController!.setFlashMode(
      _flashOn ? FlashMode.torch : FlashMode.off,
    );
  }

  Future<void> _captureAndCrop() async {
    if (_cameraController == null || _isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      // التقاط الصورة
      final XFile file = await _cameraController!.takePicture();
      final bytes = await File(file.path).readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) return;

      // حجم الشاشة
      final screenSize = MediaQuery.of(context).size;
      final sw = screenSize.width;
      final sh = screenSize.height;

      // أبعاد الإطار على الشاشة
      final frameW = sw * _frameWidthRatio;
      final frameH = sh * _frameHeightRatio;
      final frameLeft = (sw - frameW) / 2;
      final frameTop = (sh - frameH) / 2;

      // نسبة التحويل من الشاشة إلى الصورة الحقيقية
      final scaleX = originalImage.width / sw;
      final scaleY = originalImage.height / sh;

      final cropX = (frameLeft * scaleX).toInt().clamp(0, originalImage.width);
      final cropY = (frameTop * scaleY).toInt().clamp(0, originalImage.height);
      final cropW = (frameW * scaleX).toInt().clamp(1, originalImage.width - cropX);
      final cropH = (frameH * scaleY).toInt().clamp(1, originalImage.height - cropY);

      // قص الصورة
      final cropped = img.copyCrop(
        originalImage,
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
      );

      // حفظ الصورة المقصوصة
      final croppedPath = '${file.path}_cropped.jpg';
      await File(croppedPath).writeAsBytes(img.encodeJpg(cropped, quality: 95));

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PreviewPhotoScreen(imagePath: croppedPath),
          ),
        );
      }
    } catch (e) {
      debugPrint('Capture error: $e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── معاينة الكاميرا ──
          if (_isInitialized && _cameraController != null)
            Positioned.fill(child: CameraPreview(_cameraController!))
          else
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // ── تعتيم حول الإطار ──
          Positioned.fill(
            child: LayoutBuilder(builder: (ctx, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final fw = w * _frameWidthRatio;
              final fh = h * _frameHeightRatio;
              final fl = (w - fw) / 2;
              final ft = (h - fh) / 2;
              return CustomPaint(
                painter: _OverlayPainter(
                  frameRect: Rect.fromLTWH(fl, ft, fw, fh),
                ),
              );
            }),
          ),

          // ── شريط علوي ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      _flashOn ? Icons.flash_on : Icons.flash_off,
                      color: Colors.white,
                    ),
                    onPressed: _toggleFlash,
                  ),
                  const Text(
                    'الكاميرا',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),

          // ── نص التعليمات ──
          const Positioned(
            top: 130,
            left: 0,
            right: 0,
            child: Text(
              'قم بوضع استمارة المركبة بالكامل داخل الإطار\nلالتقاط صورة واضحة',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),

          // ── زوايا الإطار ──
          Center(
            child: Builder(builder: (ctx) {
              final w = MediaQuery.of(context).size.width * _frameWidthRatio;
              final h = MediaQuery.of(context).size.height * _frameHeightRatio;
              return SizedBox(
                width: w,
                height: h,
                child: CustomPaint(painter: _CornerPainter()),
              );
            }),
          ),

          // ── زر التصوير ──
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _captureAndCrop,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: _isCapturing ? 44 : 56,
                      height: _isCapturing ? 44 : 56,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// تعتيم خارج الإطار
class _OverlayPainter extends CustomPainter {
  final Rect frameRect;
  const _OverlayPainter({required this.frameRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(8)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.frameRect != frameRect;
}

// زوايا الإطار الزرقاء
class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 22.0;
    final w = size.width;
    final h = size.height;

    // أعلى يسار
    canvas.drawLine(Offset.zero, const Offset(len, 0), paint);
    canvas.drawLine(Offset.zero, const Offset(0, len), paint);
    // أعلى يمين
    canvas.drawLine(Offset(w, 0), Offset(w - len, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, len), paint);
    // أسفل يسار
    canvas.drawLine(Offset(0, h), Offset(len, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - len), paint);
    // أسفل يمين
    canvas.drawLine(Offset(w, h), Offset(w - len, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - len), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}
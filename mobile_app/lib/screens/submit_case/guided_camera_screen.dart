import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'photo_preview_screen.dart';
import 'quality_controller.dart';

class GuidedCameraScreen extends StatefulWidget {
  const GuidedCameraScreen({super.key});

  @override
  State<GuidedCameraScreen> createState() => _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends State<GuidedCameraScreen> {
  CameraController? _controller;
  bool isCameraReady = false;
  int _sensorOrientation = 0;

  List<XFile> shots = [];

  late final QualityController _qualityController;
  QualityResult _currentResult = QualityResult.initial();
  StreamSubscription<QualityResult>? _qualitySubscription;

  bool _isTakingPicture = false;
  bool _isDisposed = false;
  bool _showFlash = false;

  @override
  void initState() {
    super.initState();
    _qualityController = QualityController();
    _listenToQuality();
    _initCamera();
  }

  void _listenToQuality() {
    _qualitySubscription = _qualityController.stream.listen((result) {
      if (!mounted || _isDisposed) return;
      setState(() => _currentResult = result);
    });
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final camera = cameras.first;
    _sensorOrientation = camera.sensorOrientation;

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();
    await _startImageStream();

    if (mounted && !_isDisposed) {
      setState(() => isCameraReady = true);
    }
  }

  Future<void> _startImageStream() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isStreamingImages) return;
    await _controller!.startImageStream((CameraImage frame) {
      if (_isTakingPicture || _isDisposed) return;
      _qualityController.processFrame(frame, _sensorOrientation);
    });
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (shots.length >= 10) return;
    if (_isTakingPicture) return;

    setState(() => _isTakingPicture = true);

    try {
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }

      final image = await _controller!.takePicture();

      if (mounted && !_isDisposed) setState(() => _showFlash = true);
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted && !_isDisposed) setState(() => _showFlash = false);

      await _startImageStream();

      if (mounted && !_isDisposed) setState(() => shots.add(image));
    } catch (e) {
      print('❌ Error taking picture: $e');
    } finally {
      if (mounted && !_isDisposed) setState(() => _isTakingPicture = false);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _qualitySubscription?.cancel();
    _qualityController.dispose();
    if (_controller != null) {
      if (_controller!.value.isStreamingImages) {
        _controller!.stopImageStream();
      }
      _controller!.dispose();
    }
    super.dispose();
  }

  Color get _bannerColor {
    if (_currentResult.allOk) return const Color(0xFF2EAB5F);
    if (!_currentResult.brightnessOk) return const Color(0xFFE65100);
    if (!_currentResult.sharpnessOk) return const Color(0xFF1565C0);
    return const Color(0xFFE65100);
  }

  IconData get _bannerIcon {
    if (_currentResult.allOk) return Icons.check_circle;
    if (!_currentResult.brightnessOk) return Icons.wb_sunny_outlined;
    if (!_currentResult.sharpnessOk) return Icons.blur_on;
    return Icons.social_distance;
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Read screen width once for responsive sizing
    final sw = MediaQuery.of(context).size.width;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: isCameraReady
          ? Stack(
              children: [
                // ── Camera preview ─────────────────────────────────
                SizedBox.expand(child: CameraPreview(_controller!)),

                // ── Green flash ─────────────────────────────────────
                if (_showFlash)
                  Container(color: Colors.green.withOpacity(0.35)),

                // ── Guidance banner ─────────────────────────────────
                // ✅ left/right margins prevent edge overflow on any device
                Positioned(
                  top: topPad + 16,
                  left: sw * 0.06,
                  right: sw * 0.06,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _bannerColor,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_bannerIcon, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          // ✅ Flexible allows text to wrap on long messages
                          // instead of overflowing — fixes the 4px & 82px overflow
                          Flexible(
                            child: Text(
                              _currentResult.guidance,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                // ✅ Responsive font size
                                fontSize: (sw * 0.035).clamp(12.0, 15.0),
                              ),
                              softWrap: true,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Thumbnail preview ───────────────────────────────
                if (shots.isNotEmpty)
                  Positioned(
                    top: topPad + 70,
                    right: 20,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PhotoPreviewScreen(
                              imageFile: File(shots.last.path),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 70,
                        height: 90,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 2),
                          image: DecorationImage(
                            image: FileImage(File(shots.last.path)),
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(8),
                                bottomRight: Radius.circular(8),
                              ),
                            ),
                            child: const Icon(
                              Icons.zoom_in,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── Shot counter ────────────────────────────────────
                if (shots.isNotEmpty)
                  Positioned(
                    top: topPad + 70,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${shots.length}/10',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                // ── Capture button ──────────────────────────────────
                Positioned(
                  bottom: 120,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: (_currentResult.allOk && !_isTakingPicture)
                          ? _takePicture
                          : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (_currentResult.allOk && !_isTakingPicture)
                              ? Colors.white
                              : Colors.white.withOpacity(0.4),
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: _isTakingPicture
                            ? const Padding(
                                padding: EdgeInsets.all(22),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt,
                                size: 32,
                                color: Colors.black,
                              ),
                      ),
                    ),
                  ),
                ),

                // ── Next button ─────────────────────────────────────
                if (shots.isNotEmpty)
                  Positioned(
                    bottom: 40,
                    left: 60,
                    right: 60,
                    child: ElevatedButton(
                      onPressed: _isTakingPicture
                          ? null
                          : () {
                              final files = shots
                                  .map((x) => File(x.path))
                                  .toList();
                              Navigator.pop(context, files);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4A7D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text('next'),
                    ),
                  ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

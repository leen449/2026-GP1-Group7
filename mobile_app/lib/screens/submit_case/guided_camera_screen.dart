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
  // ── Camera ────────────────────────────────────────────────────────
  CameraController? _controller;
  bool isCameraReady = false;
  int _sensorOrientation = 0;

  // ── Shots ─────────────────────────────────────────────────────────
  List<XFile> shots = [];

  // ── Quality controller ────────────────────────────────────────────
  late final QualityController _qualityController;
  QualityResult _currentResult = QualityResult.initial();
  StreamSubscription<QualityResult>? _qualitySubscription;

  // ── Auto-capture countdown ────────────────────────────────────────
  // When allOk == true we start a 1-second timer before auto-capturing
  Timer? _autoCaptureTimer;
  bool _autoCaptureArmed = false;

  // ── Flash overlay (green flash after capture) ─────────────────────
  bool _showFlash = false;

  @override
  void initState() {
    super.initState();
    _qualityController = QualityController();
    _listenToQuality();
    _initCamera();
  }

  // ── Listen to quality stream and update UI ─────────────────────────
  void _listenToQuality() {
    _qualitySubscription = _qualityController.stream.listen((result) {
      if (!mounted) return;
      setState(() => _currentResult = result);

      // Auto-capture logic
      if (result.allOk && !_autoCaptureArmed) {
        _armAutoCapture();
      } else if (!result.allOk && _autoCaptureArmed) {
        _disarmAutoCapture();
      }
    });
  }

  // ── Init camera and start image stream ────────────────────────────
  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final camera = cameras.first;
    _sensorOrientation = camera.sensorOrientation;

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420, // ✅ needed for Y-plane
    );

    await _controller!.initialize();

    // ✅ Start streaming frames to QualityController
    await _controller!.startImageStream((CameraImage frame) {
      _qualityController.processFrame(frame, _sensorOrientation);
    });

    if (mounted) {
      setState(() => isCameraReady = true);
    }
  }

  // ── Auto-capture: arm a 1-second timer ────────────────────────────
  void _armAutoCapture() {
    _autoCaptureArmed = true;
    _autoCaptureTimer = Timer(const Duration(seconds: 1), () {
      if (_currentResult.allOk && mounted) {
        _takePicture();
      }
    });
  }

  void _disarmAutoCapture() {
    _autoCaptureArmed = false;
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
  }

  // ── Take picture ──────────────────────────────────────────────────
  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (shots.length >= 10) return;

    // Stop stream briefly to take picture
    await _controller!.stopImageStream();

    final image = await _controller!.takePicture();

    // Show green flash
    if (mounted) setState(() => _showFlash = true);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _showFlash = false);
    });

    // Resume stream
    await _controller!.startImageStream((CameraImage frame) {
      _qualityController.processFrame(frame, _sensorOrientation);
    });

    if (mounted) {
      setState(() {
        shots.add(image);
        _autoCaptureArmed = false;
      });
    }
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _qualitySubscription?.cancel();
    _qualityController.dispose();
    _controller?.stopImageStream();
    _controller?.dispose();
    super.dispose();
  }

  // ── Guidance banner color ─────────────────────────────────────────
  Color get _bannerColor {
    if (_currentResult.allOk) return const Color(0xFF2EAB5F); // green
    if (!_currentResult.brightnessOk) return const Color(0xFFE65100); // orange
    if (!_currentResult.sharpnessOk) return const Color(0xFF1565C0); // blue
    return const Color(0xFFE65100); // orange for distance
  }

  IconData get _bannerIcon {
    if (_currentResult.allOk) return Icons.check_circle;
    if (!_currentResult.brightnessOk) return Icons.wb_sunny_outlined;
    if (!_currentResult.sharpnessOk) return Icons.blur_on;
    return Icons.social_distance;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isCameraReady
          ? Stack(
              children: [
                // ── Camera preview ───────────────────────────────────
                SizedBox.expand(child: CameraPreview(_controller!)),

                // ── Green flash overlay on capture ───────────────────
                if (_showFlash)
                  Container(color: Colors.green.withOpacity(0.35)),

                // ── Guidance banner ──────────────────────────────────
                Positioned(
                  top: 60,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
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
                          Text(
                            _currentResult.guidance,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Auto-capture indicator ───────────────────────────
                if (_autoCaptureArmed)
                  Positioned(
                    top: 115,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        'Auto-capturing...',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                // ── Thumbnail preview (tap to preview) ───────────────
                if (shots.isNotEmpty)
                  Positioned(
                    top: 120,
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

                // ── Shot counter ─────────────────────────────────────
                if (shots.isNotEmpty)
                  Positioned(
                    top: 120,
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

                // ── Manual capture button ────────────────────────────
                Positioned(
                  bottom: 120,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _currentResult.allOk ? _takePicture : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentResult.allOk
                              ? Colors.white
                              : Colors.white.withOpacity(0.4),
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 32,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Next button (shown after at least 1 shot) ────────
                if (shots.isNotEmpty)
                  Positioned(
                    bottom: 40,
                    left: 60,
                    right: 60,
                    child: ElevatedButton(
                      onPressed: () {
                        final files = shots.map((x) => File(x.path)).toList();
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

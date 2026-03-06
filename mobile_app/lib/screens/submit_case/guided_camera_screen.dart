import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'photo_preview_screen.dart';

class GuidedCameraScreen extends StatefulWidget {
  const GuidedCameraScreen({super.key});

  @override
  State<GuidedCameraScreen> createState() => _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends State<GuidedCameraScreen> {
  CameraController? _controller;
  List<XFile> shots = [];
  bool isGuidanceOk = false;
  String guidanceText = "move closer";
  bool isCameraReady = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _startFakeGuidance();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final camera = cameras.first;

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _controller!.initialize();

    setState(() {
      isCameraReady = true;
    });
  }

  void _startFakeGuidance() {
    // MVP FAKE LOGIC
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        guidanceText = "align properly";
      });
    });

    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        guidanceText = "capture";
        isGuidanceOk = true;
      });
    });
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (shots.length >= 10) return;

    final image = await _controller!.takePicture();

    setState(() {
      shots.add(image);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isCameraReady
          ? Stack(
              children: [
                // Camera preview
                SizedBox.expand(child: CameraPreview(_controller!)),

                // Guidance banner
                Positioned(
                  top: 60,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isGuidanceOk
                                ? Icons.check_circle
                                : Icons.warning_amber_rounded,
                            color: isGuidanceOk ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Text(guidanceText),
                        ],
                      ),
                    ),
                  ),
                ),

                // Thumbnail preview
                // Thumbnail preview — tap to preview
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
                        // Small preview icon hint
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

                // Capture button
                Positioned(
                  bottom: 120,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: isGuidanceOk ? _takePicture : null,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isGuidanceOk
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

                // Next button
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
                      child: const Text("next"),
                    ),
                  ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

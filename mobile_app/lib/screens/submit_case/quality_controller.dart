import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

// ─────────────────────────────────────────────
// 1. QualityResult — what the UI reads
// ─────────────────────────────────────────────
class QualityResult {
  final bool brightnessOk;
  final bool sharpnessOk;
  final bool distanceOk;
  final String guidance;
  final double brightnessValue; // for debugging / display
  final double sharpnessValue; // for debugging / display

  const QualityResult({
    required this.brightnessOk,
    required this.sharpnessOk,
    required this.distanceOk,
    required this.guidance,
    required this.brightnessValue,
    required this.sharpnessValue,
  });

  // ✅ All checks passed
  bool get allOk => brightnessOk && sharpnessOk && distanceOk;

  // Default "not ready" state shown before first frame is analysed
  factory QualityResult.initial() => const QualityResult(
    brightnessOk: false,
    sharpnessOk: false,
    distanceOk: false,
    guidance: 'Point camera at the damage',
    brightnessValue: 0,
    sharpnessValue: 0,
  );
}

// ─────────────────────────────────────────────
// 2. Thresholds — tweak these for your needs
// ─────────────────────────────────────────────
class _Thresholds {
  // Brightness: Y-plane average (0–255)
  static const double minBrightness = 60.0; // below = too dark
  static const double maxBrightness = 210.0; // above = too bright

  // Sharpness: Laplacian variance on downscaled image
  // Higher = sharper. Tune this based on testing.
  static const double minSharpness = 80.0;

  // Distance: bounding box width as fraction of frame width
  // 0.35 = object must cover at least 35% of the frame width
  static const double minObjectFraction = 0.35;
}

// ─────────────────────────────────────────────
// 3. QualityController — the main class
// ─────────────────────────────────────────────
class QualityController {
  // Throttle: minimum gap between analyses
  DateTime? _lastAnalysisTime;
  static const int _throttleMs = 250;

  // ML Kit object detector (used every 5th frame only)
  late final ObjectDetector _objectDetector;

  // Frame counter — used to skip ML Kit on most frames
  int _frameCount = 0;

  // Whether ML Kit is currently running (prevent overlap)
  bool _isDetecting = false;

  // Last known distance result (reused between ML Kit frames)
  bool _lastDistanceOk = false;

  // Stream controller — UI listens to this
  final _resultController = StreamController<QualityResult>.broadcast();
  Stream<QualityResult> get stream => _resultController.stream;

  // ── Init ──────────────────────────────────────────────────────────
  QualityController() {
    _initObjectDetector();
  }

  void _initObjectDetector() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream, // optimised for live frames
      classifyObjects: false, // we don't need labels, just bbox
      multipleObjects: false, // we only care about the main object
    );
    _objectDetector = ObjectDetector(options: options);
  }

  // ── Main entry point — call this from CameraController.startImageStream ──
  Future<void> processFrame(CameraImage frame, int sensorOrientation) async {
    // ✅ Throttle — skip frame if less than 250ms since last analysis
    final now = DateTime.now();
    if (_lastAnalysisTime != null &&
        now.difference(_lastAnalysisTime!).inMilliseconds < _throttleMs) {
      return;
    }
    _lastAnalysisTime = now;

    _frameCount++;

    // ── A. Brightness (every frame, very cheap) ──────────────────────
    final brightness = _calculateBrightness(frame);
    final brightnessOk =
        brightness >= _Thresholds.minBrightness &&
        brightness <= _Thresholds.maxBrightness;

    // ── B. Sharpness (every frame on downscaled image) ───────────────
    final sharpness = await _calculateSharpness(frame);
    final sharpnessOk = sharpness >= _Thresholds.minSharpness;

    // ── C. Distance via ML Kit (every 5th frame only) ────────────────
    if (_frameCount % 5 == 0 && !_isDetecting) {
      _isDetecting = true;
      _runObjectDetection(frame, sensorOrientation).then((distanceOk) {
        _lastDistanceOk = distanceOk;
        _isDetecting = false;
      });
    }

    // ── D. Build result and emit ─────────────────────────────────────
    final result = QualityResult(
      brightnessOk: brightnessOk,
      sharpnessOk: sharpnessOk,
      distanceOk: _lastDistanceOk,
      guidance: _buildGuidance(
        brightnessOk,
        sharpnessOk,
        _lastDistanceOk,
        brightness,
      ),
      brightnessValue: brightness,
      sharpnessValue: sharpness,
    );

    if (!_resultController.isClosed) {
      _resultController.add(result);
    }
  }

  // ─────────────────────────────────────────────
  // A. Brightness — reads Y-plane average
  // ─────────────────────────────────────────────
  double _calculateBrightness(CameraImage frame) {
    // The Y-plane is the first plane in YUV420 format
    // Each byte = brightness of one pixel (0 = black, 255 = white)
    final yPlane = frame.planes[0].bytes;

    // Sample every 10th pixel for speed (still accurate enough)
    int total = 0;
    int count = 0;
    for (int i = 0; i < yPlane.length; i += 10) {
      total += yPlane[i];
      count++;
    }

    return count > 0 ? total / count : 0.0;
  }

  // ─────────────────────────────────────────────
  // B. Sharpness — Laplacian variance in Dart
  // ─────────────────────────────────────────────
  Future<double> _calculateSharpness(CameraImage frame) async {
    // Run in an isolate so it doesn't block the UI thread
    return await Isolate.run(() => _laplacianVariance(frame));
  }

  static double _laplacianVariance(CameraImage frame) {
    final yPlane = frame.planes[0].bytes;
    final width = frame.width;
    final height = frame.height;

    // Step 1: Downsample to 100x100 for speed
    // We manually pick pixels at even intervals
    const targetSize = 100;
    final xStep = width ~/ targetSize;
    final yStep = height ~/ targetSize;

    // Step 2: Build a small greyscale image from sampled pixels
    final pixels = img.Image(width: targetSize, height: targetSize);
    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final srcX = x * xStep;
        final srcY = y * yStep;
        final pixelIndex = srcY * width + srcX;
        if (pixelIndex < yPlane.length) {
          final grey = yPlane[pixelIndex];
          pixels.setPixelRgb(x, y, grey, grey, grey);
        }
      }
    }

    // Step 3: Apply Laplacian kernel:
    // [ 0,  1,  0]
    // [ 1, -4,  1]
    // [ 0,  1,  0]
    // This highlights edges — high values = sharp edges
    final List<double> laplacianValues = [];

    for (int y = 1; y < targetSize - 1; y++) {
      for (int x = 1; x < targetSize - 1; x++) {
        final center = pixels.getPixel(x, y).r.toDouble();
        final top = pixels.getPixel(x, y - 1).r.toDouble();
        final bottom = pixels.getPixel(x, y + 1).r.toDouble();
        final left = pixels.getPixel(x - 1, y).r.toDouble();
        final right = pixels.getPixel(x + 1, y).r.toDouble();

        final laplacian = (top + bottom + left + right) - (4 * center);
        laplacianValues.add(laplacian);
      }
    }

    // Step 4: Calculate variance of Laplacian values
    // High variance = sharp image, low variance = blurry
    if (laplacianValues.isEmpty) return 0.0;

    final mean =
        laplacianValues.reduce((a, b) => a + b) / laplacianValues.length;
    final variance =
        laplacianValues
            .map((v) => (v - mean) * (v - mean))
            .reduce((a, b) => a + b) /
        laplacianValues.length;

    return variance;
  }

  // ─────────────────────────────────────────────
  // C. Distance — ML Kit Object Detection
  // ─────────────────────────────────────────────
  Future<bool> _runObjectDetection(
    CameraImage frame,
    int sensorOrientation,
  ) async {
    try {
      // Convert CameraImage to InputImage for ML Kit
      final inputImage = _cameraImageToInputImage(frame, sensorOrientation);
      if (inputImage == null) return _lastDistanceOk;

      final objects = await _objectDetector.processImage(inputImage);
      if (objects.isEmpty) return false;

      // Find the largest detected object
      final frameWidth = frame.width.toDouble();
      final largestObject = objects.reduce(
        (a, b) => a.boundingBox.width > b.boundingBox.width ? a : b,
      );

      // Check if it covers enough of the frame
      final fraction = largestObject.boundingBox.width / frameWidth;
      return fraction >= _Thresholds.minObjectFraction;
    } catch (e) {
      return _lastDistanceOk; // keep last known value on error
    }
  }

  InputImage? _cameraImageToInputImage(
    CameraImage frame,
    int sensorOrientation,
  ) {
    // Map sensor orientation to ML Kit rotation
    final rotation = _rotationFromSensorOrientation(sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(frame.format.raw);
    if (format == null) return null;

    return InputImage.fromBytes(
      bytes: frame.planes[0].bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: frame.planes[0].bytesPerRow,
      ),
    );
  }

  InputImageRotation? _rotationFromSensorOrientation(int orientation) {
    switch (orientation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return null;
    }
  }

  // ─────────────────────────────────────────────
  // D. Guidance message — priority order
  // ─────────────────────────────────────────────
  String _buildGuidance(
    bool brightnessOk,
    bool sharpnessOk,
    bool distanceOk,
    double brightness,
  ) {
    if (!brightnessOk) {
      return brightness < _Thresholds.minBrightness
          ? 'Too dark — move to better lighting'
          : 'Too bright — avoid direct light';
    }
    if (!sharpnessOk) return 'Hold still — image is blurry';
    if (!distanceOk) return 'Move closer to the vehicle';
    return 'Good — hold still...';
  }

  // ─────────────────────────────────────────────
  // E. Cleanup
  // ─────────────────────────────────────────────
  void dispose() {
    _objectDetector.close();
    _resultController.close();
  }
}

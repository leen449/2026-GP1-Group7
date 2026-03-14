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
  final double brightnessValue;
  final double sharpnessValue;

  const QualityResult({
    required this.brightnessOk,
    required this.sharpnessOk,
    required this.distanceOk,
    required this.guidance,
    required this.brightnessValue,
    required this.sharpnessValue,
  });

  bool get allOk => brightnessOk && sharpnessOk && distanceOk;

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
// 2. Thresholds — tightened for better quality
// ─────────────────────────────────────────────
class _Thresholds {
  // ✅ Tighter brightness range for better exposure
  static const double minBrightness = 80.0; // was 60
  static const double maxBrightness = 190.0; // was 210

  // ✅ Higher sharpness requirement
  static const double minSharpness = 120.0; // was 80

  // Distance fraction (ML Kit fallback handles this)
  static const double minObjectFraction = 0.02;
}

// ─────────────────────────────────────────────
// 3. QualityController
// ─────────────────────────────────────────────
class QualityController {
  // Throttle
  DateTime? _lastAnalysisTime;
  static const int _throttleMs = 250;

  // ML Kit
  late final ObjectDetector _objectDetector;
  int _frameCount = 0;
  bool _isDetecting = false;
  bool _lastDistanceOk = false;

  // ✅ Fallback counter — 20 frames × 250ms = 5 seconds before fallback
  int _framesWithNoDetection = 0;
  static const int _noDetectionFallbackFrames =
      20; // was 12 (~3s), now 20 (~5s)

  // Tracks whether ML Kit detected something (vs nothing at all)
  bool _mlKitDetectedSomething = false;

  // Stream
  final _resultController = StreamController<QualityResult>.broadcast();
  Stream<QualityResult> get stream => _resultController.stream;

  QualityController() {
    _initObjectDetector();
  }

  void _initObjectDetector() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: false,
      multipleObjects: false,
    );
    _objectDetector = ObjectDetector(options: options);
  }

  // ── Main entry point ──────────────────────────────────────────────
  Future<void> processFrame(CameraImage frame, int sensorOrientation) async {
    final now = DateTime.now();
    if (_lastAnalysisTime != null &&
        now.difference(_lastAnalysisTime!).inMilliseconds < _throttleMs) {
      return;
    }
    _lastAnalysisTime = now;

    _frameCount++;

    // ── A. Brightness ────────────────────────────────────────────────
    final brightness = _calculateBrightness(frame);
    final brightnessOk =
        brightness >= _Thresholds.minBrightness &&
        brightness <= _Thresholds.maxBrightness;

    // ── B. Sharpness ─────────────────────────────────────────────────
    final sharpness = await _calculateSharpness(frame);
    final sharpnessOk = sharpness >= _Thresholds.minSharpness;

    // ── C. Distance via ML Kit (every 5th frame only) ────────────────
    if (_frameCount % 5 == 0 && !_isDetecting) {
      _isDetecting = true;
      _runObjectDetection(frame, sensorOrientation).then((result) {
        final detected = result['detected'] as bool;
        final distanceOk = result['distanceOk'] as bool;

        if (detected) {
          _mlKitDetectedSomething = true;
          _lastDistanceOk = distanceOk;
          _framesWithNoDetection = 0;
        } else {
          _mlKitDetectedSomething = false;
          _framesWithNoDetection++;
          // ✅ After 5 seconds of no detection, assume close enough
          if (_framesWithNoDetection >= _noDetectionFallbackFrames) {
            _lastDistanceOk = true;
          }
        }

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
  // A. Brightness
  // ─────────────────────────────────────────────
  double _calculateBrightness(CameraImage frame) {
    final yPlane = frame.planes[0].bytes;
    int total = 0;
    int count = 0;
    for (int i = 0; i < yPlane.length; i += 10) {
      total += yPlane[i];
      count++;
    }
    return count > 0 ? total / count : 0.0;
  }

  // ─────────────────────────────────────────────
  // B. Sharpness
  // ─────────────────────────────────────────────
  Future<double> _calculateSharpness(CameraImage frame) async {
    return await Isolate.run(() => _laplacianVariance(frame));
  }

  static double _laplacianVariance(CameraImage frame) {
    final yPlane = frame.planes[0].bytes;
    final width = frame.width;
    final height = frame.height;

    const targetSize = 100;
    final xStep = width ~/ targetSize;
    final yStep = height ~/ targetSize;

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
  // C. Distance — ML Kit
  // Returns Map with 'detected' and 'distanceOk'
  // ─────────────────────────────────────────────
  Future<Map<String, bool>> _runObjectDetection(
    CameraImage frame,
    int sensorOrientation,
  ) async {
    try {
      final inputImage = _cameraImageToInputImage(frame, sensorOrientation);
      if (inputImage == null) {
        return {'detected': false, 'distanceOk': false};
      }

      final objects = await _objectDetector.processImage(inputImage);

      if (objects.isEmpty) {
        return {'detected': false, 'distanceOk': false};
      }

      final frameWidth = frame.width.toDouble();
      final largestObject = objects.reduce(
        (a, b) => a.boundingBox.width > b.boundingBox.width ? a : b,
      );
      final fraction = largestObject.boundingBox.width / frameWidth;
      final distanceOk = fraction >= _Thresholds.minObjectFraction;

      return {'detected': true, 'distanceOk': distanceOk};
    } catch (e) {
      return {'detected': false, 'distanceOk': false};
    }
  }

  InputImage? _cameraImageToInputImage(
    CameraImage frame,
    int sensorOrientation,
  ) {
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
  // D. Guidance message
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
    // Only show "move closer" when ML Kit detected something too small
    // not when it detected nothing (= user is already very close)
    if (!distanceOk && _mlKitDetectedSomething) {
      return 'Move closer to the vehicle';
    }
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

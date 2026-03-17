import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

// ─────────────────────────────────────────────────────────────────────
// QualityResult
// ─────────────────────────────────────────────────────────────────────
class QualityResult {
  final bool brightnessOk;
  final bool sharpnessOk;
  final bool distanceOk;
  final String guidance;
  final double brightnessValue;
  final double sharpnessValue;
  final double overexposedPercentage;
  final double adaptiveThreshold;

  const QualityResult({
    required this.brightnessOk,
    required this.sharpnessOk,
    required this.distanceOk,
    required this.guidance,
    required this.brightnessValue,
    required this.sharpnessValue,
    required this.overexposedPercentage,
    required this.adaptiveThreshold,
  });

  bool get allOk => brightnessOk && sharpnessOk && distanceOk;

  factory QualityResult.initial() => const QualityResult(
    brightnessOk: false,
    sharpnessOk: false,
    distanceOk: false,
    guidance: 'Point camera at the damage',
    brightnessValue: 0,
    sharpnessValue: 0,
    overexposedPercentage: 0,
    adaptiveThreshold: 0,
  );
}

// ─────────────────────────────────────────────────────────────────────
// BrightnessMetrics
// ─────────────────────────────────────────────────────────────────────
class _BrightnessMetrics {
  final double average;
  final double overexposedPercentage;
  const _BrightnessMetrics(this.average, this.overexposedPercentage);
}

// ─────────────────────────────────────────────────────────────────────
// Thresholds
// ─────────────────────────────────────────────────────────────────────
class _Thresholds {
  // Brightness
  static const double minBrightness = 80.0;
  static const double maxBrightness = 190.0;
  static const int overexposedPixelValue = 240;
  static const double maxOverexposedPixelPercentage = 0.05;

  // FFT sharpness ratio (0.0–1.0)
  static const double minFftSharpness = 0.08;

  // Distance: vehicle must cover at least 50% of frame width
  // This ensures user is close to the damage, not just near the car
  static const double minVehicleFraction = 0.50;

  // Brightness change that indicates camera has moved significantly
  // Used to reset distance fallback
  static const double brightnessMovementDelta = 15.0;
}

// ─────────────────────────────────────────────────────────────────────
// QualityController
// ─────────────────────────────────────────────────────────────────────
class QualityController {
  // Throttle — main analysis
  DateTime? _lastAnalysisTime;
  static const int _throttleMs = 350;

  // ML Kit — separate throttle so it never blocks brightness/sharpness
  DateTime? _lastMlKitTime;
  static const int _mlKitThrottleMs = 1500; // run ML Kit every 1.5 seconds
  late final ObjectDetector _objectDetector;
  bool _isDetecting = false;
  bool _lastDistanceOk = false;
  int _framesWithNoDetection = 0;
  // Fallback: after 5 seconds of no vehicle detected → assume close enough
  static const int _noDetectionFallbackFrames = 4; // 4 × 1.5s = 6s
  bool _mlKitDetectedVehicle = false;

  // Heavy analysis (FFT) every 3rd throttled frame
  int _heavyCounter = 0;
  double _lastSharpness = 0;

  // Track brightness to detect camera movement → reset distance
  double _lastBrightness = 0;

  // Frame counter
  int _frameCount = 0;

  // Stream
  final _resultController = StreamController<QualityResult>.broadcast();
  Stream<QualityResult> get stream => _resultController.stream;

  QualityController() {
    _initObjectDetector();
  }

  void _initObjectDetector() {
    // ✅ DetectionMode.single — for per-frame analysis, no tracking overhead
    // ✅ classifyObjects: true — enables vehicle/car/transport labels
    // ✅ multipleObjects: true — detect all, then filter for vehicle
    final options = ObjectDetectorOptions(
      mode: DetectionMode.single,
      classifyObjects: true,
      multipleObjects: true,
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
    _heavyCounter++;

    // ── A. Brightness (~0.5ms) ────────────────────────────────────────
    final metrics = _calculateBrightnessMetrics(frame.planes[0].bytes);
    final brightnessOk =
        metrics.average >= _Thresholds.minBrightness &&
        metrics.average <= _Thresholds.maxBrightness &&
        metrics.overexposedPercentage <=
            _Thresholds.maxOverexposedPixelPercentage;

    // ✅ Detect significant camera movement via brightness change
    // If brightness changed a lot → user moved → reset distance fallback
    if (_lastBrightness != 0 &&
        (metrics.average - _lastBrightness).abs() >
            _Thresholds.brightnessMovementDelta) {
      _framesWithNoDetection = 0;
      _lastDistanceOk = false;
      _mlKitDetectedVehicle = false;
    }
    _lastBrightness = metrics.average;

    // ── B. FFT Sharpness (every 3rd frame, ~5ms) ──────────────────────
    if (_heavyCounter % 3 == 0) {
      try {
        _lastSharpness = _computeFftSharpness(
          frame.planes[0].bytes,
          frame.width,
          frame.height,
        );
      } catch (e) {
        // Keep last known value on error
      }
    }
    final sharpnessOk = _lastSharpness >= _Thresholds.minFftSharpness;

    // ── C. ML Kit Distance (every 1.5 seconds, non-blocking) ──────────
    // Runs completely independently — doesn't delay brightness/sharpness
    final nowMlKit = DateTime.now();
    if (!_isDetecting &&
        (_lastMlKitTime == null ||
            nowMlKit.difference(_lastMlKitTime!).inMilliseconds >=
                _mlKitThrottleMs)) {
      _lastMlKitTime = nowMlKit;
      _isDetecting = true;
      // Fire and forget — result updates on next frame
      _runVehicleDetection(frame, sensorOrientation).then((result) {
        final vehicleFound = result['vehicleFound'] as bool;
        final distanceOk = result['distanceOk'] as bool;

        if (vehicleFound) {
          _mlKitDetectedVehicle = true;
          _lastDistanceOk = distanceOk;
          _framesWithNoDetection = 0;
        } else {
          _mlKitDetectedVehicle = false;
          _framesWithNoDetection++;
          // Fallback after ~6 seconds of no vehicle detected
          if (_framesWithNoDetection >= _noDetectionFallbackFrames) {
            _lastDistanceOk = true;
          }
        }
        _isDetecting = false;
      });
    }

    // ── D. Emit result ────────────────────────────────────────────────
    final result = QualityResult(
      brightnessOk: brightnessOk,
      sharpnessOk: sharpnessOk,
      distanceOk: _lastDistanceOk,
      guidance: _buildGuidance(
        brightnessOk,
        sharpnessOk,
        _lastDistanceOk,
        _mlKitDetectedVehicle,
        metrics.average,
        metrics.overexposedPercentage,
      ),
      brightnessValue: metrics.average,
      sharpnessValue: _lastSharpness,
      overexposedPercentage: metrics.overexposedPercentage,
      adaptiveThreshold: _Thresholds.minFftSharpness,
    );

    if (!_resultController.isClosed) {
      _resultController.add(result);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // A. Brightness
  // ─────────────────────────────────────────────────────────────────
  _BrightnessMetrics _calculateBrightnessMetrics(Uint8List yPlane) {
    int total = 0;
    int count = 0;
    int overexposedCount = 0;
    for (int i = 0; i < yPlane.length; i += 20) {
      final pixel = yPlane[i];
      total += pixel;
      count++;
      if (pixel >= _Thresholds.overexposedPixelValue) overexposedCount++;
    }
    return _BrightnessMetrics(
      count > 0 ? total / count : 0.0,
      count > 0 ? overexposedCount / count : 0.0,
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // B. FFT Sharpness
  // High-frequency energy ratio — higher = sharper
  // ─────────────────────────────────────────────────────────────────
  double _computeFftSharpness(Uint8List yBytes, int width, int height) {
    const n = 64;
    final xStep = width ~/ n;
    final yStep = height ~/ n;

    final real = List<double>.filled(n * n, 0.0);
    final imag = List<double>.filled(n * n, 0.0);

    for (int row = 0; row < n; row++) {
      for (int col = 0; col < n; col++) {
        final idx = (row * yStep) * width + (col * xStep);
        if (idx < yBytes.length) {
          real[row * n + col] = yBytes[idx] / 255.0;
        }
      }
    }

    for (int row = 0; row < n; row++) {
      final rRow = real.sublist(row * n, row * n + n);
      final iRow = imag.sublist(row * n, row * n + n);
      _fft1d(rRow, iRow);
      for (int col = 0; col < n; col++) {
        real[row * n + col] = rRow[col];
        imag[row * n + col] = iRow[col];
      }
    }

    for (int col = 0; col < n; col++) {
      final rCol = List<double>.generate(n, (r) => real[r * n + col]);
      final iCol = List<double>.generate(n, (r) => imag[r * n + col]);
      _fft1d(rCol, iCol);
      for (int row = 0; row < n; row++) {
        real[row * n + col] = rCol[row];
        imag[row * n + col] = iCol[row];
      }
    }

    double totalEnergy = 0.0;
    double highFreqEnergy = 0.0;
    final halfN = n ~/ 2;
    final highFreqCut = n ~/ 4;

    for (int row = 0; row < n; row++) {
      for (int col = 0; col < n; col++) {
        final r = real[row * n + col];
        final im = imag[row * n + col];
        final mag = r * r + im * im;
        totalEnergy += mag;
        final fr = (row < halfN ? row : n - row).toDouble();
        final fc = (col < halfN ? col : n - col).toDouble();
        if (sqrt(fr * fr + fc * fc) > highFreqCut) {
          highFreqEnergy += mag;
        }
      }
    }

    return totalEnergy == 0 ? 0.0 : highFreqEnergy / totalEnergy;
  }

  void _fft1d(List<double> real, List<double> imag) {
    final n = real.length;
    if (n <= 1) return;
    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) j ^= bit;
      j ^= bit;
      if (i < j) {
        final tr = real[i];
        real[i] = real[j];
        real[j] = tr;
        final ti = imag[i];
        imag[i] = imag[j];
        imag[j] = ti;
      }
    }
    for (int len = 2; len <= n; len <<= 1) {
      final ang = -2 * pi / len;
      final wRe = cos(ang);
      final wIm = sin(ang);
      for (int i = 0; i < n; i += len) {
        double curRe = 1.0, curIm = 0.0;
        for (int k = 0; k < len ~/ 2; k++) {
          final uRe = real[i + k];
          final uIm = imag[i + k];
          final vRe =
              real[i + k + len ~/ 2] * curRe - imag[i + k + len ~/ 2] * curIm;
          final vIm =
              real[i + k + len ~/ 2] * curIm + imag[i + k + len ~/ 2] * curRe;
          real[i + k] = uRe + vRe;
          imag[i + k] = uIm + vIm;
          real[i + k + len ~/ 2] = uRe - vRe;
          imag[i + k + len ~/ 2] = uIm - vIm;
          final newRe = curRe * wRe - curIm * wIm;
          curIm = curRe * wIm + curIm * wRe;
          curRe = newRe;
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // C. Vehicle Detection via ML Kit
  // ✅ Uses classification to filter for vehicle-related objects only
  // ✅ Checks if vehicle covers 50%+ of frame width
  // ─────────────────────────────────────────────────────────────────
  Future<Map<String, bool>> _runVehicleDetection(
    CameraImage frame,
    int sensorOrientation,
  ) async {
    try {
      final inputImage = _cameraImageToInputImage(frame, sensorOrientation);
      if (inputImage == null) {
        return {'vehicleFound': false, 'distanceOk': false};
      }

      final objects = await _objectDetector.processImage(inputImage);
      if (objects.isEmpty) {
        return {'vehicleFound': false, 'distanceOk': false};
      }

      // ✅ Filter for vehicle-related objects using classification labels
      final vehicleKeywords = [
        'vehicle',
        'car',
        'automobile',
        'transport',
        'truck',
        'van',
        'suv',
        'sedan',
        'wheel',
        'tire',
      ];

      final vehicleObjects = objects.where((obj) {
        if (obj.labels.isEmpty) return false;
        return obj.labels.any((label) {
          final text = label.text.toLowerCase();
          return vehicleKeywords.any((kw) => text.contains(kw));
        });
      }).toList();

      // If no vehicle label found, fall back to largest object
      // (covers cases where ML Kit doesn't classify but detects something)
      final candidates = vehicleObjects.isNotEmpty ? vehicleObjects : objects;

      final frameWidth = frame.width.toDouble();
      final largest = candidates.reduce(
        (a, b) => a.boundingBox.width > b.boundingBox.width ? a : b,
      );

      final fraction = largest.boundingBox.width / frameWidth;

      print(
        '🔍 ML Kit: ${candidates.length} object(s), '
        'largest=${(fraction * 100).toStringAsFixed(0)}% of frame'
        '${vehicleObjects.isNotEmpty ? " (vehicle label)" : " (no label)"}',
      );

      return {
        'vehicleFound': true,
        'distanceOk': fraction >= _Thresholds.minVehicleFraction,
      };
    } catch (e) {
      print('❌ ML Kit error: $e');
      return {'vehicleFound': false, 'distanceOk': false};
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

  // ─────────────────────────────────────────────────────────────────
  // D. Guidance
  // ─────────────────────────────────────────────────────────────────
  String _buildGuidance(
    bool brightnessOk,
    bool sharpnessOk,
    bool distanceOk,
    bool vehicleDetected,
    double brightness,
    double overexposedPct,
  ) {
    if (!brightnessOk) {
      if (brightness < _Thresholds.minBrightness) {
        return 'Too dark — move to better lighting';
      } else if (overexposedPct > _Thresholds.maxOverexposedPixelPercentage) {
        return 'Too bright — reduce direct light or adjust angle';
      } else {
        return 'Too bright — avoid direct light';
      }
    }

    if (!sharpnessOk) return 'Hold still — image is blurry';

    if (!distanceOk) {
      // ✅ Specific message based on whether vehicle was detected
      if (vehicleDetected) {
        return 'Move closer to the damage area';
      } else {
        return 'Point camera at the vehicle damage';
      }
    }

    return 'Good — tap to capture';
  }

  // ─────────────────────────────────────────────────────────────────
  // E. Cleanup
  // ─────────────────────────────────────────────────────────────────
  void dispose() {
    _objectDetector.close();
    _resultController.close();
  }
}

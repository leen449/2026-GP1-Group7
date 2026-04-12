import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';

// ─────────────────────────────────────────────────────────────────────
// QualityResult — what the UI reads
// ML Kit removed — distance check replaced with simple frame coverage
// ─────────────────────────────────────────────────────────────────────
class QualityResult {
  final bool brightnessOk;
  final bool sharpnessOk;
  final String guidance;
  final double brightnessValue;
  final double sharpnessValue;
  final double overexposedPercentage;

  const QualityResult({
    required this.brightnessOk,
    required this.sharpnessOk,
    required this.guidance,
    required this.brightnessValue,
    required this.sharpnessValue,
    required this.overexposedPercentage,
  });

  // ✅ No more distanceOk — ML Kit removed from real-time stream
  bool get allOk => brightnessOk && sharpnessOk;

  factory QualityResult.initial() => const QualityResult(
    brightnessOk: false,
    sharpnessOk: false,
    guidance: 'Point camera at the damage',
    brightnessValue: 0,
    sharpnessValue: 0,
    overexposedPercentage: 0,
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
  static const double minBrightness = 80.0;
  static const double maxBrightness = 190.0;
  static const int overexposedPixelValue = 240;
  static const double maxOverexposedPixelPercentage = 0.05;
  static const double minFftSharpness = 0.08;
}

// ─────────────────────────────────────────────────────────────────────
// QualityController — brightness + FFT sharpness only
// ML Kit object detection moved to post-capture ImageValidator
// ─────────────────────────────────────────────────────────────────────
class QualityController {
  DateTime? _lastAnalysisTime;
  static const int _throttleMs = 350;

  int _heavyCounter = 0;
  double _lastSharpness = 0;

  final _resultController = StreamController<QualityResult>.broadcast();
  Stream<QualityResult> get stream => _resultController.stream;

  // ── Main entry point ──────────────────────────────────────────────
  Future<void> processFrame(CameraImage frame, int sensorOrientation) async {
    final now = DateTime.now();
    if (_lastAnalysisTime != null &&
        now.difference(_lastAnalysisTime!).inMilliseconds < _throttleMs) {
      return;
    }
    _lastAnalysisTime = now;
    _heavyCounter++;

    // ── A. Brightness (~0.5ms) ────────────────────────────────────
    final metrics = _calculateBrightnessMetrics(frame.planes[0].bytes);
    final brightnessOk =
        metrics.average >= _Thresholds.minBrightness &&
        metrics.average <= _Thresholds.maxBrightness &&
        metrics.overexposedPercentage <=
            _Thresholds.maxOverexposedPixelPercentage;

    // ── B. FFT sharpness every 3rd frame (~5ms) ───────────────────
    if (_heavyCounter % 3 == 0) {
      try {
        _lastSharpness = _computeFftSharpness(
          frame.planes[0].bytes,
          frame.width,
          frame.height,
        );
      } catch (_) {
        // keep last known value
      }
    }
    final sharpnessOk = _lastSharpness >= _Thresholds.minFftSharpness;

    // ── C. Emit ───────────────────────────────────────────────────
    if (!_resultController.isClosed) {
      _resultController.add(
        QualityResult(
          brightnessOk: brightnessOk,
          sharpnessOk: sharpnessOk,
          guidance: _buildGuidance(
            brightnessOk,
            sharpnessOk,
            metrics.average,
            metrics.overexposedPercentage,
          ),
          brightnessValue: metrics.average,
          sharpnessValue: _lastSharpness,
          overexposedPercentage: metrics.overexposedPercentage,
        ),
      );
    }
  }

  // ── A. Brightness ─────────────────────────────────────────────────
  _BrightnessMetrics _calculateBrightnessMetrics(Uint8List yPlane) {
    int total = 0, count = 0, overexposedCount = 0;
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

  // ── B. FFT sharpness ──────────────────────────────────────────────
  double _computeFftSharpness(Uint8List yBytes, int width, int height) {
    const n = 64;
    final xStep = width ~/ n;
    final yStep = height ~/ n;

    final real = List<double>.filled(n * n, 0.0);
    final imag = List<double>.filled(n * n, 0.0);

    for (int row = 0; row < n; row++) {
      for (int col = 0; col < n; col++) {
        final idx = (row * yStep) * width + (col * xStep);
        if (idx < yBytes.length) real[row * n + col] = yBytes[idx] / 255.0;
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

    double totalEnergy = 0.0, highFreqEnergy = 0.0;
    final halfN = n ~/ 2, highFreqCut = n ~/ 4;

    for (int row = 0; row < n; row++) {
      for (int col = 0; col < n; col++) {
        final r = real[row * n + col], im = imag[row * n + col];
        final mag = r * r + im * im;
        totalEnergy += mag;
        final fr = (row < halfN ? row : n - row).toDouble();
        final fc = (col < halfN ? col : n - col).toDouble();
        if (sqrt(fr * fr + fc * fc) > highFreqCut) highFreqEnergy += mag;
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
      final wRe = cos(ang), wIm = sin(ang);
      for (int i = 0; i < n; i += len) {
        double curRe = 1.0, curIm = 0.0;
        for (int k = 0; k < len ~/ 2; k++) {
          final uRe = real[i + k], uIm = imag[i + k];
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

  // ── C. Guidance ───────────────────────────────────────────────────
  String _buildGuidance(
    bool brightnessOk,
    bool sharpnessOk,
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
    return 'Good — tap to capture';
  }

  void dispose() => _resultController.close();
}

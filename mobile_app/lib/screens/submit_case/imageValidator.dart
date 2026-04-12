import 'dart:io';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

// ─────────────────────────────────────────────────────────────────────
// ImageValidationStatus
// ─────────────────────────────────────────────────────────────────────
enum ImageValidationStatus { valid, uncertain, pending }

// ─────────────────────────────────────────────────────────────────────
// ImageValidationResult
// ─────────────────────────────────────────────────────────────────────
class ImageValidationResult {
  final File image;
  final ImageValidationStatus status;
  final String? detectedLabel;

  const ImageValidationResult({
    required this.image,
    required this.status,
    this.detectedLabel,
  });

  bool get isValid => status == ImageValidationStatus.valid;
  bool get isUncertain => status == ImageValidationStatus.uncertain;
  bool get isPending => status == ImageValidationStatus.pending;

  factory ImageValidationResult.pending(File image) => ImageValidationResult(
    image: image,
    status: ImageValidationStatus.pending,
  );
}

// ─────────────────────────────────────────────────────────────────────
// ImageValidator
// ─────────────────────────────────────────────────────────────────────
class ImageValidator {
  // Persistent detector (performance optimization)
  static final ObjectDetector _detector = ObjectDetector(
    options: ObjectDetectorOptions(
      mode: DetectionMode.single,
      classifyObjects: true,
      multipleObjects: true,
    ),
  );

  // Strong keywords (only used as bonus signal)
  static const List<String> _strongVehicleKeywords = [
    'vehicle',
    'car',
    'transport',
  ];

  // ───────────────────────────────────────────────────────────────────
  // Validate single image
  // ───────────────────────────────────────────────────────────────────
  static Future<ImageValidationResult> validateImage(File image) async {
    try {
      final inputImage = InputImage.fromFile(image);
      final objects = await _detector.processImage(inputImage);

      // ❌ Nothing detected → suspicious
      if (objects.isEmpty) {
        return ImageValidationResult(
          image: image,
          status: ImageValidationStatus.uncertain,
          detectedLabel: 'no objects',
        );
      }

      int totalLabels = 0;
      int vehicleMatches = 0;

      for (final obj in objects) {
        totalLabels += obj.labels.length;

        for (final label in obj.labels) {
          final text = label.text.toLowerCase();

          if (text.contains('vehicle') ||
              text.contains('car') ||
              text.contains('transport')) {
            vehicleMatches++;
          }
        }
      }

      // 🎯 Strong vehicle signal
      if (vehicleMatches > 0) {
        return ImageValidationResult(
          image: image,
          status: ImageValidationStatus.valid,
          detectedLabel: 'vehicle detected',
        );
      }

      // 🧠 Weak signal (object exists but not clear)
      if (totalLabels > 0) {
        return ImageValidationResult(
          image: image,
          status: ImageValidationStatus.uncertain,
          detectedLabel: 'object detected',
        );
      }

      // fallback
      return ImageValidationResult(
        image: image,
        status: ImageValidationStatus.uncertain,
        detectedLabel: 'unknown',
      );
    } catch (e) {
      return ImageValidationResult(
        image: image,
        status: ImageValidationStatus.uncertain,
        detectedLabel: 'error',
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────
  // Validate all images (progressive)
  // ───────────────────────────────────────────────────────────────────
  static Future<List<ImageValidationResult>> validateAll({
    required List<File> images,
    void Function(int index, ImageValidationResult result)? onProgress,
  }) async {
    final results = <ImageValidationResult>[];

    for (int i = 0; i < images.length; i++) {
      final result = await validateImage(images[i]);
      results.add(result);
      onProgress?.call(i, result);
    }

    return results;
  }

  // ───────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────
  static bool allUncertain(List<ImageValidationResult> results) {
    if (results.isEmpty) return false;
    return results.every((r) => r.isUncertain);
  }

  static int countValid(List<ImageValidationResult> results) =>
      results.where((r) => r.isValid).length;

  static int countUncertain(List<ImageValidationResult> results) =>
      results.where((r) => r.isUncertain).length;
}

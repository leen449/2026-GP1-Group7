import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

class CloudinaryService {
  // ── Load credentials from .env ────────────────────────────────────
  static String get _cloudName => dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
  static String get _uploadPreset =>
      dotenv.env['CLOUDINARY_UPLOAD_PRESET'] ?? '';

  // ── Base URLs ─────────────────────────────────────────────────────
  static String get _imageUploadUrl =>
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload';
  // ─────────────────────────────────────────────────────────────────
  // Upload a single image (JPG/PNG)
  // Returns the secure download URL or null on failure
  // ─────────────────────────────────────────────────────────────────
  static Future<String?> uploadImage({
    required File imageFile,
    required String caseId,
    required int imageIndex,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_imageUploadUrl));

      // ── Credentials ──────────────────────────────────────────────
      request.fields['upload_preset'] = _uploadPreset;

      // ── Organise files in folders by case ────────────────────────
      // Result: accident_cases/caseId/image_0, image_1, etc.
      request.fields['folder'] = 'accident_cases/$caseId';
      request.fields['public_id'] = 'image_$imageIndex';

      // ── Attach the file ──────────────────────────────────────────
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      // ── Send ─────────────────────────────────────────────────────
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final json = jsonDecode(responseBody);
        final url = json['secure_url'] as String?;
        print('✅ Image uploaded: $url');
        return url;
      } else {
        print('❌ Image upload failed: ${response.statusCode} $responseBody');
        return null;
      }
    } catch (e) {
      print('❌ Image upload error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // PDF upload via Cloudinary is disabled —
  // Cloudinary free plan blocks raw file delivery.
  // PDFs are stored as base64 in Firestore instead.
  // Re-enable this when Firebase Storage billing is set up.
  // ─────────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────
  // Upload all images for a case at once
  // Returns a list of URLs in the same order as the input files
  // ─────────────────────────────────────────────────────────────────
  static Future<List<String>> uploadAllImages({
    required List<File> images,
    required String caseId,
  }) async {
    final List<String> urls = [];

    for (int i = 0; i < images.length; i++) {
      final url = await uploadImage(
        imageFile: images[i],
        caseId: caseId,
        imageIndex: i,
      );
      if (url != null) {
        urls.add(url);
      } else {
        // If any upload fails, we still continue with the rest
        print('⚠️ Image $i failed to upload, skipping');
      }
    }

    return urls;
  }
}

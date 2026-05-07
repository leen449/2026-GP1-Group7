import 'dart:convert';
import 'package:http/http.dart' as http;

class OcrService {
  // Base URL for the FastAPI backend
  // Use 10.0.2.2 for Android emulator (maps to localhost on the host machine)
  static const String _baseUrl = 'http://192.168.0.12:8000';
  // static const String _baseUrl = 'http://127.0.0.1:8000'; // iOS simulator
  // static const String _baseUrl = 'http://192.168.0.250:8000'; // physical device

  /// Sends the cropped registration card image to the OCR API.
  /// Returns a map of extracted vehicle fields ready to fill the form.
  static Future<Map<String, String>> scanCard(String imagePath) async {
    try {
      final uri = Uri.parse('$_baseUrl/ocr/');

      // Use multipart request to send the image as a file upload
      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('file', imagePath));

      // Wait up to 30 seconds for the OCR response
      final response = await request.send().timeout(
        const Duration(seconds: 150),
      );

      if (response.statusCode == 200) {
        final body = await response.stream.bytesToString();
        final json = jsonDecode(body);

        // Extract the structured data object from the API response
        final data = json['data'] as Map<String, dynamic>;

        // Map API response keys → controller-friendly keys
        // Note: API uses spaces in keys (e.g. 'plate number'), we use camelCase
        return {
          'plateNumber': data['plateNumber'] ?? '',
          'make': data['make'] ?? '',
          'model': data['model'] ?? '',
          'year': data['year'] ?? '',
          'color': data['color'] ?? '',
          'chassisNumber': data['chassisNumber'] ?? '',
        };
      } else {
        throw Exception('Server returned status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('OCR request failed: $e');
    }
  }
}

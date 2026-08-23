import 'dart:convert';

import 'package:http/http.dart' as http;

class ReportResult {
  final bool created;
  final String reportId;
  final String reportNumber;
  final String pdfUrl;
  final String? verifyUrl;

  const ReportResult({
    required this.created,
    required this.reportId,
    required this.reportNumber,
    required this.pdfUrl,
    this.verifyUrl,
  });

  factory ReportResult.fromJson(Map<String, dynamic> json) {
    return ReportResult(
      created: json['created'] == true,
      reportId: json['reportId']?.toString() ?? '',
      reportNumber: json['reportNumber']?.toString() ?? '',
      pdfUrl: json['pdfUrl']?.toString() ?? '',
      verifyUrl: json['verifyUrl']?.toString(),
    );
  }
}

class ReportService {
  // نفس عنوان الباك إند.
  // نعدله لاحقًا إذا تغير الـIP أو صار عندكم رابط نشر حقيقي.
  static const String _baseUrl = 'http://172.20.10.2:8000';

  static Future<ReportResult> generateReport({required String caseId}) async {
    final cleanedCaseId = caseId.trim();

    if (cleanedCaseId.isEmpty) {
      throw Exception('رقم الطلب غير موجود');
    }

    final uri = Uri.parse('$_baseUrl/reports/cases/$cleanedCaseId/generate');

    try {
      final response = await http
          .post(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 60));

      Map<String, dynamic> responseData = {};

      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          responseData = decoded;
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final result = ReportResult.fromJson(responseData);

        if (result.pdfUrl.isEmpty) {
          throw Exception('تم إنشاء التقرير ولكن رابط الملف غير موجود');
        }

        return result;
      }

      final detail = responseData['detail'];

      throw Exception(
        detail?.toString() ??
            'تعذر إنشاء التقرير، رمز الخطأ: ${response.statusCode}',
      );
    } on FormatException {
      throw Exception('استجابة الباك إند غير صحيحة');
    } on http.ClientException {
      throw Exception('تعذر الاتصال بالخادم');
    } catch (error) {
      final message = error.toString();

      if (message.startsWith('Exception: ')) {
        throw Exception(message.replaceFirst('Exception: ', ''));
      }

      throw Exception('حدث خطأ أثناء إنشاء التقرير');
    }
  }
}

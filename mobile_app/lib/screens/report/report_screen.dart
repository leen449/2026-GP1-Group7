import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

class ReportScreen extends StatelessWidget {
  final String pdfUrl;
  final String reportNumber;

  const ReportScreen({
    super.key,
    required this.pdfUrl,
    required this.reportNumber,
  });

  // Same colors used in SubmitObjectionScreen
  static const Color primaryColor = Color(0xFF2563EB);
  static const Color darkTextColor = Color(0xFF111827);
  static const Color backgroundColor = Color(0xFFF8FAFC);

  Future<void> _downloadReport(BuildContext context) async {
    final uri = Uri.tryParse(pdfUrl);

    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'رابط التقرير غير صحيح',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
      return;
    }

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر فتح التقرير',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.white,
          centerTitle: true,
          automaticallyImplyLeading: false,

          // Same back arrow style as SubmitObjectionScreen
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: darkTextColor,
            ),
          ),

          // Download stays on the opposite side
          actions: [
            IconButton(
              tooltip: 'تنزيل التقرير',
              onPressed: () => _downloadReport(context),
              icon: const Icon(
                Icons.download_rounded,
                color: primaryColor,
              ),
            ),
          ],

          title: Text(
            reportNumber.isEmpty ? 'التقرير' : reportNumber,
            style: const TextStyle(
              color: darkTextColor,
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),

        body: SfPdfViewer.network(
          pdfUrl,
          canShowScrollHead: false,
          canShowScrollStatus: false,
          enableDoubleTapZooming: true,
          onDocumentLoadFailed: (details) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'تعذر تحميل التقرير: ${details.description}',
                  textDirection: TextDirection.rtl,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
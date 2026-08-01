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

  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);

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
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
  backgroundColor: _pageBg,
  elevation: 0,
  automaticallyImplyLeading: false,

  leading: IconButton(
    tooltip: 'تنزيل التقرير',
    icon: const Icon(
      Icons.download_rounded,
      color: _textDark,
    ),
    onPressed: () => _downloadReport(context),
  ),

  actions: [
    IconButton(
      icon: const Icon(
        Icons.arrow_forward_ios_rounded,
        color: _textDark,
      ),
      onPressed: () => Navigator.pop(context),
    ),
  ],

  title: Text(
    reportNumber.isEmpty ? 'التقرير' : reportNumber,
    style: const TextStyle(
      color: _textDark,
      fontWeight: FontWeight.w800,
      fontSize: 18,
    ),
  ),

  centerTitle: true,
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
    );
  }
}
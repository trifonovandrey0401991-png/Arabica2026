import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'rko_reports_service.dart';

/// Страница просмотра PDF РКО
class RKOPDFViewerPage extends StatelessWidget {
  final String fileName;

  const RKOPDFViewerPage({
    super.key,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    final pdfUrl = RKOReportsService.getPDFUrl(fileName);

    return Scaffold(
      appBar: AppBar(
        title: Text(fileName),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: SfPdfViewer.network(
        pdfUrl,
        onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
          print('Ошибка загрузки PDF: ${details.error}');
          print('Описание: ${details.description}');
        },
      ),
    );
  }
}


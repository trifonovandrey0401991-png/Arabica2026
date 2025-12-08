import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'rko_reports_service.dart';

/// Страница просмотра PDF РКО
class RKOPDFViewerPage extends StatefulWidget {
  final String fileName;

  const RKOPDFViewerPage({
    super.key,
    required this.fileName,
  });

  @override
  State<RKOPDFViewerPage> createState() => _RKOPDFViewerPageState();
}

class _RKOPDFViewerPageState extends State<RKOPDFViewerPage> {
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final pdfUrl = RKOReportsService.getPDFUrl(widget.fileName);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName.length > 30 
            ? '${widget.fileName.substring(0, 30)}...' 
            : widget.fileName,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Ошибка загрузки PDF',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                      });
                    },
                    child: const Text('Попробовать снова'),
                  ),
                ],
              ),
            )
          : SfPdfViewer.network(
              pdfUrl,
              onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                print('Ошибка загрузки PDF: ${details.error}');
                print('Описание: ${details.description}');
                if (mounted) {
                  setState(() {
                    _errorMessage = details.description ?? 'Не удалось загрузить документ';
                  });
                }
              },
            ),
    );
  }
}


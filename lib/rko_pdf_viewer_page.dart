import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'rko_reports_service.dart';

/// Страница просмотра РКО (PDF или DOCX)
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
  bool _isLoading = false;

  bool get _isDocx => widget.fileName.toLowerCase().endsWith('.docx');
  bool get _isPdf => widget.fileName.toLowerCase().endsWith('.pdf');

  Future<void> _openDocx() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final fileUrl = RKOReportsService.getPDFUrl(widget.fileName);
      final uri = Uri.parse(fileUrl);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Не удалось открыть файл');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка открытия файла: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileUrl = RKOReportsService.getPDFUrl(widget.fileName);

    // Для .docx файлов открываем через системное приложение
    if (_isDocx) {
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
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Ошибка открытия файла',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                          onPressed: _openDocx,
                          child: const Text('Попробовать снова'),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.description, size: 80, color: Color(0xFF004D40)),
                        const SizedBox(height: 24),
                        const Text(
                          'Файл Word (.docx)',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            widget.fileName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: _openDocx,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Открыть в приложении'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF004D40),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
      );
    }

    // Для PDF файлов используем встроенный просмотрщик
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
                  const Text(
                    'Ошибка загрузки PDF',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              fileUrl,
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


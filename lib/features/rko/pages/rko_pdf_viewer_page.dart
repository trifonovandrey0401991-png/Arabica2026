import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:open_file/open_file.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../services/rko_reports_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

// http оставлен для скачивания binary файлов (DOCX/PDF) с сервера

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

  @override
  void initState() {
    super.initState();
    // Автоматически открываем .docx файл при загрузке страницы
    if (_isDocx) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openDocx();
      });
    }
  }

  Future<void> _openDocx() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final fileUrl = RKOReportsService.getPDFUrl(widget.fileName);
      Logger.info('Скачиваем файл: $fileUrl');

      // Скачиваем файл
      final response = await http.get(Uri.parse(fileUrl), headers: ApiConstants.headersWithApiKey);
      if (response.statusCode != 200) {
        throw Exception('Ошибка скачивания файла: ${response.statusCode}');
      }
      
      // Сохраняем во временную директорию
      final directory = await getTemporaryDirectory();
      final filePath = path.join(directory.path, widget.fileName);
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      Logger.success('Файл сохранен: $filePath');

      // Открываем файл через системное приложение
      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done) {
        throw Exception('Не удалось открыть файл: ${result.message}. Установите приложение для просмотра Word документов.');
      }
      Logger.success('Файл открыт в системном приложении');
    } catch (e) {
      Logger.error('Ошибка открытия файла', e);
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
          backgroundColor: AppColors.primaryGreen,
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red),
                        SizedBox(height: 16),
                        Text(
                          'Ошибка открытия файла',
                          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32.w),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14.sp),
                          ),
                        ),
                        SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _openDocx,
                          child: Text('Попробовать снова'),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.description, size: 80, color: AppColors.primaryGreen),
                        SizedBox(height: 24),
                        Text(
                          'Файл Word (.docx)',
                          style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 16),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32.w),
                          child: Text(
                            widget.fileName,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14.sp),
                          ),
                        ),
                        SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: _openDocx,
                          icon: Icon(Icons.open_in_new),
                          label: Text('Открыть в приложении'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
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
        backgroundColor: AppColors.primaryGreen,
      ),
      body: _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    'Ошибка загрузки PDF',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32.w),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14.sp),
                    ),
                  ),
                  SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                      });
                    },
                    child: Text('Попробовать снова'),
                  ),
                ],
              ),
            )
          : SfPdfViewer.network(
              fileUrl,
              onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                Logger.error('Ошибка загрузки PDF: ${details.error}', details.description);
                if (mounted) {
                  setState(() {
                    _errorMessage = details.description;
                  });
                }
              },
            ),
    );
  }
}

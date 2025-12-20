import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'shift_report_model.dart';
import 'google_drive_service.dart';
import 'shift_photo_gallery_page.dart';

/// Страница просмотра отчета пересменки
class ShiftReportViewPage extends StatefulWidget {
  final ShiftReport report;

  const ShiftReportViewPage({
    super.key,
    required this.report,
  });

  @override
  State<ShiftReportViewPage> createState() => _ShiftReportViewPageState();
}

class _ShiftReportViewPageState extends State<ShiftReportViewPage> {
  late ShiftReport _currentReport;

  @override
  void initState() {
    super.initState();
    _currentReport = widget.report;
  }

  Future<void> _confirmReport() async {
    final confirmedReport = _currentReport.copyWith(confirmedAt: DateTime.now());
    await ShiftReport.updateReport(confirmedReport);
    setState(() {
      _currentReport = confirmedReport;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Отчет подтвержден'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчет пересменки'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Информация об отчете
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Магазин: ${_currentReport.shopAddress}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Сотрудник: ${_currentReport.employeeName}'),
                          Text(
                            'Дата: ${_currentReport.createdAt.day}.${_currentReport.createdAt.month}.${_currentReport.createdAt.year} '
                            '${_currentReport.createdAt.hour}:${_currentReport.createdAt.minute.toString().padLeft(2, '0')}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Ответы на вопросы
                  ..._currentReport.answers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final answer = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Вопрос ${index + 1}: ${answer.question}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (answer.textAnswer != null)
                        Text('Ответ: ${answer.textAnswer}'),
                      if (answer.numberAnswer != null)
                        Text('Ответ: ${answer.numberAnswer}'),
                      if (answer.photoPath != null || answer.photoDriveId != null) ...[
                        const SizedBox(height: 8),
                        // Если есть эталонное фото, показываем две фото рядом
                        if (answer.referencePhotoUrl != null)
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Эталон',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      height: 200,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.grey),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          answer.referencePhotoUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const Center(
                                              child: Icon(Icons.error),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Сделано сотрудником',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ShiftPhotoGalleryPage(
                                              reports: [_currentReport],
                                              initialIndex: index,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        height: 200,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.grey),
                                        ),
                                        child: answer.photoPath != null
                                            ? (kIsWeb || answer.photoPath!.startsWith('data:') || answer.photoPath!.startsWith('http'))
                                                ? Image.network(
                                                    answer.photoPath!,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context, error, stackTrace) {
                                                      return const Center(
                                                        child: Icon(Icons.error),
                                                      );
                                                    },
                                                  )
                                                : Image.file(
                                                    File(answer.photoPath!),
                                                    fit: BoxFit.cover,
                                                  )
                                            : answer.photoDriveId != null
                                                ? FutureBuilder<String>(
                                                    future: Future.value(GoogleDriveService.getPhotoUrl(answer.photoDriveId!)),
                                                    builder: (context, snapshot) {
                                                      if (snapshot.hasData) {
                                                        return Image.network(
                                                          snapshot.data!,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (context, error, stackTrace) {
                                                            return const Center(
                                                              child: Icon(Icons.error),
                                                            );
                                                          },
                                                        );
                                                      }
                                                      return const Center(
                                                        child: CircularProgressIndicator(),
                                                      );
                                                    },
                                                  )
                                                : const Center(
                                                    child: Icon(Icons.image),
                                                  ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          // Если нет эталонного фото, показываем только сделанное фото
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ShiftPhotoGalleryPage(
                                    reports: [_currentReport],
                                    initialIndex: index,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              height: 200,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey),
                              ),
                              child: answer.photoPath != null
                                  ? (kIsWeb || answer.photoPath!.startsWith('data:') || answer.photoPath!.startsWith('http'))
                                      ? Image.network(
                                          answer.photoPath!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const Center(
                                              child: Icon(Icons.error),
                                            );
                                          },
                                        )
                                      : Image.file(
                                          File(answer.photoPath!),
                                          fit: BoxFit.cover,
                                        )
                                  : answer.photoDriveId != null
                                      ? FutureBuilder<String>(
                                          future: Future.value(GoogleDriveService.getPhotoUrl(answer.photoDriveId!)),
                                          builder: (context, snapshot) {
                                            if (snapshot.hasData) {
                                              return Image.network(
                                                snapshot.data!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return const Center(
                                                    child: Icon(Icons.error),
                                                  );
                                                },
                                              );
                                            }
                                            return const Center(
                                              child: CircularProgressIndicator(),
                                            );
                                          },
                                        )
                                      : const Center(
                                          child: Icon(Icons.image),
                                        ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              );
            }),
                ],
              ),
            ),
            // Кнопка подтверждения внизу
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
              ),
              child: SafeArea(
                child: _currentReport.isConfirmed
                    ? Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Отчет подтвержден',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _confirmReport,
                          icon: const Icon(Icons.check_circle, size: 24),
                          label: const Text(
                            'Подтвердить',
                            style: TextStyle(fontSize: 18),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF004D40),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


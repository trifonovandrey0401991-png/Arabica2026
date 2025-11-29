import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'shift_report_model.dart';
import 'google_drive_service.dart';
import 'shift_photo_gallery_page.dart';

/// Страница просмотра отчета пересменки
class ShiftReportViewPage extends StatelessWidget {
  final ShiftReport report;

  const ShiftReportViewPage({
    super.key,
    required this.report,
  });

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
                      'Магазин: ${report.shopAddress}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Сотрудник: ${report.employeeName}'),
                    Text(
                      'Дата: ${report.createdAt.day}.${report.createdAt.month}.${report.createdAt.year} '
                      '${report.createdAt.hour}:${report.createdAt.minute.toString().padLeft(2, '0')}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Ответы на вопросы
            ...report.answers.asMap().entries.map((entry) {
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
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ShiftPhotoGalleryPage(
                                  reports: [report],
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
    );
  }
}


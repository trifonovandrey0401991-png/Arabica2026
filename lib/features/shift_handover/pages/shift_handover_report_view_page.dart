import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/shift_handover_report_model.dart';
import '../../../core/services/photo_upload_service.dart';

/// Страница просмотра отчета сдачи смены
class ShiftHandoverReportViewPage extends StatefulWidget {
  final ShiftHandoverReport report;

  const ShiftHandoverReportViewPage({
    super.key,
    required this.report,
  });

  @override
  State<ShiftHandoverReportViewPage> createState() => _ShiftHandoverReportViewPageState();
}

class _ShiftHandoverReportViewPageState extends State<ShiftHandoverReportViewPage> {
  late ShiftHandoverReport _currentReport;

  @override
  void initState() {
    super.initState();
    _currentReport = widget.report;
  }

  Future<void> _confirmReport() async {
    final confirmedReport = ShiftHandoverReport(
      id: _currentReport.id,
      employeeName: _currentReport.employeeName,
      shopAddress: _currentReport.shopAddress,
      createdAt: _currentReport.createdAt,
      answers: _currentReport.answers,
      isSynced: _currentReport.isSynced,
      confirmedAt: DateTime.now(),
    );

    await ShiftHandoverReport.saveLocal(confirmedReport);

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
        title: const Text('Отчет сдачи смены'),
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
                      if (answer.photoPath != null || answer.photoUrl != null) ...[
                        const SizedBox(height: 8),
                        // Если есть эталонное фото, показываем две фото рядом
                        Builder(
                          builder: (context) {
                            if (answer.referencePhotoUrl != null) {
                              return Row(
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
                                              loadingBuilder: (context, child, loadingProgress) {
                                                if (loadingProgress == null) return child;
                                                return const Center(
                                                  child: CircularProgressIndicator(),
                                                );
                                              },
                                              errorBuilder: (context, error, stackTrace) {
                                                return const Center(
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(Icons.error, size: 48),
                                                      SizedBox(height: 8),
                                                      Text('Ошибка загрузки\nэталонного фото',
                                                        textAlign: TextAlign.center,
                                                        style: TextStyle(fontSize: 12)),
                                                    ],
                                                  ),
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
                                    Container(
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
                                          : answer.photoUrl != null
                                              ? Image.network(
                                                  answer.photoUrl!,
                                                  fit: BoxFit.cover,
                                                  loadingBuilder: (context, child, loadingProgress) {
                                                    if (loadingProgress == null) return child;
                                                    return const Center(
                                                      child: CircularProgressIndicator(),
                                                    );
                                                  },
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return const Center(
                                                      child: Column(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          Icon(Icons.error, size: 48),
                                                          SizedBox(height: 8),
                                                          Text('Ошибка загрузки фото', style: TextStyle(fontSize: 12)),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                )
                                              : const Center(
                                                  child: Icon(Icons.image),
                                                ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                            } else {
                              return const SizedBox.shrink();
                            }
                          },
                        ),
                        if (answer.referencePhotoUrl == null)
                          // Если нет эталонного фото, показываем только сделанное фото
                          Container(
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
                                : answer.photoUrl != null
                                    ? Image.network(
                                        answer.photoUrl!,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return const Center(
                                            child: CircularProgressIndicator(),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          return const Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.error, size: 48),
                                                SizedBox(height: 8),
                                                Text('Ошибка загрузки фото', style: TextStyle(fontSize: 12)),
                                              ],
                                            ),
                                          );
                                        },
                                      )
                                    : const Center(
                                        child: Icon(Icons.image),
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

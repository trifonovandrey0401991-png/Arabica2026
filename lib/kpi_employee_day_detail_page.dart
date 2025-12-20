import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'kpi_models.dart';
import 'recount_service.dart';
import 'recount_report_model.dart';
import 'shift_report_service.dart';
import 'shift_report_model.dart';
import 'rko_reports_service.dart';
import 'google_drive_service.dart';
import 'utils/logger.dart';

/// Детальная страница одного дня работы сотрудника в магазине
class KPIEmployeeDayDetailPage extends StatefulWidget {
  final KPIEmployeeShopDayData shopDayData;

  const KPIEmployeeDayDetailPage({
    super.key,
    required this.shopDayData,
  });

  @override
  State<KPIEmployeeDayDetailPage> createState() => _KPIEmployeeDayDetailPageState();
}

class _KPIEmployeeDayDetailPageState extends State<KPIEmployeeDayDetailPage> {
  RecountReport? _recountReport;
  ShiftReport? _shiftReport;
  bool _isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoadingDetails = true);

    try {
      // Загружаем отчет пересчета, если есть ID
      if (widget.shopDayData.recountReportId != null) {
        try {
          final recounts = await RecountService.getReports(
            employeeName: widget.shopDayData.employeeName,
          );
          try {
            _recountReport = recounts.firstWhere(
              (r) => r.id == widget.shopDayData.recountReportId,
            );
          } catch (e) {
            Logger.debug('Отчет пересчета с ID ${widget.shopDayData.recountReportId} не найден');
          }
        } catch (e) {
          Logger.error('Ошибка загрузки отчета пересчета', e);
        }
      }

      // Загружаем отчет пересменки, если есть ID
      if (widget.shopDayData.shiftReportId != null) {
        try {
          final shifts = await ShiftReportService.getReports(
            employeeName: widget.shopDayData.employeeName,
          );
          try {
            _shiftReport = shifts.firstWhere(
              (s) => s.id == widget.shopDayData.shiftReportId,
            );
          } catch (e) {
            Logger.debug('Отчет пересменки с ID ${widget.shopDayData.shiftReportId} не найден');
          }
        } catch (e) {
          Logger.error('Ошибка загрузки отчета пересменки', e);
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки деталей', e);
    } finally {
      if (mounted) {
        setState(() => _isLoadingDetails = false);
      }
    }
  }

  Future<void> _downloadRKO() async {
    if (widget.shopDayData.rkoFileName == null) return;

    try {
      const serverUrl = 'https://arabica26.ru';
      final url = '$serverUrl/api/rko/file/${Uri.encodeComponent(widget.shopDayData.rkoFileName!)}';
      final uri = Uri.parse(url);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось открыть файл РКО')),
          );
        }
      }
    } catch (e) {
      Logger.error('Ошибка открытия РКО', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка при открытии файла РКО')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.shopDayData.displayTitle),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoadingDetails
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Статусы выполнения
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Статусы выполнения',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildStatusRow(
                            'Приход на работу',
                            widget.shopDayData.attendanceTime != null,
                            widget.shopDayData.formattedAttendanceTime ?? 'не отмечен',
                          ),
                          const Divider(),
                          _buildStatusRow(
                            'Пересменка',
                            widget.shopDayData.hasShift,
                            widget.shopDayData.hasShift ? 'выполнена' : 'не выполнена',
                          ),
                          const Divider(),
                          _buildStatusRow(
                            'Пересчет товара',
                            widget.shopDayData.hasRecount,
                            widget.shopDayData.hasRecount ? 'выполнен' : 'не выполнен',
                          ),
                          const Divider(),
                          _buildStatusRow(
                            'РКО',
                            widget.shopDayData.hasRKO,
                            widget.shopDayData.hasRKO ? 'сдано' : 'не сдано',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Время прихода
                  if (widget.shopDayData.attendanceTime != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.access_time, color: Color(0xFF004D40)),
                        title: const Text('Время прихода'),
                        subtitle: Text(
                          widget.shopDayData.formattedAttendanceTime ?? '',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  
                  // РКО
                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.receipt_long,
                        color: widget.shopDayData.hasRKO
                            ? Colors.green
                            : Colors.grey,
                      ),
                      title: const Text('РКО'),
                      subtitle: widget.shopDayData.hasRKO
                          ? Text(widget.shopDayData.rkoFileName ?? 'Файл не найден')
                          : const Text('РКО не сдано'),
                      trailing: widget.shopDayData.hasRKO && widget.shopDayData.rkoFileName != null
                          ? IconButton(
                              icon: const Icon(Icons.download),
                              onPressed: _downloadRKO,
                            )
                          : null,
                    ),
                  ),
                  
                  // Отчет пересчета
                  Card(
                    child: ExpansionTile(
                      leading: Icon(
                        Icons.inventory,
                        color: widget.shopDayData.hasRecount
                            ? Colors.green
                            : Colors.grey,
                      ),
                      title: const Text('Отчет пересчета'),
                      subtitle: widget.shopDayData.hasRecount
                          ? const Text('Нажмите для просмотра')
                          : const Text('Пересчет не выполнен'),
                      initiallyExpanded: widget.shopDayData.hasRecount && _recountReport != null,
                      children: [
                        if (widget.shopDayData.hasRecount)
                          _buildRecountReport(_recountReport)
                        else
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              'Отчет пересчета отсутствует',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Отчет пересменки
                  Card(
                    child: ExpansionTile(
                      leading: Icon(
                        Icons.work_history,
                        color: widget.shopDayData.hasShift
                            ? Colors.green
                            : Colors.grey,
                      ),
                      title: const Text('Отчет пересменки'),
                      subtitle: widget.shopDayData.hasShift
                          ? const Text('Нажмите для просмотра')
                          : const Text('Пересменка не выполнена'),
                      initiallyExpanded: widget.shopDayData.hasShift && _shiftReport != null,
                      children: [
                        if (widget.shopDayData.hasShift)
                          _buildShiftReport(_shiftReport)
                        else
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              'Отчет пересменки отсутствует',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusRow(String label, bool isCompleted, String status) {
    return Row(
      children: [
        Icon(
          isCompleted ? Icons.check_circle : Icons.cancel,
          color: isCompleted ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecountReport(RecountReport? report) {
    if (report == null) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'Отчет пересчета не найден',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ID отчета: ${report.id}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          if (report.answers.isEmpty)
            const Text(
              'Нет ответов в отчете',
              style: TextStyle(color: Colors.grey),
            )
          else
            ...report.answers.map((answer) => Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Card(
                    color: Colors.grey[100],
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (answer.question != null)
                            Text(
                              'Вопрос: ${answer.question}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          if (answer.answer != null) ...[
                            const SizedBox(height: 4),
                            Text('Ответ: ${answer.answer}'),
                          ],
                          if (answer.quantity != null) ...[
                            const SizedBox(height: 4),
                            Text('Количество: ${answer.quantity}'),
                          ],
                          if (answer.actualBalance != null) ...[
                            const SizedBox(height: 4),
                            Text('Фактический остаток: ${answer.actualBalance}'),
                          ],
                          if (answer.programBalance != null) ...[
                            const SizedBox(height: 4),
                            Text('Остаток в программе: ${answer.programBalance}'),
                          ],
                          if (answer.difference != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Разница: ${answer.difference}',
                              style: TextStyle(
                                color: answer.difference! > 0
                                    ? Colors.red
                                    : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                          if (answer.photoUrl != null) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Фото прикреплено',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildShiftReport(ShiftReport? report) {
    if (report == null) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'Отчет пересменки не найден',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ID отчета: ${report.id}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          if (report.answers.isEmpty)
            const Text(
              'Нет ответов в отчете',
              style: TextStyle(color: Colors.grey),
            )
          else
            ...report.answers.map((answer) => Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Card(
                    color: Colors.grey[100],
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Вопрос: ${answer.question}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (answer.textAnswer != null) ...[
                            const SizedBox(height: 4),
                            Text('Ответ: ${answer.textAnswer}'),
                          ],
                          if (answer.numberAnswer != null) ...[
                            const SizedBox(height: 4),
                            Text('Ответ (число): ${answer.numberAnswer}'),
                          ],
                          if (answer.photoPath != null || answer.photoDriveId != null) ...[
                            const SizedBox(height: 8),
                            // Если есть эталонное фото, показываем две фото рядом
                            if (answer.referencePhotoUrl != null) ...[
                              const Text(
                                'Фото:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Эталон',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          height: 100,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(
                                              answer.referencePhotoUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                return const Center(
                                                  child: Icon(Icons.error, size: 24),
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
                                          'Сделано',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          height: 100,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: answer.photoPath != null
                                                ? (kIsWeb || answer.photoPath!.startsWith('data:') || answer.photoPath!.startsWith('http'))
                                                    ? Image.network(
                                                        answer.photoPath!,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (context, error, stackTrace) {
                                                          print('❌ Ошибка загрузки фото сотрудника: $error');
                                                          return const Center(
                                                            child: Icon(Icons.error, size: 24),
                                                          );
                                                        },
                                                      )
                                                    : Image.file(
                                                        File(answer.photoPath!),
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (context, error, stackTrace) {
                                                          print('❌ Ошибка загрузки локального фото: $error');
                                                          return const Center(
                                                            child: Icon(Icons.error, size: 24),
                                                          );
                                                        },
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
                                                                print('❌ Ошибка загрузки фото из Google Drive: $error, URL: ${snapshot.data}');
                                                                return const Center(
                                                                  child: Icon(Icons.error, size: 24),
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
                                                        child: Icon(Icons.image, size: 24),
                                                      ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              // Если нет эталонного фото, показываем только сделанное фото
                              Container(
                                height: 200,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: answer.photoPath != null
                                      ? (kIsWeb || answer.photoPath!.startsWith('data:') || answer.photoPath!.startsWith('http'))
                                          ? Image.network(
                                              answer.photoPath!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                print('❌ Ошибка загрузки фото сотрудника: $error');
                                                return const Center(
                                                  child: Icon(Icons.error, size: 64),
                                                );
                                              },
                                            )
                                          : Image.file(
                                              File(answer.photoPath!),
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                print('❌ Ошибка загрузки локального фото: $error');
                                                return const Center(
                                                  child: Icon(Icons.error, size: 64),
                                                );
                                              },
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
                                                      print('❌ Ошибка загрузки фото из Google Drive: $error, URL: ${snapshot.data}');
                                                      return const Center(
                                                        child: Icon(Icons.error, size: 64),
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
                                              child: Icon(Icons.image, size: 64),
                                            ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}


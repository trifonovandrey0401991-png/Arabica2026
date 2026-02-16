import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../models/kpi_models.dart';
import '../../recount/services/recount_service.dart';
import '../../recount/models/recount_report_model.dart';
import '../../shifts/services/shift_report_service.dart';
import '../../shifts/models/shift_report_model.dart';
import '../../../core/services/photo_upload_service.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
      Logger.debug('📄 Попытка загрузки РКО: ${widget.shopDayData.rkoFileName}');
      final serverUrl = 'https://arabica26.ru';
      // Используем query параметр вместо path параметра для правильной обработки кириллицы
      final uri = Uri.parse('$serverUrl/api/rko/download').replace(
        queryParameters: {'fileName': widget.shopDayData.rkoFileName!},
      );
      Logger.debug('📄 URL РКО: $uri');
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось открыть файл РКО')),
          );
        }
      }
    } catch (e) {
      Logger.error('Ошибка открытия РКО', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при открытии файла РКО')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.shopDayData.displayTitle),
        backgroundColor: Color(0xFF004D40),
      ),
      body: _isLoadingDetails
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.0.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Статусы выполнения
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Статусы выполнения',
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 16),
                          _buildStatusRow(
                            'Приход на работу',
                            widget.shopDayData.attendanceTime != null,
                            widget.shopDayData.formattedAttendanceTime ?? 'не отмечен',
                          ),
                          Divider(),
                          _buildStatusRow(
                            'Пересменка',
                            widget.shopDayData.hasShift,
                            widget.shopDayData.hasShift ? 'выполнена' : 'не выполнена',
                          ),
                          Divider(),
                          _buildStatusRow(
                            'Пересчет товара',
                            widget.shopDayData.hasRecount,
                            widget.shopDayData.hasRecount ? 'выполнен' : 'не выполнен',
                          ),
                          Divider(),
                          _buildStatusRow(
                            'РКО',
                            widget.shopDayData.hasRKO,
                            widget.shopDayData.hasRKO ? 'сдано' : 'не сдано',
                          ),
                          Divider(),
                          _buildStatusRow(
                            'Конверт',
                            widget.shopDayData.hasEnvelope,
                            widget.shopDayData.hasEnvelope ? 'сформирован' : 'не сформирован',
                          ),
                          Divider(),
                          _buildStatusRow(
                            'Сдача смены',
                            widget.shopDayData.hasShiftHandover,
                            widget.shopDayData.hasShiftHandover ? 'сдана' : 'не сдана',
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  
                  // Время прихода
                  if (widget.shopDayData.attendanceTime != null)
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.access_time, color: Color(0xFF004D40)),
                        title: Text('Время прихода'),
                        subtitle: Text(
                          widget.shopDayData.formattedAttendanceTime ?? '',
                          style: TextStyle(
                            fontSize: 18.sp,
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
                      title: Text('РКО'),
                      subtitle: widget.shopDayData.hasRKO
                          ? Text(widget.shopDayData.rkoFileName ?? 'Файл не найден')
                          : Text('РКО не сдано'),
                      trailing: widget.shopDayData.hasRKO && widget.shopDayData.rkoFileName != null
                          ? IconButton(
                              icon: Icon(Icons.download),
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
                      title: Text('Отчет пересчета'),
                      subtitle: widget.shopDayData.hasRecount
                          ? Text('Нажмите для просмотра')
                          : Text('Пересчет не выполнен'),
                      initiallyExpanded: widget.shopDayData.hasRecount && _recountReport != null,
                      children: [
                        if (widget.shopDayData.hasRecount)
                          _buildRecountReport(_recountReport)
                        else
                          Padding(
                            padding: EdgeInsets.all(16.0.w),
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
                      title: Text('Отчет пересменки'),
                      subtitle: widget.shopDayData.hasShift
                          ? Text('Нажмите для просмотра')
                          : Text('Пересменка не выполнена'),
                      initiallyExpanded: widget.shopDayData.hasShift && _shiftReport != null,
                      children: [
                        if (widget.shopDayData.hasShift)
                          _buildShiftReport(_shiftReport)
                        else
                          Padding(
                            padding: EdgeInsets.all(16.0.w),
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
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  fontSize: 14.sp,
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
      return Padding(
        padding: EdgeInsets.all(16.0.w),
        child: Text(
          'Отчет пересчета не найден',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(16.0.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ID отчета: ${report.id}',
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          if (report.answers.isEmpty)
            Text(
              'Нет ответов в отчете',
              style: TextStyle(color: Colors.grey),
            )
          else
            ...report.answers.map((answer) => Padding(
                  padding: EdgeInsets.only(bottom: 12.0.h),
                  child: Card(
                    color: Colors.grey[100],
                    child: Padding(
                      padding: EdgeInsets.all(12.0.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Вопрос: ${answer.question}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text('Ответ: ${answer.answer}'),
                          if (answer.quantity != null) ...[
                            SizedBox(height: 4),
                            Text('Количество: ${answer.quantity}'),
                          ],
                          if (answer.actualBalance != null) ...[
                            SizedBox(height: 4),
                            Text('Фактический остаток: ${answer.actualBalance}'),
                          ],
                          if (answer.programBalance != null) ...[
                            SizedBox(height: 4),
                            Text('Остаток в программе: ${answer.programBalance}'),
                          ],
                          if (answer.difference != null) ...[
                            SizedBox(height: 4),
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
                            SizedBox(height: 8),
                            Text(
                              'Фото прикреплено',
                              style: TextStyle(
                                fontSize: 12.sp,
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
      return Padding(
        padding: EdgeInsets.all(16.0.w),
        child: Text(
          'Отчет пересменки не найден',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(16.0.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ID отчета: ${report.id}',
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          if (report.answers.isEmpty)
            Text(
              'Нет ответов в отчете',
              style: TextStyle(color: Colors.grey),
            )
          else
            ...report.answers.map((answer) => Padding(
                  padding: EdgeInsets.only(bottom: 12.0.h),
                  child: Card(
                    color: Colors.grey[100],
                    child: Padding(
                      padding: EdgeInsets.all(12.0.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Вопрос: ${answer.question}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (answer.textAnswer != null) ...[
                            SizedBox(height: 4),
                            Text('Ответ: ${answer.textAnswer}'),
                          ],
                          if (answer.numberAnswer != null) ...[
                            SizedBox(height: 4),
                            Text('Ответ (число): ${answer.numberAnswer}'),
                          ],
                          if (answer.photoPath != null || answer.photoDriveId != null) ...[
                            SizedBox(height: 8),
                            // Если есть эталонное фото, показываем две фото рядом
                            Builder(
                              builder: (context) {
                                Logger.debug('KPI: Проверка эталонного фото для вопроса "${answer.question}"');
                                Logger.debug('   referencePhotoUrl: ${answer.referencePhotoUrl}');
                                Logger.debug('   photoPath: ${answer.photoPath}');
                                Logger.debug('   photoDriveId: ${answer.photoDriveId}');

                                if (answer.referencePhotoUrl != null) {
                                  Logger.debug('Есть эталонное фото: ${answer.referencePhotoUrl}');
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Фото:',
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Эталон',
                                                  style: TextStyle(
                                                    fontSize: 10.sp,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                Container(
                                                  height: 100,
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(8.r),
                                                    border: Border.all(color: Colors.grey),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(8.r),
                                                    child: AppCachedImage(
                                                      imageUrl: answer.referencePhotoUrl!,
                                                      fit: BoxFit.cover,
                                                      errorWidget: (context, error, stackTrace) {
                                                        Logger.error('Ошибка загрузки эталонного фото, URL: ${answer.referencePhotoUrl}', error);
                                                        return Center(
                                                          child: Icon(Icons.error, size: 24),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Сделано',
                                          style: TextStyle(
                                            fontSize: 10.sp,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Container(
                                          height: 100,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8.r),
                                            border: Border.all(color: Colors.grey),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8.r),
                                            child: answer.photoPath != null
                                                ? (kIsWeb || answer.photoPath!.startsWith('data:') || answer.photoPath!.startsWith('http'))
                                                    ? AppCachedImage(
                                                        imageUrl: answer.photoPath!,
                                                        fit: BoxFit.cover,
                                                        errorWidget: (context, error, stackTrace) {
                                                          Logger.error('Ошибка загрузки фото сотрудника', error);
                                                          return Center(
                                                            child: Icon(Icons.error, size: 24),
                                                          );
                                                        },
                                                      )
                                                    : Image.file(
                                                        File(answer.photoPath!),
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (context, error, stackTrace) {
                                                          Logger.error('Ошибка загрузки локального фото', error);
                                                          return Center(
                                                            child: Icon(Icons.error, size: 24),
                                                          );
                                                        },
                                                      )
                                                : answer.photoDriveId != null
                                                    ? FutureBuilder<String>(
                                                        future: Future.value(PhotoUploadService.getPhotoUrl(answer.photoDriveId!)),
                                                        builder: (context, snapshot) {
                                                          if (snapshot.hasData) {
                                                            final photoUrl = snapshot.data!;
                                                            Logger.debug('KPI: Загрузка фото сотрудника из: $photoUrl');
                                                            return AppCachedImage(
                                                              imageUrl: photoUrl,
                                                              fit: BoxFit.cover,
                                                              errorWidget: (context, error, stackTrace) {
                                                                Logger.error('Ошибка загрузки фото из Google Drive, URL: $photoUrl, photoDriveId: ${answer.photoDriveId}', error);
                                                                return Center(
                                                                  child: Icon(Icons.error, size: 24),
                                                                );
                                                              },
                                                            );
                                                          }
                                                          return Center(
                                                            child: CircularProgressIndicator(),
                                                          );
                                                        },
                                                      )
                                                    : Center(
                                                        child: Icon(Icons.image, size: 24),
                                                      ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                                    ],
                                  );
                                } else {
                                  Logger.debug('Нет эталонного фото в ответе');
                                  return SizedBox.shrink();
                                }
                              },
                            ),
                            if (answer.referencePhotoUrl == null) ...[
                              // Если нет эталонного фото, показываем только сделанное фото
                              Container(
                                height: 200,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8.r),
                                  border: Border.all(color: Colors.grey),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8.r),
                                  child: answer.photoPath != null
                                      ? (kIsWeb || answer.photoPath!.startsWith('data:') || answer.photoPath!.startsWith('http'))
                                          ? AppCachedImage(
                                              imageUrl: answer.photoPath!,
                                              fit: BoxFit.cover,
                                              errorWidget: (context, error, stackTrace) {
                                                Logger.error('Ошибка загрузки фото сотрудника', error);
                                                return Center(
                                                  child: Icon(Icons.error, size: 64),
                                                );
                                              },
                                            )
                                          : Image.file(
                                              File(answer.photoPath!),
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                Logger.error('Ошибка загрузки локального фото', error);
                                                return Center(
                                                  child: Icon(Icons.error, size: 64),
                                                );
                                              },
                                            )
                                      : answer.photoDriveId != null
                                          ? FutureBuilder<String>(
                                              future: Future.value(PhotoUploadService.getPhotoUrl(answer.photoDriveId!)),
                                              builder: (context, snapshot) {
                                                if (snapshot.hasData) {
                                                  return AppCachedImage(
                                                    imageUrl: snapshot.data!,
                                                    fit: BoxFit.cover,
                                                    errorWidget: (context, error, stackTrace) {
                                                      Logger.error('Ошибка загрузки фото из Google Drive, URL: ${snapshot.data}', error);
                                                      return Center(
                                                        child: Icon(Icons.error, size: 64),
                                                      );
                                                    },
                                                  );
                                                }
                                                return Center(
                                                  child: CircularProgressIndicator(),
                                                );
                                              },
                                            )
                                          : Center(
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


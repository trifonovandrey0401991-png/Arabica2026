import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shift_report_model.dart';
import '../services/shift_report_service.dart';
import '../../../core/services/photo_upload_service.dart';
import 'shift_photo_gallery_page.dart';
import '../../../core/utils/logger.dart';
import 'package:arabica_app/shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница просмотра отчета пересменки
class ShiftReportViewPage extends StatefulWidget {
  final ShiftReport report;
  final bool isReadOnly;

  const ShiftReportViewPage({
    super.key,
    required this.report,
    this.isReadOnly = false,
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
    // Показываем диалог выбора оценки
    final result = await _showRatingDialog();
    if (result == null) return; // Пользователь отменил

    final int rating = result;

    try {
      // Получаем имя админа
      final prefs = await SharedPreferences.getInstance();
      final adminName = prefs.getString('currentEmployeeName') ??
                        prefs.getString('user_display_name') ??
                        'Неизвестный';

      final confirmedReport = _currentReport.copyWith(
        confirmedAt: DateTime.now(),
        rating: rating,
        confirmedByAdmin: adminName,
        status: 'confirmed',
      );

      // Сохраняем локально
      await ShiftReport.updateReport(confirmedReport);

      // Отправляем на сервер
      final serverSuccess = await ShiftReportService.updateReport(confirmedReport);

      if (!mounted) return;
      setState(() {
        _currentReport = confirmedReport;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(serverSuccess
                ? 'Отчет подтвержден с оценкой $rating'
                : 'Отчет подтвержден локально с оценкой $rating'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, st) {
      Logger.error('Ошибка подтверждения отчета пересменки', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось подтвердить отчет. Попробуйте ещё раз.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<int?> _showRatingDialog() async {
    int selectedRating = 5;

    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.emeraldDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.r),
                side: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              title: Text(
                'Оценка пересменки',
                style: TextStyle(color: Colors.white.withOpacity(0.95)),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Выберите оценку от 1 до 10:',
                    style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.7)),
                  ),
                  SizedBox(height: 20),
                  // Отображение выбранной оценки
                  Container(
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: _getRatingColor(selectedRating).withOpacity(0.85),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      '$selectedRating',
                      style: TextStyle(
                        fontSize: 48.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  // Кнопки выбора оценки
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: List.generate(10, (index) {
                      final rating = index + 1;
                      final isSelected = rating == selectedRating;
                      return InkWell(
                        onTap: () {
                          setDialogState(() {
                            selectedRating = rating;
                          });
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _getRatingColor(rating).withOpacity(0.85)
                                : Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8.r),
                            border: isSelected
                                ? Border.all(color: AppColors.gold, width: 2)
                                : Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Center(
                            child: Text(
                              '$rating',
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : Colors.white.withOpacity(0.6),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(selectedRating),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.night,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                  ),
                  child: Text(
                    'Подтвердить',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getRatingColor(int rating) {
    if (rating <= 3) return Colors.red;
    if (rating <= 5) return Colors.orange;
    if (rating <= 7) return Colors.amber;
    return Colors.green;
  }

  /// Отображение фото сотрудника с приоритетом серверного URL
  Widget _buildEmployeePhoto(dynamic answer) {
    // Приоритет 1: photoDriveId — серверный URL (работает на любом устройстве)
    if (answer.photoDriveId != null) {
      final photoUrl = answer.photoDriveId!.startsWith('http')
          ? answer.photoDriveId!
          : PhotoUploadService.getPhotoUrl(answer.photoDriveId!);
      return AppCachedImage(
        imageUrl: photoUrl,
        fit: BoxFit.cover,
        errorWidget: (context, error, stackTrace) {
          Logger.error('Ошибка загрузки фото сотрудника: URL: $photoUrl', error);
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 48, color: Colors.red.withOpacity(0.7)),
                SizedBox(height: 8),
                Text(
                  'Ошибка загрузки фото',
                  style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5)),
                ),
              ],
            ),
          );
        },
      );
    }

    // Приоритет 2: photoPath — HTTP URL или data URL
    if (answer.photoPath != null) {
      if (kIsWeb || answer.photoPath!.startsWith('data:') || answer.photoPath!.startsWith('http')) {
        return AppCachedImage(
          imageUrl: answer.photoPath!,
          fit: BoxFit.cover,
          errorWidget: (context, error, stackTrace) {
            return Center(child: Icon(Icons.error, color: Colors.red.withOpacity(0.7)));
          },
        );
      }
      // Приоритет 3: photoPath — локальный файл (только на том же устройстве)
      return Image.file(File(answer.photoPath!), fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, size: 48, color: Colors.white.withOpacity(0.3)),
                SizedBox(height: 8),
                Text('Фото на другом устройстве',
                  style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.4))),
              ],
            ),
          );
        },
      );
    }

    return Center(child: Icon(Icons.image, color: Colors.white.withOpacity(0.3)));
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 4.h),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Отчет пересменки',
              style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Магазин: ${_currentReport.shopAddress}',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.95),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Сотрудник: ${_currentReport.employeeName}',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            Builder(builder: (_) {
              final lc = _currentReport.createdAt.toLocal();
              return Text(
                'Дата: ${lc.day}.${lc.month}.${lc.year} '
                '${lc.hour}:${lc.minute.toString().padLeft(2, '0')}',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerCard(int index, dynamic answer) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Вопрос ${index + 1}: ${answer.question}',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.95),
              ),
            ),
            SizedBox(height: 8),
            if (answer.textAnswer != null)
              Text(
                'Ответ: ${answer.textAnswer}',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
            if (answer.numberAnswer != null)
              Text(
                'Ответ: ${answer.numberAnswer}',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
            if (answer.photoPath != null || answer.photoDriveId != null) ...[
              SizedBox(height: 8),
              // Если есть эталонное фото, показываем две фото рядом
              Builder(
                builder: (context) {
                  Logger.debug('Отчет: Проверка эталонного фото для вопроса "${answer.question}"');
                  Logger.debug('   referencePhotoUrl: ${answer.referencePhotoUrl}');
                  Logger.debug('   photoPath: ${answer.photoPath}');
                  Logger.debug('   photoDriveId: ${answer.photoDriveId}');

                  if (answer.referencePhotoUrl != null) {
                    Logger.success('   Есть эталонное фото: ${answer.referencePhotoUrl}');
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Эталон',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.gold.withOpacity(0.8),
                                ),
                              ),
                              SizedBox(height: 4),
                              Container(
                                height: 200,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12.r),
                                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12.r),
                                  child: AppCachedImage(
                                    imageUrl: answer.referencePhotoUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, error, stackTrace) {
                                      Logger.error('Ошибка загрузки эталонного фото: URL: ${answer.referencePhotoUrl}', error);
                                      return Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.error, size: 48, color: Colors.red.withOpacity(0.7)),
                                            SizedBox(height: 8),
                                            Text(
                                              'Ошибка загрузки\nэталонного фото',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5)),
                                            ),
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
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Сделано сотрудником',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.gold.withOpacity(0.8),
                                ),
                              ),
                              SizedBox(height: 4),
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
                                    borderRadius: BorderRadius.circular(12.r),
                                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12.r),
                                    child: _buildEmployeePhoto(answer),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  } else {
                    Logger.debug('   Нет эталонного фото в ответе');
                    return SizedBox.shrink();
                  }
                },
              ),
              if (answer.referencePhotoUrl == null)
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
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.white.withOpacity(0.15)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12.r),
                      child: _buildEmployeePhoto(answer),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColors.emeraldDark.withOpacity(0.8),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: SafeArea(
        child: _currentReport.isExpired
            ? Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cancel, color: Colors.red.withOpacity(0.9)),
                        SizedBox(width: 8),
                        Text(
                          'Отчет просрочен',
                          style: TextStyle(
                            color: Colors.red.withOpacity(0.9),
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (_currentReport.expiredAt != null) ...[
                      SizedBox(height: 8),
                      Text(
                        'Просрочен: ${_currentReport.expiredAt!.day}.${_currentReport.expiredAt!.month}.${_currentReport.expiredAt!.year}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14.sp,
                        ),
                      ),
                    ],
                    SizedBox(height: 4),
                    Text(
                      'Подтверждение невозможно',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                ),
              )
            : widget.isReadOnly
            ? Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.access_time, color: Colors.orange.withOpacity(0.9)),
                        SizedBox(width: 8),
                        Text(
                          'Отчет не подтвержден вовремя',
                          style: TextStyle(
                            color: Colors.orange.withOpacity(0.9),
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Ожидает более 5 часов',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14.sp,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Только для просмотра',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                ),
              )
            : _currentReport.isConfirmed
            ? Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.withOpacity(0.9)),
                        SizedBox(width: 8),
                        Text(
                          'Отчет подтвержден',
                          style: TextStyle(
                            color: Colors.green.withOpacity(0.9),
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (_currentReport.rating != null) ...[
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Оценка: ',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 14.sp,
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12.w,
                              vertical: 4.h,
                            ),
                            decoration: BoxDecoration(
                              color: _getRatingColor(_currentReport.rating!).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(color: _getRatingColor(_currentReport.rating!).withOpacity(0.4)),
                            ),
                            child: Text(
                              '${_currentReport.rating}',
                              style: TextStyle(
                                color: _getRatingColor(_currentReport.rating!),
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_currentReport.confirmedByAdmin != null) ...[
                      SizedBox(height: 4),
                      Text(
                        'Проверил: ${_currentReport.confirmedByAdmin}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ],
                ),
              )
            : SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _confirmReport,
                  icon: Icon(Icons.check_circle, size: 24),
                  label: Text(
                    'Подтвердить',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.night,
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(16.w),
                  children: [
                    // Информация об отчете
                    _buildInfoCard(),
                    SizedBox(height: 16),

                    // Ответы на вопросы
                    ..._currentReport.answers.asMap().entries.map((entry) {
                      final index = entry.key;
                      final answer = entry.value;
                      return _buildAnswerCard(index, answer);
                    }),
                  ],
                ),
              ),
              // Кнопка подтверждения внизу (не показываем для просроченных и read-only)
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }
}

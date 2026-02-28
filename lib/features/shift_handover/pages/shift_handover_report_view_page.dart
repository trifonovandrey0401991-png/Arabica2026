import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shift_handover_report_model.dart';
import '../services/shift_handover_report_service.dart';
import '../../ai_training/services/shift_ai_verification_service.dart';
import 'package:arabica_app/shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

/// Страница просмотра отчета сдачи смены
class ShiftHandoverReportViewPage extends StatefulWidget {
  final ShiftHandoverReport report;
  final bool isReadOnly;

  const ShiftHandoverReportViewPage({
    super.key,
    required this.report,
    this.isReadOnly = false,
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
    // Показываем диалог выбора оценки
    final result = await _showRatingDialog();
    if (result == null) return; // Пользователь отменил

    final int rating = result;

    try {
      // Получаем имя текущего авторизованного пользователя (админа)
      // ВАЖНО: user_employee_name/user_display_name НЕ перезаписываются при просмотре чужих отчетов
      final prefs = await SharedPreferences.getInstance();
      final adminName = prefs.getString('user_employee_name') ??
                        prefs.getString('user_display_name') ??
                        prefs.getString('user_name') ??
                        'Неизвестный';

      final confirmedReport = _currentReport.copyWith(
        confirmedAt: DateTime.now(),
        rating: rating,
        confirmedByAdmin: adminName,
        status: 'approved', // Для push-уведомления сотруднику
      );

      // Сохраняем локально
      await ShiftHandoverReport.updateReport(confirmedReport);

      // Отправляем на сервер
      final serverSuccess = await ShiftHandoverReportService.updateReport(confirmedReport);

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
      Logger.error('Ошибка подтверждения отчета сдачи смены', e, st);
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
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: AppColors.emeraldDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Padding(
                padding: EdgeInsets.all(24.w),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Оценка сдачи смены',
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Выберите оценку от 1 до 10:',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                    SizedBox(height: 20),
                    // Отображение выбранной оценки
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                      decoration: BoxDecoration(
                        color: _getRatingColor(selectedRating).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text(
                        '$selectedRating',
                        style: TextStyle(
                          fontSize: 48.sp,
                          fontWeight: FontWeight.bold,
                          color: _getRatingColor(selectedRating),
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
                                  ? _getRatingColor(rating)
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
                    SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            'Отмена',
                            style: TextStyle(color: Colors.white.withOpacity(0.6)),
                          ),
                        ),
                        SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(selectedRating),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
                          child: Text('Подтвердить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Отображение фото сотрудника с приоритетом серверного URL
  Widget _buildEmployeePhoto(ShiftHandoverAnswer answer) {
    // Приоритет 1: photoDriveId — серверный URL (работает на любом устройстве)
    if (answer.photoDriveId != null) {
      final photoUrl = answer.photoDriveId!.startsWith('http')
          ? answer.photoDriveId!
          : '${ApiConstants.serverUrl}/shift-photos/${answer.photoDriveId}';
      return AppCachedImage(
        imageUrl: photoUrl,
        fit: BoxFit.cover,
        errorWidget: (context, error, stackTrace) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 48, color: Colors.white.withOpacity(0.4)),
                SizedBox(height: 8),
                Text(
                  'Ошибка загрузки фото',
                  style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.4)),
                ),
              ],
            ),
          );
        },
      );
    }

    // Приоритет 2: photoUrl — серверный URL (legacy)
    if (answer.photoUrl != null) {
      return AppCachedImage(
        imageUrl: answer.photoUrl!,
        fit: BoxFit.cover,
        errorWidget: (context, error, stackTrace) {
          return Center(
            child: Icon(Icons.error, size: 48, color: Colors.white.withOpacity(0.4)),
          );
        },
      );
    }

    // Приоритет 3: photoPath — HTTP URL или data URL
    if (answer.photoPath != null) {
      if (kIsWeb || answer.photoPath!.startsWith('data:') || answer.photoPath!.startsWith('http')) {
        return AppCachedImage(
          imageUrl: answer.photoPath!,
          fit: BoxFit.cover,
          errorWidget: (context, error, stackTrace) {
            return Center(
              child: Icon(Icons.error, color: Colors.white.withOpacity(0.4)),
            );
          },
        );
      }
      // Приоритет 4: photoPath — локальный файл (только на том же устройстве)
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

  void _openPhotoFullscreen(BuildContext context, Widget photo) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.of(dialogContext).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: photo,
                ),
              ),
              Positioned(
                top: 40,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getRatingColor(int rating) {
    if (rating <= 3) return Colors.red;
    if (rating <= 5) return Colors.orange;
    if (rating <= 7) return Colors.amber;
    return Colors.green;
  }

  /// Карточка результатов AI верификации
  Widget _buildAiVerificationCard() {
    final aiPassed = _currentReport.aiVerificationPassed;
    final aiSkipped = _currentReport.aiVerificationSkipped ?? false;
    final aiShortages = _currentReport.aiShortages ?? [];
    final bboxAnnotations = _currentReport.aiBboxAnnotations ?? {};

    Color cardColor;
    IconData cardIcon;
    String cardTitle;
    String cardSubtitle;

    if (aiSkipped) {
      cardColor = Colors.grey;
      cardIcon = Icons.skip_next;
      cardTitle = 'ИИ проверка пропущена';
      cardSubtitle = 'Сотрудник пропустил автоматическую проверку товаров';
    } else if (aiPassed == true) {
      cardColor = Colors.green;
      cardIcon = Icons.verified;
      cardTitle = 'ИИ проверка пройдена';
      cardSubtitle = 'Все товары найдены на фотографиях';
    } else if (aiPassed == false) {
      cardColor = Colors.orange;
      cardIcon = Icons.warning;
      cardTitle = 'Выявлены недостачи';
      cardSubtitle = 'ИИ обнаружил отсутствующие товары';
    } else {
      // Не должно произойти, но на всякий случай
      return SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: cardColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(cardIcon, color: cardColor, size: 24),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cardTitle,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: cardColor,
                      ),
                    ),
                    Text(
                      cardSubtitle,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Показываем список недостач если есть
          if (aiShortages.isNotEmpty) ...[
            SizedBox(height: 16),
            Divider(color: Colors.white.withOpacity(0.1)),
            SizedBox(height: 8),
            Text(
              'Недостачи (${aiShortages.length}):',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14.sp,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            ...aiShortages.map((shortage) {
              final productName = shortage['productName'] ?? 'Неизвестный товар';
              final barcode = shortage['barcode'] ?? '';
              final stockQty = shortage['stockQuantity'] ?? 0;
              return Container(
                margin: EdgeInsets.only(bottom: 8.h),
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cancel, color: Colors.red, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                productName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Код: $barcode',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: Colors.white.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Строка расхождения остатков
                    if (stockQty > 0) ...[
                      SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(10.w),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6.r),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Сотрудник указал: 0 шт. | Остаток в магазине: $stockQty шт.',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],

          // Секция BBox аннотаций для обучения (товары, найденные сотрудником через BBox)
          if (bboxAnnotations.isNotEmpty) ...[
            SizedBox(height: 16),
            Divider(color: Colors.white.withOpacity(0.1)),
            SizedBox(height: 8),
            Text(
              'Аннотации для обучения (${bboxAnnotations.length}):',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14.sp,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Товары, найденные сотрудником с помощью BBox',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            SizedBox(height: 8),
            ...bboxAnnotations.entries.map((entry) {
              final productId = entry.key;
              final annotationId = entry.value;
              // Ищем имя товара в aiShortages
              final shortageInfo = aiShortages.firstWhere(
                (s) => s['productId'] == productId || s['barcode'] == productId,
                orElse: () => <String, dynamic>{},
              );
              final productName = shortageInfo['productName'] as String? ?? productId;
              return Container(
                margin: EdgeInsets.only(bottom: 8.h),
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.photo_camera, color: Colors.blue, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            productName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    _buildAnnotationActions(annotationId, productId),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// Кнопки "Обучить" / "Отклонить" для аннотации с bbox
  Widget _buildAnnotationActions(String annotationId, String productName) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _handleAnnotationAction(annotationId, productName, approve: true),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.green.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.school, color: Colors.green, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Обучить',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => _handleAnnotationAction(annotationId, productName, approve: false),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block, color: Colors.red.withOpacity(0.8), size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Отклонить',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleAnnotationAction(String annotationId, String productName, {required bool approve}) async {
    final action = approve ? 'обучить' : 'отклонить';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text(
          approve ? 'Обучить ИИ?' : 'Отклонить фото?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          approve
              ? 'Загрузить фото "$productName" для обучения ИИ?'
              : 'Не использовать фото "$productName" для обучения?',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(approve ? 'Обучить' : 'Отклонить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    bool success;
    if (approve) {
      success = await ShiftAiVerificationService.approveAnnotation(annotationId);
    } else {
      success = await ShiftAiVerificationService.rejectAnnotation(annotationId);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? (approve ? 'Фото загружено для обучения' : 'Фото отклонено')
              : 'Ошибка: не удалось $action'),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: Column(
          children: [
            // Custom app bar
            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Отчет сдачи смены',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(16.w),
                children: [
                  // Информация об отчете
                  Container(
                    margin: EdgeInsets.only(bottom: 12.h),
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Магазин: ${_currentReport.shopAddress}',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Сотрудник: ${_currentReport.employeeName}',
                          style: TextStyle(color: Colors.white.withOpacity(0.6)),
                        ),
                        Text(
                          'Дата: ${_currentReport.createdAt.day.toString().padLeft(2, '0')}.${_currentReport.createdAt.month.toString().padLeft(2, '0')}.${_currentReport.createdAt.year} '
                          '${_currentReport.createdAt.hour.toString().padLeft(2, '0')}:${_currentReport.createdAt.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(color: Colors.white.withOpacity(0.6)),
                        ),
                        // Показываем информацию о подтверждении
                        if (_currentReport.isConfirmed && _currentReport.confirmedAt != null) ...[
                          SizedBox(height: 12),
                          Divider(color: Colors.white.withOpacity(0.1)),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Подтверждено: ${_currentReport.confirmedAt!.day.toString().padLeft(2, '0')}.${_currentReport.confirmedAt!.month.toString().padLeft(2, '0')}.${_currentReport.confirmedAt!.year} '
                                '${_currentReport.confirmedAt!.hour.toString().padLeft(2, '0')}:${_currentReport.confirmedAt!.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          if (_currentReport.rating != null) ...[
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  'Оценка: ',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                                  decoration: BoxDecoration(
                                    color: _getRatingColor(_currentReport.rating!),
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                  child: Text(
                                    '${_currentReport.rating}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16.sp,
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
                                fontSize: 12.sp,
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),

                  // AI Verification результаты
                  if (_currentReport.aiVerificationPassed != null ||
                      _currentReport.aiVerificationSkipped == true ||
                      (_currentReport.aiShortages != null && _currentReport.aiShortages!.isNotEmpty)) ...[
                    SizedBox(height: 16),
                    _buildAiVerificationCard(),
                  ],

                  SizedBox(height: 16),

                  // Ответы на вопросы
                  ..._currentReport.answers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final answer = entry.value;
                    final hasPhoto = answer.photoPath != null || answer.photoUrl != null || answer.photoDriveId != null;
                    return Container(
                      margin: EdgeInsets.only(bottom: 12.h),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.all(16.w),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Вопрос ${index + 1}: ${answer.question}',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (answer.textAnswer != null) ...[
                                  SizedBox(height: 8),
                                  Text(
                                    'Ответ: ${answer.textAnswer}',
                                    style: TextStyle(color: Colors.white.withOpacity(0.6)),
                                  ),
                                ],
                                if (answer.numberAnswer != null) ...[
                                  SizedBox(height: 8),
                                  Text(
                                    'Ответ: ${answer.numberAnswer}',
                                    style: TextStyle(color: Colors.white.withOpacity(0.6)),
                                  ),
                                ],
                                // Если есть эталонное фото, показываем две фото рядом
                                if (hasPhoto && answer.referencePhotoUrl != null) ...[
                                  SizedBox(height: 8),
                                  Row(
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
                                                color: Colors.white.withOpacity(0.6),
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            GestureDetector(
                                              onTap: () => _openPhotoFullscreen(
                                                context,
                                                AppCachedImage(
                                                  imageUrl: answer.referencePhotoUrl!,
                                                  fit: BoxFit.contain,
                                                  errorWidget: (context, error, stackTrace) => Center(
                                                    child: Icon(Icons.error, color: Colors.white54),
                                                  ),
                                                ),
                                              ),
                                              child: Container(
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
                                                      return Center(
                                                        child: Column(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            Icon(Icons.error, size: 48, color: Colors.white.withOpacity(0.4)),
                                                            SizedBox(height: 8),
                                                            Text(
                                                              'Ошибка загрузки\nэталонного фото',
                                                              textAlign: TextAlign.center,
                                                              style: TextStyle(
                                                                fontSize: 12.sp,
                                                                color: Colors.white.withOpacity(0.4),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
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
                                                color: Colors.white.withOpacity(0.6),
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            GestureDetector(
                                              onTap: () => _openPhotoFullscreen(context, _buildEmployeePhoto(answer)),
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
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Фото без эталона — на всю ширину карточки с тапом для полного экрана
                          if (hasPhoto && answer.referencePhotoUrl == null)
                            GestureDetector(
                              onTap: () => _openPhotoFullscreen(context, _buildEmployeePhoto(answer)),
                              child: AspectRatio(
                                aspectRatio: 4 / 3,
                                child: _buildEmployeePhoto(answer),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            // Кнопка подтверждения внизу (не показываем для просроченных и read-only)
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: AppColors.night.withOpacity(0.8),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: SafeArea(
                child: _currentReport.isExpired
                    ? Container(
                        padding: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cancel, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  'Отчет просрочен',
                                  style: TextStyle(
                                    color: Colors.white,
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
                                  color: Colors.white.withOpacity(0.6),
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
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.access_time, color: Colors.orange),
                                SizedBox(width: 8),
                                Text(
                                  'Отчет не подтвержден вовремя',
                                  style: TextStyle(
                                    color: Colors.white,
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
                                color: Colors.white.withOpacity(0.6),
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
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green),
                                SizedBox(width: 8),
                                Text(
                                  'Отчет подтвержден',
                                  style: TextStyle(
                                    color: Colors.white,
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
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 14.sp,
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12.w,
                                      vertical: 4.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12.r),
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
                            style: TextStyle(fontSize: 18.sp),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16.h),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.r),
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

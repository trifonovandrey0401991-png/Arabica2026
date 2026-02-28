import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/logger.dart';
import '../models/recount_report_model.dart';
import '../models/recount_answer_model.dart';
import '../services/recount_service.dart';
import '../services/recount_points_service.dart';
import '../../ai_training/services/cigarette_vision_service.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница просмотра отчета пересчета с возможностью оценки
class RecountReportViewPage extends StatefulWidget {
  final RecountReport report;
  final VoidCallback? onReportUpdated;
  final bool isReadOnly;

  const RecountReportViewPage({
    super.key,
    required this.report,
    this.onReportUpdated,
    this.isReadOnly = false,
  });

  @override
  State<RecountReportViewPage> createState() => _RecountReportViewPageState();
}

class _RecountReportViewPageState extends State<RecountReportViewPage> {
  late RecountReport _currentReport;
  int? _selectedRating;
  bool _isRating = false;
  String? _adminName;
  final Map<int, String> _photoVerificationStatus = {}; // photoIndex -> status
  final Set<int> _verifyingPhotos = {}; // фото в процессе верификации
  final Map<int, String> _aiErrorDecisions = {}; // questionIndex -> decision
  final Set<int> _processingAiDecisions = {}; // в процессе отправки решения

  // Отправка фото на обучение ИИ из отчёта (по решению админа)
  final Map<int, String> _trainingSubmitStatus = {}; // answerIndex -> 'sent'
  final Set<int> _submittingForTraining = {}; // в процессе отправки

  @override
  void initState() {
    super.initState();
    _currentReport = widget.report;
    _selectedRating = _currentReport.adminRating;
    _loadAdminName();
    _loadPhotoVerifications();
    _loadAiErrorDecisions();
  }

  /// Загрузить решения по ошибкам ИИ из ответов
  void _loadAiErrorDecisions() {
    for (int i = 0; i < _currentReport.answers.length; i++) {
      final answer = _currentReport.answers[i];
      if (answer.aiErrorAdminDecision != null) {
        _aiErrorDecisions[i] = answer.aiErrorAdminDecision!;
      }
    }
  }

  /// Отправить фото из отчёта на обучение ИИ (по решению админа)
  Future<void> _submitReportPhotoForTraining(int answerIndex, RecountAnswer answer) async {
    if (mounted) setState(() {
      _submittingForTraining.add(answerIndex);
    });

    try {
      final success = await CigaretteVisionService.submitReportPhotoForTraining(
        photoUrl: answer.photoUrl!,
        productId: answer.productId ?? answer.question,
        productName: answer.question,
        shopAddress: _currentReport.shopAddress,
        employeeAnswer: answer.employeeConfirmedQuantity ?? answer.actualBalance ?? answer.quantity,
        selectedRegion: answer.selectedRegion,
      );

      if (success) {
        if (!mounted) return;
        setState(() {
          _trainingSubmitStatus[answerIndex] = 'sent';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Фото отправлено на обучение ИИ'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка отправки фото на обучение'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('Ошибка отправки фото на обучение', e);
    } finally {
      if (mounted) {
        setState(() {
          _submittingForTraining.remove(answerIndex);
        });
      }
    }
  }

  /// Кнопка "В обучение ИИ" для фото из отчёта
  Widget _buildReportTrainingButton(int answerIndex, RecountAnswer answer) {
    // Показываем только если: есть фото на сервере и есть данные ИИ
    final hasPhoto = answer.photoUrl != null;
    final hasAiData = answer.selectedRegion != null || answer.aiVerified == true;
    if (!hasPhoto || !hasAiData || widget.isReadOnly) return SizedBox.shrink();

    final status = _trainingSubmitStatus[answerIndex];
    final isSubmitting = _submittingForTraining.contains(answerIndex);

    // Если уже отправлено
    if (status == 'sent') {
      return Container(
        margin: EdgeInsets.only(top: 8.h),
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: AppColors.success.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.school, color: AppColors.success, size: 20),
            SizedBox(width: 8),
            Text(
              'Отправлено на обучение ИИ',
              style: TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    // Кнопка отправки
    return Container(
      margin: EdgeInsets.only(top: 8.h),
      child: ElevatedButton.icon(
        onPressed: isSubmitting ? null : () => _submitReportPhotoForTraining(answerIndex, answer),
        icon: isSubmitting
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(Icons.school, size: 16),
        label: Text('В обучение ИИ', style: TextStyle(fontSize: 12.sp)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.info,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 16.w),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        ),
      ),
    );
  }

  /// Загрузить статусы верификации фото из отчёта
  void _loadPhotoVerifications() {
    if (_currentReport.photoVerifications != null) {
      for (final v in _currentReport.photoVerifications!) {
        final photoIndex = v['photoIndex'] as int?;
        final status = v['status'] as String?;
        if (photoIndex != null && status != null) {
          _photoVerificationStatus[photoIndex] = status;
        }
      }
    }
  }

  Future<void> _loadAdminName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name');
    if (!mounted) return;
    setState(() {
      _adminName = name;
    });
  }

  /// Верифицировать фото (принять или отклонить)
  Future<void> _verifyPhoto(int photoIndex, String status) async {
    if (_adminName == null || _currentReport.employeePhone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось определить администратора или телефон сотрудника'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (mounted) setState(() {
      _verifyingPhotos.add(photoIndex);
    });

    try {
      final success = await RecountPointsService.verifyPhoto(
        reportId: _currentReport.id,
        photoIndex: photoIndex,
        status: status,
        adminName: _adminName!,
        employeePhone: _currentReport.employeePhone!,
      );

      if (success) {
        if (!mounted) return;
        setState(() {
          _photoVerificationStatus[photoIndex] = status;
        });

        final pointsChange = status == 'approved' ? '+0.2' : '-2.5';
        final statusText = status == 'approved' ? 'принято' : 'отклонено';

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Фото $statusText ($pointsChange баллов)'),
              backgroundColor: status == 'approved' ? AppColors.success : AppColors.error,
            ),
          );
        }

        if (widget.onReportUpdated != null) {
          widget.onReportUpdated!();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка верификации фото'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('Ошибка верификации фото', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _verifyingPhotos.remove(photoIndex);
        });
      }
    }
  }

  /// Построить виджет кнопок верификации фото
  Widget _buildPhotoVerificationButtons(int photoIndex) {
    final status = _photoVerificationStatus[photoIndex];
    final isVerifying = _verifyingPhotos.contains(photoIndex);

    // Если фото уже верифицировано - показываем статус
    if (status != null && status != 'pending') {
      final isApproved = status == 'approved';
      return Container(
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: isApproved
              ? AppColors.success.withOpacity(0.1)
              : AppColors.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: isApproved
                ? AppColors.success.withOpacity(0.3)
                : AppColors.error.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isApproved ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: isApproved ? AppColors.success : AppColors.error,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              isApproved ? 'Принято (+0.2 балла)' : 'Отклонено (-2.5 балла)',
              style: TextStyle(
                color: isApproved ? AppColors.success : AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    // Если read-only или просрочено - не показываем кнопки
    if (widget.isReadOnly || _currentReport.isExpired) {
      return SizedBox.shrink();
    }

    // Показываем кнопки "Принять" и "Отклонить"
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isVerifying ? null : () => _verifyPhoto(photoIndex, 'approved'),
            icon: isVerifying
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(Icons.check_rounded, size: 18),
            label: Text('Принять'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isVerifying ? null : () => _verifyPhoto(photoIndex, 'rejected'),
            icon: isVerifying
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(Icons.close_rounded, size: 18),
            label: Text('Отклонить'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
          ),
        ),
      ],
    );
  }

  /// Построить кнопки решения админа по ошибке ИИ
  Widget _buildAiErrorDecisionButtons(int questionIndex, answer) {
    final decision = _aiErrorDecisions[questionIndex] ?? answer.aiErrorAdminDecision;
    final isProcessing = _processingAiDecisions.contains(questionIndex);

    // Если решение уже принято - показываем статус
    if (decision != null) {
      final isApproved = decision == 'approved_for_training';
      return Container(
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: isApproved
              ? AppColors.success.withOpacity(0.1)
              : AppColors.warning.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: isApproved ? AppColors.success.withOpacity(0.3) : AppColors.warning.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isApproved ? Icons.school : Icons.photo_camera_back,
              color: isApproved ? AppColors.success : AppColors.warning,
              size: 20,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isApproved ? 'Добавлено к обучению' : 'Плохое фото (отклонено)',
                    style: TextStyle(
                      color: isApproved ? AppColors.success : AppColors.warning,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.sp,
                    ),
                  ),
                  if (answer.aiErrorDecisionBy != null)
                    Text(
                      'Решение: ${answer.aiErrorDecisionBy}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11.sp,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Если read-only или просрочено - не показываем кнопки
    if (widget.isReadOnly || _currentReport.isExpired) {
      return Container(
        padding: EdgeInsets.all(8.w),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(
          'Требуется решение админа',
          style: TextStyle(color: Colors.grey, fontSize: 12.sp),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Показываем кнопки "Добавить к обучению" и "Плохое фото"
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Решение по ошибке ИИ:',
          style: TextStyle(fontSize: 12.sp, color: Colors.white60),
        ),
        SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isProcessing
                    ? null
                    : () => _handleAiErrorDecision(questionIndex, 'approved_for_training'),
                icon: isProcessing
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(Icons.school, size: 16),
                label: Text('К обучению', style: TextStyle(fontSize: 12.sp)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                ),
              ),
            ),
            SizedBox(width: 6),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isProcessing
                    ? null
                    : () => _handleAiErrorDecision(questionIndex, 'rejected_bad_photo'),
                icon: isProcessing
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(Icons.photo_camera_back, size: 16),
                label: Text('Плохое фото', style: TextStyle(fontSize: 12.sp)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Обработать решение админа по ошибке ИИ
  Future<void> _handleAiErrorDecision(int questionIndex, String decision) async {
    if (_adminName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось определить администратора'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final answer = _currentReport.answers[questionIndex];

    if (mounted) setState(() {
      _processingAiDecisions.add(questionIndex);
    });

    try {
      final result = await CigaretteVisionService.reportAdminAiDecision(
        productId: answer.productId ?? answer.question,
        decision: decision,
        adminName: _adminName!,
        productName: answer.question,
        expectedCount: answer.actualBalance ?? answer.quantity,
        aiCount: answer.aiQuantity,
        shopAddress: _currentReport.shopAddress,
      );

      if (result.success) {
        if (!mounted) return;
        setState(() {
          _aiErrorDecisions[questionIndex] = decision;
        });

        final isApproved = decision == 'approved_for_training';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isApproved
                    ? 'Фото добавлено к обучению ИИ'
                    : 'Фото отклонено (плохое качество)',
              ),
              backgroundColor: isApproved ? AppColors.success : AppColors.warning,
            ),
          );
        }

        // Проверяем авто-отключение ИИ
        if (result.isDisabled && isApproved) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'ИИ отключен для "${answer.question}" после ${result.consecutiveErrors} ошибок',
                ),
                backgroundColor: AppColors.error,
                duration: Duration(seconds: 5),
              ),
            );
          }
        }

        if (widget.onReportUpdated != null) {
          widget.onReportUpdated!();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка: ${result.error}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('Ошибка отправки решения по ИИ', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingAiDecisions.remove(questionIndex);
        });
      }
    }
  }

  Future<void> _rateReport() async {
    if (_selectedRating == null || _adminName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Выберите оценку'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (mounted) setState(() {
      _isRating = true;
    });

    try {
      final success = await RecountService.rateReport(
        _currentReport.id,
        _selectedRating!,
        _adminName!,
      );

      if (success) {
        // Обновляем отчет
        final updatedReport = _currentReport.copyWith(
          adminRating: _selectedRating,
          adminName: _adminName,
          ratedAt: DateTime.now(),
        );

        if (!mounted) return;
        setState(() {
          _currentReport = updatedReport;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Оценка успешно поставлена'),
              backgroundColor: AppColors.success,
            ),
          );
        }

        if (widget.onReportUpdated != null) {
          widget.onReportUpdated!();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка постановки оценки'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('Ошибка постановки оценки', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRating = false;
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════
  // UI Helper methods
  // ═══════════════════════════════════════════════════

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.h),
      child: Row(
        children: [
          Container(
            width: 32.w,
            height: 32.w,
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(icon, size: 16, color: AppColors.emerald),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.grey[500],
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.night,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _gradeColor(int? grade) {
    switch (grade) {
      case 1: return AppColors.error;
      case 2: return AppColors.gold;
      default: return AppColors.emerald;
    }
  }

  // ═══════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Отчет пересчета',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18.sp,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.emeraldDark, AppColors.emerald],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.emeraldDark, AppColors.night],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.all(16.w),
            children: [
              // ═══ Info Card ═══
              _buildInfoCard(),
              SizedBox(height: 16.h),

              // ═══ Rating Card ═══
              if (!_currentReport.isRated && !_currentReport.isExpired && !widget.isReadOnly) ...[
                _buildRatingCard(),
                SizedBox(height: 16.h),
              ],

              // ═══ Answer cards ═══
              ..._currentReport.answers.asMap().entries.map((entry) {
                return Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: _buildAnswerCard(entry.key, entry.value),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // Info Card — shop, employee, time, status
  // ═══════════════════════════════════════════════════

  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gradient header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.emerald, AppColors.emeraldLight],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(Icons.store_rounded, color: AppColors.gold, size: 22),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    _currentReport.shopAddress,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Info rows
          Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              children: [
                _buildInfoRow(Icons.person_outline, 'Сотрудник', _currentReport.employeeName),
                _buildInfoRow(Icons.timer_outlined, 'Время пересчета', _currentReport.formattedDuration),
                _buildInfoRow(
                  Icons.calendar_today_outlined,
                  'Дата',
                  '${_currentReport.completedAt.day.toString().padLeft(2, '0')}.${_currentReport.completedAt.month.toString().padLeft(2, '0')}.${_currentReport.completedAt.year} '
                  '${_currentReport.completedAt.hour.toString().padLeft(2, '0')}:${_currentReport.completedAt.minute.toString().padLeft(2, '0')}',
                ),
                // Rating badge
                if (_currentReport.isRated) ...[
                  SizedBox(height: 12.h),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.gold.withOpacity(0.15), AppColors.gold.withOpacity(0.05)],
                      ),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.star_rounded, color: AppColors.gold, size: 24),
                        SizedBox(width: 8.w),
                        Text(
                          'Оценка: ${_currentReport.adminRating}/10',
                          style: TextStyle(
                            color: AppColors.darkGold,
                            fontWeight: FontWeight.bold,
                            fontSize: 15.sp,
                          ),
                        ),
                        if (_currentReport.adminName != null) ...[
                          SizedBox(width: 8.w),
                          Text(
                            '(${_currentReport.adminName})',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12.sp,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                // Expired badge
                if (_currentReport.isExpired && !_currentReport.isRated) ...[
                  SizedBox(height: 12.h),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 22),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Отчёт просрочен',
                                style: TextStyle(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.sp,
                                ),
                              ),
                              if (_currentReport.expiredAt != null)
                                Text(
                                  'Просрочен: ${_currentReport.expiredAt!.day}.${_currentReport.expiredAt!.month}.${_currentReport.expiredAt!.year}',
                                  style: TextStyle(
                                    color: AppColors.error.withOpacity(0.7),
                                    fontSize: 12.sp,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Read-only badge
                if (widget.isReadOnly && !_currentReport.isRated && !_currentReport.isExpired) ...[
                  SizedBox(height: 12.h),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.access_time_rounded, color: AppColors.warning, size: 22),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Отчёт не оценен вовремя',
                                style: TextStyle(
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.sp,
                                ),
                              ),
                              Text(
                                'Ожидает более 5 часов — только просмотр',
                                style: TextStyle(
                                  color: AppColors.warning.withOpacity(0.8),
                                  fontSize: 12.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // Rating Card — gold-themed star rating
  // ═══════════════════════════════════════════════════

  Widget _buildRatingCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_rounded, color: AppColors.gold, size: 24),
              SizedBox(width: 8.w),
              Text(
                'Оценка отчета',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.emeraldDark,
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          // Circle rating buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(10, (index) {
              final rating = index + 1;
              final isSelected = _selectedRating == rating;
              return GestureDetector(
                onTap: () {
                  if (mounted) setState(() {
                    _selectedRating = isSelected ? null : rating;
                  });
                },
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  width: 30.w,
                  height: 30.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppColors.gold : Colors.grey[200],
                    boxShadow: isSelected
                        ? [BoxShadow(color: AppColors.gold.withOpacity(0.4), blurRadius: 8, offset: Offset(0, 2))]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '$rating',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[600],
                        fontWeight: FontWeight.bold,
                        fontSize: 13.sp,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isRating ? null : _rateReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 14.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                elevation: 2,
              ),
              child: _isRating
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Поставить оценку',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // Answer Card — single question with result
  // ═══════════════════════════════════════════════════

  Widget _buildAnswerCard(int index, RecountAnswer answer) {
    final gradeColor = _gradeColor(answer.grade);
    final hasPhoto = answer.photoUrl != null || answer.photoPath != null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        color: const Color(0xFF0A2424),
        border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grade header with gradient
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [gradeColor.withOpacity(0.28), gradeColor.withOpacity(0.08)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              border: Border(bottom: BorderSide(color: gradeColor.withOpacity(0.35))),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: gradeColor,
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    'Грейд ${answer.grade}',
                    style: TextStyle(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.bold),
                  ),
                ),
                if (answer.photoRequired)
                  Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: Icon(Icons.camera_alt_outlined, color: AppColors.gold, size: 16),
                  ),
              ],
            ),
          ),
          // Question title
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
            child: Text(
              'Вопрос ${index + 1}: ${answer.question}',
              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          // Match / mismatch + AI blocks
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, hasPhoto ? 10.h : 16.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (answer.answer == 'сходится')
                  _buildMatchBlock(answer)
                else if (answer.answer == 'не сходится')
                  _buildMismatchBlock(answer),
                if (answer.aiVerified == true) ...[
                  SizedBox(height: 10.h),
                  _buildAiVerificationBlock(index, answer),
                ],
              ],
            ),
          ),
          // Photo — full-width, edge-to-edge (card clips corners)
          if (hasPhoto) _buildPhotoBlock(index, answer),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // Match / Mismatch blocks
  // ═══════════════════════════════════════════════════

  Widget _buildMatchBlock(RecountAnswer answer) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.success.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Сходится',
                  style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 15.sp),
                ),
                if (answer.quantity != null)
                  Text(
                    'Количество: ${answer.quantity} шт',
                    style: TextStyle(fontSize: 13.sp, color: Colors.white70),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMismatchBlock(RecountAnswer answer) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.cancel_rounded, color: AppColors.error, size: 22),
              ),
              SizedBox(width: 12.w),
              Text(
                'Не сходится',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.bold,
                  fontSize: 15.sp,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          // Data row with separators
          Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: const Color(0xFF061818),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _buildCountColumn('По программе', '${answer.programBalance ?? '-'} шт', Colors.white70),
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: AppColors.emerald.withOpacity(0.3)),
                  Expanded(
                    child: _buildCountColumn('По факту', '${answer.actualBalance ?? '-'} шт', Colors.white70),
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: AppColors.emerald.withOpacity(0.3)),
                  Expanded(
                    child: _buildCountColumn(
                      'Разница',
                      answer.difference != null
                          ? (answer.difference! > 0
                              ? '-${answer.difference}'
                              : '+${answer.difference!.abs()}')
                          : '-',
                      answer.difference != null
                          ? (answer.difference! > 0 ? AppColors.error : AppColors.info)
                          : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Hint text
          if (answer.difference != null && answer.difference != 0) ...[
            SizedBox(height: 8.h),
            Text(
              answer.difference! > 0
                  ? 'Недостача: меньше на ${answer.difference} шт'
                  : 'Излишек: больше на ${answer.difference!.abs()} шт',
              style: TextStyle(
                fontSize: 12.sp,
                color: answer.difference! > 0 ? AppColors.error : AppColors.info,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCountColumn(String label, String value, Color valueColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11.sp, color: Colors.white54),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 4.h),
        Text(
          value,
          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: valueColor),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  // AI Verification block
  // ═══════════════════════════════════════════════════

  Widget _buildAiVerificationBlock(int index, RecountAnswer answer) {
    final isMismatch = answer.aiMismatch == true;
    final accentColor = isMismatch ? AppColors.warning : AppColors.info;

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: accentColor.withOpacity(0.25), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.smart_toy_rounded, color: accentColor, size: 20),
              SizedBox(width: 8.w),
              Text(
                'Проверено ИИ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                  fontSize: 14.sp,
                ),
              ),
              Spacer(),
              if (answer.aiConfidence != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    '${(answer.aiConfidence! * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 10.h),
          // Counts row
          Row(
            children: [
              Expanded(
                child: _buildAiCountItem(
                  'Сотрудник',
                  '${answer.actualBalance ?? answer.quantity ?? '-'} шт',
                ),
              ),
              Container(
                width: 24.w,
                alignment: Alignment.center,
                child: Icon(Icons.compare_arrows, color: Colors.grey[400], size: 20),
              ),
              Expanded(
                child: _buildAiCountItem(
                  'ИИ насчитал',
                  '${answer.aiQuantity ?? '-'} шт',
                  valueColor: isMismatch ? AppColors.warning : null,
                ),
              ),
            ],
          ),
          // Employee confirmed
          if (answer.employeeConfirmedQuantity != null) ...[
            SizedBox(height: 8.h),
            _buildSmallBadge(
              Icons.person_pin,
              'Сотрудник подтвердил: ${answer.employeeConfirmedQuantity} шт.',
              AppColors.success,
            ),
          ],
          // Employee selected region
          if (answer.selectedRegion != null) ...[
            SizedBox(height: 4.h),
            _buildSmallBadge(
              Icons.crop,
              'Сотрудник выделил область на фото',
              AppColors.info,
            ),
          ],
          // Mismatch warning
          if (isMismatch) ...[
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_rounded, color: AppColors.error, size: 16),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      'Расхождение между сотрудником и ИИ!',
                      style: TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.sp,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Employee reported AI error
            if (answer.employeeReportedAiError == true) ...[
              SizedBox(height: 4.h),
              _buildSmallBadge(
                Icons.report_problem,
                'Сотрудник сообщил об ошибке ИИ',
                AppColors.purple,
              ),
            ],
            // AI error decision buttons
            SizedBox(height: 8.h),
            _buildAiErrorDecisionButtons(index, answer),
          ],
        ],
      ),
    );
  }

  Widget _buildAiCountItem(String label, String value, {Color? valueColor}) {
    return Container(
      padding: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: const Color(0xFF061818),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11.sp, color: Colors.white54)),
          SizedBox(height: 4.h),
          Text(
            value,
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: valueColor ?? Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallBadge(IconData icon, String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          SizedBox(width: 4.w),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // Photo block
  // ═══════════════════════════════════════════════════

  Widget _buildPhotoBlock(int index, RecountAnswer answer) {
    Widget buildImage() {
      if (answer.photoUrl != null) {
        return AppCachedImage(
          imageUrl: answer.photoUrl!,
          fit: BoxFit.cover,
          errorWidget: (context, error, stackTrace) =>
              Center(child: Icon(Icons.error, color: AppColors.error)),
        );
      } else if (answer.photoPath != null) {
        if (kIsWeb || answer.photoPath!.startsWith('data:') || answer.photoPath!.startsWith('http')) {
          return AppCachedImage(
            imageUrl: answer.photoPath!,
            fit: BoxFit.cover,
            errorWidget: (context, error, stackTrace) =>
                Center(child: Icon(Icons.error, color: AppColors.error)),
          );
        } else {
          return Image.file(
            File(answer.photoPath!),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                Center(child: Icon(Icons.error, color: AppColors.error)),
          );
        }
      }
      return Center(child: Icon(Icons.image_not_supported, color: Colors.grey));
    }

    final imageWidget = buildImage();

    return Column(
      children: [
        // Full-width photo — clipped by parent card's borderRadius
        AspectRatio(
          aspectRatio: 4 / 3,
          child: answer.selectedRegion != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    imageWidget,
                    LayoutBuilder(
                      builder: (context, constraints) => CustomPaint(
                        painter: _RegionOverlayPainter(
                          region: answer.selectedRegion!,
                          containerWidth: constraints.maxWidth,
                          containerHeight: constraints.maxHeight,
                        ),
                      ),
                    ),
                  ],
                )
              : imageWidget,
        ),
        // Verification + training buttons
        Padding(
          padding: EdgeInsets.all(12.w),
          child: Column(
            children: [
              _buildPhotoVerificationButtons(index),
              _buildReportTrainingButton(index, answer),
            ],
          ),
        ),
      ],
    );
  }
}

/// Рисует красный прямоугольник поверх фото — область, выделенная сотрудником
class _RegionOverlayPainter extends CustomPainter {
  final Map<String, double> region;
  final double containerWidth;
  final double containerHeight;

  _RegionOverlayPainter({
    required this.region,
    required this.containerWidth,
    required this.containerHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = (region['x'] ?? 0) * size.width;
    final y = (region['y'] ?? 0) * size.height;
    final w = (region['width'] ?? 0) * size.width;
    final h = (region['height'] ?? 0) * size.height;

    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
  }

  @override
  bool shouldRepaint(covariant _RegionOverlayPainter oldDelegate) {
    return oldDelegate.region != region;
  }
}

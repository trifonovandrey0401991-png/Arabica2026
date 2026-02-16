import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/logger.dart';
import '../models/recount_report_model.dart';
import '../services/recount_service.dart';
import '../services/recount_points_service.dart';
import '../../ai_training/services/cigarette_vision_service.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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

  // Pending counting samples для обучения ИИ
  Map<String, List<dynamic>> _pendingSamplesByProduct = {}; // productId -> samples
  final Map<String, String> _approvedSamples = {}; // sampleId -> 'approved' или 'rejected'
  final Set<String> _processingSamples = {}; // в процессе approve/reject

  @override
  void initState() {
    super.initState();
    _currentReport = widget.report;
    _selectedRating = _currentReport.adminRating;
    _loadAdminName();
    _loadPhotoVerifications();
    _loadAiErrorDecisions();
    _loadPendingCountingSamples();
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

  /// Загрузить pending counting samples для товаров из отчёта
  Future<void> _loadPendingCountingSamples() async {
    try {
      final allPending = await CigaretteVisionService.getAllPendingCountingSamples();
      final Map<String, List<dynamic>> byProduct = {};

      for (final sample in allPending) {
        // Индексируем по productId/barcode
        final productId = sample.productId.isNotEmpty ? sample.productId : sample.barcode;
        if (productId.isNotEmpty) {
          byProduct.putIfAbsent(productId, () => []);
          byProduct[productId]!.add(sample);
        }
        // Также индексируем по productName для совместимости со старыми отчётами
        final productName = sample.productName;
        if (productName.isNotEmpty) {
          byProduct.putIfAbsent(productName, () => []);
          byProduct[productName]!.add(sample);
        }
      }

      if (mounted) {
        setState(() {
          _pendingSamplesByProduct = byProduct;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки pending samples', e);
    }
  }

  /// Одобрить pending фото для обучения ИИ
  Future<void> _approvePendingSample(String sampleId) async {
    setState(() {
      _processingSamples.add(sampleId);
    });

    try {
      final success = await CigaretteVisionService.approvePendingCountingSample(sampleId);
      if (success) {
        setState(() {
          _approvedSamples[sampleId] = 'approved';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Фото добавлено в обучение ИИ'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка одобрения фото'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('Ошибка одобрения pending sample', e);
    } finally {
      setState(() {
        _processingSamples.remove(sampleId);
      });
    }
  }

  /// Отклонить pending фото
  Future<void> _rejectPendingSample(String sampleId) async {
    setState(() {
      _processingSamples.add(sampleId);
    });

    try {
      final success = await CigaretteVisionService.rejectPendingCountingSample(sampleId);
      if (success) {
        setState(() {
          _approvedSamples[sampleId] = 'rejected';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Фото отклонено'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('Ошибка отклонения pending sample', e);
    } finally {
      setState(() {
        _processingSamples.remove(sampleId);
      });
    }
  }

  /// Построить кнопки для pending фото обучения ИИ
  Widget _buildPendingTrainingButtons(String productId) {
    final pendingSamples = _pendingSamplesByProduct[productId] ?? [];
    if (pendingSamples.isEmpty) return SizedBox.shrink();

    return Column(
      children: pendingSamples.map<Widget>((sample) {
        final sampleId = sample.id ?? '';
        final status = _approvedSamples[sampleId];
        final isProcessing = _processingSamples.contains(sampleId);

        // Если уже обработан
        if (status != null) {
          return Container(
            margin: EdgeInsets.only(top: 8.h),
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: status == 'approved'
                  ? Colors.green.withOpacity(0.15)
                  : Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(
                color: status == 'approved' ? Colors.green : Colors.orange,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  status == 'approved' ? Icons.school : Icons.cancel,
                  color: status == 'approved' ? Colors.green : Colors.orange,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  status == 'approved'
                      ? 'Добавлено в обучение ИИ'
                      : 'Фото отклонено',
                  style: TextStyle(
                    color: status == 'approved' ? Colors.green[700] : Colors.orange[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }

        // Кнопки одобрить/отклонить
        return Container(
          margin: EdgeInsets.only(top: 8.h),
          padding: EdgeInsets.all(10.w),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: Colors.blue.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.smart_toy, color: Colors.blue, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Фото для обучения ИИ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      fontSize: 13.sp,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isProcessing ? null : () => _approvePendingSample(sampleId),
                      icon: isProcessing
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(Icons.check, size: 16),
                      label: Text('В обучение', style: TextStyle(fontSize: 12.sp)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 8.h),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isProcessing ? null : () => _rejectPendingSample(sampleId),
                      icon: isProcessing
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(Icons.close, size: 16),
                      label: Text('Отклонить', style: TextStyle(fontSize: 12.sp)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 8.h),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
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
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
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
        setState(() {
          _photoVerificationStatus[photoIndex] = status;
        });

        final pointsChange = status == 'approved' ? '+0.2' : '-2.5';
        final statusText = status == 'approved' ? 'принято' : 'отклонено';

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Фото $statusText ($pointsChange баллов)'),
              backgroundColor: status == 'approved' ? Colors.green : Colors.red,
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
              backgroundColor: Colors.red,
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
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _verifyingPhotos.remove(photoIndex);
      });
    }
  }

  /// Построить виджет кнопок верификации фото
  Widget _buildPhotoVerificationButtons(int photoIndex) {
    final status = _photoVerificationStatus[photoIndex];
    final isVerifying = _verifyingPhotos.contains(photoIndex);

    // Если фото уже верифицировано - показываем статус
    if (status != null && status != 'pending') {
      return Container(
        padding: EdgeInsets.all(8.w),
        decoration: BoxDecoration(
          color: status == 'approved'
              ? Colors.green.withOpacity(0.2)
              : Colors.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              status == 'approved' ? Icons.check_circle : Icons.cancel,
              color: status == 'approved' ? Colors.green : Colors.red,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              status == 'approved' ? 'Принято (+0.2 балла)' : 'Отклонено (-2.5 балла)',
              style: TextStyle(
                color: status == 'approved' ? Colors.green[700] : Colors.red[700],
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
                : Icon(Icons.check, size: 18),
            label: Text('Принять'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12.h),
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
                : Icon(Icons.close, size: 18),
            label: Text('Отклонить'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12.h),
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
              ? Colors.green.withOpacity(0.15)
              : Colors.orange.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(
            color: isApproved ? Colors.green : Colors.orange,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isApproved ? Icons.school : Icons.photo_camera_back,
              color: isApproved ? Colors.green : Colors.orange,
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
                      color: isApproved ? Colors.green[700] : Colors.orange[700],
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
          style: TextStyle(fontSize: 12.sp, color: Colors.grey),
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
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
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
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
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
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final answer = _currentReport.answers[questionIndex];

    setState(() {
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
              backgroundColor: isApproved ? Colors.green : Colors.orange,
            ),
          );
        }

        // Проверяем авто-отключение ИИ
        if (result.isDisabled && isApproved) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⚠️ ИИ отключен для "${answer.question}" после ${result.consecutiveErrors} ошибок',
                ),
                backgroundColor: Colors.red,
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
              backgroundColor: Colors.red,
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
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _processingAiDecisions.remove(questionIndex);
      });
    }
  }

  Future<void> _rateReport() async {
    if (_selectedRating == null || _adminName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Выберите оценку'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
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
        
        setState(() {
          _currentReport = updatedReport;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Оценка успешно поставлена'),
              backgroundColor: Colors.green,
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
              backgroundColor: Colors.red,
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
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isRating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Отчет пересчета'),
        backgroundColor: Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: Color(0xFF004D40),
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
                padding: EdgeInsets.all(16.w),
                children: [
                  // Информация об отчете
                  Card(
                    color: Colors.white.withOpacity(0.95),
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
                              color: Color(0xFF004D40),
                            ),
                          ),
                          SizedBox(height: 8),
                          Text('Сотрудник: ${_currentReport.employeeName}'),
                          Text('Время пересчета: ${_currentReport.formattedDuration}'),
                          Text(
                            'Дата: ${_currentReport.completedAt.day}.${_currentReport.completedAt.month}.${_currentReport.completedAt.year} '
                            '${_currentReport.completedAt.hour.toString().padLeft(2, '0')}:${_currentReport.completedAt.minute.toString().padLeft(2, '0')}',
                          ),
                          if (_currentReport.isRated) ...[
                            SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.all(8.w),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.star, color: Colors.green),
                                  SizedBox(width: 8),
                                  Text(
                                    'Оценка: ${_currentReport.adminRating}/10',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (_currentReport.adminName != null)
                                    Text(
                                      ' (${_currentReport.adminName})',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12.sp,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          // Блок "Отчёт просрочен"
                          if (_currentReport.isExpired && !_currentReport.isRated) ...[
                            SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(color: Colors.red.withOpacity(0.5)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber, color: Colors.red),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Отчёт просрочен',
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16.sp,
                                          ),
                                        ),
                                        if (_currentReport.expiredAt != null)
                                          Text(
                                            'Просрочен: ${_currentReport.expiredAt!.day}.${_currentReport.expiredAt!.month}.${_currentReport.expiredAt!.year}',
                                            style: TextStyle(
                                              color: Colors.red[700],
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
                          // Блок "Отчёт не оценен вовремя" (ожидает более 5 часов)
                          if (widget.isReadOnly && !_currentReport.isRated && !_currentReport.isExpired) ...[
                            SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(color: Colors.orange.withOpacity(0.5)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.access_time, color: Colors.orange),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Отчёт не оценен вовремя',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16.sp,
                                          ),
                                        ),
                                        Text(
                                          'Ожидает более 5 часов - только просмотр',
                                          style: TextStyle(
                                            color: Colors.orange[700],
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
                  ),
                  SizedBox(height: 16),

                  // Оценка (если еще не оценено, не просрочено и не read-only)
                  if (!_currentReport.isRated && !_currentReport.isExpired && !widget.isReadOnly)
                    Card(
                      color: Colors.white.withOpacity(0.95),
                      child: Padding(
                        padding: EdgeInsets.all(16.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Оценка отчета:',
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF004D40),
                              ),
                            ),
                            SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(10, (index) {
                                final rating = index + 1;
                                return ChoiceChip(
                                  label: Text('$rating'),
                                  selected: _selectedRating == rating,
                                  onSelected: (selected) {
                                    setState(() {
                                      _selectedRating = selected ? rating : null;
                                    });
                                  },
                                  selectedColor: Colors.green,
                                  labelStyle: TextStyle(
                                    color: _selectedRating == rating
                                        ? Colors.white
                                        : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              }),
                            ),
                            SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isRating ? null : _rateReport,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF004D40),
                                  padding: EdgeInsets.symmetric(vertical: 16.h),
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
                      ),
                    ),
                  if (!_currentReport.isRated && !_currentReport.isExpired && !widget.isReadOnly) SizedBox(height: 16),

                  // Ответы на вопросы
                  ..._currentReport.answers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final answer = entry.value;
                    return Card(
                      color: Colors.white.withOpacity(0.95),
                      margin: EdgeInsets.only(bottom: 12.h),
                      child: Padding(
                        padding: EdgeInsets.all(16.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.w,
                                    vertical: 4.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: answer.grade == 1
                                        ? Colors.red
                                        : answer.grade == 2
                                            ? Colors.orange
                                            : Colors.blue,
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                  child: Text(
                                    'Грейд ${answer.grade}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (answer.photoRequired)
                                  Padding(
                                    padding: EdgeInsets.only(left: 8.w),
                                    child: Icon(
                                      Icons.camera_alt,
                                      color: Colors.orange,
                                      size: 16,
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Вопрос ${index + 1}: ${answer.question}',
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF004D40),
                              ),
                            ),
                            SizedBox(height: 8),
                            if (answer.answer == 'сходится')
                              Container(
                                padding: EdgeInsets.all(12.w),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8.r),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green, size: 24),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Сходится',
                                            style: TextStyle(
                                              color: Colors.green[700],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16.sp,
                                            ),
                                          ),
                                          if (answer.quantity != null)
                                            Text(
                                              'Количество: ${answer.quantity} шт',
                                              style: TextStyle(fontSize: 14.sp),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (answer.answer == 'не сходится')
                              Container(
                                padding: EdgeInsets.all(12.w),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8.r),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.cancel, color: Colors.red, size: 24),
                                        SizedBox(width: 12),
                                        Text(
                                          'Не сходится',
                                          style: TextStyle(
                                            color: Colors.red[700],
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16.sp,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8),
                                    // Строка с данными: По программе | По факту | Разница
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Text(
                                                'По программе',
                                                style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                                              ),
                                              Text(
                                                '${answer.programBalance ?? '-'} шт',
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Text(
                                                'По факту',
                                                style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                                              ),
                                              Text(
                                                '${answer.actualBalance ?? '-'} шт',
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Text(
                                                'Разница',
                                                style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                                              ),
                                              if (answer.difference != null)
                                                Text(
                                                  answer.difference! > 0
                                                      ? '-${answer.difference}' // Недостача
                                                      : '+${answer.difference!.abs()}', // Излишек
                                                  style: TextStyle(
                                                    fontSize: 16.sp,
                                                    fontWeight: FontWeight.bold,
                                                    color: answer.difference! > 0
                                                        ? Colors.red // Недостача - красный
                                                        : Colors.blue, // Излишек - синий
                                                  ),
                                                )
                                              else
                                                Text('-'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Подсказка: что означает разница
                                    if (answer.difference != null && answer.difference != 0) ...[
                                      SizedBox(height: 8),
                                      Text(
                                        answer.difference! > 0
                                            ? 'Недостача: меньше на ${answer.difference} шт'
                                            : 'Излишек: больше на ${answer.difference!.abs()} шт',
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          color: answer.difference! > 0 ? Colors.red[700] : Colors.blue[700],
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            // Блок ИИ проверки
                            if (answer.aiVerified == true) ...[
                              SizedBox(height: 12),
                              Container(
                                padding: EdgeInsets.all(12.w),
                                decoration: BoxDecoration(
                                  color: answer.aiMismatch == true
                                      ? Colors.orange.withOpacity(0.1)
                                      : Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8.r),
                                  border: Border.all(
                                    color: answer.aiMismatch == true ? Colors.orange : Colors.blue,
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          answer.aiMismatch == true ? Icons.warning_amber : Icons.check_circle,
                                          color: answer.aiMismatch == true ? Colors.orange : Colors.blue,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Icon(
                                          Icons.smart_toy,
                                          color: answer.aiMismatch == true ? Colors.orange : Colors.blue,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          '✓ Проверено ИИ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: answer.aiMismatch == true ? Colors.orange[700] : Colors.blue[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Сотрудник:',
                                                style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                                              ),
                                              Text(
                                                '${answer.actualBalance ?? answer.quantity ?? '-'} шт',
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'ИИ насчитал:',
                                                style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                                              ),
                                              Text(
                                                '${answer.aiQuantity ?? '-'} шт',
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  fontWeight: FontWeight.bold,
                                                  color: answer.aiMismatch == true ? Colors.orange[700] : Colors.blue[700],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (answer.aiConfidence != null)
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Уверенность:',
                                                  style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                                                ),
                                                Text(
                                                  '${(answer.aiConfidence! * 100).toInt()}%',
                                                  style: TextStyle(
                                                    fontSize: 16.sp,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    // Бейдж "Сотрудник подтвердил количество"
                                    if (answer.employeeConfirmedQuantity != null) ...[
                                      SizedBox(height: 8),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4.r),
                                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.person_pin, color: Colors.green, size: 14),
                                            SizedBox(width: 4),
                                            Text(
                                              'Сотрудник подтвердил: ${answer.employeeConfirmedQuantity} шт.',
                                              style: TextStyle(
                                                color: Colors.green[700],
                                                fontSize: 11.sp,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    // Бейдж "Сотрудник выделил область"
                                    if (answer.selectedRegion != null) ...[
                                      SizedBox(height: 4),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                        decoration: BoxDecoration(
                                          color: Colors.cyan.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4.r),
                                          border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.crop, color: Colors.cyan, size: 14),
                                            SizedBox(width: 4),
                                            Text(
                                              'Сотрудник выделил область на фото',
                                              style: TextStyle(
                                                color: Colors.cyan[700],
                                                fontSize: 11.sp,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (answer.aiMismatch == true) ...[
                                      SizedBox(height: 8),
                                      Container(
                                        padding: EdgeInsets.all(8.w),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4.r),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.warning, color: Colors.red, size: 16),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Расхождение между сотрудником и ИИ!',
                                                style: TextStyle(
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12.sp,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Метка если сотрудник сообщил об ошибке ИИ
                                      if (answer.employeeReportedAiError == true) ...[
                                        SizedBox(height: 4),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4.r),
                                            border: Border.all(color: Colors.purple.withOpacity(0.3)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.report_problem, color: Colors.purple, size: 14),
                                              SizedBox(width: 4),
                                              Text(
                                                'Сотрудник сообщил об ошибке ИИ',
                                                style: TextStyle(
                                                  color: Colors.purple,
                                                  fontSize: 11.sp,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      // Кнопки решения админа по ошибке ИИ
                                      SizedBox(height: 8),
                                      _buildAiErrorDecisionButtons(index, answer),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                            // Фото
                            if (answer.photoUrl != null || answer.photoPath != null) ...[
                              SizedBox(height: 12),
                              Container(
                                height: 200,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12.r),
                                  border: Border.all(color: Colors.grey),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12.r),
                                  child: answer.photoUrl != null
                                      ? AppCachedImage(
                                          imageUrl: answer.photoUrl!,
                                          fit: BoxFit.cover,
                                          errorWidget: (context, error, stackTrace) {
                                            return Center(
                                              child: Icon(Icons.error),
                                            );
                                          },
                                        )
                                      : answer.photoPath != null
                                          ? (kIsWeb || answer.photoPath!.startsWith('data:') || answer.photoPath!.startsWith('http'))
                                              ? AppCachedImage(
                                                  imageUrl: answer.photoPath!,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (context, error, stackTrace) {
                                                    return Center(
                                                      child: Icon(Icons.error),
                                                    );
                                                  },
                                                )
                                              : Image.file(
                                                  File(answer.photoPath!),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return Center(
                                                      child: Icon(Icons.error),
                                                    );
                                                  },
                                                )
                                          : Center(
                                              child: Icon(Icons.image_not_supported),
                                            ),
                                ),
                              ),
                              // Кнопки верификации фото
                              SizedBox(height: 8),
                              _buildPhotoVerificationButtons(index),
                              // Кнопки для обучения ИИ (pending samples)
                              // Ищем по productId или по question (название товара)
                              if (!widget.isReadOnly)
                                _buildPendingTrainingButtons(answer.productId ?? answer.question),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


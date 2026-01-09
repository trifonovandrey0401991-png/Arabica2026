import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/recount_report_model.dart';
import '../models/recount_settings_model.dart';
import '../services/recount_service.dart';
import '../services/recount_points_service.dart';
import '../../../core/services/photo_upload_service.dart';

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
  Map<int, String> _photoVerificationStatus = {}; // photoIndex -> status
  Set<int> _verifyingPhotos = {}; // фото в процессе верификации

  @override
  void initState() {
    super.initState();
    _currentReport = widget.report;
    _selectedRating = _currentReport.adminRating;
    _loadAdminName();
    _loadPhotoVerifications();
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
        const SnackBar(
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
            const SnackBar(
              content: Text('Ошибка верификации фото'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Ошибка верификации фото: $e');
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
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: status == 'approved'
              ? Colors.green.withOpacity(0.2)
              : Colors.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              status == 'approved' ? Icons.check_circle : Icons.cancel,
              color: status == 'approved' ? Colors.green : Colors.red,
              size: 20,
            ),
            const SizedBox(width: 8),
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
      return const SizedBox.shrink();
    }

    // Показываем кнопки "Принять" и "Отклонить"
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isVerifying ? null : () => _verifyPhoto(photoIndex, 'approved'),
            icon: isVerifying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check, size: 18),
            label: const Text('Принять'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isVerifying ? null : () => _verifyPhoto(photoIndex, 'rejected'),
            icon: isVerifying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.close, size: 18),
            label: const Text('Отклонить'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _rateReport() async {
    if (_selectedRating == null || _adminName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
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
            const SnackBar(
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
            const SnackBar(
              content: Text('Ошибка постановки оценки'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Ошибка постановки оценки: $e');
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
        title: const Text('Отчет пересчета'),
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
                    color: Colors.white.withOpacity(0.95),
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
                              color: Color(0xFF004D40),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Сотрудник: ${_currentReport.employeeName}'),
                          Text('Время пересчета: ${_currentReport.formattedDuration}'),
                          Text(
                            'Дата: ${_currentReport.completedAt.day}.${_currentReport.completedAt.month}.${_currentReport.completedAt.year} '
                            '${_currentReport.completedAt.hour.toString().padLeft(2, '0')}:${_currentReport.completedAt.minute.toString().padLeft(2, '0')}',
                          ),
                          if (_currentReport.isRated) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.star, color: Colors.green),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Оценка: ${_currentReport.adminRating}/10',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (_currentReport.adminName != null)
                                    Text(
                                      ' (${_currentReport.adminName})',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          // Блок "Отчёт просрочен"
                          if (_currentReport.isExpired && !_currentReport.isRated) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.withOpacity(0.5)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Отчёт просрочен',
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (_currentReport.expiredAt != null)
                                          Text(
                                            'Просрочен: ${_currentReport.expiredAt!.day}.${_currentReport.expiredAt!.month}.${_currentReport.expiredAt!.year}',
                                            style: TextStyle(
                                              color: Colors.red[700],
                                              fontSize: 12,
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
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.withOpacity(0.5)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time, color: Colors.orange),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Отчёт не оценен вовремя',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          'Ожидает более 5 часов - только просмотр',
                                          style: TextStyle(
                                            color: Colors.orange[700],
                                            fontSize: 12,
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
                  const SizedBox(height: 16),

                  // Оценка (если еще не оценено, не просрочено и не read-only)
                  if (!_currentReport.isRated && !_currentReport.isExpired && !widget.isReadOnly)
                    Card(
                      color: Colors.white.withOpacity(0.95),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Оценка отчета:',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF004D40),
                              ),
                            ),
                            const SizedBox(height: 16),
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
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isRating ? null : _rateReport,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF004D40),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: _isRating
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Text(
                                        'Поставить оценку',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!_currentReport.isRated && !_currentReport.isExpired && !widget.isReadOnly) const SizedBox(height: 16),

                  // Ответы на вопросы
                  ..._currentReport.answers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final answer = entry.value;
                    return Card(
                      color: Colors.white.withOpacity(0.95),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: answer.grade == 1
                                        ? Colors.red
                                        : answer.grade == 2
                                            ? Colors.orange
                                            : Colors.blue,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Грейд ${answer.grade}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (answer.photoRequired)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(
                                      Icons.camera_alt,
                                      color: Colors.orange,
                                      size: 16,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Вопрос ${index + 1}: ${answer.question}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF004D40),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (answer.answer == 'сходится')
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Ответ: Сходится',
                                    style: TextStyle(
                                      color: Colors.green[700],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (answer.quantity != null)
                                    Text('Количество: ${answer.quantity}'),
                                ],
                              )
                            else if (answer.answer == 'не сходится')
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Ответ: Не сходится',
                                    style: TextStyle(
                                      color: Colors.red[700],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (answer.programBalance != null)
                                    Text('Остаток по программе: ${answer.programBalance}'),
                                  if (answer.actualBalance != null)
                                    Text('Фактический остаток: ${answer.actualBalance}'),
                                  if (answer.difference != null)
                                    Text(
                                      'Разница: ${answer.difference! > 0 ? '+' : ''}${answer.difference}',
                                      style: TextStyle(
                                        color: answer.difference! > 0
                                            ? Colors.red
                                            : Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                            // Фото
                            if (answer.photoUrl != null || answer.photoPath != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                height: 200,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: answer.photoUrl != null
                                      ? Image.network(
                                          answer.photoUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const Center(
                                              child: Icon(Icons.error),
                                            );
                                          },
                                        )
                                      : answer.photoPath != null
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
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return const Center(
                                                      child: Icon(Icons.error),
                                                    );
                                                  },
                                                )
                                          : const Center(
                                              child: Icon(Icons.image_not_supported),
                                            ),
                                ),
                              ),
                              // Кнопки верификации фото
                              const SizedBox(height: 8),
                              _buildPhotoVerificationButtons(index),
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


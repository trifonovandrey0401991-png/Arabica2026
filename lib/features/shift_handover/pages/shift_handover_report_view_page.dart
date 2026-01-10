import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shift_handover_report_model.dart';
import '../services/shift_handover_report_service.dart';

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
    );

    // Сохраняем локально
    await ShiftHandoverReport.updateReport(confirmedReport);

    // Отправляем на сервер
    final serverSuccess = await ShiftHandoverReportService.updateReport(confirmedReport);

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
  }

  Future<int?> _showRatingDialog() async {
    int selectedRating = 5;

    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Оценка сдачи смены'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Выберите оценку от 1 до 10:',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  // Отображение выбранной оценки
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: _getRatingColor(selectedRating).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$selectedRating',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: _getRatingColor(selectedRating),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
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
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(color: Colors.black, width: 2)
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              '$rating',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : Colors.black87,
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
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(selectedRating),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                  ),
                  child: const Text('Подтвердить', style: TextStyle(color: Colors.white)),
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
                            'Дата: ${_currentReport.createdAt.day.toString().padLeft(2, '0')}.${_currentReport.createdAt.month.toString().padLeft(2, '0')}.${_currentReport.createdAt.year} '
                            '${_currentReport.createdAt.hour.toString().padLeft(2, '0')}:${_currentReport.createdAt.minute.toString().padLeft(2, '0')}',
                          ),
                          // Показываем информацию о подтверждении
                          if (_currentReport.isConfirmed && _currentReport.confirmedAt != null) ...[
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Подтверждено: ${_currentReport.confirmedAt!.day.toString().padLeft(2, '0')}.${_currentReport.confirmedAt!.month.toString().padLeft(2, '0')}.${_currentReport.confirmedAt!.year} '
                                  '${_currentReport.confirmedAt!.hour.toString().padLeft(2, '0')}:${_currentReport.confirmedAt!.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            if (_currentReport.rating != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('Оценка: ', style: TextStyle(fontSize: 14)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getRatingColor(_currentReport.rating!),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${_currentReport.rating}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (_currentReport.confirmedByAdmin != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Проверил: ${_currentReport.confirmedByAdmin}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ],
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
            // Кнопка подтверждения внизу (не показываем для просроченных и read-only)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
              ),
              child: SafeArea(
                child: _currentReport.isExpired
                    ? Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cancel, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Отчет просрочен',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (_currentReport.expiredAt != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Просрочен: ${_currentReport.expiredAt!.day}.${_currentReport.expiredAt!.month}.${_currentReport.expiredAt!.year}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            const Text(
                              'Подтверждение невозможно',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : widget.isReadOnly
                    ? Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.access_time, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Отчет не подтвержден вовремя',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ожидает более 5 часов',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Только для просмотра',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _currentReport.isConfirmed
                    ? Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Row(
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
                            if (_currentReport.rating != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Оценка: ',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${_currentReport.rating}',
                                      style: TextStyle(
                                        color: _getRatingColor(_currentReport.rating!),
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (_currentReport.confirmedByAdmin != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Проверил: ${_currentReport.confirmedByAdmin}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
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

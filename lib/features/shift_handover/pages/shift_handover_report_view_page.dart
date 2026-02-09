import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shift_handover_report_model.dart';
import '../services/shift_handover_report_service.dart';
import 'package:arabica_app/shared/widgets/app_cached_image.dart';

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
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

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
      status: 'approved', // Для push-уведомления сотруднику
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
            return Dialog(
              backgroundColor: _emeraldDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Оценка сдачи смены',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Выберите оценку от 1 до 10:',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.6),
                      ),
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
                                  : Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(color: _gold, width: 2)
                                  : Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Center(
                              child: Text(
                                '$rating',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.6),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),
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
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(selectedRating),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Подтвердить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cardColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(cardIcon, color: cardColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cardTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: cardColor,
                      ),
                    ),
                    Text(
                      cardSubtitle,
                      style: TextStyle(
                        fontSize: 12,
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
            const SizedBox(height: 16),
            Divider(color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 8),
            Text(
              'Недостачи (${aiShortages.length}):',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            ...aiShortages.map((shortage) {
              final productName = shortage['productName'] ?? 'Неизвестный товар';
              final barcode = shortage['barcode'] ?? '';
              final stockQty = shortage['stockQuantity'] ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cancel, color: Colors.red, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            productName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Код: $barcode • На остатках: $stockQty шт.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: Column(
          children: [
            // Custom app bar
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Отчет сдачи смены',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
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
                padding: const EdgeInsets.all(16),
                children: [
                  // Информация об отчете
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Магазин: ${_currentReport.shopAddress}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
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
                          const SizedBox(height: 12),
                          Divider(color: Colors.white.withOpacity(0.1)),
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
                                Text(
                                  'Оценка: ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ),
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
                              style: TextStyle(
                                fontSize: 12,
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
                    const SizedBox(height: 16),
                    _buildAiVerificationCard(),
                  ],

                  const SizedBox(height: 16),

                  // Ответы на вопросы
                  ..._currentReport.answers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final answer = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Вопрос ${index + 1}: ${answer.question}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (answer.textAnswer != null)
                            Text(
                              'Ответ: ${answer.textAnswer}',
                              style: TextStyle(color: Colors.white.withOpacity(0.6)),
                            ),
                          if (answer.numberAnswer != null)
                            Text(
                              'Ответ: ${answer.numberAnswer}',
                              style: TextStyle(color: Colors.white.withOpacity(0.6)),
                            ),
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
                                            Text(
                                              'Эталон',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white.withOpacity(0.6),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              height: 200,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.white.withOpacity(0.15)),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(12),
                                                child: AppCachedImage(
                                                  imageUrl: answer.referencePhotoUrl!,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (context, error, stackTrace) {
                                                    return Center(
                                                      child: Column(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          Icon(Icons.error, size: 48, color: Colors.white.withOpacity(0.4)),
                                                          const SizedBox(height: 8),
                                                          Text(
                                                            'Ошибка загрузки\nэталонного фото',
                                                            textAlign: TextAlign.center,
                                                            style: TextStyle(
                                                              fontSize: 12,
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
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Сделано сотрудником',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white.withOpacity(0.6),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              height: 200,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.white.withOpacity(0.15)),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(12),
                                                child: answer.photoPath != null
                                                    ? (kIsWeb || answer.photoPath!.startsWith('data:') || answer.photoPath!.startsWith('http'))
                                                        ? AppCachedImage(
                                                            imageUrl: answer.photoPath!,
                                                            fit: BoxFit.cover,
                                                            errorWidget: (context, error, stackTrace) {
                                                              return Center(
                                                                child: Icon(Icons.error, color: Colors.white.withOpacity(0.4)),
                                                              );
                                                            },
                                                          )
                                                        : Image.file(
                                                            File(answer.photoPath!),
                                                            fit: BoxFit.cover,
                                                          )
                                                    : answer.photoUrl != null
                                                        ? AppCachedImage(
                                                            imageUrl: answer.photoUrl!,
                                                            fit: BoxFit.cover,
                                                            errorWidget: (context, error, stackTrace) {
                                                              return Center(
                                                                child: Column(
                                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                                  children: [
                                                                    Icon(Icons.error, size: 48, color: Colors.white.withOpacity(0.4)),
                                                                    const SizedBox(height: 8),
                                                                    Text(
                                                                      'Ошибка загрузки фото',
                                                                      style: TextStyle(
                                                                        fontSize: 12,
                                                                        color: Colors.white.withOpacity(0.4),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              );
                                                            },
                                                          )
                                                        : Center(
                                                            child: Icon(Icons.image, color: Colors.white.withOpacity(0.4)),
                                                          ),
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
                                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: answer.photoPath != null
                                      ? (kIsWeb || answer.photoPath!.startsWith('data:') || answer.photoPath!.startsWith('http'))
                                          ? AppCachedImage(
                                              imageUrl: answer.photoPath!,
                                              fit: BoxFit.cover,
                                              errorWidget: (context, error, stackTrace) {
                                                return Center(
                                                  child: Icon(Icons.error, color: Colors.white.withOpacity(0.4)),
                                                );
                                              },
                                            )
                                          : Image.file(
                                              File(answer.photoPath!),
                                              fit: BoxFit.cover,
                                            )
                                      : answer.photoUrl != null
                                          ? AppCachedImage(
                                              imageUrl: answer.photoUrl!,
                                              fit: BoxFit.cover,
                                              errorWidget: (context, error, stackTrace) {
                                                return Center(
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(Icons.error, size: 48, color: Colors.white.withOpacity(0.4)),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        'Ошибка загрузки фото',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.white.withOpacity(0.4),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            )
                                          : Center(
                                              child: Icon(Icons.image, color: Colors.white.withOpacity(0.4)),
                                            ),
                                ),
                              ),
                          ],
                        ],
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
                color: _night.withOpacity(0.8),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: SafeArea(
                child: _currentReport.isExpired
                    ? Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cancel, color: Colors.red),
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
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'Подтверждение невозможно',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
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
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.access_time, color: Colors.orange),
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
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Только для просмотра',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
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
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green),
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
                                  Text(
                                    'Оценка: ',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 14,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
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
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
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
                            backgroundColor: _gold,
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

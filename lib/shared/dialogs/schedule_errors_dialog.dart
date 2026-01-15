import 'package:flutter/material.dart';
import '../../features/work_schedule/work_schedule_validator.dart';

/// Диалог отображения ошибок в графике
class ScheduleErrorsDialog extends StatelessWidget {
  final ScheduleValidationResult validationResult;
  final Function(ScheduleError) onErrorTap;

  const ScheduleErrorsDialog({
    super.key,
    required this.validationResult,
    required this.onErrorTap,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Ошибки в заполнении графика'),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.6,
        child: ListView(
          children: [
            // Критичные ошибки
            if (validationResult.criticalErrors.isNotEmpty) ...[
              _buildSectionHeader('Критичные ошибки', Colors.red, validationResult.criticalErrors.length),
              const SizedBox(height: 8),
              ...validationResult.criticalErrors.map((error) =>
                _buildErrorTile(error, Colors.red, context)
              ),
              const SizedBox(height: 16),
            ],

            // Предупреждения
            if (validationResult.warnings.isNotEmpty) ...[
              _buildSectionHeader('Предупреждения', Colors.orange, validationResult.warnings.length),
              const SizedBox(height: 8),
              ...validationResult.warnings.map((error) =>
                _buildErrorTile(error, Colors.orange, context)
              ),
            ],

            // Если нет ошибок
            if (!validationResult.hasErrors)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 64),
                      SizedBox(height: 16),
                      Text(
                        'Ошибок не найдено!',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }

  /// Заголовок секции
  Widget _buildSectionHeader(String title, Color color, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Плитка ошибки
  Widget _buildErrorTile(ScheduleError error, Color color, BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          error.isCritical ? Icons.error : Icons.warning,
          color: color,
        ),
        title: Text(
          error.displayMessage,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          _formatErrorDate(error.date),
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: const Icon(Icons.arrow_forward, color: Color(0xFF004D40)),
        onTap: () {
          Navigator.of(context).pop();
          onErrorTap(error);
        },
      ),
    );
  }

  /// Форматировать дату ошибки
  String _formatErrorDate(DateTime date) {
    final weekday = _getWeekdayName(date.weekday);
    final monthName = _getMonthName(date.month);
    return '$weekday, ${date.day} $monthName ${date.year}';
  }

  /// Получить название дня недели
  String _getWeekdayName(int weekday) {
    const weekdays = {
      1: 'Понедельник',
      2: 'Вторник',
      3: 'Среда',
      4: 'Четверг',
      5: 'Пятница',
      6: 'Суббота',
      7: 'Воскресенье',
    };
    return weekdays[weekday] ?? '';
  }

  /// Получить название месяца
  String _getMonthName(int month) {
    const months = {
      1: 'января',
      2: 'февраля',
      3: 'марта',
      4: 'апреля',
      5: 'мая',
      6: 'июня',
      7: 'июля',
      8: 'августа',
      9: 'сентября',
      10: 'октября',
      11: 'ноября',
      12: 'декабря',
    };
    return months[month] ?? '';
  }
}

import 'package:flutter/material.dart';

/// Утилиты для работы с эффективностью
class EfficiencyUtils {
  /// Получить название месяца
  static String getMonthName(int month, int year) {
    const months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];

    if (month < 1 || month > 12) {
      return 'Неизвестный месяц';
    }

    return '${months[month - 1]} $year';
  }

  /// Сгенерировать список последних 12 месяцев
  static List<Map<String, dynamic>> generateMonthsList() {
    final now = DateTime.now();
    final List<Map<String, dynamic>> months = [];

    for (int i = 0; i < 12; i++) {
      final date = DateTime(now.year, now.month - i, 1);
      months.add({
        'year': date.year,
        'month': date.month,
        'name': getMonthName(date.month, date.year),
      });
    }

    return months;
  }

  /// Форматировать число баллов
  static String formatPoints(double points) {
    if (points >= 0) {
      return '+${points.toStringAsFixed(1)}';
    }
    return points.toStringAsFixed(1);
  }

  /// Константы цветов для эффективности
  static const primaryColor = Color(0xFF004D40);
  static const secondaryColor = Color(0xFFE0F2F1);
}

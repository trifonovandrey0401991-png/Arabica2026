import 'package:flutter/material.dart';
import '../models/efficiency_data_model.dart';

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

  /// Получить иконку для категории эффективности
  static IconData getCategoryIcon(EfficiencyCategory category) {
    switch (category) {
      case EfficiencyCategory.shift:
        return Icons.swap_horiz;
      case EfficiencyCategory.recount:
        return Icons.inventory_2;
      case EfficiencyCategory.shiftHandover:
        return Icons.assignment_turned_in;
      case EfficiencyCategory.attendance:
        return Icons.access_time;
      case EfficiencyCategory.test:
        return Icons.quiz;
      case EfficiencyCategory.reviews:
        return Icons.star;
      case EfficiencyCategory.productSearch:
        return Icons.search;
      case EfficiencyCategory.rko:
        return Icons.receipt_long;
      case EfficiencyCategory.orders:
        return Icons.shopping_cart;
      case EfficiencyCategory.shiftPenalty:
        return Icons.warning;
      case EfficiencyCategory.tasks:
        return Icons.assignment;
    }
  }

  /// Получить цвет для категории эффективности
  static Color getCategoryColor(EfficiencyCategory category) {
    switch (category) {
      case EfficiencyCategory.shift:
        return Colors.blue;
      case EfficiencyCategory.recount:
        return Colors.purple;
      case EfficiencyCategory.shiftHandover:
        return Colors.teal;
      case EfficiencyCategory.attendance:
        return Colors.orange;
      case EfficiencyCategory.test:
        return Colors.indigo;
      case EfficiencyCategory.reviews:
        return Colors.amber;
      case EfficiencyCategory.productSearch:
        return Colors.cyan;
      case EfficiencyCategory.rko:
        return Colors.brown;
      case EfficiencyCategory.orders:
        return Colors.green;
      case EfficiencyCategory.shiftPenalty:
        return Colors.red;
      case EfficiencyCategory.tasks:
        return Colors.deepPurple;
    }
  }
}

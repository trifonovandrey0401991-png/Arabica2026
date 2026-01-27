import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  // ===== ЭКСПОРТ ДАННЫХ =====

  /// Форматировать данные эффективности для экспорта (текстовый формат)
  ///
  /// [summary] - сводка эффективности (магазина или сотрудника)
  /// [monthName] - название месяца для заголовка
  /// [isShop] - true для магазина, false для сотрудника
  static String formatForExport({
    required EfficiencySummary summary,
    required String monthName,
    required bool isShop,
  }) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('dd.MM.yyyy');

    // Заголовок
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('ЭФФЕКТИВНОСТЬ: ${summary.entityName}');
    buffer.writeln('Период: $monthName');
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln();

    // Общие баллы
    buffer.writeln('ИТОГО: ${summary.formattedTotal} баллов');
    buffer.writeln('  Заработано: +${summary.earnedPoints.toStringAsFixed(1)}');
    buffer.writeln('  Потеряно:   -${summary.lostPoints.toStringAsFixed(1)}');
    buffer.writeln();

    // По категориям
    buffer.writeln('ПО КАТЕГОРИЯМ:');
    buffer.writeln('───────────────────────────────────────');

    // Категории уже отсортированы в categorySummaries
    for (final category in summary.categorySummaries) {
      final formattedPoints = category.points >= 0
          ? '+${category.points.toStringAsFixed(2)}'
          : category.points.toStringAsFixed(2);
      buffer.writeln('  ${category.name.padRight(25)} $formattedPoints');
    }
    buffer.writeln();

    // Записи (последние 30)
    buffer.writeln('ЗАПИСИ (${summary.recordsCount} всего):');
    buffer.writeln('───────────────────────────────────────');

    final sortedRecords = List<EfficiencyRecord>.from(summary.records)
      ..sort((a, b) => b.date.compareTo(a.date));

    final recentRecords = sortedRecords.take(30);

    for (final record in recentRecords) {
      final date = dateFormat.format(record.date);
      final points = record.formattedPoints;
      final category = record.categoryName;
      final secondary = isShop ? record.employeeName : record.shopAddress;

      buffer.write('  $date  $category');
      if (secondary.isNotEmpty) {
        buffer.write(' ($secondary)');
      }
      buffer.writeln('  $points');
    }

    buffer.writeln();
    buffer.writeln('───────────────────────────────────────');
    buffer.writeln('Экспортировано: ${dateFormat.format(DateTime.now())}');

    return buffer.toString();
  }

  /// Форматировать данные эффективности в CSV формат
  static String formatForExportCsv({
    required EfficiencySummary summary,
    required String monthName,
    required bool isShop,
  }) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('dd.MM.yyyy');

    // Заголовок CSV
    buffer.writeln('Дата,Категория,${isShop ? "Сотрудник" : "Магазин"},Значение,Баллы');

    // Записи
    final sortedRecords = List<EfficiencyRecord>.from(summary.records)
      ..sort((a, b) => b.date.compareTo(a.date));

    for (final record in sortedRecords) {
      final date = dateFormat.format(record.date);
      final category = record.categoryName;
      final secondary = isShop ? record.employeeName : record.shopAddress;
      final rawValue = record.formattedRawValue;
      final points = record.points.toStringAsFixed(2);

      // Экранируем запятые в тексте
      final escapedSecondary = secondary.contains(',')
          ? '"$secondary"'
          : secondary;

      buffer.writeln('$date,$category,$escapedSecondary,$rawValue,$points');
    }

    return buffer.toString();
  }
}

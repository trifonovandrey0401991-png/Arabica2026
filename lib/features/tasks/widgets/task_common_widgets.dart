import 'package:flutter/material.dart';
import '../models/task_model.dart';

/// Общие константы и виджеты для модуля задач
class TaskStyles {
  // Основные цвета
  static const primaryColor = Color(0xFF004D40);
  static const accentColor = Color(0xFF00897B);

  // Градиенты для статусов
  static const orangeGradient = [Color(0xFFFF6B35), Color(0xFFF7C200)];
  static const greenGradient = [Color(0xFF00b09b), Color(0xFF96c93d)];
  static const redGradient = [Color(0xFFE53935), Color(0xFFFF5252)];
  static const blueGradient = [Color(0xFF2196F3), Color(0xFF64B5F6)];
  static const greyGradient = [Color(0xFF757575), Color(0xFF9E9E9E)];

  /// Получить градиент для статуса задачи
  static List<Color> getStatusGradient(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return orangeGradient;
      case TaskStatus.submitted:
        return blueGradient;
      case TaskStatus.approved:
        return greenGradient;
      case TaskStatus.rejected:
      case TaskStatus.expired:
      case TaskStatus.declined:
        return redGradient;
    }
  }

  /// Получить иконку для статуса задачи
  static IconData getStatusIcon(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return Icons.pending_actions;
      case TaskStatus.submitted:
        return Icons.hourglass_top;
      case TaskStatus.approved:
        return Icons.check_circle;
      case TaskStatus.rejected:
        return Icons.cancel;
      case TaskStatus.expired:
        return Icons.timer_off;
      case TaskStatus.declined:
        return Icons.block;
    }
  }

  /// Получить цвет для статуса (одиночный цвет, не градиент)
  static Color getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return Colors.orange;
      case TaskStatus.submitted:
        return Colors.blue;
      case TaskStatus.approved:
        return Colors.green;
      case TaskStatus.rejected:
        return Colors.red;
      case TaskStatus.expired:
        return Colors.grey;
      case TaskStatus.declined:
        return Colors.deepOrange;
    }
  }

  /// Получить иконку для типа ответа
  static IconData getResponseTypeIcon(TaskResponseType type) {
    switch (type) {
      case TaskResponseType.photo:
        return Icons.photo_camera;
      case TaskResponseType.photoAndText:
        return Icons.photo_library;
      case TaskResponseType.text:
        return Icons.text_fields;
    }
  }

  /// Получить текст для типа ответа
  static String getResponseTypeText(TaskResponseType type) {
    switch (type) {
      case TaskResponseType.photo:
        return 'Только фото';
      case TaskResponseType.photoAndText:
        return 'Фото и текст';
      case TaskResponseType.text:
        return 'Только текст';
    }
  }
}

/// Утилиты для форматирования данных задач
class TaskUtils {
  /// Форматировать дату и время
  static String formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Форматировать только дату
  static String formatDate(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year}';
  }

  /// Форматировать короткую дату (dd.MM HH:mm)
  static String formatShortDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Проверить, просрочена ли задача
  static bool isOverdue(DateTime deadline) {
    return DateTime.now().isAfter(deadline);
  }

  /// Получить название месяца
  static String getMonthName(int month, int year) {
    const months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    if (month < 1 || month > 12) return 'Неизвестный месяц';
    return '${months[month - 1]} $year';
  }

  /// Сгенерировать список последних N месяцев
  static List<Map<String, dynamic>> generateMonthsList({int count = 12}) {
    final now = DateTime.now();
    final List<Map<String, dynamic>> months = [];

    for (int i = 0; i < count; i++) {
      final date = DateTime(now.year, now.month - i, 1);
      months.add({
        'year': date.year,
        'month': date.month,
        'name': getMonthName(date.month, date.year),
        'key': '${date.year}-${date.month.toString().padLeft(2, '0')}',
      });
    }

    return months;
  }
}

/// Виджет статусного бейджа для задачи
class TaskStatusBadge extends StatelessWidget {
  final TaskStatus status;
  final bool showIcon;
  final double? fontSize;

  const TaskStatusBadge({
    super.key,
    required this.status,
    this.showIcon = true,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = TaskStyles.getStatusGradient(status);
    final icon = TaskStyles.getStatusIcon(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient.map((c) => c.withOpacity(0.15)).toList()),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(icon, size: 14, color: gradient[0]),
            const SizedBox(width: 4),
          ],
          Text(
            status.displayName,
            style: TextStyle(
              color: gradient[0],
              fontSize: fontSize ?? 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Виджет иконки статуса с градиентом
class TaskStatusIconBox extends StatelessWidget {
  final TaskStatus status;
  final double size;

  const TaskStatusIconBox({
    super.key,
    required this.status,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = TaskStyles.getStatusGradient(status);
    final icon = TaskStyles.getStatusIcon(status);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: size * 0.5,
      ),
    );
  }
}

/// Виджет бейджа с баллами
class TaskPointsBadge extends StatelessWidget {
  final double points;
  final double? fontSize;

  const TaskPointsBadge({
    super.key,
    required this.points,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = points >= 0;
    final color = isPositive ? Colors.green : Colors.red;
    final text = isPositive ? '+${points.toStringAsFixed(0)}' : points.toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize ?? 11,
          color: color[700],
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Виджет пустого состояния для списка задач
class TaskEmptyState extends StatelessWidget {
  final String message;
  final String? subtitle;
  final IconData? icon;
  final List<Color>? gradientColors;

  const TaskEmptyState({
    super.key,
    required this.message,
    this.subtitle,
    this.icon,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gradientColors ?? TaskStyles.greyGradient;
    final displayIcon = icon ?? Icons.inbox;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors.map((c) => c.withOpacity(0.15)).toList()),
              shape: BoxShape.circle,
            ),
            child: Icon(
              displayIcon,
              size: 48,
              color: colors[0],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Виджет заголовка секции
class TaskSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;

  const TaskSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: TaskStyles.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: TaskStyles.primaryColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: TaskStyles.primaryColor,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: TaskStyles.primaryColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Виджет вкладки с бейджем
class TaskTabWithBadge extends StatelessWidget {
  final String text;
  final int count;
  final List<Color> gradientColors;

  const TaskTabWithBadge({
    super.key,
    required this.text,
    required this.count,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: gradientColors[0].withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Утилиты для форматирования дат
class DateFormatter {
  static const List<String> _monthNamesRu = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
  ];

  /// Форматирует месяц из формата YYYY-MM в "Месяц Год"
  /// Например: "2026-01" -> "Январь 2026"
  static String formatMonthKey(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length == 2) {
      final year = parts[0];
      final month = int.tryParse(parts[1]) ?? 0;
      if (month >= 1 && month <= 12) {
        return '${_monthNamesRu[month - 1]} $year';
      }
    }
    return monthKey;
  }

  /// Безопасно извлекает дату из строки (первые 10 символов)
  /// Если строка короче - возвращает её целиком
  static String extractDate(String dateString) {
    if (dateString.length >= 10) {
      return dateString.substring(0, 10);
    }
    return dateString;
  }

  /// Получить название месяца по номеру (1-12)
  static String getMonthName(int month) {
    if (month >= 1 && month <= 12) {
      return _monthNamesRu[month - 1];
    }
    return '';
  }

  /// Форматирует дату в формат dd.MM.yyyy
  /// Например: DateTime(2026, 1, 31) -> "31.01.2026"
  static String formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  /// Форматирует дату в короткий формат dd.MM
  /// Например: DateTime(2026, 1, 31) -> "31.01"
  static String formatShortDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month';
  }

  /// Форматирует дату и время в формат dd.MM.yyyy HH:mm
  /// Например: DateTime(2026, 1, 31, 14, 30) -> "31.01.2026 14:30"
  static String formatDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day.$month.${dateTime.year} $hour:$minute';
  }

  /// Форматирует дату и время в короткий формат dd.MM HH:mm
  /// Например: DateTime(2026, 1, 31, 14, 30) -> "31.01 14:30"
  static String formatShortDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day.$month $hour:$minute';
  }

  /// Генерирует ключ месяца для API в формате YYYY-MM
  /// Например: DateTime(2026, 1, 31) -> "2026-01"
  static String toMonthKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }

  /// Форматирует время в формат HH:mm
  /// Например: DateTime(2026, 1, 31, 14, 30) -> "14:30"
  static String formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Форматирует дату для имени файла (без спецсимволов)
  /// Например: DateTime(2026, 1, 31) -> "31_01_2026"
  static String formatForFilename(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '${day}_${month}_${date.year}';
  }
}

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
}

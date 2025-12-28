/// Утилиты для нормализации данных KPI
class KPINormalizers {
  /// Нормализовать адрес магазина
  /// Убирает лишние пробелы и приводит к нижнему регистру для корректного сравнения
  static String normalizeShopAddress(String address) {
    return address.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Нормализовать имя сотрудника
  /// Убирает лишние пробелы и приводит к нижнему регистру для корректного сравнения
  static String normalizeEmployeeName(String name) {
    return name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Нормализовать дату (убрать время, оставить только год-месяц-день)
  static DateTime normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Нормализовать дату для запроса (с временем 00:00:00)
  static DateTime normalizeDateForQuery(DateTime date) {
    return DateTime(date.year, date.month, date.day, 0, 0, 0);
  }

  /// Создать ключ магазин+дата с нормализацией
  static String createShopDateKey(String shopAddress, DateTime date) {
    final normalizedAddress = normalizeShopAddress(shopAddress);
    final normalizedDate = normalizeDate(date);
    return '${normalizedAddress}_${normalizedDate.year}_${normalizedDate.month}_${normalizedDate.day}';
  }

  /// Создать ключ кэша для данных магазина за день
  static String createShopDayCacheKey(String shopAddress, DateTime date) {
    final normalizedDate = normalizeDate(date);
    return 'kpi_shop_day_${shopAddress}_${normalizedDate.year}_${normalizedDate.month}_${normalizedDate.day}';
  }

  /// Создать ключ кэша для данных сотрудника
  static String createEmployeeCacheKey(String employeeName) {
    return 'kpi_employee_$employeeName';
  }

  /// Создать ключ кэша для данных сотрудника по магазинам
  static String createEmployeeShopsCacheKey(String employeeName) {
    return 'kpi_employee_shops_$employeeName';
  }
}

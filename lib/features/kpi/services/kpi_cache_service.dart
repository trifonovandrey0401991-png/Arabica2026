import '../../../core/utils/cache_manager.dart';
import '../../../core/utils/logger.dart';
import '../../../core/constants/app_constants.dart';
import '../models/kpi_models.dart';
import 'kpi_normalizers.dart';

/// Сервис для кэширования KPI данных
class KPICacheService {
  /// Получить данные магазина за день из кэша
  /// Для недавних дат (последние 7 дней) кэш всегда очищается
  static KPIShopDayData? getShopDayData(String shopAddress, DateTime date) {
    final normalizedDate = KPINormalizers.normalizeDate(date);

    // Проверяем, является ли дата недавней (последние 7 дней)
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysDiff = normalizedDate.difference(today).inDays;

    final cacheKey = KPINormalizers.createShopDayCacheKey(shopAddress, normalizedDate);

    // Для недавних дат (последние 7 дней) всегда очищаем кэш, чтобы видеть свежие данные
    if (daysDiff >= -7 && daysDiff <= 0) {
      CacheManager.remove(cacheKey);
      Logger.debug('🔄 Кэш очищен для недавней даты: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day} (разница: $daysDiff дней)');
      return null;
    }

    // Для старых дат используем кэш, если он есть
    final cached = CacheManager.get<KPIShopDayData>(cacheKey);
    if (cached != null) {
      Logger.debug('KPI данные магазина загружены из кэша для даты: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
    }
    return cached;
  }

  /// Сохранить данные магазина за день в кэш
  static void saveShopDayData(String shopAddress, DateTime date, KPIShopDayData data) {
    final normalizedDate = KPINormalizers.normalizeDate(date);
    final cacheKey = KPINormalizers.createShopDayCacheKey(shopAddress, normalizedDate);
    CacheManager.set(cacheKey, data, duration: AppConstants.cacheDuration);
    Logger.debug('💾 KPI данные магазина сохранены в кэш для даты: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
  }

  /// Получить данные сотрудника из кэша
  static KPIEmployeeData? getEmployeeData(String employeeName) {
    final cacheKey = KPINormalizers.createEmployeeCacheKey(employeeName);
    final cached = CacheManager.get<KPIEmployeeData>(cacheKey);
    if (cached != null) {
      Logger.debug('KPI данные сотрудника загружены из кэша: $employeeName');
    }
    return cached;
  }

  /// Сохранить данные сотрудника в кэш
  static void saveEmployeeData(String employeeName, KPIEmployeeData data) {
    final cacheKey = KPINormalizers.createEmployeeCacheKey(employeeName);
    CacheManager.set(cacheKey, data, duration: AppConstants.cacheDuration);
    Logger.debug('💾 KPI данные сотрудника сохранены в кэш: $employeeName');
  }

  /// Получить данные сотрудника по магазинам из кэша
  static KPIEmployeeShopDaysData? getEmployeeShopDaysData(String employeeName) {
    final cacheKey = KPINormalizers.createEmployeeShopsCacheKey(employeeName);
    final cached = CacheManager.get<KPIEmployeeShopDaysData>(cacheKey);
    if (cached != null) {
      Logger.debug('KPI данные сотрудника по магазинам загружены из кэша: $employeeName');
    }
    return cached;
  }

  /// Сохранить данные сотрудника по магазинам в кэш
  static void saveEmployeeShopDaysData(String employeeName, KPIEmployeeShopDaysData data) {
    final cacheKey = KPINormalizers.createEmployeeShopsCacheKey(employeeName);
    CacheManager.set(cacheKey, data, duration: AppConstants.cacheDuration);
    Logger.debug('💾 KPI данные сотрудника по магазинам сохранены в кэш: $employeeName');
  }

  /// Очистить весь кэш KPI
  static void clearAll() {
    CacheManager.clear();
    Logger.debug('🗑️ Весь кэш KPI очищен');
  }

  /// Очистить кэш для конкретной даты и магазина
  static void clearForDate(String shopAddress, DateTime date) {
    final normalizedDate = KPINormalizers.normalizeDate(date);
    final cacheKey = KPINormalizers.createShopDayCacheKey(shopAddress, normalizedDate);
    CacheManager.remove(cacheKey);
    Logger.debug('🗑️ Кэш очищен для магазина "$shopAddress" за ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
  }

  /// Очистить весь кэш для магазина
  static void clearForShop(String shopAddress) {
    // Очищаем весь кэш (можно оптимизировать, если будет нужно)
    CacheManager.clear();
    Logger.debug('🗑️ Весь кэш очищен для магазина "$shopAddress"');
  }

  /// Получить список всех сотрудников из кэша
  static List<String>? getAllEmployees() {
    const cacheKey = 'kpi_all_employees';
    final cached = CacheManager.get<List<String>>(cacheKey);
    if (cached != null) {
      Logger.debug('Список сотрудников загружен из кэша');
    }
    return cached;
  }

  /// Сохранить список всех сотрудников в кэш
  static void saveAllEmployees(List<String> employees) {
    const cacheKey = 'kpi_all_employees';
    CacheManager.set(cacheKey, employees, duration: AppConstants.cacheDuration);
    Logger.debug('💾 Список сотрудников сохранен в кэш: ${employees.length} записей');
  }

  /// Получить список всех магазинов из кэша
  static List<String>? getAllShops() {
    const cacheKey = 'kpi_all_shops';
    final cached = CacheManager.get<List<String>>(cacheKey);
    if (cached != null) {
      Logger.debug('Список магазинов загружен из кэша');
    }
    return cached;
  }

  /// Сохранить список всех магазинов в кэш
  static void saveAllShops(List<String> shops) {
    const cacheKey = 'kpi_all_shops';
    CacheManager.set(cacheKey, shops, duration: AppConstants.cacheDuration);
    Logger.debug('💾 Список магазинов сохранен в кэш: ${shops.length} записей');
  }
}

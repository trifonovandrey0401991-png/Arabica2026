import '../../../core/utils/cache_manager.dart';
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
      return null;
    }

    // Для старых дат используем кэш, если он есть
    return CacheManager.get<KPIShopDayData>(cacheKey);
  }

  /// Сохранить данные магазина за день в кэш
  static void saveShopDayData(String shopAddress, DateTime date, KPIShopDayData data) {
    final normalizedDate = KPINormalizers.normalizeDate(date);
    final cacheKey = KPINormalizers.createShopDayCacheKey(shopAddress, normalizedDate);
    CacheManager.set(cacheKey, data, duration: AppConstants.cacheDuration);
  }

  /// Получить данные сотрудника из кэша
  static KPIEmployeeData? getEmployeeData(String employeeName) {
    final cacheKey = KPINormalizers.createEmployeeCacheKey(employeeName);
    return CacheManager.get<KPIEmployeeData>(cacheKey);
  }

  /// Сохранить данные сотрудника в кэш
  static void saveEmployeeData(String employeeName, KPIEmployeeData data) {
    final cacheKey = KPINormalizers.createEmployeeCacheKey(employeeName);
    CacheManager.set(cacheKey, data, duration: AppConstants.cacheDuration);
  }

  /// Получить данные сотрудника по магазинам из кэша
  static KPIEmployeeShopDaysData? getEmployeeShopDaysData(String employeeName) {
    final cacheKey = KPINormalizers.createEmployeeShopsCacheKey(employeeName);
    return CacheManager.get<KPIEmployeeShopDaysData>(cacheKey);
  }

  /// Сохранить данные сотрудника по магазинам в кэш
  static void saveEmployeeShopDaysData(String employeeName, KPIEmployeeShopDaysData data) {
    final cacheKey = KPINormalizers.createEmployeeShopsCacheKey(employeeName);
    CacheManager.set(cacheKey, data, duration: AppConstants.cacheDuration);
  }

  /// Очистить весь кэш KPI
  static void clearAll() {
    CacheManager.clear();
  }

  /// Очистить кэш для конкретной даты и магазина
  static void clearForDate(String shopAddress, DateTime date) {
    final normalizedDate = KPINormalizers.normalizeDate(date);
    final cacheKey = KPINormalizers.createShopDayCacheKey(shopAddress, normalizedDate);
    CacheManager.remove(cacheKey);
  }

  /// Очистить весь кэш для магазина
  static void clearForShop(String shopAddress) {
    // Очищаем весь кэш (можно оптимизировать, если будет нужно)
    CacheManager.clear();
  }

  /// Получить список всех сотрудников из кэша
  static List<String>? getAllEmployees() {
    const cacheKey = 'kpi_all_employees';
    return CacheManager.get<List<String>>(cacheKey);
  }

  /// Сохранить список всех сотрудников в кэш
  static void saveAllEmployees(List<String> employees) {
    const cacheKey = 'kpi_all_employees';
    CacheManager.set(cacheKey, employees, duration: AppConstants.cacheDuration);
  }

  /// Получить список всех магазинов из кэша
  static List<String>? getAllShops() {
    const cacheKey = 'kpi_all_shops';
    return CacheManager.get<List<String>>(cacheKey);
  }

  /// Сохранить список всех магазинов в кэш
  static void saveAllShops(List<String> shops) {
    const cacheKey = 'kpi_all_shops';
    CacheManager.set(cacheKey, shops, duration: AppConstants.cacheDuration);
  }
}

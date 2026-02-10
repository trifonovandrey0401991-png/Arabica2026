import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/kpi_models.dart';
import '../../../core/utils/logger.dart';

/// Сервис персистентного хранения KPI данных (SharedPreferences).
///
/// Используется как fallback при отсутствии интернета:
/// - При успешном API запросе данные сохраняются в persistence
/// - При ошибке сети данные загружаются из persistence
class KPIPersistenceService {
  static const String _prefix = 'kpi_persist_';

  // ====== Employee Shop Days Data ======

  /// Сохранить данные сотрудника по магазинам и дням
  static Future<void> saveEmployeeShopDaysData(
    String employeeName,
    KPIEmployeeShopDaysData data,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(data.toJson());
      await prefs.setString('${_prefix}employee_shopdays_$employeeName', json);
    } catch (e) {
      Logger.debug('KPI Persistence: ошибка сохранения данных сотрудника: $e');
    }
  }

  /// Загрузить данные сотрудника по магазинам и дням
  static Future<KPIEmployeeShopDaysData?> getEmployeeShopDaysData(
    String employeeName,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('${_prefix}employee_shopdays_$employeeName');
      if (json == null) return null;

      final map = jsonDecode(json) as Map<String, dynamic>;
      return KPIEmployeeShopDaysData.fromJson(map);
    } catch (e) {
      Logger.debug('KPI Persistence: ошибка загрузки данных сотрудника: $e');
      return null;
    }
  }

  // ====== All Employees List ======

  /// Сохранить список всех сотрудников
  static Future<void> saveAllEmployees(List<String> employees) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(employees);
      await prefs.setString('${_prefix}all_employees', json);
    } catch (e) {
      Logger.debug('KPI Persistence: ошибка сохранения списка сотрудников: $e');
    }
  }

  /// Загрузить список всех сотрудников
  static Future<List<String>?> getAllEmployees() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('${_prefix}all_employees');
      if (json == null) return null;

      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>();
    } catch (e) {
      Logger.debug('KPI Persistence: ошибка загрузки списка сотрудников: $e');
      return null;
    }
  }

  // ====== All Shops List ======

  /// Сохранить список всех магазинов
  static Future<void> saveAllShops(List<String> shops) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(shops);
      await prefs.setString('${_prefix}all_shops', json);
    } catch (e) {
      Logger.debug('KPI Persistence: ошибка сохранения списка магазинов: $e');
    }
  }

  /// Загрузить список всех магазинов
  static Future<List<String>?> getAllShops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('${_prefix}all_shops');
      if (json == null) return null;

      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>();
    } catch (e) {
      Logger.debug('KPI Persistence: ошибка загрузки списка магазинов: $e');
      return null;
    }
  }

  // ====== Управление ======

  /// Очистить все персистентные KPI данные
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
      Logger.debug('KPI Persistence: очищено ${keys.length} записей');
    } catch (e) {
      Logger.debug('KPI Persistence: ошибка очистки: $e');
    }
  }
}

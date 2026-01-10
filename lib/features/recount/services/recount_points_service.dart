import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/recount_points_model.dart';
import '../models/recount_settings_model.dart';
import '../../../core/utils/logger.dart';
import '../../../core/constants/api_constants.dart';

/// Сервис для работы с баллами пересчёта
class RecountPointsService {
  static const String _baseUrl = '${ApiConstants.serverUrl}/api';

  /// Получить баллы всех сотрудников
  static Future<List<RecountPoints>> getAllPoints() async {
    try {
      Logger.debug('Загружаем баллы всех сотрудников...');

      final response = await http.get(
        Uri.parse('$_baseUrl/recount-points'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['points'] != null) {
          final List<dynamic> pointsList = data['points'];
          final result = pointsList
              .map((json) => RecountPoints.fromJson(json))
              .toList();
          Logger.success('Загружено баллов: ${result.length}');
          return result;
        }
      }

      Logger.warning('Не удалось загрузить баллы: ${response.statusCode}');
      return [];
    } catch (e) {
      Logger.error('Ошибка загрузки баллов: $e');
      return [];
    }
  }

  /// Получить баллы конкретного сотрудника по телефону
  static Future<RecountPoints?> getPointsByPhone(String phone) async {
    try {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s+]'), '');
      Logger.debug('Загружаем баллы сотрудника: $normalizedPhone');

      final response = await http.get(
        Uri.parse('$_baseUrl/recount-points/$normalizedPhone'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['points'] != null) {
          return RecountPoints.fromJson(data['points']);
        }
      }

      return null;
    } catch (e) {
      Logger.error('Ошибка загрузки баллов сотрудника: $e');
      return null;
    }
  }

  /// Обновить баллы сотрудника (ручная установка админом)
  static Future<bool> updatePoints({
    required String phone,
    required double points,
    required String adminName,
    String? employeeName,
  }) async {
    try {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s+]'), '');
      Logger.debug('Обновляем баллы сотрудника: $normalizedPhone -> $points');

      final response = await http.put(
        Uri.parse('$_baseUrl/recount-points/$normalizedPhone'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'points': points,
          'adminName': adminName,
          'employeeName': employeeName,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          Logger.success('Баллы обновлены');
          return true;
        }
      }

      Logger.warning('Не удалось обновить баллы: ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('Ошибка обновления баллов: $e');
      return false;
    }
  }

  /// Инициализировать баллы всем сотрудникам (85 по умолчанию)
  static Future<int> initializeAllPoints() async {
    try {
      Logger.debug('Инициализируем баллы для всех сотрудников...');

      final response = await http.post(
        Uri.parse('$_baseUrl/recount-points/init'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final count = data['count'] ?? 0;
          Logger.success('Инициализировано: $count сотрудников');
          return count;
        }
      }

      return 0;
    } catch (e) {
      Logger.error('Ошибка инициализации баллов: $e');
      return 0;
    }
  }

  /// Получить общие настройки пересчёта
  static Future<RecountSettings> getSettings() async {
    try {
      Logger.debug('Загружаем настройки пересчёта...');

      final response = await http.get(
        Uri.parse('$_baseUrl/recount-settings'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['settings'] != null) {
          return RecountSettings.fromJson(data['settings']);
        }
      }

      // Возвращаем настройки по умолчанию
      return RecountSettings();
    } catch (e) {
      Logger.error('Ошибка загрузки настроек: $e');
      return RecountSettings();
    }
  }

  /// Обновить общие настройки пересчёта
  static Future<bool> updateSettings(RecountSettings settings) async {
    try {
      Logger.debug('Обновляем настройки пересчёта...');

      final response = await http.put(
        Uri.parse('$_baseUrl/recount-settings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(settings.toJson()),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          Logger.success('Настройки обновлены');
          return true;
        }
      }

      Logger.warning('Не удалось обновить настройки: ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('Ошибка обновления настроек: $e');
      return false;
    }
  }

  /// Верифицировать фото в отчёте (принять/отклонить)
  static Future<bool> verifyPhoto({
    required String reportId,
    required int photoIndex,
    required String status, // 'approved' или 'rejected'
    required String adminName,
    required String employeePhone,
  }) async {
    try {
      Logger.debug('Верификация фото: $reportId, индекс $photoIndex -> $status');

      final response = await http.patch(
        Uri.parse('$_baseUrl/recount-reports/$reportId/verify-photo'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'photoIndex': photoIndex,
          'status': status,
          'adminName': adminName,
          'employeePhone': employeePhone,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          Logger.success('Фото верифицировано');
          return true;
        }
      }

      Logger.warning('Не удалось верифицировать фото: ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('Ошибка верификации фото: $e');
      return false;
    }
  }

  /// Добавить баллы сотруднику (после верификации фото)
  static Future<bool> addPointsChange({
    required String phone,
    required double change,
    required String reason,
  }) async {
    try {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s+]'), '');
      Logger.debug('Изменение баллов: $normalizedPhone, ${change > 0 ? '+' : ''}$change');

      // Получаем текущие баллы
      final current = await getPointsByPhone(normalizedPhone);
      if (current == null) {
        Logger.warning('Сотрудник не найден: $normalizedPhone');
        return false;
      }

      // Вычисляем новые баллы (не меньше 0, не больше 100)
      final newPoints = (current.points + change).clamp(0.0, 100.0);

      final response = await http.put(
        Uri.parse('$_baseUrl/recount-points/$normalizedPhone'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'points': newPoints,
          'adminName': 'Система',
          'reason': reason,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          Logger.success('Баллы изменены: $newPoints');
          return true;
        }
      }

      return false;
    } catch (e) {
      Logger.error('Ошибка изменения баллов: $e');
      return false;
    }
  }
}

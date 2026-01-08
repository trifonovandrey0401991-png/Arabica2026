import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/shift_transfer_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class ShiftTransferService {
  static const String baseEndpoint = '/api/shift-transfers';

  /// Создать запрос на передачу смены
  static Future<bool> createRequest(ShiftTransferRequest request) async {
    try {
      Logger.debug('Создание запроса на передачу смены: ${request.fromEmployeeName} -> ${request.toEmployeeName ?? "всем"}');

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(request.toJson()),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('Запрос на передачу смены создан успешно');
          return true;
        } else {
          throw Exception(data['error'] ?? 'Ошибка создания запроса');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Ошибка создания запроса на передачу смены', e);
      return false;
    }
  }

  /// Получить уведомления для сотрудника
  /// Возвращает запросы где toEmployeeId == employeeId или isBroadcast
  static Future<List<ShiftTransferRequest>> getEmployeeRequests(String employeeId) async {
    try {
      Logger.debug('Загрузка уведомлений для сотрудника: $employeeId');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/employee/$employeeId'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final requests = (data['requests'] as List<dynamic>)
              .map((r) => ShiftTransferRequest.fromJson(r as Map<String, dynamic>))
              .toList();
          Logger.debug('Загружено уведомлений: ${requests.length}');
          return requests;
        } else {
          throw Exception(data['error'] ?? 'Ошибка загрузки уведомлений');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Ошибка загрузки уведомлений сотрудника', e);
      return [];
    }
  }

  /// Получить запросы для администратора (ожидающие одобрения)
  static Future<List<ShiftTransferRequest>> getAdminRequests() async {
    try {
      Logger.debug('Загрузка запросов для администратора');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/admin'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final requests = (data['requests'] as List<dynamic>)
              .map((r) => ShiftTransferRequest.fromJson(r as Map<String, dynamic>))
              .toList();
          Logger.debug('Загружено запросов для админа: ${requests.length}');
          return requests;
        } else {
          throw Exception(data['error'] ?? 'Ошибка загрузки запросов');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Ошибка загрузки запросов для админа', e);
      return [];
    }
  }

  /// Сотрудник принимает запрос
  static Future<bool> acceptRequest(String requestId, String employeeId, String employeeName) async {
    try {
      Logger.debug('Принятие запроса $requestId сотрудником $employeeName');

      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$requestId/accept'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'employeeId': employeeId,
          'employeeName': employeeName,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('Запрос принят');
          return true;
        } else {
          throw Exception(data['error'] ?? 'Ошибка принятия запроса');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Ошибка принятия запроса', e);
      return false;
    }
  }

  /// Сотрудник отклоняет запрос
  static Future<bool> rejectRequest(String requestId) async {
    try {
      Logger.debug('Отклонение запроса $requestId');

      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$requestId/reject'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('Запрос отклонен');
          return true;
        } else {
          throw Exception(data['error'] ?? 'Ошибка отклонения запроса');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Ошибка отклонения запроса', e);
      return false;
    }
  }

  /// Администратор одобряет запрос
  static Future<bool> approveRequest(String requestId) async {
    try {
      Logger.debug('Одобрение запроса $requestId администратором');

      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$requestId/approve'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('Запрос одобрен, график обновлен');
          return true;
        } else {
          throw Exception(data['error'] ?? 'Ошибка одобрения запроса');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Ошибка одобрения запроса', e);
      return false;
    }
  }

  /// Администратор отклоняет запрос
  static Future<bool> declineRequest(String requestId) async {
    try {
      Logger.debug('Отклонение запроса $requestId администратором');

      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$requestId/decline'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('Запрос отклонен администратором');
          return true;
        } else {
          throw Exception(data['error'] ?? 'Ошибка отклонения запроса');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Ошибка отклонения запроса администратором', e);
      return false;
    }
  }

  /// Отметить запрос как прочитанный
  static Future<bool> markAsRead(String requestId, {bool isAdmin = false}) async {
    try {
      Logger.debug('Отметка запроса $requestId как прочитанного (isAdmin: $isAdmin)');

      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$requestId/read'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({'isAdmin': isAdmin}),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      Logger.error('Ошибка отметки запроса как прочитанного', e);
      return false;
    }
  }

  /// Получить количество непрочитанных уведомлений для сотрудника
  static Future<int> getUnreadCount(String employeeId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/employee/$employeeId/unread-count'),
      ).timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['count'] ?? 0;
        }
      }
      return 0;
    } catch (e) {
      Logger.error('Ошибка получения счетчика непрочитанных', e);
      return 0;
    }
  }

  /// Получить количество непрочитанных уведомлений для администратора
  static Future<int> getAdminUnreadCount() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/admin/unread-count'),
      ).timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['count'] ?? 0;
        }
      }
      return 0;
    } catch (e) {
      Logger.error('Ошибка получения счетчика непрочитанных для админа', e);
      return 0;
    }
  }

  /// Получить исходящие запросы сотрудника (которые он отправил)
  static Future<List<ShiftTransferRequest>> getOutgoingRequests(String employeeId) async {
    try {
      Logger.debug('Загрузка исходящих запросов для сотрудника: $employeeId');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/employee/$employeeId/outgoing'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final requests = (data['requests'] as List<dynamic>)
              .map((r) => ShiftTransferRequest.fromJson(r as Map<String, dynamic>))
              .toList();
          Logger.debug('Загружено исходящих запросов: ${requests.length}');
          return requests;
        } else {
          throw Exception(data['error'] ?? 'Ошибка загрузки запросов');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Ошибка загрузки исходящих запросов', e);
      return [];
    }
  }
}

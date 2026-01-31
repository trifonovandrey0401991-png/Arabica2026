import '../models/shift_transfer_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class ShiftTransferService {
  static const String baseEndpoint = ApiConstants.shiftTransfersEndpoint;

  /// Создать запрос на передачу смены
  static Future<bool> createRequest(ShiftTransferRequest request) async {
    Logger.debug('Создание запроса на передачу смены: ${request.fromEmployeeName} -> ${request.toEmployeeName ?? "всем"}');
    return await BaseHttpService.simplePost(
      endpoint: baseEndpoint,
      body: request.toJson(),
    );
  }

  /// Получить уведомления для сотрудника
  /// Возвращает запросы где toEmployeeId == employeeId или isBroadcast
  static Future<List<ShiftTransferRequest>> getEmployeeRequests(String employeeId) async {
    Logger.debug('Загрузка уведомлений для сотрудника: $employeeId');
    return await BaseHttpService.getList<ShiftTransferRequest>(
      endpoint: '$baseEndpoint/employee/$employeeId',
      fromJson: (json) => ShiftTransferRequest.fromJson(json),
      listKey: 'requests',
    );
  }

  /// Получить запросы для администратора (ожидающие одобрения)
  static Future<List<ShiftTransferRequest>> getAdminRequests() async {
    Logger.debug('Загрузка запросов для администратора');
    return await BaseHttpService.getList<ShiftTransferRequest>(
      endpoint: '$baseEndpoint/admin',
      fromJson: (json) => ShiftTransferRequest.fromJson(json),
      listKey: 'requests',
    );
  }

  /// Сотрудник принимает запрос
  static Future<bool> acceptRequest(String requestId, String employeeId, String employeeName) async {
    Logger.debug('Принятие запроса $requestId сотрудником $employeeName');
    return await BaseHttpService.simplePut(
      endpoint: '$baseEndpoint/$requestId/accept',
      body: {
        'employeeId': employeeId,
        'employeeName': employeeName,
      },
    );
  }

  /// Сотрудник отклоняет запрос
  static Future<bool> rejectRequest(String requestId, {String? employeeId, String? employeeName}) async {
    Logger.debug('Отклонение запроса $requestId сотрудником ${employeeName ?? 'unknown'}');
    return await BaseHttpService.simplePut(
      endpoint: '$baseEndpoint/$requestId/reject',
      body: {
        if (employeeId != null) 'employeeId': employeeId,
        if (employeeName != null) 'employeeName': employeeName,
      },
    );
  }

  /// Администратор одобряет запрос
  /// [selectedEmployeeId] - ID выбранного сотрудника (обязателен если несколько принявших)
  static Future<bool> approveRequest(String requestId, {String? selectedEmployeeId}) async {
    Logger.debug('Одобрение запроса $requestId администратором (selected: $selectedEmployeeId)');
    return await BaseHttpService.simplePut(
      endpoint: '$baseEndpoint/$requestId/approve',
      body: {
        if (selectedEmployeeId != null) 'selectedEmployeeId': selectedEmployeeId,
      },
    );
  }

  /// Администратор отклоняет запрос
  static Future<bool> declineRequest(String requestId) async {
    Logger.debug('Отклонение запроса $requestId администратором');
    return await BaseHttpService.simplePut(
      endpoint: '$baseEndpoint/$requestId/decline',
      body: {},
    );
  }

  /// Отметить запрос как прочитанный
  /// [phone] - телефон текущего пользователя для безопасной проверки прав на сервере
  /// [isAdmin] - DEPRECATED: используется только для обратной совместимости
  static Future<bool> markAsRead(String requestId, {String? phone, bool isAdmin = false}) async {
    Logger.debug('Отметка запроса $requestId как прочитанного (phone: $phone, isAdmin: $isAdmin)');
    return await BaseHttpService.simplePut(
      endpoint: '$baseEndpoint/$requestId/read',
      body: {
        if (phone != null) 'phone': phone,
        'isAdmin': isAdmin,
      },
    );
  }

  /// Получить количество непрочитанных уведомлений для сотрудника
  static Future<int> getUnreadCount(String employeeId) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$baseEndpoint/employee/$employeeId/unread-count',
        timeout: ApiConstants.shortTimeout,
      );
      if (result != null && result['success'] == true) {
        return result['count'] ?? 0;
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
      final result = await BaseHttpService.getRaw(
        endpoint: '$baseEndpoint/admin/unread-count',
        timeout: ApiConstants.shortTimeout,
      );
      if (result != null && result['success'] == true) {
        return result['count'] ?? 0;
      }
      return 0;
    } catch (e) {
      Logger.error('Ошибка получения счетчика непрочитанных для админа', e);
      return 0;
    }
  }

  /// Получить исходящие запросы сотрудника (которые он отправил)
  static Future<List<ShiftTransferRequest>> getOutgoingRequests(String employeeId) async {
    Logger.debug('Загрузка исходящих запросов для сотрудника: $employeeId');
    return await BaseHttpService.getList<ShiftTransferRequest>(
      endpoint: '$baseEndpoint/employee/$employeeId/outgoing',
      fromJson: (json) => ShiftTransferRequest.fromJson(json),
      listKey: 'requests',
    );
  }
}

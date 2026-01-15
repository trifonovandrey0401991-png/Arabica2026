import '../pages/employees_page.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class EmployeeService {
  /// Получить всех сотрудников
  static Future<List<Employee>> getEmployees() async {
    Logger.debug('📥 Загрузка сотрудников с сервера...');

    return await BaseHttpService.getList<Employee>(
      endpoint: ApiConstants.employeesEndpoint,
      fromJson: (json) => Employee.fromJson(json),
      listKey: 'employees',
    );
  }

  /// Получить сотрудника по ID
  static Future<Employee?> getEmployee(String id) async {
    return await BaseHttpService.get<Employee>(
      endpoint: '${ApiConstants.employeesEndpoint}/$id',
      fromJson: (json) => Employee.fromJson(json),
      itemKey: 'employee',
    );
  }

  /// Создать нового сотрудника
  static Future<Employee?> createEmployee({
    required String name,
    String? phone,
    bool? isAdmin,
    bool? isManager,
    String? employeeName,
    List<String>? preferredWorkDays,
    List<String>? preferredShops,
    Map<String, int>? shiftPreferences,
  }) async {
    Logger.debug('📤 Создание сотрудника: $name');

    final requestBody = <String, dynamic>{
      'name': name,
    };
    if (phone != null) requestBody['phone'] = phone;
    if (isAdmin != null) requestBody['isAdmin'] = isAdmin;
    if (isManager != null) requestBody['isManager'] = isManager;
    if (employeeName != null) requestBody['employeeName'] = employeeName;
    if (preferredWorkDays != null) requestBody['preferredWorkDays'] = preferredWorkDays;
    if (preferredShops != null) requestBody['preferredShops'] = preferredShops;
    if (shiftPreferences != null) requestBody['shiftPreferences'] = shiftPreferences;

    return await BaseHttpService.post<Employee>(
      endpoint: ApiConstants.employeesEndpoint,
      body: requestBody,
      fromJson: (json) => Employee.fromJson(json),
      itemKey: 'employee',
    );
  }

  /// Обновить сотрудника
  static Future<Employee?> updateEmployee({
    required String id,
    String? name,
    String? phone,
    bool? isAdmin,
    bool? isManager,
    String? employeeName,
    List<String>? preferredWorkDays,
    List<String>? preferredShops,
    Map<String, int>? shiftPreferences,
  }) async {
    Logger.debug('📤 Обновление сотрудника: $id');

    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (phone != null) body['phone'] = phone;
    if (isAdmin != null) body['isAdmin'] = isAdmin;
    if (isManager != null) body['isManager'] = isManager;
    if (employeeName != null) body['employeeName'] = employeeName;
    if (preferredWorkDays != null) body['preferredWorkDays'] = preferredWorkDays;
    if (preferredShops != null) body['preferredShops'] = preferredShops;
    if (shiftPreferences != null) body['shiftPreferences'] = shiftPreferences;

    return await BaseHttpService.put<Employee>(
      endpoint: '${ApiConstants.employeesEndpoint}/$id',
      body: body,
      fromJson: (json) => Employee.fromJson(json),
      itemKey: 'employee',
    );
  }

  /// Удалить сотрудника
  static Future<bool> deleteEmployee(String id) async {
    Logger.debug('📤 Удаление сотрудника: $id');

    return await BaseHttpService.delete(
      endpoint: '${ApiConstants.employeesEndpoint}/$id',
    );
  }
}



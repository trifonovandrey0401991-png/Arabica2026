import 'package:http/http.dart' as http;
import 'dart:convert';
import 'employees_page.dart';
import 'utils/logger.dart';

class EmployeeService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/employees';

  /// Получить всех сотрудников
  static Future<List<Employee>> getEmployees() async {
    try {
      Logger.debug('📥 Загрузка сотрудников с сервера...');
      
      final response = await http.get(
        Uri.parse(baseUrl),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final employeesJson = result['employees'] as List<dynamic>;
          final employees = employeesJson
              .map((json) => Employee.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено сотрудников: ${employees.length}');
          return employees;
        } else {
          Logger.error('❌ Ошибка загрузки сотрудников: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки сотрудников', e);
      return [];
    }
  }

  /// Получить сотрудника по ID
  static Future<Employee?> getEmployee(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/$id'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return Employee.fromJson(result['employee'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки сотрудника', e);
      return null;
    }
  }

  /// Создать нового сотрудника
  static Future<Employee?> createEmployee({
    required String name,
    String? phone,
    bool? isAdmin,
    String? employeeName,
    List<String>? preferredWorkDays,
    List<String>? preferredShops,
    Map<String, int>? shiftPreferences,
  }) async {
    try {
      Logger.debug('📤 Создание сотрудника: $name');
      
      final requestBody = <String, dynamic>{
        'name': name,
      };
      if (phone != null) requestBody['phone'] = phone;
      if (isAdmin != null) requestBody['isAdmin'] = isAdmin;
      if (employeeName != null) requestBody['employeeName'] = employeeName;
      if (preferredWorkDays != null) requestBody['preferredWorkDays'] = preferredWorkDays;
      if (preferredShops != null) requestBody['preferredShops'] = preferredShops;
      if (shiftPreferences != null) requestBody['shiftPreferences'] = shiftPreferences;
      
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Сотрудник создан: ${result['employee']['id']}');
          return Employee.fromJson(result['employee'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка создания сотрудника: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания сотрудника', e);
      return null;
    }
  }

  /// Обновить сотрудника
  static Future<Employee?> updateEmployee({
    required String id,
    String? name,
    String? phone,
    bool? isAdmin,
    String? employeeName,
    List<String>? preferredWorkDays,
    List<String>? preferredShops,
    Map<String, int>? shiftPreferences,
  }) async {
    try {
      Logger.debug('📤 Обновление сотрудника: $id');
      
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (phone != null) body['phone'] = phone;
      if (isAdmin != null) body['isAdmin'] = isAdmin;
      if (employeeName != null) body['employeeName'] = employeeName;
      if (preferredWorkDays != null) body['preferredWorkDays'] = preferredWorkDays;
      if (preferredShops != null) body['preferredShops'] = preferredShops;
      if (shiftPreferences != null) body['shiftPreferences'] = shiftPreferences;
      
      final response = await http.put(
        Uri.parse('$baseUrl/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Сотрудник обновлен: $id');
          return Employee.fromJson(result['employee'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка обновления сотрудника: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка обновления сотрудника', e);
      return null;
    }
  }

  /// Удалить сотрудника
  static Future<bool> deleteEmployee(String id) async {
    try {
      Logger.debug('📤 Удаление сотрудника: $id');
      
      final response = await http.delete(
        Uri.parse('$baseUrl/$id'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Сотрудник удален: $id');
          return true;
        } else {
          Logger.error('❌ Ошибка удаления сотрудника: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка удаления сотрудника', e);
      return false;
    }
  }
}



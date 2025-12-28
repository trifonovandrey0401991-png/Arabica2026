import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_role_model.dart';
import '../../../server_config.dart';

/// Сервис для работы с ролями пользователей
class UserRoleService {
  /// Проверить, является ли пользователь сотрудником через API
  static Future<UserRoleData?> checkEmployeeViaAPI(String phone) async {
    try {
      // Нормализуем номер телефона: убираем + и пробелы, оставляем только цифры
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      
      print('🔍 Проверка сотрудника через API с номером: $normalizedPhone');
      
      // Загружаем список сотрудников с сервера
      final uri = Uri.parse('https://arabica26.ru/api/employees');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при получении списка сотрудников');
        },
      );

      if (response.statusCode != 200) {
        print('⚠️ Ошибка получения списка сотрудников: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true || data['employees'] == null) {
        print('⚠️ Неверный формат ответа от API сотрудников');
        return null;
      }

      final employees = data['employees'] as List;
      print('📋 Загружено сотрудников: ${employees.length}');

      // Ищем сотрудника по телефону
      for (var emp in employees) {
        final empPhone = emp['phone']?.toString().trim();
        if (empPhone != null && empPhone.isNotEmpty) {
          final empNormalizedPhone = empPhone.replaceAll(RegExp(r'[\s\+]'), '');
          if (empNormalizedPhone == normalizedPhone) {
            final employeeName = emp['name']?.toString().trim() ?? '';
            final isAdmin = emp['isAdmin'] == true || emp['isAdmin'] == 1 || emp['isAdmin'] == '1';
            
            print('✅ Сотрудник найден через API:');
            print('   ID: ${emp['id']}');
            print('   Имя: $employeeName');
            print('   Админ: $isAdmin');
            
            // Сохраняем employeeId для последующего использования
            if (emp['id'] != null) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('currentEmployeeId', emp['id'].toString());
              await prefs.setString('currentEmployeeName', employeeName);
              print('💾 Сохранен employeeId: ${emp['id']}');
            }
            
            return UserRoleData(
              role: isAdmin ? UserRole.admin : UserRole.employee,
              displayName: employeeName,
              phone: normalizedPhone,
              employeeName: employeeName,
            );
          }
        }
      }
      
      print('ℹ️ Сотрудник не найден через API');
      return null;
    } catch (e) {
      print('⚠️ Ошибка проверки сотрудника через API: $e');
      return null;
    }
  }

  /// Получить роль пользователя по номеру телефона
  static Future<UserRoleData> getUserRole(String phone) async {
    try {
      // Нормализуем номер телефона: убираем + и пробелы, оставляем только цифры
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      
      print('🔍 Проверка роли пользователя с номером: $normalizedPhone');
      
      // СНАЧАЛА проверяем через API сотрудников (для сотрудников, созданных через API)
      final apiRole = await checkEmployeeViaAPI(phone);
      if (apiRole != null) {
        print('✅ Роль определена через API: ${apiRole.role.name}');
        return apiRole;
      }
      
      // ЕСЛИ не найден через API, проверяем через сервер
      print('📊 Проверка роли через сервер...');
      final uri = Uri.parse(
        '$serverUrl?action=getUserRole&phone=${Uri.encodeQueryComponent(normalizedPhone)}',
      );
      
      print('🔗 URL запроса: $uri');

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при получении роли пользователя');
        },
      );

      if (response.statusCode != 200) {
        print('❌ Ошибка получения роли: ${response.statusCode}');
        // По умолчанию возвращаем роль клиента
        return UserRoleData(
          role: UserRole.client,
          displayName: '',
          phone: normalizedPhone,
        );
      }

      final data = jsonDecode(response.body);
      
      if (data['success'] != true) {
        print('⚠️ Сервер вернул success: false, используем роль клиента по умолчанию');
        return UserRoleData(
          role: UserRole.client,
          displayName: data['clientName'] ?? '',
          phone: normalizedPhone,
        );
      }

      // Определяем роль на основе данных
      UserRole role = UserRole.client;
      String displayName = data['clientName'] ?? ''; // Имя из столбца A
      String? employeeName = data['employeeName']; // Имя из столбца G

      // Проверяем столбец H (админ)
      final adminValue = data['isAdmin'];
      if (adminValue == 1 || adminValue == '1') {
        role = UserRole.admin;
        // Если есть имя в столбце G, используем его
        if (employeeName != null && employeeName.isNotEmpty) {
          displayName = employeeName;
        }
      }
      // Проверяем столбец G (сотрудник)
      else if (employeeName != null && employeeName.isNotEmpty) {
        role = UserRole.employee;
        displayName = employeeName;
      }

      print('✅ Роль определена через сервер: ${role.name}');
      print('   Имя для отображения: $displayName');
      if (employeeName != null) {
        print('   Имя сотрудника (G): $employeeName');
      }

      return UserRoleData(
        role: role,
        displayName: displayName,
        phone: normalizedPhone,
        employeeName: employeeName,
      );
    } catch (e) {
      print('❌ Ошибка получения роли: $e');
      // При ошибке (таймаут) не перезаписываем роль - возвращаем null,
      // чтобы вызывающий код мог использовать кэшированную роль
      rethrow; // Пробрасываем исключение дальше, чтобы вызывающий код мог обработать
    }
  }

  /// Сохранить роль пользователя в SharedPreferences
  static Future<void> saveUserRole(UserRoleData roleData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', roleData.role.name);
      await prefs.setString('user_display_name', roleData.displayName);
      if (roleData.employeeName != null) {
        await prefs.setString('user_employee_name', roleData.employeeName!);
      } else {
        await prefs.remove('user_employee_name');
      }
      print('✅ Роль сохранена: ${roleData.role.name}');
    } catch (e) {
      print('❌ Ошибка сохранения роли: $e');
    }
  }

  /// Загрузить роль пользователя из SharedPreferences
  static Future<UserRoleData?> loadUserRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final roleStr = prefs.getString('user_role');
      final displayName = prefs.getString('user_display_name') ?? '';
      final phone = prefs.getString('user_phone') ?? '';
      final employeeName = prefs.getString('user_employee_name');

      if (roleStr == null) {
        return null;
      }

      UserRole role;
      switch (roleStr) {
        case 'admin':
          role = UserRole.admin;
          break;
        case 'employee':
          role = UserRole.employee;
          break;
        default:
          role = UserRole.client;
      }

      return UserRoleData(
        role: role,
        displayName: displayName,
        phone: phone,
        employeeName: employeeName,
      );
    } catch (e) {
      print('❌ Ошибка загрузки роли: $e');
      return null;
    }
  }

  /// Очистить сохраненную роль
  static Future<void> clearUserRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_role');
      await prefs.remove('user_display_name');
      await prefs.remove('user_employee_name');
      print('✅ Роль очищена');
    } catch (e) {
      print('❌ Ошибка очистки роли: $e');
    }
  }
}


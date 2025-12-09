import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_role_model.dart';
import 'google_script_config.dart';

/// Сервис для работы с ролями пользователей
class UserRoleService {
  /// Получить роль пользователя по номеру телефона
  static Future<UserRoleData> getUserRole(String phone) async {
    try {
      // Нормализуем номер телефона: убираем + и пробелы, оставляем только цифры
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      
      final uri = Uri.parse(
        '$googleScriptUrl?action=getUserRole&phone=${Uri.encodeQueryComponent(normalizedPhone)}',
      );
      
      print('🔍 Проверка роли пользователя с номером: $normalizedPhone');
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

      print('✅ Роль определена: ${role.name}');
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


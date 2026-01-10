import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_role_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

/// Сервис для работы с ролями пользователей
class UserRoleService {
  /// Проверить, является ли пользователь сотрудником через API
  static Future<UserRoleData?> checkEmployeeViaAPI(String phone) async {
    try {
      // Нормализуем номер телефона: убираем + и пробелы, оставляем только цифры
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');

      Logger.debug('🔍 Проверка сотрудника через API с номером: $normalizedPhone');

      // Загружаем список сотрудников с сервера
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/employees',
        timeout: ApiConstants.shortTimeout,
      );

      if (result == null || result['success'] != true || result['employees'] == null) {
        Logger.debug('⚠️ Неверный формат ответа от API сотрудников');
        return null;
      }

      final employees = result['employees'] as List;
      Logger.debug('📋 Загружено сотрудников: ${employees.length}');

      // Ищем сотрудника по телефону
      for (var emp in employees) {
        final empPhone = emp['phone']?.toString().trim();
        if (empPhone != null && empPhone.isNotEmpty) {
          final empNormalizedPhone = empPhone.replaceAll(RegExp(r'[\s\+]'), '');
          if (empNormalizedPhone == normalizedPhone) {
            final employeeName = emp['name']?.toString().trim() ?? '';
            final isAdmin = emp['isAdmin'] == true || emp['isAdmin'] == 1 || emp['isAdmin'] == '1';

            Logger.debug('✅ Сотрудник найден через API:');
            Logger.debug('   ID: ${emp['id']}');
            Logger.debug('   Имя: $employeeName');
            Logger.debug('   Админ: $isAdmin');

            // Сохраняем employeeId для последующего использования
            if (emp['id'] != null) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('currentEmployeeId', emp['id'].toString());
              await prefs.setString('currentEmployeeName', employeeName);
              Logger.debug('💾 Сохранен employeeId: ${emp['id']}');
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

      Logger.debug('ℹ️ Сотрудник не найден через API');
      return null;
    } catch (e) {
      Logger.debug('⚠️ Ошибка проверки сотрудника через API: $e');
      return null;
    }
  }

  /// Получить роль пользователя по номеру телефона
  static Future<UserRoleData> getUserRole(String phone) async {
    try {
      // Нормализуем номер телефона: убираем + и пробелы, оставляем только цифры
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');

      Logger.debug('🔍 Проверка роли пользователя с номером: $normalizedPhone');

      // СНАЧАЛА проверяем через API сотрудников (для сотрудников, созданных через API)
      final apiRole = await checkEmployeeViaAPI(phone);
      if (apiRole != null) {
        Logger.debug('✅ Роль определена через API: ${apiRole.role.name}');
        return apiRole;
      }

      // ЕСЛИ не найден через API, проверяем через сервер
      Logger.debug('📊 Проверка роли через сервер...');

      final result = await BaseHttpService.getRaw(
        endpoint: '?action=getUserRole&phone=${Uri.encodeQueryComponent(normalizedPhone)}',
        timeout: ApiConstants.shortTimeout,
      );

      if (result == null || result['success'] != true) {
        Logger.debug('⚠️ Сервер вернул success: false, используем роль клиента по умолчанию');
        return UserRoleData(
          role: UserRole.client,
          displayName: result?['clientName'] ?? '',
          phone: normalizedPhone,
        );
      }

      // Определяем роль на основе данных
      UserRole role = UserRole.client;
      String displayName = result['clientName'] ?? ''; // Имя из столбца A
      String? employeeName = result['employeeName']; // Имя из столбца G

      // Проверяем столбец H (админ)
      final adminValue = result['isAdmin'];
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

      Logger.debug('✅ Роль определена через сервер: ${role.name}');
      Logger.debug('   Имя для отображения: $displayName');
      if (employeeName != null) {
        Logger.debug('   Имя сотрудника (G): $employeeName');
      }

      return UserRoleData(
        role: role,
        displayName: displayName,
        phone: normalizedPhone,
        employeeName: employeeName,
      );
    } catch (e) {
      Logger.debug('❌ Ошибка получения роли: $e');
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
      Logger.debug('✅ Роль сохранена: ${roleData.role.name}');
    } catch (e) {
      Logger.debug('❌ Ошибка сохранения роли: $e');
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
      Logger.debug('❌ Ошибка загрузки роли: $e');
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
      Logger.debug('✅ Роль очищена');
    } catch (e) {
      Logger.debug('❌ Ошибка очистки роли: $e');
    }
  }
}


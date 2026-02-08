import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_role_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import 'employee_registration_service.dart';

/// Сервис для работы с ролями пользователей
class UserRoleService {
  /// Кэш мультитенантной роли (чтобы не делать запрос каждый раз)
  static Map<String, dynamic>? _cachedMultitenantRole;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Получить мультитенантную роль пользователя (developer/admin/manager)
  static Future<Map<String, dynamic>?> getMultitenantRole(String phone) async {
    try {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');

      // Проверяем кэш
      if (_cachedMultitenantRole != null &&
          _cacheTime != null &&
          DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        Logger.debug('📦 Используем кэшированную мультитенантную роль');
        return _cachedMultitenantRole;
      }

      Logger.debug('🔍 Проверка мультитенантной роли для: $normalizedPhone');

      final result = await BaseHttpService.getRaw(
        endpoint: '/api/shop-managers/role/$normalizedPhone',
        timeout: ApiConstants.shortTimeout,
      );

      if (result == null || result['success'] != true) {
        Logger.debug('⚠️ Мультитенантная роль не определена');
        return null;
      }

      // Кэшируем результат
      _cachedMultitenantRole = result['role'] as Map<String, dynamic>?;
      _cacheTime = DateTime.now();

      if (_cachedMultitenantRole != null) {
        Logger.debug('✅ Мультитенантная роль: ${_cachedMultitenantRole!['role']}');
        if (_cachedMultitenantRole!['managedShopIds'] != null) {
          Logger.debug('   Магазины: ${(_cachedMultitenantRole!['managedShopIds'] as List).length}');
        }
        if (_cachedMultitenantRole!['managedEmployees'] != null) {
          Logger.debug('   Сотрудники: ${(_cachedMultitenantRole!['managedEmployees'] as List).length}');
        }
      }

      return _cachedMultitenantRole;
    } catch (e) {
      Logger.debug('⚠️ Ошибка получения мультитенантной роли: $e');
      return null;
    }
  }

  /// Очистить кэш мультитенантной роли
  static void clearMultitenantCache() {
    _cachedMultitenantRole = null;
    _cacheTime = null;
    Logger.debug('🧹 Кэш мультитенантной роли очищен');
  }

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

            // Проверяем верификацию сотрудника
            // Если сотрудник не верифицирован - он видит приложение как клиент
            final registration = await EmployeeRegistrationService.getRegistration(normalizedPhone);
            final isVerified = registration?.isVerified ?? false;
            Logger.debug('   Верификация: $isVerified');

            if (!isVerified) {
              Logger.debug('⚠️ Сотрудник не верифицирован, будет показан как клиент');
              return null;
            }

            // Сохраняем employeeId для последующего использования
            if (emp['id'] != null) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('currentEmployeeId', emp['id'].toString());
              await prefs.setString('currentEmployeeName', employeeName);
              Logger.debug('💾 Сохранен employeeId: ${emp['id']}');
            }

            // Получаем мультитенантную роль
            final multitenantRole = await getMultitenantRole(normalizedPhone);

            // Определяем финальную роль с учётом мультитенантности
            UserRole finalRole;
            List<String> managedShopIds = [];
            List<String> managedEmployees = [];
            String? primaryShopId;
            bool canSeeAllManagerShops = false;

            if (multitenantRole != null) {
              final mtRole = multitenantRole['role'] as String?;
              if (mtRole == 'developer') {
                finalRole = UserRole.developer;
                Logger.debug('🔧 Пользователь - DEVELOPER');
              } else if (mtRole == 'admin') {
                finalRole = UserRole.admin;
                managedShopIds = (multitenantRole['managedShopIds'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ?? [];
                managedEmployees = (multitenantRole['managedEmployees'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ?? [];
                Logger.debug('👔 Пользователь - ADMIN (управляющий)');
              } else if (mtRole == 'manager') {
                finalRole = UserRole.manager;
                primaryShopId = multitenantRole['primaryShopId'] as String?;
                managedShopIds = (multitenantRole['managedShopIds'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ?? [];
                canSeeAllManagerShops = multitenantRole['canSeeAllManagerShops'] == true;
                Logger.debug('🏪 Пользователь - MANAGER (заведующая), магазинов: ${managedShopIds.length}');
              } else {
                // Используем роль из employees API
                finalRole = isAdmin ? UserRole.admin : UserRole.employee;
              }
            } else {
              // Мультитенантная роль не определена - используем стандартную
              finalRole = isAdmin ? UserRole.admin : UserRole.employee;
            }

            return UserRoleData(
              role: finalRole,
              displayName: employeeName,
              phone: normalizedPhone,
              employeeName: employeeName,
              managedShopIds: managedShopIds,
              managedEmployees: managedEmployees,
              primaryShopId: primaryShopId,
              canSeeAllManagerShops: canSeeAllManagerShops,
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

      // Очищаем кэш мультитенантной роли при новом запросе
      clearMultitenantCache();

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

      // Проверяем столбец H (админ) или столбец G (сотрудник)
      final adminValue = result['isAdmin'];
      final isAdminFromServer = adminValue == 1 || adminValue == '1';
      final isEmployeeFromServer = employeeName != null && employeeName.isNotEmpty;

      // Если пользователь определён как сотрудник/админ, проверяем верификацию
      if (isAdminFromServer || isEmployeeFromServer) {
        final registration = await EmployeeRegistrationService.getRegistration(normalizedPhone);
        final isVerified = registration?.isVerified ?? false;
        Logger.debug('   Верификация: $isVerified');

        if (!isVerified) {
          Logger.debug('⚠️ Сотрудник не верифицирован, будет показан как клиент');
          return UserRoleData(
            role: UserRole.client,
            displayName: displayName,
            phone: normalizedPhone,
          );
        }

        // Сотрудник верифицирован - устанавливаем роль
        if (isAdminFromServer) {
          role = UserRole.admin;
          if (employeeName != null && employeeName.isNotEmpty) {
            displayName = employeeName;
          }
        } else {
          role = UserRole.employee;
          displayName = employeeName!;
        }
      }

      Logger.debug('✅ Роль определена через сервер: ${role.name}');
      Logger.debug('   Имя для отображения: $displayName');
      if (employeeName != null) {
        Logger.debug('   Имя сотрудника (G): $employeeName');
      }

      // Загружаем мультитенантные данные (managedShopIds, managedEmployees)
      List<String> managedShopIds = [];
      List<String> managedEmployees = [];
      String? primaryShopId;
      bool canSeeAllManagerShops = false;

      if (role == UserRole.admin || role == UserRole.employee) {
        final multitenantRole = await getMultitenantRole(normalizedPhone);
        if (multitenantRole != null) {
          final mtRole = multitenantRole['role'] as String?;
          if (mtRole == 'developer') {
            role = UserRole.developer;
            Logger.debug('🔧 Роль повышена до DEVELOPER (из мультитенантности)');
          } else if (mtRole == 'admin') {
            role = UserRole.admin;
            managedShopIds = (multitenantRole['managedShopIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ?? [];
            managedEmployees = (multitenantRole['managedEmployees'] as List?)
                ?.map((e) => e.toString())
                .toList() ?? [];
          } else if (mtRole == 'manager') {
            role = UserRole.manager;
            primaryShopId = multitenantRole['primaryShopId'] as String?;
            managedShopIds = (multitenantRole['managedShopIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ?? [];
            canSeeAllManagerShops = multitenantRole['canSeeAllManagerShops'] == true;
          }
          Logger.debug('   Мультитенантность: магазины=${managedShopIds.length}, сотрудники=${managedEmployees.length}');
        }
      }

      return UserRoleData(
        role: role,
        displayName: displayName,
        phone: normalizedPhone,
        employeeName: role != UserRole.client ? employeeName : null,
        managedShopIds: managedShopIds,
        managedEmployees: managedEmployees,
        primaryShopId: primaryShopId,
        canSeeAllManagerShops: canSeeAllManagerShops,
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
      await prefs.setString('user_phone', roleData.phone); // Сохраняем телефон!

      if (roleData.employeeName != null) {
        await prefs.setString('user_employee_name', roleData.employeeName!);
      } else {
        await prefs.remove('user_employee_name');
      }

      // Сохраняем мультитенантные данные
      await prefs.setStringList('user_managed_shop_ids', roleData.managedShopIds);
      await prefs.setStringList('user_managed_employees', roleData.managedEmployees);

      if (roleData.primaryShopId != null) {
        await prefs.setString('user_primary_shop_id', roleData.primaryShopId!);
      } else {
        await prefs.remove('user_primary_shop_id');
      }

      await prefs.setBool('user_can_see_all_manager_shops', roleData.canSeeAllManagerShops);

      Logger.debug('✅ Роль сохранена: ${roleData.role.name}');
      if (roleData.managedShopIds.isNotEmpty) {
        Logger.debug('   Магазины: ${roleData.managedShopIds.length}');
      }
      if (roleData.managedEmployees.isNotEmpty) {
        Logger.debug('   Сотрудники: ${roleData.managedEmployees.length}');
      }
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

      // Загружаем мультитенантные данные
      final managedShopIds = prefs.getStringList('user_managed_shop_ids') ?? [];
      final managedEmployees = prefs.getStringList('user_managed_employees') ?? [];
      final primaryShopId = prefs.getString('user_primary_shop_id');
      final canSeeAllManagerShops = prefs.getBool('user_can_see_all_manager_shops') ?? false;

      if (roleStr == null) {
        return null;
      }

      UserRole role;
      switch (roleStr) {
        case 'developer':
          role = UserRole.developer;
          break;
        case 'admin':
          role = UserRole.admin;
          break;
        case 'manager':
          role = UserRole.manager;
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
        managedShopIds: managedShopIds,
        managedEmployees: managedEmployees,
        primaryShopId: primaryShopId,
        canSeeAllManagerShops: canSeeAllManagerShops,
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
      await prefs.remove('user_managed_shop_ids');
      await prefs.remove('user_managed_employees');
      await prefs.remove('user_primary_shop_id');
      await prefs.remove('user_can_see_all_manager_shops');

      // Очищаем кэш мультитенантной роли
      clearMultitenantCache();

      Logger.debug('✅ Роль очищена');
    } catch (e) {
      Logger.debug('❌ Ошибка очистки роли: $e');
    }
  }
}


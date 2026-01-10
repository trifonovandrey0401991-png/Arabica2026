import 'package:shared_preferences/shared_preferences.dart';
import '../../shops/models/shop_settings_model.dart';
import '../../employees/services/employee_registration_service.dart';
import '../../employees/models/employee_registration_model.dart';
import '../../shifts/models/shift_report_model.dart';
import '../../shops/models/shop_model.dart';
import '../../employees/pages/employees_page.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/cache_manager.dart';

class RKOService {
  static const String _shopSettingsEndpoint = '/api/shop-settings';

  /// Получить последнюю пересменку сотрудника
  static Future<ShiftReport?> getLastShift(String employeeName) async {
    try {
      final reports = await ShiftReport.loadAllReports();

      // Фильтруем отчеты по имени сотрудника и сортируем по дате (новые первыми)
      final employeeReports = reports
          .where((r) => r.employeeName.toLowerCase() == employeeName.toLowerCase())
          .toList();

      employeeReports.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (employeeReports.isNotEmpty) {
        return employeeReports.first;
      }

      return null;
    } catch (e) {
      Logger.error('Ошибка получения последней пересменки', e);
      return null;
    }
  }

  /// Получить настройки магазина (с кэшированием)
  static Future<ShopSettings?> getShopSettings(String shopAddress) async {
    // Проверяем кэш
    final cacheKey = 'shop_settings_${Uri.encodeComponent(shopAddress)}';
    final cached = CacheManager.get<ShopSettings>(cacheKey);
    if (cached != null) {
      Logger.debug('Настройки магазина загружены из кэша');
      return cached;
    }

    try {
      final result = await BaseHttpService.get<ShopSettings>(
        endpoint: '$_shopSettingsEndpoint/${Uri.encodeComponent(shopAddress)}',
        fromJson: (json) => ShopSettings.fromJson(json),
        itemKey: 'settings',
      );

      if (result != null) {
        // Сохраняем в кэш
        CacheManager.set(cacheKey, result, duration: AppConstants.cacheDuration);
      }
      return result;
    } catch (e) {
      Logger.error('Ошибка получения настроек магазина', e);
      return null;
    }
  }

  /// Получить следующий номер документа для магазина
  static Future<int> getNextDocumentNumber(String shopAddress) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_shopSettingsEndpoint/${Uri.encodeComponent(shopAddress)}/document-number',
      );

      if (result != null) {
        return result['documentNumber'] as int? ?? 1;
      }
      return 1;
    } catch (e) {
      Logger.error('Ошибка получения номера документа', e);
      return 1;
    }
  }

  /// Обновить номер документа для магазина
  static Future<bool> updateDocumentNumber(String shopAddress, int documentNumber) async {
    try {
      return await BaseHttpService.simplePost(
        endpoint: '$_shopSettingsEndpoint/${Uri.encodeComponent(shopAddress)}/document-number',
        body: {'documentNumber': documentNumber},
      );
    } catch (e) {
      Logger.error('Ошибка обновления номера документа', e);
      return false;
    }
  }

  /// Получить данные сотрудника из регистрации
  static Future<EmployeeRegistration?> getEmployeeData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');

      if (phone == null || phone.isEmpty) {
        return null;
      }

      // Нормализуем телефон
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      return await EmployeeRegistrationService.getRegistration(normalizedPhone);
    } catch (e) {
      Logger.error('Ошибка получения данных сотрудника', e);
      return null;
    }
  }

  /// Получить имя сотрудника из меню "Сотрудники" (единый источник истины)
  /// Использует EmployeesPage.getCurrentEmployeeName() для получения правильного имени
  static Future<String?> getEmployeeName() async {
    try {
      // Используем единый метод из EmployeesPage
      return await EmployeesPage.getCurrentEmployeeName();
    } catch (e) {
      Logger.error('Ошибка получения имени сотрудника', e);
      return null;
    }
  }

  /// Получить магазин из последней пересменки
  static Future<Shop?> getShopFromLastShift(String employeeName) async {
    try {
      final lastShift = await getLastShift(employeeName);
      if (lastShift == null) {
        return null;
      }

      // Загружаем список магазинов и ищем по адресу
      final shops = await Shop.loadShopsFromGoogleSheets();
      return shops.firstWhere(
        (shop) => shop.address == lastShift.shopAddress,
        orElse: () => shops.first, // Если не найдено, возвращаем первый магазин
      );
    } catch (e) {
      Logger.error('Ошибка получения магазина из пересменки', e);
      return null;
    }
  }
}

import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

/// Настройки акции лояльности
class LoyaltyPromoSettings {
  final String promoText;
  final int pointsRequired;
  final int drinksToGive;

  const LoyaltyPromoSettings({
    this.promoText = '',
    required this.pointsRequired,
    required this.drinksToGive,
  });

  /// Пустые настройки (используется только при ошибке загрузки)
  static const empty = LoyaltyPromoSettings(
    promoText: '',
    pointsRequired: 0,
    drinksToGive: 0,
  );

  factory LoyaltyPromoSettings.fromJson(Map<String, dynamic> json) {
    return LoyaltyPromoSettings(
      promoText: (json['promoText'] ?? '').toString(),
      pointsRequired: int.tryParse(json['pointsRequired']?.toString() ?? '') ?? 0,
      drinksToGive: int.tryParse(json['drinksToGive']?.toString() ?? '') ?? 0,
    );
  }
}

class LoyaltyInfo {
  final String name;
  final String phone;
  final String qr;
  final int points;
  final int freeDrinks;
  final String promoText;
  final bool readyForRedeem;
  final int pointsRequired;
  final int drinksToGive;

  const LoyaltyInfo({
    required this.name,
    required this.phone,
    required this.qr,
    required this.points,
    required this.freeDrinks,
    required this.promoText,
    required this.readyForRedeem,
    required this.pointsRequired,
    required this.drinksToGive,
  });

  factory LoyaltyInfo.fromJson(Map<String, dynamic> json, {required LoyaltyPromoSettings settings}) {
    final pointsRequired = settings.pointsRequired;
    final drinksToGive = settings.drinksToGive;
    final points = int.tryParse(json['points']?.toString() ?? '') ?? 0;

    return LoyaltyInfo(
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      qr: (json['qr'] ?? '').toString(),
      points: points,
      freeDrinks: int.tryParse(json['freeDrinks']?.toString() ?? '') ?? 0,
      promoText: settings.promoText.isNotEmpty ? settings.promoText : (json['promoText'] ?? '').toString(),
      readyForRedeem: pointsRequired > 0 && points >= pointsRequired,
      pointsRequired: pointsRequired,
      drinksToGive: drinksToGive,
    );
  }

  /// Создать копию с новыми настройками
  LoyaltyInfo copyWithSettings(LoyaltyPromoSettings settings) {
    return LoyaltyInfo(
      name: name,
      phone: phone,
      qr: qr,
      points: points,
      freeDrinks: freeDrinks,
      promoText: settings.promoText.isNotEmpty ? settings.promoText : promoText,
      readyForRedeem: points >= settings.pointsRequired,
      pointsRequired: settings.pointsRequired,
      drinksToGive: settings.drinksToGive,
    );
  }

  /// Создать копию с новым promoText
  LoyaltyInfo copyWithPromoText(String newPromoText) {
    return LoyaltyInfo(
      name: name,
      phone: phone,
      qr: qr,
      points: points,
      freeDrinks: freeDrinks,
      promoText: newPromoText,
      readyForRedeem: readyForRedeem,
      pointsRequired: pointsRequired,
      drinksToGive: drinksToGive,
    );
  }
}

class LoyaltyService {
  /// Кэш настроек акции
  static LoyaltyPromoSettings? _cachedSettings;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 5);

  /// Очистить кэш настроек (вызывается после сохранения настроек в админке)
  static void clearSettingsCache() {
    _cachedSettings = null;
    _cacheTime = null;
  }

  /// Загрузить настройки акции с сервера
  static Future<LoyaltyPromoSettings> fetchPromoSettings() async {
    // Проверяем кэш
    if (_cachedSettings != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _cachedSettings!;
      }
    }

    try {
      final result = await BaseHttpService.getRaw(endpoint: '/api/loyalty-promo');

      if (result != null && result['success'] == true) {
        _cachedSettings = LoyaltyPromoSettings.fromJson(result);
        _cacheTime = DateTime.now();
        Logger.debug('✅ Настройки акции загружены: ${_cachedSettings!.pointsRequired}+${_cachedSettings!.drinksToGive}');
        return _cachedSettings!;
      }
      return LoyaltyPromoSettings.empty;
    } catch (e) {
      Logger.error('Ошибка загрузки настроек акции', e);
      return LoyaltyPromoSettings.empty;
    }
  }

  /// Загрузить текст условий акции с сервера (для обратной совместимости)
  static Future<String> fetchPromoText() async {
    final settings = await fetchPromoSettings();
    return settings.promoText;
  }

  /// Сохранить настройки акции на сервер (только для админа)
  static Future<bool> savePromoSettings({
    required String promoText,
    required int pointsRequired,
    required int drinksToGive,
    required String employeePhone,
  }) async {
    try {
      final normalizedPhone = employeePhone.replaceAll(RegExp(r'[\s\+]'), '');
      final success = await BaseHttpService.simplePost(
        endpoint: '/api/loyalty-promo',
        body: {
          'promoText': promoText,
          'pointsRequired': pointsRequired,
          'drinksToGive': drinksToGive,
          'employeePhone': normalizedPhone,
        },
      );

      if (success) {
        // Очищаем кэш чтобы изменения применились сразу
        clearSettingsCache();
        Logger.debug('✅ Настройки акции сохранены: $pointsRequired+$drinksToGive');
      }
      return success;
    } catch (e) {
      Logger.error('Ошибка сохранения настроек акции', e);
      return false;
    }
  }

  static Future<LoyaltyInfo> registerClient({
    required String name,
    required String phone,
    required String qr,
  }) async {
    // Нормализуем номер телефона: убираем + и пробелы
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');

    final result = await BaseHttpService.postRaw(
      endpoint: '',
      body: {
        'action': 'register',
        'name': name,
        'phone': normalizedPhone,
        'qr': qr,
        'points': 0,
        'freeDrinks': 0,
      },
      timeout: ApiConstants.longTimeout,
    );

    if (result == null || result['success'] != true) {
      throw Exception(result?['error'] ?? 'Ошибка регистрации клиента');
    }

    // Если есть сообщение о том, что пользователь уже существует, это нормально
    if (result['message'] != null) {
      Logger.info(result['message']);
    }

    // Загружаем настройки акции
    final settings = await fetchPromoSettings();
    return LoyaltyInfo.fromJson(result['client'], settings: settings);
  }

  static Future<LoyaltyInfo> fetchByPhone(String phone) async {
    try {
      // Нормализуем номер телефона: убираем + и пробелы
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');

      Logger.debug('📞 Поиск пользователя с номером: $normalizedPhone');

      final result = await BaseHttpService.getRaw(
        endpoint: '?action=getClient&phone=${Uri.encodeQueryComponent(normalizedPhone)}',
        timeout: ApiConstants.defaultTimeout,
      );

      if (result == null || result['success'] != true) {
        Logger.error('Сервер вернул success: false. Ошибка: ${result?['error']}');
        throw Exception(result?['error'] ?? 'Не удалось получить данные клиента');
      }

      if (result['client'] == null) {
        Logger.error('Клиент не найден в ответе сервера');
        throw Exception('Клиент не найден в базе данных');
      }

      Logger.debug('Пользователь найден: ${result['client']['name']}');

      // Загружаем настройки акции с нашего сервера
      final settings = await fetchPromoSettings();
      final info = LoyaltyInfo.fromJson(result['client'], settings: settings);

      // Синхронизируем freeDrinksGiven в нашей базе клиентов
      try {
        await syncFreeDrinksGiven(normalizedPhone, info.freeDrinks);
      } catch (e) {
        Logger.error('Ошибка синхронизации freeDrinksGiven', e);
      }

      return info;
    } catch (e, stackTrace) {
      Logger.error('КРИТИЧЕСКАЯ ОШИБКА в fetchByPhone', e, stackTrace);
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Ошибка при получении данных клиента: $e');
    }
  }

  static Future<LoyaltyInfo> fetchByQr(String qr) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '?action=getClient&qr=${Uri.encodeQueryComponent(qr)}',
        timeout: ApiConstants.longTimeout,
      );

      if (result == null || result['success'] != true) {
        throw Exception(result?['error'] ?? 'Не удалось получить данные клиента');
      }

      if (result['client'] == null) {
        throw Exception('Клиент не найден в базе данных');
      }

      // Загружаем настройки акции с нашего сервера
      final settings = await fetchPromoSettings();
      final info = LoyaltyInfo.fromJson(result['client'], settings: settings);

      return info;
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Ошибка при получении данных клиента: $e');
    }
  }

  static Future<LoyaltyInfo> addPoint(String qr) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '',
      body: {
        'action': 'addPoint',
        'qr': qr,
      },
      timeout: ApiConstants.longTimeout,
    );

    if (result == null || result['success'] != true) {
      throw Exception(result?['error'] ?? 'Произошла ошибка сервера');
    }

    // Загружаем настройки акции для корректного определения readyForRedeem
    final settings = await fetchPromoSettings();
    return LoyaltyInfo.fromJson(result['client'], settings: settings);
  }

  static Future<LoyaltyInfo> redeem(String qr) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '',
      body: {
        'action': 'redeem',
        'qr': qr,
      },
      timeout: ApiConstants.longTimeout,
    );

    if (result == null || result['success'] != true) {
      throw Exception(result?['error'] ?? 'Произошла ошибка сервера');
    }

    // Загружаем настройки акции
    final settings = await fetchPromoSettings();
    final loyaltyInfo = LoyaltyInfo.fromJson(result['client'], settings: settings);

    // Обновляем счётчик бесплатных напитков в нашей базе клиентов
    try {
      await incrementFreeDrinksGiven(loyaltyInfo.phone, count: settings.drinksToGive);
    } catch (e) {
      Logger.error('Ошибка обновления счётчика бесплатных напитков', e);
    }

    return loyaltyInfo;
  }

  /// Увеличить счётчик выданных бесплатных напитков для клиента
  static Future<void> incrementFreeDrinksGiven(String phone, {int count = 1}) async {
    try {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      await BaseHttpService.postRaw(
        endpoint: '/api/clients/$normalizedPhone/free-drink',
        body: {'count': count},
      );
      Logger.debug('🍹 Счётчик бесплатных напитков обновлён: +$count для $normalizedPhone');
    } catch (e) {
      Logger.error('Ошибка обновления счётчика бесплатных напитков', e);
      rethrow;
    }
  }

  /// Синхронизировать freeDrinksGiven с данными из внешнего API лояльности
  static Future<void> syncFreeDrinksGiven(String phone, int freeDrinks) async {
    try {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      await BaseHttpService.postRaw(
        endpoint: '/api/clients/$normalizedPhone/sync-free-drinks',
        body: {'freeDrinksGiven': freeDrinks},
      );
      Logger.debug('🔄 Синхронизация freeDrinksGiven: $freeDrinks для $normalizedPhone');
    } catch (e) {
      // Не критично, просто логируем
      Logger.error('Ошибка синхронизации freeDrinksGiven', e);
    }
  }
}



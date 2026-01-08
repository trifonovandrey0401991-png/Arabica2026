import 'dart:convert';

import 'package:http/http.dart' as http;

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
      final uri = Uri.parse('${ApiConstants.serverUrl}/api/loyalty-promo');
      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _cachedSettings = LoyaltyPromoSettings.fromJson(data);
          _cacheTime = DateTime.now();
          Logger.debug('✅ Настройки акции загружены: ${_cachedSettings!.pointsRequired}+${_cachedSettings!.drinksToGive}');
          return _cachedSettings!;
        }
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

  static Future<LoyaltyInfo> registerClient({
    required String name,
    required String phone,
    required String qr,
  }) async {
    // Нормализуем номер телефона: убираем + и пробелы
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
    final response = await _post({
      'action': 'register',
      'name': name,
      'phone': normalizedPhone,
      'qr': qr,
      'points': 0,
      'freeDrinks': 0,
    });
    
    // Если есть сообщение о том, что пользователь уже существует, это нормально
    if (response['message'] != null) {
      Logger.info(response['message']);
    }

    // Загружаем настройки акции
    final settings = await fetchPromoSettings();
    return LoyaltyInfo.fromJson(response['client'], settings: settings);
  }

  static Future<LoyaltyInfo> fetchByPhone(String phone) async {
    try {
    // Нормализуем номер телефона: убираем + и пробелы
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
    final uri = Uri.parse(
      '${ApiConstants.serverUrl}?action=getClient&phone=${Uri.encodeQueryComponent(normalizedPhone)}',
    );

    Logger.debug('📞 Поиск пользователя с номером: $normalizedPhone');

    http.Response response;
    try {
      final stopwatch = Stopwatch()..start();
      response = await http.get(uri).timeout(
        ApiConstants.defaultTimeout,
        onTimeout: () {
          stopwatch.stop();
          Logger.error('ТАЙМАУТ: Запрос не завершился за 15 секунд', Exception('Таймаут'));
          throw Exception('Таймаут при получении данных клиента');
        },
      );
      stopwatch.stop();
      Logger.debug('⏱️ Время подключения: ${stopwatch.elapsedMilliseconds}ms');
    } on http.ClientException catch (e) {
      Logger.error('Сетевая ошибка (ClientException)', e);
      rethrow;
    } on Exception catch (e) {
      Logger.error('Ошибка запроса', e);
      rethrow;
    }
      
      if (response.statusCode != 200) {
        Logger.error('Неожиданный статус ответа: ${response.statusCode}');
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }

    final data = _decode(response.body);
    
    if (data['success'] != true) {
      Logger.error('Сервер вернул success: false. Ошибка: ${data['error']}');
      throw Exception(data['error'] ?? 'Не удалось получить данные клиента');
    }

      if (data['client'] == null) {
        Logger.error('Клиент не найден в ответе сервера');
        throw Exception('Клиент не найден в базе данных');
      }

    Logger.debug('Пользователь найден: ${data['client']['name']}');

    // Загружаем настройки акции с нашего сервера
    final settings = await fetchPromoSettings();
    final info = LoyaltyInfo.fromJson(data['client'], settings: settings);

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
    final uri = Uri.parse(
      '${ApiConstants.serverUrl}?action=getClient&qr=${Uri.encodeQueryComponent(qr)}',
    );

    final response = await http.get(uri).timeout(ApiConstants.longTimeout);
      
      if (response.statusCode != 200) {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }

    final data = _decode(response.body);
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Не удалось получить данные клиента');
    }

      if (data['client'] == null) {
        throw Exception('Клиент не найден в базе данных');
      }

    // Загружаем настройки акции с нашего сервера
    final settings = await fetchPromoSettings();
    final info = LoyaltyInfo.fromJson(data['client'], settings: settings);

    return info;
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Ошибка при получении данных клиента: $e');
    }
  }

  static Future<LoyaltyInfo> addPoint(String qr) async {
    final response = await _post({
      'action': 'addPoint',
      'qr': qr,
    });

    // Загружаем настройки акции для корректного определения readyForRedeem
    final settings = await fetchPromoSettings();
    return LoyaltyInfo.fromJson(response['client'], settings: settings);
  }

  static Future<LoyaltyInfo> redeem(String qr) async {
    final response = await _post({
      'action': 'redeem',
      'qr': qr,
    });

    // Загружаем настройки акции
    final settings = await fetchPromoSettings();
    return LoyaltyInfo.fromJson(response['client'], settings: settings);
  }

  static Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse(ApiConstants.serverUrl);
      if (!uri.hasScheme || !uri.hasAuthority) {
        throw Exception('Invalid URL: ${ApiConstants.serverUrl}');
      }

      final response = await http
          .post(
            uri,
            headers: ApiConstants.jsonHeaders,
            body: jsonEncode(body),
          )
          .timeout(ApiConstants.longTimeout);

      if (response.statusCode != 200) {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }

      final data = _decode(response.body);
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Произошла ошибка сервера');
      }
      return data;
    } catch (e) {
      if (e is Exception && e.toString().contains('Invalid URL')) {
        rethrow;
      }
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Ошибка при отправке запроса: $e');
    }
  }

  static Map<String, dynamic> _decode(String raw) {
    try {
      if (raw.isEmpty) {
        throw Exception('Пустой ответ от сервера');
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Некорректный формат ответа сервера');
      }
      return decoded;
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Некорректный ответ сервера: $e');
    }
  }
}



import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../server_config.dart';
import '../../../core/utils/logger.dart';

class LoyaltyInfo {
  final String name;
  final String phone;
  final String qr;
  final int points;
  final int freeDrinks;
  final String promoText;
  final bool readyForRedeem;

  const LoyaltyInfo({
    required this.name,
    required this.phone,
    required this.qr,
    required this.points,
    required this.freeDrinks,
    required this.promoText,
    required this.readyForRedeem,
  });

  factory LoyaltyInfo.fromJson(Map<String, dynamic> json) {
    return LoyaltyInfo(
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      qr: (json['qr'] ?? '').toString(),
      points: int.tryParse(json['points']?.toString() ?? '') ?? 0,
      freeDrinks: int.tryParse(json['freeDrinks']?.toString() ?? '') ?? 0,
      promoText: (json['promoText'] ?? '').toString(),
      readyForRedeem: json['readyForRedeem'] == true,
    );
  }
}

class LoyaltyService {
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
    
    return LoyaltyInfo.fromJson(response['client']);
  }

  static Future<LoyaltyInfo> fetchByPhone(String phone) async {
    try {
    // Нормализуем номер телефона: убираем + и пробелы
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
    final uri = Uri.parse(
      '$serverUrl?action=getClient&phone=${Uri.encodeQueryComponent(normalizedPhone)}',
    );
    
    Logger.debug('📞 Поиск пользователя с номером: $normalizedPhone');

    http.Response response;
    try {
      final stopwatch = Stopwatch()..start();
      response = await http.get(uri).timeout(
        const Duration(seconds: 15), // Уменьшен таймаут с 30 до 15 секунд
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

    Logger.success('Пользователь найден: ${data['client']['name']}');
    return LoyaltyInfo.fromJson(data['client']);
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
      '$serverUrl?action=getClient&qr=${Uri.encodeQueryComponent(qr)}',
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 30));
      
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

    return LoyaltyInfo.fromJson(data['client']);
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

    return LoyaltyInfo.fromJson(response['client']);
  }

  static Future<LoyaltyInfo> redeem(String qr) async {
    final response = await _post({
      'action': 'redeem',
      'qr': qr,
    });

    return LoyaltyInfo.fromJson(response['client']);
  }

  static Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse(serverUrl);
      if (!uri.hasScheme || !uri.hasAuthority) {
        throw Exception('Invalid URL: $serverUrl');
      }
      
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

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



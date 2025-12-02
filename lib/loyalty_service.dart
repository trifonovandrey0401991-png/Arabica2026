import 'dart:convert';

import 'package:http/http.dart' as http;

import 'google_script_config.dart';

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
      // ignore: avoid_print
      print('ℹ️ ${response['message']}');
    }
    
    return LoyaltyInfo.fromJson(response['client']);
  }

  static Future<LoyaltyInfo> fetchByPhone(String phone) async {
    try {
    // Нормализуем номер телефона: убираем + и пробелы
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
    final uri = Uri.parse(
      '$googleScriptUrl?action=getClient&phone=${Uri.encodeQueryComponent(normalizedPhone)}',
    );
    
    print('📞 Поиск пользователя с номером: $normalizedPhone (исходный: $phone)');
    print('🔗 URL запроса: $uri');
    print('⏰ Время начала запроса: ${DateTime.now().toIso8601String()}');
    print('🌐 Платформа: ${Uri.base.scheme}');
    print('🔍 Пробуем подключиться к серверу...');

    http.Response response;
    try {
      final stopwatch = Stopwatch()..start();
      response = await http.get(uri).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          stopwatch.stop();
          print('⏱️ ТАЙМАУТ: Запрос не завершился за 30 секунд');
          print('⏱️ Прошло времени: ${stopwatch.elapsedMilliseconds}ms');
          throw Exception('Таймаут при получении данных клиента');
        },
      );
      stopwatch.stop();
      print('⏱️ Время подключения: ${stopwatch.elapsedMilliseconds}ms');
      print('✅ Ответ получен: статус ${response.statusCode}');
      print('📦 Размер ответа: ${response.body.length} байт');
      print('⏰ Время получения ответа: ${DateTime.now().toIso8601String()}');
    } on http.ClientException catch (e) {
      print('❌ Сетевая ошибка (ClientException): $e');
      print('   Это может быть из-за:');
      print('   1. Проблем с сетью на устройстве');
      print('   2. Сервер недоступен');
      print('   3. Проблем с DNS');
      rethrow;
    } on Exception catch (e) {
      print('❌ Ошибка запроса: $e');
      rethrow;
    }
      
      if (response.statusCode != 200) {
        print('❌ Неожиданный статус ответа: ${response.statusCode}');
        print('📄 Тело ответа: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }

    final data = _decode(response.body);
    print('📋 Данные ответа: success=${data['success']}, client=${data['client'] != null ? "найден" : "не найден"}');
    
    if (data['success'] != true) {
      print('❌ Сервер вернул success: false');
      print('   Ошибка: ${data['error']}');
      throw Exception(data['error'] ?? 'Не удалось получить данные клиента');
    }

      if (data['client'] == null) {
        print('❌ Клиент не найден в ответе сервера');
        throw Exception('Клиент не найден в базе данных');
      }

    print('✅ Пользователь найден: ${data['client']['name']}');
    return LoyaltyInfo.fromJson(data['client']);
    } catch (e, stackTrace) {
      print('❌ КРИТИЧЕСКАЯ ОШИБКА в fetchByPhone: $e');
      print('📚 Stack trace: $stackTrace');
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Ошибка при получении данных клиента: $e');
    }
  }

  static Future<LoyaltyInfo> fetchByQr(String qr) async {
    try {
    final uri = Uri.parse(
      '$googleScriptUrl?action=getClient&qr=${Uri.encodeQueryComponent(qr)}',
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
      final uri = Uri.parse(googleScriptUrl);
      if (!uri.hasScheme || !uri.hasAuthority) {
        throw Exception('Invalid URL: $googleScriptUrl');
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



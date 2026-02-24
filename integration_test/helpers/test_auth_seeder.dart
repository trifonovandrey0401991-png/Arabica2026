import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'test_data.dart';

/// Пре-заполняет SharedPreferences и FlutterSecureStorage
/// настоящим токеном от сервера, чтобы приложение показывало PinEntryPage.
///
/// Вызывать ПЕРЕД app.main() в каждом тесте.
class TestAuthSeeder {
  static const String _apiBase = 'https://arabica26.ru';

  /// Записать сессию developer'а (Андрей В, 79054443224)
  static Future<void> seedDeveloper() async {
    await _seedSession(
      phone: TestData.testClientPhone, // 79054443224
      name: TestData.testClientName,   // Андрей В
      pin: TestData.testPin,           // 1111
    );
  }

  /// Записать сессию для произвольного пользователя
  static Future<void> seedUser({
    required String phone,
    required String name,
    String pin = '1111',
  }) async {
    await _seedSession(phone: phone, name: name, pin: pin);
  }

  static Future<void> _seedSession({
    required String phone,
    required String name,
    required String pin,
  }) async {
    // 1. Получаем НАСТОЯЩИЙ токен от сервера
    print('>>> TestAuthSeeder: Получаем токен для $phone...');
    final loginResponse = await http.post(
      Uri.parse('$_apiBase/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'pin': pin,
        'deviceId': 'integration-test-device',
        'deviceName': 'Integration Test',
      }),
    );

    if (loginResponse.statusCode != 200) {
      print('>>> TestAuthSeeder: Ошибка логина: ${loginResponse.statusCode} ${loginResponse.body}');
      throw Exception('Auth login failed: ${loginResponse.statusCode}');
    }

    final loginData = jsonDecode(loginResponse.body);
    final sessionToken = loginData['sessionToken'] as String;
    final expiresAt = loginData['expiresAt'];
    final serverName = loginData['name'] ?? name;
    print('>>> TestAuthSeeder: Токен получен для $serverName');

    // 2. SharedPreferences — минимум для _checkRegistration
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_registered', true);
    await prefs.setString('user_phone', phone);
    await prefs.setString('user_name', serverName);

    // 3. FlutterSecureStorage — PIN и сессия с НАСТОЯЩИМ токеном
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );

    // auth_credentials — хеш PIN для локальной проверки
    final salt = 'test_salt_for_integration_tests';
    final pinHash = sha256.convert(utf8.encode(pin + salt)).toString();
    final credentials = {
      'pinHash': pinHash,
      'salt': salt,
      'biometricEnabled': false,
      'createdAt': DateTime.now().toIso8601String(),
      'failedAttempts': 0,
      'lockedUntil': null,
    };
    await storage.write(
        key: 'auth_credentials', value: jsonEncode(credentials));

    // auth_session — с НАСТОЯЩИМ токеном от сервера
    final session = {
      'sessionToken': sessionToken,
      'phone': phone,
      'name': serverName,
      'deviceId': 'integration-test-device',
      'deviceName': 'Integration Test',
      'createdAt': DateTime.now().toIso8601String(),
      'expiresAt': expiresAt is int
          ? DateTime.fromMillisecondsSinceEpoch(expiresAt).toIso8601String()
          : expiresAt.toString(),
      'lastActivity': null,
      'isVerified': true,
      'role': 'employee',
    };
    await storage.write(key: 'auth_session', value: jsonEncode(session));

    print('>>> TestAuthSeeder: Сессия записана');
  }
}

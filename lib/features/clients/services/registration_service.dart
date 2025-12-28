import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../loyalty/services/loyalty_service.dart';
import 'core/utils/logger.dart';

/// Сервис регистрации клиентов.
class RegistrationService {
  static const String serverUrl = 'https://arabica26.ru';
  
  /// Регистрирует клиента и возвращает информацию о его программе лояльности.
  static Future<LoyaltyInfo?> registerUser({
    required String name,
    required String phone,
    required String qr,
  }) async {
    try {
      Logger.debug('📝 Регистрация пользователя: $name ($phone)');
      final info = await LoyaltyService.registerClient(
        name: name,
        phone: phone,
        qr: qr,
      );
      Logger.success('✅ Клиент зарегистрирован, QR: ${info.qr}');
      
      // Сохраняем данные о клиенте на сервере
      try {
        await _saveClientToServer(
          phone: phone,
          name: name,
          clientName: name,
        );
        Logger.success('✅ Данные клиента сохранены на сервере');
      } catch (e) {
        Logger.warning('⚠️ Не удалось сохранить данные клиента на сервере: $e');
        // Не прерываем регистрацию, если не удалось сохранить на сервере
      }
      
      return info;
    } catch (e) {
      Logger.error('❌ Ошибка регистрации: $e');
      return null;
    }
  }
  
  /// Сохранить данные клиента на сервере (публичный метод для использования в других местах)
  static Future<void> saveClientToServer({
    required String phone,
    required String name,
    required String clientName,
  }) async {
    await _saveClientToServer(
      phone: phone,
      name: name,
      clientName: clientName,
    );
  }
  
  /// Сохранить данные клиента на сервере
  static Future<void> _saveClientToServer({
    required String phone,
    required String name,
    required String clientName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/api/clients'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'name': name,
          'clientName': clientName,
          'isAdmin': false,
          'employeeName': '',
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode != 200) {
        throw Exception('Ошибка сохранения: ${response.statusCode}');
      }
      
      final result = jsonDecode(response.body);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Ошибка сохранения клиента');
      }
    } catch (e) {
      Logger.warning('Ошибка сохранения клиента на сервере: $e');
      rethrow;
    }
  }
}

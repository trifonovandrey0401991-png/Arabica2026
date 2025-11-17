import 'loyalty_service.dart';

/// Сервис регистрации клиентов.
class RegistrationService {
  /// Регистрирует клиента и возвращает информацию о его программе лояльности.
  static Future<LoyaltyInfo?> registerUser({
    required String name,
    required String phone,
    required String qr,
  }) async {
    try {
      // ignore: avoid_print
      print('📝 Регистрация пользователя: $name ($phone)');
      final info = await LoyaltyService.registerClient(
        name: name,
        phone: phone,
        qr: qr,
      );
      // ignore: avoid_print
      print('✅ Клиент зарегистрирован, QR: ${info.qr}');
      return info;
    } catch (e) {
      // ignore: avoid_print
      print('❌ Ошибка регистрации: $e');
      return null;
    }
  }
}

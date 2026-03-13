import '../../loyalty/services/loyalty_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/utils/logger.dart';

/// Сервис регистрации клиентов.
class RegistrationService {
  /// Регистрирует клиента и возвращает информацию о его программе лояльности.
  static Future<LoyaltyInfo?> registerUser({
    required String name,
    required String phone,
    required String qr,
  }) async {
    try {
      Logger.debug('Регистрация пользователя: $name (${Logger.maskPhone(phone)})');

      // 1. Сначала создаём клиента на сервере (POST /api/clients)
      // Это нужно ДО registerClient, т.к. action=register ищет клиента в БД
      try {
        await _saveClientToServer(
          phone: phone,
          name: name,
          clientName: name,
        );
        Logger.debug('Данные клиента сохранены на сервере');
      } catch (e) {
        Logger.error('Не удалось сохранить данные клиента на сервере', e);
        // Продолжаем — registerClient может найти клиента другим способом
      }

      // 2. Теперь регистрируем в системе лояльности
      final info = await LoyaltyService.registerClient(
        name: name,
        phone: phone,
        qr: qr,
      );
      Logger.success('Клиент зарегистрирован, QR: ${info.qr}');

      return info;
    } catch (e) {
      Logger.error('Ошибка регистрации', e);
      return null;
    }
  }

  /// Сохранить данные клиента на сервере (публичный метод для использования в других местах)
  static Future<void> saveClientToServer({
    required String phone,
    required String name,
    required String clientName,
    int? referredBy,
  }) async {
    await _saveClientToServer(
      phone: phone,
      name: name,
      clientName: clientName,
      referredBy: referredBy,
    );
  }

  /// Сохранить данные клиента на сервере
  static Future<void> _saveClientToServer({
    required String phone,
    required String name,
    required String clientName,
    int? referredBy,
  }) async {
    try {
      final body = <String, dynamic>{
        'phone': phone,
        'name': name,
        'clientName': clientName,
        'isAdmin': false,
        'employeeName': '',
      };

      // Добавляем referredBy только если указан
      if (referredBy != null) {
        body['referredBy'] = referredBy;
      }

      final success = await BaseHttpService.simplePost(
        endpoint: ApiConstants.clientsEndpoint,
        body: body,
      );

      if (!success) {
        throw Exception('Ошибка сохранения клиента');
      }
    } catch (e) {
      Logger.error('Ошибка сохранения клиента на сервере', e);
      rethrow;
    }
  }
}

import '../models/client_model.dart';
import '../models/client_message_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class ClientService {
  /// Получить список всех клиентов
  static Future<List<Client>> getClients() async {
    Logger.debug('Загрузка списка клиентов...');

    final clients = await BaseHttpService.getList<Client>(
      endpoint: ApiConstants.clientsEndpoint,
      fromJson: (json) => Client.fromJson(json),
      listKey: 'clients',
    );

    if (clients.isNotEmpty) {
      Logger.debug('Первый клиент: ${clients[0].name} (${clients[0].phone})');
    }

    return clients;
  }

  /// Получить переписку с клиентом
  static Future<List<ClientMessage>> getClientMessages(String clientPhone) async {
    Logger.debug('Загрузка сообщений для клиента: $clientPhone');

    return await BaseHttpService.getList<ClientMessage>(
      endpoint: '${ApiConstants.clientsEndpoint}/$clientPhone/messages',
      fromJson: (json) => ClientMessage.fromJson(json),
      listKey: 'messages',
    );
  }

  /// Отправить сообщение клиенту
  static Future<ClientMessage?> sendMessage({
    required String clientPhone,
    required String text,
    String? imageUrl,
    String? senderPhone,
  }) async {
    try {
      Logger.debug('Отправка сообщения клиенту: $clientPhone');

      final requestBody = <String, dynamic>{
        'text': text,
      };
      if (imageUrl != null) requestBody['imageUrl'] = imageUrl;
      if (senderPhone != null) requestBody['senderPhone'] = senderPhone;

      final result = await BaseHttpService.postRaw(
        endpoint: '${ApiConstants.clientsEndpoint}/$clientPhone/messages',
        body: requestBody,
        timeout: ApiConstants.longTimeout,
      );

      if (result != null) {
        Logger.debug('Сообщение отправлено');

        if (result['message'] != null && result['message'] is Map) {
          return ClientMessage.fromJson(result['message'] as Map<String, dynamic>);
        } else {
          return ClientMessage(
            id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
            clientPhone: clientPhone,
            senderPhone: senderPhone ?? 'system',
            text: text,
            imageUrl: imageUrl,
            timestamp: DateTime.now().toIso8601String(),
            isRead: false,
          );
        }
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка отправки сообщения', e);
      return null;
    }
  }

  /// Отправить сообщение всем клиентам
  static Future<Map<String, dynamic>?> sendBroadcastMessage({
    required String text,
    String? imageUrl,
    String? senderPhone,
  }) async {
    try {
      Logger.debug('Отправка сообщения всем клиентам');

      final requestBody = <String, dynamic>{
        'text': text,
      };
      if (imageUrl != null) requestBody['imageUrl'] = imageUrl;
      if (senderPhone != null) requestBody['senderPhone'] = senderPhone;

      final result = await BaseHttpService.postRaw(
        endpoint: '${ApiConstants.clientsEndpoint}/messages/broadcast',
        body: requestBody,
        timeout: const Duration(seconds: 60),
      );

      if (result != null) {
        Logger.debug('Сообщение отправлено ${result['sentCount']} клиентам');
        return {
          'sentCount': result['sentCount'] ?? 0,
          'totalClients': result['totalClients'] ?? 0,
        };
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка отправки сообщения всем клиентам', e);
      return null;
    }
  }

  /// Отметить сообщение как прочитанное
  static Future<bool> markMessageAsRead(String messageId) async {
    try {
      Logger.debug('Отметка сообщения как прочитанного: $messageId');
      return true;
    } catch (e) {
      Logger.error('Ошибка отметки сообщения', e);
      return false;
    }
  }

  /// Отметить сетевые сообщения клиента как прочитанные админом
  static Future<bool> markNetworkMessagesAsReadByAdmin(String clientPhone) async {
    try {
      Logger.debug('Отметка сетевых сообщений клиента как прочитанных: $clientPhone');

      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
      return await BaseHttpService.simplePost(
        endpoint: '/api/client-dialogs/$normalizedPhone/network/read-by-admin',
        body: {},
      );
    } catch (e) {
      Logger.error('Ошибка отметки сообщений', e);
      return false;
    }
  }
}

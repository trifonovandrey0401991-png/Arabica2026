import '../models/network_message_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class NetworkMessageService {
  static const String _baseEndpoint = ApiConstants.clientDialogsEndpoint;

  /// Получить сетевые сообщения (broadcast) для клиента
  static Future<NetworkDialogData> getNetworkMessages(String clientPhone) async {
    try {
      Logger.debug('Loading network messages for: $clientPhone');

      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/$normalizedPhone/network',
      );

      if (result != null && result['success'] == true) {
        final data = NetworkDialogData.fromJson(result);
        Logger.debug('Loaded ${data.messages.length} network messages');
        return data;
      }

      return NetworkDialogData(messages: [], unreadCount: 0);
    } catch (e) {
      Logger.error('Error loading network messages: $e');
      return NetworkDialogData(messages: [], unreadCount: 0);
    }
  }

  /// Отправить ответ на сетевое сообщение
  static Future<NetworkMessage?> sendReply({
    required String clientPhone,
    required String text,
    String? imageUrl,
    String? clientName,
  }) async {
    Logger.debug('Sending network reply from: $clientPhone');

    final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');

    return await BaseHttpService.post<NetworkMessage>(
      endpoint: '$_baseEndpoint/$normalizedPhone/network/reply',
      body: {
        'text': text,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (clientName != null) 'clientName': clientName,
      },
      fromJson: (json) => NetworkMessage.fromJson(json),
      itemKey: 'message',
    );
  }

  /// Отметить сообщения как прочитанные клиентом
  static Future<bool> markAsReadByClient(String clientPhone) async {
    Logger.debug('Marking network messages as read by client: $clientPhone');

    final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
    return await BaseHttpService.simplePost(
      endpoint: '$_baseEndpoint/$normalizedPhone/network/read-by-client',
      body: {},
    );
  }
}

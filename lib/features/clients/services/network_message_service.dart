import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/network_message_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class NetworkMessageService {
  /// Получить сетевые сообщения (broadcast) для клиента
  static Future<NetworkDialogData> getNetworkMessages(String clientPhone) async {
    try {
      Logger.debug('Loading network messages for: $clientPhone');

      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/client-dialogs/$normalizedPhone/network'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final data = NetworkDialogData.fromJson(result);
          Logger.debug('Loaded ${data.messages.length} network messages');
          return data;
        }
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
    try {
      Logger.debug('Sending network reply from: $clientPhone');

      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
      final requestBody = <String, dynamic>{
        'text': text,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (clientName != null) 'clientName': clientName,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/client-dialogs/$normalizedPhone/network/reply'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(requestBody),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['message'] != null) {
          Logger.debug('Network reply sent successfully');
          return NetworkMessage.fromJson(result['message'] as Map<String, dynamic>);
        }
      }

      return null;
    } catch (e) {
      Logger.error('Error sending network reply: $e');
      return null;
    }
  }

  /// Отметить сообщения как прочитанные клиентом
  static Future<bool> markAsReadByClient(String clientPhone) async {
    try {
      Logger.debug('Marking network messages as read by client: $clientPhone');

      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/client-dialogs/$normalizedPhone/network/read-by-client'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }

      return false;
    } catch (e) {
      Logger.error('Error marking messages as read: $e');
      return false;
    }
  }
}

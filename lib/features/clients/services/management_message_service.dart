import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/management_message_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class ManagementMessageService {
  /// Получить сообщения руководству для клиента
  static Future<ManagementDialogData> getManagementMessages(String clientPhone) async {
    try {
      Logger.debug('Loading management messages for: $clientPhone');

      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/client-dialogs/$normalizedPhone/management'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final data = ManagementDialogData.fromJson(result);
          Logger.debug('Loaded ${data.messages.length} management messages');
          return data;
        }
      }

      return ManagementDialogData(messages: [], unreadCount: 0);
    } catch (e) {
      Logger.error('Error loading management messages: $e');
      return ManagementDialogData(messages: [], unreadCount: 0);
    }
  }

  /// Отправить сообщение руководству
  static Future<ManagementMessage?> sendMessage({
    required String clientPhone,
    required String text,
    String? imageUrl,
    String? clientName,
  }) async {
    try {
      Logger.debug('Sending management message from: $clientPhone');

      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
      final requestBody = <String, dynamic>{
        'text': text,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (clientName != null) 'clientName': clientName,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/client-dialogs/$normalizedPhone/management/reply'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(requestBody),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['message'] != null) {
          Logger.debug('Management message sent successfully');
          return ManagementMessage.fromJson(result['message'] as Map<String, dynamic>);
        }
      }

      return null;
    } catch (e) {
      Logger.error('Error sending management message: $e');
      return null;
    }
  }

  /// Отправить сообщение от руководства клиенту
  static Future<ManagementMessage?> sendManagerMessage({
    required String clientPhone,
    required String text,
    String? imageUrl,
  }) async {
    try {
      Logger.debug('Sending manager message to: $clientPhone');

      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
      final requestBody = <String, dynamic>{
        'text': text,
        if (imageUrl != null) 'imageUrl': imageUrl,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/client-dialogs/$normalizedPhone/management/send'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(requestBody),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['message'] != null) {
          Logger.debug('Manager message sent successfully');
          return ManagementMessage.fromJson(result['message'] as Map<String, dynamic>);
        }
      }

      return null;
    } catch (e) {
      Logger.error('Error sending manager message: $e');
      return null;
    }
  }

  /// Отметить сообщения как прочитанные клиентом
  static Future<bool> markAsReadByClient(String clientPhone) async {
    try {
      Logger.debug('Marking management messages as read by client: $clientPhone');

      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/client-dialogs/$normalizedPhone/management/read-by-client'),
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

  /// Отметить сообщения как прочитанные руководством (админом)
  static Future<bool> markAsReadByManager(String clientPhone) async {
    try {
      Logger.debug('Marking management messages as read by manager: $clientPhone');

      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/client-dialogs/$normalizedPhone/management/read-by-manager'),
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

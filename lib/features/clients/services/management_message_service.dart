import '../models/management_message_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class ManagementMessageService {
  static const String _baseEndpoint = ApiConstants.clientDialogsEndpoint;

  /// Получить сообщения руководству для клиента
  static Future<ManagementDialogData> getManagementMessages(String clientPhone) async {
    try {
      Logger.debug('Loading management messages for: $clientPhone');

      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');

      // Guard against empty phone
      if (normalizedPhone.isEmpty) {
        Logger.debug('⚠️ Empty phone number, skipping request');
        return ManagementDialogData(messages: [], unreadCount: 0);
      }

      // SECURITY: Передаём clientPhone для авторизационной проверки на сервере
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/$normalizedPhone/management?clientPhone=$normalizedPhone',
      );

      if (result != null && result['success'] == true) {
        final data = ManagementDialogData.fromJson(result);
        Logger.debug('Loaded ${data.messages.length} management messages');
        return data;
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
    Logger.debug('Sending management message from: $clientPhone');

    final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');

    return await BaseHttpService.post<ManagementMessage>(
      endpoint: '$_baseEndpoint/$normalizedPhone/management/reply',
      body: {
        'text': text,
        'senderPhone': normalizedPhone, // SECURITY: Передаём телефон для проверки
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (clientName != null) 'clientName': clientName,
      },
      fromJson: (json) => ManagementMessage.fromJson(json),
      itemKey: 'message',
    );
  }

  /// Отправить сообщение от руководства клиенту
  /// [senderPhone] - телефон админа для проверки прав на сервере
  static Future<ManagementMessage?> sendManagerMessage({
    required String clientPhone,
    required String text,
    required String senderPhone, // SECURITY: Обязательный параметр для проверки isAdmin
    String? imageUrl,
  }) async {
    Logger.debug('Sending manager message to: $clientPhone from admin: $senderPhone');

    final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
    final normalizedSenderPhone = senderPhone.replaceAll(RegExp(r'[\s\+]'), '');

    return await BaseHttpService.post<ManagementMessage>(
      endpoint: '$_baseEndpoint/$normalizedPhone/management/send',
      body: {
        'text': text,
        'senderPhone': normalizedSenderPhone, // SECURITY: Передаём телефон админа
        if (imageUrl != null) 'imageUrl': imageUrl,
      },
      fromJson: (json) => ManagementMessage.fromJson(json),
      itemKey: 'message',
    );
  }

  /// Отметить сообщения как прочитанные клиентом
  static Future<bool> markAsReadByClient(String clientPhone) async {
    Logger.debug('Marking management messages as read by client: $clientPhone');

    final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
    return await BaseHttpService.simplePost(
      endpoint: '$_baseEndpoint/$normalizedPhone/management/read-by-client',
      body: {},
    );
  }

  /// Отметить сообщения как прочитанные руководством (админом)
  static Future<bool> markAsReadByManager(String clientPhone) async {
    Logger.debug('Marking management messages as read by manager: $clientPhone');

    final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s\+]'), '');
    return await BaseHttpService.simplePost(
      endpoint: '$_baseEndpoint/$normalizedPhone/management/read-by-manager',
      body: {},
    );
  }
}

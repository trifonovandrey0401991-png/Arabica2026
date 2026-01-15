import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/employee_chat_model.dart';
import '../models/employee_chat_message_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

// http и dart:convert оставлены для multipart загрузки фото

/// Сервис для работы с чатом сотрудников
class EmployeeChatService {
  static const String baseEndpoint = ApiConstants.employeeChatsEndpoint;

  /// Получить список всех чатов для пользователя
  static Future<List<EmployeeChat>> getChats(String phone, {bool isAdmin = false}) async {
    Logger.debug('📥 Загрузка списка чатов для $phone (isAdmin: $isAdmin)...');
    return await BaseHttpService.getList<EmployeeChat>(
      endpoint: baseEndpoint,
      fromJson: (json) => EmployeeChat.fromJson(json),
      listKey: 'chats',
      queryParams: {
        'phone': phone,
        if (isAdmin) 'isAdmin': 'true',
      },
    );
  }

  /// Получить сообщения чата
  static Future<List<EmployeeChatMessage>> getMessages(
    String chatId, {
    String? phone,
    int limit = 50,
    String? before,
  }) async {
    Logger.debug('📥 Загрузка сообщений чата $chatId...');

    final queryParams = <String, String>{'limit': limit.toString()};
    if (phone != null) queryParams['phone'] = phone;
    if (before != null) queryParams['before'] = before;

    return await BaseHttpService.getList<EmployeeChatMessage>(
      endpoint: '$baseEndpoint/$chatId/messages',
      fromJson: (json) => EmployeeChatMessage.fromJson(json),
      listKey: 'messages',
      queryParams: queryParams,
    );
  }

  /// Отправить сообщение
  static Future<EmployeeChatMessage?> sendMessage({
    required String chatId,
    required String senderPhone,
    required String senderName,
    String? text,
    String? imageUrl,
  }) async {
    Logger.debug('📤 Отправка сообщения в чат $chatId...');

    return await BaseHttpService.post<EmployeeChatMessage>(
      endpoint: '$baseEndpoint/$chatId/messages',
      body: {
        'senderPhone': senderPhone,
        'senderName': senderName,
        'text': text ?? '',
        if (imageUrl != null) 'imageUrl': imageUrl,
      },
      fromJson: (json) => EmployeeChatMessage.fromJson(json),
      itemKey: 'message',
    );
  }

  /// Отметить чат как прочитанный
  static Future<bool> markAsRead(String chatId, String phone) async {
    Logger.debug('📝 Отметка чата $chatId как прочитанного...');
    return await BaseHttpService.simplePost(
      endpoint: '$baseEndpoint/$chatId/read',
      body: {'phone': phone},
    );
  }

  /// Создать или получить приватный чат
  static Future<EmployeeChat?> getOrCreatePrivateChat(
    String phone1,
    String phone2,
  ) async {
    Logger.debug('📝 Создание приватного чата $phone1 - $phone2...');

    return await BaseHttpService.post<EmployeeChat>(
      endpoint: '$baseEndpoint/private',
      body: {
        'phone1': phone1,
        'phone2': phone2,
      },
      fromJson: (json) => EmployeeChat.fromJson(json),
      itemKey: 'chat',
    );
  }

  /// Создать или получить чат магазина
  static Future<EmployeeChat?> getOrCreateShopChat(String shopAddress) async {
    Logger.debug('📝 Создание чата магазина $shopAddress...');

    return await BaseHttpService.post<EmployeeChat>(
      endpoint: '$baseEndpoint/shop',
      body: {'shopAddress': shopAddress},
      fromJson: (json) => EmployeeChat.fromJson(json),
      itemKey: 'chat',
    );
  }

  /// Загрузить фото для сообщения (multipart upload)
  static Future<String?> uploadMessagePhoto(File photoFile) async {
    try {
      Logger.debug('📤 Загрузка фото для сообщения...');

      final uri = Uri.parse('${ApiConstants.serverUrl}/upload-media');
      final request = http.MultipartRequest('POST', uri);

      final bytes = await photoFile.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
        contentType: MediaType('image', 'jpeg'),
      );

      request.files.add(multipartFile);

      final streamedResponse = await request.send().timeout(ApiConstants.uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['url'] != null) {
          final photoUrl = data['url'] as String;
          Logger.debug('✅ Фото загружено: $photoUrl');
          return photoUrl;
        }
      }

      Logger.debug('⚠️ Ошибка загрузки фото: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('Ошибка загрузки фото', e);
      return null;
    }
  }

  /// Удалить сообщение (только для админов)
  static Future<bool> deleteMessage(String chatId, String messageId) async {
    Logger.debug('🗑️ Удаление сообщения $messageId из чата $chatId...');
    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/$chatId/messages/$messageId',
    );
  }

  // ===== УПРАВЛЕНИЕ УЧАСТНИКАМИ ЧАТА МАГАЗИНА =====

  /// Получить участников чата магазина
  static Future<List<ShopChatMember>> getShopChatMembers(String shopAddress) async {
    Logger.debug('📥 Загрузка участников чата магазина $shopAddress...');
    return await BaseHttpService.getList<ShopChatMember>(
      endpoint: '$baseEndpoint/shop/$shopAddress/members',
      fromJson: (json) => ShopChatMember.fromJson(json),
      listKey: 'members',
    );
  }

  /// Добавить сотрудников в чат магазина
  static Future<bool> addShopChatMembers(String shopAddress, List<String> phones) async {
    Logger.debug('➕ Добавление ${phones.length} сотрудников в чат магазина $shopAddress...');
    return await BaseHttpService.simplePost(
      endpoint: '$baseEndpoint/shop/$shopAddress/members',
      body: {'phones': phones},
    );
  }

  /// Удалить сотрудника из чата магазина
  static Future<bool> removeShopChatMember(String shopAddress, String phone) async {
    Logger.debug('➖ Удаление сотрудника $phone из чата магазина $shopAddress...');
    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/shop/$shopAddress/members/$phone',
    );
  }

  // ===== ОЧИСТКА СООБЩЕНИЙ =====

  /// Очистить сообщения чата
  /// mode: "previous_month" - удалить за предыдущий месяц, "all" - удалить все
  static Future<int> clearChatMessages(String chatId, String mode) async {
    Logger.debug('🗑️ Очистка сообщений чата $chatId (режим: $mode)...');
    try {
      final response = await BaseHttpService.postRaw(
        endpoint: '$baseEndpoint/$chatId/clear',
        body: {'mode': mode},
      );
      if (response != null && response['deletedCount'] != null) {
        return response['deletedCount'] as int;
      }
      return 0;
    } catch (e) {
      Logger.error('Ошибка очистки сообщений', e);
      return 0;
    }
  }
}

/// Модель участника чата магазина
class ShopChatMember {
  final String phone;
  final String name;
  final String position;

  ShopChatMember({
    required this.phone,
    required this.name,
    this.position = '',
  });

  factory ShopChatMember.fromJson(Map<String, dynamic> json) => ShopChatMember(
    phone: json['phone'] ?? '',
    name: json['name'] ?? '',
    position: json['position'] ?? '',
  );
}

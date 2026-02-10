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
    Logger.debug('📥 Загрузка списка чатов для ${Logger.maskPhone(phone)} (isAdmin: $isAdmin)...');
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
    Logger.debug('📝 Создание приватного чата ${Logger.maskPhone(phone1)} - ${Logger.maskPhone(phone2)}...');

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

      final uri = Uri.parse('${ApiConstants.serverUrl}/upload-photo');
      final request = http.MultipartRequest('POST', uri);

      // Добавляем заголовки авторизации
      if (ApiConstants.apiKey != null && ApiConstants.apiKey!.isNotEmpty) {
        request.headers['X-API-Key'] = ApiConstants.apiKey!;
      }
      if (ApiConstants.sessionToken != null && ApiConstants.sessionToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${ApiConstants.sessionToken}';
      }

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
  /// [requesterPhone] - телефон запрашивающего (должен быть админом)
  static Future<bool> deleteMessage(String chatId, String messageId, {required String requesterPhone}) async {
    Logger.debug('🗑️ Удаление сообщения $messageId из чата $chatId (requester: ${Logger.maskPhone(requesterPhone)})...');
    final normalizedPhone = requesterPhone.replaceAll(RegExp(r'[\s\+]'), '');
    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/$chatId/messages/$messageId?requesterPhone=$normalizedPhone',
    );
  }

  // ===== ПОИСК СООБЩЕНИЙ =====

  /// Поиск сообщений в чате
  static Future<List<EmployeeChatMessage>> searchMessages(
    String chatId,
    String query, {
    int limit = 50,
  }) async {
    Logger.debug('🔍 Поиск сообщений в чате $chatId: "$query"...');
    return await BaseHttpService.getList<EmployeeChatMessage>(
      endpoint: '$baseEndpoint/$chatId/messages/search',
      fromJson: (json) => EmployeeChatMessage.fromJson(json),
      listKey: 'messages',
      queryParams: {
        'query': query,
        'limit': limit.toString(),
      },
    );
  }

  // ===== РЕАКЦИИ НА СООБЩЕНИЯ =====

  /// Добавить реакцию к сообщению
  static Future<Map<String, List<String>>?> addReaction({
    required String chatId,
    required String messageId,
    required String phone,
    required String reaction,
  }) async {
    Logger.debug('👍 Добавление реакции $reaction к сообщению $messageId...');
    try {
      final response = await BaseHttpService.postRaw(
        endpoint: '$baseEndpoint/$chatId/messages/$messageId/reactions',
        body: {
          'phone': phone,
          'reaction': reaction,
        },
      );
      if (response != null && response['reactions'] != null) {
        final rawReactions = response['reactions'] as Map<String, dynamic>;
        Map<String, List<String>> result = {};
        for (final entry in rawReactions.entries) {
          if (entry.value is List) {
            result[entry.key] = List<String>.from(entry.value);
          }
        }
        return result;
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка добавления реакции', e);
      return null;
    }
  }

  /// Удалить реакцию с сообщения
  static Future<Map<String, List<String>>?> removeReaction({
    required String chatId,
    required String messageId,
    required String phone,
    required String reaction,
  }) async {
    Logger.debug('👎 Удаление реакции $reaction с сообщения $messageId...');
    try {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      final response = await BaseHttpService.deleteWithResponse(
        endpoint: '$baseEndpoint/$chatId/messages/$messageId/reactions?phone=$normalizedPhone&reaction=$reaction',
      );
      if (response != null && response['reactions'] != null) {
        final rawReactions = response['reactions'] as Map<String, dynamic>;
        Map<String, List<String>> result = {};
        for (final entry in rawReactions.entries) {
          if (entry.value is List) {
            result[entry.key] = List<String>.from(entry.value);
          }
        }
        return result;
      }
      return {};
    } catch (e) {
      Logger.error('Ошибка удаления реакции', e);
      return null;
    }
  }

  // ===== ПЕРЕСЫЛКА СООБЩЕНИЙ =====

  /// Переслать сообщение в другой чат
  static Future<EmployeeChatMessage?> forwardMessage({
    required String targetChatId,
    required String sourceChatId,
    required String sourceMessageId,
    required String senderPhone,
    required String senderName,
  }) async {
    Logger.debug('➡️ Пересылка сообщения $sourceMessageId в чат $targetChatId...');
    return await BaseHttpService.post<EmployeeChatMessage>(
      endpoint: '$baseEndpoint/$targetChatId/messages/forward',
      body: {
        'sourceChatId': sourceChatId,
        'sourceMessageId': sourceMessageId,
        'senderPhone': senderPhone,
        'senderName': senderName,
      },
      fromJson: (json) => EmployeeChatMessage.fromJson(json),
      itemKey: 'message',
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

  /// Удалить сотрудника из чата магазина (только для админов)
  /// [requesterPhone] - телефон запрашивающего (должен быть админом)
  static Future<bool> removeShopChatMember(String shopAddress, String phone, {required String requesterPhone}) async {
    Logger.debug('➖ Удаление сотрудника ${Logger.maskPhone(phone)} из чата магазина $shopAddress (requester: ${Logger.maskPhone(requesterPhone)})...');
    final normalizedPhone = requesterPhone.replaceAll(RegExp(r'[\s\+]'), '');
    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/shop/$shopAddress/members/$phone?requesterPhone=$normalizedPhone',
    );
  }

  // ===== ОЧИСТКА СООБЩЕНИЙ =====

  /// Очистить сообщения чата (только для админов)
  /// mode: "previous_month" - удалить за предыдущий месяц, "all" - удалить все
  /// [requesterPhone] - телефон запрашивающего (должен быть админом)
  static Future<int> clearChatMessages(String chatId, String mode, {required String requesterPhone}) async {
    Logger.debug('🗑️ Очистка сообщений чата $chatId (режим: $mode, requester: ${Logger.maskPhone(requesterPhone)})...');
    try {
      final normalizedPhone = requesterPhone.replaceAll(RegExp(r'[\s\+]'), '');
      final response = await BaseHttpService.postRaw(
        endpoint: '$baseEndpoint/$chatId/clear',
        body: {
          'mode': mode,
          'requesterPhone': normalizedPhone,
        },
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

  // ===== ГРУППОВЫЕ ЧАТЫ =====

  /// Создать группу (только для админов)
  static Future<EmployeeChat?> createGroup({
    required String creatorPhone,
    required String creatorName,
    required String name,
    String? imageUrl,
    required List<String> participants,
  }) async {
    Logger.debug('📝 Создание группы "$name"...');
    return await BaseHttpService.post<EmployeeChat>(
      endpoint: '$baseEndpoint/group',
      body: {
        'creatorPhone': creatorPhone,
        'creatorName': creatorName,
        'name': name,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'participants': participants,
      },
      fromJson: (json) => EmployeeChat.fromJson(json),
      itemKey: 'chat',
    );
  }

  /// Обновить группу (только создатель)
  static Future<EmployeeChat?> updateGroup({
    required String groupId,
    required String requesterPhone,
    String? name,
    String? imageUrl,
  }) async {
    Logger.debug('📝 Обновление группы $groupId...');
    return await BaseHttpService.put<EmployeeChat>(
      endpoint: '$baseEndpoint/group/$groupId',
      body: {
        'requesterPhone': requesterPhone,
        if (name != null) 'name': name,
        if (imageUrl != null) 'imageUrl': imageUrl,
      },
      fromJson: (json) => EmployeeChat.fromJson(json),
      itemKey: 'chat',
    );
  }

  /// Получить информацию о группе
  static Future<EmployeeChat?> getGroupInfo(String groupId) async {
    Logger.debug('📥 Получение информации о группе $groupId...');
    return await BaseHttpService.get<EmployeeChat>(
      endpoint: '$baseEndpoint/group/$groupId',
      fromJson: (json) => EmployeeChat.fromJson(json),
      itemKey: 'group',
    );
  }

  /// Добавить участников в группу (только создатель)
  static Future<bool> addGroupMembers({
    required String groupId,
    required String requesterPhone,
    required List<String> phones,
  }) async {
    Logger.debug('➕ Добавление участников в группу $groupId...');
    return await BaseHttpService.simplePost(
      endpoint: '$baseEndpoint/group/$groupId/members',
      body: {
        'requesterPhone': requesterPhone,
        'phones': phones,
      },
    );
  }

  /// Удалить участника из группы (только создатель)
  static Future<bool> removeGroupMember({
    required String groupId,
    required String requesterPhone,
    required String phone,
  }) async {
    Logger.debug('➖ Удаление участника ${Logger.maskPhone(phone)} из группы...');
    final normalized = requesterPhone.replaceAll(RegExp(r'[\s\+]'), '');
    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/group/$groupId/members/$phone?requesterPhone=$normalized',
    );
  }

  /// Выйти из группы
  static Future<bool> leaveGroup(String groupId, String phone) async {
    Logger.debug('🚪 Выход из группы $groupId...');
    return await BaseHttpService.simplePost(
      endpoint: '$baseEndpoint/group/$groupId/leave',
      body: {'phone': phone},
    );
  }

  /// Удалить группу (только создатель)
  static Future<bool> deleteGroup(String groupId, String requesterPhone) async {
    Logger.debug('🗑️ Удаление группы $groupId...');
    final normalized = requesterPhone.replaceAll(RegExp(r'[\s\+]'), '');
    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/group/$groupId?requesterPhone=$normalized',
    );
  }

  /// Загрузить фото группы (используем общий upload)
  static Future<String?> uploadGroupPhoto(File photoFile) async {
    return await uploadMessagePhoto(photoFile);
  }

  // ===== ПОЛУЧЕНИЕ СПИСКА КЛИЕНТОВ =====

  /// Получить список клиентов для выбора в группу
  static Future<List<ChatClient>> getClientsForGroupSelection() async {
    Logger.debug('📥 Загрузка списка клиентов для группы...');
    return await BaseHttpService.getList<ChatClient>(
      endpoint: '/api/clients/list',
      fromJson: (json) => ChatClient.fromJson(json),
      listKey: 'clients',
    );
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

/// Модель клиента для выбора в группу
class ChatClient {
  final String phone;
  final String? name;
  final int points;

  ChatClient({
    required this.phone,
    this.name,
    this.points = 0,
  });

  factory ChatClient.fromJson(Map<String, dynamic> json) => ChatClient(
    phone: json['phone'] ?? '',
    name: json['name'],
    points: json['points'] ?? 0,
  );

  /// Отображаемое имя (имя или телефон)
  String get displayName => name ?? phone;
}

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/employee_chat_model.dart';
import '../models/employee_chat_message_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

/// Сервис для работы с чатом сотрудников
class EmployeeChatService {
  static const String _baseUrl = '${ApiConstants.serverUrl}/api/employee-chats';

  /// Получить список всех чатов для пользователя
  static Future<List<EmployeeChat>> getChats(String phone) async {
    try {
      Logger.debug('📥 Загрузка списка чатов для $phone...');

      final response = await http.get(
        Uri.parse('$_baseUrl?phone=$phone'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['chats'] != null) {
          final chats = (data['chats'] as List)
              .map((c) => EmployeeChat.fromJson(c))
              .toList();
          Logger.debug('✅ Загружено чатов: ${chats.length}');
          return chats;
        }
      }

      Logger.debug('⚠️ Ошибка загрузки чатов: ${response.statusCode}');
      return [];
    } catch (e) {
      Logger.error('Ошибка загрузки чатов', e);
      return [];
    }
  }

  /// Получить сообщения чата
  static Future<List<EmployeeChatMessage>> getMessages(
    String chatId, {
    String? phone,
    int limit = 50,
    String? before,
  }) async {
    try {
      Logger.debug('📥 Загрузка сообщений чата $chatId...');

      var url = '$_baseUrl/$chatId/messages?limit=$limit';
      if (phone != null) url += '&phone=$phone';
      if (before != null) url += '&before=$before';

      final response = await http.get(
        Uri.parse(url),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['messages'] != null) {
          final messages = (data['messages'] as List)
              .map((m) => EmployeeChatMessage.fromJson(m))
              .toList();
          Logger.debug('✅ Загружено сообщений: ${messages.length}');
          return messages;
        }
      }

      Logger.debug('⚠️ Ошибка загрузки сообщений: ${response.statusCode}');
      return [];
    } catch (e) {
      Logger.error('Ошибка загрузки сообщений', e);
      return [];
    }
  }

  /// Отправить сообщение
  static Future<EmployeeChatMessage?> sendMessage({
    required String chatId,
    required String senderPhone,
    required String senderName,
    String? text,
    String? imageUrl,
  }) async {
    try {
      Logger.debug('📤 Отправка сообщения в чат $chatId...');

      final response = await http.post(
        Uri.parse('$_baseUrl/$chatId/messages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'senderPhone': senderPhone,
          'senderName': senderName,
          'text': text ?? '',
          'imageUrl': imageUrl,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['message'] != null) {
          Logger.debug('✅ Сообщение отправлено');
          return EmployeeChatMessage.fromJson(data['message']);
        }
      }

      Logger.debug('⚠️ Ошибка отправки сообщения: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('Ошибка отправки сообщения', e);
      return null;
    }
  }

  /// Отметить чат как прочитанный
  static Future<bool> markAsRead(String chatId, String phone) async {
    try {
      Logger.debug('📝 Отметка чата $chatId как прочитанного...');

      final response = await http.post(
        Uri.parse('$_baseUrl/$chatId/read'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('✅ Чат отмечен как прочитанный');
          return true;
        }
      }

      Logger.debug('⚠️ Ошибка отметки прочтения: ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('Ошибка отметки прочтения', e);
      return false;
    }
  }

  /// Создать или получить приватный чат
  static Future<EmployeeChat?> getOrCreatePrivateChat(
    String phone1,
    String phone2,
  ) async {
    try {
      Logger.debug('📝 Создание приватного чата $phone1 - $phone2...');

      final response = await http.post(
        Uri.parse('$_baseUrl/private'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone1': phone1,
          'phone2': phone2,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['chat'] != null) {
          Logger.debug('✅ Приватный чат создан/получен');
          return EmployeeChat.fromJson(data['chat']);
        }
      }

      Logger.debug('⚠️ Ошибка создания приватного чата: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('Ошибка создания приватного чата', e);
      return null;
    }
  }

  /// Создать или получить чат магазина
  static Future<EmployeeChat?> getOrCreateShopChat(String shopAddress) async {
    try {
      Logger.debug('📝 Создание чата магазина $shopAddress...');

      final response = await http.post(
        Uri.parse('$_baseUrl/shop'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'shopAddress': shopAddress}),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['chat'] != null) {
          Logger.debug('✅ Чат магазина создан/получен');
          return EmployeeChat.fromJson(data['chat']);
        }
      }

      Logger.debug('⚠️ Ошибка создания чата магазина: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('Ошибка создания чата магазина', e);
      return null;
    }
  }

  /// Загрузить фото для сообщения
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
    try {
      Logger.debug('🗑️ Удаление сообщения $messageId из чата $chatId...');

      final response = await http.delete(
        Uri.parse('$_baseUrl/$chatId/messages/$messageId'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('✅ Сообщение удалено');
          return true;
        }
      }

      Logger.debug('⚠️ Ошибка удаления сообщения: ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('Ошибка удаления сообщения', e);
      return false;
    }
  }
}

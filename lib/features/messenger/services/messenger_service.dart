import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../models/contact_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class MessengerService {
  static const String _base = '/api/messenger';

  // ==================== CONVERSATIONS ====================

  static Future<List<Conversation>> getConversations(String phone, {int limit = 50, int offset = 0}) async {
    return await BaseHttpService.getList<Conversation>(
      endpoint: '$_base/conversations',
      fromJson: (json) => Conversation.fromJson(json),
      listKey: 'conversations',
      queryParams: {
        'phone': phone,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
      paginate: false,
    );
  }

  static Future<Conversation?> getOrCreatePrivateChat({
    required String phone1,
    required String phone2,
    String? name1,
    String? name2,
  }) async {
    return await BaseHttpService.post<Conversation>(
      endpoint: '$_base/conversations/private',
      fromJson: (json) => Conversation.fromJson(json),
      itemKey: 'conversation',
      body: {
        'phone1': phone1,
        'phone2': phone2,
        'name1': name1,
        'name2': name2,
      },
    );
  }

  static Future<Conversation?> createGroup({
    required String creatorPhone,
    required String creatorName,
    required String name,
    required List<Map<String, String>> participants,
  }) async {
    return await BaseHttpService.post<Conversation>(
      endpoint: '$_base/conversations/group',
      fromJson: (json) => Conversation.fromJson(json),
      itemKey: 'conversation',
      body: {
        'creatorPhone': creatorPhone,
        'creatorName': creatorName,
        'name': name,
        'participants': participants,
      },
    );
  }

  static Future<Conversation?> getConversation(String conversationId) async {
    return await BaseHttpService.get<Conversation>(
      endpoint: '$_base/conversations/$conversationId',
      fromJson: (json) => Conversation.fromJson(json),
      itemKey: 'conversation',
    );
  }

  static Future<bool> updateGroup(String conversationId, {required String phone, String? name, String? avatarUrl}) async {
    return await BaseHttpService.simplePut(
      endpoint: '$_base/conversations/$conversationId',
      body: {
        'phone': phone,
        if (name != null) 'name': name,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      },
    );
  }

  static Future<bool> deleteConversation(String conversationId, String phone) async {
    return await BaseHttpService.delete(
      endpoint: '$_base/conversations/$conversationId?phone=$phone',
    );
  }

  // ==================== PARTICIPANTS ====================

  static Future<bool> addParticipants(String conversationId, {required String requesterPhone, required List<Map<String, String>> phones}) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/conversations/$conversationId/participants',
      body: {
        'requesterPhone': requesterPhone,
        'phones': phones,
      },
    );
    return result?['success'] == true;
  }

  static Future<bool> removeParticipant(String conversationId, String targetPhone, {required String requesterPhone}) async {
    return await BaseHttpService.delete(
      endpoint: '$_base/conversations/$conversationId/participants/$targetPhone?requesterPhone=$requesterPhone',
    );
  }

  static Future<bool> leaveGroup(String conversationId, String phone) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/conversations/$conversationId/leave',
      body: {'phone': phone},
    );
    return result?['success'] == true;
  }

  // ==================== MESSAGES ====================

  static Future<List<MessengerMessage>> getMessages(String conversationId, {int limit = 50, String? before}) async {
    final queryParams = <String, String>{'limit': limit.toString()};
    if (before != null) queryParams['before'] = before;

    return await BaseHttpService.getList<MessengerMessage>(
      endpoint: '$_base/conversations/$conversationId/messages',
      fromJson: (json) => MessengerMessage.fromJson(json),
      listKey: 'messages',
      queryParams: queryParams,
      paginate: false,
    );
  }

  static Future<MessengerMessage?> sendMessage({
    required String conversationId,
    required String senderPhone,
    required String senderName,
    MessageType type = MessageType.text,
    String? content,
    String? mediaUrl,
    int? voiceDuration,
    String? replyToId,
  }) async {
    return await BaseHttpService.post<MessengerMessage>(
      endpoint: '$_base/conversations/$conversationId/messages',
      fromJson: (json) => MessengerMessage.fromJson(json),
      itemKey: 'message',
      body: {
        'senderPhone': senderPhone,
        'senderName': senderName,
        'type': type == MessageType.text ? 'text'
            : type == MessageType.image ? 'image'
            : type == MessageType.video ? 'video'
            : type == MessageType.voice ? 'voice'
            : type == MessageType.emoji ? 'emoji'
            : 'text',
        if (content != null) 'content': content,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (voiceDuration != null) 'voiceDuration': voiceDuration,
        if (replyToId != null) 'replyToId': replyToId,
      },
    );
  }

  static Future<bool> deleteMessage(String conversationId, String messageId, String phone) async {
    return await BaseHttpService.delete(
      endpoint: '$_base/conversations/$conversationId/messages/$messageId?phone=$phone',
    );
  }

  static Future<List<MessengerMessage>> searchMessages(String conversationId, String query, {int limit = 50}) async {
    return await BaseHttpService.getList<MessengerMessage>(
      endpoint: '$_base/conversations/$conversationId/messages/search',
      fromJson: (json) => MessengerMessage.fromJson(json),
      listKey: 'messages',
      queryParams: {'query': query, 'limit': limit.toString()},
      paginate: false,
    );
  }

  // ==================== READ RECEIPTS ====================

  static Future<bool> markAsRead(String conversationId, String phone) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/conversations/$conversationId/read',
      body: {'phone': phone},
    );
    return result?['success'] == true;
  }

  // ==================== REACTIONS ====================

  static Future<bool> addReaction(String conversationId, String messageId, {required String phone, required String reaction}) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/conversations/$conversationId/messages/$messageId/reactions',
      body: {'phone': phone, 'reaction': reaction},
    );
    return result?['success'] == true;
  }

  static Future<bool> removeReaction(String conversationId, String messageId, {required String phone, required String reaction}) async {
    return await BaseHttpService.delete(
      endpoint: '$_base/conversations/$conversationId/messages/$messageId/reactions?phone=$phone&reaction=$reaction',
    );
  }

  // ==================== MEDIA UPLOAD ====================

  static Future<String?> uploadMedia(File file) async {
    try {
      final uri = Uri.parse('${ApiConstants.serverUrl}$_base/upload');
      final request = http.MultipartRequest('POST', uri);

      request.headers.addAll(ApiConstants.jsonHeaders);
      request.headers.remove('Content-Type'); // multipart sets its own

      final ext = file.path.split('.').last.toLowerCase();
      String mimeType = 'application/octet-stream';
      if (['jpg', 'jpeg'].contains(ext)) mimeType = 'image/jpeg';
      if (ext == 'png') mimeType = 'image/png';
      if (ext == 'mp4') mimeType = 'video/mp4';
      if (['m4a', 'aac'].contains(ext)) mimeType = 'audio/m4a';
      if (ext == 'ogg') mimeType = 'audio/ogg';

      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType.parse(mimeType),
      ));

      final streamedResponse = await request.send().timeout(ApiConstants.uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['url'] as String?;
        }
      }
      Logger.error('Upload failed: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('Upload error: $e');
      return null;
    }
  }

  // ==================== CONTACTS ====================

  static Future<List<MessengerContact>> searchContacts(String query) async {
    return await BaseHttpService.getList<MessengerContact>(
      endpoint: '$_base/contacts/search',
      fromJson: (json) => MessengerContact.fromJson(json),
      listKey: 'contacts',
      queryParams: {'query': query},
      paginate: false,
    );
  }

  static Future<List<MessengerContact>> matchPhones(List<String> phones) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/contacts/by-phones',
      body: {'phones': phones},
    );
    if (result != null && result['contacts'] is List) {
      return (result['contacts'] as List)
          .map((json) => MessengerContact.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // ==================== UNREAD COUNT ====================

  static Future<int> getUnreadCount(String phone) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_base/unread?phone=$phone',
      );
      if (result != null && result['success'] == true) {
        return (result['unreadCount'] as num?)?.toInt() ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }
}

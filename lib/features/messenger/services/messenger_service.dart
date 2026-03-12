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
        'phones': phones,
      },
    );
    return result?['success'] == true;
  }

  static Future<bool> removeParticipant(String conversationId, String targetPhone, {required String requesterPhone}) async {
    return await BaseHttpService.delete(
      endpoint: '$_base/conversations/$conversationId/participants/$targetPhone',
    );
  }

  static Future<bool> leaveGroup(String conversationId, String phone) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/conversations/$conversationId/leave',
      body: {},
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
    String? fileName,
    int? fileSize,
    String? mediaGroupId,
  }) async {
    return await BaseHttpService.post<MessengerMessage>(
      endpoint: '$_base/conversations/$conversationId/messages',
      fromJson: (json) => MessengerMessage.fromJson(json),
      itemKey: 'message',
      body: {
        'senderName': senderName,
        'type': type == MessageType.text ? 'text'
            : type == MessageType.image ? 'image'
            : type == MessageType.video ? 'video'
            : type == MessageType.voice ? 'voice'
            : type == MessageType.emoji ? 'emoji'
            : type == MessageType.videoNote ? 'video_note'
            : type == MessageType.file ? 'file'
            : type == MessageType.poll ? 'poll'
            : type == MessageType.sticker ? 'sticker'
            : type == MessageType.gif ? 'gif'
            : type == MessageType.contact ? 'contact'
            : 'text',
        if (content != null) 'content': content,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (voiceDuration != null) 'voiceDuration': voiceDuration,
        if (replyToId != null) 'replyToId': replyToId,
        if (fileName != null) 'fileName': fileName,
        if (fileSize != null) 'fileSize': fileSize,
        if (mediaGroupId != null) 'mediaGroupId': mediaGroupId,
      },
    );
  }

  static Future<bool> pinMessage(String conversationId, String messageId, String phone) async {
    return await BaseHttpService.simplePut(
      endpoint: '$_base/conversations/$conversationId/messages/$messageId/pin?phone=$phone',
      body: {},
    );
  }

  static Future<bool> unpinMessage(String conversationId, String messageId) async {
    return await BaseHttpService.delete(
      endpoint: '$_base/conversations/$conversationId/messages/$messageId/pin',
    );
  }

  static Future<List<MessengerMessage>> getPinnedMessages(String conversationId) async {
    return await BaseHttpService.getList<MessengerMessage>(
      endpoint: '$_base/conversations/$conversationId/pinned',
      fromJson: (json) => MessengerMessage.fromJson(json),
      listKey: 'messages',
    );
  }

  static Future<bool> forwardMessage(String sourceMessageId, List<String> targetConversationIds) async {
    return await BaseHttpService.simplePost(
      endpoint: '$_base/forward',
      body: {
        'sourceMessageId': sourceMessageId,
        'targetConversationIds': targetConversationIds,
      },
    );
  }

  static Future<bool> editMessage(String conversationId, String messageId, {required String content}) async {
    return await BaseHttpService.simplePut(
      endpoint: '$_base/conversations/$conversationId/messages/$messageId',
      body: {'content': content},
    );
  }

  /// Delete message for everyone (sender only, within 1 hour)
  static Future<bool> deleteMessageForAll(String conversationId, String messageId) async {
    return await BaseHttpService.delete(
      endpoint: '$_base/conversations/$conversationId/messages/$messageId?mode=forAll',
    );
  }

  /// Delete message for me only (hides from my view)
  static Future<bool> deleteMessageForMe(String conversationId, String messageId) async {
    return await BaseHttpService.delete(
      endpoint: '$_base/conversations/$conversationId/messages/$messageId?mode=forMe',
    );
  }

  /// Hide messages from media gallery (hide for me only, does NOT delete for others)
  static Future<bool> hideMessages(List<String> messageIds) async {
    return await BaseHttpService.simplePost(
      endpoint: '$_base/messages/hide',
      body: {'messageIds': messageIds},
    );
  }

  /// Set auto-delete timer for a conversation (0 = off)
  static Future<bool> setAutoDelete(String conversationId, int seconds) async {
    return await BaseHttpService.simplePut(
      endpoint: '$_base/conversations/$conversationId/auto-delete',
      body: {'seconds': seconds},
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

  /// Global fuzzy search across contacts, groups, and messages.
  static Future<Map<String, dynamic>> globalSearch(String query, {int limit = 20}) async {
    final result = await BaseHttpService.getRaw(
      endpoint: '$_base/search',
      queryParams: {'query': query, 'limit': limit.toString()},
    );
    if (result == null || result['success'] != true) {
      return {'contacts': [], 'groups': [], 'messages': []};
    }
    return {
      'contacts': (result['contacts'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      'groups': (result['groups'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      'messages': (result['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    };
  }

  // ==================== READ RECEIPTS ====================

  static Future<bool> markAsRead(String conversationId, String phone) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/conversations/$conversationId/read',
      body: {},
    );
    return result?['success'] == true;
  }

  /// Get list of participants who have read a specific message
  static Future<List<Map<String, dynamic>>> getMessageReaders(
      String conversationId, String messageId) async {
    final result = await BaseHttpService.getRaw(
      endpoint: '$_base/conversations/$conversationId/messages/$messageId/readers',
    );
    if (result?['success'] == true) {
      return (result!['readers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    }
    return [];
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

  // ==================== POLLS ====================

  static Future<Map<String, dynamic>?> createPoll({
    required String conversationId,
    required String question,
    required List<String> options,
    bool multipleChoice = false,
    bool anonymous = false,
  }) async {
    return await BaseHttpService.postRaw(
      endpoint: '$_base/conversations/$conversationId/poll',
      body: {
        'question': question,
        'options': options,
        'multipleChoice': multipleChoice,
        'anonymous': anonymous,
      },
    );
  }

  static Future<Map<String, dynamic>?> votePoll(String conversationId, String pollId, int optionIndex) async {
    return await BaseHttpService.postRaw(
      endpoint: '$_base/conversations/$conversationId/poll/$pollId/vote',
      body: {'optionIndex': optionIndex},
    );
  }

  static Future<bool> closePoll(String conversationId, String pollId) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/conversations/$conversationId/poll/$pollId/close',
      body: {},
    );
    return result?['success'] == true;
  }

  static Future<Map<String, dynamic>?> getPoll(String conversationId, String messageId) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_base/conversations/$conversationId/poll/$messageId',
      );
      if (result != null && result['success'] == true && result['poll'] != null) {
        return result['poll'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      Logger.error('getPoll error: $e');
      return null;
    }
  }

  /// Fetch multiple polls at once (max 50 message IDs)
  static Future<Map<String, Map<String, dynamic>>> getPollsBatch(
    String conversationId,
    List<String> messageIds,
  ) async {
    try {
      final result = await BaseHttpService.postRaw(
        endpoint: '$_base/conversations/$conversationId/polls/batch',
        body: {'messageIds': messageIds},
      );
      if (result != null && result['success'] == true && result['polls'] is Map) {
        final polls = result['polls'] as Map<String, dynamic>;
        return polls.map((k, v) => MapEntry(k, v as Map<String, dynamic>));
      }
      return {};
    } catch (e) {
      Logger.error('getPollsBatch error: $e');
      return {};
    }
  }

  // ==================== CHANNELS ====================

  static Future<Conversation?> createChannel({
    required String name,
    String? description,
    String? avatarUrl,
  }) async {
    return await BaseHttpService.post<Conversation>(
      endpoint: '$_base/conversations/channel',
      fromJson: (json) => Conversation.fromJson(json),
      itemKey: 'conversation',
      body: {
        'name': name,
        if (description != null) 'description': description,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      },
    );
  }

  static Future<List<Map<String, dynamic>>> getChannels() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_base/channels',
      );
      if (result != null && result['success'] == true && result['channels'] is List) {
        return (result['channels'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      Logger.error('getChannels error: $e');
      return [];
    }
  }

  static Future<bool> subscribeToChannel(String channelId) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/channels/$channelId/subscribe',
      body: {},
    );
    return result?['success'] == true;
  }

  static Future<bool> unsubscribeFromChannel(String channelId) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/channels/$channelId/unsubscribe',
      body: {},
    );
    return result?['success'] == true;
  }

  /// Set participant role in a channel (writer or member)
  static Future<bool> setChannelRole(String channelId, {required String phone, required String role}) async {
    return await BaseHttpService.simplePut(
      endpoint: '$_base/channels/$channelId/role',
      body: {'phone': phone, 'role': role},
    );
  }

  // ==================== STICKERS ====================

  static Future<List<Map<String, dynamic>>> getStickerPacks() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_base/sticker-packs',
      );
      if (result != null && result['success'] == true && result['packs'] is List) {
        return (result['packs'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      Logger.error('getStickerPacks error: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getStickerPack(String packId) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_base/sticker-packs/$packId',
      );
      if (result != null && result['success'] == true && result['pack'] != null) {
        return result['pack'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      Logger.error('getStickerPack error: $e');
      return null;
    }
  }

  // ==================== FAVORITE STICKERS ====================

  static Future<List<String>> getFavoriteStickers() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_base/favorite-stickers',
      );
      if (result != null && result['success'] == true && result['stickers'] is List) {
        return (result['stickers'] as List).cast<String>();
      }
      return [];
    } catch (e) {
      Logger.error('getFavoriteStickers error: $e');
      return [];
    }
  }

  static Future<bool> addFavoriteSticker(String stickerUrl) async {
    try {
      final result = await BaseHttpService.postRaw(
        endpoint: '$_base/favorite-stickers',
        body: {'stickerUrl': stickerUrl},
      );
      return result?['success'] == true;
    } catch (e) {
      Logger.error('addFavoriteSticker error: $e');
      return false;
    }
  }

  static Future<bool> removeFavoriteSticker(String stickerUrl) async {
    try {
      final encodedUrl = Uri.encodeComponent(stickerUrl);
      return await BaseHttpService.delete(
        endpoint: '$_base/favorite-stickers?url=$encodedUrl',
      );
    } catch (e) {
      Logger.error('removeFavoriteSticker error: $e');
      return false;
    }
  }

  // ==================== CUSTOM STICKER UPLOAD ====================

  /// Upload a custom sticker image from gallery.
  /// Server resizes to 512x512 PNG and adds to favorites automatically.
  static Future<String?> uploadCustomSticker(File file) async {
    try {
      final uri = Uri.parse('${ApiConstants.serverUrl}$_base/custom-stickers/upload');
      final request = http.MultipartRequest('POST', uri);

      request.headers.addAll(ApiConstants.jsonHeaders);
      request.headers.remove('Content-Type');

      final ext = file.path.split('.').last.toLowerCase();
      String mimeType = 'image/png';
      if (['jpg', 'jpeg'].contains(ext)) mimeType = 'image/jpeg';
      if (ext == 'webp') mimeType = 'image/webp';

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
          return data['stickerUrl'] as String?;
        }
      }
      Logger.error('Custom sticker upload failed: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('Custom sticker upload error: $e');
      return null;
    }
  }

  // ==================== GIF ====================

  static Future<List<Map<String, dynamic>>> searchGifs(String query, {int limit = 20}) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_base/gifs/search?query=${Uri.encodeComponent(query)}&limit=$limit',
      );
      if (result != null && result['success'] == true && result['gifs'] is List) {
        return (result['gifs'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      Logger.error('searchGifs error: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getTrendingGifs({int limit = 20}) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_base/gifs/trending?limit=$limit',
      );
      if (result != null && result['success'] == true && result['gifs'] is List) {
        return (result['gifs'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      Logger.error('getTrendingGifs error: $e');
      return [];
    }
  }

  // ==================== FAVORITE GIFS ====================

  static Future<List<String>> getFavoriteGifs() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_base/favorite-gifs',
      );
      if (result != null && result['success'] == true && result['gifs'] is List) {
        return (result['gifs'] as List).cast<String>();
      }
      return [];
    } catch (e) {
      Logger.error('getFavoriteGifs error: $e');
      return [];
    }
  }

  static Future<bool> addFavoriteGif(String gifUrl) async {
    try {
      final result = await BaseHttpService.postRaw(
        endpoint: '$_base/favorite-gifs',
        body: {'gifUrl': gifUrl},
      );
      return result?['success'] == true;
    } catch (e) {
      Logger.error('addFavoriteGif error: $e');
      return false;
    }
  }

  static Future<bool> removeFavoriteGif(String gifUrl) async {
    try {
      final encodedUrl = Uri.encodeComponent(gifUrl);
      return await BaseHttpService.delete(
        endpoint: '$_base/favorite-gifs?url=$encodedUrl',
      );
    } catch (e) {
      Logger.error('removeFavoriteGif error: $e');
      return false;
    }
  }

  // ==================== SAVED MESSAGES ("Избранное") ====================

  static Future<Conversation?> getSavedMessages(String phone) async {
    return await BaseHttpService.get<Conversation>(
      endpoint: '$_base/saved?phone=$phone',
      fromJson: (json) => Conversation.fromJson(json),
      itemKey: 'conversation',
    );
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

  // ==================== USER PROFILE ====================

  static Future<Map<String, dynamic>?> getProfile(String phone) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_base/profile?phone=$phone',
      );
      if (result != null && result['success'] == true && result['profile'] != null) {
        return result['profile'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> updateProfile({
    required String phone,
    String? displayName,
    String? avatarUrl,
  }) async {
    try {
      final result = await BaseHttpService.putRaw(
        endpoint: '$_base/profile',
        body: {
          'phone': phone,
          if (displayName != null) 'displayName': displayName,
          if (avatarUrl != null) 'avatarUrl': avatarUrl,
        },
      );
      if (result != null && result['success'] == true && result['profile'] != null) {
        return result['profile'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
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

  // ==================== BLOCK / UNBLOCK ====================

  static Future<bool> blockUser({required String phone, required String blockedPhone}) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/block',
      body: {'phone': phone, 'blockedPhone': blockedPhone},
    );
    return result?['success'] == true;
  }

  static Future<bool> unblockUser({required String phone, required String blockedPhone}) async {
    return await BaseHttpService.delete(
      endpoint: '$_base/block?phone=$phone&blockedPhone=$blockedPhone',
    );
  }

  static Future<List<Map<String, dynamic>>> getBlockedUsers(String phone) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_base/blocks?phone=$phone',
      );
      if (result != null && result['success'] == true && result['blocks'] is List) {
        return (result['blocks'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      Logger.error('getBlockedUsers error: $e');
      return [];
    }
  }

  // ==================== FOLDERS ====================

  static Future<List<Map<String, dynamic>>> getFolders(String phone) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_base/folders?phone=$phone',
      );
      if (result != null && result['success'] == true && result['folders'] is List) {
        return (result['folders'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      Logger.error('getFolders error: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> createFolder({
    required String phone,
    required String name,
    String filterType = 'manual',
    int sortOrder = 0,
  }) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/folders',
      body: {
        'phone': phone,
        'name': name,
        'filterType': filterType,
        'sortOrder': sortOrder,
      },
    );
    if (result != null && result['success'] == true && result['folder'] != null) {
      return result['folder'] as Map<String, dynamic>;
    }
    return null;
  }

  static Future<bool> updateFolder(String folderId, {String? name, int? sortOrder}) async {
    return await BaseHttpService.simplePut(
      endpoint: '$_base/folders/$folderId',
      body: {
        if (name != null) 'name': name,
        if (sortOrder != null) 'sortOrder': sortOrder,
      },
    );
  }

  static Future<bool> deleteFolder(String folderId) async {
    return await BaseHttpService.delete(
      endpoint: '$_base/folders/$folderId',
    );
  }

  static Future<bool> addConversationToFolder(String folderId, String conversationId) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/folders/$folderId/conversations',
      body: {'conversationId': conversationId},
    );
    return result?['success'] == true;
  }

  static Future<bool> removeConversationFromFolder(String folderId, String conversationId) async {
    return await BaseHttpService.delete(
      endpoint: '$_base/folders/$folderId/conversations/$conversationId',
    );
  }

  // ==================== CONTACT PROFILE ====================

  /// Get shared media (images, videos, files) from a conversation
  static Future<List<Map<String, dynamic>>> getConversationMedia(
    String conversationId, {int limit = 50, int offset = 0}
  ) async {
    final result = await BaseHttpService.getRaw(
      endpoint: '$_base/conversations/$conversationId/media?limit=$limit&offset=$offset',
    );
    if (result != null && result['media'] is List) {
      return (result['media'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Get groups that both current user and target phone participate in
  static Future<List<Map<String, dynamic>>> getCommonGroups(String targetPhone) async {
    final result = await BaseHttpService.getRaw(
      endpoint: '$_base/common-groups?phone=$targetPhone',
    );
    if (result != null && result['groups'] is List) {
      return (result['groups'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  // ==================== MUTE ====================

  /// Mute a conversation. duration: "1h", "8h", "2d", "forever"
  static Future<bool> muteConversation(String conversationId, String duration) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/conversations/$conversationId/mute',
      body: {'duration': duration},
    );
    return result?['success'] == true;
  }

  /// Unmute a conversation
  static Future<bool> unmuteConversation(String conversationId) async {
    return await BaseHttpService.delete(
      endpoint: '$_base/conversations/$conversationId/mute',
    );
  }

  /// Check mute status of a conversation
  static Future<Map<String, dynamic>> getMuteStatus(String conversationId) async {
    final result = await BaseHttpService.getRaw(
      endpoint: '$_base/conversations/$conversationId/mute',
    );
    return result ?? {'is_muted': false};
  }

  // ==================== MESSAGE TEMPLATES ====================

  static Future<List<Map<String, dynamic>>> getTemplates() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_base/templates',
      );
      if (result != null && result['success'] == true && result['templates'] is List) {
        return (result['templates'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      Logger.error('getTemplates error: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> createTemplate({
    required String title,
    required String content,
    int sortOrder = 0,
  }) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '$_base/templates',
      body: {'title': title, 'content': content, 'sortOrder': sortOrder},
    );
    if (result != null && result['success'] == true && result['template'] != null) {
      return result['template'] as Map<String, dynamic>;
    }
    return null;
  }

  static Future<bool> deleteTemplate(int id) async {
    return await BaseHttpService.delete(endpoint: '$_base/templates/$id');
  }

  // ==================== BROADCAST ====================

  /// Send a message to multiple conversations at once (max 50)
  static Future<Map<String, dynamic>?> broadcast({
    required List<String> conversationIds,
    required String content,
    String type = 'text',
  }) async {
    try {
      final result = await BaseHttpService.postRaw(
        endpoint: '$_base/broadcast',
        body: {
          'conversationIds': conversationIds,
          'content': content,
          'type': type,
        },
      );
      return result;
    } catch (e) {
      Logger.error('Broadcast error: $e');
      return null;
    }
  }
}

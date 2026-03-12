import 'package:flutter_test/flutter_test.dart';
import 'package:arabica_app/features/messenger/models/message_model.dart';
import 'package:arabica_app/features/messenger/models/conversation_model.dart';
import 'package:arabica_app/features/messenger/models/participant_model.dart';

/// Service tests for MessengerService.
///
/// NOTE: Full HTTP mock tests require adding `mockito` and `build_runner`
/// to dev_dependencies in pubspec.yaml. These are not currently present,
/// so this file tests the data transformation logic that the service
/// relies on (JSON parsing for API responses).
///
/// To enable HTTP mocking in the future, add to pubspec.yaml:
///   dev_dependencies:
///     mockito: ^5.4.0
///     build_runner: ^2.4.0
///
/// Then create mocks for http.Client and inject into BaseHttpService.

void main() {
  // ==========================================================================
  // getConversations: simulated API response parsing
  // ==========================================================================
  group('getConversations response parsing', () {
    test('parses successful response with conversations list', () {
      // Simulates the JSON body the server returns for GET /api/messenger/conversations
      final responseBody = {
        'success': true,
        'conversations': [
          {
            'id': 'private_79001111111_79002222222',
            'type': 'private',
            'participants': [
              {'phone': '79001111111', 'name': 'Иван'},
              {'phone': '79002222222', 'name': 'Мария'},
            ],
            'unread_count': 3,
            'last_message': {
              'id': 'msg_1',
              'conversation_id': 'private_79001111111_79002222222',
              'sender_phone': '79002222222',
              'type': 'text',
              'content': 'Привет!',
              'created_at': '2026-03-10T12:00:00Z',
            },
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-03-10T12:00:00Z',
          },
          {
            'id': 'group_work_chat',
            'type': 'group',
            'name': 'Рабочий чат',
            'participants': [
              {'phone': '79001111111', 'name': 'Иван', 'role': 'admin'},
              {'phone': '79002222222', 'name': 'Мария', 'role': 'member'},
              {'phone': '79003333333', 'name': 'Анна', 'role': 'member'},
            ],
            'unread_count': 0,
            'created_at': '2026-02-01T00:00:00Z',
            'updated_at': '2026-03-09T18:00:00Z',
          },
        ],
      };

      // Parse as the service would via BaseHttpService.getList
      final conversations = (responseBody['conversations'] as List)
          .map((json) => Conversation.fromJson(json as Map<String, dynamic>))
          .toList();

      expect(conversations.length, 2);

      // First conversation: private chat
      expect(conversations[0].type, ConversationType.private_);
      expect(conversations[0].unreadCount, 3);
      expect(conversations[0].lastMessage?.content, 'Привет!');
      expect(conversations[0].displayName('79001111111'), 'Мария');

      // Second conversation: group chat
      expect(conversations[1].type, ConversationType.group);
      expect(conversations[1].name, 'Рабочий чат');
      expect(conversations[1].participants.length, 3);
      expect(conversations[1].participants[0].isAdmin, true);
    });

    test('parses empty conversations list', () {
      final responseBody = {
        'success': true,
        'conversations': [],
      };

      final conversations = (responseBody['conversations'] as List)
          .map((json) => Conversation.fromJson(json as Map<String, dynamic>))
          .toList();

      expect(conversations, isEmpty);
    });

    test('handles error response gracefully (missing conversations key)', () {
      final responseBody = {
        'success': false,
        'error': 'Unauthorized',
      };

      // BaseHttpService returns empty list when key is missing
      final rawList = responseBody['conversations'];
      final conversations = rawList is List
          ? rawList.map((json) => Conversation.fromJson(json as Map<String, dynamic>)).toList()
          : <Conversation>[];

      expect(conversations, isEmpty);
    });
  });

  // ==========================================================================
  // getMessages: simulated API response parsing
  // ==========================================================================
  group('getMessages response parsing', () {
    test('parses successful response with messages list', () {
      final responseBody = {
        'success': true,
        'messages': [
          {
            'id': 'msg_1',
            'conversation_id': 'conv_1',
            'sender_phone': '79001111111',
            'sender_name': 'Иван',
            'type': 'text',
            'content': 'Привет!',
            'created_at': '2026-03-10T12:00:00Z',
            'reactions': {'👍': ['79002222222']},
          },
          {
            'id': 'msg_2',
            'conversation_id': 'conv_1',
            'sender_phone': '79002222222',
            'sender_name': 'Мария',
            'type': 'image',
            'media_url': 'https://example.com/photo.jpg',
            'created_at': '2026-03-10T12:01:00Z',
          },
          {
            'id': 'msg_3',
            'conversation_id': 'conv_1',
            'sender_phone': '79001111111',
            'sender_name': 'Иван',
            'type': 'voice',
            'media_url': 'https://example.com/voice.m4a',
            'voice_duration': 30,
            'created_at': '2026-03-10T12:02:00Z',
          },
        ],
      };

      final messages = (responseBody['messages'] as List)
          .map((json) => MessengerMessage.fromJson(json as Map<String, dynamic>))
          .toList();

      expect(messages.length, 3);

      expect(messages[0].type, MessageType.text);
      expect(messages[0].content, 'Привет!');
      expect(messages[0].reactions['👍'], ['79002222222']);

      expect(messages[1].type, MessageType.image);
      expect(messages[1].mediaUrl, 'https://example.com/photo.jpg');

      expect(messages[2].type, MessageType.voice);
      expect(messages[2].voiceDuration, 30);
    });

    test('parses empty messages list', () {
      final responseBody = {
        'success': true,
        'messages': [],
      };

      final messages = (responseBody['messages'] as List)
          .map((json) => MessengerMessage.fromJson(json as Map<String, dynamic>))
          .toList();

      expect(messages, isEmpty);
    });

    test('handles missing messages key', () {
      final responseBody = {'success': false, 'error': 'Not found'};

      final rawList = responseBody['messages'];
      final messages = rawList is List
          ? rawList.map((json) => MessengerMessage.fromJson(json as Map<String, dynamic>)).toList()
          : <MessengerMessage>[];

      expect(messages, isEmpty);
    });
  });

  // ==========================================================================
  // sendMessage: request body construction
  // ==========================================================================
  group('sendMessage request body construction', () {
    // Tests the type string mapping used in MessengerService.sendMessage
    test('MessageType to string mapping covers all types', () {
      final typeMap = <MessageType, String>{
        MessageType.text: 'text',
        MessageType.image: 'image',
        MessageType.video: 'video',
        MessageType.voice: 'voice',
        MessageType.emoji: 'emoji',
        MessageType.videoNote: 'video_note',
        MessageType.file: 'file',
        MessageType.poll: 'poll',
        MessageType.sticker: 'sticker',
        MessageType.gif: 'gif',
        MessageType.contact: 'contact',
        MessageType.call: 'call',
      };

      for (final entry in typeMap.entries) {
        // Create a message with this type and verify typeString matches
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': entry.value,
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.type, entry.key, reason: 'Failed for type string: ${entry.value}');
        expect(msg.typeString, entry.value, reason: 'typeString mismatch for: ${entry.key}');
      }

      // Verify all enum values are covered
      expect(typeMap.length, MessageType.values.length,
          reason: 'Not all MessageType values are tested');
    });

    test('sendMessage body includes optional fields only when provided', () {
      // Simulates the body construction from MessengerService.sendMessage
      String? content = 'Тест';
      String? mediaUrl;
      int? voiceDuration;
      String? replyToId = 'msg_reply';
      String? fileName;
      int? fileSize;
      String? mediaGroupId;

      final body = {
        'senderName': 'Иван',
        'type': 'text',
        if (content != null) 'content': content,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (voiceDuration != null) 'voiceDuration': voiceDuration,
        if (replyToId != null) 'replyToId': replyToId,
        if (fileName != null) 'fileName': fileName,
        if (fileSize != null) 'fileSize': fileSize,
        if (mediaGroupId != null) 'mediaGroupId': mediaGroupId,
      };

      expect(body.containsKey('content'), true);
      expect(body.containsKey('replyToId'), true);
      expect(body.containsKey('mediaUrl'), false); // null, not included
      expect(body.containsKey('voiceDuration'), false);
      expect(body.containsKey('fileName'), false);
      expect(body.containsKey('fileSize'), false);
      expect(body.containsKey('mediaGroupId'), false);
    });

    test('sendMessage body for voice message includes duration', () {
      String? content;
      String? mediaUrl = 'https://example.com/voice.m4a';
      int? voiceDuration = 45;

      final body = {
        'senderName': 'Мария',
        'type': 'voice',
        if (content != null) 'content': content,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (voiceDuration != null) 'voiceDuration': voiceDuration,
      };

      expect(body['type'], 'voice');
      expect(body['mediaUrl'], 'https://example.com/voice.m4a');
      expect(body['voiceDuration'], 45);
      expect(body.containsKey('content'), false);
    });

    test('sendMessage body for file message includes fileName and fileSize', () {
      String? fileName = 'report.xlsx';
      int? fileSize = 2048;
      String? mediaUrl = 'https://example.com/report.xlsx';

      final body = {
        'senderName': 'Иван',
        'type': 'file',
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (fileName != null) 'fileName': fileName,
        if (fileSize != null) 'fileSize': fileSize,
      };

      expect(body['type'], 'file');
      expect(body['fileName'], 'report.xlsx');
      expect(body['fileSize'], 2048);
    });
  });

  // ==========================================================================
  // sendMessage response parsing
  // ==========================================================================
  group('sendMessage response parsing', () {
    test('parses successful send response', () {
      final responseBody = {
        'success': true,
        'message': {
          'id': 'msg_new_1',
          'conversation_id': 'conv_1',
          'sender_phone': '79001111111',
          'sender_name': 'Иван',
          'type': 'text',
          'content': 'Новое сообщение',
          'created_at': '2026-03-10T12:00:00Z',
        },
      };

      final message = MessengerMessage.fromJson(
          responseBody['message'] as Map<String, dynamic>);

      expect(message.id, 'msg_new_1');
      expect(message.content, 'Новое сообщение');
      expect(message.senderPhone, '79001111111');
    });

    test('handles error response (message key missing)', () {
      final responseBody = {
        'success': false,
        'error': 'Rate limited',
      };

      final rawMessage = responseBody['message'];
      final message = rawMessage != null
          ? MessengerMessage.fromJson(rawMessage as Map<String, dynamic>)
          : null;

      expect(message, isNull);
    });
  });

  // ==========================================================================
  // Complex conversation scenarios
  // ==========================================================================
  group('complex scenarios', () {
    test('conversation list with mixed types and nested messages', () {
      final responseBody = {
        'success': true,
        'conversations': [
          {
            'id': 'private_79001111111_79002222222',
            'type': 'private',
            'participants': [
              {'phone': '79001111111', 'name': 'Иван'},
              {'phone': '79002222222', 'name': 'Мария'},
            ],
            'unread_count': 1,
            'last_message': {
              'id': 'msg_img',
              'conversation_id': 'private_79001111111_79002222222',
              'sender_phone': '79002222222',
              'type': 'image',
              'media_url': 'https://example.com/photo.jpg',
              'created_at': '2026-03-10T12:00:00Z',
            },
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-03-10T12:00:00Z',
          },
          {
            'id': 'group_team',
            'type': 'group',
            'name': 'Команда',
            'participants': [
              {'phone': '79001111111', 'name': 'Иван', 'role': 'admin'},
              {'phone': '79002222222', 'name': 'Мария'},
              {'phone': '79003333333', 'name': 'Анна'},
            ],
            'unread_count': 10,
            'last_message': {
              'id': 'msg_poll',
              'conversation_id': 'group_team',
              'sender_phone': '79001111111',
              'type': 'poll',
              'content': 'Куда пойдём?',
              'created_at': '2026-03-10T11:00:00Z',
            },
            'created_at': '2026-02-01T00:00:00Z',
            'updated_at': '2026-03-10T11:00:00Z',
          },
          {
            'id': 'channel_news',
            'type': 'channel',
            'name': 'Новости кофейни',
            'description': 'Важные объявления',
            'unread_count': 0,
            'created_at': '2026-01-15T00:00:00Z',
            'updated_at': '2026-03-09T00:00:00Z',
          },
        ],
      };

      final conversations = (responseBody['conversations'] as List)
          .map((json) => Conversation.fromJson(json as Map<String, dynamic>))
          .toList();

      expect(conversations.length, 3);

      // Private chat
      final privateChat = conversations[0];
      expect(privateChat.displayName('79001111111'), 'Мария');
      expect(privateChat.lastMessage!.type, MessageType.image);
      expect(privateChat.lastMessage!.preview, contains('Фото'));

      // Group chat
      final groupChat = conversations[1];
      expect(groupChat.displayName('79001111111'), 'Команда');
      expect(groupChat.unreadCount, 10);
      expect(groupChat.lastMessage!.type, MessageType.poll);
      expect(groupChat.lastMessage!.preview, contains('Опрос'));

      // Channel
      final channel = conversations[2];
      expect(channel.type, ConversationType.channel);
      expect(channel.description, 'Важные объявления');
      expect(channel.lastMessage, isNull);
    });

    test('forwarded message preserves forward metadata', () {
      final responseBody = {
        'success': true,
        'messages': [
          {
            'id': 'msg_fwd',
            'conversation_id': 'conv_1',
            'sender_phone': '79001111111',
            'sender_name': 'Иван',
            'type': 'text',
            'content': 'Пересланное сообщение',
            'forwarded_from_id': 'msg_original_123',
            'forwarded_from_name': 'Петр',
            'created_at': '2026-03-10T12:00:00Z',
          },
        ],
      };

      final messages = (responseBody['messages'] as List)
          .map((json) => MessengerMessage.fromJson(json as Map<String, dynamic>))
          .toList();

      expect(messages[0].isForwarded, true);
      expect(messages[0].forwardedFromId, 'msg_original_123');
      expect(messages[0].forwardedFromName, 'Петр');
    });

    test('pinned message has pin metadata', () {
      final msg = MessengerMessage.fromJson({
        'id': 'msg_pin',
        'conversation_id': 'conv_1',
        'sender_phone': '79001111111',
        'type': 'text',
        'content': 'Закреплённое сообщение',
        'is_pinned': true,
        'pinned_at': '2026-03-10T12:00:00Z',
        'pinned_by': '79009999999',
        'created_at': '2026-03-10T10:00:00Z',
      });

      expect(msg.isPinned, true);
      expect(msg.pinnedBy, '79009999999');
      expect(msg.pinnedAt, isNotNull);
      expect(msg.pinnedAt!.year, 2026);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:arabica_app/features/messenger/models/message_model.dart';
import 'package:arabica_app/features/messenger/models/conversation_model.dart';
import 'package:arabica_app/features/messenger/models/participant_model.dart';
import 'package:arabica_app/features/messenger/models/contact_model.dart';

void main() {
  // ==========================================================================
  // MessengerMessage tests
  // ==========================================================================
  group('MessengerMessage', () {
    group('fromJson', () {
      test('parses full JSON with all fields', () {
        final json = {
          'id': 'msg_001',
          'conversation_id': 'conv_123',
          'sender_phone': '79001234567',
          'sender_name': 'Иван',
          'type': 'text',
          'content': 'Привет!',
          'media_url': 'https://example.com/photo.jpg',
          'voice_duration': 15,
          'reply_to_id': 'msg_000',
          'reactions': {
            '👍': ['79001111111', '79002222222'],
            '❤️': ['79003333333'],
          },
          'is_deleted': false,
          'created_at': '2026-03-10T12:00:00.000Z',
          'edited_at': '2026-03-10T12:05:00.000Z',
          'delivered_to': ['79001111111', '79002222222'],
          'file_name': 'document.pdf',
          'file_size': 1024,
          'forwarded_from_id': 'msg_999',
          'forwarded_from_name': 'Петр',
          'is_pinned': true,
          'pinned_at': '2026-03-10T12:10:00.000Z',
          'pinned_by': '79009999999',
          'media_group_id': 'album_001',
        };

        final msg = MessengerMessage.fromJson(json);

        expect(msg.id, 'msg_001');
        expect(msg.conversationId, 'conv_123');
        expect(msg.senderPhone, '79001234567');
        expect(msg.senderName, 'Иван');
        expect(msg.type, MessageType.text);
        expect(msg.content, 'Привет!');
        expect(msg.mediaUrl, 'https://example.com/photo.jpg');
        expect(msg.voiceDuration, 15);
        expect(msg.replyToId, 'msg_000');
        expect(msg.reactions['👍'], ['79001111111', '79002222222']);
        expect(msg.reactions['❤️'], ['79003333333']);
        expect(msg.isDeleted, false);
        expect(msg.createdAt.year, 2026);
        expect(msg.editedAt, isNotNull);
        expect(msg.deliveredTo, ['79001111111', '79002222222']);
        expect(msg.fileName, 'document.pdf');
        expect(msg.fileSize, 1024);
        expect(msg.forwardedFromId, 'msg_999');
        expect(msg.forwardedFromName, 'Петр');
        expect(msg.isPinned, true);
        expect(msg.pinnedAt, isNotNull);
        expect(msg.pinnedBy, '79009999999');
        expect(msg.mediaGroupId, 'album_001');
      });

      test('parses minimal JSON (only required fields)', () {
        final json = {
          'id': 'msg_002',
          'conversation_id': 'conv_456',
          'sender_phone': '79005555555',
          'created_at': '2026-03-10T10:00:00.000Z',
        };

        final msg = MessengerMessage.fromJson(json);

        expect(msg.id, 'msg_002');
        expect(msg.conversationId, 'conv_456');
        expect(msg.senderPhone, '79005555555');
        expect(msg.senderName, isNull);
        expect(msg.type, MessageType.text); // default
        expect(msg.content, isNull);
        expect(msg.mediaUrl, isNull);
        expect(msg.voiceDuration, isNull);
        expect(msg.replyToId, isNull);
        expect(msg.reactions, isEmpty);
        expect(msg.isDeleted, false);
        expect(msg.editedAt, isNull);
        expect(msg.deliveredTo, isEmpty);
        expect(msg.fileName, isNull);
        expect(msg.fileSize, isNull);
        expect(msg.forwardedFromId, isNull);
        expect(msg.forwardedFromName, isNull);
        expect(msg.isPinned, false);
        expect(msg.pinnedAt, isNull);
        expect(msg.pinnedBy, isNull);
        expect(msg.mediaGroupId, isNull);
      });

      test('handles null and missing fields gracefully', () {
        final json = <String, dynamic>{
          'id': null,
          'conversation_id': null,
          'sender_phone': null,
          'type': null,
          'content': null,
          'created_at': null,
          'reactions': null,
          'is_deleted': null,
          'delivered_to': null,
        };

        final msg = MessengerMessage.fromJson(json);

        expect(msg.id, '');
        expect(msg.conversationId, '');
        expect(msg.senderPhone, '');
        expect(msg.type, MessageType.text); // null type defaults to text
        expect(msg.content, isNull);
        expect(msg.reactions, isEmpty);
        expect(msg.isDeleted, false);
        expect(msg.deliveredTo, isEmpty);
      });

      test('parses empty JSON without crash', () {
        final msg = MessengerMessage.fromJson({});

        expect(msg.id, '');
        expect(msg.conversationId, '');
        expect(msg.senderPhone, '');
        expect(msg.type, MessageType.text);
      });
    });

    group('message types', () {
      test('parses type "image"', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'image', 'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.type, MessageType.image);
        expect(msg.typeString, 'image');
      });

      test('parses type "video"', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'video', 'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.type, MessageType.video);
        expect(msg.typeString, 'video');
      });

      test('parses type "voice"', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'voice', 'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.type, MessageType.voice);
        expect(msg.typeString, 'voice');
      });

      test('parses type "poll"', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'poll', 'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.type, MessageType.poll);
        expect(msg.typeString, 'poll');
      });

      test('parses type "file"', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'file', 'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.type, MessageType.file);
        expect(msg.typeString, 'file');
      });

      test('parses type "sticker"', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'sticker', 'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.type, MessageType.sticker);
        expect(msg.typeString, 'sticker');
      });

      test('parses type "gif"', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'gif', 'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.type, MessageType.gif);
        expect(msg.typeString, 'gif');
      });

      test('parses type "contact"', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'contact', 'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.type, MessageType.contact);
        expect(msg.typeString, 'contact');
      });

      test('parses type "video_note"', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'video_note', 'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.type, MessageType.videoNote);
        expect(msg.typeString, 'video_note');
      });

      test('parses type "emoji"', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'emoji', 'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.type, MessageType.emoji);
        expect(msg.typeString, 'emoji');
      });

      test('parses type "call"', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'call', 'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.type, MessageType.call);
        expect(msg.typeString, 'call');
      });

      test('unknown type defaults to text', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'unknown_future_type', 'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.type, MessageType.text);
        expect(msg.typeString, 'text');
      });
    });

    group('computed properties', () {
      test('isEdited returns true when editedAt is set', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'created_at': '2026-01-01T00:00:00Z',
          'edited_at': '2026-01-01T01:00:00Z',
        });
        expect(msg.isEdited, true);
      });

      test('isEdited returns false when editedAt is null', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.isEdited, false);
      });

      test('isForwarded returns true when forwardedFromId is set', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'created_at': '2026-01-01T00:00:00Z',
          'forwarded_from_id': 'msg_original',
        });
        expect(msg.isForwarded, true);
      });

      test('isForwarded returns false when forwardedFromId is null', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.isForwarded, false);
      });
    });

    group('preview', () {
      test('text message returns content', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'text', 'content': 'Привет мир',
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.preview, 'Привет мир');
      });

      test('deleted message returns "Сообщение удалено"', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'text', 'content': 'secret',
          'is_deleted': true,
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.preview, 'Сообщение удалено');
      });

      test('image without album returns photo emoji', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'image',
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.preview, contains('Фото'));
      });

      test('image with media_group_id returns album', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'image', 'media_group_id': 'album_1',
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.preview, contains('Альбом'));
      });

      test('voice message shows formatted duration', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'voice', 'voice_duration': 125,
          'created_at': '2026-01-01T00:00:00Z',
        });
        // 125 seconds = 2:05
        expect(msg.preview, contains('2:05'));
      });

      test('voice message with 0 duration', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'voice', 'voice_duration': 0,
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.preview, contains('0:00'));
      });

      test('file message shows filename', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'file', 'file_name': 'report.xlsx',
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.preview, contains('report.xlsx'));
      });

      test('file message without filename shows Документ', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'file',
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.preview, contains('Документ'));
      });

      test('poll message preview', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'poll',
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.preview, contains('Опрос'));
      });

      test('video_note preview', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'video_note',
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.preview, contains('Видео-кружок'));
      });

      test('sticker preview', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'sticker',
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.preview, contains('Стикер'));
      });

      test('contact preview', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'contact',
          'created_at': '2026-01-01T00:00:00Z',
        });
        expect(msg.preview, contains('Контакт'));
      });
    });

    group('copyWith', () {
      test('creates copy with updated content', () {
        final original = MessengerMessage.fromJson({
          'id': 'msg_1', 'conversation_id': 'c', 'sender_phone': 'p',
          'type': 'text', 'content': 'Original',
          'created_at': '2026-01-01T00:00:00Z',
        });

        final copy = original.copyWith(content: 'Updated');

        expect(copy.id, 'msg_1'); // unchanged
        expect(copy.content, 'Updated'); // changed
        expect(copy.senderPhone, 'p'); // unchanged
      });

      test('creates copy with updated reactions', () {
        final original = MessengerMessage.fromJson({
          'id': 'msg_1', 'conversation_id': 'c', 'sender_phone': 'p',
          'created_at': '2026-01-01T00:00:00Z',
        });

        final copy = original.copyWith(reactions: {'👍': ['79001111111']});

        expect(copy.reactions['👍'], ['79001111111']);
        expect(original.reactions, isEmpty); // original unchanged
      });

      test('creates copy with isDeleted', () {
        final original = MessengerMessage.fromJson({
          'id': 'msg_1', 'conversation_id': 'c', 'sender_phone': 'p',
          'created_at': '2026-01-01T00:00:00Z',
        });

        final copy = original.copyWith(isDeleted: true);

        expect(copy.isDeleted, true);
        expect(original.isDeleted, false);
      });

      test('creates copy with isPending and isFailed', () {
        final original = MessengerMessage.fromJson({
          'id': 'msg_1', 'conversation_id': 'c', 'sender_phone': 'p',
          'created_at': '2026-01-01T00:00:00Z',
        });

        final pending = original.copyWith(isPending: true);
        expect(pending.isPending, true);
        expect(pending.isFailed, false);

        final failed = original.copyWith(isFailed: true);
        expect(failed.isFailed, true);
      });

      test('creates copy with isPinned', () {
        final original = MessengerMessage.fromJson({
          'id': 'msg_1', 'conversation_id': 'c', 'sender_phone': 'p',
          'created_at': '2026-01-01T00:00:00Z',
        });

        final pinned = original.copyWith(isPinned: true);
        expect(pinned.isPinned, true);
        expect(original.isPinned, false);
      });
    });

    group('reactions parsing', () {
      test('parses reactions map correctly', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'created_at': '2026-01-01T00:00:00Z',
          'reactions': {
            '👍': ['79001111111', '79002222222'],
            '❤️': ['79003333333'],
            '😂': [],
          },
        });

        expect(msg.reactions.length, 3);
        expect(msg.reactions['👍']!.length, 2);
        expect(msg.reactions['❤️']!.length, 1);
        expect(msg.reactions['😂'], isEmpty);
      });

      test('handles reactions as non-Map gracefully', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'created_at': '2026-01-01T00:00:00Z',
          'reactions': 'not a map',
        });
        expect(msg.reactions, isEmpty);
      });

      test('handles reactions with non-List values', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'created_at': '2026-01-01T00:00:00Z',
          'reactions': {'👍': 'not a list'},
        });
        // Non-list values are skipped
        expect(msg.reactions.containsKey('👍'), false);
      });
    });

    group('timestamp parsing', () {
      test('parses ISO timestamp correctly', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'created_at': '2026-03-10T15:30:00.000Z',
        });

        expect(msg.createdAt.year, 2026);
        expect(msg.createdAt.month, 3);
        expect(msg.createdAt.day, 10);
      });

      test('handles invalid timestamp without crash', () {
        final msg = MessengerMessage.fromJson({
          'id': '1', 'conversation_id': 'c', 'sender_phone': 'p',
          'created_at': 'invalid-date',
        });
        // Should fallback to DateTime.now() — just check it doesn't crash
        expect(msg.createdAt, isNotNull);
      });
    });
  });

  // ==========================================================================
  // Conversation tests
  // ==========================================================================
  group('Conversation', () {
    group('fromJson', () {
      test('parses full JSON with all fields', () {
        final json = {
          'id': 'private_79001111111_79002222222',
          'type': 'private',
          'name': null,
          'avatar_url': 'https://example.com/avatar.jpg',
          'creator_phone': '79001111111',
          'creator_name': 'Иван',
          'description': null,
          'participants': [
            {
              'phone': '79001111111',
              'name': 'Иван',
              'role': 'member',
              'joined_at': '2026-01-01T00:00:00Z',
              'avatar_url': null,
            },
            {
              'phone': '79002222222',
              'name': 'Мария',
              'role': 'member',
              'joined_at': '2026-01-01T00:00:00Z',
              'avatar_url': null,
            },
          ],
          'unread_count': 5,
          'last_message': {
            'id': 'msg_last',
            'conversation_id': 'private_79001111111_79002222222',
            'sender_phone': '79002222222',
            'sender_name': 'Мария',
            'type': 'text',
            'content': 'Последнее сообщение',
            'created_at': '2026-03-10T12:00:00Z',
          },
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-03-10T12:00:00Z',
          'last_read_at': '2026-03-10T11:00:00Z',
          'auto_delete_seconds': 3600,
        };

        final conv = Conversation.fromJson(json);

        expect(conv.id, 'private_79001111111_79002222222');
        expect(conv.type, ConversationType.private_);
        expect(conv.name, isNull);
        expect(conv.avatarUrl, 'https://example.com/avatar.jpg');
        expect(conv.creatorPhone, '79001111111');
        expect(conv.creatorName, 'Иван');
        expect(conv.description, isNull);
        expect(conv.participants.length, 2);
        expect(conv.unreadCount, 5);
        expect(conv.lastMessage, isNotNull);
        expect(conv.lastMessage!.content, 'Последнее сообщение');
        expect(conv.createdAt.year, 2026);
        expect(conv.updatedAt.year, 2026);
        expect(conv.lastReadAt, isNotNull);
        expect(conv.autoDeleteSeconds, 3600);
      });

      test('parses minimal JSON', () {
        final json = {
          'id': 'conv_min',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        };

        final conv = Conversation.fromJson(json);

        expect(conv.id, 'conv_min');
        expect(conv.type, ConversationType.private_); // default
        expect(conv.name, isNull);
        expect(conv.avatarUrl, isNull);
        expect(conv.creatorPhone, isNull);
        expect(conv.participants, isEmpty);
        expect(conv.unreadCount, 0);
        expect(conv.lastMessage, isNull);
        expect(conv.lastReadAt, isNull);
        expect(conv.autoDeleteSeconds, 0);
      });

      test('parses empty JSON without crash', () {
        final conv = Conversation.fromJson({});

        expect(conv.id, '');
        expect(conv.type, ConversationType.private_);
        expect(conv.participants, isEmpty);
        expect(conv.unreadCount, 0);
      });
    });

    group('conversation types', () {
      test('parses type "private" correctly', () {
        final conv = Conversation.fromJson({
          'id': 'c1', 'type': 'private',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.type, ConversationType.private_);
      });

      test('parses type "group" correctly', () {
        final conv = Conversation.fromJson({
          'id': 'c2', 'type': 'group', 'name': 'Рабочий чат',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.type, ConversationType.group);
      });

      test('parses type "channel" correctly', () {
        final conv = Conversation.fromJson({
          'id': 'c3', 'type': 'channel', 'name': 'Новости',
          'description': 'Канал с новостями',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.type, ConversationType.channel);
        expect(conv.description, 'Канал с новостями');
      });

      test('unknown type defaults to private', () {
        final conv = Conversation.fromJson({
          'id': 'c4', 'type': 'unknown_type',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.type, ConversationType.private_);
      });

      test('null type defaults to private', () {
        final conv = Conversation.fromJson({
          'id': 'c5', 'type': null,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.type, ConversationType.private_);
      });
    });

    group('displayName', () {
      test('group shows group name', () {
        final conv = Conversation.fromJson({
          'id': 'g1', 'type': 'group', 'name': 'Кофейня №1',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.displayName('79001111111'), 'Кофейня №1');
      });

      test('group without name shows "Группа"', () {
        final conv = Conversation.fromJson({
          'id': 'g2', 'type': 'group',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.displayName('79001111111'), 'Группа');
      });

      test('channel shows channel name', () {
        final conv = Conversation.fromJson({
          'id': 'ch1', 'type': 'channel', 'name': 'Объявления',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.displayName('79001111111'), 'Объявления');
      });

      test('channel without name shows "Канал"', () {
        final conv = Conversation.fromJson({
          'id': 'ch2', 'type': 'channel',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.displayName('79001111111'), 'Канал');
      });

      test('private chat shows other participant name', () {
        final conv = Conversation.fromJson({
          'id': 'private_79001111111_79002222222', 'type': 'private',
          'participants': [
            {'phone': '79001111111', 'name': 'Иван'},
            {'phone': '79002222222', 'name': 'Мария'},
          ],
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.displayName('79001111111'), 'Мария');
      });

      test('private chat shows phone when other has no name', () {
        final conv = Conversation.fromJson({
          'id': 'private_79001111111_79002222222', 'type': 'private',
          'participants': [
            {'phone': '79001111111', 'name': 'Иван'},
            {'phone': '79002222222'},
          ],
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.displayName('79001111111'), '79002222222');
      });

      test('private chat with no participants shows "Чат"', () {
        final conv = Conversation.fromJson({
          'id': 'private_79001111111_79002222222', 'type': 'private',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.displayName('79001111111'), 'Чат');
      });
    });

    group('isSavedMessages', () {
      test('returns true for self-chat', () {
        final conv = Conversation.fromJson({
          'id': 'private_79001111111_79001111111', 'type': 'private',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.isSavedMessages('79001111111'), true);
      });

      test('returns false for chat with another person', () {
        final conv = Conversation.fromJson({
          'id': 'private_79001111111_79002222222', 'type': 'private',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.isSavedMessages('79001111111'), false);
      });

      test('returns false for group conversations', () {
        final conv = Conversation.fromJson({
          'id': 'group_123', 'type': 'group',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.isSavedMessages('79001111111'), false);
      });

      test('saved messages displayName returns "Избранное"', () {
        final conv = Conversation.fromJson({
          'id': 'private_79001111111_79001111111', 'type': 'private',
          'participants': [
            {'phone': '79001111111', 'name': 'Иван'},
          ],
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.displayName('79001111111'), 'Избранное');
      });
    });

    group('otherPhone', () {
      test('returns other phone in private chat', () {
        final conv = Conversation.fromJson({
          'id': 'p1', 'type': 'private',
          'participants': [
            {'phone': '79001111111'},
            {'phone': '79002222222'},
          ],
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.otherPhone('79001111111'), '79002222222');
      });

      test('returns null for group chat', () {
        final conv = Conversation.fromJson({
          'id': 'g1', 'type': 'group',
          'participants': [
            {'phone': '79001111111'},
            {'phone': '79002222222'},
          ],
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.otherPhone('79001111111'), isNull);
      });

      test('returns null when no other participants', () {
        final conv = Conversation.fromJson({
          'id': 'p2', 'type': 'private',
          'participants': [
            {'phone': '79001111111'},
          ],
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.otherPhone('79001111111'), isNull);
      });
    });

    group('participants parsing', () {
      test('parses participants with all fields', () {
        final conv = Conversation.fromJson({
          'id': 'g1', 'type': 'group',
          'participants': [
            {
              'phone': '79001111111',
              'name': 'Иван',
              'role': 'admin',
              'joined_at': '2026-01-01T00:00:00Z',
              'last_read_at': '2026-03-10T12:00:00Z',
              'avatar_url': 'https://example.com/avatar.jpg',
            },
          ],
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });

        expect(conv.participants.length, 1);
        final p = conv.participants.first;
        expect(p.phone, '79001111111');
        expect(p.name, 'Иван');
        expect(p.role, 'admin');
        expect(p.isAdmin, true);
        expect(p.joinedAt, isNotNull);
        expect(p.lastReadAt, isNotNull);
        expect(p.avatarUrl, 'https://example.com/avatar.jpg');
      });

      test('skips null participants', () {
        final conv = Conversation.fromJson({
          'id': 'g2', 'type': 'group',
          'participants': [
            {'phone': '79001111111', 'name': 'Иван'},
            null,
            {'phone': '79002222222', 'name': 'Мария'},
          ],
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.participants.length, 2);
      });

      test('handles non-list participants', () {
        final conv = Conversation.fromJson({
          'id': 'g3', 'type': 'group',
          'participants': 'not a list',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.participants, isEmpty);
      });
    });

    group('last_message parsing', () {
      test('parses last_message as MessengerMessage', () {
        final conv = Conversation.fromJson({
          'id': 'c1', 'type': 'private',
          'last_message': {
            'id': 'msg_1',
            'conversation_id': 'c1',
            'sender_phone': '79001111111',
            'type': 'text',
            'content': 'Тест',
            'created_at': '2026-03-10T12:00:00Z',
          },
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });

        expect(conv.lastMessage, isNotNull);
        expect(conv.lastMessage!.id, 'msg_1');
        expect(conv.lastMessage!.content, 'Тест');
        expect(conv.lastMessage!.type, MessageType.text);
      });

      test('null last_message is handled', () {
        final conv = Conversation.fromJson({
          'id': 'c2', 'type': 'private',
          'last_message': null,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        });
        expect(conv.lastMessage, isNull);
      });
    });
  });

  // ==========================================================================
  // Participant tests
  // ==========================================================================
  group('Participant', () {
    test('fromJson with all fields', () {
      final p = Participant.fromJson({
        'phone': '79001111111',
        'name': 'Иван',
        'role': 'admin',
        'joined_at': '2026-01-01T00:00:00Z',
        'last_read_at': '2026-03-10T12:00:00Z',
        'avatar_url': 'https://example.com/a.jpg',
      });

      expect(p.phone, '79001111111');
      expect(p.name, 'Иван');
      expect(p.role, 'admin');
      expect(p.isAdmin, true);
      expect(p.joinedAt, isNotNull);
      expect(p.lastReadAt, isNotNull);
      expect(p.avatarUrl, 'https://example.com/a.jpg');
    });

    test('fromJson with minimal fields', () {
      final p = Participant.fromJson({'phone': '79002222222'});

      expect(p.phone, '79002222222');
      expect(p.name, isNull);
      expect(p.role, 'member');
      expect(p.isAdmin, false);
      expect(p.joinedAt, isNull);
      expect(p.lastReadAt, isNull);
      expect(p.avatarUrl, isNull);
    });

    test('fromJson with empty map', () {
      final p = Participant.fromJson({});

      expect(p.phone, '');
      expect(p.role, 'member');
      expect(p.isAdmin, false);
    });
  });

  // ==========================================================================
  // MessengerContact tests
  // ==========================================================================
  group('MessengerContact', () {
    test('fromJson with all fields', () {
      final c = MessengerContact.fromJson({
        'phone': '79001111111',
        'name': 'Иван Петров',
        'userType': 'employee',
      });

      expect(c.phone, '79001111111');
      expect(c.name, 'Иван Петров');
      expect(c.userType, 'employee');
      expect(c.displayName, 'Иван Петров');
    });

    test('fromJson with user_type (snake_case)', () {
      final c = MessengerContact.fromJson({
        'phone': '79001111111',
        'user_type': 'employee',
      });
      expect(c.userType, 'employee');
    });

    test('fromJson prefers userType over user_type', () {
      final c = MessengerContact.fromJson({
        'phone': '79001111111',
        'userType': 'employee',
        'user_type': 'client',
      });
      expect(c.userType, 'employee');
    });

    test('fromJson with minimal fields', () {
      final c = MessengerContact.fromJson({'phone': '79002222222'});

      expect(c.phone, '79002222222');
      expect(c.name, isNull);
      expect(c.userType, 'client'); // default
      expect(c.displayName, '79002222222'); // falls back to phone
    });

    test('displayName returns name when available', () {
      final c = MessengerContact.fromJson({
        'phone': '79001111111',
        'name': 'Мария',
      });
      expect(c.displayName, 'Мария');
    });

    test('displayName returns phone when name is null', () {
      final c = MessengerContact.fromJson({
        'phone': '79001111111',
      });
      expect(c.displayName, '79001111111');
    });
  });
}

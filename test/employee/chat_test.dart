import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P1 Тесты чата сотрудников для роли СОТРУДНИК
/// Покрывает: 4 типа чатов, WebSocket, сообщения, группы
void main() {
  group('Employee Chat Tests (P1)', () {
    late MockChatService mockChatService;
    late MockWebSocketService mockWebSocket;

    setUp(() async {
      mockChatService = MockChatService();
      mockWebSocket = MockWebSocketService();
    });

    tearDown(() async {
      mockChatService.clear();
      mockWebSocket.disconnect();
    });

    // ==================== ТИПЫ ЧАТОВ ====================

    group('Chat Types Tests', () {
      test('ET-CHT-001: Получение общего чата (general)', () async {
        // Act
        final chat = await mockChatService.getChat('general');

        // Assert
        expect(chat['type'], 'general');
        expect(chat['name'], 'Общий чат');
      });

      test('ET-CHT-002: Получение чата магазина (shop)', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];

        // Act
        final chat = await mockChatService.getChat('shop_$shopId');

        // Assert
        expect(chat['type'], 'shop');
        expect(chat['shopId'], shopId);
      });

      test('ET-CHT-003: Получение приватного чата (private)', () async {
        // Arrange
        final user1 = MockEmployeeData.validEmployee['id'];
        final user2 = MockEmployeeData.secondEmployee['id'];

        // Act
        final chat = await mockChatService.getPrivateChat(user1, user2);

        // Assert
        expect(chat['type'], 'private');
        expect(chat['participants'].length, 2);
      });

      test('ET-CHT-004: Получение группового чата (group)', () async {
        // Arrange
        final groupId = 'group_001';

        // Act
        final chat = await mockChatService.getChat(groupId);

        // Assert
        expect(chat['type'], 'group');
      });

      test('ET-CHT-005: Список всех чатов сотрудника', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];

        // Act
        final chats = await mockChatService.getEmployeeChats(employeeId);

        // Assert
        expect(chats, isA<List>());
        expect(chats.any((c) => c['type'] == 'general'), true);
      });
    });

    // ==================== СООБЩЕНИЯ ====================

    group('Messages Tests', () {
      test('ET-CHT-006: Отправка текстового сообщения', () async {
        // Arrange
        final chatId = 'general';
        final senderId = MockEmployeeData.validEmployee['id'];
        final text = 'Привет всем!';

        // Act
        final result = await mockChatService.sendMessage(
          chatId: chatId,
          senderId: senderId,
          senderName: MockEmployeeData.validEmployee['name'],
          text: text,
        );

        // Assert
        expect(result['success'], true);
        expect(result['message']['text'], text);
      });

      test('ET-CHT-007: Отправка фото в чат', () async {
        // Arrange
        final chatId = 'general';
        final senderId = MockEmployeeData.validEmployee['id'];
        final imageUrl = '/path/to/image.jpg';

        // Act
        final result = await mockChatService.sendMessage(
          chatId: chatId,
          senderId: senderId,
          senderName: MockEmployeeData.validEmployee['name'],
          imageUrl: imageUrl,
        );

        // Assert
        expect(result['success'], true);
        expect(result['message']['imageUrl'], imageUrl);
      });

      test('ET-CHT-008: Получение истории сообщений', () async {
        // Arrange
        final chatId = 'general';
        await mockChatService.sendMessage(
          chatId: chatId,
          senderId: MockEmployeeData.validEmployee['id'],
          senderName: MockEmployeeData.validEmployee['name'],
          text: 'Тестовое сообщение',
        );

        // Act
        final messages = await mockChatService.getMessages(chatId);

        // Assert
        expect(messages, isA<List>());
        expect(messages.length, greaterThan(0));
      });

      test('ET-CHT-009: Пагинация сообщений', () async {
        // Arrange
        final chatId = 'general';
        for (var i = 0; i < 50; i++) {
          await mockChatService.sendMessage(
            chatId: chatId,
            senderId: MockEmployeeData.validEmployee['id'],
            senderName: MockEmployeeData.validEmployee['name'],
            text: 'Сообщение $i',
          );
        }

        // Act
        final page1 = await mockChatService.getMessages(chatId, limit: 20);
        final page2 = await mockChatService.getMessages(
          chatId,
          limit: 20,
          offset: 20,
        );

        // Assert
        expect(page1.length, 20);
        expect(page2.length, 20);
        expect(page1.first['text'], isNot(equals(page2.first['text'])));
      });

      test('ET-CHT-010: Отметка сообщений прочитанными', () async {
        // Arrange
        final chatId = 'general';
        await mockChatService.sendMessage(
          chatId: chatId,
          senderId: MockEmployeeData.secondEmployee['id'],
          senderName: MockEmployeeData.secondEmployee['name'],
          text: 'Непрочитанное сообщение',
        );
        final userId = MockEmployeeData.validEmployee['id'];

        // Act
        final result = await mockChatService.markAsRead(chatId, userId);

        // Assert
        expect(result['success'], true);
      });

      test('ET-CHT-011: Счётчик непрочитанных сообщений', () async {
        // Arrange
        final chatId = 'general';
        final userId = MockEmployeeData.validEmployee['id'];
        await mockChatService.sendMessage(
          chatId: chatId,
          senderId: MockEmployeeData.secondEmployee['id'],
          senderName: MockEmployeeData.secondEmployee['name'],
          text: 'Новое сообщение 1',
        );
        await mockChatService.sendMessage(
          chatId: chatId,
          senderId: MockEmployeeData.secondEmployee['id'],
          senderName: MockEmployeeData.secondEmployee['name'],
          text: 'Новое сообщение 2',
        );

        // Act
        final unreadCount = await mockChatService.getUnreadCount(chatId, userId);

        // Assert
        expect(unreadCount, greaterThan(0));
      });
    });

    // ==================== ГРУППОВЫЕ ЧАТЫ ====================

    group('Group Chat Tests', () {
      test('ET-CHT-012: Создание группового чата', () async {
        // Arrange
        final creatorId = MockEmployeeData.adminEmployee['id'];
        final participants = [
          MockEmployeeData.validEmployee['id'],
          MockEmployeeData.secondEmployee['id'],
        ];

        // Act
        final result = await mockChatService.createGroup(
          name: 'Тестовая группа',
          creatorId: creatorId,
          participants: participants,
        );

        // Assert
        expect(result['success'], true);
        expect(result['group']['name'], 'Тестовая группа');
        expect(result['group']['participants'].length, 3); // + creator
      });

      test('ET-CHT-013: Добавление участника в группу', () async {
        // Arrange
        final group = await mockChatService.createGroup(
          name: 'Группа',
          creatorId: MockEmployeeData.adminEmployee['id'],
          participants: [MockEmployeeData.validEmployee['id']],
        );
        final newMember = MockEmployeeData.secondEmployee['id'];

        // Act
        final result = await mockChatService.addGroupMember(
          group['group']['id'],
          newMember,
        );

        // Assert
        expect(result['success'], true);
        expect(result['participants'].contains(newMember), true);
      });

      test('ET-CHT-014: Удаление участника из группы', () async {
        // Arrange
        final group = await mockChatService.createGroup(
          name: 'Группа',
          creatorId: MockEmployeeData.adminEmployee['id'],
          participants: [
            MockEmployeeData.validEmployee['id'],
            MockEmployeeData.secondEmployee['id'],
          ],
        );
        final memberToRemove = MockEmployeeData.secondEmployee['id'];

        // Act
        final result = await mockChatService.removeGroupMember(
          group['group']['id'],
          memberToRemove,
        );

        // Assert
        expect(result['success'], true);
        expect(result['participants'].contains(memberToRemove), false);
      });

      test('ET-CHT-015: Удаление группы создателем', () async {
        // Arrange
        final group = await mockChatService.createGroup(
          name: 'Группа для удаления',
          creatorId: MockEmployeeData.adminEmployee['id'],
          participants: [MockEmployeeData.validEmployee['id']],
        );

        // Act
        final result = await mockChatService.deleteGroup(
          group['group']['id'],
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['success'], true);
      });

      test('ET-CHT-016: Невозможность удаления группы не-создателем', () async {
        // Arrange
        final group = await mockChatService.createGroup(
          name: 'Группа',
          creatorId: MockEmployeeData.adminEmployee['id'],
          participants: [MockEmployeeData.validEmployee['id']],
        );

        // Act
        final result = await mockChatService.deleteGroup(
          group['group']['id'],
          MockEmployeeData.validEmployee['id'],
        );

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('permission'));
      });

      test('ET-CHT-017: Переименование группы', () async {
        // Arrange
        final group = await mockChatService.createGroup(
          name: 'Старое имя',
          creatorId: MockEmployeeData.adminEmployee['id'],
          participants: [MockEmployeeData.validEmployee['id']],
        );

        // Act
        final result = await mockChatService.renameGroup(
          group['group']['id'],
          'Новое имя',
        );

        // Assert
        expect(result['success'], true);
        expect(result['name'], 'Новое имя');
      });
    });

    // ==================== WEBSOCKET ====================

    group('WebSocket Tests', () {
      test('ET-CHT-018: Подключение к WebSocket', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];

        // Act
        final connected = await mockWebSocket.connect(employeeId);

        // Assert
        expect(connected, true);
        expect(mockWebSocket.isConnected, true);
      });

      test('ET-CHT-019: Получение сообщений в реальном времени', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockWebSocket.connect(employeeId);
        final receivedMessages = <Map<String, dynamic>>[];

        mockWebSocket.onMessage = (message) {
          receivedMessages.add(message);
        };

        // Act
        mockWebSocket.simulateIncomingMessage({
          'chatId': 'general',
          'senderId': MockEmployeeData.secondEmployee['id'],
          'text': 'Новое сообщение',
        });

        // Assert
        expect(receivedMessages.length, 1);
        expect(receivedMessages.first['text'], 'Новое сообщение');
      });

      test('ET-CHT-020: Отправка сообщения через WebSocket', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockWebSocket.connect(employeeId);

        // Act
        final result = mockWebSocket.send({
          'type': 'message',
          'chatId': 'general',
          'text': 'WebSocket сообщение',
        });

        // Assert
        expect(result, true);
      });

      test('ET-CHT-021: Переподключение при разрыве связи', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockWebSocket.connect(employeeId);

        // Act
        mockWebSocket.simulateDisconnect();
        await Future.delayed(Duration(milliseconds: 100));
        final reconnected = await mockWebSocket.reconnect();

        // Assert
        expect(reconnected, true);
        expect(mockWebSocket.isConnected, true);
      });

      test('ET-CHT-022: Отключение от WebSocket', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockWebSocket.connect(employeeId);

        // Act
        mockWebSocket.disconnect();

        // Assert
        expect(mockWebSocket.isConnected, false);
      });
    });

    // ==================== ФИЛЬТРАЦИЯ ДЛЯ КЛИЕНТОВ ====================

    group('Client Access Tests', () {
      test('ET-CHT-023: Клиент видит только группы где он участник', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];

        // Create group with client
        await mockChatService.createGroup(
          name: 'Группа с клиентом',
          creatorId: MockEmployeeData.adminEmployee['id'],
          participants: [clientPhone],
        );

        // Create group without client
        await mockChatService.createGroup(
          name: 'Группа без клиента',
          creatorId: MockEmployeeData.adminEmployee['id'],
          participants: [MockEmployeeData.validEmployee['id']],
        );

        // Act
        final clientGroups = await mockChatService.getClientGroups(clientPhone);

        // Assert
        expect(clientGroups.length, 1);
        expect(clientGroups.first['name'], 'Группа с клиентом');
      });

      test('ET-CHT-024: Клиент не видит general чат', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];

        // Act
        final chats = await mockChatService.getClientChats(clientPhone);

        // Assert
        expect(chats.any((c) => c['type'] == 'general'), false);
      });

      test('ET-CHT-025: Клиент не видит shop чаты', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];

        // Act
        final chats = await mockChatService.getClientChats(clientPhone);

        // Assert
        expect(chats.any((c) => c['type'] == 'shop'), false);
      });

      test('ET-CHT-026: Нормализация телефона клиента', () async {
        // Arrange
        final phoneWithSpaces = '+7 900 123 45 67';
        final normalizedPhone = '79001234567';

        // Act
        final normalized = mockChatService.normalizePhone(phoneWithSpaces);

        // Assert
        expect(normalized, normalizedPhone);
      });
    });

    // ==================== PUSH-УВЕДОМЛЕНИЯ ====================

    group('Push Notification Tests', () {
      test('ET-CHT-027: Push при новом сообщении в чате', () async {
        // Arrange
        final chatId = 'general';

        // Act
        final result = await mockChatService.sendMessage(
          chatId: chatId,
          senderId: MockEmployeeData.validEmployee['id'],
          senderName: MockEmployeeData.validEmployee['name'],
          text: 'Сообщение с уведомлением',
        );

        // Assert
        expect(result['notificationsSent'], greaterThan(0));
      });

      test('ET-CHT-028: Push содержит превью сообщения', () async {
        // Arrange
        final text = 'Это текст сообщения';

        // Act
        final notification = mockChatService.buildNotification(
          senderName: MockEmployeeData.validEmployee['name'],
          text: text,
          chatName: 'Общий чат',
        );

        // Assert
        expect(notification['body'], contains(text.substring(0, 20)));
      });
    });

    // ==================== СОРТИРОВКА ====================

    group('Sorting Tests', () {
      test('ET-CHT-029: Непрочитанные чаты вверху списка', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];

        // Act
        final chats = await mockChatService.getEmployeeChats(
          employeeId,
          sortByUnread: true,
        );

        // Assert
        // Unread chats should come first
        bool foundRead = false;
        for (final chat in chats) {
          if (chat['unreadCount'] == 0) {
            foundRead = true;
          } else if (foundRead) {
            fail('Unread chat found after read chat');
          }
        }
      });

      test('ET-CHT-030: Сортировка по времени последнего сообщения', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];

        // Act
        final chats = await mockChatService.getEmployeeChats(employeeId);

        // Assert
        for (var i = 0; i < chats.length - 1; i++) {
          final time1 = DateTime.parse(chats[i]['lastMessageAt'] ?? '2000-01-01');
          final time2 = DateTime.parse(chats[i + 1]['lastMessageAt'] ?? '2000-01-01');
          expect(
            time1.isAfter(time2) || time1.isAtSameMomentAs(time2),
            true,
            reason: 'Chats should be sorted by last message time',
          );
        }
      });
    });
  });
}

// ==================== MOCK SERVICES ====================

class MockChatService {
  final Map<String, Map<String, dynamic>> _chats = {
    'general': {
      'id': 'general',
      'type': 'general',
      'name': 'Общий чат',
      'lastMessageAt': DateTime.now().toIso8601String(),
    },
  };
  final Map<String, List<Map<String, dynamic>>> _messages = {};
  final Map<String, Map<String, dynamic>> _groups = {};
  final Map<String, int> _unreadCounts = {};

  Future<Map<String, dynamic>> getChat(String chatId) async {
    if (_chats.containsKey(chatId)) {
      return _chats[chatId]!;
    }

    if (chatId.startsWith('shop_')) {
      final shopId = chatId.replaceFirst('shop_', '');
      return {
        'id': chatId,
        'type': 'shop',
        'shopId': shopId,
        'name': 'Чат магазина',
      };
    }

    if (chatId.startsWith('group_') || _groups.containsKey(chatId)) {
      return _groups[chatId] ?? {
        'id': chatId,
        'type': 'group',
        'name': 'Групповой чат',
      };
    }

    return {'id': chatId, 'type': 'unknown'};
  }

  Future<Map<String, dynamic>> getPrivateChat(String user1, String user2) async {
    final chatId = 'private_${user1}_$user2';
    return {
      'id': chatId,
      'type': 'private',
      'participants': [user1, user2],
    };
  }

  Future<List<Map<String, dynamic>>> getEmployeeChats(
    String employeeId, {
    bool sortByUnread = false,
  }) async {
    final chats = [
      _chats['general']!,
      {
        'id': 'shop_shop_001',
        'type': 'shop',
        'name': 'Чат магазина',
        'unreadCount': 2,
        'lastMessageAt': DateTime.now().subtract(Duration(hours: 1)).toIso8601String(),
      },
    ];

    _groups.forEach((id, group) {
      if ((group['participants'] as List).contains(employeeId)) {
        chats.add(group);
      }
    });

    if (sortByUnread) {
      chats.sort((a, b) {
        final unreadA = a['unreadCount'] ?? 0;
        final unreadB = b['unreadCount'] ?? 0;
        if (unreadA != unreadB) return unreadB.compareTo(unreadA);
        final timeA = DateTime.parse(a['lastMessageAt'] ?? '2000-01-01');
        final timeB = DateTime.parse(b['lastMessageAt'] ?? '2000-01-01');
        return timeB.compareTo(timeA);
      });
    } else {
      chats.sort((a, b) {
        final timeA = DateTime.parse(a['lastMessageAt'] ?? '2000-01-01');
        final timeB = DateTime.parse(b['lastMessageAt'] ?? '2000-01-01');
        return timeB.compareTo(timeA);
      });
    }

    return chats;
  }

  Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    String? text,
    String? imageUrl,
  }) async {
    final message = {
      'id': 'msg_${DateTime.now().millisecondsSinceEpoch}',
      'chatId': chatId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'imageUrl': imageUrl,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _messages.putIfAbsent(chatId, () => []);
    _messages[chatId]!.add(message);

    // Update last message time
    if (_chats.containsKey(chatId)) {
      _chats[chatId]!['lastMessageAt'] = message['createdAt'];
    }

    return {
      'success': true,
      'message': message,
      'notificationsSent': 5, // Mock notification count
    };
  }

  Future<List<Map<String, dynamic>>> getMessages(
    String chatId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final messages = _messages[chatId] ?? [];
    final end = (offset + limit).clamp(0, messages.length);
    return messages.sublist(offset.clamp(0, messages.length), end);
  }

  Future<Map<String, dynamic>> markAsRead(String chatId, String userId) async {
    _unreadCounts['${chatId}_$userId'] = 0;
    return {'success': true};
  }

  Future<int> getUnreadCount(String chatId, String userId) async {
    return _unreadCounts['${chatId}_$userId'] ?? (_messages[chatId]?.length ?? 0);
  }

  Future<Map<String, dynamic>> createGroup({
    required String name,
    required String creatorId,
    required List<String> participants,
  }) async {
    final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
    final allParticipants = [creatorId, ...participants];

    final group = {
      'id': groupId,
      'type': 'group',
      'name': name,
      'creatorId': creatorId,
      'participants': allParticipants,
      'lastMessageAt': DateTime.now().toIso8601String(),
    };

    _groups[groupId] = group;
    _chats[groupId] = group;

    return {'success': true, 'group': group};
  }

  Future<Map<String, dynamic>> addGroupMember(String groupId, String memberId) async {
    if (_groups.containsKey(groupId)) {
      final participants = List<String>.from(_groups[groupId]!['participants']);
      if (!participants.contains(memberId)) {
        participants.add(memberId);
        _groups[groupId]!['participants'] = participants;
      }
      return {'success': true, 'participants': participants};
    }
    return {'success': false, 'error': 'Group not found'};
  }

  Future<Map<String, dynamic>> removeGroupMember(String groupId, String memberId) async {
    if (_groups.containsKey(groupId)) {
      final participants = List<String>.from(_groups[groupId]!['participants']);
      participants.remove(memberId);
      _groups[groupId]!['participants'] = participants;
      return {'success': true, 'participants': participants};
    }
    return {'success': false, 'error': 'Group not found'};
  }

  Future<Map<String, dynamic>> deleteGroup(String groupId, String requesterId) async {
    if (!_groups.containsKey(groupId)) {
      return {'success': false, 'error': 'Group not found'};
    }

    if (_groups[groupId]!['creatorId'] != requesterId) {
      return {'success': false, 'error': 'No permission to delete'};
    }

    _groups.remove(groupId);
    _chats.remove(groupId);
    return {'success': true};
  }

  Future<Map<String, dynamic>> renameGroup(String groupId, String newName) async {
    if (_groups.containsKey(groupId)) {
      _groups[groupId]!['name'] = newName;
      return {'success': true, 'name': newName};
    }
    return {'success': false, 'error': 'Group not found'};
  }

  Future<List<Map<String, dynamic>>> getClientGroups(String phone) async {
    final normalizedPhone = normalizePhone(phone);
    return _groups.values
        .where((g) => (g['participants'] as List).contains(normalizedPhone))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getClientChats(String phone) async {
    // Clients can only see groups they're part of
    return getClientGroups(phone);
  }

  String normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[\s+]'), '');
  }

  Map<String, dynamic> buildNotification({
    required String senderName,
    required String text,
    required String chatName,
  }) {
    return {
      'title': '$senderName в $chatName',
      'body': text.length > 50 ? '${text.substring(0, 50)}...' : text,
    };
  }

  void clear() {
    _chats.clear();
    _messages.clear();
    _groups.clear();
    _unreadCounts.clear();
    _chats['general'] = {
      'id': 'general',
      'type': 'general',
      'name': 'Общий чат',
      'lastMessageAt': DateTime.now().toIso8601String(),
    };
  }
}

class MockWebSocketService {
  bool _connected = false;
  String? _userId;
  void Function(Map<String, dynamic>)? onMessage;

  bool get isConnected => _connected;

  Future<bool> connect(String userId) async {
    _userId = userId;
    _connected = true;
    return true;
  }

  void disconnect() {
    _connected = false;
    _userId = null;
  }

  bool send(Map<String, dynamic> data) {
    if (!_connected) return false;
    return true;
  }

  void simulateIncomingMessage(Map<String, dynamic> message) {
    if (_connected && onMessage != null) {
      onMessage!(message);
    }
  }

  void simulateDisconnect() {
    _connected = false;
  }

  Future<bool> reconnect() async {
    if (_userId != null) {
      return connect(_userId!);
    }
    return false;
  }
}

// ==================== MOCK DATA ====================

class MockShopData {
  static const Map<String, dynamic> validShop = {
    'id': 'shop_001',
    'name': 'Кофейня на Арбате',
    'address': 'ул. Арбат, 10',
  };
}

class MockEmployeeData {
  static const Map<String, dynamic> validEmployee = {
    'id': 'emp_001',
    'name': 'Тестовый Сотрудник',
    'phone': '79001234567',
    'isAdmin': false,
  };

  static const Map<String, dynamic> secondEmployee = {
    'id': 'emp_002',
    'name': 'Второй Сотрудник',
    'phone': '79002222222',
    'isAdmin': false,
  };

  static const Map<String, dynamic> adminEmployee = {
    'id': 'admin_001',
    'name': 'Администратор',
    'phone': '79009999999',
    'isAdmin': true,
  };
}

class MockClientData {
  static const Map<String, dynamic> validClient = {
    'phone': '79001234567',
    'name': 'Тестовый Клиент',
  };
}

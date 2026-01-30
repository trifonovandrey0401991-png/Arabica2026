import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/employee_chat_message_model.dart';

/// Сервис WebSocket для real-time функций чата:
/// - Мгновенное получение сообщений
/// - Индикатор набора текста
/// - Статус онлайн пользователей
class ChatWebSocketService {
  static ChatWebSocketService? _instance;
  static ChatWebSocketService get instance {
    _instance ??= ChatWebSocketService._();
    return _instance!;
  }

  ChatWebSocketService._();

  WebSocketChannel? _channel;
  String? _userPhone;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  // Stream controllers для событий
  final _newMessageController = StreamController<ChatWebSocketNewMessage>.broadcast();
  final _typingController = StreamController<ChatWebSocketTyping>.broadcast();
  final _onlineStatusController = StreamController<ChatWebSocketOnlineStatus>.broadcast();
  final _messageDeletedController = StreamController<ChatWebSocketMessageDeleted>.broadcast();
  final _chatClearedController = StreamController<ChatWebSocketChatCleared>.broadcast();
  final _reactionAddedController = StreamController<ChatWebSocketReaction>.broadcast();
  final _reactionRemovedController = StreamController<ChatWebSocketReaction>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();

  // Публичные streams
  Stream<ChatWebSocketNewMessage> get onNewMessage => _newMessageController.stream;
  Stream<ChatWebSocketTyping> get onTyping => _typingController.stream;
  Stream<ChatWebSocketOnlineStatus> get onOnlineStatus => _onlineStatusController.stream;
  Stream<ChatWebSocketMessageDeleted> get onMessageDeleted => _messageDeletedController.stream;
  Stream<ChatWebSocketChatCleared> get onChatCleared => _chatClearedController.stream;
  Stream<ChatWebSocketReaction> get onReactionAdded => _reactionAddedController.stream;
  Stream<ChatWebSocketReaction> get onReactionRemoved => _reactionRemovedController.stream;
  Stream<bool> get onConnectionStatus => _connectionStatusController.stream;

  bool get isConnected => _isConnected;

  /// Подключиться к WebSocket серверу
  Future<void> connect(String userPhone) async {
    if (_isConnected && _userPhone == userPhone) {
      Logger.debug('WebSocket: уже подключен');
      return;
    }

    _userPhone = userPhone.replaceAll(RegExp(r'[\s+]'), '');

    try {
      // Формируем WebSocket URL
      final wsUrl = _buildWebSocketUrl();
      Logger.debug('WebSocket: подключение к $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Слушаем сообщения
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      _isConnected = true;
      _connectionStatusController.add(true);

      // Запускаем ping для поддержания соединения
      _startPing();

      Logger.debug('WebSocket: подключен');
    } catch (e) {
      Logger.error('WebSocket: ошибка подключения', e);
      _scheduleReconnect();
    }
  }

  /// Отключиться от WebSocket сервера
  void disconnect() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _connectionStatusController.add(false);
    Logger.debug('WebSocket: отключен');
  }

  /// Отправить событие "начал печатать"
  void sendTypingStart(String chatId) {
    _send({
      'type': 'typing_start',
      'chatId': chatId,
    });
  }

  /// Отправить событие "перестал печатать"
  void sendTypingStop(String chatId) {
    _send({
      'type': 'typing_stop',
      'chatId': chatId,
    });
  }

  /// Запросить список онлайн пользователей
  void requestOnlineUsers() {
    _send({'type': 'get_online_users'});
  }

  // ===== ПРИВАТНЫЕ МЕТОДЫ =====

  String _buildWebSocketUrl() {
    // Преобразуем HTTP URL в WebSocket URL
    var baseUrl = ApiConstants.serverUrl;
    if (baseUrl.startsWith('https://')) {
      baseUrl = baseUrl.replaceFirst('https://', 'wss://');
    } else if (baseUrl.startsWith('http://')) {
      baseUrl = baseUrl.replaceFirst('http://', 'ws://');
    }
    return '$baseUrl/ws/employee-chat?phone=$_userPhone';
  }

  void _send(Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      Logger.debug('WebSocket: не подключен, сообщение не отправлено');
      return;
    }
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (e) {
      Logger.error('WebSocket: ошибка отправки', e);
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data.toString()) as Map<String, dynamic>;
      final type = message['type'] as String?;

      switch (type) {
        case 'connected':
          Logger.debug('WebSocket: подтверждение подключения');
          break;

        case 'new_message':
          final chatId = message['chatId'] as String?;
          final msgData = message['message'] as Map<String, dynamic>?;
          if (chatId != null && msgData != null) {
            _newMessageController.add(ChatWebSocketNewMessage(
              chatId: chatId,
              message: EmployeeChatMessage.fromJson(msgData),
            ));
          }
          break;

        case 'typing':
          final chatId = message['chatId'] as String?;
          final phone = message['phone'] as String?;
          final isTyping = message['isTyping'] as bool? ?? false;
          if (chatId != null && phone != null) {
            _typingController.add(ChatWebSocketTyping(
              chatId: chatId,
              phone: phone,
              isTyping: isTyping,
            ));
          }
          break;

        case 'online_status':
          final phone = message['phone'] as String?;
          final isOnline = message['isOnline'] as bool? ?? false;
          if (phone != null) {
            _onlineStatusController.add(ChatWebSocketOnlineStatus(
              phone: phone,
              isOnline: isOnline,
            ));
          }
          break;

        case 'online_users_list':
          final users = message['users'] as List<dynamic>? ?? [];
          for (final user in users) {
            if (user is Map<String, dynamic>) {
              final phone = user['phone'] as String?;
              if (phone != null) {
                _onlineStatusController.add(ChatWebSocketOnlineStatus(
                  phone: phone,
                  isOnline: true,
                ));
              }
            }
          }
          break;

        case 'message_deleted':
          final chatId = message['chatId'] as String?;
          final messageId = message['messageId'] as String?;
          if (chatId != null && messageId != null) {
            _messageDeletedController.add(ChatWebSocketMessageDeleted(
              chatId: chatId,
              messageId: messageId,
            ));
          }
          break;

        case 'chat_cleared':
          final chatId = message['chatId'] as String?;
          final deletedCount = message['deletedCount'] as int? ?? 0;
          if (chatId != null) {
            _chatClearedController.add(ChatWebSocketChatCleared(
              chatId: chatId,
              deletedCount: deletedCount,
            ));
          }
          break;

        case 'reaction_added':
          final chatId = message['chatId'] as String?;
          final messageId = message['messageId'] as String?;
          final reaction = message['reaction'] as String?;
          final phone = message['phone'] as String?;
          if (chatId != null && messageId != null && reaction != null && phone != null) {
            _reactionAddedController.add(ChatWebSocketReaction(
              chatId: chatId,
              messageId: messageId,
              reaction: reaction,
              phone: phone,
            ));
          }
          break;

        case 'reaction_removed':
          final chatId = message['chatId'] as String?;
          final messageId = message['messageId'] as String?;
          final reaction = message['reaction'] as String?;
          final phone = message['phone'] as String?;
          if (chatId != null && messageId != null && reaction != null && phone != null) {
            _reactionRemovedController.add(ChatWebSocketReaction(
              chatId: chatId,
              messageId: messageId,
              reaction: reaction,
              phone: phone,
            ));
          }
          break;

        case 'pong':
          // Ответ на ping, соединение живо
          break;

        default:
          Logger.debug('WebSocket: неизвестный тип сообщения: $type');
      }
    } catch (e) {
      Logger.error('WebSocket: ошибка обработки сообщения', e);
    }
  }

  void _handleError(dynamic error) {
    Logger.error('WebSocket: ошибка', error);
    _isConnected = false;
    _connectionStatusController.add(false);
    _scheduleReconnect();
  }

  void _handleDone() {
    Logger.debug('WebSocket: соединение закрыто');
    _isConnected = false;
    _connectionStatusController.add(false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_userPhone != null && !_isConnected) {
        Logger.debug('WebSocket: попытка переподключения...');
        connect(_userPhone!);
      }
    });
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _send({'type': 'ping'});
    });
  }

  /// Освободить ресурсы
  void dispose() {
    disconnect();
    _newMessageController.close();
    _typingController.close();
    _onlineStatusController.close();
    _messageDeletedController.close();
    _chatClearedController.close();
    _reactionAddedController.close();
    _reactionRemovedController.close();
    _connectionStatusController.close();
    _instance = null;
  }
}

// ===== МОДЕЛИ СОБЫТИЙ =====

class ChatWebSocketNewMessage {
  final String chatId;
  final EmployeeChatMessage message;

  ChatWebSocketNewMessage({required this.chatId, required this.message});
}

class ChatWebSocketTyping {
  final String chatId;
  final String phone;
  final bool isTyping;

  ChatWebSocketTyping({
    required this.chatId,
    required this.phone,
    required this.isTyping,
  });
}

class ChatWebSocketOnlineStatus {
  final String phone;
  final bool isOnline;

  ChatWebSocketOnlineStatus({required this.phone, required this.isOnline});
}

class ChatWebSocketMessageDeleted {
  final String chatId;
  final String messageId;

  ChatWebSocketMessageDeleted({required this.chatId, required this.messageId});
}

class ChatWebSocketChatCleared {
  final String chatId;
  final int deletedCount;

  ChatWebSocketChatCleared({required this.chatId, required this.deletedCount});
}

class ChatWebSocketReaction {
  final String chatId;
  final String messageId;
  final String reaction;
  final String phone;

  ChatWebSocketReaction({
    required this.chatId,
    required this.messageId,
    required this.reaction,
    required this.phone,
  });
}

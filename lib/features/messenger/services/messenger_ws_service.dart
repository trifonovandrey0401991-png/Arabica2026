import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/notification_service.dart';
import '../models/message_model.dart';

// ==================== WebSocket Event Models ====================

class MsgrNewMessage {
  final String conversationId;
  final MessengerMessage message;
  MsgrNewMessage({required this.conversationId, required this.message});
}

class MsgrTyping {
  final String conversationId;
  final String phone;
  final bool isTyping;
  MsgrTyping({required this.conversationId, required this.phone, required this.isTyping});
}

class MsgrOnlineStatus {
  final String phone;
  final bool isOnline;
  MsgrOnlineStatus({required this.phone, required this.isOnline});
}

class MsgrMessageDeleted {
  final String conversationId;
  final String messageId;
  MsgrMessageDeleted({required this.conversationId, required this.messageId});
}

class MsgrReadReceipt {
  final String conversationId;
  final String phone;
  final String readAt;
  MsgrReadReceipt({required this.conversationId, required this.phone, required this.readAt});
}

class MsgrReaction {
  final String conversationId;
  final String messageId;
  final String reaction;
  final String phone;
  MsgrReaction({required this.conversationId, required this.messageId, required this.reaction, required this.phone});
}

class MsgrMessageEdited {
  final String conversationId;
  final String messageId;
  final String newContent;
  final String editedAt;
  MsgrMessageEdited({required this.conversationId, required this.messageId, required this.newContent, required this.editedAt});
}

class MsgrMessageDelivered {
  final String conversationId;
  final String messageId;
  final List<String> deliveredTo;
  MsgrMessageDelivered({required this.conversationId, required this.messageId, required this.deliveredTo});
}

// ==================== Call Event Models ====================

class MsgrCallIncoming {
  final String callId;
  final String callerPhone;
  final String callerName;
  final String offerSdp;
  MsgrCallIncoming({required this.callId, required this.callerPhone, required this.callerName, required this.offerSdp});
}

class MsgrCallAnswered {
  final String callId;
  final String answerSdp;
  final String calleePhone;
  MsgrCallAnswered({required this.callId, required this.answerSdp, required this.calleePhone});
}

class MsgrCallRejected {
  final String callId;
  final String calleePhone;
  MsgrCallRejected({required this.callId, required this.calleePhone});
}

class MsgrCallIceCandidate {
  final String? callId;
  final Map<String, dynamic> candidate;
  final String fromPhone;
  MsgrCallIceCandidate({this.callId, required this.candidate, required this.fromPhone});
}

class MsgrCallHangup {
  final String? callId;
  final String fromPhone;
  MsgrCallHangup({this.callId, required this.fromPhone});
}

// ==================== WebSocket Service ====================

class MessengerWsService {
  static MessengerWsService? _instance;
  static MessengerWsService get instance {
    _instance ??= MessengerWsService._();
    return _instance!;
  }

  MessengerWsService._();

  WebSocketChannel? _channel;
  String? _userPhone;
  bool _isConnected = false;
  bool _isDisposed = false;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _connectionGeneration = 0;

  // Tracks which conversation is currently open (to suppress duplicate notifications)
  static String? _activeConversationId;
  static void setActiveConversation(String? id) => _activeConversationId = id;

  // Phone book names: normalized phone → contact name from device
  static bool isClientUser = false;
  static Map<String, String> phoneBookNames = {};
  static Set<String> phoneBookPhones = {};

  // Online users cache: phone → isOnline
  final Map<String, bool> _onlineUsers = {};

  bool isPhoneOnline(String phone) {
    final normalized = phone.replaceAll(RegExp(r'[^\d]'), '');
    return _onlineUsers[normalized] == true;
  }

  // Reconnection
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _baseReconnectDelay = Duration(seconds: 2);

  // Stream controllers (broadcast)
  final _newMessageController = StreamController<MsgrNewMessage>.broadcast();
  final _typingController = StreamController<MsgrTyping>.broadcast();
  final _onlineStatusController = StreamController<MsgrOnlineStatus>.broadcast();
  final _messageDeletedController = StreamController<MsgrMessageDeleted>.broadcast();
  final _readReceiptController = StreamController<MsgrReadReceipt>.broadcast();
  final _reactionAddedController = StreamController<MsgrReaction>.broadcast();
  final _reactionRemovedController = StreamController<MsgrReaction>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _messageEditedController = StreamController<MsgrMessageEdited>.broadcast();
  final _messageDeliveredController = StreamController<MsgrMessageDelivered>.broadcast();
  // Call signaling streams
  final _callIncomingController = StreamController<MsgrCallIncoming>.broadcast();
  final _callAnsweredController = StreamController<MsgrCallAnswered>.broadcast();
  final _callRejectedController = StreamController<MsgrCallRejected>.broadcast();
  final _callIceCandidateController = StreamController<MsgrCallIceCandidate>.broadcast();
  final _callHangupController = StreamController<MsgrCallHangup>.broadcast();

  // Public streams
  Stream<MsgrNewMessage> get onNewMessage => _newMessageController.stream;
  Stream<MsgrTyping> get onTyping => _typingController.stream;
  Stream<MsgrOnlineStatus> get onOnlineStatus => _onlineStatusController.stream;
  Stream<MsgrMessageDeleted> get onMessageDeleted => _messageDeletedController.stream;
  Stream<MsgrReadReceipt> get onReadReceipt => _readReceiptController.stream;
  Stream<MsgrReaction> get onReactionAdded => _reactionAddedController.stream;
  Stream<MsgrReaction> get onReactionRemoved => _reactionRemovedController.stream;
  Stream<bool> get onConnectionStatus => _connectionStatusController.stream;
  Stream<MsgrMessageEdited> get onMessageEdited => _messageEditedController.stream;
  Stream<MsgrMessageDelivered> get onMessageDelivered => _messageDeliveredController.stream;
  // Call signaling public streams
  Stream<MsgrCallIncoming> get onCallIncoming => _callIncomingController.stream;
  Stream<MsgrCallAnswered> get onCallAnswered => _callAnsweredController.stream;
  Stream<MsgrCallRejected> get onCallRejected => _callRejectedController.stream;
  Stream<MsgrCallIceCandidate> get onCallIceCandidate => _callIceCandidateController.stream;
  Stream<MsgrCallHangup> get onCallHangup => _callHangupController.stream;

  bool get isConnected => _isConnected;

  Future<void> connect(String userPhone) async {
    if (_isConnected && _userPhone == userPhone) return;

    _userPhone = userPhone;
    _isDisposed = false;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    // Increment generation to invalidate old connection handlers
    _connectionGeneration++;
    final myGeneration = _connectionGeneration;

    // Close old connection (its onDone will be ignored via generation check)
    _pingTimer?.cancel();
    try { _channel?.sink.close(); } catch (_) {}
    _channel = null;

    try {
      final wsUrl = _buildWebSocketUrl();
      Logger.debug('💬 Messenger WS: connecting to $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          if (_connectionGeneration != myGeneration) return;
          _handleError(error);
        },
        onDone: () {
          if (_connectionGeneration != myGeneration) return;
          _handleDone();
        },
      );

      _reconnectAttempts = 0;
      _startPing();

      Logger.debug('💬 Messenger WS: channel opened, waiting for server confirmation');
    } catch (e) {
      Logger.error('💬 Messenger WS: connection error: $e');
      _isConnected = false;
      _connectionStatusController.add(false);
      _scheduleReconnect();
    }
  }

  String _buildWebSocketUrl() {
    var baseUrl = ApiConstants.serverUrl;
    if (baseUrl.startsWith('https://')) {
      baseUrl = baseUrl.replaceFirst('https://', 'wss://');
    } else if (baseUrl.startsWith('http://')) {
      baseUrl = baseUrl.replaceFirst('http://', 'ws://');
    }

    final token = ApiConstants.sessionToken;
    final tokenParam = (token != null && token.isNotEmpty) ? '&token=$token' : '';
    return '$baseUrl/ws/messenger?phone=$_userPhone$tokenParam';
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _send({'type': 'ping'});
    });
  }

  void _handleMessage(dynamic data) {
    if (_isDisposed) return;
    try {
      final message = jsonDecode(data.toString()) as Map<String, dynamic>;
      final type = message['type'] as String?;

      switch (type) {
        case 'new_message':
          final convId = message['conversationId'] as String? ?? '';
          final msgData = message['message'] as Map<String, dynamic>?;
          if (msgData != null) {
            final msg = MessengerMessage.fromJson(msgData);
            _newMessageController.add(MsgrNewMessage(
              conversationId: convId,
              message: msg,
            ));
            // Auto-send delivery ack (we received the message)
            if (msg.senderPhone != _userPhone) {
              _send({'type': 'delivery_ack', 'messageIds': [msg.id], 'conversationId': convId});
            }
            // Show local notification if user is not currently in this chat
            if (_activeConversationId != convId) {
              // Name priority: phone book → profile name (group) / phone (private)
              final normalizedSender = _normalizePhone(msg.senderPhone);
              final bookName = phoneBookNames[normalizedSender] ?? phoneBookNames[msg.senderPhone];
              String senderName;
              if (bookName != null) {
                senderName = bookName;
              } else if (convId.startsWith('private_')) {
                senderName = msg.senderPhone;
              } else {
                senderName = msg.senderName ?? msg.senderPhone;
              }
              final preview = (msg.content != null && msg.content!.isNotEmpty)
                  ? msg.content!
                  : 'Новое сообщение';
              NotificationService.showMessengerNotification(senderName, preview, convId);
            }
          }
          break;

        case 'typing':
          _typingController.add(MsgrTyping(
            conversationId: message['conversationId'] as String? ?? '',
            phone: message['phone'] as String? ?? '',
            isTyping: message['isTyping'] == true,
          ));
          break;

        case 'online_status':
          final statusPhone = message['phone'] as String? ?? '';
          final isOnline = message['isOnline'] == true;
          if (statusPhone.isNotEmpty) _onlineUsers[statusPhone] = isOnline;
          _onlineStatusController.add(MsgrOnlineStatus(
            phone: statusPhone,
            isOnline: isOnline,
          ));
          break;

        case 'online_users_list':
          final users = message['users'] as List?;
          if (users != null) {
            _onlineUsers.clear();
            for (final u in users) {
              if (u is Map) {
                final p = u['phone']?.toString() ?? '';
                if (p.isNotEmpty) _onlineUsers[p] = true;
              }
            }
          }
          break;

        case 'message_deleted':
          _messageDeletedController.add(MsgrMessageDeleted(
            conversationId: message['conversationId'] as String? ?? '',
            messageId: message['messageId'] as String? ?? '',
          ));
          break;

        case 'message_edited':
          _messageEditedController.add(MsgrMessageEdited(
            conversationId: message['conversationId'] as String? ?? '',
            messageId: message['messageId'] as String? ?? '',
            newContent: message['newContent'] as String? ?? '',
            editedAt: message['editedAt'] as String? ?? '',
          ));
          break;

        case 'message_delivered':
          final rawDelivered = message['deliveredTo'];
          final deliveredList = rawDelivered is List
              ? rawDelivered.map((e) => e.toString()).toList()
              : <String>[];
          _messageDeliveredController.add(MsgrMessageDelivered(
            conversationId: message['conversationId'] as String? ?? '',
            messageId: message['messageId'] as String? ?? '',
            deliveredTo: deliveredList,
          ));
          break;

        case 'read_receipt':
          _readReceiptController.add(MsgrReadReceipt(
            conversationId: message['conversationId'] as String? ?? '',
            phone: message['phone'] as String? ?? '',
            readAt: message['readAt'] as String? ?? '',
          ));
          break;

        case 'reaction_added':
          _reactionAddedController.add(MsgrReaction(
            conversationId: message['conversationId'] as String? ?? '',
            messageId: message['messageId'] as String? ?? '',
            reaction: message['reaction'] as String? ?? '',
            phone: message['phone'] as String? ?? '',
          ));
          break;

        case 'reaction_removed':
          _reactionRemovedController.add(MsgrReaction(
            conversationId: message['conversationId'] as String? ?? '',
            messageId: message['messageId'] as String? ?? '',
            reaction: message['reaction'] as String? ?? '',
            phone: message['phone'] as String? ?? '',
          ));
          break;

        case 'connected':
          _isConnected = true;
          _connectionStatusController.add(true);
          requestOnlineUsers();
          Logger.debug('💬 Messenger WS: server confirmed connection');
          break;

        case 'pong':
          break;

        // ===== CALL SIGNALING =====
        case 'call_incoming':
          Logger.debug('📞 WS received call_incoming from ${message['callerPhone']}, callId=${message['callId']}, hasListeners=${_callIncomingController.hasListener}');
          _callIncomingController.add(MsgrCallIncoming(
            callId: message['callId'] as String? ?? '',
            callerPhone: message['callerPhone'] as String? ?? '',
            callerName: message['callerName'] as String? ?? '',
            offerSdp: message['offerSdp'] as String? ?? '',
          ));
          break;
        case 'call_answered':
          _callAnsweredController.add(MsgrCallAnswered(
            callId: message['callId'] as String? ?? '',
            answerSdp: message['answerSdp'] as String? ?? '',
            calleePhone: message['calleePhone'] as String? ?? '',
          ));
          break;
        case 'call_rejected':
          _callRejectedController.add(MsgrCallRejected(
            callId: message['callId'] as String? ?? '',
            calleePhone: message['calleePhone'] as String? ?? '',
          ));
          break;
        case 'call_ice_candidate':
          final raw = message['candidate'];
          if (raw is Map<String, dynamic>) {
            _callIceCandidateController.add(MsgrCallIceCandidate(
              callId: message['callId'] as String?,
              candidate: raw,
              fromPhone: message['fromPhone'] as String? ?? '',
            ));
          }
          break;
        case 'call_hangup':
          _callHangupController.add(MsgrCallHangup(
            callId: message['callId'] as String?,
            fromPhone: message['fromPhone'] as String? ?? '',
          ));
          break;
      }
    } catch (e) {
      Logger.error('💬 Messenger WS: parse error: $e');
    }
  }

  void _handleError(dynamic error) {
    Logger.error('💬 Messenger WS: error: $error');
    _isConnected = false;
    _connectionStatusController.add(false);
    _scheduleReconnect();
  }

  void _handleDone() {
    Logger.debug('💬 Messenger WS: disconnected');
    _isConnected = false;
    _pingTimer?.cancel();
    _connectionStatusController.add(false);

    if (!_isDisposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed || _userPhone == null) return;

    // Cancel any pending reconnect timer
    _reconnectTimer?.cancel();

    _reconnectAttempts++;

    if (_reconnectAttempts > _maxReconnectAttempts) {
      Logger.debug('💬 Messenger WS: max reconnect attempts, waiting 1 min');
      _reconnectTimer = Timer(const Duration(minutes: 1), () {
        if (!_isDisposed) {
          _reconnectAttempts = 0;
          _doConnect();
        }
      });
      return;
    }

    // Exponential backoff: 2s, 4s, 8s, 16s, 32s, max 60s
    final delay = Duration(
      seconds: (_baseReconnectDelay.inSeconds * (1 << (_reconnectAttempts - 1)))
          .clamp(2, 60),
    );

    Logger.debug('💬 Messenger WS: reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(delay, () {
      if (!_isDisposed) _doConnect();
    });
  }

  // ==================== ACTIONS ====================

  void sendTypingStart(String conversationId) {
    _send({'type': 'typing_start', 'conversationId': conversationId});
  }

  void sendTypingStop(String conversationId) {
    _send({'type': 'typing_stop', 'conversationId': conversationId});
  }

  void requestOnlineUsers() {
    _send({'type': 'get_online_users'});
  }

  // ===== CALL SIGNALING SEND METHODS =====

  void sendCallOffer({required String targetPhone, required String callId, required String offerSdp, required String callerName}) {
    _send({'type': 'call_offer', 'targetPhone': targetPhone, 'callId': callId, 'offerSdp': offerSdp, 'callerName': callerName});
  }

  void sendCallAnswer({required String callerPhone, required String callId, required String answerSdp}) {
    _send({'type': 'call_answer', 'callerPhone': callerPhone, 'callId': callId, 'answerSdp': answerSdp});
  }

  void sendCallReject({required String callerPhone, required String callId}) {
    _send({'type': 'call_reject', 'callerPhone': callerPhone, 'callId': callId});
  }

  void sendCallIceCandidate({required String targetPhone, required String callId, required Map<String, dynamic> candidate}) {
    _send({'type': 'call_ice_candidate', 'targetPhone': targetPhone, 'callId': callId, 'candidate': candidate});
  }

  void sendCallHangup({required String targetPhone, required String callId}) {
    _send({'type': 'call_hangup', 'targetPhone': targetPhone, 'callId': callId});
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (e) {
        Logger.error('💬 Messenger WS: send error: $e');
      }
    } else {
      Logger.error('💬 WS _send DROPPED: type=${data['type']} (connected=$_isConnected, channel=${_channel != null})');
    }
  }

  /// Send with retry: waits for WS connection and retries up to [maxRetries] times.
  /// Used for critical messages like call_answer that must not be lost.
  Future<bool> sendWithRetry(Map<String, dynamic> data, {int maxRetries = 3}) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      if (_channel != null && _isConnected) {
        try {
          _channel!.sink.add(jsonEncode(data));
          Logger.debug('💬 WS sendWithRetry: sent type=${data['type']} (attempt $attempt)');
          return true;
        } catch (e) {
          Logger.error('💬 WS sendWithRetry error: $e');
        }
      }
      if (attempt < maxRetries) {
        // Wait for reconnection
        reconnectIfNeeded();
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    Logger.error('💬 WS sendWithRetry FAILED: type=${data['type']} after $maxRetries retries');
    return false;
  }

  /// Call when app returns to foreground — reconnects immediately if disconnected
  void reconnectIfNeeded() {
    if (!_isConnected && !_isDisposed && _userPhone != null) {
      _reconnectTimer?.cancel();
      _reconnectAttempts = 0;
      _doConnect();
    }
  }

  // ==================== LIFECYCLE ====================

  void disconnect() {
    _isDisposed = true;
    _isConnected = false;
    _connectionGeneration++; // Invalidate old connection handlers
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    try { _channel?.sink.close(); } catch (_) {}
    _channel = null;
    _onlineUsers.clear();
    _activeConversationId = null;
    isClientUser = false;
    phoneBookNames = {};
    phoneBookPhones = {};
    _connectionStatusController.add(false);
  }

  static String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '7$digits';
    if (digits.length == 11) {
      if (digits.startsWith('8')) return '7${digits.substring(1)}';
      if (digits.startsWith('7')) return digits;
    }
    return raw;
  }

  void dispose() {
    disconnect();
    _newMessageController.close();
    _typingController.close();
    _onlineStatusController.close();
    _messageDeletedController.close();
    _readReceiptController.close();
    _reactionAddedController.close();
    _reactionRemovedController.close();
    _connectionStatusController.close();
    _messageEditedController.close();
    _messageDeliveredController.close();
    _callIncomingController.close();
    _callAnsweredController.close();
    _callRejectedController.close();
    _callIceCandidateController.close();
    _callHangupController.close();
    _instance = null;
  }
}

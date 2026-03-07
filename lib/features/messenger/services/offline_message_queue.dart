import 'dart:async';
import 'dart:collection';
import '../models/message_model.dart';
import 'messenger_service.dart';
import 'messenger_ws_service.dart';

/// Queued message waiting to be sent
class QueuedMessage {
  final String conversationId;
  final String senderPhone;
  final String senderName;
  final MessageType type;
  final String? content;
  final String? mediaUrl;
  final String? replyToId;
  final String tempId;
  int retryCount;

  QueuedMessage({
    required this.conversationId,
    required this.senderPhone,
    required this.senderName,
    required this.type,
    this.content,
    this.mediaUrl,
    this.replyToId,
    required this.tempId,
    this.retryCount = 0,
  });
}

/// Offline message queue: stores messages when offline, sends when back online.
/// Singleton — survives page transitions.
class OfflineMessageQueue {
  static final OfflineMessageQueue _instance = OfflineMessageQueue._();
  static OfflineMessageQueue get instance => _instance;
  OfflineMessageQueue._();

  final Queue<QueuedMessage> _queue = Queue();
  bool _isFlushing = false;
  StreamSubscription? _connectionSub;

  /// Callbacks for UI updates
  final _sentController = StreamController<({String tempId, MessengerMessage message})>.broadcast();
  final _failedController = StreamController<String>.broadcast();

  Stream<({String tempId, MessengerMessage message})> get onSent => _sentController.stream;
  Stream<String> get onFailed => _failedController.stream;

  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;

  /// Start listening to WS connection status
  void init() {
    _connectionSub?.cancel();
    _connectionSub = MessengerWsService.instance.onConnectionStatus.listen((connected) {
      if (connected && _queue.isNotEmpty) {
        flush();
      }
    });
  }

  /// Add message to queue
  void enqueue(QueuedMessage msg) {
    _queue.add(msg);
  }

  /// Try to send all queued messages
  Future<void> flush() async {
    if (_isFlushing || _queue.isEmpty) return;
    _isFlushing = true;

    try {
      while (_queue.isNotEmpty) {
        final msg = _queue.first;

        final result = await MessengerService.sendMessage(
          conversationId: msg.conversationId,
          senderPhone: msg.senderPhone,
          senderName: msg.senderName,
          type: msg.type,
          content: msg.content,
          mediaUrl: msg.mediaUrl,
          replyToId: msg.replyToId,
        );

        if (result != null) {
          _queue.removeFirst();
          _sentController.add((tempId: msg.tempId, message: result));
        } else {
          msg.retryCount++;
          if (msg.retryCount >= 3) {
            _queue.removeFirst();
            _failedController.add(msg.tempId);
          } else {
            // Stop flushing — will retry on next connection
            break;
          }
        }
      }
    } finally {
      _isFlushing = false;
    }
  }

  /// Remove a specific message from queue (e.g., user deleted it)
  void remove(String tempId) {
    _queue.removeWhere((m) => m.tempId == tempId);
  }

  void dispose() {
    _connectionSub?.cancel();
    _sentController.close();
    _failedController.close();
  }
}

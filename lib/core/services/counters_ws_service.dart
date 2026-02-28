import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants/api_constants.dart';
import '../utils/logger.dart';

/// Event model for counter updates received via WebSocket
class CounterUpdateEvent {
  final String counter;
  final int? delta;
  final String timestamp;

  CounterUpdateEvent({
    required this.counter,
    required this.delta,
    required this.timestamp,
  });
}

/// WebSocket service for live counter/badge updates.
/// Singleton — connects once, all pages listen to the same stream.
///
/// When the server notifies about a counter change, this service
/// broadcasts the event. Pages that display badges listen and
/// reload only the affected counter instead of polling everything.
class CountersWsService {
  static CountersWsService? _instance;
  static CountersWsService get instance {
    _instance ??= CountersWsService._();
    return _instance!;
  }

  CountersWsService._();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  String? _userPhone;
  String? _userRole;
  bool _isConnected = false;
  bool _isConnecting = false; // TCP open but not yet confirmed by server
  bool _isDisposed = false;
  Timer? _pingTimer;

  // Reconnection
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _baseReconnectDelay = Duration(seconds: 2);

  // Stream controllers (broadcast — multiple listeners)
  final _counterUpdateController = StreamController<CounterUpdateEvent>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();

  /// Stream of counter update events.
  /// Listen to this to know when to reload a specific badge.
  Stream<CounterUpdateEvent> get onCounterUpdate => _counterUpdateController.stream;

  /// Stream of connection status changes.
  Stream<bool> get onConnectionStatus => _connectionStatusController.stream;

  bool get isConnected => _isConnected;

  /// Connect to the counters WebSocket.
  /// Call once from the main page (MainMenuPage or ManagerGridPage).
  /// Safe to call multiple times — will not reconnect if already connected.
  Future<void> connect(String userPhone, {String role = 'employee'}) async {
    if ((_isConnected || _isConnecting) && _userPhone == userPhone) return;

    _userPhone = userPhone;
    _userRole = role;
    _isDisposed = false;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    if (_isConnecting) return;
    _isConnecting = true;
    try {
      final wsUrl = _buildWebSocketUrl();
      Logger.debug('📊 Counters WS: connecting...');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _channelSubscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      // Do NOT set _isConnected = true here.
      // Wait for server to send the 'connected' confirmation message.
      // This prevents premature badge updates and ping-before-handshake.
      Logger.debug('📊 Counters WS: socket opened, awaiting server confirmation...');
    } catch (e) {
      Logger.error('📊 Counters WS: connection error: $e');
      _isConnecting = false;
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
    final roleParam = (_userRole != null) ? '&role=$_userRole' : '';
    return '$baseUrl/ws/counters?phone=$_userPhone$tokenParam$roleParam';
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _send({'type': 'ping'});
    });
  }

  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data.toString()) as Map<String, dynamic>;
      final type = message['type'] as String?;

      switch (type) {
        case 'counter_update':
          final counter = message['counter'] as String? ?? '';
          final delta = message['delta'] as int?;
          final timestamp = message['timestamp'] as String? ?? '';
          _counterUpdateController.add(CounterUpdateEvent(
            counter: counter,
            delta: delta,
            timestamp: timestamp,
          ));
          break;

        case 'connected':
          Logger.debug('📊 Counters WS: server confirmed connection');
          _isConnecting = false;
          _isConnected = true;
          _reconnectAttempts = 0;
          _connectionStatusController.add(true);
          _startPing();
          break;

        case 'pong':
          break;
      }
    } catch (e) {
      Logger.error('📊 Counters WS: parse error: $e');
    }
  }

  void _handleError(dynamic error) {
    Logger.error('📊 Counters WS: error: $error');
    _isConnecting = false;
    _isConnected = false;
    _connectionStatusController.add(false);
    _scheduleReconnect();
  }

  void _handleDone() {
    Logger.debug('📊 Counters WS: disconnected');
    _isConnecting = false;
    _isConnected = false;
    _pingTimer?.cancel();
    _connectionStatusController.add(false);

    if (!_isDisposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed || _userPhone == null) return;

    _reconnectAttempts++;

    if (_reconnectAttempts > _maxReconnectAttempts) {
      Logger.debug('📊 Counters WS: max reconnect attempts, waiting 5 min');
      Future.delayed(const Duration(minutes: 5), () {
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

    Logger.debug('📊 Counters WS: reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    Future.delayed(delay, () {
      if (!_isDisposed) _doConnect();
    });
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (e) {
        Logger.error('📊 Counters WS: send error: $e');
      }
    }
  }

  void disconnect() {
    _isDisposed = true;
    _isConnecting = false;
    _isConnected = false;
    _pingTimer?.cancel();
    _channelSubscription?.cancel();
    _channelSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _connectionStatusController.add(false);
  }

  void dispose() {
    disconnect();
    _counterUpdateController.close();
    _connectionStatusController.close();
    _instance = null;
  }
}

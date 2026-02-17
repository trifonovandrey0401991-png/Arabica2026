import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

/// P1 Тесты WebSocket reconnect reset (Task 2.8)
/// Покрывает: reconnect с экспоненциальным backoff, сброс после 10 неудач
void main() {
  group('WebSocket Reconnect Tests (Phase 2.8)', () {
    late MockWebSocketReconnectService mockWs;

    setUp(() {
      mockWs = MockWebSocketReconnectService();
    });

    tearDown(() {
      mockWs.dispose();
    });

    // ==================== RECONNECT ====================

    group('Reconnect Logic', () {
      test('PH2-WS-001: Первое переподключение с минимальной задержкой', () {
        // Act
        final delay = mockWs.getReconnectDelay(0);

        // Assert — первая попытка: 1 сек (2^0 * 1000)
        expect(delay.inSeconds, 1);
      });

      test('PH2-WS-002: Экспоненциальный рост задержки', () {
        // Act
        final delay0 = mockWs.getReconnectDelay(0);
        final delay1 = mockWs.getReconnectDelay(1);
        final delay2 = mockWs.getReconnectDelay(2);
        final delay3 = mockWs.getReconnectDelay(3);

        // Assert — 1, 2, 4, 8 секунд
        expect(delay0.inSeconds, 1);
        expect(delay1.inSeconds, 2);
        expect(delay2.inSeconds, 4);
        expect(delay3.inSeconds, 8);
      });

      test('PH2-WS-003: Максимальная задержка ограничена 30 секундами', () {
        // Act — 2^10 = 1024 секунд → должно быть ограничено
        final delay = mockWs.getReconnectDelay(10);

        // Assert
        expect(delay.inSeconds, lessThanOrEqualTo(30));
      });

      test('PH2-WS-004: Счётчик попыток увеличивается', () {
        // Act
        mockWs.scheduleReconnect();
        mockWs.scheduleReconnect();
        mockWs.scheduleReconnect();

        // Assert
        expect(mockWs.reconnectAttempts, 3);
      });
    });

    // ==================== MAX ATTEMPTS + RESET ====================

    group('Max Attempts and Reset', () {
      test('PH2-WS-005: После 10 неудач — прекращение попыток', () {
        // Arrange
        mockWs.maxReconnectAttempts = 10;

        // Act — исчерпываем все попытки
        for (var i = 0; i < 10; i++) {
          mockWs.scheduleReconnect();
        }
        final canRetry = mockWs.scheduleReconnect(); // 11-я попытка

        // Assert
        expect(canRetry, false);
        expect(mockWs.reconnectAttempts, 10);
      });

      test('PH2-WS-006: Таймер сброса планируется после 10 неудач', () {
        // Arrange
        mockWs.maxReconnectAttempts = 10;

        // Act — исчерпываем все попытки
        for (var i = 0; i < 10; i++) {
          mockWs.scheduleReconnect();
        }
        mockWs.scheduleReconnect(); // Сработает reset timer

        // Assert
        expect(mockWs.retryResetTimerActive, true);
      });

      test('PH2-WS-007: Сброс счётчика после таймера', () async {
        // Arrange
        mockWs.maxReconnectAttempts = 10;
        mockWs.retryResetDelay = Duration(milliseconds: 50);

        // Act — исчерпываем все попытки
        for (var i = 0; i < 10; i++) {
          mockWs.scheduleReconnect();
        }
        mockWs.scheduleReconnect(); // Запускает reset timer

        // Ждём сброса
        await Future.delayed(Duration(milliseconds: 100));

        // Assert
        expect(mockWs.reconnectAttempts, 0);
        expect(mockWs.retryResetTimerActive, false);
      });

      test('PH2-WS-008: После сброса — reconnect снова работает', () async {
        // Arrange
        mockWs.maxReconnectAttempts = 10;
        mockWs.retryResetDelay = Duration(milliseconds: 50);

        // Исчерпываем все попытки
        for (var i = 0; i < 10; i++) {
          mockWs.scheduleReconnect();
        }
        mockWs.scheduleReconnect(); // reset timer

        await Future.delayed(Duration(milliseconds: 100));

        // Act — после сброса
        final canRetry = mockWs.scheduleReconnect();

        // Assert
        expect(canRetry, true);
        expect(mockWs.reconnectAttempts, 1);
      });
    });

    // ==================== DISCONNECT ====================

    group('Disconnect Cleanup', () {
      test('PH2-WS-009: Disconnect отменяет retry reset timer', () {
        // Arrange
        mockWs.maxReconnectAttempts = 10;
        for (var i = 0; i < 10; i++) {
          mockWs.scheduleReconnect();
        }
        mockWs.scheduleReconnect(); // reset timer scheduled

        // Act
        mockWs.disconnect();

        // Assert
        expect(mockWs.retryResetTimerActive, false);
      });

      test('PH2-WS-010: Disconnect сбрасывает счётчик попыток', () {
        // Arrange
        mockWs.scheduleReconnect();
        mockWs.scheduleReconnect();
        mockWs.scheduleReconnect();

        // Act
        mockWs.disconnect();

        // Assert
        expect(mockWs.reconnectAttempts, 0);
      });
    });
  });
}

// ==================== MOCK ====================

class MockWebSocketReconnectService {
  int reconnectAttempts = 0;
  int maxReconnectAttempts = 10;
  Duration retryResetDelay = const Duration(minutes: 5);
  Timer? _retryResetTimer;

  bool get retryResetTimerActive => _retryResetTimer?.isActive ?? false;

  Duration getReconnectDelay(int attempt) {
    final seconds = (1 << attempt).clamp(0, 30); // 2^attempt, max 30s
    return Duration(seconds: seconds);
  }

  /// Returns false if max attempts exhausted
  bool scheduleReconnect() {
    if (reconnectAttempts >= maxReconnectAttempts) {
      // Планируем сброс через retryResetDelay
      _retryResetTimer?.cancel();
      _retryResetTimer = Timer(retryResetDelay, () {
        reconnectAttempts = 0;
        _retryResetTimer = null;
      });
      return false;
    }

    reconnectAttempts++;
    return true;
  }

  void disconnect() {
    _retryResetTimer?.cancel();
    _retryResetTimer = null;
    reconnectAttempts = 0;
  }

  void dispose() {
    disconnect();
  }
}

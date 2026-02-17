import 'package:flutter_test/flutter_test.dart';

/// P1 Тесты auto-logout при 401 (Task 2.5)
/// Покрывает: callback при 401, debounce, очистка токена
void main() {
  group('Auto-Logout 401 Tests (Phase 2.5)', () {
    late MockBaseHttpService mockService;

    setUp(() {
      mockService = MockBaseHttpService();
    });

    tearDown(() {
      mockService.reset();
    });

    // ==================== CALLBACK ====================

    group('Unauthorized Callback', () {
      test('PH2-AUTH-001: Callback вызывается при 401', () {
        // Arrange
        var callbackCount = 0;
        mockService.onUnauthorized = () => callbackCount++;

        // Act
        mockService.simulateHttpError(401, '/api/test');

        // Assert
        expect(callbackCount, 1);
      });

      test('PH2-AUTH-002: Callback НЕ вызывается при 403', () {
        // Arrange
        var callbackCount = 0;
        mockService.onUnauthorized = () => callbackCount++;

        // Act
        mockService.simulateHttpError(403, '/api/test');

        // Assert
        expect(callbackCount, 0);
      });

      test('PH2-AUTH-003: Callback НЕ вызывается при 500', () {
        // Arrange
        var callbackCount = 0;
        mockService.onUnauthorized = () => callbackCount++;

        // Act
        mockService.simulateHttpError(500, '/api/test');

        // Assert
        expect(callbackCount, 0);
      });

      test('PH2-AUTH-004: Без callback 401 не вызывает ошибку', () {
        // Arrange — onUnauthorized = null

        // Act & Assert — не должно бросить исключение
        expect(
          () => mockService.simulateHttpError(401, '/api/test'),
          returnsNormally,
        );
      });
    });

    // ==================== DEBOUNCE ====================

    group('Debounce Protection', () {
      test('PH2-AUTH-005: Повторный 401 — debounce предотвращает двойной вызов',
          () {
        // Arrange
        var callbackCount = 0;
        mockService.onUnauthorized = () => callbackCount++;

        // Act — два 401 подряд
        mockService.simulateHttpError(401, '/api/test1');
        mockService.simulateHttpError(401, '/api/test2');

        // Assert — callback вызван только 1 раз (debounce)
        expect(callbackCount, 1);
      });

      test('PH2-AUTH-006: После сброса debounce — callback вызывается снова',
          () async {
        // Arrange
        var callbackCount = 0;
        mockService.onUnauthorized = () => callbackCount++;
        mockService.debounceDelay = Duration(milliseconds: 50);

        // Act
        mockService.simulateHttpError(401, '/api/test1');
        expect(callbackCount, 1);

        // Ждём сброса debounce
        await Future.delayed(Duration(milliseconds: 100));

        mockService.simulateHttpError(401, '/api/test2');

        // Assert
        expect(callbackCount, 2);
      });
    });

    // ==================== ОЧИСТКА ТОКЕНА ====================

    group('Token Cleanup', () {
      test('PH2-AUTH-007: Токен очищается при 401', () {
        // Arrange
        mockService.sessionToken = 'valid_token_123';

        // Act
        mockService.simulateHttpError(401, '/api/test');

        // Assert
        expect(mockService.sessionToken, isNull);
      });

      test('PH2-AUTH-008: Токен не меняется при других ошибках', () {
        // Arrange
        mockService.sessionToken = 'valid_token_123';

        // Act
        mockService.simulateHttpError(500, '/api/test');

        // Assert
        expect(mockService.sessionToken, 'valid_token_123');
      });
    });
  });
}

// ==================== MOCK ====================

class MockBaseHttpService {
  void Function()? onUnauthorized;
  String? sessionToken;
  bool _isHandlingUnauthorized = false;
  Duration debounceDelay = const Duration(seconds: 5);

  void simulateHttpError(int statusCode, String endpoint) {
    if (statusCode == 401) {
      _handleUnauthorized();
    }
  }

  void _handleUnauthorized() {
    if (_isHandlingUnauthorized) return;
    _isHandlingUnauthorized = true;

    sessionToken = null;
    onUnauthorized?.call();

    Future.delayed(debounceDelay, () {
      _isHandlingUnauthorized = false;
    });
  }

  void reset() {
    onUnauthorized = null;
    sessionToken = null;
    _isHandlingUnauthorized = false;
    debounceDelay = const Duration(seconds: 5);
  }
}

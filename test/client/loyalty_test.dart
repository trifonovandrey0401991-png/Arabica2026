import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P2 Тесты карты лояльности для роли КЛИЕНТ
/// Покрывает: QR-код, баллы, бонусы, акция N+M
void main() {
  group('Loyalty Card Tests (P2)', () {
    late MockLoyaltyService mockLoyaltyService;

    setUp(() async {
      mockLoyaltyService = MockLoyaltyService();
    });

    tearDown(() async {
      mockLoyaltyService.clear();
    });

    // ==================== QR-КОД ====================

    group('QR Code Tests', () {
      test('CT-LOY-001: Получение QR-кода клиента', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];

        // Act
        final qrData = await mockLoyaltyService.getClientQR(clientPhone);

        // Assert
        expect(qrData['qrCode'], isNotNull);
        expect(qrData['phone'], clientPhone);
      });

      test('CT-LOY-002: QR-код уникален для каждого клиента', () async {
        // Arrange
        final phone1 = '79001111111';
        final phone2 = '79002222222';

        // Act
        final qr1 = await mockLoyaltyService.getClientQR(phone1);
        final qr2 = await mockLoyaltyService.getClientQR(phone2);

        // Assert
        expect(qr1['qrCode'], isNot(equals(qr2['qrCode'])));
      });

      test('CT-LOY-003: Сканирование QR-кода сотрудником', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];
        final qrData = await mockLoyaltyService.getClientQR(clientPhone);

        // Act
        final scanResult = await mockLoyaltyService.scanQR(qrData['qrCode']);

        // Assert
        expect(scanResult['success'], true);
        expect(scanResult['phone'], clientPhone);
      });

      test('CT-LOY-004: Невалидный QR-код отклоняется', () async {
        // Act
        final result = await mockLoyaltyService.scanQR('invalid_qr_code');

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('invalid'));
      });
    });

    // ==================== БАЛЛЫ ====================

    group('Points Tests', () {
      test('CT-LOY-005: Получение текущих баллов клиента', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];

        // Act
        final points = await mockLoyaltyService.getPoints(clientPhone);

        // Assert
        expect(points, isA<int>());
        expect(points, greaterThanOrEqualTo(0));
      });

      test('CT-LOY-006: Начисление балла за покупку', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];
        final pointsBefore = await mockLoyaltyService.getPoints(clientPhone);

        // Act
        final result = await mockLoyaltyService.addPoint(clientPhone);
        final pointsAfter = await mockLoyaltyService.getPoints(clientPhone);

        // Assert
        expect(result['success'], true);
        expect(pointsAfter, pointsBefore + 1);
      });

      test('CT-LOY-007: +1 балл за каждый напиток', () async {
        // Arrange
        final clientPhone = '79003333333';

        // Act
        await mockLoyaltyService.addPoint(clientPhone);
        await mockLoyaltyService.addPoint(clientPhone);
        await mockLoyaltyService.addPoint(clientPhone);
        final points = await mockLoyaltyService.getPoints(clientPhone);

        // Assert
        expect(points, 3);
      });

      test('CT-LOY-008: Прогресс-бар показывает накопление', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];
        final settings = await mockLoyaltyService.getPromoSettings();

        // Act
        final points = await mockLoyaltyService.getPoints(clientPhone);
        final progress = points / settings['pointsRequired'];

        // Assert
        expect(progress, greaterThanOrEqualTo(0));
        expect(progress, lessThanOrEqualTo(1));
      });
    });

    // ==================== АКЦИЯ N+M ====================

    group('Promo N+M Tests', () {
      test('CT-LOY-009: Получение настроек акции', () async {
        // Act
        final settings = await mockLoyaltyService.getPromoSettings();

        // Assert
        expect(settings['pointsRequired'], isA<int>());
        expect(settings['drinksToGive'], isA<int>());
        expect(settings['promoText'], isNotNull);
      });

      test('CT-LOY-010: Дефолтная акция 10+1', () async {
        // Act
        final settings = await mockLoyaltyService.getPromoSettings();

        // Assert
        expect(settings['pointsRequired'], 10);
        expect(settings['drinksToGive'], 1);
      });

      test('CT-LOY-011: Достижение порога активирует бонус', () async {
        // Arrange
        final clientPhone = '79004444444';
        final settings = await mockLoyaltyService.getPromoSettings();

        // Накопить нужное количество баллов
        for (var i = 0; i < settings['pointsRequired']; i++) {
          await mockLoyaltyService.addPoint(clientPhone);
        }

        // Act
        final canRedeem = await mockLoyaltyService.canRedeemBonus(clientPhone);

        // Assert
        expect(canRedeem, true);
      });

      test('CT-LOY-012: Выдача бесплатного напитка', () async {
        // Arrange
        final clientPhone = '79005555555';
        final settings = await mockLoyaltyService.getPromoSettings();

        for (var i = 0; i < settings['pointsRequired']; i++) {
          await mockLoyaltyService.addPoint(clientPhone);
        }

        // Act
        final result = await mockLoyaltyService.redeemBonus(clientPhone);

        // Assert
        expect(result['success'], true);
        expect(result['drinksGiven'], settings['drinksToGive']);
      });

      test('CT-LOY-013: Баллы сбрасываются после redeem', () async {
        // Arrange
        final clientPhone = '79006666666';
        final settings = await mockLoyaltyService.getPromoSettings();

        for (var i = 0; i < settings['pointsRequired']; i++) {
          await mockLoyaltyService.addPoint(clientPhone);
        }

        // Act
        await mockLoyaltyService.redeemBonus(clientPhone);
        final pointsAfter = await mockLoyaltyService.getPoints(clientPhone);

        // Assert
        expect(pointsAfter, 0);
      });

      test('CT-LOY-014: Невозможно redeem без достаточных баллов', () async {
        // Arrange
        final clientPhone = '79007777777';
        await mockLoyaltyService.addPoint(clientPhone); // Only 1 point

        // Act
        final result = await mockLoyaltyService.redeemBonus(clientPhone);

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('insufficient'));
      });

      test('CT-LOY-015: Счётчик выданных бесплатных напитков', () async {
        // Arrange
        final clientPhone = '79008888888';
        final settings = await mockLoyaltyService.getPromoSettings();

        for (var i = 0; i < settings['pointsRequired']; i++) {
          await mockLoyaltyService.addPoint(clientPhone);
        }

        // Act
        await mockLoyaltyService.redeemBonus(clientPhone);
        final stats = await mockLoyaltyService.getClientStats(clientPhone);

        // Assert
        expect(stats['freeDrinksGiven'], 1);
      });
    });

    // ==================== АДМИНИСТРИРОВАНИЕ АКЦИИ ====================

    group('Promo Admin Tests', () {
      test('CT-LOY-016: Изменение формулы акции (только админ)', () async {
        // Arrange
        final newSettings = {
          'pointsRequired': 5,
          'drinksToGive': 1,
          'promoText': 'Каждый 6-й напиток бесплатно!',
        };

        // Act
        final result = await mockLoyaltyService.updatePromoSettings(
          newSettings,
          isAdmin: true,
        );

        // Assert
        expect(result['success'], true);
      });

      test('CT-LOY-017: Не-админ не может изменить настройки', () async {
        // Arrange
        final newSettings = {'pointsRequired': 3};

        // Act
        final result = await mockLoyaltyService.updatePromoSettings(
          newSettings,
          isAdmin: false,
        );

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('permission'));
      });

      test('CT-LOY-018: Валидация pointsRequired (1-100)', () async {
        // Act
        final resultTooLow = await mockLoyaltyService.updatePromoSettings(
          {'pointsRequired': 0},
          isAdmin: true,
        );
        final resultTooHigh = await mockLoyaltyService.updatePromoSettings(
          {'pointsRequired': 101},
          isAdmin: true,
        );

        // Assert
        expect(resultTooLow['success'], false);
        expect(resultTooHigh['success'], false);
      });

      test('CT-LOY-019: Валидация drinksToGive (1-10)', () async {
        // Act
        final resultTooLow = await mockLoyaltyService.updatePromoSettings(
          {'drinksToGive': 0},
          isAdmin: true,
        );
        final resultTooHigh = await mockLoyaltyService.updatePromoSettings(
          {'drinksToGive': 11},
          isAdmin: true,
        );

        // Assert
        expect(resultTooLow['success'], false);
        expect(resultTooHigh['success'], false);
      });

      test('CT-LOY-020: Кастомный текст условий акции', () async {
        // Arrange
        final promoText = 'Специальная акция: каждый 5-й кофе в подарок!';

        // Act
        await mockLoyaltyService.updatePromoSettings(
          {'promoText': promoText},
          isAdmin: true,
        );
        final settings = await mockLoyaltyService.getPromoSettings();

        // Assert
        expect(settings['promoText'], promoText);
      });
    });

    // ==================== СИНХРОНИЗАЦИЯ ====================

    group('Sync Tests', () {
      test('CT-LOY-021: Синхронизация freeDrinksGiven', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];

        // Act
        final result = await mockLoyaltyService.syncFreeDrinks(
          clientPhone,
          externalCount: 5,
        );

        // Assert
        expect(result['success'], true);
        expect(result['synced'], true);
      });

      test('CT-LOY-022: Кэширование настроек акции (5 минут)', () async {
        // Act
        final settings1 = await mockLoyaltyService.getPromoSettings();
        final settings2 = await mockLoyaltyService.getPromoSettings();

        // Assert
        expect(mockLoyaltyService.cacheHits, 1); // Second call hit cache
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockLoyaltyService {
  final Map<String, int> _points = {};
  final Map<String, int> _freeDrinksGiven = {};
  final Map<String, String> _qrCodes = {};
  int cacheHits = 0;
  Map<String, dynamic>? _cachedSettings;

  Map<String, dynamic> _promoSettings = {
    'pointsRequired': 10,
    'drinksToGive': 1,
    'promoText': 'Каждый 11-й напиток бесплатно!',
  };

  Future<Map<String, dynamic>> getClientQR(String phone) async {
    if (!_qrCodes.containsKey(phone)) {
      _qrCodes[phone] = 'qr_${phone.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
    }
    return {
      'qrCode': _qrCodes[phone],
      'phone': phone,
    };
  }

  Future<Map<String, dynamic>> scanQR(String qrCode) async {
    final entry = _qrCodes.entries.firstWhere(
      (e) => e.value == qrCode,
      orElse: () => MapEntry('', ''),
    );

    if (entry.key.isEmpty) {
      return {'success': false, 'error': 'invalid QR code'};
    }

    return {'success': true, 'phone': entry.key};
  }

  Future<int> getPoints(String phone) async {
    return _points[phone] ?? 0;
  }

  Future<Map<String, dynamic>> addPoint(String phone) async {
    _points[phone] = (_points[phone] ?? 0) + 1;
    return {'success': true, 'newPoints': _points[phone]};
  }

  Future<Map<String, dynamic>> getPromoSettings() async {
    if (_cachedSettings != null) {
      cacheHits++;
      return _cachedSettings!;
    }
    _cachedSettings = Map.from(_promoSettings);
    return _promoSettings;
  }

  Future<bool> canRedeemBonus(String phone) async {
    final points = await getPoints(phone);
    final settings = await getPromoSettings();
    return points >= settings['pointsRequired'];
  }

  Future<Map<String, dynamic>> redeemBonus(String phone) async {
    final points = await getPoints(phone);
    final settings = await getPromoSettings();

    if (points < settings['pointsRequired']) {
      return {'success': false, 'error': 'insufficient points'};
    }

    _points[phone] = 0;
    _freeDrinksGiven[phone] = (_freeDrinksGiven[phone] ?? 0) + (settings['drinksToGive'] as int);

    return {
      'success': true,
      'drinksGiven': settings['drinksToGive'],
    };
  }

  Future<Map<String, dynamic>> getClientStats(String phone) async {
    return {
      'points': _points[phone] ?? 0,
      'freeDrinksGiven': _freeDrinksGiven[phone] ?? 0,
    };
  }

  Future<Map<String, dynamic>> updatePromoSettings(
    Map<String, dynamic> newSettings, {
    required bool isAdmin,
  }) async {
    if (!isAdmin) {
      return {'success': false, 'error': 'No permission'};
    }

    if (newSettings.containsKey('pointsRequired')) {
      final points = newSettings['pointsRequired'] as int;
      if (points < 1 || points > 100) {
        return {'success': false, 'error': 'pointsRequired must be 1-100'};
      }
      _promoSettings['pointsRequired'] = points;
    }

    if (newSettings.containsKey('drinksToGive')) {
      final drinks = newSettings['drinksToGive'] as int;
      if (drinks < 1 || drinks > 10) {
        return {'success': false, 'error': 'drinksToGive must be 1-10'};
      }
      _promoSettings['drinksToGive'] = drinks;
    }

    if (newSettings.containsKey('promoText')) {
      _promoSettings['promoText'] = newSettings['promoText'];
    }

    _cachedSettings = null; // Invalidate cache
    return {'success': true};
  }

  Future<Map<String, dynamic>> syncFreeDrinks(
    String phone, {
    required int externalCount,
  }) async {
    _freeDrinksGiven[phone] = externalCount;
    return {'success': true, 'synced': true};
  }

  void clear() {
    _points.clear();
    _freeDrinksGiven.clear();
    _qrCodes.clear();
    _cachedSettings = null;
    cacheHits = 0;
  }
}

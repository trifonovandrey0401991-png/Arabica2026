import 'package:flutter_test/flutter_test.dart';
import 'dart:math';
import '../mocks/mock_services.dart';

/// P3 Тесты магазинов на карте + геофенсинг для роли КЛИЕНТ
/// Покрывает: Карта, маркеры, геозоны, push-уведомления
void main() {
  group('Shops Map & Geofencing Tests (P3)', () {
    late MockShopsMapService mockShopsMapService;
    late MockGeofenceService mockGeofenceService;

    setUp(() async {
      mockShopsMapService = MockShopsMapService();
      mockGeofenceService = MockGeofenceService();
    });

    tearDown(() async {
      mockShopsMapService.clear();
      mockGeofenceService.clear();
    });

    // ==================== КАРТА МАГАЗИНОВ ====================

    group('Shops Map Tests', () {
      test('CT-MAP-001: Получение списка магазинов с координатами', () async {
        // Act
        final shops = await mockShopsMapService.getShopsWithCoordinates();

        // Assert
        expect(shops, isA<List>());
        for (final shop in shops) {
          expect(shop['latitude'], isNotNull);
          expect(shop['longitude'], isNotNull);
        }
      });

      test('CT-MAP-002: Магазин содержит название и адрес', () async {
        // Act
        final shops = await mockShopsMapService.getShopsWithCoordinates();

        // Assert
        for (final shop in shops) {
          expect(shop['name'], isNotNull);
          expect(shop['address'], isNotNull);
        }
      });

      test('CT-MAP-003: Валидация координат (-90..90, -180..180)', () async {
        // Act
        final shops = await mockShopsMapService.getShopsWithCoordinates();

        // Assert
        for (final shop in shops) {
          final lat = shop['latitude'] as double;
          final lng = shop['longitude'] as double;
          expect(lat, inInclusiveRange(-90, 90));
          expect(lng, inInclusiveRange(-180, 180));
        }
      });

      test('CT-MAP-004: Получение ближайших магазинов', () async {
        // Arrange
        final userLat = 55.7558;
        final userLng = 37.6173;

        // Act
        final nearest = await mockShopsMapService.getNearestShops(
          userLat,
          userLng,
          limit: 3,
        );

        // Assert
        expect(nearest.length, lessThanOrEqualTo(3));
      });

      test('CT-MAP-005: Сортировка по расстоянию', () async {
        // Arrange
        final userLat = 55.7558;
        final userLng = 37.6173;

        // Act
        final nearest = await mockShopsMapService.getNearestShops(
          userLat,
          userLng,
        );

        // Assert
        for (var i = 0; i < nearest.length - 1; i++) {
          expect(
            nearest[i]['distance'] <= nearest[i + 1]['distance'],
            true,
            reason: 'Shops should be sorted by distance',
          );
        }
      });

      test('CT-MAP-006: Расчёт расстояния по формуле Haversine', () async {
        // Arrange
        final lat1 = 55.7558;
        final lng1 = 37.6173;
        final lat2 = 55.7600;
        final lng2 = 37.6200;

        // Act
        final distance = mockShopsMapService.calculateDistance(
          lat1, lng1, lat2, lng2,
        );

        // Assert
        expect(distance, greaterThan(0));
        expect(distance, lessThan(1000)); // Less than 1km for nearby points
      });

      test('CT-MAP-007: Магазин содержит часы работы', () async {
        // Act
        final shops = await mockShopsMapService.getShopsWithCoordinates();

        // Assert
        for (final shop in shops) {
          expect(shop['workingHours'], isNotNull);
        }
      });
    });

    // ==================== ГЕОФЕНСИНГ ====================

    group('Geofencing Tests', () {
      test('CT-GEO-001: Получение настроек геозоны', () async {
        // Act
        final settings = await mockGeofenceService.getSettings();

        // Assert
        expect(settings['radius'], isA<int>());
        expect(settings['enabled'], isA<bool>());
      });

      test('CT-GEO-002: Дефолтный радиус геозоны', () async {
        // Act
        final settings = await mockGeofenceService.getSettings();

        // Assert
        expect(settings['radius'], 500); // 500 meters default
      });

      test('CT-GEO-003: Проверка входа в геозону', () async {
        // Arrange
        final shopLat = 55.7558;
        final shopLng = 37.6173;
        final userLat = 55.7560; // Very close
        final userLng = 37.6175;
        final radius = 500;

        // Act
        final isInside = mockGeofenceService.isInsideGeofence(
          userLat, userLng,
          shopLat, shopLng,
          radius,
        );

        // Assert
        expect(isInside, true);
      });

      test('CT-GEO-004: Пользователь вне геозоны', () async {
        // Arrange
        final shopLat = 55.7558;
        final shopLng = 37.6173;
        final userLat = 55.8000; // Far away
        final userLng = 37.7000;
        final radius = 500;

        // Act
        final isInside = mockGeofenceService.isInsideGeofence(
          userLat, userLng,
          shopLat, shopLng,
          radius,
        );

        // Assert
        expect(isInside, false);
      });

      test('CT-GEO-005: Push-уведомление при входе в геозону', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];
        final shopId = MockShopData.validShop['id'];

        // Act
        final result = await mockGeofenceService.checkAndNotify(
          clientPhone: clientPhone,
          shopId: shopId,
          userLat: 55.7558,
          userLng: 37.6173,
        );

        // Assert
        expect(result['notificationSent'], true);
      });

      test('CT-GEO-006: Cooldown 24 часа для повторных уведомлений', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];
        final shopId = MockShopData.validShop['id'];

        // First notification
        await mockGeofenceService.checkAndNotify(
          clientPhone: clientPhone,
          shopId: shopId,
          userLat: 55.7558,
          userLng: 37.6173,
        );

        // Act - try again
        final result = await mockGeofenceService.checkAndNotify(
          clientPhone: clientPhone,
          shopId: shopId,
          userLat: 55.7558,
          userLng: 37.6173,
        );

        // Assert
        expect(result['notificationSent'], false);
        expect(result['reason'], contains('cooldown'));
      });

      test('CT-GEO-007: Настраиваемый текст уведомления', () async {
        // Arrange
        final customText = 'Заходите к нам! Скидка 10% на все напитки!';
        await mockGeofenceService.updateSettings({
          'notificationText': customText,
        });

        // Act
        final settings = await mockGeofenceService.getSettings();

        // Assert
        expect(settings['notificationText'], customText);
      });

      test('CT-GEO-008: Включение/выключение геофенсинга', () async {
        // Act - disable
        await mockGeofenceService.updateSettings({'enabled': false});
        final result = await mockGeofenceService.checkAndNotify(
          clientPhone: MockClientData.validClient['phone'],
          shopId: MockShopData.validShop['id'],
          userLat: 55.7558,
          userLng: 37.6173,
        );

        // Assert
        expect(result['notificationSent'], false);
        expect(result['reason'], contains('disabled'));
      });

      test('CT-GEO-009: Изменение радиуса геозоны', () async {
        // Act
        await mockGeofenceService.updateSettings({'radius': 1000});
        final settings = await mockGeofenceService.getSettings();

        // Assert
        expect(settings['radius'], 1000);
      });

      test('CT-GEO-010: Статистика уведомлений', () async {
        // Arrange
        await mockGeofenceService.checkAndNotify(
          clientPhone: '79001111111',
          shopId: MockShopData.validShop['id'],
          userLat: 55.7558,
          userLng: 37.6173,
        );
        mockGeofenceService.resetCooldownForTesting('79002222222');
        await mockGeofenceService.checkAndNotify(
          clientPhone: '79002222222',
          shopId: MockShopData.validShop['id'],
          userLat: 55.7558,
          userLng: 37.6173,
        );

        // Act
        final stats = await mockGeofenceService.getStats();

        // Assert
        expect(stats['totalNotifications'], greaterThan(0));
      });
    });

    // ==================== ФОНОВАЯ ПРОВЕРКА ====================

    group('Background Check Tests', () {
      test('CT-GEO-011: Фоновая проверка каждые 15 минут', () async {
        // Act
        final config = await mockGeofenceService.getBackgroundConfig();

        // Assert
        expect(config['intervalMinutes'], 15);
      });

      test('CT-GEO-012: Проверка всех магазинов при обновлении позиции', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];
        final userLat = 55.7558;
        final userLng = 37.6173;

        // Act
        final result = await mockGeofenceService.checkAllShops(
          clientPhone: clientPhone,
          userLat: userLat,
          userLng: userLng,
        );

        // Assert
        expect(result['shopsChecked'], greaterThan(0));
      });
    });
  });
}

// ==================== MOCK SERVICES ====================

class MockShopsMapService {
  final List<Map<String, dynamic>> _shops = [
    {
      'id': 'shop_001',
      'name': 'Кофейня Центр',
      'address': 'ул. Центральная, 1',
      'latitude': 55.7558,
      'longitude': 37.6173,
      'workingHours': '08:00-22:00',
    },
    {
      'id': 'shop_002',
      'name': 'Кофейня Север',
      'address': 'ул. Северная, 10',
      'latitude': 55.8558,
      'longitude': 37.7173,
      'workingHours': '09:00-21:00',
    },
    {
      'id': 'shop_003',
      'name': 'Кофейня Юг',
      'address': 'ул. Южная, 5',
      'latitude': 55.6558,
      'longitude': 37.5173,
      'workingHours': '07:00-23:00',
    },
  ];

  Future<List<Map<String, dynamic>>> getShopsWithCoordinates() async {
    return _shops;
  }

  Future<List<Map<String, dynamic>>> getNearestShops(
    double userLat,
    double userLng, {
    int? limit,
  }) async {
    final shopsWithDistance = _shops.map((shop) {
      final distance = calculateDistance(
        userLat, userLng,
        shop['latitude'], shop['longitude'],
      );
      return {...shop, 'distance': distance};
    }).toList();

    shopsWithDistance.sort((a, b) =>
      (a['distance'] as double).compareTo(b['distance'] as double)
    );

    if (limit != null) {
      return shopsWithDistance.take(limit).toList();
    }
    return shopsWithDistance;
  }

  /// Haversine formula for calculating distance between two points
  double calculateDistance(
    double lat1, double lng1,
    double lat2, double lng2,
  ) {
    const R = 6371000; // Earth's radius in meters
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final deltaPhi = (lat2 - lat1) * pi / 180;
    final deltaLambda = (lng2 - lng1) * pi / 180;

    final a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
              cos(phi1) * cos(phi2) *
              sin(deltaLambda / 2) * sin(deltaLambda / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  void clear() {
    // Reset if needed
  }
}

class MockGeofenceService {
  Map<String, dynamic> _settings = {
    'radius': 500,
    'enabled': true,
    'notificationText': 'Вы рядом с нашей кофейней! Загляните на чашечку кофе!',
    'cooldownHours': 24,
  };

  final Map<String, DateTime> _lastNotifications = {};
  int _notificationCount = 0;

  Future<Map<String, dynamic>> getSettings() async {
    return _settings;
  }

  Future<void> updateSettings(Map<String, dynamic> updates) async {
    _settings = {..._settings, ...updates};
  }

  bool isInsideGeofence(
    double userLat, double userLng,
    double shopLat, double shopLng,
    int radius,
  ) {
    final distance = _calculateDistance(userLat, userLng, shopLat, shopLng);
    return distance <= radius;
  }

  double _calculateDistance(
    double lat1, double lng1,
    double lat2, double lng2,
  ) {
    const R = 6371000;
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final deltaPhi = (lat2 - lat1) * pi / 180;
    final deltaLambda = (lng2 - lng1) * pi / 180;

    final a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
              cos(phi1) * cos(phi2) *
              sin(deltaLambda / 2) * sin(deltaLambda / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  Future<Map<String, dynamic>> checkAndNotify({
    required String clientPhone,
    required String shopId,
    required double userLat,
    required double userLng,
  }) async {
    // Check if enabled
    if (!_settings['enabled']) {
      return {'notificationSent': false, 'reason': 'Geofencing disabled'};
    }

    // Check cooldown
    final key = '${clientPhone}_$shopId';
    final lastNotification = _lastNotifications[key];
    if (lastNotification != null) {
      final hoursSince = DateTime.now().difference(lastNotification).inHours;
      if (hoursSince < _settings['cooldownHours']) {
        return {'notificationSent': false, 'reason': 'cooldown active'};
      }
    }

    // Check if inside geofence (simplified - assume shop at default location)
    final shopLat = 55.7558;
    final shopLng = 37.6173;
    final isInside = isInsideGeofence(
      userLat, userLng,
      shopLat, shopLng,
      _settings['radius'],
    );

    if (!isInside) {
      return {'notificationSent': false, 'reason': 'Outside geofence'};
    }

    // Send notification
    _lastNotifications[key] = DateTime.now();
    _notificationCount++;

    return {
      'notificationSent': true,
      'text': _settings['notificationText'],
    };
  }

  Future<Map<String, dynamic>> getStats() async {
    return {
      'totalNotifications': _notificationCount,
    };
  }

  Future<Map<String, dynamic>> getBackgroundConfig() async {
    return {
      'intervalMinutes': 15,
      'enabled': _settings['enabled'],
    };
  }

  Future<Map<String, dynamic>> checkAllShops({
    required String clientPhone,
    required double userLat,
    required double userLng,
  }) async {
    // Simulate checking all shops
    return {
      'shopsChecked': 3,
      'notificationsSent': 0,
    };
  }

  void resetCooldownForTesting(String clientPhone) {
    _lastNotifications.removeWhere((key, _) => key.startsWith(clientPhone));
  }

  void clear() {
    _lastNotifications.clear();
    _notificationCount = 0;
    _settings = {
      'radius': 500,
      'enabled': true,
      'notificationText': 'Вы рядом с нашей кофейней!',
      'cooldownHours': 24,
    };
  }
}

import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P1 Тесты Рейтинга и Колеса Удачи для роли СОТРУДНИК
/// Покрывает: Расчёт рейтинга, нормализация, топ-3, прокрутки колеса
void main() {
  group('Rating & Fortune Wheel Tests (P1)', () {
    late MockRatingService mockRatingService;
    late MockFortuneWheelService mockWheelService;

    setUp(() async {
      mockWheelService = MockFortuneWheelService();
      mockRatingService = MockRatingService(mockWheelService);
    });

    tearDown(() async {
      mockRatingService.clear();
      mockWheelService.clear();
    });

    // ==================== РАСЧЁТ РЕЙТИНГА ====================

    group('Rating Calculation Tests', () {
      test('ET-RAT-001: Расчёт рейтинга с нормализацией по сменам', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final totalPoints = 70.5;
        final shiftsCount = 20;
        final referralPoints = 11.0;

        // Act
        final rating = mockRatingService.calculateNormalizedRating(
          totalPoints: totalPoints,
          shiftsCount: shiftsCount,
          referralPoints: referralPoints,
        );

        // Assert
        // Formula: (70.5 / 20) + 11 = 3.525 + 11 = 14.525
        expect(rating, closeTo(14.525, 0.001));
      });

      test('ET-RAT-002: Рейтинг с нулевыми сменами = 0', () async {
        // Arrange
        final totalPoints = 50.0;
        final shiftsCount = 0;
        final referralPoints = 5.0;

        // Act
        final rating = mockRatingService.calculateNormalizedRating(
          totalPoints: totalPoints,
          shiftsCount: shiftsCount,
          referralPoints: referralPoints,
        );

        // Assert
        expect(rating, referralPoints); // Only referral points when no shifts
      });

      test('ET-RAT-003: Рейтинг включает все 10 категорий эффективности', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = '2024-01';

        // Act
        final efficiency = await mockRatingService.calculateEfficiency(employeeId, month);

        // Assert
        expect(efficiency['breakdown'], isNotNull);
        expect(efficiency['breakdown'].keys.length, 10);
        expect(efficiency['breakdown'].containsKey('shifts'), true);
        expect(efficiency['breakdown'].containsKey('recount'), true);
        expect(efficiency['breakdown'].containsKey('envelope'), true);
        expect(efficiency['breakdown'].containsKey('attendance'), true);
        expect(efficiency['breakdown'].containsKey('reviews'), true);
        expect(efficiency['breakdown'].containsKey('rko'), true);
        expect(efficiency['breakdown'].containsKey('orders'), true);
        expect(efficiency['breakdown'].containsKey('productSearch'), true);
        expect(efficiency['breakdown'].containsKey('tests'), true);
        expect(efficiency['breakdown'].containsKey('tasks'), true);
      });

      test('ET-RAT-004: Рейтинг включает штрафы', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = '2024-01';

        // Act
        final efficiency = await mockRatingService.calculateEfficiency(employeeId, month);

        // Assert
        expect(efficiency['penalties'], isNotNull);
        expect(efficiency['penalties']['shift_missed_penalty'], isA<num>());
        expect(efficiency['penalties']['envelope_missed_penalty'], isA<num>());
      });

      test('ET-RAT-005: Рефералы с милестоунами', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final referralsCount = 7; // Should trigger milestone

        // Act
        final referralPoints = mockRatingService.calculateReferralPoints(
          referralsCount,
          basePoints: 1,
          milestoneThreshold: 5,
          milestonePoints: 5,
        );

        // Assert
        // 7 referrals * 1 point + 1 milestone (5 referrals) * 5 bonus = 7 + 5 = 12
        expect(referralPoints, 12.0);
      });

      test('ET-RAT-006: Сортировка сотрудников по рейтингу', () async {
        // Arrange
        final month = '2024-01';

        // Act
        final ratings = await mockRatingService.getAllRatings(month);

        // Assert
        for (var i = 0; i < ratings.length - 1; i++) {
          expect(
            ratings[i]['normalizedRating'] >= ratings[i + 1]['normalizedRating'],
            true,
            reason: 'Ratings should be sorted descending',
          );
        }
      });

      test('ET-RAT-007: Позиции присваиваются корректно', () async {
        // Arrange
        final month = '2024-01';

        // Act
        final ratings = await mockRatingService.getAllRatings(month);

        // Assert
        for (var i = 0; i < ratings.length; i++) {
          expect(ratings[i]['position'], i + 1);
        }
      });

      test('ET-RAT-008: История рейтинга за 3 месяца', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];

        // Act
        final history = await mockRatingService.getEmployeeRatingHistory(
          employeeId,
          months: 3,
        );

        // Assert
        expect(history.length, lessThanOrEqualTo(3));
        for (final entry in history) {
          expect(entry['month'], isNotNull);
          expect(entry['position'], isNotNull);
        }
      });

      test('ET-RAT-009: Кэширование рейтингов завершённых месяцев', () async {
        // Arrange
        final month = '2024-01'; // Past month

        // Act
        final ratings1 = await mockRatingService.getAllRatings(month);
        final ratings2 = await mockRatingService.getAllRatings(month);

        // Assert
        expect(mockRatingService.cacheHits, 1); // Second call should hit cache
      });
    });

    // ==================== ТОП-3 И ПРОКРУТКИ ====================

    group('Top-3 Awards Tests', () {
      test('ET-RAT-010: Топ-1 получает 2 прокрутки', () async {
        // Arrange
        // Use current month to avoid expiration
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';

        // Act
        await mockRatingService.calculateAndAwardSpins(month);
        final spins = await mockWheelService.getSpins(
          MockEmployeeData.topEmployee['id'],
          month,
        );

        // Assert
        expect(spins['available'], 2);
      });

      test('ET-RAT-011: Топ-2 получает 1 прокрутку', () async {
        // Arrange
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';

        // Act
        await mockRatingService.calculateAndAwardSpins(month);
        final spins = await mockWheelService.getSpins(
          MockEmployeeData.secondEmployee['id'],
          month,
        );

        // Assert
        expect(spins['available'], 1);
      });

      test('ET-RAT-012: Топ-3 получает 1 прокрутку', () async {
        // Arrange
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';

        // Act
        await mockRatingService.calculateAndAwardSpins(month);
        final spins = await mockWheelService.getSpins(
          MockEmployeeData.thirdEmployee['id'],
          month,
        );

        // Assert
        expect(spins['available'], 1);
      });

      test('ET-RAT-013: Вне топ-3 не получает прокрутки', () async {
        // Arrange
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';

        // Act
        await mockRatingService.calculateAndAwardSpins(month);
        final spins = await mockWheelService.getSpins(
          MockEmployeeData.validEmployee['id'],
          month,
        );

        // Assert
        expect(spins['available'], 0);
      });

      test('ET-RAT-014: Срок истечения прокруток - конец следующего месяца', () async {
        // Arrange
        final now = DateTime.now();
        final earnedMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        final employeeId = MockEmployeeData.topEmployee['id'];

        // Act
        await mockRatingService.calculateAndAwardSpins(earnedMonth);
        final spins = await mockWheelService.getSpins(employeeId, earnedMonth);

        // Assert
        final expiresAt = DateTime.parse(spins['expiresAt']);
        expect(expiresAt.month, now.month + 1 > 12 ? 1 : now.month + 1); // Next month end
        expect(expiresAt.year, now.month + 1 > 12 ? now.year + 1 : now.year);
      });
    });

    // ==================== КОЛЕСО УДАЧИ ====================

    group('Fortune Wheel Tests', () {
      test('ET-WHL-001: Получение настроек секторов (15 штук)', () async {
        // Act
        final settings = await mockWheelService.getSettings();

        // Assert
        expect(settings['sectors'].length, 15);
      });

      test('ET-WHL-002: Сумма вероятностей = 100%', () async {
        // Act
        final settings = await mockWheelService.getSettings();

        // Assert
        final sectors = settings['sectors'] as List<Map<String, dynamic>>;
        double totalProbability = 0.0;
        for (final sector in sectors) {
          totalProbability += sector['probability'] as double;
        }
        expect(totalProbability, closeTo(100.0, 0.01));
      });

      test('ET-WHL-003: Прокрутка колеса уменьшает доступные прокрутки', () async {
        // Arrange
        final employeeId = MockEmployeeData.topEmployee['id'];
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        await mockRatingService.calculateAndAwardSpins(month);

        // Act
        final spinsBefore = await mockWheelService.getSpins(employeeId, month);
        await mockWheelService.spin(employeeId, month);
        final spinsAfter = await mockWheelService.getSpins(employeeId, month);

        // Assert
        expect(spinsAfter['available'], spinsBefore['available'] - 1);
      });

      test('ET-WHL-004: Невозможность прокрутки при 0 прокрутках', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';

        // Act
        final result = await mockWheelService.spin(employeeId, month);

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('no spins'));
      });

      test('ET-WHL-005: Результат прокрутки сохраняется в историю', () async {
        // Arrange
        final employeeId = MockEmployeeData.topEmployee['id'];
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        await mockRatingService.calculateAndAwardSpins(month);

        // Act
        final spinResult = await mockWheelService.spin(employeeId, month);
        final history = await mockWheelService.getHistory(month);

        // Assert
        expect(history.any((h) => h['id'] == spinResult['historyId']), true);
      });

      test('ET-WHL-006: Выбор сектора по вероятности', () async {
        // Arrange
        final settings = await mockWheelService.getSettings();
        final results = <String, int>{};

        // Act - simulate many spins
        for (var i = 0; i < 1000; i++) {
          final sector = mockWheelService.selectSectorByProbability(
            settings['sectors'],
          );
          results[sector['label']] = (results[sector['label']] ?? 0) + 1;
        }

        // Assert - each sector should be selected at least once
        for (final sector in settings['sectors']) {
          expect(
            results.containsKey(sector['label']),
            true,
            reason: 'Sector ${sector['label']} should be selected at least once',
          );
        }
      });

      test('ET-WHL-007: Истёкшие прокрутки не доступны', () async {
        // Arrange
        final employeeId = MockEmployeeData.topEmployee['id'];
        final expiredMonth = '2023-10'; // Old month

        // Act
        final spins = await mockWheelService.getSpins(employeeId, expiredMonth);

        // Assert
        expect(spins['expired'], true);
        expect(spins['available'], 0);
      });

      test('ET-WHL-008: Админ отмечает приз как выданный', () async {
        // Arrange
        final employeeId = MockEmployeeData.topEmployee['id'];
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        await mockRatingService.calculateAndAwardSpins(month);
        final spinResult = await mockWheelService.spin(employeeId, month);

        // Act
        final result = await mockWheelService.markPrizeProcessed(
          spinResult['historyId'],
        );

        // Assert
        expect(result['success'], true);
        expect(result['processed'], true);
      });

      test('ET-WHL-009: История прокруток за месяц', () async {
        // Arrange
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        await mockRatingService.calculateAndAwardSpins(month);
        await mockWheelService.spin(MockEmployeeData.topEmployee['id'], month);

        // Act
        final history = await mockWheelService.getHistory(month);

        // Assert
        expect(history, isA<List>());
        for (final entry in history) {
          expect(entry['employeeId'], isNotNull);
          expect(entry['sector'], isNotNull);
          expect(entry['timestamp'], isNotNull);
        }
      });

      test('ET-WHL-010: Анимация колеса корректна', () async {
        // Arrange
        final targetSector = 5;
        final sectors = 15;

        // Act
        final rotations = mockWheelService.calculateRotation(
          targetSector,
          sectors,
        );

        // Assert
        expect(rotations['totalRotations'], greaterThanOrEqualTo(3));
        expect(rotations['finalAngle'], greaterThanOrEqualTo(0));
        expect(rotations['finalAngle'], lessThan(360));
      });
    });

    // ==================== СТРАНИЦА "МОЙ РЕЙТИНГ" ====================

    group('My Rating Page Tests', () {
      test('ET-RAT-015: Отображение позиции сотрудника', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';

        // Act
        final myRating = await mockRatingService.getEmployeeRating(
          employeeId,
          month,
        );

        // Assert
        expect(myRating['position'], isA<int>());
        expect(myRating['position'], greaterThan(0));
      });

      test('ET-RAT-016: Отображение breakdown по категориям', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';

        // Act
        final myRating = await mockRatingService.getEmployeeRating(
          employeeId,
          month,
        );

        // Assert
        expect(myRating['breakdown'], isNotNull);
        expect(myRating['breakdown']['shifts'], isA<num>());
      });

      test('ET-RAT-017: Сравнение с топ-3', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final now = DateTime.now();
        final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';

        // Act
        final comparison = await mockRatingService.getTopComparison(
          employeeId,
          month,
        );

        // Assert
        expect(comparison['top3'], isA<List>());
        expect(comparison['top3'].length, 3);
        expect(comparison['myPosition'], isA<int>());
      });
    });
  });
}

// ==================== MOCK SERVICES ====================

class MockRatingService {
  final Map<String, List<Map<String, dynamic>>> _cache = {};
  int cacheHits = 0;
  final MockFortuneWheelService _wheelService;

  MockRatingService(this._wheelService);

  double calculateNormalizedRating({
    required double totalPoints,
    required int shiftsCount,
    required double referralPoints,
  }) {
    if (shiftsCount == 0) return referralPoints;
    return (totalPoints / shiftsCount) + referralPoints;
  }

  double calculateReferralPoints(
    int referralsCount, {
    required int basePoints,
    required int milestoneThreshold,
    required int milestonePoints,
  }) {
    final baseTotal = referralsCount * basePoints.toDouble();
    final milestones = referralsCount ~/ milestoneThreshold;
    final milestoneTotal = milestones * milestonePoints.toDouble();
    return baseTotal + milestoneTotal;
  }

  Future<Map<String, dynamic>> calculateEfficiency(String employeeId, String month) async {
    return {
      'employeeId': employeeId,
      'month': month,
      'total': 70.5,
      'breakdown': {
        'shifts': 15.0,
        'recount': 10.0,
        'envelope': 8.0,
        'attendance': 12.0,
        'reviews': 5.0,
        'rko': 3.0,
        'orders': 7.0,
        'productSearch': 4.0,
        'tests': 3.5,
        'tasks': 3.0,
      },
      'penalties': {
        'shift_missed_penalty': -5.0,
        'envelope_missed_penalty': 0.0,
        'rko_missed_penalty': 0.0,
      },
    };
  }

  Future<List<Map<String, dynamic>>> getAllRatings(String month) async {
    if (_cache.containsKey(month)) {
      cacheHits++;
      return _cache[month]!;
    }

    final ratings = <Map<String, dynamic>>[
      {'employeeId': 'emp_top', 'name': 'Топ Сотрудник', 'normalizedRating': 14.525, 'position': 1},
      {'employeeId': 'emp_second', 'name': 'Второй Сотрудник', 'normalizedRating': 13.0, 'position': 2},
      {'employeeId': 'emp_third', 'name': 'Третий Сотрудник', 'normalizedRating': 8.78, 'position': 3},
      {'employeeId': 'emp_001', 'name': 'Тестовый Сотрудник', 'normalizedRating': 7.5, 'position': 4},
    ];

    _cache[month] = ratings;
    return ratings;
  }

  Future<List<Map<String, dynamic>>> getEmployeeRatingHistory(
    String employeeId, {
    required int months,
  }) async {
    return [
      {'month': '2024-01', 'position': 4, 'normalizedRating': 7.5},
      {'month': '2023-12', 'position': 3, 'normalizedRating': 9.2},
      {'month': '2023-11', 'position': 5, 'normalizedRating': 6.8},
    ].take(months).toList();
  }

  Future<void> calculateAndAwardSpins(String month) async {
    final ratings = await getAllRatings(month);
    // Award spins to top 3
    for (var i = 0; i < ratings.length && i < 3; i++) {
      final employeeId = ratings[i]['employeeId'] as String;
      final spins = i == 0 ? 2 : 1; // Top 1 gets 2, others get 1
      _wheelService.awardSpins(employeeId, month, spins);
    }
  }

  Future<Map<String, dynamic>> getEmployeeRating(String employeeId, String month) async {
    final ratings = await getAllRatings(month);
    Map<String, dynamic>? found;
    for (final r in ratings) {
      if (r['employeeId'] == employeeId) {
        found = r;
        break;
      }
    }
    final rating = found ?? <String, dynamic>{'position': ratings.length + 1};
    // Add breakdown if not present
    if (rating['breakdown'] == null) {
      rating['breakdown'] = {
        'shifts': 15.0,
        'recount': 10.0,
        'envelope': 8.0,
        'attendance': 12.0,
        'reviews': 5.0,
        'rko': 3.0,
        'orders': 7.0,
        'productSearch': 4.0,
        'tests': 3.5,
        'tasks': 3.0,
      };
    }
    return rating;
  }

  Future<Map<String, dynamic>> getTopComparison(String employeeId, String month) async {
    final ratings = await getAllRatings(month);
    Map<String, dynamic>? myRating;
    for (final r in ratings) {
      if (r['employeeId'] == employeeId) {
        myRating = r;
        break;
      }
    }
    myRating ??= <String, dynamic>{'position': ratings.length + 1};

    return {
      'top3': ratings.take(3).toList(),
      'myPosition': myRating['position'],
    };
  }

  void clear() {
    _cache.clear();
    cacheHits = 0;
  }
}

class MockFortuneWheelService {
  final Map<String, Map<String, int>> _spins = {};
  final List<Map<String, dynamic>> _history = [];
  int _randomSeed = DateTime.now().millisecondsSinceEpoch;

  Future<Map<String, dynamic>> getSettings() async {
    final sectors = <Map<String, dynamic>>[];
    for (var i = 0; i < 15; i++) {
      sectors.add({
        'label': 'Приз ${i + 1}',
        'probability': 100.0 / 15,
        'color': '#${(i * 17 % 256).toRadixString(16).padLeft(2, '0')}FF00',
      });
    }
    return {'sectors': sectors};
  }

  Future<Map<String, dynamic>> getSpins(String employeeId, String month) async {
    // Check expiration
    final monthDate = DateTime.parse('$month-01');
    final now = DateTime.now();
    final expirationDate = DateTime(monthDate.year, monthDate.month + 2, 0);

    if (now.isAfter(expirationDate)) {
      return {'available': 0, 'expired': true, 'expiresAt': expirationDate.toIso8601String()};
    }

    final key = '$employeeId-$month';
    final available = _spins[key]?['available'] ?? 0;
    return {
      'available': available,
      'expired': false,
      'expiresAt': expirationDate.toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> spin(String employeeId, String month) async {
    final key = '$employeeId-$month';
    final available = _spins[key]?['available'] ?? 0;

    if (available <= 0) {
      return {'success': false, 'error': 'no spins available'};
    }

    _spins[key] = {'available': available - 1};

    final settings = await getSettings();
    final sector = selectSectorByProbability(settings['sectors']);
    final historyId = 'hist_${DateTime.now().millisecondsSinceEpoch}';

    _history.add({
      'id': historyId,
      'employeeId': employeeId,
      'month': month,
      'sector': sector['label'],
      'timestamp': DateTime.now().toIso8601String(),
      'processed': false,
    });

    return {'success': true, 'sector': sector, 'historyId': historyId};
  }

  Map<String, dynamic> selectSectorByProbability(List<dynamic> sectors) {
    // Use a simple LCG random generator for testing
    _randomSeed = ((_randomSeed * 1103515245 + 12345) & 0x7fffffff);
    final random = (_randomSeed % 100).toDouble();
    double cumulative = 0;

    for (final sector in sectors) {
      cumulative += sector['probability'] as double;
      if (random < cumulative) {
        return sector as Map<String, dynamic>;
      }
    }
    return sectors.last as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getHistory(String month) async {
    return _history.where((h) => h['month'] == month).toList();
  }

  Future<Map<String, dynamic>> markPrizeProcessed(String historyId) async {
    final index = _history.indexWhere((h) => h['id'] == historyId);
    if (index >= 0) {
      _history[index]['processed'] = true;
      return {'success': true, 'processed': true};
    }
    return {'success': false, 'error': 'Not found'};
  }

  Map<String, dynamic> calculateRotation(int targetSector, int totalSectors) {
    final sectorAngle = 360.0 / totalSectors;
    final baseRotations = 3 + (DateTime.now().millisecond % 3);
    final finalAngle = targetSector * sectorAngle;

    return {
      'totalRotations': baseRotations,
      'finalAngle': finalAngle,
      'totalAngle': baseRotations * 360 + finalAngle,
    };
  }

  void awardSpins(String employeeId, String month, int count) {
    final key = '$employeeId-$month';
    _spins[key] = {'available': count};
  }

  void clear() {
    _spins.clear();
    _history.clear();
  }
}

// ==================== MOCK DATA ====================

class MockEmployeeData {
  static const Map<String, dynamic> validEmployee = {
    'id': 'emp_001',
    'name': 'Тестовый Сотрудник',
    'phone': '79001234567',
    'isAdmin': false,
  };

  static const Map<String, dynamic> topEmployee = {
    'id': 'emp_top',
    'name': 'Топ Сотрудник',
    'phone': '79001111111',
    'isAdmin': false,
  };

  static const Map<String, dynamic> secondEmployee = {
    'id': 'emp_second',
    'name': 'Второй Сотрудник',
    'phone': '79002222222',
    'isAdmin': false,
  };

  static const Map<String, dynamic> thirdEmployee = {
    'id': 'emp_third',
    'name': 'Третий Сотрудник',
    'phone': '79003333333',
    'isAdmin': false,
  };
}

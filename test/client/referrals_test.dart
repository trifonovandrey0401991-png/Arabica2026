import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P2 Тесты реферальной системы для роли КЛИЕНТ/СОТРУДНИК
/// Покрывает: Приглашения, награды, милестоуны
void main() {
  group('Referral System Tests (P2)', () {
    late MockReferralService mockReferralService;

    setUp(() async {
      mockReferralService = MockReferralService();
    });

    tearDown(() async {
      mockReferralService.clear();
    });

    // ==================== СОЗДАНИЕ ПРИГЛАШЕНИЙ ====================

    group('Referral Creation Tests', () {
      test('CT-REF-001: Генерация реферального кода', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];

        // Act
        final result = await mockReferralService.generateCode(employeeId);

        // Assert
        expect(result['success'], true);
        expect(result['code'], isNotEmpty);
        expect(result['code'].length, greaterThanOrEqualTo(6));
      });

      test('CT-REF-002: Код уникален для сотрудника', () async {
        // Arrange
        final code1 = await mockReferralService.generateCode('emp_001');
        final code2 = await mockReferralService.generateCode('emp_002');

        // Assert
        expect(code1['code'], isNot(equals(code2['code'])));
      });

      test('CT-REF-003: Применение реферального кода', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final codeResult = await mockReferralService.generateCode(employeeId);
        final code = codeResult['code'];
        final clientPhone = '79001234567';

        // Act
        final result = await mockReferralService.applyCode(clientPhone, code);

        // Assert
        expect(result['success'], true);
        expect(result['referral']['referrerId'], employeeId);
        expect(result['referral']['clientPhone'], clientPhone);
      });

      test('CT-REF-004: Нельзя использовать код повторно тем же клиентом', () async {
        // Arrange
        final codeResult = await mockReferralService.generateCode(MockEmployeeData.validEmployee['id']);
        final code = codeResult['code'];
        final clientPhone = '79001234567';
        await mockReferralService.applyCode(clientPhone, code);

        // Act
        final result = await mockReferralService.applyCode(clientPhone, code);

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('already'));
      });

      test('CT-REF-005: Невалидный код', () async {
        // Act
        final result = await mockReferralService.applyCode('79001234567', 'INVALID');

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('not found'));
      });
    });

    // ==================== НАГРАДЫ ====================

    group('Reward Tests', () {
      test('CT-REF-006: Базовые баллы за реферала', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final codeResult = await mockReferralService.generateCode(employeeId);
        await mockReferralService.applyCode('79001111111', codeResult['code']);

        // Act
        final points = await mockReferralService.getEmployeePoints(employeeId);

        // Assert
        expect(points, greaterThan(0));
      });

      test('CT-REF-007: Накопление баллов за рефералов', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final codeResult = await mockReferralService.generateCode(employeeId);
        final code = codeResult['code'];

        // Add 5 referrals
        for (var i = 0; i < 5; i++) {
          await mockReferralService.applyCode('7900111111$i', code);
        }

        // Act
        final points = await mockReferralService.getEmployeePoints(employeeId);

        // Assert
        expect(points, greaterThanOrEqualTo(5)); // At least 1 point per referral
      });

      test('CT-REF-008: Бонус клиенту за использование кода', () async {
        // Arrange
        final codeResult = await mockReferralService.generateCode(MockEmployeeData.validEmployee['id']);
        final clientPhone = '79001234567';

        // Act
        final result = await mockReferralService.applyCode(clientPhone, codeResult['code']);

        // Assert
        expect(result['clientBonus'], isNotNull);
        expect(result['clientBonus'], greaterThan(0));
      });
    });

    // ==================== МИЛЕСТОУНЫ ====================

    group('Milestone Tests', () {
      test('CT-REF-009: Достижение милестоуна (5 рефералов)', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final codeResult = await mockReferralService.generateCode(employeeId);
        final code = codeResult['code'];

        // Add 5 referrals
        for (var i = 0; i < 5; i++) {
          await mockReferralService.applyCode('7900111111$i', code);
        }

        // Act
        final milestones = await mockReferralService.getAchievedMilestones(employeeId);

        // Assert
        expect(milestones.any((m) => m['threshold'] == 5), true);
      });

      test('CT-REF-010: Бонус за милестоун', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final codeResult = await mockReferralService.generateCode(employeeId);
        final code = codeResult['code'];

        final pointsBefore = await mockReferralService.getEmployeePoints(employeeId);

        // Add 5 referrals to hit milestone
        for (var i = 0; i < 5; i++) {
          await mockReferralService.applyCode('7900222222$i', code);
        }

        // Act
        final pointsAfter = await mockReferralService.getEmployeePoints(employeeId);

        // Assert
        // Should have base points + milestone bonus
        expect(pointsAfter, greaterThan(pointsBefore + 5));
      });

      test('CT-REF-011: Несколько милестоунов (5, 10, 25)', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final codeResult = await mockReferralService.generateCode(employeeId);
        final code = codeResult['code'];

        // Add 10 referrals
        for (var i = 0; i < 10; i++) {
          await mockReferralService.applyCode('7900333333$i', code);
        }

        // Act
        final milestones = await mockReferralService.getAchievedMilestones(employeeId);

        // Assert
        expect(milestones.length, greaterThanOrEqualTo(2)); // 5 and 10
      });
    });

    // ==================== СТАТИСТИКА ====================

    group('Statistics Tests', () {
      test('CT-REF-012: Количество приглашённых', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final codeResult = await mockReferralService.generateCode(employeeId);
        final code = codeResult['code'];

        for (var i = 0; i < 7; i++) {
          await mockReferralService.applyCode('7900444444$i', code);
        }

        // Act
        final stats = await mockReferralService.getStats(employeeId);

        // Assert
        expect(stats['totalReferrals'], 7);
      });

      test('CT-REF-013: История приглашений', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final codeResult = await mockReferralService.generateCode(employeeId);
        final code = codeResult['code'];

        await mockReferralService.applyCode('79005555551', code);
        await mockReferralService.applyCode('79005555552', code);

        // Act
        final history = await mockReferralService.getHistory(employeeId);

        // Assert
        expect(history.length, 2);
        expect(history.every((h) => h['referrerId'] == employeeId), true);
      });

      test('CT-REF-014: Рейтинг по рефералам', () async {
        // Arrange
        // Employee 1: 10 referrals
        final code1 = await mockReferralService.generateCode('emp_001');
        for (var i = 0; i < 10; i++) {
          await mockReferralService.applyCode('7900600000$i', code1['code']);
        }

        // Employee 2: 5 referrals
        final code2 = await mockReferralService.generateCode('emp_002');
        for (var i = 0; i < 5; i++) {
          await mockReferralService.applyCode('7900700000$i', code2['code']);
        }

        // Act
        final leaderboard = await mockReferralService.getLeaderboard();

        // Assert
        expect(leaderboard.first['employeeId'], 'emp_001');
        expect(leaderboard[1]['employeeId'], 'emp_002');
      });
    });

    // ==================== ИНТЕГРАЦИЯ С РЕЙТИНГОМ ====================

    group('Rating Integration Tests', () {
      test('CT-REF-015: Баллы рефералов в эффективности', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = DateTime.now().toIso8601String().substring(0, 7);
        final codeResult = await mockReferralService.generateCode(employeeId);

        for (var i = 0; i < 3; i++) {
          await mockReferralService.applyCode('7900800000$i', codeResult['code']);
        }

        // Act
        final efficiencyPoints = await mockReferralService.getEfficiencyPoints(
          employeeId,
          month,
        );

        // Assert
        expect(efficiencyPoints, greaterThan(0));
      });

      test('CT-REF-016: Отдельный подсчёт для колеса удачи', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final codeResult = await mockReferralService.generateCode(employeeId);

        for (var i = 0; i < 7; i++) {
          await mockReferralService.applyCode('7900900000$i', codeResult['code']);
        }

        // Act
        final ratingPoints = await mockReferralService.getRatingPoints(employeeId);

        // Assert
        expect(ratingPoints, greaterThan(0));
        // Should include milestone bonuses
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockReferralService {
  final Map<String, String> _codes = {}; // employeeId -> code
  final List<Map<String, dynamic>> _referrals = [];
  final int _basePoints = 1;
  final int _milestoneBonus = 3;
  final List<int> _milestones = [5, 10, 25, 50, 100];
  int _codeCounter = 0;

  Future<Map<String, dynamic>> generateCode(String employeeId) async {
    if (_codes.containsKey(employeeId)) {
      return {'success': true, 'code': _codes[employeeId]};
    }

    _codeCounter++;
    final code = 'REF${_codeCounter.toString().padLeft(4, '0')}${employeeId.hashCode.abs() % 1000}';
    _codes[employeeId] = code;

    return {'success': true, 'code': code};
  }

  Future<Map<String, dynamic>> applyCode(String clientPhone, String code) async {
    // Find referrer
    String? referrerId;
    for (final entry in _codes.entries) {
      if (entry.value == code) {
        referrerId = entry.key;
        break;
      }
    }

    if (referrerId == null) {
      return {'success': false, 'error': 'Code not found'};
    }

    // Check if client already used a referral
    if (_referrals.any((r) => r['clientPhone'] == clientPhone)) {
      return {'success': false, 'error': 'Client already used a referral code'};
    }

    final referral = {
      'id': 'ref_${_referrals.length + 1}',
      'referrerId': referrerId,
      'clientPhone': clientPhone,
      'code': code,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _referrals.add(referral);

    return {
      'success': true,
      'referral': referral,
      'clientBonus': 50, // 50 bonus points for client
    };
  }

  Future<int> getEmployeePoints(String employeeId) async {
    final count = _referrals.where((r) => r['referrerId'] == employeeId).length;
    int points = count * _basePoints;

    // Add milestone bonuses
    for (final milestone in _milestones) {
      if (count >= milestone) {
        points += _milestoneBonus;
      }
    }

    return points;
  }

  Future<List<Map<String, dynamic>>> getAchievedMilestones(String employeeId) async {
    final count = _referrals.where((r) => r['referrerId'] == employeeId).length;
    return _milestones
        .where((m) => count >= m)
        .map((m) => {'threshold': m, 'bonus': _milestoneBonus})
        .toList();
  }

  Future<Map<String, dynamic>> getStats(String employeeId) async {
    final count = _referrals.where((r) => r['referrerId'] == employeeId).length;
    return {
      'totalReferrals': count,
      'totalPoints': await getEmployeePoints(employeeId),
    };
  }

  Future<List<Map<String, dynamic>>> getHistory(String employeeId) async {
    return _referrals.where((r) => r['referrerId'] == employeeId).toList();
  }

  Future<List<Map<String, dynamic>>> getLeaderboard() async {
    final counts = <String, int>{};
    for (final r in _referrals) {
      final empId = r['referrerId'] as String;
      counts[empId] = (counts[empId] ?? 0) + 1;
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return entries.map((e) => {
      'employeeId': e.key,
      'count': e.value,
    }).toList();
  }

  Future<int> getEfficiencyPoints(String employeeId, String month) async {
    // For efficiency, only count referrals from this month
    final monthReferrals = _referrals.where((r) =>
      r['referrerId'] == employeeId &&
      (r['createdAt'] as String).startsWith(month)
    ).length;
    return monthReferrals * _basePoints;
  }

  Future<int> getRatingPoints(String employeeId) async {
    return await getEmployeePoints(employeeId);
  }

  void clear() {
    _codes.clear();
    _referrals.clear();
    _codeCounter = 0;
  }
}

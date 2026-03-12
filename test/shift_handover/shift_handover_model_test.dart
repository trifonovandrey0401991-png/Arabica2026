// Shift Handover Model Tests
// Tests for ShiftHandoverReport and ShiftHandoverAnswer models

import 'package:flutter_test/flutter_test.dart';
import 'package:arabica_app/features/shift_handover/models/shift_handover_report_model.dart';
import 'package:arabica_app/features/shift_handover/models/pending_shift_handover_report_model.dart';

void main() {
  group('ShiftHandoverAnswer model', () {
    test('fromJson parses valid data correctly', () {
      final json = {
        'question': 'Витрина чистая?',
        'textAnswer': 'Да',
        'numberAnswer': 3.5,
        'photoPath': '/local/photo.jpg',
        'photoUrl': 'https://server.com/photo.jpg',
        'photoDriveId': 'drive_123',
        'referencePhotoUrl': 'https://server.com/ref.jpg',
      };

      final answer = ShiftHandoverAnswer.fromJson(json);

      expect(answer.question, 'Витрина чистая?');
      expect(answer.textAnswer, 'Да');
      expect(answer.numberAnswer, 3.5);
      expect(answer.photoPath, '/local/photo.jpg');
      expect(answer.photoUrl, 'https://server.com/photo.jpg');
      expect(answer.photoDriveId, 'drive_123');
      expect(answer.referencePhotoUrl, 'https://server.com/ref.jpg');
    });

    test('fromJson handles missing optional fields', () {
      final json = {'question': 'Test?'};
      final answer = ShiftHandoverAnswer.fromJson(json);

      expect(answer.question, 'Test?');
      expect(answer.textAnswer, isNull);
      expect(answer.numberAnswer, isNull);
      expect(answer.photoPath, isNull);
      expect(answer.photoUrl, isNull);
      expect(answer.photoDriveId, isNull);
      expect(answer.referencePhotoUrl, isNull);
    });

    test('fromJson defaults question to empty string when null', () {
      final answer = ShiftHandoverAnswer.fromJson({});
      expect(answer.question, '');
    });

    test('fromJson converts int numberAnswer to double', () {
      final json = {'question': 'Count', 'numberAnswer': 7};
      final answer = ShiftHandoverAnswer.fromJson(json);
      expect(answer.numberAnswer, 7.0);
      expect(answer.numberAnswer, isA<double>());
    });

    test('toJson serializes all fields', () {
      final answer = ShiftHandoverAnswer(
        question: 'Q?',
        textAnswer: 'A',
        numberAnswer: 2.0,
        photoPath: '/p',
        photoUrl: 'https://url',
        photoDriveId: 'drv',
        referencePhotoUrl: 'https://ref',
      );

      final json = answer.toJson();

      expect(json['question'], 'Q?');
      expect(json['textAnswer'], 'A');
      expect(json['numberAnswer'], 2.0);
      expect(json['photoPath'], '/p');
      expect(json['photoUrl'], 'https://url');
      expect(json['photoDriveId'], 'drv');
      expect(json['referencePhotoUrl'], 'https://ref');
    });

    test('toJson omits photoDriveId and referencePhotoUrl when null', () {
      final answer = ShiftHandoverAnswer(question: 'Q');
      final json = answer.toJson();

      expect(json.containsKey('photoDriveId'), isFalse);
      expect(json.containsKey('referencePhotoUrl'), isFalse);
      // photoUrl and textAnswer are included even when null
      expect(json.containsKey('photoUrl'), isTrue);
    });

    test('toJson/fromJson roundtrip preserves data', () {
      final original = ShiftHandoverAnswer(
        question: 'Проверка',
        textAnswer: 'ok',
        numberAnswer: 10.0,
        photoPath: '/path',
        photoUrl: 'https://url',
        photoDriveId: 'drive',
        referencePhotoUrl: 'https://ref',
      );

      final restored = ShiftHandoverAnswer.fromJson(original.toJson());

      expect(restored.question, original.question);
      expect(restored.textAnswer, original.textAnswer);
      expect(restored.numberAnswer, original.numberAnswer);
      expect(restored.photoPath, original.photoPath);
      expect(restored.photoUrl, original.photoUrl);
      expect(restored.photoDriveId, original.photoDriveId);
      expect(restored.referencePhotoUrl, original.referencePhotoUrl);
    });
  });

  group('ShiftHandoverReport model', () {
    Map<String, dynamic> _validJson() => {
      'id': 'handover_001',
      'employeeName': 'Анна Сидорова',
      'employeePhone': '79001234567',
      'shopAddress': 'ул. Северная, 10',
      'createdAt': '2026-03-10T10:00:00.000Z',
      'answers': [
        {'question': 'Чистота зала', 'textAnswer': 'Хорошо'},
        {'question': 'Остатки молока', 'numberAnswer': 5},
      ],
      'isSynced': true,
      'confirmedAt': '2026-03-10T14:00:00.000Z',
      'rating': 9,
      'confirmedByAdmin': 'Админ',
      'status': 'confirmed',
      'expiredAt': null,
      'aiVerificationPassed': true,
      'aiVerificationSkipped': false,
      'aiShortages': [
        {'productId': 'p1', 'productName': 'Молоко'}
      ],
      'aiBboxAnnotations': {'p1': 'ann_001'},
    };

    group('fromJson', () {
      test('parses valid complete data', () {
        final report = ShiftHandoverReport.fromJson(_validJson());

        expect(report.id, 'handover_001');
        expect(report.employeeName, 'Анна Сидорова');
        expect(report.employeePhone, '79001234567');
        expect(report.shopAddress, 'ул. Северная, 10');
        expect(report.answers.length, 2);
        expect(report.answers[0].question, 'Чистота зала');
        expect(report.answers[1].numberAnswer, 5.0);
        expect(report.isSynced, true);
        expect(report.rating, 9);
        expect(report.confirmedByAdmin, 'Админ');
        expect(report.status, 'confirmed');
        expect(report.aiVerificationPassed, true);
        expect(report.aiVerificationSkipped, false);
        expect(report.aiShortages, isNotNull);
        expect(report.aiShortages!.length, 1);
        expect(report.aiBboxAnnotations, isNotNull);
        expect(report.aiBboxAnnotations!['p1'], 'ann_001');
      });

      test('handles missing optional fields with defaults', () {
        final json = {
          'createdAt': '2026-03-10T10:00:00.000Z',
        };

        final report = ShiftHandoverReport.fromJson(json);

        expect(report.id, '');
        expect(report.employeeName, '');
        expect(report.employeePhone, isNull);
        expect(report.shopAddress, '');
        expect(report.answers, isEmpty);
        expect(report.isSynced, false);
        expect(report.confirmedAt, isNull);
        expect(report.rating, isNull);
        expect(report.confirmedByAdmin, isNull);
        expect(report.status, isNull);
        expect(report.expiredAt, isNull);
        expect(report.aiVerificationPassed, isNull);
        expect(report.aiVerificationSkipped, isNull);
        expect(report.aiShortages, isNull);
        expect(report.aiBboxAnnotations, isNull);
      });

      test('handles null answers list', () {
        final json = {
          'createdAt': '2026-03-10T10:00:00.000Z',
          'answers': null,
        };

        final report = ShiftHandoverReport.fromJson(json);
        expect(report.answers, isEmpty);
      });

      test('parses UTC date string with Z suffix', () {
        final json = {
          'createdAt': '2026-03-10T10:00:00.000Z',
        };

        final report = ShiftHandoverReport.fromJson(json);
        // _parseDateTime converts to local time, so we verify it parsed
        expect(report.createdAt, isNotNull);
      });

      test('parses date string without Z suffix (treats as UTC)', () {
        final json = {
          'createdAt': '2026-03-10T10:00:00.000',
        };

        final report = ShiftHandoverReport.fromJson(json);
        // _parseDateTime adds Z if missing, then converts to local
        expect(report.createdAt, isNotNull);
      });

      test('parses date string with timezone offset', () {
        final json = {
          'createdAt': '2026-03-10T10:00:00.000+03:00',
        };

        final report = ShiftHandoverReport.fromJson(json);
        expect(report.createdAt, isNotNull);
      });

      test('throws FormatException for invalid createdAt date', () {
        final json = {'createdAt': 'invalid-date'};
        expect(() => ShiftHandoverReport.fromJson(json), throwsFormatException);
      });
    });

    group('toJson', () {
      test('serializes all fields correctly', () {
        final report = ShiftHandoverReport.fromJson(_validJson());
        final json = report.toJson();

        expect(json['id'], 'handover_001');
        expect(json['employeeName'], 'Анна Сидорова');
        expect(json['employeePhone'], '79001234567');
        expect(json['shopAddress'], 'ул. Северная, 10');
        expect(json['answers'], isList);
        expect((json['answers'] as List).length, 2);
        expect(json['rating'], 9);
        expect(json['status'], 'confirmed');
      });

      test('omits AI fields when null', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.utc(2026, 1, 1),
          answers: [],
        );

        final json = report.toJson();
        expect(json.containsKey('aiVerificationPassed'), isFalse);
        expect(json.containsKey('aiVerificationSkipped'), isFalse);
        expect(json.containsKey('aiShortages'), isFalse);
        expect(json.containsKey('aiBboxAnnotations'), isFalse);
      });

      test('omits employeePhone when null', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.utc(2026, 1, 1),
          answers: [],
        );

        final json = report.toJson();
        expect(json.containsKey('employeePhone'), isFalse);
      });

      test('omits empty aiBboxAnnotations', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.utc(2026, 1, 1),
          answers: [],
          aiBboxAnnotations: {},
        );

        final json = report.toJson();
        expect(json.containsKey('aiBboxAnnotations'), isFalse);
      });

      test('createdAt is serialized as UTC ISO8601', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.utc(2026, 3, 10, 10, 0, 0),
          answers: [],
        );

        final json = report.toJson();
        expect(json['createdAt'], contains('2026-03-10'));
        expect(json['createdAt'], endsWith('Z'));
      });
    });

    group('generateId', () {
      test('generates ID with handover_ prefix', () {
        final date = DateTime(2026, 3, 10, 14, 30, 45);
        final id = ShiftHandoverReport.generateId('Анна', 'ул. Северная, 10', date);
        expect(id, startsWith('handover_'));
        expect(id, contains('Анна'));
        expect(id, contains('ул. Северная, 10'));
        expect(id, contains('2026-03-10'));
        expect(id, contains('14-30-45'));
      });

      test('pads month, day, hour, minute, second with zeros', () {
        final date = DateTime(2026, 1, 5, 8, 3, 2);
        final id = ShiftHandoverReport.generateId('Name', 'Addr', date);
        expect(id, 'handover_Name_Addr_2026-01-05_08-03-02');
      });
    });

    group('status helpers', () {
      test('isConfirmed returns true when confirmedAt is set', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          confirmedAt: DateTime.now(),
        );
        expect(report.isConfirmed, isTrue);
      });

      test('isConfirmed returns false when confirmedAt is null', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
        );
        expect(report.isConfirmed, isFalse);
      });

      test('isExpired returns true when status is expired', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          status: 'expired',
        );
        expect(report.isExpired, isTrue);
      });

      test('isExpired returns true when expiredAt is set', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          expiredAt: DateTime.now(),
        );
        expect(report.isExpired, isTrue);
      });

      test('isExpired returns false for non-expired report', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          status: 'pending',
        );
        expect(report.isExpired, isFalse);
      });
    });

    group('isOlderThanWeek', () {
      test('returns true for report older than 7 days', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now().subtract(const Duration(days: 8)),
          answers: [],
        );
        expect(report.isOlderThanWeek, isTrue);
      });

      test('returns false for recent report', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
        );
        expect(report.isOlderThanWeek, isFalse);
      });
    });

    group('verificationStatus', () {
      test('returns confirmed when report is confirmed', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          confirmedAt: DateTime.now(),
        );
        expect(report.verificationStatus, 'confirmed');
      });

      test('returns not_verified after 6+ hours without confirmation', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now().subtract(const Duration(hours: 7)),
          answers: [],
        );
        expect(report.verificationStatus, 'not_verified');
      });

      test('returns pending for recent unconfirmed report', () {
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
        );
        expect(report.verificationStatus, 'pending');
      });

      test('confirmed takes priority over not_verified', () {
        // Even if old, confirmed still returns confirmed
        final report = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now().subtract(const Duration(hours: 10)),
          answers: [],
          confirmedAt: DateTime.now(),
        );
        expect(report.verificationStatus, 'confirmed');
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final original = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.utc(2026, 1, 1),
          answers: [],
          status: 'pending',
        );

        final updated = original.copyWith(
          status: 'confirmed',
          rating: 10,
          confirmedByAdmin: 'Admin',
          confirmedAt: DateTime.utc(2026, 1, 1, 12),
        );

        expect(updated.status, 'confirmed');
        expect(updated.rating, 10);
        expect(updated.confirmedByAdmin, 'Admin');
        expect(updated.confirmedAt, DateTime.utc(2026, 1, 1, 12));
        // Unchanged
        expect(updated.id, 'h1');
        expect(updated.employeeName, 'Test');
        expect(updated.shopAddress, 'Addr');
      });

      test('preserves employeePhone in copy', () {
        final original = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          employeePhone: '79001234567',
          shopAddress: 'Addr',
          createdAt: DateTime.utc(2026, 1, 1),
          answers: [],
        );

        final copy = original.copyWith(status: 'confirmed');
        expect(copy.employeePhone, '79001234567');
      });

      test('updates AI verification fields', () {
        final original = ShiftHandoverReport(
          id: 'h1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.utc(2026, 1, 1),
          answers: [],
        );

        final updated = original.copyWith(
          aiVerificationPassed: false,
          aiVerificationSkipped: true,
          aiShortages: [{'productId': 'p1'}],
          aiBboxAnnotations: {'p1': 'ann1'},
        );

        expect(updated.aiVerificationPassed, false);
        expect(updated.aiVerificationSkipped, true);
        expect(updated.aiShortages!.length, 1);
        expect(updated.aiBboxAnnotations!['p1'], 'ann1');
      });
    });
  });

  group('PendingShiftHandoverReport model', () {
    Map<String, dynamic> _validPendingJson() => {
      'id': 'pending_001',
      'shopAddress': 'ул. Центральная, 1',
      'shiftType': 'morning',
      'shiftLabel': 'Утро',
      'date': '2026-03-10',
      'deadline': '12:00',
      'status': 'pending',
      'completedBy': null,
      'createdAt': '2026-03-10T06:00:00.000',
      'completedAt': null,
    };

    group('fromJson', () {
      test('parses valid data', () {
        final report = PendingShiftHandoverReport.fromJson(_validPendingJson());

        expect(report.id, 'pending_001');
        expect(report.shopAddress, 'ул. Центральная, 1');
        expect(report.shiftType, 'morning');
        expect(report.shiftLabel, 'Утро');
        expect(report.date, '2026-03-10');
        expect(report.deadline, '12:00');
        expect(report.status, 'pending');
        expect(report.completedBy, isNull);
        expect(report.completedAt, isNull);
      });

      test('handles missing fields with defaults', () {
        final report = PendingShiftHandoverReport.fromJson({});

        expect(report.id, '');
        expect(report.shopAddress, '');
        expect(report.shiftType, 'morning');
        expect(report.date, '');
        expect(report.deadline, '');
        expect(report.status, 'pending');
        expect(report.completedBy, isNull);
      });

      test('defaults shiftLabel based on shiftType when not provided', () {
        final morningReport = PendingShiftHandoverReport.fromJson({
          'shiftType': 'morning',
          'createdAt': '2026-03-10T06:00:00.000',
        });
        expect(morningReport.shiftLabel, 'Утро');

        final eveningReport = PendingShiftHandoverReport.fromJson({
          'shiftType': 'evening',
          'createdAt': '2026-03-10T06:00:00.000',
        });
        expect(eveningReport.shiftLabel, 'Вечер');
      });

      test('uses explicit shiftLabel over default', () {
        final report = PendingShiftHandoverReport.fromJson({
          'shiftType': 'morning',
          'shiftLabel': 'Custom Label',
          'createdAt': '2026-03-10T06:00:00.000',
        });
        expect(report.shiftLabel, 'Custom Label');
      });

      test('parses completed report', () {
        final json = {
          'id': 'pending_002',
          'shopAddress': 'Addr',
          'shiftType': 'evening',
          'shiftLabel': 'Вечер',
          'date': '2026-03-10',
          'deadline': '22:00',
          'status': 'completed',
          'completedBy': 'Иван',
          'createdAt': '2026-03-10T16:00:00.000',
          'completedAt': '2026-03-10T21:30:00.000',
        };

        final report = PendingShiftHandoverReport.fromJson(json);
        expect(report.status, 'completed');
        expect(report.completedBy, 'Иван');
        expect(report.completedAt, isNotNull);
      });
    });

    group('toJson', () {
      test('serializes all fields', () {
        final report = PendingShiftHandoverReport.fromJson(_validPendingJson());
        final json = report.toJson();

        expect(json['id'], 'pending_001');
        expect(json['shopAddress'], 'ул. Центральная, 1');
        expect(json['shiftType'], 'morning');
        expect(json['shiftLabel'], 'Утро');
        expect(json['date'], '2026-03-10');
        expect(json['deadline'], '12:00');
        expect(json['status'], 'pending');
      });

      test('toJson/fromJson roundtrip preserves data', () {
        final original = PendingShiftHandoverReport.fromJson(_validPendingJson());
        final restored = PendingShiftHandoverReport.fromJson(original.toJson());

        expect(restored.id, original.id);
        expect(restored.shopAddress, original.shopAddress);
        expect(restored.shiftType, original.shiftType);
        expect(restored.shiftLabel, original.shiftLabel);
        expect(restored.date, original.date);
        expect(restored.deadline, original.deadline);
        expect(restored.status, original.status);
      });
    });

    group('isOverdue', () {
      test('returns false for completed report', () {
        final report = PendingShiftHandoverReport(
          id: 'p1',
          shopAddress: 'Addr',
          shiftType: 'morning',
          shiftLabel: 'Утро',
          date: _todayString(),
          deadline: '00:01', // Past deadline
          status: 'completed',
          createdAt: DateTime.now(),
        );
        expect(report.isOverdue, isFalse);
      });

      test('returns false for a different date', () {
        final report = PendingShiftHandoverReport(
          id: 'p1',
          shopAddress: 'Addr',
          shiftType: 'morning',
          shiftLabel: 'Утро',
          date: '2025-01-01', // Past date, not today
          deadline: '00:01',
          status: 'pending',
          createdAt: DateTime.now(),
        );
        expect(report.isOverdue, isFalse);
      });

      test('returns true when current time is past deadline today', () {
        final now = DateTime.now();
        // Deadline 1 minute ago
        final pastHour = now.hour;
        final pastMinute = now.minute > 0 ? now.minute - 1 : 0;
        final deadline = '${pastHour.toString().padLeft(2, '0')}:${pastMinute.toString().padLeft(2, '0')}';

        final report = PendingShiftHandoverReport(
          id: 'p1',
          shopAddress: 'Addr',
          shiftType: 'morning',
          shiftLabel: 'Утро',
          date: _todayString(),
          deadline: deadline,
          status: 'pending',
          createdAt: DateTime.now(),
        );

        // Only overdue if minute > 0 (otherwise edge case at midnight)
        if (now.minute > 0) {
          expect(report.isOverdue, isTrue);
        }
      });

      test('returns false when current time is before deadline today', () {
        final report = PendingShiftHandoverReport(
          id: 'p1',
          shopAddress: 'Addr',
          shiftType: 'morning',
          shiftLabel: 'Утро',
          date: _todayString(),
          deadline: '23:59',
          status: 'pending',
          createdAt: DateTime.now(),
        );
        expect(report.isOverdue, isFalse);
      });
    });
  });
}

/// Helper to get today's date as YYYY-MM-DD string
String _todayString() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

// Employee Shift Reports Tests
// Priority: P0 (Critical)
// Tests for ShiftReport, ShiftAnswer, ShiftShortage, ShiftReportStatus models

import 'package:flutter_test/flutter_test.dart';
import 'package:arabica_app/features/shifts/models/shift_report_model.dart';
import 'package:arabica_app/features/shifts/models/shift_shortage_model.dart';

void main() {
  group('ShiftAnswer model', () {
    test('fromJson parses valid data correctly', () {
      final json = {
        'question': 'Проверили ли вы кассу?',
        'textAnswer': 'Да',
        'numberAnswer': 42.5,
        'photoPath': '/local/photo.jpg',
        'photoDriveId': 'drive_abc123',
        'referencePhotoUrl': 'https://example.com/ref.jpg',
      };

      final answer = ShiftAnswer.fromJson(json);

      expect(answer.question, 'Проверили ли вы кассу?');
      expect(answer.textAnswer, 'Да');
      expect(answer.numberAnswer, 42.5);
      expect(answer.photoPath, '/local/photo.jpg');
      expect(answer.photoDriveId, 'drive_abc123');
      expect(answer.referencePhotoUrl, 'https://example.com/ref.jpg');
    });

    test('fromJson handles missing optional fields', () {
      final json = {'question': 'Сколько товара?'};

      final answer = ShiftAnswer.fromJson(json);

      expect(answer.question, 'Сколько товара?');
      expect(answer.textAnswer, isNull);
      expect(answer.numberAnswer, isNull);
      expect(answer.photoPath, isNull);
      expect(answer.photoDriveId, isNull);
      expect(answer.referencePhotoUrl, isNull);
    });

    test('fromJson defaults question to empty string when null', () {
      final answer = ShiftAnswer.fromJson({});
      expect(answer.question, '');
    });

    test('fromJson converts int numberAnswer to double', () {
      final json = {'question': 'Count', 'numberAnswer': 10};
      final answer = ShiftAnswer.fromJson(json);
      expect(answer.numberAnswer, 10.0);
      expect(answer.numberAnswer, isA<double>());
    });

    test('toJson serializes all fields', () {
      final answer = ShiftAnswer(
        question: 'Test?',
        textAnswer: 'Yes',
        numberAnswer: 5.0,
        photoPath: '/path',
        photoDriveId: 'driveId',
        referencePhotoUrl: 'https://ref.url',
      );

      final json = answer.toJson();

      expect(json['question'], 'Test?');
      expect(json['textAnswer'], 'Yes');
      expect(json['numberAnswer'], 5.0);
      expect(json['photoPath'], '/path');
      expect(json['photoDriveId'], 'driveId');
      expect(json['referencePhotoUrl'], 'https://ref.url');
    });

    test('toJson omits referencePhotoUrl when null', () {
      final answer = ShiftAnswer(question: 'Q');
      final json = answer.toJson();

      expect(json.containsKey('referencePhotoUrl'), isFalse);
      // Other nullable fields are included as null
      expect(json.containsKey('textAnswer'), isTrue);
    });

    test('toJson/fromJson roundtrip preserves data', () {
      final original = ShiftAnswer(
        question: 'Фото витрины',
        textAnswer: null,
        numberAnswer: 15.0,
        photoPath: '/photo.jpg',
        photoDriveId: 'abc',
        referencePhotoUrl: 'https://ref.com/img.png',
      );

      final restored = ShiftAnswer.fromJson(original.toJson());

      expect(restored.question, original.question);
      expect(restored.numberAnswer, original.numberAnswer);
      expect(restored.photoPath, original.photoPath);
      expect(restored.photoDriveId, original.photoDriveId);
      expect(restored.referencePhotoUrl, original.referencePhotoUrl);
    });
  });

  group('ShiftReportStatus enum', () {
    test('fromString parses all valid status strings', () {
      expect(ShiftReportStatusExtension.fromString('pending'), ShiftReportStatus.pending);
      expect(ShiftReportStatusExtension.fromString('review'), ShiftReportStatus.review);
      expect(ShiftReportStatusExtension.fromString('confirmed'), ShiftReportStatus.confirmed);
      expect(ShiftReportStatusExtension.fromString('failed'), ShiftReportStatus.failed);
      expect(ShiftReportStatusExtension.fromString('rejected'), ShiftReportStatus.rejected);
      expect(ShiftReportStatusExtension.fromString('expired'), ShiftReportStatus.expired);
    });

    test('fromString is case-insensitive', () {
      expect(ShiftReportStatusExtension.fromString('PENDING'), ShiftReportStatus.pending);
      expect(ShiftReportStatusExtension.fromString('Review'), ShiftReportStatus.review);
      expect(ShiftReportStatusExtension.fromString('CONFIRMED'), ShiftReportStatus.confirmed);
    });

    test('fromString defaults to pending for unknown values', () {
      expect(ShiftReportStatusExtension.fromString('unknown'), ShiftReportStatus.pending);
      expect(ShiftReportStatusExtension.fromString(''), ShiftReportStatus.pending);
    });

    test('fromString defaults to pending for null', () {
      expect(ShiftReportStatusExtension.fromString(null), ShiftReportStatus.pending);
    });

    test('name returns correct string for each status', () {
      expect(ShiftReportStatus.pending.name, 'pending');
      expect(ShiftReportStatus.review.name, 'review');
      expect(ShiftReportStatus.confirmed.name, 'confirmed');
      expect(ShiftReportStatus.failed.name, 'failed');
      expect(ShiftReportStatus.rejected.name, 'rejected');
      expect(ShiftReportStatus.expired.name, 'expired');
    });

    test('label returns human-readable Russian labels', () {
      expect(ShiftReportStatus.pending.label, 'Ожидает');
      expect(ShiftReportStatus.review.label, 'На проверке');
      expect(ShiftReportStatus.confirmed.label, 'Подтверждён');
      expect(ShiftReportStatus.failed.label, 'Не пройден');
      expect(ShiftReportStatus.rejected.label, 'Отклонён');
      expect(ShiftReportStatus.expired.label, 'Истёк');
    });
  });

  group('ShiftReport model', () {
    Map<String, dynamic> _validJson() => {
      'id': 'report_001',
      'employeeName': 'Иван Петров',
      'employeeId': 'emp_001',
      'shopAddress': 'ул. Центральная, 1',
      'shopName': 'Кофейня Центр',
      'createdAt': '2026-03-10T10:00:00.000',
      'answers': [
        {'question': 'Касса проверена?', 'textAnswer': 'Да'},
        {'question': 'Количество товара', 'numberAnswer': 15},
      ],
      'isSynced': true,
      'confirmedAt': '2026-03-10T12:00:00.000',
      'rating': 8,
      'confirmedByAdmin': 'Админ',
      'status': 'confirmed',
      'expiredAt': null,
      'shiftType': 'morning',
      'submittedAt': '2026-03-10T10:30:00.000',
      'reviewDeadline': '2026-03-10T16:00:00.000',
      'failedAt': null,
      'rejectedAt': null,
    };

    group('fromJson', () {
      test('parses valid complete data', () {
        final report = ShiftReport.fromJson(_validJson());

        expect(report.id, 'report_001');
        expect(report.employeeName, 'Иван Петров');
        expect(report.employeeId, 'emp_001');
        expect(report.shopAddress, 'ул. Центральная, 1');
        expect(report.shopName, 'Кофейня Центр');
        expect(report.createdAt, DateTime(2026, 3, 10, 10, 0, 0));
        expect(report.answers.length, 2);
        expect(report.answers[0].question, 'Касса проверена?');
        expect(report.answers[1].numberAnswer, 15.0);
        expect(report.isSynced, true);
        expect(report.confirmedAt, DateTime(2026, 3, 10, 12, 0, 0));
        expect(report.rating, 8);
        expect(report.confirmedByAdmin, 'Админ');
        expect(report.status, 'confirmed');
        expect(report.shiftType, 'morning');
        expect(report.submittedAt, DateTime(2026, 3, 10, 10, 30, 0));
        expect(report.reviewDeadline, DateTime(2026, 3, 10, 16, 0, 0));
      });

      test('handles missing optional fields with defaults', () {
        final json = {
          'createdAt': '2026-03-10T10:00:00.000',
        };

        final report = ShiftReport.fromJson(json);

        expect(report.id, '');
        expect(report.employeeName, '');
        expect(report.employeeId, isNull);
        expect(report.shopAddress, '');
        expect(report.shopName, isNull);
        expect(report.answers, isEmpty);
        expect(report.isSynced, false);
        expect(report.confirmedAt, isNull);
        expect(report.rating, isNull);
        expect(report.confirmedByAdmin, isNull);
        expect(report.status, isNull);
        expect(report.expiredAt, isNull);
        expect(report.shiftType, isNull);
        expect(report.submittedAt, isNull);
        expect(report.reviewDeadline, isNull);
        expect(report.failedAt, isNull);
        expect(report.rejectedAt, isNull);
        expect(report.shortages, isNull);
        expect(report.aiVerificationPassed, isNull);
      });

      test('handles null answers list', () {
        final json = {
          'createdAt': '2026-03-10T10:00:00.000',
          'answers': null,
        };

        final report = ShiftReport.fromJson(json);
        expect(report.answers, isEmpty);
      });

      test('parses shortages when present', () {
        final json = {
          'createdAt': '2026-03-10T10:00:00.000',
          'shortages': [
            {
              'productId': 'p1',
              'barcode': '1234567890',
              'productName': 'Капучино',
              'stockQuantity': 5,
              'confirmedAt': '2026-03-10T10:00:00.000',
              'employeeName': 'Иван',
            },
          ],
          'aiVerificationPassed': false,
        };

        final report = ShiftReport.fromJson(json);
        expect(report.shortages, isNotNull);
        expect(report.shortages!.length, 1);
        expect(report.shortages![0].productName, 'Капучино');
        expect(report.shortages![0].stockQuantity, 5);
        expect(report.aiVerificationPassed, false);
      });

      test('parses all date fields correctly', () {
        final json = {
          'createdAt': '2026-03-10T10:00:00.000',
          'confirmedAt': '2026-03-10T12:00:00.000',
          'expiredAt': '2026-03-11T10:00:00.000',
          'submittedAt': '2026-03-10T10:30:00.000',
          'reviewDeadline': '2026-03-10T16:00:00.000',
          'failedAt': '2026-03-10T18:00:00.000',
          'rejectedAt': '2026-03-10T20:00:00.000',
        };

        final report = ShiftReport.fromJson(json);
        expect(report.createdAt.hour, 10);
        expect(report.confirmedAt!.hour, 12);
        expect(report.expiredAt!.day, 11);
        expect(report.submittedAt!.minute, 30);
        expect(report.reviewDeadline!.hour, 16);
        expect(report.failedAt!.hour, 18);
        expect(report.rejectedAt!.hour, 20);
      });

      test('throws FormatException for invalid createdAt date', () {
        final json = {'createdAt': 'not-a-date'};
        expect(() => ShiftReport.fromJson(json), throwsFormatException);
      });
    });

    group('toJson', () {
      test('serializes all fields correctly', () {
        final report = ShiftReport.fromJson(_validJson());
        final json = report.toJson();

        expect(json['id'], 'report_001');
        expect(json['employeeName'], 'Иван Петров');
        expect(json['shopAddress'], 'ул. Центральная, 1');
        expect(json['status'], 'confirmed');
        expect(json['rating'], 8);
        expect(json['answers'], isList);
        expect((json['answers'] as List).length, 2);
      });

      test('omits shortages and aiVerificationPassed when null', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime(2026, 1, 1),
          answers: [],
        );

        final json = report.toJson();
        expect(json.containsKey('shortages'), isFalse);
        expect(json.containsKey('aiVerificationPassed'), isFalse);
      });

      test('includes shortages and aiVerificationPassed when set', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime(2026, 1, 1),
          answers: [],
          shortages: [
            ShiftShortage(
              productId: 'p1',
              barcode: '123',
              productName: 'Item',
              stockQuantity: 3,
              confirmedAt: DateTime(2026, 1, 1),
              employeeName: 'Test',
            ),
          ],
          aiVerificationPassed: true,
        );

        final json = report.toJson();
        expect(json.containsKey('shortages'), isTrue);
        expect(json['aiVerificationPassed'], true);
        expect((json['shortages'] as List).length, 1);
      });

      test('toJson/fromJson roundtrip preserves data', () {
        final original = ShiftReport.fromJson(_validJson());
        final restored = ShiftReport.fromJson(original.toJson());

        expect(restored.id, original.id);
        expect(restored.employeeName, original.employeeName);
        expect(restored.shopAddress, original.shopAddress);
        expect(restored.status, original.status);
        expect(restored.rating, original.rating);
        expect(restored.shiftType, original.shiftType);
        expect(restored.answers.length, original.answers.length);
        expect(restored.createdAt, original.createdAt);
        expect(restored.confirmedAt, original.confirmedAt);
        expect(restored.submittedAt, original.submittedAt);
      });
    });

    group('generateId', () {
      test('generates deterministic ID from inputs', () {
        final date = DateTime(2026, 3, 10, 14, 30, 45);
        final id = ShiftReport.generateId('Иван', 'ул. Центральная, 1', date);
        expect(id, 'Иван_ул. Центральная, 1_2026-03-10_14-30-45');
      });

      test('pads month and day with zeros', () {
        final date = DateTime(2026, 1, 5, 9, 5, 3);
        final id = ShiftReport.generateId('Name', 'Addr', date);
        expect(id, 'Name_Addr_2026-01-05_09-05-03');
      });
    });

    group('status helpers', () {
      test('isPending returns true for pending status', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          status: 'pending',
        );
        expect(report.isPending, isTrue);
        expect(report.isInReview, isFalse);
        expect(report.isFailed, isFalse);
        expect(report.isRejected, isFalse);
      });

      test('isPending returns true for null status', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          status: null,
        );
        expect(report.isPending, isTrue);
      });

      test('isInReview returns true for review status', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          status: 'review',
        );
        expect(report.isInReview, isTrue);
        expect(report.isPending, isFalse);
      });

      test('isFailed returns true for failed status', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          status: 'failed',
        );
        expect(report.isFailed, isTrue);
      });

      test('isRejected returns true for rejected status', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          status: 'rejected',
        );
        expect(report.isRejected, isTrue);
      });

      test('statusEnum converts string status to enum', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          status: 'review',
        );
        expect(report.statusEnum, ShiftReportStatus.review);
      });

      test('statusEnum returns pending for null status', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
        );
        expect(report.statusEnum, ShiftReportStatus.pending);
      });
    });

    group('isConfirmed / isExpired', () {
      test('isConfirmed returns true when confirmedAt is set', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          confirmedAt: DateTime.now(),
        );
        expect(report.isConfirmed, isTrue);
      });

      test('isConfirmed returns false when confirmedAt is null', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
        );
        expect(report.isConfirmed, isFalse);
      });

      test('isExpired returns true when status is expired', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          status: 'expired',
        );
        expect(report.isExpired, isTrue);
      });

      test('isExpired returns true when expiredAt is set', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          expiredAt: DateTime.now(),
        );
        expect(report.isExpired, isTrue);
      });

      test('isExpired returns false for non-expired report', () {
        final report = ShiftReport(
          id: 'r1',
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
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now().subtract(const Duration(days: 8)),
          answers: [],
        );
        expect(report.isOlderThanWeek, isTrue);
      });

      test('returns false for report created today', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
        );
        expect(report.isOlderThanWeek, isFalse);
      });

      test('returns false for report created exactly 7 days ago', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now().subtract(const Duration(days: 7)),
          answers: [],
        );
        expect(report.isOlderThanWeek, isFalse);
      });
    });

    group('verificationStatus', () {
      test('returns confirmed when report is confirmed', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
          confirmedAt: DateTime.now(),
        );
        expect(report.verificationStatus, 'confirmed');
      });

      test('returns not_verified when 6+ hours without confirmation', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now().subtract(const Duration(hours: 7)),
          answers: [],
        );
        expect(report.verificationStatus, 'not_verified');
      });

      test('returns pending when created recently and not confirmed', () {
        final report = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime.now(),
          answers: [],
        );
        expect(report.verificationStatus, 'pending');
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final original = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime(2026, 1, 1),
          answers: [],
          status: 'pending',
        );

        final updated = original.copyWith(
          status: 'review',
          rating: 8,
          confirmedByAdmin: 'Admin',
        );

        expect(updated.status, 'review');
        expect(updated.rating, 8);
        expect(updated.confirmedByAdmin, 'Admin');
        // Unchanged fields preserved
        expect(updated.id, 'r1');
        expect(updated.employeeName, 'Test');
        expect(updated.shopAddress, 'Addr');
      });

      test('preserves original values when not overridden', () {
        final original = ShiftReport(
          id: 'r1',
          employeeName: 'Test',
          shopAddress: 'Addr',
          createdAt: DateTime(2026, 1, 1),
          answers: [ShiftAnswer(question: 'Q1')],
          isSynced: true,
          rating: 5,
        );

        final copy = original.copyWith(status: 'confirmed');

        expect(copy.rating, 5);
        expect(copy.isSynced, true);
        expect(copy.answers.length, 1);
      });
    });
  });

  group('ShiftShortage model', () {
    test('fromJson parses valid data', () {
      final json = {
        'productId': 'prod_001',
        'barcode': '1234567890123',
        'productName': 'Капучино 250мл',
        'stockQuantity': 10,
        'confirmedAt': '2026-03-10T10:00:00.000',
        'employeeName': 'Иван Петров',
      };

      final shortage = ShiftShortage.fromJson(json);

      expect(shortage.productId, 'prod_001');
      expect(shortage.barcode, '1234567890123');
      expect(shortage.productName, 'Капучино 250мл');
      expect(shortage.stockQuantity, 10);
      expect(shortage.confirmedAt, DateTime(2026, 3, 10, 10, 0, 0));
      expect(shortage.employeeName, 'Иван Петров');
    });

    test('fromJson handles missing fields with defaults', () {
      final shortage = ShiftShortage.fromJson({});

      expect(shortage.productId, '');
      expect(shortage.barcode, '');
      expect(shortage.productName, '');
      expect(shortage.stockQuantity, 0);
      expect(shortage.employeeName, '');
      // confirmedAt defaults to DateTime.now() — just verify it's recent
      expect(shortage.confirmedAt.difference(DateTime.now()).inSeconds.abs(), lessThan(2));
    });

    test('toJson serializes correctly', () {
      final now = DateTime(2026, 3, 10, 14, 30, 0);
      final shortage = ShiftShortage(
        productId: 'p1',
        barcode: '999',
        productName: 'Латте',
        stockQuantity: 3,
        confirmedAt: now,
        employeeName: 'Тест',
      );

      final json = shortage.toJson();

      expect(json['productId'], 'p1');
      expect(json['barcode'], '999');
      expect(json['productName'], 'Латте');
      expect(json['stockQuantity'], 3);
      expect(json['confirmedAt'], now.toIso8601String());
      expect(json['employeeName'], 'Тест');
    });

    test('toJson/fromJson roundtrip preserves data', () {
      final original = ShiftShortage(
        productId: 'p1',
        barcode: '1234',
        productName: 'Test Product',
        stockQuantity: 7,
        confirmedAt: DateTime(2026, 3, 10, 10, 0, 0),
        employeeName: 'Employee',
      );

      final restored = ShiftShortage.fromJson(original.toJson());

      expect(restored.productId, original.productId);
      expect(restored.barcode, original.barcode);
      expect(restored.productName, original.productName);
      expect(restored.stockQuantity, original.stockQuantity);
      expect(restored.confirmedAt, original.confirmedAt);
      expect(restored.employeeName, original.employeeName);
    });

    test('toString returns descriptive string', () {
      final shortage = ShiftShortage(
        productId: 'p1',
        barcode: '123',
        productName: 'Item',
        stockQuantity: 5,
        confirmedAt: DateTime.now(),
        employeeName: 'Test',
      );

      final str = shortage.toString();
      expect(str, contains('p1'));
      expect(str, contains('123'));
      expect(str, contains('Item'));
      expect(str, contains('5'));
    });
  });
}

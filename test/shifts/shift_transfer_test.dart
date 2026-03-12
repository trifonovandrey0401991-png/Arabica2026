// Shift Transfer Model Tests
// Tests for ShiftTransferRequest, AcceptedByEmployee, and ShiftTransferStatus

import 'package:flutter_test/flutter_test.dart';
import 'package:arabica_app/features/work_schedule/models/shift_transfer_model.dart';
import 'package:arabica_app/features/work_schedule/models/work_schedule_model.dart';

void main() {
  group('ShiftTransferStatus enum', () {
    test('fromString parses all valid status strings', () {
      expect(ShiftTransferStatusExtension.fromString('pending'), ShiftTransferStatus.pending);
      expect(ShiftTransferStatusExtension.fromString('has_acceptances'), ShiftTransferStatus.hasAcceptances);
      expect(ShiftTransferStatusExtension.fromString('accepted'), ShiftTransferStatus.accepted);
      expect(ShiftTransferStatusExtension.fromString('rejected'), ShiftTransferStatus.rejected);
      expect(ShiftTransferStatusExtension.fromString('approved'), ShiftTransferStatus.approved);
      expect(ShiftTransferStatusExtension.fromString('declined'), ShiftTransferStatus.declined);
      expect(ShiftTransferStatusExtension.fromString('expired'), ShiftTransferStatus.expired);
    });

    test('fromString is case-insensitive', () {
      expect(ShiftTransferStatusExtension.fromString('PENDING'), ShiftTransferStatus.pending);
      expect(ShiftTransferStatusExtension.fromString('Has_Acceptances'), ShiftTransferStatus.hasAcceptances);
      expect(ShiftTransferStatusExtension.fromString('APPROVED'), ShiftTransferStatus.approved);
    });

    test('fromString defaults to pending for unknown values', () {
      expect(ShiftTransferStatusExtension.fromString('unknown'), ShiftTransferStatus.pending);
      expect(ShiftTransferStatusExtension.fromString(''), ShiftTransferStatus.pending);
    });

    test('name returns correct string for each status', () {
      expect(ShiftTransferStatus.pending.name, 'pending');
      expect(ShiftTransferStatus.hasAcceptances.name, 'has_acceptances');
      expect(ShiftTransferStatus.accepted.name, 'accepted');
      expect(ShiftTransferStatus.rejected.name, 'rejected');
      expect(ShiftTransferStatus.approved.name, 'approved');
      expect(ShiftTransferStatus.declined.name, 'declined');
      expect(ShiftTransferStatus.expired.name, 'expired');
    });

    test('label returns human-readable Russian labels', () {
      expect(ShiftTransferStatus.pending.label, 'Ожидает ответа');
      expect(ShiftTransferStatus.hasAcceptances.label, 'Есть принявшие');
      expect(ShiftTransferStatus.accepted.label, 'Принято');
      expect(ShiftTransferStatus.rejected.label, 'Отклонено');
      expect(ShiftTransferStatus.approved.label, 'Одобрено');
      expect(ShiftTransferStatus.declined.label, 'Отказано');
      expect(ShiftTransferStatus.expired.label, 'Истек срок');
    });
  });

  group('AcceptedByEmployee model', () {
    test('fromJson parses valid data', () {
      final json = {
        'employeeId': 'emp_001',
        'employeeName': 'Иван Петров',
        'acceptedAt': '2026-03-10T14:00:00.000',
      };

      final accepted = AcceptedByEmployee.fromJson(json);

      expect(accepted.employeeId, 'emp_001');
      expect(accepted.employeeName, 'Иван Петров');
      expect(accepted.acceptedAt, DateTime(2026, 3, 10, 14, 0, 0));
    });

    test('fromJson handles missing employeeId and employeeName', () {
      final json = {
        'acceptedAt': '2026-03-10T14:00:00.000',
      };

      final accepted = AcceptedByEmployee.fromJson(json);
      expect(accepted.employeeId, '');
      expect(accepted.employeeName, '');
    });

    test('toJson serializes correctly', () {
      final accepted = AcceptedByEmployee(
        employeeId: 'emp_002',
        employeeName: 'Анна',
        acceptedAt: DateTime(2026, 3, 10, 15, 30, 0),
      );

      final json = accepted.toJson();

      expect(json['employeeId'], 'emp_002');
      expect(json['employeeName'], 'Анна');
      expect(json['acceptedAt'], '2026-03-10T15:30:00.000');
    });

    test('toJson/fromJson roundtrip preserves data', () {
      final original = AcceptedByEmployee(
        employeeId: 'emp_003',
        employeeName: 'Test',
        acceptedAt: DateTime(2026, 3, 10, 10, 0, 0),
      );

      final restored = AcceptedByEmployee.fromJson(original.toJson());

      expect(restored.employeeId, original.employeeId);
      expect(restored.employeeName, original.employeeName);
      expect(restored.acceptedAt, original.acceptedAt);
    });
  });

  group('ShiftTransferRequest model', () {
    Map<String, dynamic> _validJson() => {
      'id': 'transfer_001',
      'fromEmployeeId': 'emp_001',
      'fromEmployeeName': 'Иван Петров',
      'toEmployeeId': 'emp_002',
      'toEmployeeName': 'Анна Сидорова',
      'scheduleEntryId': 'sched_001',
      'shiftDate': '2026-03-15',
      'shopAddress': 'ул. Центральная, 1',
      'shopName': 'Кофейня Центр',
      'shiftType': 'morning',
      'comment': 'Нужно поменяться',
      'status': 'pending',
      'acceptedByEmployeeId': null,
      'acceptedByEmployeeName': null,
      'acceptedBy': [],
      'approvedEmployeeId': null,
      'approvedEmployeeName': null,
      'createdAt': '2026-03-10T10:00:00.000',
      'acceptedAt': null,
      'resolvedAt': null,
      'isReadByRecipient': false,
      'isReadByAdmin': false,
    };

    group('fromJson', () {
      test('parses valid complete data', () {
        final request = ShiftTransferRequest.fromJson(_validJson());

        expect(request.id, 'transfer_001');
        expect(request.fromEmployeeId, 'emp_001');
        expect(request.fromEmployeeName, 'Иван Петров');
        expect(request.toEmployeeId, 'emp_002');
        expect(request.toEmployeeName, 'Анна Сидорова');
        expect(request.scheduleEntryId, 'sched_001');
        expect(request.shiftDate, DateTime(2026, 3, 15));
        expect(request.shopAddress, 'ул. Центральная, 1');
        expect(request.shopName, 'Кофейня Центр');
        expect(request.shiftType, ShiftType.morning);
        expect(request.comment, 'Нужно поменяться');
        expect(request.status, ShiftTransferStatus.pending);
        expect(request.acceptedBy, isEmpty);
        expect(request.isReadByRecipient, false);
        expect(request.isReadByAdmin, false);
      });

      test('handles missing optional fields', () {
        final json = {
          'shiftDate': '2026-03-15',
          'createdAt': '2026-03-10T10:00:00.000',
        };

        final request = ShiftTransferRequest.fromJson(json);

        expect(request.id, '');
        expect(request.fromEmployeeId, '');
        expect(request.fromEmployeeName, '');
        expect(request.toEmployeeId, isNull);
        expect(request.toEmployeeName, isNull);
        expect(request.comment, isNull);
        expect(request.acceptedByEmployeeId, isNull);
        expect(request.acceptedAt, isNull);
        expect(request.resolvedAt, isNull);
        expect(request.isReadByRecipient, false);
        expect(request.isReadByAdmin, false);
      });

      test('parses acceptedBy list', () {
        final json = _validJson();
        json['acceptedBy'] = [
          {
            'employeeId': 'emp_003',
            'employeeName': 'Петр',
            'acceptedAt': '2026-03-11T10:00:00.000',
          },
          {
            'employeeId': 'emp_004',
            'employeeName': 'Мария',
            'acceptedAt': '2026-03-11T11:00:00.000',
          },
        ];
        json['status'] = 'has_acceptances';

        final request = ShiftTransferRequest.fromJson(json);

        expect(request.acceptedBy.length, 2);
        expect(request.acceptedBy[0].employeeName, 'Петр');
        expect(request.acceptedBy[1].employeeName, 'Мария');
        expect(request.status, ShiftTransferStatus.hasAcceptances);
      });

      test('handles null acceptedBy', () {
        final json = _validJson();
        json['acceptedBy'] = null;

        final request = ShiftTransferRequest.fromJson(json);
        expect(request.acceptedBy, isEmpty);
      });

      test('parses all shift types', () {
        for (final type in ['morning', 'day', 'evening']) {
          final json = _validJson();
          json['shiftType'] = type;
          final request = ShiftTransferRequest.fromJson(json);
          expect(request.shiftType, isNotNull);
        }
      });

      test('parses dates with time components', () {
        final json = _validJson();
        json['acceptedAt'] = '2026-03-12T14:30:00.000';
        json['resolvedAt'] = '2026-03-13T09:00:00.000';

        final request = ShiftTransferRequest.fromJson(json);

        expect(request.acceptedAt, DateTime(2026, 3, 12, 14, 30, 0));
        expect(request.resolvedAt, DateTime(2026, 3, 13, 9, 0, 0));
      });
    });

    group('toJson', () {
      test('serializes all fields correctly', () {
        final request = ShiftTransferRequest.fromJson(_validJson());
        final json = request.toJson();

        expect(json['id'], 'transfer_001');
        expect(json['fromEmployeeId'], 'emp_001');
        expect(json['fromEmployeeName'], 'Иван Петров');
        expect(json['toEmployeeId'], 'emp_002');
        expect(json['shopAddress'], 'ул. Центральная, 1');
        expect(json['comment'], 'Нужно поменяться');
        expect(json['status'], 'pending');
        expect(json['isReadByRecipient'], false);
        expect(json['isReadByAdmin'], false);
      });

      test('serializes shiftDate as date-only string', () {
        final request = ShiftTransferRequest.fromJson(_validJson());
        final json = request.toJson();

        expect(json['shiftDate'], '2026-03-15');
        expect(json['shiftDate'], isNot(contains('T')));
      });

      test('serializes acceptedBy list', () {
        final request = ShiftTransferRequest(
          id: 't1',
          fromEmployeeId: 'e1',
          fromEmployeeName: 'From',
          scheduleEntryId: 's1',
          shiftDate: DateTime(2026, 3, 15),
          shopAddress: 'Addr',
          shopName: 'Shop',
          shiftType: ShiftType.morning,
          createdAt: DateTime(2026, 3, 10),
          acceptedBy: [
            AcceptedByEmployee(
              employeeId: 'e2',
              employeeName: 'To',
              acceptedAt: DateTime(2026, 3, 11),
            ),
          ],
        );

        final json = request.toJson();
        expect(json['acceptedBy'], isList);
        expect((json['acceptedBy'] as List).length, 1);
        expect((json['acceptedBy'] as List)[0]['employeeId'], 'e2');
      });

      test('toJson/fromJson roundtrip preserves core data', () {
        final original = ShiftTransferRequest.fromJson(_validJson());
        final restored = ShiftTransferRequest.fromJson(original.toJson());

        expect(restored.id, original.id);
        expect(restored.fromEmployeeId, original.fromEmployeeId);
        expect(restored.fromEmployeeName, original.fromEmployeeName);
        expect(restored.toEmployeeId, original.toEmployeeId);
        expect(restored.shopAddress, original.shopAddress);
        expect(restored.shopName, original.shopName);
        expect(restored.comment, original.comment);
        expect(restored.status, original.status);
        expect(restored.isReadByRecipient, original.isReadByRecipient);
        expect(restored.isReadByAdmin, original.isReadByAdmin);
      });
    });

    group('computed properties', () {
      test('isBroadcast returns true when toEmployeeId is null', () {
        final json = _validJson();
        json['toEmployeeId'] = null;
        final request = ShiftTransferRequest.fromJson(json);
        expect(request.isBroadcast, isTrue);
      });

      test('isBroadcast returns false when toEmployeeId is set', () {
        final request = ShiftTransferRequest.fromJson(_validJson());
        expect(request.isBroadcast, isFalse);
      });

      test('isActive returns true for pending status', () {
        final json = _validJson();
        json['status'] = 'pending';
        final request = ShiftTransferRequest.fromJson(json);
        expect(request.isActive, isTrue);
      });

      test('isActive returns true for has_acceptances status', () {
        final json = _validJson();
        json['status'] = 'has_acceptances';
        final request = ShiftTransferRequest.fromJson(json);
        expect(request.isActive, isTrue);
      });

      test('isActive returns false for completed statuses', () {
        for (final status in ['approved', 'declined', 'rejected', 'expired']) {
          final json = _validJson();
          json['status'] = status;
          final request = ShiftTransferRequest.fromJson(json);
          expect(request.isActive, isFalse, reason: 'Expected isActive=false for status=$status');
        }
      });

      test('hasAcceptances returns true when acceptedBy is not empty', () {
        final request = ShiftTransferRequest(
          id: 't1',
          fromEmployeeId: 'e1',
          fromEmployeeName: 'From',
          scheduleEntryId: 's1',
          shiftDate: DateTime(2026, 3, 15),
          shopAddress: 'Addr',
          shopName: 'Shop',
          shiftType: ShiftType.morning,
          createdAt: DateTime(2026, 3, 10),
          acceptedBy: [
            AcceptedByEmployee(
              employeeId: 'e2',
              employeeName: 'To',
              acceptedAt: DateTime(2026, 3, 11),
            ),
          ],
        );
        expect(request.hasAcceptances, isTrue);
        expect(request.acceptedCount, 1);
      });

      test('hasAcceptances returns false when acceptedBy is empty', () {
        final json = _validJson();
        final request = ShiftTransferRequest.fromJson(json);
        expect(request.hasAcceptances, isFalse);
        expect(request.acceptedCount, 0);
      });

      test('isPendingApproval returns true for accepted or has_acceptances', () {
        for (final status in ['accepted', 'has_acceptances']) {
          final json = _validJson();
          json['status'] = status;
          final request = ShiftTransferRequest.fromJson(json);
          expect(request.isPendingApproval, isTrue,
              reason: 'Expected isPendingApproval=true for status=$status');
        }
      });

      test('isPendingApproval returns false for other statuses', () {
        for (final status in ['pending', 'approved', 'declined', 'rejected', 'expired']) {
          final json = _validJson();
          json['status'] = status;
          final request = ShiftTransferRequest.fromJson(json);
          expect(request.isPendingApproval, isFalse,
              reason: 'Expected isPendingApproval=false for status=$status');
        }
      });

      test('isCompleted returns true for terminal statuses', () {
        for (final status in ['approved', 'declined', 'rejected', 'expired']) {
          final json = _validJson();
          json['status'] = status;
          final request = ShiftTransferRequest.fromJson(json);
          expect(request.isCompleted, isTrue,
              reason: 'Expected isCompleted=true for status=$status');
        }
      });

      test('isCompleted returns false for active statuses', () {
        for (final status in ['pending', 'has_acceptances', 'accepted']) {
          final json = _validJson();
          json['status'] = status;
          final request = ShiftTransferRequest.fromJson(json);
          expect(request.isCompleted, isFalse,
              reason: 'Expected isCompleted=false for status=$status');
        }
      });
    });

    group('copyWith', () {
      test('creates copy with updated status', () {
        final original = ShiftTransferRequest.fromJson(_validJson());
        final updated = original.copyWith(status: ShiftTransferStatus.approved);

        expect(updated.status, ShiftTransferStatus.approved);
        expect(updated.id, original.id);
        expect(updated.fromEmployeeId, original.fromEmployeeId);
      });

      test('creates copy with new acceptedBy list', () {
        final original = ShiftTransferRequest.fromJson(_validJson());
        final newAccepted = [
          AcceptedByEmployee(
            employeeId: 'e5',
            employeeName: 'New',
            acceptedAt: DateTime(2026, 3, 12),
          ),
        ];

        final updated = original.copyWith(acceptedBy: newAccepted);
        expect(updated.acceptedBy.length, 1);
        expect(updated.acceptedBy[0].employeeName, 'New');
      });

      test('preserves all fields when no overrides', () {
        final original = ShiftTransferRequest.fromJson(_validJson());
        final copy = original.copyWith();

        expect(copy.id, original.id);
        expect(copy.fromEmployeeId, original.fromEmployeeId);
        expect(copy.fromEmployeeName, original.fromEmployeeName);
        expect(copy.toEmployeeId, original.toEmployeeId);
        expect(copy.toEmployeeName, original.toEmployeeName);
        expect(copy.scheduleEntryId, original.scheduleEntryId);
        expect(copy.shopAddress, original.shopAddress);
        expect(copy.shopName, original.shopName);
        expect(copy.comment, original.comment);
        expect(copy.status, original.status);
        expect(copy.isReadByRecipient, original.isReadByRecipient);
        expect(copy.isReadByAdmin, original.isReadByAdmin);
      });
    });

    group('toString', () {
      test('returns descriptive string', () {
        final request = ShiftTransferRequest.fromJson(_validJson());
        final str = request.toString();

        expect(str, contains('transfer_001'));
        expect(str, contains('Иван Петров'));
        expect(str, contains('Анна Сидорова'));
      });

      test('shows "всем" for broadcast requests', () {
        final json = _validJson();
        json['toEmployeeId'] = null;
        json['toEmployeeName'] = null;
        final request = ShiftTransferRequest.fromJson(json);
        final str = request.toString();

        expect(str, contains('всем'));
      });
    });
  });
}

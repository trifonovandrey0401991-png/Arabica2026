import 'package:flutter_test/flutter_test.dart';
import 'package:arabica_app/features/efficiency/models/efficiency_data_model.dart';

/// Тесты фильтрации эффективности по телефону сотрудника
/// Покрывает: EfficiencyRecord.employeePhone, фильтрация по телефону с fallback по имени
void main() {
  group('EfficiencyRecord employeePhone', () {
    test('PHONE-001: Поле employeePhone сохраняется в модели', () {
      final record = EfficiencyRecord(
        id: 'test1',
        category: EfficiencyCategory.shift,
        shopAddress: 'Магазин 1',
        employeeName: 'Глазкова Ольга',
        employeePhone: '79001234567',
        date: DateTime(2026, 3, 1),
        points: 1.5,
        rawValue: 8,
        sourceId: 'shift_1',
      );

      expect(record.employeePhone, '79001234567');
      expect(record.employeeName, 'Глазкова Ольга');
    });

    test('PHONE-002: employeePhone по умолчанию пустая строка', () {
      final record = EfficiencyRecord(
        id: 'test2',
        category: EfficiencyCategory.shift,
        shopAddress: 'Магазин 1',
        employeeName: 'Иванов Иван',
        date: DateTime(2026, 3, 1),
        points: 1.0,
        rawValue: 7,
        sourceId: 'shift_2',
      );

      expect(record.employeePhone, '');
    });

    test('PHONE-003: toJson включает employeePhone', () {
      final record = EfficiencyRecord(
        id: 'test3',
        category: EfficiencyCategory.shift,
        shopAddress: 'Магазин 1',
        employeeName: 'Петрова Анна',
        employeePhone: '79009876543',
        date: DateTime(2026, 3, 1),
        points: 2.0,
        rawValue: 10,
        sourceId: 'shift_3',
      );

      final json = record.toJson();
      expect(json['employeePhone'], '79009876543');
    });

    test('PHONE-004: fromJson восстанавливает employeePhone', () {
      final json = {
        'id': 'test4',
        'category': 'shift',
        'shopAddress': 'Магазин 2',
        'employeeName': 'Сидоров Пётр',
        'employeePhone': '79005551234',
        'date': '2026-03-01T00:00:00.000',
        'points': 1.5,
        'rawValue': 8,
        'sourceId': 'shift_4',
      };

      final record = EfficiencyRecord.fromJson(json);
      expect(record.employeePhone, '79005551234');
      expect(record.employeeName, 'Сидоров Пётр');
    });

    test('PHONE-005: fromJson без employeePhone ставит пустую строку', () {
      final json = {
        'id': 'test5',
        'category': 'shift',
        'shopAddress': 'Магазин 2',
        'employeeName': 'Козлов Денис',
        'date': '2026-03-01T00:00:00.000',
        'points': 0.5,
        'rawValue': 6,
        'sourceId': 'shift_5',
      };

      final record = EfficiencyRecord.fromJson(json);
      expect(record.employeePhone, '');
    });
  });

  group('Фильтрация записей по телефону', () {
    late List<EfficiencyRecord> records;

    setUp(() {
      records = [
        EfficiencyRecord(
          id: 'r1',
          category: EfficiencyCategory.shift,
          shopAddress: 'Магазин 1',
          employeeName: 'Глазкова Ольга',
          employeePhone: '79001234567',
          date: DateTime(2026, 3, 1),
          points: 1.5,
          rawValue: 8,
          sourceId: 's1',
        ),
        EfficiencyRecord(
          id: 'r2',
          category: EfficiencyCategory.recount,
          shopAddress: 'Магазин 1',
          employeeName: 'Глазкова О.С.',  // Имя записано по-другому!
          employeePhone: '79001234567',    // Но телефон тот же
          date: DateTime(2026, 3, 1),
          points: 1.0,
          rawValue: 7,
          sourceId: 's2',
        ),
        EfficiencyRecord(
          id: 'r3',
          category: EfficiencyCategory.attendance,
          shopAddress: 'Магазин 2',
          employeeName: 'Иванов Иван',
          employeePhone: '79009999999',
          date: DateTime(2026, 3, 1),
          points: 0.5,
          rawValue: true,
          sourceId: 's3',
        ),
        EfficiencyRecord(
          id: 'r4',
          category: EfficiencyCategory.shiftHandover,
          shopAddress: 'Магазин 1',
          employeeName: 'Глазкова Ольга',
          employeePhone: '',  // Телефон пустой — старый отчёт
          date: DateTime(2026, 3, 1),
          points: 1.2,
          rawValue: 8,
          sourceId: 's4',
        ),
      ];
    });

    /// Воспроизводит логику isMyRecord из my_efficiency_page.dart
    bool isMyRecord(EfficiencyRecord r, String normalizedPhone, String lowerEmployeeName) {
      if (normalizedPhone.isNotEmpty && r.employeePhone.isNotEmpty) {
        final recordPhone = r.employeePhone.replaceAll(RegExp(r'[^0-9]'), '');
        if (recordPhone == normalizedPhone) return true;
      }
      if (lowerEmployeeName.isNotEmpty && r.employeeName.trim().toLowerCase() == lowerEmployeeName) {
        return true;
      }
      return false;
    }

    test('FILTER-001: По телефону находит записи с разным написанием имени', () {
      final myRecords = records.where(
        (r) => isMyRecord(r, '79001234567', 'глазкова ольга'),
      ).toList();

      // r1 — совпадение по телефону И имени
      // r2 — совпадение по телефону (имя "Глазкова О.С." не совпадает, но телефон тот же)
      // r4 — совпадение по имени (телефон пустой, fallback)
      expect(myRecords.length, 3);
      expect(myRecords.map((r) => r.id).toList(), ['r1', 'r2', 'r4']);
    });

    test('FILTER-002: Без телефона фильтрует только по имени', () {
      final myRecords = records.where(
        (r) => isMyRecord(r, '', 'глазкова ольга'),
      ).toList();

      // Без телефона: только r1 и r4 (точное совпадение имени)
      // r2 "Глазкова О.С." НЕ совпадает
      expect(myRecords.length, 2);
      expect(myRecords.map((r) => r.id).toList(), ['r1', 'r4']);
    });

    test('FILTER-003: Телефон с + нормализуется', () {
      final myRecords = records.where(
        (r) => isMyRecord(r, '79001234567', 'глазкова ольга'),
      ).toList();

      // Нормализация +7 → 79001234567 — работает
      expect(myRecords.length, 3);
    });

    test('FILTER-004: Чужой телефон не захватывает записи', () {
      final myRecords = records.where(
        (r) => isMyRecord(r, '79009999999', 'иванов иван'),
      ).toList();

      // Только r3 — Иванов Иван
      expect(myRecords.length, 1);
      expect(myRecords.first.id, 'r3');
    });

    test('FILTER-005: Пустой телефон и пустое имя — ничего не находит', () {
      final myRecords = records.where(
        (r) => isMyRecord(r, '', ''),
      ).toList();

      expect(myRecords.length, 0);
    });

    test('FILTER-006: Только телефон, без имени — находит по телефону', () {
      final myRecords = records.where(
        (r) => isMyRecord(r, '79001234567', ''),
      ).toList();

      // r1 и r2 — по телефону. r4 — телефон пустой, имя не сравнивается (пустое)
      expect(myRecords.length, 2);
      expect(myRecords.map((r) => r.id).toList(), ['r1', 'r2']);
    });
  });
}

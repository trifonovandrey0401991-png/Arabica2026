import 'package:flutter_test/flutter_test.dart';

/// Тесты параллельного подсчёта отчётов (ReportsCounterService)
/// Проверяем что _safeCount паттерн правильно обрабатывает ошибки
void main() {
  group('ReportsCounter Parallel Safety Tests', () {
    // ==================== _safeCount PATTERN ====================

    test('RCPT-001: safeCount возвращает значение при успехе', () async {
      final result = await _safeCount(() async => 42, 'test');
      expect(result, 42);
    });

    test('RCPT-002: safeCount возвращает 0 при ошибке', () async {
      final result = await _safeCount(
        () async => throw Exception('Network error'),
        'test',
      );
      expect(result, 0);
    });

    test('RCPT-003: safeCount возвращает 0 при timeout', () async {
      final result = await _safeCount(
        () async {
          await Future.delayed(Duration(milliseconds: 50));
          throw Exception('Timeout');
        },
        'test',
      );
      expect(result, 0);
    });

    // ==================== PARALLEL EXECUTION ====================

    test('RCPT-004: Future.wait суммирует все счётчики корректно', () async {
      final results = await Future.wait<int>([
        _safeCount(() async => 5, 'reports'),
        _safeCount(() async => 3, 'withdrawals'),
        _safeCount(() async => 2, 'envelopes'),
        _safeCount(() async => 7, 'reviews'),
      ]);

      final total = results.fold(0, (sum, count) => sum + count);
      expect(total, 17);
    });

    test('RCPT-005: Ошибка в одном счётчике не ломает остальные', () async {
      final results = await Future.wait<int>([
        _safeCount(() async => 5, 'reports'),
        _safeCount(() async => throw Exception('DB down'), 'withdrawals'),
        _safeCount(() async => 2, 'envelopes'),
        _safeCount(() async => throw Exception('Timeout'), 'reviews'),
      ]);

      final total = results.fold(0, (sum, count) => sum + count);
      expect(total, 7); // 5 + 0 + 2 + 0
    });

    test('RCPT-006: Все счётчики ошибочные — возвращает 0', () async {
      final results = await Future.wait<int>([
        _safeCount(() async => throw Exception('Error 1'), 'a'),
        _safeCount(() async => throw Exception('Error 2'), 'b'),
        _safeCount(() async => throw Exception('Error 3'), 'c'),
      ]);

      final total = results.fold(0, (sum, count) => sum + count);
      expect(total, 0);
    });

    test('RCPT-007: 12 параллельных счётчиков выполняются', () async {
      final results = await Future.wait<int>(
        List.generate(12, (i) => _safeCount(() async => i + 1, 'counter_$i')),
      );

      expect(results.length, 12);
      // Сумма 1+2+3+...+12 = 78
      final total = results.fold(0, (sum, count) => sum + count);
      expect(total, 78);
    });

    test('RCPT-008: Параллельное выполнение быстрее последовательного', () async {
      // Каждый "запрос" занимает 50мс
      final sw = Stopwatch()..start();
      await Future.wait<int>([
        _safeCount(() async {
          await Future.delayed(Duration(milliseconds: 50));
          return 1;
        }, 'a'),
        _safeCount(() async {
          await Future.delayed(Duration(milliseconds: 50));
          return 2;
        }, 'b'),
        _safeCount(() async {
          await Future.delayed(Duration(milliseconds: 50));
          return 3;
        }, 'c'),
      ]);
      sw.stop();

      // Параллельно = ~50мс, последовательно = ~150мс
      // Допускаем до 120мс (запас на CI)
      expect(sw.elapsedMilliseconds, lessThan(120));
    });
  });
}

/// Копия паттерна _safeCount из ReportsCounterService для тестирования
Future<int> _safeCount(Future<int> Function() fn, String label) async {
  try {
    return await fn();
  } catch (e) {
    return 0;
  }
}

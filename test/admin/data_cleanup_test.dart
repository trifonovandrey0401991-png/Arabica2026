import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P3 Тесты очистки данных для роли АДМИНИСТРАТОР
/// Покрывает: Очистка по категориям, подтверждение, история
void main() {
  group('Data Cleanup Tests (P3)', () {
    late MockDataCleanupService mockCleanupService;

    setUp(() async {
      mockCleanupService = MockDataCleanupService();
    });

    tearDown(() async {
      mockCleanupService.clear();
    });

    // ==================== КАТЕГОРИИ ОЧИСТКИ ====================

    group('Cleanup Categories Tests', () {
      test('AT-CLN-001: Получение списка категорий для очистки', () async {
        // Act
        final categories = await mockCleanupService.getCleanupCategories();

        // Assert
        expect(categories, isA<List>());
        expect(categories.isNotEmpty, true);
      });

      test('AT-CLN-002: Категория содержит описание и размер данных', () async {
        // Act
        final categories = await mockCleanupService.getCleanupCategories();

        // Assert
        for (final category in categories) {
          expect(category['id'], isNotNull);
          expect(category['name'], isNotNull);
          expect(category['description'], isNotNull);
          expect(category['dataSize'], isNotNull);
        }
      });

      test('AT-CLN-003: Очистка старых отчётов пересменок', () async {
        // Act
        final result = await mockCleanupService.cleanup(
          category: 'shift_reports',
          olderThan: DateTime.now().subtract(Duration(days: 90)),
        );

        // Assert
        expect(result['success'], true);
        expect(result['deletedCount'], isA<int>());
      });

      test('AT-CLN-004: Очистка старых отчётов конвертов', () async {
        // Act
        final result = await mockCleanupService.cleanup(
          category: 'envelope_reports',
          olderThan: DateTime.now().subtract(Duration(days: 90)),
        );

        // Assert
        expect(result['success'], true);
      });

      test('AT-CLN-005: Очистка логов', () async {
        // Act
        final result = await mockCleanupService.cleanup(
          category: 'logs',
          olderThan: DateTime.now().subtract(Duration(days: 30)),
        );

        // Assert
        expect(result['success'], true);
      });

      test('AT-CLN-006: Очистка временных файлов', () async {
        // Act
        final result = await mockCleanupService.cleanup(
          category: 'temp_files',
          olderThan: DateTime.now().subtract(Duration(days: 7)),
        );

        // Assert
        expect(result['success'], true);
      });
    });

    // ==================== ПОДТВЕРЖДЕНИЕ ====================

    group('Confirmation Tests', () {
      test('AT-CLN-007: Предварительный просмотр данных для удаления', () async {
        // Act
        final preview = await mockCleanupService.previewCleanup(
          category: 'shift_reports',
          olderThan: DateTime.now().subtract(Duration(days: 90)),
        );

        // Assert
        expect(preview['itemsToDelete'], isA<int>());
        expect(preview['sizeToFree'], isA<String>());
      });

      test('AT-CLN-008: Очистка требует подтверждения', () async {
        // Act - try to cleanup without confirmation
        final result = await mockCleanupService.cleanup(
          category: 'shift_reports',
          olderThan: DateTime.now().subtract(Duration(days: 90)),
          confirmed: false,
        );

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('confirmation'));
      });

      test('AT-CLN-009: Очистка с подтверждением проходит', () async {
        // Act
        final result = await mockCleanupService.cleanup(
          category: 'shift_reports',
          olderThan: DateTime.now().subtract(Duration(days: 90)),
          confirmed: true,
        );

        // Assert
        expect(result['success'], true);
      });
    });

    // ==================== ИСТОРИЯ ====================

    group('History Tests', () {
      test('AT-CLN-010: Запись в историю очистки', () async {
        // Arrange
        await mockCleanupService.cleanup(
          category: 'logs',
          olderThan: DateTime.now().subtract(Duration(days: 30)),
          confirmed: true,
        );

        // Act
        final history = await mockCleanupService.getCleanupHistory();

        // Assert
        expect(history.length, greaterThan(0));
      });

      test('AT-CLN-011: История содержит детали очистки', () async {
        // Arrange
        await mockCleanupService.cleanup(
          category: 'temp_files',
          olderThan: DateTime.now().subtract(Duration(days: 7)),
          confirmed: true,
        );

        // Act
        final history = await mockCleanupService.getCleanupHistory();

        // Assert
        expect(history.first['category'], isNotNull);
        expect(history.first['deletedCount'], isNotNull);
        expect(history.first['timestamp'], isNotNull);
      });
    });

    // ==================== БЕЗОПАСНОСТЬ ====================

    group('Safety Tests', () {
      test('AT-CLN-012: Только админ может выполнять очистку', () async {
        // Act
        final result = await mockCleanupService.cleanup(
          category: 'logs',
          olderThan: DateTime.now().subtract(Duration(days: 30)),
          confirmed: true,
          isAdmin: false,
        );

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('permission'));
      });

      test('AT-CLN-013: Минимальный возраст данных для удаления', () async {
        // Act - try to delete data younger than 7 days
        final result = await mockCleanupService.cleanup(
          category: 'logs',
          olderThan: DateTime.now().subtract(Duration(days: 1)),
          confirmed: true,
        );

        // Assert
        expect(result['success'], false);
        expect(result['error'].toString().toLowerCase(), contains('minimum'));
      });

      test('AT-CLN-014: Защита критических данных', () async {
        // Act - try to cleanup employees (protected)
        final result = await mockCleanupService.cleanup(
          category: 'employees',
          olderThan: DateTime.now().subtract(Duration(days: 365)),
          confirmed: true,
        );

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('protected'));
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockDataCleanupService {
  final List<Map<String, dynamic>> _history = [];
  final List<String> _protectedCategories = ['employees', 'clients', 'shops'];

  Future<List<Map<String, dynamic>>> getCleanupCategories() async {
    return [
      {
        'id': 'shift_reports',
        'name': 'Отчёты пересменок',
        'description': 'Старые отчёты о пересменках',
        'dataSize': '150 MB',
        'minAge': 90,
      },
      {
        'id': 'envelope_reports',
        'name': 'Отчёты конвертов',
        'description': 'Старые отчёты по конвертам',
        'dataSize': '80 MB',
        'minAge': 90,
      },
      {
        'id': 'logs',
        'name': 'Логи',
        'description': 'Системные логи',
        'dataSize': '500 MB',
        'minAge': 30,
      },
      {
        'id': 'temp_files',
        'name': 'Временные файлы',
        'description': 'Временные файлы и кэш',
        'dataSize': '200 MB',
        'minAge': 7,
      },
    ];
  }

  Future<Map<String, dynamic>> previewCleanup({
    required String category,
    required DateTime olderThan,
  }) async {
    return {
      'category': category,
      'itemsToDelete': 150,
      'sizeToFree': '50 MB',
      'olderThan': olderThan.toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> cleanup({
    required String category,
    required DateTime olderThan,
    bool confirmed = true,
    bool isAdmin = true,
  }) async {
    // Check admin permission
    if (!isAdmin) {
      return {'success': false, 'error': 'No permission - admin only'};
    }

    // Check protected categories
    if (_protectedCategories.contains(category)) {
      return {'success': false, 'error': 'Category is protected'};
    }

    // Check confirmation
    if (!confirmed) {
      return {'success': false, 'error': 'Requires confirmation'};
    }

    // Check minimum age
    final daysDiff = DateTime.now().difference(olderThan).inDays;
    if (daysDiff < 7) {
      return {'success': false, 'error': 'Minimum age is 7 days'};
    }

    // Simulate cleanup
    final deletedCount = 50 + DateTime.now().millisecond % 100;
    final cleanupRecord = {
      'id': 'cleanup_${DateTime.now().millisecondsSinceEpoch}',
      'category': category,
      'olderThan': olderThan.toIso8601String(),
      'deletedCount': deletedCount,
      'timestamp': DateTime.now().toIso8601String(),
    };

    _history.add(cleanupRecord);

    return {
      'success': true,
      'deletedCount': deletedCount,
      'freedSpace': '${deletedCount * 2} KB',
    };
  }

  Future<List<Map<String, dynamic>>> getCleanupHistory() async {
    return _history.reversed.toList();
  }

  void clear() {
    _history.clear();
  }
}

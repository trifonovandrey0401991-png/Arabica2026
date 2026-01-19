import '../../../core/services/base_http_service.dart';
import '../models/cleanup_category.dart';

/// Сервис для получения статистики данных и очистки.
class CleanupService {
  /// Получить статистику по всем категориям данных.
  static Future<List<CleanupCategory>> getDataStats() async {
    final result = await BaseHttpService.getRaw(
      endpoint: '/api/admin/data-stats',
    );

    if (result != null && result['categories'] != null) {
      final list = result['categories'] as List<dynamic>;
      return list
          .map((json) => CleanupCategory.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Получить количество записей для удаления до указанной даты.
  static Future<int> getDeleteCount(String categoryId, DateTime beforeDate) async {
    final dateStr = beforeDate.toIso8601String().split('T').first;
    final result = await BaseHttpService.getRaw(
      endpoint: '/api/admin/cleanup-preview',
      queryParams: {
        'category': categoryId,
        'beforeDate': dateStr,
      },
    );

    if (result != null) {
      return result['count'] as int? ?? 0;
    }
    return 0;
  }

  /// Очистить данные категории до указанной даты.
  /// Возвращает количество удалённых записей или null при ошибке.
  static Future<Map<String, dynamic>?> cleanupCategory(
    String categoryId,
    DateTime beforeDate,
  ) async {
    final dateStr = beforeDate.toIso8601String().split('T').first;
    final result = await BaseHttpService.postRaw(
      endpoint: '/api/admin/cleanup',
      body: {
        'category': categoryId,
        'beforeDate': dateStr,
      },
    );

    return result;
  }
}

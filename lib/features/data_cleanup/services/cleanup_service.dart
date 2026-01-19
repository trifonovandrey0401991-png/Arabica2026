import '../../../core/services/base_http_service.dart';
import '../models/cleanup_category.dart';

/// Информация о дисковом пространстве сервера.
class DiskInfo {
  final int totalBytes;
  final int usedBytes;
  final int availableBytes;
  final int usedPercent;

  DiskInfo({
    required this.totalBytes,
    required this.usedBytes,
    required this.availableBytes,
    required this.usedPercent,
  });

  factory DiskInfo.fromJson(Map<String, dynamic> json) {
    return DiskInfo(
      totalBytes: json['totalBytes'] as int? ?? 0,
      usedBytes: json['usedBytes'] as int? ?? 0,
      availableBytes: json['availableBytes'] as int? ?? 0,
      usedPercent: json['usedPercent'] as int? ?? 0,
    );
  }

  String get formattedTotal => _formatBytes(totalBytes);
  String get formattedUsed => _formatBytes(usedBytes);
  String get formattedAvailable => _formatBytes(availableBytes);

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

/// Сервис для получения статистики данных и очистки.
class CleanupService {
  /// Получить информацию о дисковом пространстве сервера.
  static Future<DiskInfo?> getDiskInfo() async {
    final result = await BaseHttpService.getRaw(
      endpoint: '/api/admin/disk-info',
    );

    if (result != null && result['success'] == true) {
      return DiskInfo.fromJson(result);
    }
    return null;
  }

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

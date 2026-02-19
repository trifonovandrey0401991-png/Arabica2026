import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/cache_manager.dart';
import '../models/job_application_model.dart';

class JobApplicationService {
  static const String _baseEndpoint = ApiConstants.jobApplicationsEndpoint;
  static const Duration _cacheDuration = Duration(minutes: 2);

  /// Создать заявку на трудоустройство
  static Future<JobApplication?> create({
    required String fullName,
    required String phone,
    required String preferredShift,
    required List<String> shopAddresses,
  }) async {
    try {
      Logger.debug('Создание заявки на работу: $fullName');

      final result = await BaseHttpService.post<JobApplication>(
        endpoint: _baseEndpoint,
        body: {
          'fullName': fullName,
          'phone': phone,
          'preferredShift': preferredShift,
          'shopAddresses': shopAddresses,
        },
        fromJson: (json) => JobApplication.fromJson(json),
        itemKey: 'application',
      );
      if (result != null) clearCache();
      return result;
    } catch (e) {
      Logger.error('Ошибка при создании заявки', e);
      return null;
    }
  }

  /// Получить все заявки (для админа, с кешированием на 2 мин)
  static Future<List<JobApplication>> getAll({bool forceRefresh = false}) async {
    const cacheKey = 'job_applications_all';

    if (forceRefresh) CacheManager.remove(cacheKey);

    return CacheManager.getOrFetch<List<JobApplication>>(
      cacheKey,
      () async {
        try {
          Logger.debug('Загрузка заявок на работу...');

          final result = await BaseHttpService.getList<JobApplication>(
            endpoint: _baseEndpoint,
            fromJson: (json) => JobApplication.fromJson(json),
            listKey: 'applications',
          );

          // Сортируем по дате (новые сверху)
          result.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          Logger.info('Загружено ${result.length} заявок');
          return result;
        } catch (e) {
          Logger.error('Ошибка при загрузке заявок', e);
          return [];
        }
      },
      duration: _cacheDuration,
    );
  }

  /// Очистить кеш заявок
  static void clearCache() {
    CacheManager.clearByPattern('job_applications_');
  }

  /// Получить количество непросмотренных заявок
  static Future<int> getUnviewedCount() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/unviewed-count',
      );
      return result?['count'] as int? ?? 0;
    } catch (e) {
      Logger.error('Ошибка получения количества непросмотренных', e);
      return 0;
    }
  }

  /// Отметить заявку как просмотренную
  static Future<bool> markAsViewed(String id, String adminName) async {
    try {
      Logger.debug('Отметка заявки $id как просмотренной');

      final success = await BaseHttpService.simplePatch(
        endpoint: '$_baseEndpoint/$id/view',
        body: {'adminName': adminName},
      );
      if (success) clearCache();
      return success;
    } catch (e) {
      Logger.error('Ошибка при отметке заявки', e);
      return false;
    }
  }

  /// Обновить статус заявки
  static Future<bool> updateStatus(String id, String status) async {
    try {
      Logger.debug('Обновление статуса заявки $id -> $status');

      final success = await BaseHttpService.simplePatch(
        endpoint: '$_baseEndpoint/$id/status',
        body: {'status': status},
      );
      if (success) clearCache();
      return success;
    } catch (e) {
      Logger.error('Ошибка при обновлении статуса заявки', e);
      return false;
    }
  }

  /// Обновить комментарий админа
  static Future<bool> updateNotes(String id, String notes) async {
    try {
      Logger.debug('Обновление комментариев заявки $id');

      return await BaseHttpService.simplePatch(
        endpoint: '$_baseEndpoint/$id/notes',
        body: {'adminNotes': notes},
      );
    } catch (e) {
      Logger.error('Ошибка при обновлении комментариев', e);
      return false;
    }
  }
}

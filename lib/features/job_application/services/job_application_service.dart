import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/job_application_model.dart';

class JobApplicationService {
  static const String _baseEndpoint = ApiConstants.jobApplicationsEndpoint;

  /// Создать заявку на трудоустройство
  static Future<JobApplication?> create({
    required String fullName,
    required String phone,
    required String preferredShift,
    required List<String> shopAddresses,
  }) async {
    try {
      Logger.debug('Создание заявки на работу: $fullName');

      return await BaseHttpService.post<JobApplication>(
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
    } catch (e) {
      Logger.error('Ошибка при создании заявки', e);
      return null;
    }
  }

  /// Получить все заявки (для админа)
  static Future<List<JobApplication>> getAll() async {
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

      return await BaseHttpService.simplePatch(
        endpoint: '$_baseEndpoint/$id/view',
        body: {'adminName': adminName},
      );
    } catch (e) {
      Logger.error('Ошибка при отметке заявки', e);
      return false;
    }
  }
}

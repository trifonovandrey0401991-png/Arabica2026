import '../models/pending_recount_report_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class PendingRecountService {
  static const String baseEndpoint = ApiConstants.pendingRecountReportsEndpoint;

  /// Получить список непройденных пересчётов за сегодня
  static Future<List<PendingRecountReport>> getPendingReports() async {
    Logger.debug('📥 Загрузка непройденных пересчётов...');
    return await BaseHttpService.getList<PendingRecountReport>(
      endpoint: baseEndpoint,
      fromJson: (json) => PendingRecountReport.fromJson(json),
      listKey: 'reports',
    );
  }

  /// Сгенерировать пересчёты на сегодня (ручной вызов)
  static Future<bool> generateDailyReports() async {
    Logger.debug('📤 Генерация пересчётов на сегодня...');
    return await BaseHttpService.simplePost(
      endpoint: '$baseEndpoint/generate',
      body: {},
    );
  }
}

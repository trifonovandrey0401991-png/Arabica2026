import '../models/pending_shift_report_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class PendingShiftService {
  static const String baseEndpoint = ApiConstants.pendingShiftReportsEndpoint;

  /// Получить список непройденных пересменок за сегодня
  static Future<List<PendingShiftReport>> getPendingReports() async {
    Logger.debug('📥 Загрузка непройденных пересменок...');
    return await BaseHttpService.getList<PendingShiftReport>(
      endpoint: baseEndpoint,
      fromJson: (json) => PendingShiftReport.fromJson(json),
      listKey: 'reports',
    );
  }

  /// Сгенерировать пересменки на сегодня (ручной вызов)
  static Future<bool> generateDailyReports() async {
    Logger.debug('📤 Генерация пересменок на сегодня...');
    return await BaseHttpService.simplePost(
      endpoint: '$baseEndpoint/generate',
      body: {},
    );
  }
}

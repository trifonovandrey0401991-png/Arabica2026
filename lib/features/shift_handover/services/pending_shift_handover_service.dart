import '../models/pending_shift_handover_report_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class PendingShiftHandoverService {
  static const String baseEndpoint = ApiConstants.pendingShiftHandoverReportsEndpoint;

  /// Получить список непройденных сдач смен за сегодня
  static Future<List<PendingShiftHandoverReport>> getPendingReports() async {
    Logger.debug('📥 Загрузка непройденных сдач смен...');
    return await BaseHttpService.getList<PendingShiftHandoverReport>(
      endpoint: baseEndpoint,
      fromJson: (json) => PendingShiftHandoverReport.fromJson(json),
      listKey: 'reports',
    );
  }

  /// Сгенерировать сдачи смен на сегодня (ручной вызов)
  static Future<bool> generateDailyReports() async {
    Logger.debug('📤 Генерация сдач смен на сегодня...');
    return await BaseHttpService.simplePost(
      endpoint: '$baseEndpoint/generate',
      body: {},
    );
  }
}

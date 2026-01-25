import '../models/pending_shift_handover_report_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class PendingShiftHandoverService {
  /// Получить список непройденных сдач смен (pending)
  static Future<List<PendingShiftHandoverReport>> getPendingReports() async {
    Logger.debug('📥 Загрузка непройденных сдач смен...');
    return await BaseHttpService.getList<PendingShiftHandoverReport>(
      endpoint: ApiConstants.shiftHandoverPendingEndpoint,
      fromJson: (json) => PendingShiftHandoverReport.fromJson(json),
      listKey: 'items',
    );
  }

  /// Получить список просроченных сдач смен (failed)
  static Future<List<PendingShiftHandoverReport>> getFailedReports() async {
    Logger.debug('📥 Загрузка просроченных сдач смен...');
    return await BaseHttpService.getList<PendingShiftHandoverReport>(
      endpoint: ApiConstants.shiftHandoverFailedEndpoint,
      fromJson: (json) => PendingShiftHandoverReport.fromJson(json),
      listKey: 'items',
    );
  }
}

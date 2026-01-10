import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/bonus_penalty_model.dart';

/// Сервис для управления премиями и штрафами сотрудников.
///
/// Админ может начислять премии или штрафы с комментарием.
/// Записи отображаются в "Моя эффективность" сотрудника.
///
/// Основные операции:
/// - [getRecords] - список премий/штрафов за месяц
/// - [create] - создать премию или штраф
/// - [delete] - удалить запись
/// - [getSummary] - сводка для сотрудника
///
/// Интеграция:
/// - Штрафы учитываются в расчёте эффективности
/// - Отображаются на странице "Моя эффективность"
class BonusPenaltyService {
  static const String _baseEndpoint = ApiConstants.bonusPenaltiesEndpoint;

  /// Получить все премии/штрафы за месяц
  static Future<List<BonusPenalty>> getRecords({String? month, String? employeeId}) async {
    try {
      final queryParams = <String, String>{};
      if (month != null) queryParams['month'] = month;
      if (employeeId != null) queryParams['employeeId'] = employeeId;

      return await BaseHttpService.getList<BonusPenalty>(
        endpoint: _baseEndpoint,
        fromJson: (json) => BonusPenalty.fromJson(json),
        listKey: 'records',
        queryParams: queryParams.isNotEmpty ? queryParams : null,
      );
    } catch (e) {
      Logger.error('Ошибка получения премий/штрафов', e);
      return [];
    }
  }

  /// Создать премию или штраф
  static Future<BonusPenalty?> create({
    required String employeeId,
    required String employeeName,
    required String type,
    required double amount,
    required String comment,
    required String adminName,
  }) async {
    try {
      Logger.debug('POST $_baseEndpoint: $type $amount для $employeeName');

      return await BaseHttpService.post<BonusPenalty>(
        endpoint: _baseEndpoint,
        body: {
          'employeeId': employeeId,
          'employeeName': employeeName,
          'type': type,
          'amount': amount,
          'comment': comment,
          'adminName': adminName,
        },
        fromJson: (json) => BonusPenalty.fromJson(json),
        itemKey: 'record',
      );
    } catch (e) {
      Logger.error('Ошибка создания премии/штрафа', e);
      return null;
    }
  }

  /// Удалить премию/штраф
  static Future<bool> delete(String id, {String? month}) async {
    try {
      String endpoint = '$_baseEndpoint/$id';
      if (month != null) {
        endpoint = '$endpoint?month=$month';
      }

      Logger.debug('DELETE $endpoint');
      return await BaseHttpService.delete(endpoint: endpoint);
    } catch (e) {
      Logger.error('Ошибка удаления премии/штрафа', e);
      return false;
    }
  }

  /// Получить сводку для сотрудника (текущий и прошлый месяц)
  static Future<BonusPenaltySummary> getSummary(String employeeId) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/summary/$employeeId',
      );

      if (result != null) {
        Logger.debug('Получена сводка для $employeeId');
        return BonusPenaltySummary.fromJson(result);
      }
      return BonusPenaltySummary.empty();
    } catch (e) {
      Logger.error('Ошибка получения сводки', e);
      return BonusPenaltySummary.empty();
    }
  }
}

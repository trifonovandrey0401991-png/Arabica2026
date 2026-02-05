import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants/api_constants.dart';
import '../utils/logger.dart';

/// Сервис для отправки push-уведомлений сотрудникам.
///
/// Используется для уведомлений о:
/// - Статусе отчётов (одобрение/отклонение)
/// - Назначении тестов
/// - Изменении графика работы
class EmployeePushService {
  /// Отправить push об изменении статуса отчёта.
  ///
  /// [employeePhone] - телефон сотрудника
  /// [reportType] - тип отчёта: shift_handover, recount, rko, envelope
  /// [status] - статус: approved, rejected, confirmed
  /// [reportDate] - дата отчёта (опционально)
  /// [rating] - оценка (опционально)
  /// [comment] - комментарий при отклонении (опционально)
  static Future<bool> sendReportStatusPush({
    required String employeePhone,
    required String reportType,
    required String status,
    String? reportDate,
    int? rating,
    String? comment,
  }) async {
    try {
      Logger.debug('📤 Push статуса отчёта: $reportType → $status');

      final response = await http
          .post(
            Uri.parse('${ApiConstants.serverUrl}/api/push/report-status'),
            headers: ApiConstants.jsonHeaders,
            body: jsonEncode({
              'employeePhone': employeePhone,
              'reportType': reportType,
              'status': status,
              if (reportDate != null) 'reportDate': reportDate,
              if (rating != null) 'rating': rating,
              if (comment != null) 'comment': comment,
            }),
          )
          .timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Push отправлен: ${result['sent']}');
          return result['sent'] == true;
        }
      }

      Logger.debug('❌ Ошибка отправки push: ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка отправки push статуса отчёта', e);
      return false;
    }
  }

  /// Отправить push о назначении теста.
  ///
  /// [employeePhone] - телефон сотрудника
  /// [testTitle] - название теста
  /// [testId] - ID теста (опционально)
  /// [deadline] - дедлайн (опционально)
  static Future<bool> sendTestAssignedPush({
    required String employeePhone,
    required String testTitle,
    String? testId,
    String? deadline,
  }) async {
    try {
      Logger.debug('📤 Push о назначении теста: $testTitle');

      final response = await http
          .post(
            Uri.parse('${ApiConstants.serverUrl}/api/push/test-assigned'),
            headers: ApiConstants.jsonHeaders,
            body: jsonEncode({
              'employeePhone': employeePhone,
              'testTitle': testTitle,
              if (testId != null) 'testId': testId,
              if (deadline != null) 'deadline': deadline,
            }),
          )
          .timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Push о тесте отправлен');
          return result['sent'] == true;
        }
      }

      Logger.debug('❌ Ошибка отправки push о тесте: ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка отправки push о тесте', e);
      return false;
    }
  }

  /// Отправить push об изменении графика работы.
  ///
  /// [employeePhone] - телефон сотрудника
  /// [month] - месяц (YYYY-MM)
  /// [shopName] - название магазина (опционально)
  /// [changes] - описание изменений (опционально)
  static Future<bool> sendScheduleUpdatedPush({
    required String employeePhone,
    String? month,
    String? shopName,
    String? changes,
  }) async {
    try {
      Logger.debug('📤 Push об изменении графика: $month');

      final response = await http
          .post(
            Uri.parse('${ApiConstants.serverUrl}/api/push/schedule-updated'),
            headers: ApiConstants.jsonHeaders,
            body: jsonEncode({
              'employeePhone': employeePhone,
              if (month != null) 'month': month,
              if (shopName != null) 'shopName': shopName,
              if (changes != null) 'changes': changes,
            }),
          )
          .timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Push о графике отправлен');
          return result['sent'] == true;
        }
      }

      Logger.debug('❌ Ошибка отправки push о графике: ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка отправки push о графике', e);
      return false;
    }
  }
}

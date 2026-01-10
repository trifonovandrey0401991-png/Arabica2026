import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/employee_rating_model.dart';

/// Сервис для работы с рейтингом сотрудников.
///
/// Рейтинг = (Баллы эффективности / Количество смен) + Баллы за приглашения.
/// Хранится история за 3 месяца (текущий + 2 предыдущих).
///
/// Основные операции:
/// - [getRatings] - рейтинг всех сотрудников за месяц
/// - [getEmployeeRatingHistory] - история рейтинга сотрудника
/// - [calculateRatings] - пересчитать рейтинг (админ)
///
/// Топ-3 получают прокрутки колеса удачи:
/// - 1 место: 2 прокрутки
/// - 2-3 место: 1 прокрутка
class RatingService {
  static const String _baseEndpoint = ApiConstants.ratingsEndpoint;

  /// Получить рейтинг всех сотрудников за месяц
  static Future<List<EmployeeRating>> getRatings({String? month}) async {
    try {
      final queryParams = <String, String>{};
      if (month != null) queryParams['month'] = month;

      return await BaseHttpService.getList<EmployeeRating>(
        endpoint: _baseEndpoint,
        fromJson: (json) => EmployeeRating.fromJson(json),
        listKey: 'ratings',
        queryParams: queryParams.isNotEmpty ? queryParams : null,
      );
    } catch (e) {
      Logger.error('Ошибка получения рейтинга', e);
      return [];
    }
  }

  /// Получить рейтинг сотрудника за несколько месяцев
  static Future<List<MonthlyRating>> getEmployeeRatingHistory(
    String employeeId, {
    int months = 3,
  }) async {
    try {
      return await BaseHttpService.getList<MonthlyRating>(
        endpoint: '$_baseEndpoint/$employeeId',
        fromJson: (json) => MonthlyRating.fromJson(json),
        listKey: 'history',
        queryParams: {'months': months.toString()},
      );
    } catch (e) {
      Logger.error('Ошибка получения истории рейтинга', e);
      return [];
    }
  }

  /// Получить текущий рейтинг сотрудника
  static Future<EmployeeRating?> getCurrentEmployeeRating(String employeeId) async {
    try {
      final ratings = await getRatings();
      return ratings.firstWhere(
        (r) => r.employeeId == employeeId,
        orElse: () => EmployeeRating(
          employeeId: employeeId,
          employeeName: '',
          totalPoints: 0,
          shiftsCount: 0,
          referralPoints: 0,
          normalizedRating: 0,
          position: 0,
          totalEmployees: ratings.length,
        ),
      );
    } catch (e) {
      Logger.error('Ошибка получения рейтинга сотрудника', e);
      return null;
    }
  }

  /// Пересчитать рейтинг (для админа)
  static Future<bool> calculateRatings({String? month}) async {
    try {
      String endpoint = '$_baseEndpoint/calculate';
      if (month != null) {
        endpoint = '$endpoint?month=$month';
      }

      return await BaseHttpService.simplePost(
        endpoint: endpoint,
        body: {},
      );
    } catch (e) {
      Logger.error('Ошибка пересчёта рейтинга', e);
      return false;
    }
  }
}

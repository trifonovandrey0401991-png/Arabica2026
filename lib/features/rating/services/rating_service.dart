import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../models/employee_rating_model.dart';

/// Сервис для работы с рейтингом сотрудников
class RatingService {
  static const String _baseUrl = '${ApiConstants.serverUrl}/api/ratings';

  /// Получить рейтинг всех сотрудников за месяц
  static Future<List<EmployeeRating>> getRatings({String? month}) async {
    try {
      final url = month != null
          ? '$_baseUrl?month=$month'
          : _baseUrl;

      final response = await http.get(
        Uri.parse(url),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return (result['ratings'] as List?)
              ?.map((e) => EmployeeRating.fromJson(e))
              .toList() ?? [];
        }
      }
      return [];
    } catch (e) {
      print('❌ Ошибка получения рейтинга: $e');
      return [];
    }
  }

  /// Получить рейтинг сотрудника за несколько месяцев
  static Future<List<MonthlyRating>> getEmployeeRatingHistory(
    String employeeId, {
    int months = 3,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/$employeeId?months=$months'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return (result['history'] as List?)
              ?.map((e) => MonthlyRating.fromJson(e))
              .toList() ?? [];
        }
      }
      return [];
    } catch (e) {
      print('❌ Ошибка получения истории рейтинга: $e');
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
      print('❌ Ошибка получения рейтинга сотрудника: $e');
      return null;
    }
  }

  /// Пересчитать рейтинг (для админа)
  static Future<bool> calculateRatings({String? month}) async {
    try {
      final url = month != null
          ? '$_baseUrl/calculate?month=$month'
          : '$_baseUrl/calculate';

      final response = await http.post(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ Ошибка пересчёта рейтинга: $e');
      return false;
    }
  }
}

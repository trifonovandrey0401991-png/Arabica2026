import '../models/test_result_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/utils/logger.dart';

class TestResultService {
  static const String baseEndpoint = '/api/test-results';

  /// Получить все результаты тестирования
  static Future<List<TestResult>> getResults() async {
    Logger.debug('📥 Загрузка результатов тестирования с сервера...');

    return await BaseHttpService.getList<TestResult>(
      endpoint: baseEndpoint,
      fromJson: (json) => TestResult.fromJson(json),
      listKey: 'results',
    );
  }

  /// Сохранить результат теста
  static Future<bool> saveResult({
    required String employeeName,
    required String employeePhone,
    required int score,
    required int totalQuestions,
    required int timeSpent,
  }) async {
    Logger.debug('📤 Сохранение результата теста: $employeeName - $score/$totalQuestions');

    final result = await BaseHttpService.post<TestResult>(
      endpoint: baseEndpoint,
      body: {
        'id': 'test_result_${employeePhone}_${DateTime.now().millisecondsSinceEpoch}',
        'employeeName': employeeName,
        'employeePhone': employeePhone,
        'score': score,
        'totalQuestions': totalQuestions,
        'timeSpent': timeSpent,
        'completedAt': DateTime.now().toIso8601String(),
      },
      fromJson: (json) => TestResult.fromJson(json),
      itemKey: 'result',
    );

    return result != null;
  }
}

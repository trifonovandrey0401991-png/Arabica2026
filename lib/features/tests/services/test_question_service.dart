import '../models/test_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class TestQuestionService {
  static const String baseEndpoint = ApiConstants.testQuestionsEndpoint;

  /// Получить все вопросы
  static Future<List<TestQuestion>> getQuestions() async {
    Logger.debug('📥 Загрузка вопросов тестирования с сервера...');

    return await BaseHttpService.getList<TestQuestion>(
      endpoint: baseEndpoint,
      fromJson: (json) => TestQuestion.fromJson(json),
      listKey: 'questions',
    );
  }

  /// Создать новый вопрос
  static Future<TestQuestion?> createQuestion({
    required String question,
    required List<String> options,
    required String correctAnswer,
  }) async {
    Logger.debug('📤 Создание вопроса тестирования: $question');

    return await BaseHttpService.post<TestQuestion>(
      endpoint: baseEndpoint,
      body: {
        'question': question,
        'options': options,
        'correctAnswer': correctAnswer,
      },
      fromJson: (json) => TestQuestion.fromJson(json),
      itemKey: 'question',
    );
  }

  /// Обновить вопрос
  static Future<TestQuestion?> updateQuestion({
    required String id,
    String? question,
    List<String>? options,
    String? correctAnswer,
  }) async {
    Logger.debug('📤 Обновление вопроса тестирования: $id');

    final body = <String, dynamic>{};
    if (question != null) body['question'] = question;
    if (options != null) body['options'] = options;
    if (correctAnswer != null) body['correctAnswer'] = correctAnswer;

    return await BaseHttpService.put<TestQuestion>(
      endpoint: '$baseEndpoint/$id',
      body: body,
      fromJson: (json) => TestQuestion.fromJson(json),
      itemKey: 'question',
    );
  }

  /// Удалить вопрос
  static Future<bool> deleteQuestion(String id) async {
    Logger.debug('📤 Удаление вопроса тестирования: $id');

    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/$id',
    );
  }

  /// Получить все настройки теста
  static Future<({int durationMinutes, int minimumScore})> getTestSettings() async {
    try {
      final response = await BaseHttpService.getRaw(
        endpoint: ApiConstants.testSettingsEndpoint,
      );
      if (response != null && response['settings'] != null) {
        final settings = response['settings'] as Map<String, dynamic>;
        return (
          durationMinutes: settings['durationMinutes'] as int? ?? 7,
          minimumScore: settings['minimumScore'] as int? ?? 0,
        );
      }
    } catch (e) {
      Logger.warning('Не удалось загрузить настройки теста: $e');
    }
    return (durationMinutes: 7, minimumScore: 0);
  }

  /// Получить настройки теста (длительность в минутах) — обратная совместимость
  static Future<int> getTestDurationMinutes() async {
    final settings = await getTestSettings();
    return settings.durationMinutes;
  }

  /// Сохранить все настройки теста
  static Future<bool> saveTestSettings({
    required int durationMinutes,
    required int minimumScore,
  }) async {
    try {
      final response = await BaseHttpService.postRaw(
        endpoint: ApiConstants.testSettingsEndpoint,
        body: {
          'durationMinutes': durationMinutes,
          'minimumScore': minimumScore,
        },
      );
      return response != null && response['success'] == true;
    } catch (e) {
      Logger.error('Ошибка сохранения настроек теста', e);
      return false;
    }
  }

  /// Сохранить длительность теста — обратная совместимость
  static Future<bool> saveTestDurationMinutes(int minutes) async {
    return saveTestSettings(durationMinutes: minutes, minimumScore: 0);
  }
}

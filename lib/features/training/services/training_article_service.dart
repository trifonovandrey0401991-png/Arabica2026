import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/training_model.dart';
import 'core/utils/logger.dart';

class TrainingArticleService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/training-articles';

  /// Получить все статьи
  static Future<List<TrainingArticle>> getArticles() async {
    try {
      Logger.debug('📥 Загрузка статей обучения с сервера...');
      
      final response = await http.get(
        Uri.parse(baseUrl),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final articlesJson = result['articles'] as List<dynamic>;
          final articles = articlesJson
              .map((json) => TrainingArticle.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено статей обучения: ${articles.length}');
          return articles;
        } else {
          Logger.error('❌ Ошибка загрузки статей: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки статей обучения', e);
      return [];
    }
  }

  /// Создать новую статью
  static Future<TrainingArticle?> createArticle({
    required String group,
    required String title,
    required String url,
  }) async {
    try {
      Logger.debug('📤 Создание статьи обучения: $title');
      
      final requestBody = <String, dynamic>{
        'group': group,
        'title': title,
        'url': url,
      };
      
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Статья создана: ${result['article']['id']}');
          return TrainingArticle.fromJson(result['article'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка создания статьи: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания статьи обучения', e);
      return null;
    }
  }

  /// Обновить статью
  static Future<TrainingArticle?> updateArticle({
    required String id,
    String? group,
    String? title,
    String? url,
  }) async {
    try {
      Logger.debug('📤 Обновление статьи обучения: $id');
      
      final body = <String, dynamic>{};
      if (group != null) body['group'] = group;
      if (title != null) body['title'] = title;
      if (url != null) body['url'] = url;
      
      final response = await http.put(
        Uri.parse('$baseUrl/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Статья обновлена: $id');
          return TrainingArticle.fromJson(result['article'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка обновления статьи: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка обновления статьи обучения', e);
      return null;
    }
  }

  /// Удалить статью
  static Future<bool> deleteArticle(String id) async {
    try {
      Logger.debug('📤 Удаление статьи обучения: $id');
      
      final response = await http.delete(
        Uri.parse('$baseUrl/$id'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Статья удалена: $id');
          return true;
        } else {
          Logger.error('❌ Ошибка удаления статьи: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка удаления статьи обучения', e);
      return false;
    }
  }
}



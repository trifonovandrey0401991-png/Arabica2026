import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../models/shift_question_model.dart';
import '../../../core/utils/logger.dart';

class ShiftQuestionService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/shift-questions';

  /// Получить все вопросы
  static Future<List<ShiftQuestion>> getQuestions({String? shopAddress}) async {
    try {
      Logger.debug('📥 Загрузка вопросов пересменки с сервера...');
      if (shopAddress != null) {
        Logger.debug('   Фильтр по магазину: $shopAddress');
      }
      
      final uri = shopAddress != null
          ? Uri.parse(baseUrl).replace(queryParameters: {'shopAddress': shopAddress})
          : Uri.parse(baseUrl);
      
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final questionsJson = result['questions'] as List<dynamic>;
          final questions = questionsJson
              .map((json) => ShiftQuestion.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено вопросов пересменки: ${questions.length}');
          return questions;
        } else {
          Logger.error('❌ Ошибка загрузки вопросов: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки вопросов пересменки', e);
      return [];
    }
  }
  
  /// Получить один вопрос по ID
  static Future<ShiftQuestion?> getQuestion(String questionId) async {
    try {
      Logger.debug('📥 Загрузка вопроса пересменки: $questionId');
      
      final response = await http.get(
        Uri.parse('$baseUrl/$questionId'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return ShiftQuestion.fromJson(result['question'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка загрузки вопроса: ${result['error']}');
          return null;
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки вопроса пересменки', e);
      return null;
    }
  }

  /// Создать новый вопрос
  static Future<ShiftQuestion?> createQuestion({
    required String question,
    String? answerFormatB,
    String? answerFormatC,
    List<String>? shops,
    Map<String, String>? referencePhotos,
  }) async {
    try {
      Logger.debug('📤 Создание вопроса пересменки: $question');
      
      final requestBody = <String, dynamic>{
        'question': question,
      };
      if (answerFormatB != null) requestBody['answerFormatB'] = answerFormatB;
      if (answerFormatC != null) requestBody['answerFormatC'] = answerFormatC;
      if (shops != null) requestBody['shops'] = shops;
      if (referencePhotos != null) requestBody['referencePhotos'] = referencePhotos;
      
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Вопрос создан: ${result['question']['id']}');
          return ShiftQuestion.fromJson(result['question'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка создания вопроса: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания вопроса пересменки', e);
      return null;
    }
  }

  /// Обновить вопрос
  static Future<ShiftQuestion?> updateQuestion({
    required String id,
    String? question,
    String? answerFormatB,
    String? answerFormatC,
    List<String>? shops,
    Map<String, String>? referencePhotos,
  }) async {
    try {
      Logger.debug('📤 Обновление вопроса пересменки: $id');
      
      final body = <String, dynamic>{};
      if (question != null) body['question'] = question;
      if (answerFormatB != null) body['answerFormatB'] = answerFormatB;
      if (answerFormatC != null) body['answerFormatC'] = answerFormatC;
      if (shops != null) body['shops'] = shops;
      if (referencePhotos != null) body['referencePhotos'] = referencePhotos;
      
      final response = await http.put(
        Uri.parse('$baseUrl/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Вопрос обновлен: $id');
          return ShiftQuestion.fromJson(result['question'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка обновления вопроса: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка обновления вопроса пересменки', e);
      return null;
    }
  }
  
  /// Загрузить эталонное фото для вопроса
  static Future<String?> uploadReferencePhoto({
    required String questionId,
    required String shopAddress,
    required File photoFile,
  }) async {
    try {
      Logger.debug('📤 Загрузка эталонного фото для вопроса: $questionId, магазин: $shopAddress');
      
      final url = '$baseUrl/$questionId/reference-photo';
      final request = http.MultipartRequest('POST', Uri.parse(url));
      
      // Добавляем файл
      request.files.add(
        await http.MultipartFile.fromPath('photo', photoFile.path),
      );
      
      // Добавляем адрес магазина
      request.fields['shopAddress'] = shopAddress;
      
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final photoUrl = result['photoUrl'] as String;
          Logger.debug('✅ Эталонное фото загружено: $photoUrl');
          return photoUrl;
        } else {
          Logger.error('❌ Ошибка загрузки эталонного фото: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки эталонного фото', e);
      return null;
    }
  }

  /// Удалить вопрос
  static Future<bool> deleteQuestion(String id) async {
    try {
      Logger.debug('📤 Удаление вопроса пересменки: $id');
      
      final response = await http.delete(
        Uri.parse('$baseUrl/$id'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Вопрос удален: $id');
          return true;
        } else {
          Logger.error('❌ Ошибка удаления вопроса: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка удаления вопроса пересменки', e);
      return false;
    }
  }
}



import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/product_question_model.dart';
import '../models/product_question_message_model.dart';
import 'core/utils/logger.dart';

class ProductQuestionService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/product-questions';

  /// Создать вопрос о товаре
  static Future<String?> createQuestion({
    required String clientPhone,
    required String clientName,
    required String shopAddress,
    required String questionText,
    String? questionImageUrl,
  }) async {
    try {
      Logger.debug('📤 Создание вопроса о товаре: $clientName, магазин: $shopAddress');
      
      final requestBody = {
        'clientPhone': clientPhone,
        'clientName': clientName,
        'shopAddress': shopAddress,
        'questionText': questionText,
        if (questionImageUrl != null) 'questionImageUrl': questionImageUrl,
      };
      
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Вопрос создан: ${result['questionId']}');
          return result['questionId'] as String?;
        } else {
          Logger.error('❌ Ошибка создания вопроса: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания вопроса: $e');
      return null;
    }
  }

  /// Получить вопросы (для сотрудников, с фильтрами)
  static Future<List<ProductQuestion>> getQuestions({
    String? shopAddress,
    bool? isAnswered,
  }) async {
    try {
      Logger.debug('📥 Загрузка вопросов: shopAddress=$shopAddress, isAnswered=$isAnswered');
      
      var url = baseUrl + '?';
      final params = <String>[];
      
      if (shopAddress != null) {
        params.add('shopAddress=${Uri.encodeComponent(shopAddress)}');
      }
      if (isAnswered != null) {
        params.add('isAnswered=$isAnswered');
      }
      
      url += params.join('&');
      
      final response = await http.get(
        Uri.parse(url),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final questionsJson = result['questions'] as List<dynamic>;
          final questions = questionsJson
              .map((json) => ProductQuestion.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено вопросов: ${questions.length}');
          return questions;
        } else {
          Logger.error('❌ Ошибка загрузки вопросов: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка загрузки вопросов: $e');
      return [];
    }
  }

  /// Получить конкретный вопрос
  static Future<ProductQuestion?> getQuestion(String questionId) async {
    try {
      Logger.debug('📥 Загрузка вопроса: $questionId');
      
      final response = await http.get(
        Uri.parse('$baseUrl/$questionId'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final question = ProductQuestion.fromJson(result['question'] as Map<String, dynamic>);
          Logger.debug('✅ Вопрос загружен: ${question.id}');
          return question;
        } else {
          Logger.error('❌ Ошибка загрузки вопроса: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки вопроса: $e');
      return null;
    }
  }

  /// Ответить на вопрос
  static Future<ProductQuestionMessage?> answerQuestion({
    required String questionId,
    required String shopAddress,
    required String text,
    String? senderPhone,
    String? imageUrl,
  }) async {
    try {
      Logger.debug('📤 Отправка ответа на вопрос: $questionId, магазин: $shopAddress');
      
      final requestBody = {
        'shopAddress': shopAddress,
        'text': text,
        if (senderPhone != null) 'senderPhone': senderPhone,
        if (imageUrl != null) 'imageUrl': imageUrl,
      };
      
      final response = await http.post(
        Uri.parse('$baseUrl/$questionId/messages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Ответ отправлен');
          if (result['message'] != null) {
            return ProductQuestionMessage.fromJson(result['message'] as Map<String, dynamic>);
          }
        } else {
          Logger.error('❌ Ошибка отправки ответа: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка отправки ответа: $e');
      return null;
    }
  }

  /// Получить диалоги клиента
  static Future<List<ProductQuestionDialog>> getClientQuestions(String clientPhone) async {
    try {
      Logger.debug('📥 Загрузка диалогов клиента: $clientPhone');
      
      final response = await http.get(
        Uri.parse('$baseUrl/client/$clientPhone'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final dialogsJson = result['dialogs'] as List<dynamic>;
          final dialogs = dialogsJson
              .map((json) => ProductQuestionDialog.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено диалогов: ${dialogs.length}');
          return dialogs;
        } else {
          Logger.error('❌ Ошибка загрузки диалогов: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка загрузки диалогов: $e');
      return [];
    }
  }

  /// Получить вопросы по магазину
  static Future<List<ProductQuestion>> getShopQuestions(String shopAddress) async {
    try {
      Logger.debug('📥 Загрузка вопросов по магазину: $shopAddress');
      
      final response = await http.get(
        Uri.parse('$baseUrl/shop/${Uri.encodeComponent(shopAddress)}'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final questionsJson = result['questions'] as List<dynamic>;
          final questions = questionsJson
              .map((json) => ProductQuestion.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено вопросов: ${questions.length}');
          return questions;
        } else {
          Logger.error('❌ Ошибка загрузки вопросов: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка загрузки вопросов: $e');
      return [];
    }
  }

  /// Загрузить фото для вопроса
  static Future<String?> uploadPhoto(String imagePath) async {
    try {
      Logger.debug('📤 Загрузка фото: $imagePath');
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/upload-photo'),
      );
      
      request.files.add(await http.MultipartFile.fromPath('photo', imagePath));
      
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Фото загружено: ${result['photoUrl']}');
          return result['photoUrl'] as String?;
        } else {
          Logger.error('❌ Ошибка загрузки фото: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки фото: $e');
      return null;
    }
  }
}




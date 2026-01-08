import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/product_question_model.dart';
import '../models/product_question_message_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

// Endpoints
const String _baseEndpoint = '/api/product-questions';
const String _dialogsEndpoint = '/api/product-question-dialogs';

class ProductQuestionService {
  static const String baseEndpoint = '/api/product-questions';

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
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(requestBody),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Вопрос создан: ${result['questionId']}');
          return result['questionId'] as String?;
        } else {
          Logger.error('❌ Ошибка создания вопроса: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания вопроса', e);
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

      final queryParams = <String, String>{};
      if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
      if (isAnswered != null) queryParams['isAnswered'] = isAnswered.toString();

      final uri = Uri.parse('${ApiConstants.serverUrl}$baseEndpoint')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

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
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка загрузки вопросов', e);
      return [];
    }
  }

  /// Получить конкретный вопрос
  static Future<ProductQuestion?> getQuestion(String questionId) async {
    try {
      Logger.debug('📥 Загрузка вопроса: $questionId');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$questionId'),
      ).timeout(ApiConstants.defaultTimeout);

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
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки вопроса', e);
      return null;
    }
  }

  /// Ответить на вопрос
  static Future<ProductQuestionMessage?> answerQuestion({
    required String questionId,
    required String shopAddress,
    required String text,
    String? senderPhone,
    String? senderName,
    String? imageUrl,
  }) async {
    try {
      Logger.debug('📤 Отправка ответа на вопрос: $questionId, магазин: $shopAddress');

      final requestBody = {
        'shopAddress': shopAddress,
        'text': text,
        if (senderPhone != null) 'senderPhone': senderPhone,
        if (senderName != null) 'senderName': senderName,
        if (imageUrl != null) 'imageUrl': imageUrl,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$questionId/messages'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(requestBody),
      ).timeout(ApiConstants.longTimeout);

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
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка отправки ответа', e);
      return null;
    }
  }

  /// Получить диалоги клиента (старый метод для совместимости)
  static Future<List<ProductQuestionDialog>> getClientQuestions(String clientPhone) async {
    try {
      Logger.debug('📥 Загрузка диалогов клиента: $clientPhone');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/client/$clientPhone'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final dialogsJson = result['dialogs'] as List<dynamic>? ?? [];
          final dialogs = dialogsJson
              .map((json) => ProductQuestionDialog.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено диалогов: ${dialogs.length}');
          return dialogs;
        } else {
          Logger.error('❌ Ошибка загрузки диалогов: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка загрузки диалогов', e);
      return [];
    }
  }

  /// Получить данные диалога клиента (единый чат "Поиск Товара")
  static Future<ProductQuestionClientDialogData?> getClientDialog(String clientPhone) async {
    try {
      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s+]'), '');
      Logger.debug('📥 Загрузка диалога клиента: $normalizedPhone');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/client/$normalizedPhone'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final data = ProductQuestionClientDialogData.fromJson(result);
          Logger.debug('✅ Загружено сообщений: ${data.messages.length}, hasQuestions: ${data.hasQuestions}');
          return data;
        } else {
          Logger.error('❌ Ошибка загрузки диалога: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки диалога', e);
      return null;
    }
  }

  /// Отправить ответ клиента (продолжить диалог)
  static Future<ProductQuestionMessage?> sendClientReply({
    required String clientPhone,
    required String text,
    String? imageUrl,
    String? questionId,
  }) async {
    try {
      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s+]'), '');
      Logger.debug('📤 Отправка ответа клиента: $normalizedPhone');

      final requestBody = {
        'text': text,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (questionId != null) 'questionId': questionId,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/client/$normalizedPhone/reply'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(requestBody),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Ответ клиента отправлен');
          if (result['message'] != null) {
            return ProductQuestionMessage.fromJson(result['message'] as Map<String, dynamic>);
          }
        } else {
          Logger.error('❌ Ошибка отправки ответа: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка отправки ответа клиента', e);
      return null;
    }
  }

  /// Получить вопросы по магазину
  static Future<List<ProductQuestion>> getShopQuestions(String shopAddress) async {
    try {
      Logger.debug('📥 Загрузка вопросов по магазину: $shopAddress');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/shop/${Uri.encodeComponent(shopAddress)}'),
      ).timeout(ApiConstants.defaultTimeout);

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
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка загрузки вопросов', e);
      return [];
    }
  }

  /// Загрузить фото для вопроса
  static Future<String?> uploadPhoto(String imagePath) async {
    try {
      Logger.debug('📤 Загрузка фото: $imagePath');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/upload-photo'),
      );

      request.files.add(await http.MultipartFile.fromPath('photo', imagePath));

      final streamedResponse = await request.send().timeout(ApiConstants.longTimeout);
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
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки фото', e);
      return null;
    }
  }

  // ========== Персональные диалоги ==========

  /// Создать персональный диалог с магазином
  static Future<PersonalProductDialog?> createPersonalDialog({
    required String clientPhone,
    required String clientName,
    required String shopAddress,
    String? originalQuestionId,
    String? initialMessage,
    String? initialImageUrl,
  }) async {
    try {
      Logger.debug('📤 Создание персонального диалога: $clientName → $shopAddress');

      final requestBody = {
        'clientPhone': clientPhone,
        'clientName': clientName,
        'shopAddress': shopAddress,
        if (originalQuestionId != null) 'originalQuestionId': originalQuestionId,
        if (initialMessage != null) 'initialMessage': initialMessage,
        if (initialImageUrl != null) 'initialImageUrl': initialImageUrl,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$_dialogsEndpoint'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(requestBody),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['dialog'] != null) {
          Logger.debug('✅ Диалог создан: ${result['dialog']['id']}');
          return PersonalProductDialog.fromJson(result['dialog'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка создания диалога: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания персонального диалога', e);
      return null;
    }
  }

  /// Получить все персональные диалоги клиента
  static Future<List<PersonalProductDialog>> getClientPersonalDialogs(String clientPhone) async {
    try {
      final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s+]'), '');
      Logger.debug('📥 Загрузка персональных диалогов клиента: $normalizedPhone');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$_dialogsEndpoint/client/$normalizedPhone'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final dialogsJson = result['dialogs'] as List<dynamic>? ?? [];
          final dialogs = dialogsJson
              .map((json) => PersonalProductDialog.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено персональных диалогов: ${dialogs.length}');
          return dialogs;
        } else {
          Logger.error('❌ Ошибка загрузки диалогов: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка загрузки персональных диалогов', e);
      return [];
    }
  }

  /// Получить все персональные диалоги для магазина (для сотрудников)
  static Future<List<PersonalProductDialog>> getShopPersonalDialogs(String shopAddress) async {
    try {
      Logger.debug('📥 Загрузка персональных диалогов магазина: $shopAddress');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$_dialogsEndpoint/shop/${Uri.encodeComponent(shopAddress)}'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final dialogsJson = result['dialogs'] as List<dynamic>? ?? [];
          final dialogs = dialogsJson
              .map((json) => PersonalProductDialog.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено персональных диалогов магазина: ${dialogs.length}');
          return dialogs;
        } else {
          Logger.error('❌ Ошибка загрузки диалогов: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка загрузки персональных диалогов магазина', e);
      return [];
    }
  }

  /// Получить все персональные диалоги (для сотрудников)
  static Future<List<PersonalProductDialog>> getAllPersonalDialogs() async {
    try {
      Logger.debug('📥 Загрузка всех персональных диалогов');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$_dialogsEndpoint/all'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final dialogsJson = result['dialogs'] as List<dynamic>? ?? [];
          final dialogs = dialogsJson
              .map((json) => PersonalProductDialog.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено всех диалогов: ${dialogs.length}');
          return dialogs;
        } else {
          Logger.error('❌ Ошибка загрузки диалогов: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка загрузки всех диалогов', e);
      return [];
    }
  }

  /// Получить конкретный персональный диалог
  static Future<PersonalProductDialog?> getPersonalDialog(String dialogId) async {
    try {
      Logger.debug('📥 Загрузка персонального диалога: $dialogId');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$_dialogsEndpoint/$dialogId'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['dialog'] != null) {
          final dialog = PersonalProductDialog.fromJson(result['dialog'] as Map<String, dynamic>);
          Logger.debug('✅ Диалог загружен: ${dialog.id}');
          return dialog;
        } else {
          Logger.error('❌ Ошибка загрузки диалога: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки персонального диалога', e);
      return null;
    }
  }

  /// Отправить сообщение в персональный диалог
  static Future<ProductQuestionMessage?> sendPersonalDialogMessage({
    required String dialogId,
    required String senderType,
    required String text,
    String? senderPhone,
    String? senderName,
    String? imageUrl,
  }) async {
    try {
      Logger.debug('📤 Отправка сообщения в диалог: $dialogId ($senderType)');

      final requestBody = {
        'senderType': senderType,
        'text': text,
        if (senderPhone != null) 'senderPhone': senderPhone,
        if (senderName != null) 'senderName': senderName,
        if (imageUrl != null) 'imageUrl': imageUrl,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$_dialogsEndpoint/$dialogId/messages'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(requestBody),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['message'] != null) {
          Logger.debug('✅ Сообщение отправлено');
          return ProductQuestionMessage.fromJson(result['message'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка отправки сообщения: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка отправки сообщения в диалог', e);
      return null;
    }
  }

  /// Отметить персональный диалог как прочитанный
  static Future<bool> markPersonalDialogRead({
    required String dialogId,
    required String readerType,
  }) async {
    try {
      Logger.debug('📤 Отметка диалога как прочитанного: $dialogId ($readerType)');

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$_dialogsEndpoint/$dialogId/mark-read'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({'readerType': readerType}),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Диалог отмечен как прочитанный');
          return true;
        } else {
          Logger.error('❌ Ошибка отметки диалога: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка отметки диалога', e);
      return false;
    }
  }

  /// Проверить, есть ли персональные диалоги у клиента
  static Future<bool> hasPersonalDialogs(String clientPhone) async {
    final dialogs = await getClientPersonalDialogs(clientPhone);
    return dialogs.isNotEmpty;
  }
}

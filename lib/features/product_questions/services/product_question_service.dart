import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/product_question_model.dart';
import '../models/product_question_message_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

// http и dart:convert оставлены для multipart загрузки фото

// Endpoints
const String _baseEndpoint = ApiConstants.productQuestionsEndpoint;
const String _dialogsEndpoint = ApiConstants.productQuestionDialogsEndpoint;

class ProductQuestionService {
  static const String baseEndpoint = ApiConstants.productQuestionsEndpoint;

  /// Создать вопрос о товаре
  static Future<String?> createQuestion({
    required String clientPhone,
    required String clientName,
    required String shopAddress,
    required String questionText,
    String? questionImageUrl,
  }) async {
    Logger.debug('📤 Создание вопроса о товаре: $clientName, магазин: $shopAddress');

    final requestBody = {
      'clientPhone': clientPhone,
      'clientName': clientName,
      'shopAddress': shopAddress,
      'questionText': questionText,
      if (questionImageUrl != null) 'questionImageUrl': questionImageUrl,
    };

    final result = await BaseHttpService.postRaw(
      endpoint: baseEndpoint,
      body: requestBody,
      timeout: ApiConstants.longTimeout,
    );

    if (result != null) {
      Logger.debug('✅ Вопрос создан: ${result['questionId']}');
      return result['questionId'] as String?;
    }
    return null;
  }

  /// Получить вопросы (для сотрудников, с фильтрами)
  static Future<List<ProductQuestion>> getQuestions({
    String? shopAddress,
    bool? isAnswered,
  }) async {
    Logger.debug('📥 Загрузка вопросов: shopAddress=$shopAddress, isAnswered=$isAnswered');

    final queryParams = <String, String>{};
    if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
    if (isAnswered != null) queryParams['isAnswered'] = isAnswered.toString();

    return await BaseHttpService.getList<ProductQuestion>(
      endpoint: baseEndpoint,
      fromJson: (json) => ProductQuestion.fromJson(json),
      listKey: 'questions',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
  }

  /// Получить конкретный вопрос
  static Future<ProductQuestion?> getQuestion(String questionId) async {
    Logger.debug('📥 Загрузка вопроса: $questionId');
    return await BaseHttpService.get<ProductQuestion>(
      endpoint: '$baseEndpoint/$questionId',
      fromJson: (json) => ProductQuestion.fromJson(json),
      itemKey: 'question',
    );
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
    Logger.debug('📤 Отправка ответа на вопрос: $questionId, магазин: $shopAddress');

    final requestBody = {
      'shopAddress': shopAddress,
      'text': text,
      if (senderPhone != null) 'senderPhone': senderPhone,
      if (senderName != null) 'senderName': senderName,
      if (imageUrl != null) 'imageUrl': imageUrl,
    };

    return await BaseHttpService.post<ProductQuestionMessage>(
      endpoint: '$baseEndpoint/$questionId/messages',
      body: requestBody,
      fromJson: (json) => ProductQuestionMessage.fromJson(json),
      itemKey: 'message',
      timeout: ApiConstants.longTimeout,
    );
  }

  /// Получить диалоги клиента (старый метод для совместимости)
  static Future<List<ProductQuestionDialog>> getClientQuestions(String clientPhone) async {
    Logger.debug('📥 Загрузка диалогов клиента: $clientPhone');
    return await BaseHttpService.getList<ProductQuestionDialog>(
      endpoint: '$baseEndpoint/client/$clientPhone',
      fromJson: (json) => ProductQuestionDialog.fromJson(json),
      listKey: 'dialogs',
    );
  }

  /// Получить данные диалога клиента (единый чат "Поиск Товара")
  static Future<ProductQuestionClientDialogData?> getClientDialog(String clientPhone) async {
    final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s+]'), '');
    Logger.debug('📥 Загрузка диалога клиента: $normalizedPhone');

    final result = await BaseHttpService.getRaw(
      endpoint: '$baseEndpoint/client/$normalizedPhone',
    );

    if (result != null) {
      final data = ProductQuestionClientDialogData.fromJson(result);
      Logger.debug('✅ Загружено сообщений: ${data.messages.length}, hasQuestions: ${data.hasQuestions}');
      return data;
    }
    return null;
  }

  /// Получить группированные диалоги клиента (по магазинам)
  static Future<ProductQuestionGroupedData?> getClientGroupedDialogs(String clientPhone) async {
    final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s+]'), '');
    Logger.debug('📥 Загрузка группированных диалогов: $normalizedPhone');

    final result = await BaseHttpService.getRaw(
      endpoint: '$baseEndpoint/client/$normalizedPhone/grouped',
    );

    if (result != null) {
      final data = ProductQuestionGroupedData.fromJson(result);
      Logger.debug('✅ Загружено ${data.byShop.length} магазинов, общий unread: ${data.totalUnread}');
      return data;
    }
    return null;
  }

  /// Отправить ответ клиента (продолжить диалог)
  static Future<ProductQuestionMessage?> sendClientReply({
    required String clientPhone,
    required String text,
    String? imageUrl,
    String? questionId,
  }) async {
    final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s+]'), '');
    Logger.debug('📤 Отправка ответа клиента: $normalizedPhone');

    final requestBody = {
      'text': text,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (questionId != null) 'questionId': questionId,
    };

    return await BaseHttpService.post<ProductQuestionMessage>(
      endpoint: '$baseEndpoint/client/$normalizedPhone/reply',
      body: requestBody,
      fromJson: (json) => ProductQuestionMessage.fromJson(json),
      itemKey: 'message',
      timeout: ApiConstants.longTimeout,
    );
  }

  /// Получить вопросы по магазину
  static Future<List<ProductQuestion>> getShopQuestions(String shopAddress) async {
    Logger.debug('📥 Загрузка вопросов по магазину: $shopAddress');
    return await BaseHttpService.getList<ProductQuestion>(
      endpoint: '$baseEndpoint/shop/${Uri.encodeComponent(shopAddress)}',
      fromJson: (json) => ProductQuestion.fromJson(json),
      listKey: 'questions',
    );
  }

  /// Загрузить фото для вопроса (multipart upload)
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
        }
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
    Logger.debug('📤 Создание персонального диалога: $clientName → $shopAddress');

    final requestBody = {
      'clientPhone': clientPhone,
      'clientName': clientName,
      'shopAddress': shopAddress,
      if (originalQuestionId != null) 'originalQuestionId': originalQuestionId,
      if (initialMessage != null) 'initialMessage': initialMessage,
      if (initialImageUrl != null) 'initialImageUrl': initialImageUrl,
    };

    return await BaseHttpService.post<PersonalProductDialog>(
      endpoint: _dialogsEndpoint,
      body: requestBody,
      fromJson: (json) => PersonalProductDialog.fromJson(json),
      itemKey: 'dialog',
      timeout: ApiConstants.longTimeout,
    );
  }

  /// Получить все персональные диалоги клиента
  static Future<List<PersonalProductDialog>> getClientPersonalDialogs(String clientPhone) async {
    final normalizedPhone = clientPhone.replaceAll(RegExp(r'[\s+]'), '');
    Logger.debug('📥 Загрузка персональных диалогов клиента: $normalizedPhone');
    return await BaseHttpService.getList<PersonalProductDialog>(
      endpoint: '$_dialogsEndpoint/client/$normalizedPhone',
      fromJson: (json) => PersonalProductDialog.fromJson(json),
      listKey: 'dialogs',
    );
  }

  /// Получить все персональные диалоги для магазина (для сотрудников)
  static Future<List<PersonalProductDialog>> getShopPersonalDialogs(String shopAddress) async {
    Logger.debug('📥 Загрузка персональных диалогов магазина: $shopAddress');
    return await BaseHttpService.getList<PersonalProductDialog>(
      endpoint: '$_dialogsEndpoint/shop/${Uri.encodeComponent(shopAddress)}',
      fromJson: (json) => PersonalProductDialog.fromJson(json),
      listKey: 'dialogs',
    );
  }

  /// Получить все персональные диалоги (для сотрудников)
  static Future<List<PersonalProductDialog>> getAllPersonalDialogs() async {
    Logger.debug('📥 Загрузка всех персональных диалогов');
    return await BaseHttpService.getList<PersonalProductDialog>(
      endpoint: '$_dialogsEndpoint/all',
      fromJson: (json) => PersonalProductDialog.fromJson(json),
      listKey: 'dialogs',
    );
  }

  /// Получить конкретный персональный диалог
  static Future<PersonalProductDialog?> getPersonalDialog(String dialogId) async {
    Logger.debug('📥 Загрузка персонального диалога: $dialogId');
    return await BaseHttpService.get<PersonalProductDialog>(
      endpoint: '$_dialogsEndpoint/$dialogId',
      fromJson: (json) => PersonalProductDialog.fromJson(json),
      itemKey: 'dialog',
    );
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
    Logger.debug('📤 Отправка сообщения в диалог: $dialogId ($senderType)');

    final requestBody = {
      'senderType': senderType,
      'text': text,
      if (senderPhone != null) 'senderPhone': senderPhone,
      if (senderName != null) 'senderName': senderName,
      if (imageUrl != null) 'imageUrl': imageUrl,
    };

    return await BaseHttpService.post<ProductQuestionMessage>(
      endpoint: '$_dialogsEndpoint/$dialogId/messages',
      body: requestBody,
      fromJson: (json) => ProductQuestionMessage.fromJson(json),
      itemKey: 'message',
      timeout: ApiConstants.longTimeout,
    );
  }

  /// Отметить персональный диалог как прочитанный
  static Future<bool> markPersonalDialogRead({
    required String dialogId,
    required String readerType,
  }) async {
    Logger.debug('📤 Отметка диалога как прочитанного: $dialogId ($readerType)');
    return await BaseHttpService.simplePost(
      endpoint: '$_dialogsEndpoint/$dialogId/mark-read',
      body: {'readerType': readerType},
    );
  }

  /// Проверить, есть ли персональные диалоги у клиента
  static Future<bool> hasPersonalDialogs(String clientPhone) async {
    final dialogs = await getClientPersonalDialogs(clientPhone);
    return dialogs.isNotEmpty;
  }
}

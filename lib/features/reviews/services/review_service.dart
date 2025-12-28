import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/review_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

/// Сервис для работы с отзывами
class ReviewService {
  /// Создать новый отзыв
  static Future<Review?> createReview({
    required String clientPhone,
    required String clientName,
    required String shopAddress,
    required String reviewType,
    required String reviewText,
  }) async {
    try {
      Logger.debug('📤 Создание отзыва для клиента: $clientName');

      final body = {
        'clientPhone': clientPhone,
        'clientName': clientName,
        'shopAddress': shopAddress,
        'reviewType': reviewType,
        'reviewText': reviewText,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}${ApiConstants.reviewsEndpoint}'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(body),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Отзыв успешно создан');
          return Review.fromJson(result['review']);
        } else {
          Logger.error('❌ Ошибка создания отзыва: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return null;
    } on http.ClientException catch (e) {
      Logger.error('❌ Сетевая ошибка (CORS/SSL/Network)', e);
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания отзыва', e);
      return null;
    }
  }

  /// Получить все отзывы (для админа)
  static Future<List<Review>> getAllReviews() async {
    try {
      Logger.debug('📥 Загрузка всех отзывов');

      final reviews = await BaseHttpService.getList<Review>(
        endpoint: ApiConstants.reviewsEndpoint,
        fromJson: (json) => Review.fromJson(json),
        listKey: 'reviews',
        timeout: ApiConstants.longTimeout,
      );

      // Сортируем по дате создания (новые первыми)
      reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return reviews;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки отзывов', e);
      return [];
    }
  }

  /// Получить отзывы клиента по телефону
  static Future<List<Review>> getClientReviews(String phone) async {
    try {
      Logger.debug('📥 Загрузка отзывов клиента: $phone');

      final reviews = await BaseHttpService.getList<Review>(
        endpoint: ApiConstants.reviewsEndpoint,
        fromJson: (json) => Review.fromJson(json),
        listKey: 'reviews',
        queryParams: {'phone': phone},
        timeout: ApiConstants.longTimeout,
      );

      // Сортируем по дате создания (новые первыми)
      reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return reviews;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки отзывов клиента', e);
      return [];
    }
  }

  /// Добавить сообщение в диалог
  static Future<bool> addMessage({
    required String reviewId,
    required String sender,
    required String senderName,
    required String text,
  }) async {
    try {
      Logger.debug('📤 Отправка сообщения в отзыв: $reviewId');

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}${ApiConstants.reviewsEndpoint}/$reviewId/messages'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'sender': sender,
          'senderName': senderName,
          'text': text,
        }),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Сообщение отправлено');
          return true;
        }
      }
      Logger.error('❌ HTTP ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка отправки сообщения', e);
      return false;
    }
  }

  /// Отметить сообщение как прочитанное
  static Future<bool> markMessageAsRead({
    required String reviewId,
    required String messageId,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}${ApiConstants.reviewsEndpoint}/$reviewId/messages/$messageId/read'),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка отметки сообщения', e);
      return false;
    }
  }

  /// Получить отзыв по ID
  static Future<Review?> getReviewById(String reviewId) async {
    return await BaseHttpService.get<Review>(
      endpoint: '${ApiConstants.reviewsEndpoint}/$reviewId',
      fromJson: (json) => Review.fromJson(json),
      itemKey: 'review',
      timeout: ApiConstants.longTimeout,
    );
  }
}


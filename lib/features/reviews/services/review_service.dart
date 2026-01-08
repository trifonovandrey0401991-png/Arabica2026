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

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}${ApiConstants.reviewsEndpoint}'),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final items = result['reviews'] as List<dynamic>;
          final reviews = <Review>[];

          for (final item in items) {
            // Пропускаем элементы, которые не являются Map или не имеют поля 'id'
            if (item is Map<String, dynamic> && item.containsKey('id') && item['id'] != null) {
              try {
                reviews.add(Review.fromJson(item));
              } catch (e) {
                Logger.debug('⚠️ Пропущен некорректный отзыв: ${item['id']}');
              }
            } else if (item is List) {
              // Обрабатываем вложенный массив (на случай если есть)
              for (final subItem in item) {
                if (subItem is Map<String, dynamic> && subItem.containsKey('id') && subItem['id'] != null) {
                  try {
                    reviews.add(Review.fromJson(subItem));
                  } catch (e) {
                    Logger.debug('⚠️ Пропущен некорректный отзыв из вложенного массива');
                  }
                }
              }
            }
          }

          // Сортируем по дате создания (новые первыми)
          reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          Logger.debug('✅ Загружено ${reviews.length} отзывов');
          return reviews;
        }
      }
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка загрузки отзывов', e);
      return [];
    }
  }

  /// Получить отзывы клиента по телефону
  static Future<List<Review>> getClientReviews(String phone) async {
    try {
      Logger.debug('📥 Загрузка отзывов клиента: $phone');

      final uri = Uri.parse('${ApiConstants.serverUrl}${ApiConstants.reviewsEndpoint}')
          .replace(queryParameters: {'phone': phone});

      final response = await http.get(uri).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final items = result['reviews'] as List<dynamic>;
          final reviews = <Review>[];

          for (final item in items) {
            if (item is Map<String, dynamic> && item.containsKey('id') && item['id'] != null) {
              try {
                reviews.add(Review.fromJson(item));
              } catch (e) {
                Logger.debug('⚠️ Пропущен некорректный отзыв');
              }
            } else if (item is List) {
              for (final subItem in item) {
                if (subItem is Map<String, dynamic> && subItem.containsKey('id') && subItem['id'] != null) {
                  try {
                    reviews.add(Review.fromJson(subItem));
                  } catch (e) {
                    Logger.debug('⚠️ Пропущен некорректный отзыв из вложенного массива');
                  }
                }
              }
            }
          }

          // Сортируем по дате создания (новые первыми)
          reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          Logger.debug('✅ Загружено ${reviews.length} отзывов клиента');
          return reviews;
        }
      }
      return [];
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


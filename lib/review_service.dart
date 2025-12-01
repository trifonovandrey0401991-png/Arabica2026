import 'package:http/http.dart' as http;
import 'dart:convert';
import 'review_model.dart';

/// Сервис для работы с отзывами
class ReviewService {
  static const String serverUrl = 'https://arabica26.ru';

  /// Создать новый отзыв
  static Future<Review?> createReview({
    required String clientPhone,
    required String clientName,
    required String shopAddress,
    required String reviewType,
    required String reviewText,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/api/reviews'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'clientPhone': clientPhone,
          'clientName': clientName,
          'shopAddress': shopAddress,
          'reviewType': reviewType,
          'reviewText': reviewText,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Таймаут при создании отзыва');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return Review.fromJson(result['review']);
        }
      }
      print('❌ Ошибка создания отзыва: ${response.statusCode}');
      return null;
    } catch (e) {
      print('❌ Ошибка создания отзыва: $e');
      return null;
    }
  }

  /// Получить все отзывы (для админа)
  static Future<List<Review>> getAllReviews() async {
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/api/reviews'),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Таймаут при загрузке отзывов');
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final reviews = (result['reviews'] as List<dynamic>)
              .map((r) => Review.fromJson(r as Map<String, dynamic>))
              .toList();
          // Сортируем по дате создания (новые первыми)
          reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return reviews;
        }
      }
      print('❌ Ошибка загрузки отзывов: ${response.statusCode}');
      return [];
    } catch (e) {
      print('❌ Ошибка загрузки отзывов: $e');
      return [];
    }
  }

  /// Получить отзывы клиента по телефону
  static Future<List<Review>> getClientReviews(String phone) async {
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/api/reviews?phone=$phone'),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Таймаут при загрузке отзывов');
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final reviews = (result['reviews'] as List<dynamic>)
              .map((r) => Review.fromJson(r as Map<String, dynamic>))
              .toList();
          // Сортируем по дате создания (новые первыми)
          reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return reviews;
        }
      }
      print('❌ Ошибка загрузки отзывов клиента: ${response.statusCode}');
      return [];
    } catch (e) {
      print('❌ Ошибка загрузки отзывов клиента: $e');
      return [];
    }
  }

  /// Добавить сообщение в диалог
  static Future<bool> addMessage({
    required String reviewId,
    required String sender, // 'client' или 'admin'
    required String senderName,
    required String text,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/api/reviews/$reviewId/messages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sender': sender,
          'senderName': senderName,
          'text': text,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Таймаут при отправке сообщения');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      print('❌ Ошибка отправки сообщения: ${response.statusCode}');
      return false;
    } catch (e) {
      print('❌ Ошибка отправки сообщения: $e');
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
        Uri.parse('$serverUrl/api/reviews/$reviewId/messages/$messageId/read'),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Таймаут при отметке сообщения');
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ Ошибка отметки сообщения: $e');
      return false;
    }
  }

  /// Получить отзыв по ID
  static Future<Review?> getReviewById(String reviewId) async {
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/api/reviews/$reviewId'),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Таймаут при загрузке отзыва');
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return Review.fromJson(result['review']);
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка загрузки отзыва: $e');
      return null;
    }
  }
}


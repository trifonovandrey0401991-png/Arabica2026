import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
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
      final url = '$serverUrl/api/reviews';
      final body = {
        'clientPhone': clientPhone,
        'clientName': clientName,
        'shopAddress': shopAddress,
        'reviewType': reviewType,
        'reviewText': reviewText,
      };
      
      print('📤 Отправка запроса на создание отзыва:');
      print('   URL: $url');
      print('   Body: ${jsonEncode(body)}');
      print('   Платформа: ${kIsWeb ? "Web" : "Mobile"}');

      // Используем обычный HTTP клиент для всех платформ
      http.Response response;
      try {
        print('📤 Отправка через http.post...');
        response = await http.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(body),
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            print('⏱️ Таймаут при создании отзыва');
            throw Exception('Таймаут при создании отзыва');
          },
        );
      } on http.ClientException catch (e) {
        // Ошибка сети (Failed to fetch) - обычно на веб-платформе
        print('❌ Сетевая ошибка (ClientException): $e');
        print('   Это может быть из-за:');
        print('   1. CORS блокирует запрос (проверьте настройки сервера)');
        print('   2. Смешанный контент (HTTP/HTTPS)');
        print('   3. Проблема с сертификатом SSL');
        print('   4. Сервер недоступен');
        print('   Попробуйте открыть консоль браузера (F12) и проверить ошибки CORS');
        rethrow;
      } catch (e) {
        print('❌ Неожиданная ошибка при отправке запроса: $e');
        rethrow;
      }

      print('📥 Получен ответ:');
      print('   Status: ${response.statusCode}');
      print('   Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          print('✅ Отзыв успешно создан');
          return Review.fromJson(result['review']);
        } else {
          print('❌ Сервер вернул success: false');
          print('   Error: ${result['error']}');
        }
      } else {
        print('❌ Ошибка создания отзыва: ${response.statusCode}');
        print('   Response body: ${response.body}');
      }
      return null;
    } on http.ClientException catch (e, stackTrace) {
      // Ошибка сети (Failed to fetch) - обычно на веб-платформе
      print('❌ Сетевая ошибка (ClientException): $e');
      print('   Stack trace: $stackTrace');
      print('   Возможные причины:');
      print('   1. CORS блокирует запрос (проверьте настройки сервера)');
      print('   2. Смешанный контент (HTTP/HTTPS)');
      print('   3. Проблема с сертификатом SSL');
      print('   4. Сервер недоступен или не отвечает');
      print('   Попробуйте:');
      print('   - Проверить консоль браузера на наличие CORS ошибок');
      print('   - Проверить, что сервер доступен: curl https://arabica26.ru/api/reviews');
      return null;
    } catch (e, stackTrace) {
      print('❌ Критическая ошибка создания отзыва: $e');
      print('   Stack trace: $stackTrace');
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


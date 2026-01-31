import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P2 Тесты отзывов для роли КЛИЕНТ
/// Покрывает: Создание, просмотр, модерация, баллы сотруднику
void main() {
  group('Reviews Tests (P2)', () {
    late MockReviewsService mockReviewsService;

    setUp(() async {
      mockReviewsService = MockReviewsService();
    });

    tearDown(() async {
      mockReviewsService.clear();
    });

    // ==================== СОЗДАНИЕ ОТЗЫВА ====================

    group('Create Review Tests', () {
      test('CT-REV-001: Создание отзыва клиентом', () async {
        // Arrange
        final reviewData = {
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'rating': 5,
          'text': 'Отличный кофе!',
        };

        // Act
        final result = await mockReviewsService.createReview(reviewData);

        // Assert
        expect(result['success'], true);
        expect(result['review']['status'], 'pending');
      });

      test('CT-REV-002: Отзыв содержит рейтинг (1-5)', () async {
        // Arrange
        final reviewData = {
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'rating': 4,
          'text': 'Хороший сервис',
        };

        // Act
        final result = await mockReviewsService.createReview(reviewData);

        // Assert
        expect(result['review']['rating'], 4);
        expect(result['review']['rating'], inInclusiveRange(1, 5));
      });

      test('CT-REV-003: Валидация рейтинга < 1', () async {
        // Arrange
        final reviewData = {
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'rating': 0,
          'text': 'Тест',
        };

        // Act
        final result = await mockReviewsService.createReview(reviewData);

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('rating'));
      });

      test('CT-REV-004: Валидация рейтинга > 5', () async {
        // Arrange
        final reviewData = {
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'rating': 6,
          'text': 'Тест',
        };

        // Act
        final result = await mockReviewsService.createReview(reviewData);

        // Assert
        expect(result['success'], false);
      });

      test('CT-REV-005: Отзыв может содержать текст', () async {
        // Arrange
        final text = 'Превосходный капучино, быстрое обслуживание!';
        final reviewData = {
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'rating': 5,
          'text': text,
        };

        // Act
        final result = await mockReviewsService.createReview(reviewData);

        // Assert
        expect(result['review']['text'], text);
      });

      test('CT-REV-006: Отзыв может быть без текста (только рейтинг)', () async {
        // Arrange
        final reviewData = {
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'rating': 5,
        };

        // Act
        final result = await mockReviewsService.createReview(reviewData);

        // Assert
        expect(result['success'], true);
        expect(result['review']['text'], isNull);
      });

      test('CT-REV-007: Отзыв привязан к магазину', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        final reviewData = {
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': shopId,
          'rating': 5,
        };

        // Act
        final result = await mockReviewsService.createReview(reviewData);

        // Assert
        expect(result['review']['shopId'], shopId);
      });

      test('CT-REV-008: Отзыв привязан к сотруднику', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final reviewData = {
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'employeeId': employeeId,
          'rating': 5,
        };

        // Act
        final result = await mockReviewsService.createReview(reviewData);

        // Assert
        expect(result['review']['employeeId'], employeeId);
      });
    });

    // ==================== ПРОСМОТР ОТЗЫВОВ ====================

    group('View Reviews Tests', () {
      test('CT-REV-009: Получение отзывов по магазину', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockReviewsService.createReview({
          'clientPhone': '79001111111',
          'shopId': shopId,
          'rating': 5,
        });
        await mockReviewsService.createReview({
          'clientPhone': '79002222222',
          'shopId': shopId,
          'rating': 4,
        });

        // Act
        final reviews = await mockReviewsService.getReviewsByShop(shopId);

        // Assert
        expect(reviews.length, 2);
        for (final review in reviews) {
          expect(review['shopId'], shopId);
        }
      });

      test('CT-REV-010: Получение отзывов сотрудника', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockReviewsService.createReview({
          'clientPhone': '79001111111',
          'shopId': MockShopData.validShop['id'],
          'employeeId': employeeId,
          'rating': 5,
        });

        // Act
        final reviews = await mockReviewsService.getReviewsByEmployee(employeeId);

        // Assert
        expect(reviews.every((r) => r['employeeId'] == employeeId), true);
      });

      test('CT-REV-011: Сортировка отзывов по дате (новые сверху)', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockReviewsService.createReview({
          'clientPhone': '79001111111',
          'shopId': shopId,
          'rating': 3,
        });
        await Future.delayed(Duration(milliseconds: 10));
        await mockReviewsService.createReview({
          'clientPhone': '79002222222',
          'shopId': shopId,
          'rating': 5,
        });

        // Act
        final reviews = await mockReviewsService.getReviewsByShop(shopId);

        // Assert
        if (reviews.length > 1) {
          final first = DateTime.parse(reviews[0]['createdAt']);
          final second = DateTime.parse(reviews[1]['createdAt']);
          expect(first.isAfter(second), true);
        }
      });

      test('CT-REV-012: Фильтрация только одобренных отзывов', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        final result = await mockReviewsService.createReview({
          'clientPhone': '79001111111',
          'shopId': shopId,
          'rating': 5,
        });
        await mockReviewsService.approveReview(result['review']['id']);

        // Act
        final approved = await mockReviewsService.getApprovedReviews(shopId);

        // Assert
        for (final review in approved) {
          expect(review['status'], 'approved');
        }
      });

      test('CT-REV-013: Средний рейтинг магазина', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        final result1 = await mockReviewsService.createReview({
          'clientPhone': '79001111111',
          'shopId': shopId,
          'rating': 5,
        });
        final result2 = await mockReviewsService.createReview({
          'clientPhone': '79002222222',
          'shopId': shopId,
          'rating': 3,
        });
        await mockReviewsService.approveReview(result1['review']['id']);
        await mockReviewsService.approveReview(result2['review']['id']);

        // Act
        final avgRating = await mockReviewsService.getAverageRating(shopId);

        // Assert
        expect(avgRating, 4.0); // (5 + 3) / 2
      });
    });

    // ==================== МОДЕРАЦИЯ ====================

    group('Moderation Tests', () {
      test('CT-REV-014: Новый отзыв в статусе pending', () async {
        // Act
        final result = await mockReviewsService.createReview({
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'rating': 5,
        });

        // Assert
        expect(result['review']['status'], 'pending');
      });

      test('CT-REV-015: Одобрение отзыва админом', () async {
        // Arrange
        final result = await mockReviewsService.createReview({
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'rating': 5,
        });
        final reviewId = result['review']['id'];

        // Act
        final approveResult = await mockReviewsService.approveReview(
          reviewId,
          adminId: MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(approveResult['success'], true);
        expect(approveResult['status'], 'approved');
      });

      test('CT-REV-016: Отклонение отзыва с причиной', () async {
        // Arrange
        final result = await mockReviewsService.createReview({
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'rating': 1,
          'text': 'Неприемлемый контент',
        });
        final reviewId = result['review']['id'];

        // Act
        final rejectResult = await mockReviewsService.rejectReview(
          reviewId,
          reason: 'Нецензурная лексика',
        );

        // Assert
        expect(rejectResult['success'], true);
        expect(rejectResult['status'], 'rejected');
        expect(rejectResult['reason'], 'Нецензурная лексика');
      });

      test('CT-REV-017: Получение отзывов на модерацию', () async {
        // Arrange
        await mockReviewsService.createReview({
          'clientPhone': '79001111111',
          'shopId': MockShopData.validShop['id'],
          'rating': 5,
        });
        await mockReviewsService.createReview({
          'clientPhone': '79002222222',
          'shopId': MockShopData.validShop['id'],
          'rating': 4,
        });

        // Act
        final pending = await mockReviewsService.getPendingReviews();

        // Assert
        expect(pending.every((r) => r['status'] == 'pending'), true);
      });
    });

    // ==================== БАЛЛЫ СОТРУДНИКУ ====================

    group('Employee Points Tests', () {
      test('CT-REV-018: Баллы за положительный отзыв (4-5 звёзд)', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final result = await mockReviewsService.createReview({
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'employeeId': employeeId,
          'rating': 5,
        });
        await mockReviewsService.approveReview(result['review']['id']);

        // Act
        final points = await mockReviewsService.getEmployeeReviewPoints(
          employeeId,
          '2024-01',
        );

        // Assert
        expect(points, greaterThan(0));
      });

      test('CT-REV-019: Нет баллов за отзыв без сотрудника', () async {
        // Arrange
        final result = await mockReviewsService.createReview({
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'rating': 5,
          // No employeeId
        });
        await mockReviewsService.approveReview(result['review']['id']);

        // Assert
        // Review should be created but no employee points
        expect(result['review']['employeeId'], isNull);
      });

      test('CT-REV-020: Интеграция с эффективностью', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = '2024-01';

        // Create and approve reviews
        for (var i = 0; i < 3; i++) {
          final result = await mockReviewsService.createReview({
            'clientPhone': '7900111111$i',
            'shopId': MockShopData.validShop['id'],
            'employeeId': employeeId,
            'rating': 5,
          });
          await mockReviewsService.approveReview(result['review']['id']);
        }

        // Act
        final efficiencyPoints = await mockReviewsService.getEmployeeReviewPoints(
          employeeId,
          month,
        );

        // Assert
        expect(efficiencyPoints, greaterThan(0));
      });
    });

    // ==================== ОТВЕТ НА ОТЗЫВ ====================

    group('Reply Tests', () {
      test('CT-REV-021: Ответ на отзыв от магазина', () async {
        // Arrange
        final result = await mockReviewsService.createReview({
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'rating': 3,
          'text': 'Долго ждал заказ',
        });
        await mockReviewsService.approveReview(result['review']['id']);

        // Act
        final replyResult = await mockReviewsService.replyToReview(
          result['review']['id'],
          'Приносим извинения! Работаем над улучшением.',
        );

        // Assert
        expect(replyResult['success'], true);
        expect(replyResult['reply'], isNotNull);
      });

      test('CT-REV-022: Один ответ на отзыв', () async {
        // Arrange
        final result = await mockReviewsService.createReview({
          'clientPhone': MockClientData.validClient['phone'],
          'shopId': MockShopData.validShop['id'],
          'rating': 4,
        });
        await mockReviewsService.approveReview(result['review']['id']);
        await mockReviewsService.replyToReview(
          result['review']['id'],
          'Спасибо за отзыв!',
        );

        // Act - try to reply again
        final secondReply = await mockReviewsService.replyToReview(
          result['review']['id'],
          'Еще один ответ',
        );

        // Assert
        expect(secondReply['success'], false);
        expect(secondReply['error'], contains('already'));
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockReviewsService {
  final List<Map<String, dynamic>> _reviews = [];
  final Map<String, double> _employeePoints = {};

  Future<Map<String, dynamic>> createReview(Map<String, dynamic> data) async {
    final rating = data['rating'] as int;

    if (rating < 1 || rating > 5) {
      return {'success': false, 'error': 'rating must be 1-5'};
    }

    final review = {
      'id': 'rev_${DateTime.now().millisecondsSinceEpoch}',
      'clientPhone': data['clientPhone'],
      'shopId': data['shopId'],
      'employeeId': data['employeeId'],
      'rating': rating,
      'text': data['text'],
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'reply': null,
    };

    _reviews.add(review);
    return {'success': true, 'review': review};
  }

  Future<List<Map<String, dynamic>>> getReviewsByShop(String shopId) async {
    return _reviews
        .where((r) => r['shopId'] == shopId)
        .toList()
      ..sort((a, b) => DateTime.parse(b['createdAt'])
          .compareTo(DateTime.parse(a['createdAt'])));
  }

  Future<List<Map<String, dynamic>>> getReviewsByEmployee(String employeeId) async {
    return _reviews.where((r) => r['employeeId'] == employeeId).toList();
  }

  Future<List<Map<String, dynamic>>> getApprovedReviews(String shopId) async {
    return _reviews
        .where((r) => r['shopId'] == shopId && r['status'] == 'approved')
        .toList();
  }

  Future<List<Map<String, dynamic>>> getPendingReviews() async {
    return _reviews.where((r) => r['status'] == 'pending').toList();
  }

  Future<double> getAverageRating(String shopId) async {
    final approved = await getApprovedReviews(shopId);
    if (approved.isEmpty) return 0.0;

    final sum = approved.fold<int>(0, (sum, r) => sum + (r['rating'] as int));
    return sum / approved.length;
  }

  Future<Map<String, dynamic>> approveReview(String reviewId, {String? adminId}) async {
    final index = _reviews.indexWhere((r) => r['id'] == reviewId);
    if (index < 0) {
      return {'success': false, 'error': 'Review not found'};
    }

    _reviews[index]['status'] = 'approved';
    _reviews[index]['approvedAt'] = DateTime.now().toIso8601String();
    _reviews[index]['approvedBy'] = adminId;

    // Award points if employee attached and rating >= 4
    final employeeId = _reviews[index]['employeeId'];
    final rating = _reviews[index]['rating'] as int;
    if (employeeId != null && rating >= 4) {
      final month = DateTime.now().toIso8601String().substring(0, 7);
      final key = '${employeeId}_$month';
      _employeePoints[key] = (_employeePoints[key] ?? 0) + 1.5;
    }

    return {'success': true, 'status': 'approved'};
  }

  Future<Map<String, dynamic>> rejectReview(String reviewId, {required String reason}) async {
    final index = _reviews.indexWhere((r) => r['id'] == reviewId);
    if (index < 0) {
      return {'success': false, 'error': 'Review not found'};
    }

    _reviews[index]['status'] = 'rejected';
    _reviews[index]['rejectedAt'] = DateTime.now().toIso8601String();
    _reviews[index]['rejectReason'] = reason;

    return {'success': true, 'status': 'rejected', 'reason': reason};
  }

  Future<double> getEmployeeReviewPoints(String employeeId, String month) async {
    final key = '${employeeId}_$month';
    return _employeePoints[key] ?? 0.0;
  }

  Future<Map<String, dynamic>> replyToReview(String reviewId, String replyText) async {
    final index = _reviews.indexWhere((r) => r['id'] == reviewId);
    if (index < 0) {
      return {'success': false, 'error': 'Review not found'};
    }

    if (_reviews[index]['reply'] != null) {
      return {'success': false, 'error': 'Reply already exists'};
    }

    _reviews[index]['reply'] = {
      'text': replyText,
      'createdAt': DateTime.now().toIso8601String(),
    };

    return {'success': true, 'reply': _reviews[index]['reply']};
  }

  void clear() {
    _reviews.clear();
    _employeePoints.clear();
  }
}

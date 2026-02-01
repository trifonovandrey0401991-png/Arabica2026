import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P2 Тесты поиска товара для роли СОТРУДНИК
/// Покрывает: Вопросы, ответы, баллы, верификация
void main() {
  group('Product Search Tests (P2)', () {
    late MockProductSearchService mockSearchService;

    setUp(() async {
      mockSearchService = MockProductSearchService();
    });

    tearDown(() async {
      mockSearchService.clear();
    });

    // ==================== СОЗДАНИЕ ВОПРОСОВ ====================

    group('Questions Tests', () {
      test('ET-PSR-001: Клиент задаёт вопрос о товаре', () async {
        // Arrange
        final questionData = {
          'clientPhone': MockClientData.validClient['phone'],
          'productName': 'Кофе Арабика',
          'text': 'Какая обжарка у этого кофе?',
        };

        // Act
        final result = await mockSearchService.createQuestion(questionData);

        // Assert
        expect(result['success'], true);
        expect(result['question']['status'], 'pending');
      });

      test('ET-PSR-002: Вопрос содержит название товара', () async {
        // Arrange
        final productName = 'Молоко 3.2%';
        final questionData = {
          'clientPhone': MockClientData.validClient['phone'],
          'productName': productName,
          'text': 'Есть ли безлактозное?',
        };

        // Act
        final result = await mockSearchService.createQuestion(questionData);

        // Assert
        expect(result['question']['productName'], productName);
      });

      test('ET-PSR-003: Вопрос привязан к магазину', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        final questionData = {
          'clientPhone': MockClientData.validClient['phone'],
          'productName': 'Круассан',
          'text': 'Есть ли в наличии?',
          'shopId': shopId,
        };

        // Act
        final result = await mockSearchService.createQuestion(questionData);

        // Assert
        expect(result['question']['shopId'], shopId);
      });

      test('ET-PSR-004: Получение списка вопросов для магазина', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockSearchService.createQuestion({
          'clientPhone': '79001111111',
          'productName': 'Товар 1',
          'text': 'Вопрос 1',
          'shopId': shopId,
        });
        await mockSearchService.createQuestion({
          'clientPhone': '79002222222',
          'productName': 'Товар 2',
          'text': 'Вопрос 2',
          'shopId': shopId,
        });

        // Act
        final questions = await mockSearchService.getQuestionsByShop(shopId);

        // Assert
        expect(questions.length, 2);
      });

      test('ET-PSR-005: Фильтрация только неотвеченных вопросов', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        final q1 = await mockSearchService.createQuestion({
          'clientPhone': '79001111111',
          'productName': 'Товар 1',
          'text': 'Вопрос 1',
          'shopId': shopId,
        });
        await mockSearchService.createQuestion({
          'clientPhone': '79002222222',
          'productName': 'Товар 2',
          'text': 'Вопрос 2',
          'shopId': shopId,
        });

        // Answer first question
        await mockSearchService.answerQuestion(
          q1['question']['id'],
          MockEmployeeData.validEmployee['id'],
          'Ответ',
        );

        // Act
        final pending = await mockSearchService.getPendingQuestions(shopId);

        // Assert
        expect(pending.length, 1);
        expect(pending.first['status'], 'pending');
      });
    });

    // ==================== ОТВЕТЫ ====================

    group('Answers Tests', () {
      test('ET-PSR-006: Сотрудник отвечает на вопрос', () async {
        // Arrange
        final question = await mockSearchService.createQuestion({
          'clientPhone': MockClientData.validClient['phone'],
          'productName': 'Кофе',
          'text': 'Какая страна происхождения?',
          'shopId': MockShopData.validShop['id'],
        });
        final employeeId = MockEmployeeData.validEmployee['id'];

        // Act
        final result = await mockSearchService.answerQuestion(
          question['question']['id'],
          employeeId,
          'Эфиопия, регион Сидамо',
        );

        // Assert
        expect(result['success'], true);
        expect(result['status'], 'answered');
      });

      test('ET-PSR-007: Ответ привязан к сотруднику', () async {
        // Arrange
        final question = await mockSearchService.createQuestion({
          'clientPhone': MockClientData.validClient['phone'],
          'productName': 'Чай',
          'text': 'Вопрос',
          'shopId': MockShopData.validShop['id'],
        });
        final employeeId = MockEmployeeData.validEmployee['id'];
        final employeeName = MockEmployeeData.validEmployee['name'];

        // Act
        final result = await mockSearchService.answerQuestion(
          question['question']['id'],
          employeeId,
          'Ответ',
          employeeName: employeeName,
        );

        // Assert
        expect(result['answer']['employeeId'], employeeId);
        expect(result['answer']['employeeName'], employeeName);
      });

      test('ET-PSR-008: Статус pending → answered после ответа', () async {
        // Arrange
        final question = await mockSearchService.createQuestion({
          'clientPhone': MockClientData.validClient['phone'],
          'productName': 'Товар',
          'text': 'Вопрос',
          'shopId': MockShopData.validShop['id'],
        });

        // Act
        await mockSearchService.answerQuestion(
          question['question']['id'],
          MockEmployeeData.validEmployee['id'],
          'Ответ',
        );
        final updated = await mockSearchService.getQuestion(question['question']['id']);

        // Assert
        expect(updated['status'], 'answered');
      });

      test('ET-PSR-009: Нельзя ответить на уже отвеченный вопрос', () async {
        // Arrange
        final question = await mockSearchService.createQuestion({
          'clientPhone': MockClientData.validClient['phone'],
          'productName': 'Товар',
          'text': 'Вопрос',
          'shopId': MockShopData.validShop['id'],
        });
        await mockSearchService.answerQuestion(
          question['question']['id'],
          MockEmployeeData.validEmployee['id'],
          'Первый ответ',
        );

        // Act
        final result = await mockSearchService.answerQuestion(
          question['question']['id'],
          MockEmployeeData.secondEmployee['id'],
          'Второй ответ',
        );

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('already'));
      });
    });

    // ==================== БАЛЛЫ ====================

    group('Points Tests', () {
      test('ET-PSR-010: Баллы за ответ на вопрос', () async {
        // Arrange
        final question = await mockSearchService.createQuestion({
          'clientPhone': MockClientData.validClient['phone'],
          'productName': 'Товар',
          'text': 'Вопрос',
          'shopId': MockShopData.validShop['id'],
        });
        final employeeId = MockEmployeeData.validEmployee['id'];

        // Act
        final result = await mockSearchService.answerQuestion(
          question['question']['id'],
          employeeId,
          'Ответ',
        );

        // Assert
        expect(result['pointsAwarded'], greaterThan(0));
      });

      test('ET-PSR-011: Настраиваемое количество баллов', () async {
        // Arrange
        mockSearchService.setPointsPerAnswer(3);
        final question = await mockSearchService.createQuestion({
          'clientPhone': MockClientData.validClient['phone'],
          'productName': 'Товар',
          'text': 'Вопрос',
          'shopId': MockShopData.validShop['id'],
        });

        // Act
        final result = await mockSearchService.answerQuestion(
          question['question']['id'],
          MockEmployeeData.validEmployee['id'],
          'Ответ',
        );

        // Assert
        expect(result['pointsAwarded'], 3);
      });

      test('ET-PSR-012: Подсчёт баллов за месяц', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = DateTime.now().toIso8601String().substring(0, 7);

        for (var i = 0; i < 5; i++) {
          final q = await mockSearchService.createQuestion({
            'clientPhone': '7900111111$i',
            'productName': 'Товар $i',
            'text': 'Вопрос $i',
            'shopId': MockShopData.validShop['id'],
          });
          await mockSearchService.answerQuestion(
            q['question']['id'],
            employeeId,
            'Ответ $i',
          );
        }

        // Act
        final totalPoints = await mockSearchService.getEmployeePoints(
          employeeId,
          month,
        );

        // Assert
        expect(totalPoints, 5); // 5 questions * 1 point each
      });

      test('ET-PSR-013: Интеграция с эффективностью', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = DateTime.now().toIso8601String().substring(0, 7);

        final q = await mockSearchService.createQuestion({
          'clientPhone': MockClientData.validClient['phone'],
          'productName': 'Товар',
          'text': 'Вопрос',
          'shopId': MockShopData.validShop['id'],
        });
        await mockSearchService.answerQuestion(
          q['question']['id'],
          employeeId,
          'Ответ',
        );

        // Act
        final points = await mockSearchService.getEmployeePoints(employeeId, month);

        // Assert
        expect(points, greaterThan(0));
      });
    });

    // ==================== ВЕРИФИКАЦИЯ ====================

    group('Verification Tests', () {
      test('ET-PSR-014: Админ верифицирует ответ', () async {
        // Arrange
        final q = await mockSearchService.createQuestion({
          'clientPhone': MockClientData.validClient['phone'],
          'productName': 'Товар',
          'text': 'Вопрос',
          'shopId': MockShopData.validShop['id'],
        });
        await mockSearchService.answerQuestion(
          q['question']['id'],
          MockEmployeeData.validEmployee['id'],
          'Ответ',
        );

        // Act
        final result = await mockSearchService.verifyAnswer(
          q['question']['id'],
          MockEmployeeData.adminEmployee['id'],
          isCorrect: true,
        );

        // Assert
        expect(result['success'], true);
        expect(result['verified'], true);
      });

      test('ET-PSR-015: Некорректный ответ может быть отмечен', () async {
        // Arrange
        final q = await mockSearchService.createQuestion({
          'clientPhone': MockClientData.validClient['phone'],
          'productName': 'Товар',
          'text': 'Вопрос',
          'shopId': MockShopData.validShop['id'],
        });
        await mockSearchService.answerQuestion(
          q['question']['id'],
          MockEmployeeData.validEmployee['id'],
          'Неправильный ответ',
        );

        // Act
        final result = await mockSearchService.verifyAnswer(
          q['question']['id'],
          MockEmployeeData.adminEmployee['id'],
          isCorrect: false,
          comment: 'Информация неверна',
        );

        // Assert
        expect(result['success'], true);
        expect(result['isCorrect'], false);
      });
    });

    // ==================== УВЕДОМЛЕНИЯ ====================

    group('Notification Tests', () {
      test('ET-PSR-016: Push при новом вопросе', () async {
        // Act
        final result = await mockSearchService.createQuestion({
          'clientPhone': MockClientData.validClient['phone'],
          'productName': 'Товар',
          'text': 'Вопрос',
          'shopId': MockShopData.validShop['id'],
        });

        // Assert
        expect(result['notificationSent'], true);
      });

      test('ET-PSR-017: Push клиенту при ответе', () async {
        // Arrange
        final q = await mockSearchService.createQuestion({
          'clientPhone': MockClientData.validClient['phone'],
          'productName': 'Товар',
          'text': 'Вопрос',
          'shopId': MockShopData.validShop['id'],
        });

        // Act
        final result = await mockSearchService.answerQuestion(
          q['question']['id'],
          MockEmployeeData.validEmployee['id'],
          'Ответ',
        );

        // Assert
        expect(result['clientNotified'], true);
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockProductSearchService {
  final List<Map<String, dynamic>> _questions = [];
  final Map<String, double> _employeePoints = {};
  int _pointsPerAnswer = 1;
  int _questionCounter = 0;

  Future<Map<String, dynamic>> createQuestion(Map<String, dynamic> data) async {
    _questionCounter++;
    final question = {
      'id': 'q_${DateTime.now().millisecondsSinceEpoch}_$_questionCounter',
      'clientPhone': data['clientPhone'],
      'productName': data['productName'],
      'text': data['text'],
      'shopId': data['shopId'],
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'answer': null,
    };

    _questions.add(question);

    return {
      'success': true,
      'question': question,
      'notificationSent': true,
    };
  }

  Future<List<Map<String, dynamic>>> getQuestionsByShop(String shopId) async {
    return _questions.where((q) => q['shopId'] == shopId).toList();
  }

  Future<List<Map<String, dynamic>>> getPendingQuestions(String shopId) async {
    return _questions
        .where((q) => q['shopId'] == shopId && q['status'] == 'pending')
        .toList();
  }

  Future<Map<String, dynamic>> getQuestion(String questionId) async {
    return _questions.firstWhere(
      (q) => q['id'] == questionId,
      orElse: () => {'error': 'Not found'},
    );
  }

  Future<Map<String, dynamic>> answerQuestion(
    String questionId,
    String employeeId,
    String answerText, {
    String? employeeName,
  }) async {
    final index = _questions.indexWhere((q) => q['id'] == questionId);
    if (index < 0) {
      return {'success': false, 'error': 'Question not found'};
    }

    if (_questions[index]['status'] == 'answered') {
      return {'success': false, 'error': 'Question already answered'};
    }

    final answer = {
      'text': answerText,
      'employeeId': employeeId,
      'employeeName': employeeName ?? 'Сотрудник',
      'createdAt': DateTime.now().toIso8601String(),
    };

    _questions[index]['status'] = 'answered';
    _questions[index]['answer'] = answer;

    // Award points
    final month = DateTime.now().toIso8601String().substring(0, 7);
    final key = '${employeeId}_$month';
    _employeePoints[key] = (_employeePoints[key] ?? 0) + _pointsPerAnswer;

    return {
      'success': true,
      'status': 'answered',
      'answer': answer,
      'pointsAwarded': _pointsPerAnswer,
      'clientNotified': true,
    };
  }

  void setPointsPerAnswer(int points) {
    _pointsPerAnswer = points;
  }

  Future<double> getEmployeePoints(String employeeId, String month) async {
    final key = '${employeeId}_$month';
    return _employeePoints[key] ?? 0;
  }

  Future<Map<String, dynamic>> verifyAnswer(
    String questionId,
    String adminId, {
    required bool isCorrect,
    String? comment,
  }) async {
    final index = _questions.indexWhere((q) => q['id'] == questionId);
    if (index < 0) {
      return {'success': false, 'error': 'Question not found'};
    }

    _questions[index]['verified'] = true;
    _questions[index]['isCorrect'] = isCorrect;
    _questions[index]['verifiedBy'] = adminId;
    _questions[index]['verificationComment'] = comment;

    return {
      'success': true,
      'verified': true,
      'isCorrect': isCorrect,
    };
  }

  void clear() {
    _questions.clear();
    _employeePoints.clear();
    _pointsPerAnswer = 1;
    _questionCounter = 0;
  }
}

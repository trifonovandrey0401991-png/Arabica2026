import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P2 Тесты обучения и тестирования для роли СОТРУДНИК
/// Покрывает: Статьи, тесты, автобаллы, прогресс
void main() {
  group('Training & Tests (P2)', () {
    late MockTrainingService mockTrainingService;
    late MockTestService mockTestService;

    setUp(() async {
      mockTrainingService = MockTrainingService();
      mockTestService = MockTestService();
    });

    tearDown(() async {
      mockTrainingService.clear();
      mockTestService.clear();
    });

    // ==================== СТАТЬИ ОБУЧЕНИЯ ====================

    group('Training Articles Tests', () {
      test('ET-TRN-001: Получение списка статей', () async {
        // Act
        final articles = await mockTrainingService.getArticles();

        // Assert
        expect(articles, isA<List>());
      });

      test('ET-TRN-002: Статья содержит заголовок и контент', () async {
        // Arrange
        await mockTrainingService.addArticle({
          'title': 'Как варить кофе',
          'content': 'Подробная инструкция...',
          'category': 'barista',
        });

        // Act
        final articles = await mockTrainingService.getArticles();

        // Assert
        expect(articles.first['title'], isNotNull);
        expect(articles.first['content'], isNotNull);
      });

      test('ET-TRN-003: Фильтрация статей по категории', () async {
        // Arrange
        await mockTrainingService.addArticle({
          'title': 'Статья 1',
          'content': 'Контент 1',
          'category': 'barista',
        });
        await mockTrainingService.addArticle({
          'title': 'Статья 2',
          'content': 'Контент 2',
          'category': 'service',
        });

        // Act
        final baristaArticles = await mockTrainingService.getArticlesByCategory('barista');

        // Assert
        expect(baristaArticles.every((a) => a['category'] == 'barista'), true);
      });

      test('ET-TRN-004: Отметка статьи как прочитанной', () async {
        // Arrange
        await mockTrainingService.addArticle({
          'id': 'art_001',
          'title': 'Статья',
          'content': 'Контент',
          'category': 'barista',
        });
        final employeeId = MockEmployeeData.validEmployee['id'];

        // Act
        final result = await mockTrainingService.markAsRead(
          'art_001',
          employeeId,
        );

        // Assert
        expect(result['success'], true);
      });

      test('ET-TRN-005: Прогресс чтения статей', () async {
        // Arrange
        await mockTrainingService.addArticle({
          'id': 'art_001',
          'title': 'Статья 1',
          'content': 'Контент 1',
          'category': 'barista',
        });
        await mockTrainingService.addArticle({
          'id': 'art_002',
          'title': 'Статья 2',
          'content': 'Контент 2',
          'category': 'barista',
        });
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockTrainingService.markAsRead('art_001', employeeId);

        // Act
        final progress = await mockTrainingService.getProgress(employeeId);

        // Assert
        expect(progress['read'], 1);
        expect(progress['total'], 2);
        expect(progress['percentage'], 50.0);
      });

      test('ET-TRN-006: Создание статьи (только админ)', () async {
        // Arrange
        final articleData = {
          'title': 'Новая статья',
          'content': 'Содержимое статьи',
          'category': 'barista',
        };

        // Act
        final result = await mockTrainingService.createArticle(
          articleData,
          isAdmin: true,
        );

        // Assert
        expect(result['success'], true);
      });

      test('ET-TRN-007: Не-админ не может создать статью', () async {
        // Act
        final result = await mockTrainingService.createArticle(
          {'title': 'Статья', 'content': 'Контент'},
          isAdmin: false,
        );

        // Assert
        expect(result['success'], false);
      });
    });

    // ==================== ТЕСТИРОВАНИЕ ====================

    group('Tests (Quiz) Tests', () {
      test('ET-TST-001: Получение списка доступных тестов', () async {
        // Act
        final tests = await mockTestService.getAvailableTests(
          MockEmployeeData.validEmployee['id'],
        );

        // Assert
        expect(tests, isA<List>());
      });

      test('ET-TST-002: Тест содержит вопросы', () async {
        // Arrange
        await mockTestService.addTest({
          'id': 'test_001',
          'title': 'Тест по кофе',
          'questions': [
            {
              'id': 'q1',
              'text': 'Какая температура воды для эспрессо?',
              'options': ['80°C', '90-95°C', '100°C'],
              'correctIndex': 1,
            },
          ],
        });

        // Act
        final test = await mockTestService.getTest('test_001');

        // Assert
        expect(test['questions'], isA<List>());
        expect(test['questions'].length, greaterThan(0));
      });

      test('ET-TST-003: Начало прохождения теста', () async {
        // Arrange
        await mockTestService.addTest({
          'id': 'test_001',
          'title': 'Тест',
          'questions': [],
        });
        final employeeId = MockEmployeeData.validEmployee['id'];

        // Act
        final result = await mockTestService.startTest('test_001', employeeId);

        // Assert
        expect(result['success'], true);
        expect(result['attemptId'], isNotNull);
      });

      test('ET-TST-004: Отправка ответов на тест', () async {
        // Arrange
        await mockTestService.addTest({
          'id': 'test_001',
          'title': 'Тест',
          'questions': [
            {'id': 'q1', 'correctIndex': 1},
            {'id': 'q2', 'correctIndex': 0},
          ],
        });
        final employeeId = MockEmployeeData.validEmployee['id'];
        final start = await mockTestService.startTest('test_001', employeeId);

        // Act
        final result = await mockTestService.submitAnswers(
          start['attemptId'],
          {'q1': 1, 'q2': 0},
        );

        // Assert
        expect(result['success'], true);
        expect(result['score'], isNotNull);
      });

      test('ET-TST-005: Подсчёт правильных ответов', () async {
        // Arrange
        await mockTestService.addTest({
          'id': 'test_001',
          'title': 'Тест',
          'questions': [
            {'id': 'q1', 'correctIndex': 1},
            {'id': 'q2', 'correctIndex': 0},
            {'id': 'q3', 'correctIndex': 2},
          ],
        });
        final employeeId = MockEmployeeData.validEmployee['id'];
        final start = await mockTestService.startTest('test_001', employeeId);

        // Act
        final result = await mockTestService.submitAnswers(
          start['attemptId'],
          {'q1': 1, 'q2': 1, 'q3': 2}, // 2 out of 3 correct
        );

        // Assert
        expect(result['correctCount'], 2);
        expect(result['totalCount'], 3);
      });

      test('ET-TST-006: Процент прохождения теста', () async {
        // Arrange
        await mockTestService.addTest({
          'id': 'test_001',
          'title': 'Тест',
          'questions': [
            {'id': 'q1', 'correctIndex': 0},
            {'id': 'q2', 'correctIndex': 0},
          ],
        });
        final employeeId = MockEmployeeData.validEmployee['id'];
        final start = await mockTestService.startTest('test_001', employeeId);

        // Act
        final result = await mockTestService.submitAnswers(
          start['attemptId'],
          {'q1': 0, 'q2': 0}, // 100% correct
        );

        // Assert
        expect(result['percentage'], 100.0);
      });

      test('ET-TST-007: Тест пройден при >= 80%', () async {
        // Arrange
        await mockTestService.addTest({
          'id': 'test_001',
          'title': 'Тест',
          'questions': List.generate(10, (i) => {'id': 'q$i', 'correctIndex': 0}),
        });
        final employeeId = MockEmployeeData.validEmployee['id'];
        final start = await mockTestService.startTest('test_001', employeeId);

        // 8 out of 10 correct = 80%
        final answers = Map.fromIterables(
          List.generate(10, (i) => 'q$i'),
          [0, 0, 0, 0, 0, 0, 0, 0, 1, 1], // 8 correct, 2 wrong
        );

        // Act
        final result = await mockTestService.submitAnswers(
          start['attemptId'],
          answers,
        );

        // Assert
        expect(result['passed'], true);
      });

      test('ET-TST-008: Тест не пройден при < 80%', () async {
        // Arrange
        await mockTestService.addTest({
          'id': 'test_001',
          'title': 'Тест',
          'questions': List.generate(10, (i) => {'id': 'q$i', 'correctIndex': 0}),
        });
        final employeeId = MockEmployeeData.validEmployee['id'];
        final start = await mockTestService.startTest('test_001', employeeId);

        // 7 out of 10 correct = 70%
        final answers = Map.fromIterables(
          List.generate(10, (i) => 'q$i'),
          [0, 0, 0, 0, 0, 0, 0, 1, 1, 1], // 7 correct, 3 wrong
        );

        // Act
        final result = await mockTestService.submitAnswers(
          start['attemptId'],
          answers,
        );

        // Assert
        expect(result['passed'], false);
      });
    });

    // ==================== АВТОБАЛЛЫ ====================

    group('Auto Points Tests', () {
      test('ET-TST-009: Автоначисление баллов за пройденный тест', () async {
        // Arrange
        await mockTestService.addTest({
          'id': 'test_001',
          'title': 'Тест',
          'points': 5,
          'questions': [{'id': 'q1', 'correctIndex': 0}],
        });
        final employeeId = MockEmployeeData.validEmployee['id'];
        final start = await mockTestService.startTest('test_001', employeeId);

        // Act
        final result = await mockTestService.submitAnswers(
          start['attemptId'],
          {'q1': 0}, // 100% correct
        );

        // Assert
        expect(result['pointsAwarded'], 5);
      });

      test('ET-TST-010: Нет баллов за непройденный тест', () async {
        // Arrange
        await mockTestService.addTest({
          'id': 'test_001',
          'title': 'Тест',
          'points': 5,
          'questions': List.generate(10, (i) => {'id': 'q$i', 'correctIndex': 0}),
        });
        final employeeId = MockEmployeeData.validEmployee['id'];
        final start = await mockTestService.startTest('test_001', employeeId);

        // 50% correct - fail
        final answers = Map.fromIterables(
          List.generate(10, (i) => 'q$i'),
          List.generate(10, (i) => i < 5 ? 0 : 1),
        );

        // Act
        final result = await mockTestService.submitAnswers(
          start['attemptId'],
          answers,
        );

        // Assert
        expect(result['pointsAwarded'], 0);
      });

      test('ET-TST-011: Баллы начисляются только за первую попытку', () async {
        // Arrange
        await mockTestService.addTest({
          'id': 'test_001',
          'title': 'Тест',
          'points': 5,
          'questions': [{'id': 'q1', 'correctIndex': 0}],
        });
        final employeeId = MockEmployeeData.validEmployee['id'];

        // First attempt - pass
        final start1 = await mockTestService.startTest('test_001', employeeId);
        await mockTestService.submitAnswers(start1['attemptId'], {'q1': 0});

        // Second attempt
        final start2 = await mockTestService.startTest('test_001', employeeId);

        // Act
        final result = await mockTestService.submitAnswers(
          start2['attemptId'],
          {'q1': 0},
        );

        // Assert
        expect(result['pointsAwarded'], 0); // No points for retry
      });

      test('ET-TST-012: Интеграция с эффективностью', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = '2024-01';

        await mockTestService.addTest({
          'id': 'test_001',
          'title': 'Тест',
          'points': 3,
          'questions': [{'id': 'q1', 'correctIndex': 0}],
        });
        final start = await mockTestService.startTest('test_001', employeeId);
        await mockTestService.submitAnswers(start['attemptId'], {'q1': 0});

        // Act
        final points = await mockTestService.getEmployeeTestPoints(
          employeeId,
          month,
        );

        // Assert
        expect(points, 3);
      });
    });

    // ==================== ИСТОРИЯ ====================

    group('History Tests', () {
      test('ET-TST-013: История попыток сотрудника', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockTestService.addTest({
          'id': 'test_001',
          'title': 'Тест',
          'questions': [{'id': 'q1', 'correctIndex': 0}],
        });
        final start = await mockTestService.startTest('test_001', employeeId);
        await mockTestService.submitAnswers(start['attemptId'], {'q1': 0});

        // Act
        final history = await mockTestService.getEmployeeHistory(employeeId);

        // Assert
        expect(history, isA<List>());
        expect(history.length, greaterThan(0));
      });

      test('ET-TST-014: Детали попытки доступны', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockTestService.addTest({
          'id': 'test_001',
          'title': 'Тест',
          'questions': [{'id': 'q1', 'correctIndex': 0}],
        });
        final start = await mockTestService.startTest('test_001', employeeId);
        await mockTestService.submitAnswers(start['attemptId'], {'q1': 0});

        // Act
        final attempt = await mockTestService.getAttempt(start['attemptId']);

        // Assert
        expect(attempt['testId'], 'test_001');
        expect(attempt['employeeId'], employeeId);
        expect(attempt['score'], isNotNull);
      });
    });
  });
}

// ==================== MOCK SERVICES ====================

class MockTrainingService {
  final List<Map<String, dynamic>> _articles = [];
  final Map<String, List<String>> _readArticles = {}; // employeeId -> articleIds

  Future<List<Map<String, dynamic>>> getArticles() async {
    return _articles;
  }

  Future<List<Map<String, dynamic>>> getArticlesByCategory(String category) async {
    return _articles.where((a) => a['category'] == category).toList();
  }

  void addArticle(Map<String, dynamic> article) {
    article['id'] ??= 'art_${DateTime.now().millisecondsSinceEpoch}';
    _articles.add(article);
  }

  Future<Map<String, dynamic>> createArticle(
    Map<String, dynamic> data, {
    required bool isAdmin,
  }) async {
    if (!isAdmin) {
      return {'success': false, 'error': 'No permission'};
    }

    addArticle(data);
    return {'success': true};
  }

  Future<Map<String, dynamic>> markAsRead(String articleId, String employeeId) async {
    _readArticles.putIfAbsent(employeeId, () => []);
    if (!_readArticles[employeeId]!.contains(articleId)) {
      _readArticles[employeeId]!.add(articleId);
    }
    return {'success': true};
  }

  Future<Map<String, dynamic>> getProgress(String employeeId) async {
    final read = _readArticles[employeeId]?.length ?? 0;
    final total = _articles.length;
    final percentage = total > 0 ? (read / total * 100) : 0.0;

    return {
      'read': read,
      'total': total,
      'percentage': percentage,
    };
  }

  void clear() {
    _articles.clear();
    _readArticles.clear();
  }
}

class MockTestService {
  final List<Map<String, dynamic>> _tests = [];
  final List<Map<String, dynamic>> _attempts = [];
  final Map<String, double> _employeePoints = {};
  final Map<String, Set<String>> _passedTests = {}; // employeeId -> testIds

  Future<List<Map<String, dynamic>>> getAvailableTests(String employeeId) async {
    return _tests;
  }

  void addTest(Map<String, dynamic> test) {
    test['points'] ??= 1;
    _tests.add(test);
  }

  Future<Map<String, dynamic>> getTest(String testId) async {
    return _tests.firstWhere(
      (t) => t['id'] == testId,
      orElse: () => {'error': 'Not found'},
    );
  }

  Future<Map<String, dynamic>> startTest(String testId, String employeeId) async {
    final attemptId = 'attempt_${DateTime.now().millisecondsSinceEpoch}';
    _attempts.add({
      'id': attemptId,
      'testId': testId,
      'employeeId': employeeId,
      'startedAt': DateTime.now().toIso8601String(),
      'status': 'in_progress',
    });

    return {
      'success': true,
      'attemptId': attemptId,
    };
  }

  Future<Map<String, dynamic>> submitAnswers(
    String attemptId,
    Map<String, int> answers,
  ) async {
    final attemptIndex = _attempts.indexWhere((a) => a['id'] == attemptId);
    if (attemptIndex < 0) {
      return {'success': false, 'error': 'Attempt not found'};
    }

    final attempt = _attempts[attemptIndex];
    final test = await getTest(attempt['testId']);
    final questions = test['questions'] as List;

    int correct = 0;
    for (final q in questions) {
      if (answers[q['id']] == q['correctIndex']) {
        correct++;
      }
    }

    final total = questions.length;
    final percentage = total > 0 ? (correct / total * 100) : 0.0;
    final passed = percentage >= 80;

    // Calculate points
    int pointsAwarded = 0;
    final employeeId = attempt['employeeId'];
    _passedTests.putIfAbsent(employeeId, () => {});

    if (passed && !_passedTests[employeeId]!.contains(attempt['testId'])) {
      pointsAwarded = test['points'] ?? 0;
      _passedTests[employeeId]!.add(attempt['testId']);

      final month = DateTime.now().toIso8601String().substring(0, 7);
      final key = '${employeeId}_$month';
      _employeePoints[key] = (_employeePoints[key] ?? 0) + pointsAwarded;
    }

    // Update attempt
    _attempts[attemptIndex]['status'] = 'completed';
    _attempts[attemptIndex]['answers'] = answers;
    _attempts[attemptIndex]['correctCount'] = correct;
    _attempts[attemptIndex]['totalCount'] = total;
    _attempts[attemptIndex]['percentage'] = percentage;
    _attempts[attemptIndex]['passed'] = passed;
    _attempts[attemptIndex]['score'] = percentage;
    _attempts[attemptIndex]['completedAt'] = DateTime.now().toIso8601String();

    return {
      'success': true,
      'correctCount': correct,
      'totalCount': total,
      'percentage': percentage,
      'passed': passed,
      'score': percentage,
      'pointsAwarded': pointsAwarded,
    };
  }

  Future<double> getEmployeeTestPoints(String employeeId, String month) async {
    final key = '${employeeId}_$month';
    return _employeePoints[key] ?? 0;
  }

  Future<List<Map<String, dynamic>>> getEmployeeHistory(String employeeId) async {
    return _attempts.where((a) => a['employeeId'] == employeeId).toList();
  }

  Future<Map<String, dynamic>> getAttempt(String attemptId) async {
    return _attempts.firstWhere(
      (a) => a['id'] == attemptId,
      orElse: () => {'error': 'Not found'},
    );
  }

  void clear() {
    _tests.clear();
    _attempts.clear();
    _employeePoints.clear();
    _passedTests.clear();
  }
}

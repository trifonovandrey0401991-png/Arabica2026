import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P2 Тесты заявок на работу для роли КЛИЕНТ
/// Покрывает: Подача заявки, статусы, уведомления
void main() {
  group('Job Application Tests (P2)', () {
    late MockJobApplicationService mockJobService;

    setUp(() async {
      mockJobService = MockJobApplicationService();
    });

    tearDown(() async {
      mockJobService.clear();
    });

    // ==================== ПОДАЧА ЗАЯВКИ ====================

    group('Application Submission Tests', () {
      test('CT-JOB-001: Подача заявки на работу', () async {
        // Arrange
        final applicationData = {
          'name': 'Иван Иванов',
          'phone': '79001234567',
          'email': 'ivan@example.com',
          'position': 'barista',
          'shopId': MockShopData.validShop['id'],
        };

        // Act
        final result = await mockJobService.submitApplication(applicationData);

        // Assert
        expect(result['success'], true);
        expect(result['application']['status'], 'pending');
      });

      test('CT-JOB-002: Обязательные поля', () async {
        // Act - missing name
        final result1 = await mockJobService.submitApplication({
          'phone': '79001234567',
          'position': 'barista',
        });

        // Act - missing phone
        final result2 = await mockJobService.submitApplication({
          'name': 'Иван',
          'position': 'barista',
        });

        // Assert
        expect(result1['success'], false);
        expect(result2['success'], false);
      });

      test('CT-JOB-003: Валидация телефона', () async {
        // Act
        final result = await mockJobService.submitApplication({
          'name': 'Иван',
          'phone': '123', // Invalid
          'position': 'barista',
        });

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('phone'));
      });

      test('CT-JOB-004: Нельзя подать повторную заявку', () async {
        // Arrange
        await mockJobService.submitApplication({
          'name': 'Иван',
          'phone': '79001234567',
          'position': 'barista',
        });

        // Act
        final result = await mockJobService.submitApplication({
          'name': 'Иван Иванов',
          'phone': '79001234567', // Same phone
          'position': 'cashier',
        });

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('exists'));
      });

      test('CT-JOB-005: Прикрепление резюме', () async {
        // Arrange
        final app = await mockJobService.submitApplication({
          'name': 'Иван',
          'phone': '79001234567',
          'position': 'barista',
        });

        // Act
        final result = await mockJobService.attachResume(
          app['application']['id'],
          'resume_pdf_base64',
        );

        // Assert
        expect(result['success'], true);
        expect(result['resumeUrl'], isNotEmpty);
      });
    });

    // ==================== ПОЗИЦИИ ====================

    group('Position Tests', () {
      test('CT-JOB-006: Список доступных позиций', () async {
        // Act
        final positions = await mockJobService.getPositions();

        // Assert
        expect(positions, isNotEmpty);
        expect(positions.any((p) => p['id'] == 'barista'), true);
        expect(positions.any((p) => p['id'] == 'cashier'), true);
      });

      test('CT-JOB-007: Выбор предпочитаемого магазина', () async {
        // Arrange
        final app = await mockJobService.submitApplication({
          'name': 'Мария',
          'phone': '79002222222',
          'position': 'barista',
          'shopId': 'shop_001',
          'preferredShops': ['shop_001', 'shop_002'],
        });

        // Assert
        expect(app['application']['preferredShops'], contains('shop_001'));
      });
    });

    // ==================== СТАТУСЫ ====================

    group('Status Tests', () {
      test('CT-JOB-008: Статус pending при подаче', () async {
        // Act
        final result = await mockJobService.submitApplication({
          'name': 'Тест',
          'phone': '79003333333',
          'position': 'barista',
        });

        // Assert
        expect(result['application']['status'], 'pending');
      });

      test('CT-JOB-009: Статус reviewing при рассмотрении', () async {
        // Arrange
        final app = await mockJobService.submitApplication({
          'name': 'Тест',
          'phone': '79004444444',
          'position': 'barista',
        });

        // Act
        final result = await mockJobService.startReview(
          app['application']['id'],
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['application']['status'], 'reviewing');
      });

      test('CT-JOB-010: Приглашение на собеседование', () async {
        // Arrange
        final app = await mockJobService.submitApplication({
          'name': 'Тест',
          'phone': '79005555555',
          'position': 'barista',
        });
        await mockJobService.startReview(
          app['application']['id'],
          MockEmployeeData.adminEmployee['id'],
        );

        // Act
        final result = await mockJobService.inviteToInterview(
          app['application']['id'],
          interviewDate: '2026-02-15',
          interviewTime: '14:00',
          location: 'Офис, ул. Примерная 1',
        );

        // Assert
        expect(result['success'], true);
        expect(result['application']['status'], 'interview_scheduled');
      });

      test('CT-JOB-011: Одобрение заявки', () async {
        // Arrange
        final app = await mockJobService.submitApplication({
          'name': 'Успешный Кандидат',
          'phone': '79006666666',
          'position': 'barista',
        });

        // Act
        final result = await mockJobService.approve(
          app['application']['id'],
          MockEmployeeData.adminEmployee['id'],
          shopId: MockShopData.validShop['id'],
          startDate: '2026-02-20',
        );

        // Assert
        expect(result['success'], true);
        expect(result['application']['status'], 'approved');
      });

      test('CT-JOB-012: Отклонение заявки', () async {
        // Arrange
        final app = await mockJobService.submitApplication({
          'name': 'Кандидат',
          'phone': '79007777777',
          'position': 'barista',
        });

        // Act
        final result = await mockJobService.reject(
          app['application']['id'],
          MockEmployeeData.adminEmployee['id'],
          reason: 'Нет опыта работы',
        );

        // Assert
        expect(result['success'], true);
        expect(result['application']['status'], 'rejected');
      });
    });

    // ==================== ПРОВЕРКА СТАТУСА ====================

    group('Status Check Tests', () {
      test('CT-JOB-013: Проверка статуса по телефону', () async {
        // Arrange
        final phone = '79008888888';
        await mockJobService.submitApplication({
          'name': 'Проверка',
          'phone': phone,
          'position': 'barista',
        });

        // Act
        final status = await mockJobService.checkStatus(phone);

        // Assert
        expect(status['found'], true);
        expect(status['status'], 'pending');
      });

      test('CT-JOB-014: Нет заявки', () async {
        // Act
        final status = await mockJobService.checkStatus('79009999999');

        // Assert
        expect(status['found'], false);
      });
    });

    // ==================== УВЕДОМЛЕНИЯ ====================

    group('Notification Tests', () {
      test('CT-JOB-015: Уведомление при подаче заявки', () async {
        // Act
        final result = await mockJobService.submitApplication({
          'name': 'Новая Заявка',
          'phone': '79001010101',
          'position': 'barista',
        });

        // Assert
        expect(result['notificationSent'], true);
      });

      test('CT-JOB-016: Уведомление о статусе кандидату', () async {
        // Arrange
        final app = await mockJobService.submitApplication({
          'name': 'Кандидат',
          'phone': '79001111111',
          'position': 'barista',
        });

        // Act
        final result = await mockJobService.approve(
          app['application']['id'],
          MockEmployeeData.adminEmployee['id'],
          shopId: MockShopData.validShop['id'],
        );

        // Assert
        expect(result['candidateNotified'], true);
      });
    });

    // ==================== АДМИН ФУНКЦИИ ====================

    group('Admin Tests', () {
      test('CT-JOB-017: Список всех заявок', () async {
        // Arrange
        for (var i = 0; i < 5; i++) {
          await mockJobService.submitApplication({
            'name': 'Кандидат $i',
            'phone': '7900121212$i',
            'position': 'barista',
          });
        }

        // Act
        final applications = await mockJobService.getAllApplications();

        // Assert
        expect(applications.length, 5);
      });

      test('CT-JOB-018: Фильтрация по статусу', () async {
        // Arrange
        final app1 = await mockJobService.submitApplication({
          'name': 'Pending',
          'phone': '79001313131',
          'position': 'barista',
        });
        final app2 = await mockJobService.submitApplication({
          'name': 'Approved',
          'phone': '79001414141',
          'position': 'barista',
        });
        await mockJobService.approve(
          app2['application']['id'],
          MockEmployeeData.adminEmployee['id'],
          shopId: MockShopData.validShop['id'],
        );

        // Act
        final pending = await mockJobService.getAllApplications(status: 'pending');
        final approved = await mockJobService.getAllApplications(status: 'approved');

        // Assert
        expect(pending.length, 1);
        expect(approved.length, 1);
      });

      test('CT-JOB-019: Комментарии к заявке', () async {
        // Arrange
        final app = await mockJobService.submitApplication({
          'name': 'Кандидат',
          'phone': '79001515151',
          'position': 'barista',
        });

        // Act
        final result = await mockJobService.addComment(
          app['application']['id'],
          MockEmployeeData.adminEmployee['id'],
          'Хороший кандидат, рекомендую',
        );

        // Assert
        expect(result['success'], true);
        expect(result['comments'].length, 1);
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockJobApplicationService {
  final List<Map<String, dynamic>> _applications = [];
  final Map<String, List<Map<String, dynamic>>> _comments = {};
  int _counter = 0;

  final List<Map<String, dynamic>> _positions = [
    {'id': 'barista', 'name': 'Бариста'},
    {'id': 'cashier', 'name': 'Кассир'},
    {'id': 'manager', 'name': 'Менеджер'},
    {'id': 'cleaner', 'name': 'Уборщик'},
  ];

  Future<Map<String, dynamic>> submitApplication(Map<String, dynamic> data) async {
    final name = data['name'] as String?;
    final phone = data['phone'] as String?;
    final position = data['position'] as String?;

    if (name == null || name.isEmpty) {
      return {'success': false, 'error': 'Name is required'};
    }

    if (phone == null || phone.length < 10) {
      return {'success': false, 'error': 'Invalid phone number'};
    }

    // Check for existing application
    if (_applications.any((a) => a['phone'] == phone && a['status'] != 'rejected')) {
      return {'success': false, 'error': 'Application already exists for this phone'};
    }

    _counter++;
    final application = {
      'id': 'app_$_counter',
      'name': name,
      'phone': phone,
      'email': data['email'],
      'position': position ?? 'barista',
      'shopId': data['shopId'],
      'preferredShops': data['preferredShops'] ?? [],
      'status': 'pending',
      'resumeUrl': null,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _applications.add(application);
    _comments['app_$_counter'] = [];

    return {
      'success': true,
      'application': application,
      'notificationSent': true,
    };
  }

  Future<Map<String, dynamic>> attachResume(String applicationId, String resumeData) async {
    final index = _applications.indexWhere((a) => a['id'] == applicationId);
    if (index < 0) {
      return {'success': false, 'error': 'Application not found'};
    }

    final resumeUrl = 'https://storage.example.com/resumes/$applicationId.pdf';
    _applications[index]['resumeUrl'] = resumeUrl;

    return {'success': true, 'resumeUrl': resumeUrl};
  }

  Future<List<Map<String, dynamic>>> getPositions() async {
    return List.from(_positions);
  }

  Future<Map<String, dynamic>> startReview(String applicationId, String adminId) async {
    final index = _applications.indexWhere((a) => a['id'] == applicationId);
    if (index < 0) {
      return {'success': false, 'error': 'Application not found'};
    }

    _applications[index]['status'] = 'reviewing';
    _applications[index]['reviewedBy'] = adminId;

    return {'success': true, 'application': _applications[index]};
  }

  Future<Map<String, dynamic>> inviteToInterview(
    String applicationId, {
    String? interviewDate,
    String? interviewTime,
    String? location,
  }) async {
    final index = _applications.indexWhere((a) => a['id'] == applicationId);
    if (index < 0) {
      return {'success': false, 'error': 'Application not found'};
    }

    _applications[index]['status'] = 'interview_scheduled';
    _applications[index]['interviewDate'] = interviewDate;
    _applications[index]['interviewTime'] = interviewTime;
    _applications[index]['interviewLocation'] = location;

    return {'success': true, 'application': _applications[index]};
  }

  Future<Map<String, dynamic>> approve(
    String applicationId,
    String adminId, {
    String? shopId,
    String? startDate,
  }) async {
    final index = _applications.indexWhere((a) => a['id'] == applicationId);
    if (index < 0) {
      return {'success': false, 'error': 'Application not found'};
    }

    _applications[index]['status'] = 'approved';
    _applications[index]['approvedBy'] = adminId;
    _applications[index]['assignedShopId'] = shopId;
    _applications[index]['startDate'] = startDate;

    return {
      'success': true,
      'application': _applications[index],
      'candidateNotified': true,
    };
  }

  Future<Map<String, dynamic>> reject(
    String applicationId,
    String adminId, {
    String? reason,
  }) async {
    final index = _applications.indexWhere((a) => a['id'] == applicationId);
    if (index < 0) {
      return {'success': false, 'error': 'Application not found'};
    }

    _applications[index]['status'] = 'rejected';
    _applications[index]['rejectedBy'] = adminId;
    _applications[index]['rejectionReason'] = reason;

    return {'success': true, 'application': _applications[index]};
  }

  Future<Map<String, dynamic>> checkStatus(String phone) async {
    final app = _applications.where((a) => a['phone'] == phone).toList();
    if (app.isEmpty) {
      return {'found': false};
    }
    return {
      'found': true,
      'status': app.last['status'],
      'application': app.last,
    };
  }

  Future<List<Map<String, dynamic>>> getAllApplications({String? status}) async {
    if (status == null) {
      return List.from(_applications);
    }
    return _applications.where((a) => a['status'] == status).toList();
  }

  Future<Map<String, dynamic>> addComment(
    String applicationId,
    String adminId,
    String text,
  ) async {
    final comments = _comments[applicationId];
    if (comments == null) {
      return {'success': false, 'error': 'Application not found'};
    }

    comments.add({
      'adminId': adminId,
      'text': text,
      'createdAt': DateTime.now().toIso8601String(),
    });

    return {'success': true, 'comments': comments};
  }

  void clear() {
    _applications.clear();
    _comments.clear();
    _counter = 0;
  }
}

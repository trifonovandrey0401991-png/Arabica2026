import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P1 Тесты задач для роли СОТРУДНИК
/// Покрывает: Разовые задачи, циклические задачи, выполнение, баллы
void main() {
  group('Tasks Tests (P1)', () {
    late MockTaskService mockTaskService;
    late MockRecurringTaskService mockRecurringService;

    setUp(() async {
      mockTaskService = MockTaskService();
      mockRecurringService = MockRecurringTaskService();
      mockRecurringService.setTaskService(mockTaskService);
    });

    tearDown(() async {
      mockTaskService.clear();
      mockRecurringService.clear();
    });

    // ==================== РАЗОВЫЕ ЗАДАЧИ ====================

    group('Single Tasks Tests', () {
      test('ET-TSK-001: Получение списка задач сотрудника', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];

        // Act
        final tasks = await mockTaskService.getEmployeeTasks(employeeId);

        // Assert
        expect(tasks, isA<List>());
      });

      test('ET-TSK-002: Создание задачи админом', () async {
        // Arrange
        final taskData = {
          'title': 'Провести инвентаризацию',
          'description': 'Пересчитать все товары',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'deadline': DateTime.now().add(Duration(days: 1)).toIso8601String(),
          'points': 5,
        };

        // Act
        final result = await mockTaskService.createTask(
          taskData,
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['success'], true);
        expect(result['task']['status'], 'pending');
      });

      test('ET-TSK-003: Задача содержит дедлайн', () async {
        // Arrange
        final deadline = DateTime.now().add(Duration(days: 2));
        final taskData = {
          'title': 'Задача с дедлайном',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'deadline': deadline.toIso8601String(),
          'points': 3,
        };

        // Act
        final result = await mockTaskService.createTask(
          taskData,
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['task']['deadline'], isNotNull);
      });

      test('ET-TSK-004: Задача содержит баллы', () async {
        // Arrange
        final points = 10;
        final taskData = {
          'title': 'Задача с баллами',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'points': points,
        };

        // Act
        final result = await mockTaskService.createTask(
          taskData,
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['task']['points'], points);
      });

      test('ET-TSK-005: Выполнение задачи сотрудником', () async {
        // Arrange
        final taskResult = await mockTaskService.createTask({
          'title': 'Тестовая задача',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'points': 5,
        }, MockEmployeeData.adminEmployee['id']);
        final taskId = taskResult['task']['id'];

        // Act
        final result = await mockTaskService.completeTask(
          taskId,
          MockEmployeeData.validEmployee['id'],
          comment: 'Выполнено!',
        );

        // Assert
        expect(result['success'], true);
        expect(result['status'], 'completed');
      });

      test('ET-TSK-006: Выполнение с фото-подтверждением', () async {
        // Arrange
        final taskResult = await mockTaskService.createTask({
          'title': 'Задача с фото',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'points': 5,
          'requirePhoto': true,
        }, MockEmployeeData.adminEmployee['id']);
        final taskId = taskResult['task']['id'];

        // Act
        final result = await mockTaskService.completeTask(
          taskId,
          MockEmployeeData.validEmployee['id'],
          photoUrl: '/path/to/photo.jpg',
        );

        // Assert
        expect(result['success'], true);
        expect(result['photoUrl'], '/path/to/photo.jpg');
      });

      test('ET-TSK-007: Невозможность выполнить чужую задачу', () async {
        // Arrange
        final taskResult = await mockTaskService.createTask({
          'title': 'Чужая задача',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'points': 5,
        }, MockEmployeeData.adminEmployee['id']);
        final taskId = taskResult['task']['id'];

        // Act
        final result = await mockTaskService.completeTask(
          taskId,
          MockEmployeeData.secondEmployee['id'], // Wrong employee
        );

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('permission'));
      });

      test('ET-TSK-008: Подтверждение выполнения админом', () async {
        // Arrange
        final taskResult = await mockTaskService.createTask({
          'title': 'Задача для подтверждения',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'points': 5,
        }, MockEmployeeData.adminEmployee['id']);
        await mockTaskService.completeTask(
          taskResult['task']['id'],
          MockEmployeeData.validEmployee['id'],
        );

        // Act
        final result = await mockTaskService.confirmTask(
          taskResult['task']['id'],
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['success'], true);
        expect(result['status'], 'confirmed');
      });

      test('ET-TSK-009: Начисление баллов после подтверждения', () async {
        // Arrange
        final points = 7;
        final taskResult = await mockTaskService.createTask({
          'title': 'Задача с баллами',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'points': points,
        }, MockEmployeeData.adminEmployee['id']);
        await mockTaskService.completeTask(
          taskResult['task']['id'],
          MockEmployeeData.validEmployee['id'],
        );

        // Act
        final result = await mockTaskService.confirmTask(
          taskResult['task']['id'],
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['pointsAwarded'], points);
      });

      test('ET-TSK-010: Отклонение задачи с причиной', () async {
        // Arrange
        final taskResult = await mockTaskService.createTask({
          'title': 'Задача для отклонения',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'points': 5,
        }, MockEmployeeData.adminEmployee['id']);
        await mockTaskService.completeTask(
          taskResult['task']['id'],
          MockEmployeeData.validEmployee['id'],
        );

        // Act
        final result = await mockTaskService.rejectTask(
          taskResult['task']['id'],
          MockEmployeeData.adminEmployee['id'],
          reason: 'Не соответствует требованиям',
        );

        // Assert
        expect(result['success'], true);
        expect(result['status'], 'rejected');
        expect(result['reason'], 'Не соответствует требованиям');
      });

      test('ET-TSK-011: Просроченная задача', () async {
        // Arrange
        final pastDeadline = DateTime.now().subtract(Duration(days: 1));
        final taskResult = await mockTaskService.createTask({
          'title': 'Просроченная задача',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'deadline': pastDeadline.toIso8601String(),
          'points': 5,
        }, MockEmployeeData.adminEmployee['id']);

        // Act
        final isOverdue = mockTaskService.isTaskOverdue(taskResult['task']);

        // Assert
        expect(isOverdue, true);
      });

      test('ET-TSK-012: Фильтрация задач по статусу', () async {
        // Arrange
        await mockTaskService.createTask({
          'title': 'Pending задача',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'points': 5,
        }, MockEmployeeData.adminEmployee['id']);

        // Act
        final pendingTasks = await mockTaskService.getEmployeeTasks(
          MockEmployeeData.validEmployee['id'],
          status: 'pending',
        );

        // Assert
        for (final task in pendingTasks) {
          expect(task['status'], 'pending');
        }
      });
    });

    // ==================== ЦИКЛИЧЕСКИЕ ЗАДАЧИ ====================

    group('Recurring Tasks Tests', () {
      test('ET-TSK-013: Создание циклической задачи', () async {
        // Arrange
        final taskData = {
          'title': 'Ежедневная уборка',
          'description': 'Убрать помещение',
          'frequency': 'daily',
          'time': '09:00',
          'assignees': [MockEmployeeData.validEmployee['id']],
          'points': 2,
        };

        // Act
        final result = await mockRecurringService.createRecurringTask(
          taskData,
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['success'], true);
        expect(result['task']['frequency'], 'daily');
      });

      test('ET-TSK-014: Частота "daily" (ежедневно)', () async {
        // Arrange
        final taskData = {
          'title': 'Daily задача',
          'frequency': 'daily',
          'time': '10:00',
          'assignees': [MockEmployeeData.validEmployee['id']],
          'points': 1,
        };

        // Act
        final result = await mockRecurringService.createRecurringTask(
          taskData,
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['task']['frequency'], 'daily');
      });

      test('ET-TSK-015: Частота "weekly" (еженедельно)', () async {
        // Arrange
        final taskData = {
          'title': 'Weekly задача',
          'frequency': 'weekly',
          'dayOfWeek': 1, // Monday
          'time': '14:00',
          'assignees': [MockEmployeeData.validEmployee['id']],
          'points': 3,
        };

        // Act
        final result = await mockRecurringService.createRecurringTask(
          taskData,
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['task']['frequency'], 'weekly');
        expect(result['task']['dayOfWeek'], 1);
      });

      test('ET-TSK-016: Частота "monthly" (ежемесячно)', () async {
        // Arrange
        final taskData = {
          'title': 'Monthly задача',
          'frequency': 'monthly',
          'dayOfMonth': 15,
          'time': '12:00',
          'assignees': [MockEmployeeData.validEmployee['id']],
          'points': 5,
        };

        // Act
        final result = await mockRecurringService.createRecurringTask(
          taskData,
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['task']['frequency'], 'monthly');
        expect(result['task']['dayOfMonth'], 15);
      });

      test('ET-TSK-017: Автогенерация экземпляров задач', () async {
        // Arrange
        await mockRecurringService.createRecurringTask({
          'title': 'Auto-generated task',
          'frequency': 'daily',
          'time': '09:00',
          'assignees': [MockEmployeeData.validEmployee['id']],
          'points': 1,
        }, MockEmployeeData.adminEmployee['id']);

        // Act
        await mockRecurringService.generateDailyInstances();
        final tasks = await mockTaskService.getEmployeeTasks(
          MockEmployeeData.validEmployee['id'],
        );

        // Assert
        expect(tasks.any((t) => t['title'] == 'Auto-generated task'), true);
      });

      test('ET-TSK-018: Назначение на нескольких сотрудников', () async {
        // Arrange
        final assignees = [
          MockEmployeeData.validEmployee['id'],
          MockEmployeeData.secondEmployee['id'],
        ];

        // Act
        final result = await mockRecurringService.createRecurringTask({
          'title': 'Групповая задача',
          'frequency': 'daily',
          'time': '10:00',
          'assignees': assignees,
          'points': 2,
        }, MockEmployeeData.adminEmployee['id']);

        // Assert
        expect(result['task']['assignees'].length, 2);
      });

      test('ET-TSK-019: Редактирование циклической задачи', () async {
        // Arrange
        final createResult = await mockRecurringService.createRecurringTask({
          'title': 'Старое название',
          'frequency': 'daily',
          'time': '09:00',
          'assignees': [MockEmployeeData.validEmployee['id']],
          'points': 1,
        }, MockEmployeeData.adminEmployee['id']);
        final taskId = createResult['task']['id'];

        // Act
        final result = await mockRecurringService.updateRecurringTask(
          taskId,
          {'title': 'Новое название'},
        );

        // Assert
        expect(result['success'], true);
        expect(result['task']['title'], 'Новое название');
      });

      test('ET-TSK-020: Удаление циклической задачи', () async {
        // Arrange
        final createResult = await mockRecurringService.createRecurringTask({
          'title': 'Задача для удаления',
          'frequency': 'daily',
          'time': '09:00',
          'assignees': [MockEmployeeData.validEmployee['id']],
          'points': 1,
        }, MockEmployeeData.adminEmployee['id']);
        final taskId = createResult['task']['id'];

        // Act
        final result = await mockRecurringService.deleteRecurringTask(taskId);

        // Assert
        expect(result['success'], true);
      });

      test('ET-TSK-021: Приостановка циклической задачи', () async {
        // Arrange
        final createResult = await mockRecurringService.createRecurringTask({
          'title': 'Задача для паузы',
          'frequency': 'daily',
          'time': '09:00',
          'assignees': [MockEmployeeData.validEmployee['id']],
          'points': 1,
        }, MockEmployeeData.adminEmployee['id']);
        final taskId = createResult['task']['id'];

        // Act
        final result = await mockRecurringService.pauseRecurringTask(taskId);

        // Assert
        expect(result['success'], true);
        expect(result['status'], 'paused');
      });

      test('ET-TSK-022: Возобновление приостановленной задачи', () async {
        // Arrange
        final createResult = await mockRecurringService.createRecurringTask({
          'title': 'Задача',
          'frequency': 'daily',
          'time': '09:00',
          'assignees': [MockEmployeeData.validEmployee['id']],
          'points': 1,
        }, MockEmployeeData.adminEmployee['id']);
        await mockRecurringService.pauseRecurringTask(createResult['task']['id']);

        // Act
        final result = await mockRecurringService.resumeRecurringTask(
          createResult['task']['id'],
        );

        // Assert
        expect(result['success'], true);
        expect(result['status'], 'active');
      });
    });

    // ==================== УВЕДОМЛЕНИЯ ====================

    group('Task Notifications Tests', () {
      test('ET-TSK-023: Push при назначении новой задачи', () async {
        // Act
        final result = await mockTaskService.createTask({
          'title': 'Новая задача',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'points': 5,
        }, MockEmployeeData.adminEmployee['id']);

        // Assert
        expect(result['notificationSent'], true);
      });

      test('ET-TSK-024: Push при приближении дедлайна', () async {
        // Arrange
        final soonDeadline = DateTime.now().add(Duration(hours: 2));
        await mockTaskService.createTask({
          'title': 'Срочная задача',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'deadline': soonDeadline.toIso8601String(),
          'points': 5,
        }, MockEmployeeData.adminEmployee['id']);

        // Act
        final reminders = await mockTaskService.checkDeadlineReminders();

        // Assert
        expect(reminders.length, greaterThan(0));
      });

      test('ET-TSK-025: Push при подтверждении/отклонении', () async {
        // Arrange
        final taskResult = await mockTaskService.createTask({
          'title': 'Задача',
          'assigneeId': MockEmployeeData.validEmployee['id'],
          'points': 5,
        }, MockEmployeeData.adminEmployee['id']);
        await mockTaskService.completeTask(
          taskResult['task']['id'],
          MockEmployeeData.validEmployee['id'],
        );

        // Act
        final result = await mockTaskService.confirmTask(
          taskResult['task']['id'],
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['notificationSent'], true);
      });
    });

    // ==================== СТАТИСТИКА ====================

    group('Task Statistics Tests', () {
      test('ET-TSK-026: Подсчёт выполненных задач', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = '2024-01';

        // Act
        final stats = await mockTaskService.getTaskStats(employeeId, month);

        // Assert
        expect(stats['completed'], isA<int>());
      });

      test('ET-TSK-027: Подсчёт баллов за задачи', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = '2024-01';

        // Act
        final stats = await mockTaskService.getTaskStats(employeeId, month);

        // Assert
        expect(stats['totalPoints'], isA<num>());
      });

      test('ET-TSK-028: Интеграция с эффективностью', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = DateTime.now().toIso8601String().substring(0, 7);

        // Выполнить и подтвердить задачу
        final taskResult = await mockTaskService.createTask({
          'title': 'Задача',
          'assigneeId': employeeId,
          'points': 5,
        }, MockEmployeeData.adminEmployee['id']);
        await mockTaskService.completeTask(taskResult['task']['id'], employeeId);
        await mockTaskService.confirmTask(
          taskResult['task']['id'],
          MockEmployeeData.adminEmployee['id'],
        );

        // Act
        final efficiencyPoints = await mockTaskService.getEfficiencyPoints(
          employeeId,
          month,
        );

        // Assert
        expect(efficiencyPoints, greaterThan(0));
      });
    });
  });
}

// ==================== MOCK SERVICES ====================

class MockTaskService {
  final List<Map<String, dynamic>> _tasks = [];
  final List<Map<String, dynamic>> _efficiencyPoints = [];

  Future<List<Map<String, dynamic>>> getEmployeeTasks(
    String employeeId, {
    String? status,
  }) async {
    var filtered = _tasks.where((t) => t['assigneeId'] == employeeId);
    if (status != null) {
      filtered = filtered.where((t) => t['status'] == status);
    }
    return filtered.toList();
  }

  Future<Map<String, dynamic>> createTask(
    Map<String, dynamic> taskData,
    String creatorId,
  ) async {
    final task = {
      'id': 'task_${DateTime.now().millisecondsSinceEpoch}',
      'title': taskData['title'],
      'description': taskData['description'],
      'assigneeId': taskData['assigneeId'],
      'deadline': taskData['deadline'],
      'points': taskData['points'] ?? 1,
      'requirePhoto': taskData['requirePhoto'] ?? false,
      'status': 'pending',
      'creatorId': creatorId,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _tasks.add(task);

    return {
      'success': true,
      'task': task,
      'notificationSent': true,
    };
  }

  Future<Map<String, dynamic>> completeTask(
    String taskId,
    String employeeId, {
    String? comment,
    String? photoUrl,
  }) async {
    final index = _tasks.indexWhere((t) => t['id'] == taskId);
    if (index < 0) {
      return {'success': false, 'error': 'Task not found'};
    }

    if (_tasks[index]['assigneeId'] != employeeId) {
      return {'success': false, 'error': 'No permission'};
    }

    _tasks[index]['status'] = 'completed';
    _tasks[index]['completedAt'] = DateTime.now().toIso8601String();
    _tasks[index]['comment'] = comment;
    _tasks[index]['photoUrl'] = photoUrl;

    return {
      'success': true,
      'status': 'completed',
      'photoUrl': photoUrl,
    };
  }

  Future<Map<String, dynamic>> confirmTask(String taskId, String adminId) async {
    final index = _tasks.indexWhere((t) => t['id'] == taskId);
    if (index < 0) {
      return {'success': false, 'error': 'Task not found'};
    }

    final points = _tasks[index]['points'] ?? 0;
    _tasks[index]['status'] = 'confirmed';
    _tasks[index]['confirmedBy'] = adminId;
    _tasks[index]['confirmedAt'] = DateTime.now().toIso8601String();

    // Record efficiency points
    _efficiencyPoints.add({
      'employeeId': _tasks[index]['assigneeId'],
      'category': 'tasks',
      'points': points,
      'month': DateTime.now().toIso8601String().substring(0, 7),
    });

    return {
      'success': true,
      'status': 'confirmed',
      'pointsAwarded': points,
      'notificationSent': true,
    };
  }

  Future<Map<String, dynamic>> rejectTask(
    String taskId,
    String adminId, {
    required String reason,
  }) async {
    final index = _tasks.indexWhere((t) => t['id'] == taskId);
    if (index < 0) {
      return {'success': false, 'error': 'Task not found'};
    }

    _tasks[index]['status'] = 'rejected';
    _tasks[index]['rejectedBy'] = adminId;
    _tasks[index]['rejectedAt'] = DateTime.now().toIso8601String();
    _tasks[index]['reason'] = reason;

    return {
      'success': true,
      'status': 'rejected',
      'reason': reason,
    };
  }

  bool isTaskOverdue(Map<String, dynamic> task) {
    if (task['deadline'] == null) return false;
    final deadline = DateTime.parse(task['deadline']);
    return DateTime.now().isAfter(deadline);
  }

  Future<List<Map<String, dynamic>>> checkDeadlineReminders() async {
    final now = DateTime.now();
    final reminders = <Map<String, dynamic>>[];

    for (final task in _tasks) {
      if (task['deadline'] != null && task['status'] == 'pending') {
        final deadline = DateTime.parse(task['deadline']);
        final hoursLeft = deadline.difference(now).inHours;
        if (hoursLeft > 0 && hoursLeft <= 4) {
          reminders.add({
            'taskId': task['id'],
            'assigneeId': task['assigneeId'],
            'hoursLeft': hoursLeft,
          });
        }
      }
    }

    return reminders;
  }

  Future<Map<String, dynamic>> getTaskStats(String employeeId, String month) async {
    final monthTasks = _tasks.where((t) {
      return t['assigneeId'] == employeeId &&
          t['createdAt']?.startsWith(month) == true;
    }).toList();

    final completed = monthTasks.where((t) => t['status'] == 'confirmed').length;
    final totalPoints = monthTasks
        .where((t) => t['status'] == 'confirmed')
        .fold<int>(0, (sum, t) => sum + (t['points'] as int? ?? 0));

    return {
      'completed': completed,
      'totalPoints': totalPoints,
      'pending': monthTasks.where((t) => t['status'] == 'pending').length,
    };
  }

  Future<double> getEfficiencyPoints(String employeeId, String month) async {
    return _efficiencyPoints
        .where((p) => p['employeeId'] == employeeId && p['month'] == month)
        .fold<double>(0.0, (sum, p) => sum + (p['points'] as num).toDouble());
  }

  void addTask(Map<String, dynamic> task) {
    _tasks.add(task);
  }

  void clear() {
    _tasks.clear();
    _efficiencyPoints.clear();
  }
}

class MockRecurringTaskService {
  final List<Map<String, dynamic>> _recurringTasks = [];
  MockTaskService? _taskService;

  void setTaskService(MockTaskService service) {
    _taskService = service;
  }

  Future<Map<String, dynamic>> createRecurringTask(
    Map<String, dynamic> taskData,
    String creatorId,
  ) async {
    final task = {
      'id': 'recurring_${DateTime.now().millisecondsSinceEpoch}',
      'title': taskData['title'],
      'description': taskData['description'],
      'frequency': taskData['frequency'],
      'time': taskData['time'],
      'dayOfWeek': taskData['dayOfWeek'],
      'dayOfMonth': taskData['dayOfMonth'],
      'assignees': taskData['assignees'],
      'points': taskData['points'] ?? 1,
      'status': 'active',
      'creatorId': creatorId,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _recurringTasks.add(task);

    return {
      'success': true,
      'task': task,
    };
  }

  Future<Map<String, dynamic>> updateRecurringTask(
    String taskId,
    Map<String, dynamic> updates,
  ) async {
    final index = _recurringTasks.indexWhere((t) => t['id'] == taskId);
    if (index < 0) {
      return {'success': false, 'error': 'Task not found'};
    }

    updates.forEach((key, value) {
      _recurringTasks[index][key] = value;
    });

    return {
      'success': true,
      'task': _recurringTasks[index],
    };
  }

  Future<Map<String, dynamic>> deleteRecurringTask(String taskId) async {
    _recurringTasks.removeWhere((t) => t['id'] == taskId);
    return {'success': true};
  }

  Future<Map<String, dynamic>> pauseRecurringTask(String taskId) async {
    final index = _recurringTasks.indexWhere((t) => t['id'] == taskId);
    if (index >= 0) {
      _recurringTasks[index]['status'] = 'paused';
      return {'success': true, 'status': 'paused'};
    }
    return {'success': false, 'error': 'Task not found'};
  }

  Future<Map<String, dynamic>> resumeRecurringTask(String taskId) async {
    final index = _recurringTasks.indexWhere((t) => t['id'] == taskId);
    if (index >= 0) {
      _recurringTasks[index]['status'] = 'active';
      return {'success': true, 'status': 'active'};
    }
    return {'success': false, 'error': 'Task not found'};
  }

  Future<void> generateDailyInstances() async {
    final now = DateTime.now();

    for (final recurring in _recurringTasks) {
      if (recurring['status'] != 'active') continue;
      if (recurring['frequency'] != 'daily') continue;

      for (final assigneeId in recurring['assignees']) {
        _taskService?.addTask({
          'id': 'inst_${DateTime.now().millisecondsSinceEpoch}_$assigneeId',
          'title': recurring['title'],
          'description': recurring['description'],
          'assigneeId': assigneeId,
          'points': recurring['points'],
          'status': 'pending',
          'recurringTaskId': recurring['id'],
          'createdAt': now.toIso8601String(),
        });
      }
    }
  }

  void clear() {
    _recurringTasks.clear();
  }
}

// ==================== MOCK DATA ====================

class MockEmployeeData {
  static const Map<String, dynamic> validEmployee = {
    'id': 'emp_001',
    'name': 'Тестовый Сотрудник',
    'phone': '79001234567',
    'isAdmin': false,
  };

  static const Map<String, dynamic> secondEmployee = {
    'id': 'emp_002',
    'name': 'Второй Сотрудник',
    'phone': '79002222222',
    'isAdmin': false,
  };

  static const Map<String, dynamic> adminEmployee = {
    'id': 'admin_001',
    'name': 'Администратор',
    'phone': '79009999999',
    'isAdmin': true,
  };
}

import '../models/task_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

/// Сервис для работы с разовыми задачами.
///
/// Задачи - это поручения от админа сотрудникам с дедлайном.
/// Сотрудник может ответить текстом или фото в зависимости от типа задачи.
///
/// Основные операции:
/// - [createTask] - создание задачи (админ)
/// - [getTasks] - список всех задач
/// - [getMyAssignments] - задачи конкретного сотрудника
/// - [respondToTask] - ответ на задачу
/// - [reviewTask] - проверка ответа (админ)
///
/// Связанные сервисы:
/// - [RecurringTaskService] - для периодических задач
class TaskService {
  static const String _tasksEndpoint = ApiConstants.tasksEndpoint;
  static const String _assignmentsEndpoint = ApiConstants.taskAssignmentsEndpoint;

  /// Создать задачу (админ)
  static Future<Task?> createTask({
    required String title,
    required String description,
    required TaskResponseType responseType,
    required DateTime deadline,
    required List<TaskRecipient> recipients,
    required String createdBy,
    List<String>? attachments,
  }) async {
    try {
      Logger.debug('Creating task: $title');

      return await BaseHttpService.post<Task>(
        endpoint: _tasksEndpoint,
        body: {
          'title': title,
          'description': description,
          'responseType': responseType.code,
          'deadline': deadline.toIso8601String(),
          'recipients': recipients.map((r) => r.toJson()).toList(),
          'createdBy': createdBy,
          'attachments': attachments ?? [],
        },
        fromJson: (json) => Task.fromJson(json),
        itemKey: 'task',
      );
    } catch (e) {
      Logger.error('Error creating task', e);
      return null;
    }
  }

  /// Получить все задачи (для отчета админа)
  static Future<List<Task>> getTasks({String? month}) async {
    try {
      Logger.debug('Loading tasks...');

      final queryParams = <String, String>{};
      if (month != null) queryParams['month'] = month;

      return await BaseHttpService.getList<Task>(
        endpoint: _tasksEndpoint,
        fromJson: (json) => Task.fromJson(json),
        listKey: 'tasks',
        queryParams: queryParams.isNotEmpty ? queryParams : null,
      );
    } catch (e) {
      Logger.error('Error loading tasks', e);
      return [];
    }
  }

  /// Получить задачу по ID с назначениями
  static Future<Map<String, dynamic>?> getTaskWithAssignments(String taskId) async {
    try {
      Logger.debug('Loading task: $taskId');

      final result = await BaseHttpService.getRaw(
        endpoint: '$_tasksEndpoint/$taskId',
      );

      if (result != null) {
        return {
          'task': Task.fromJson(result['task']),
          'assignments': (result['assignments'] as List<dynamic>)
              .map((json) => TaskAssignment.fromJson(json as Map<String, dynamic>))
              .toList(),
        };
      }

      return null;
    } catch (e) {
      Logger.error('Error loading task', e);
      return null;
    }
  }

  /// Получить назначения задач для работника
  static Future<List<TaskAssignment>> getMyAssignments(String assigneeId, {String? status}) async {
    try {
      Logger.debug('Loading assignments for: $assigneeId');

      final queryParams = <String, String>{
        'assigneeId': assigneeId,
      };
      if (status != null) queryParams['status'] = status;

      return await BaseHttpService.getList<TaskAssignment>(
        endpoint: _assignmentsEndpoint,
        fromJson: (json) => TaskAssignment.fromJson(json),
        listKey: 'assignments',
        queryParams: queryParams,
      );
    } catch (e) {
      Logger.error('Error loading assignments', e);
      return [];
    }
  }

  /// Получить все назначения (для отчета админа)
  static Future<List<TaskAssignment>> getAllAssignments({String? status, String? month}) async {
    try {
      Logger.debug('Loading all assignments...');

      final queryParams = <String, String>{};
      if (status != null) queryParams['status'] = status;
      if (month != null) queryParams['month'] = month;

      return await BaseHttpService.getList<TaskAssignment>(
        endpoint: _assignmentsEndpoint,
        fromJson: (json) => TaskAssignment.fromJson(json),
        listKey: 'assignments',
        queryParams: queryParams.isNotEmpty ? queryParams : null,
      );
    } catch (e) {
      Logger.error('Error loading assignments', e);
      return [];
    }
  }

  /// Ответить на задачу (работник)
  static Future<TaskAssignment?> respondToTask({
    required String assignmentId,
    String? responseText,
    List<String>? responsePhotos,
  }) async {
    try {
      Logger.debug('Responding to task: $assignmentId');

      return await BaseHttpService.post<TaskAssignment>(
        endpoint: '$_assignmentsEndpoint/$assignmentId/respond',
        body: {
          'responseText': responseText,
          'responsePhotos': responsePhotos ?? [],
        },
        fromJson: (json) => TaskAssignment.fromJson(json),
        itemKey: 'assignment',
      );
    } catch (e) {
      Logger.error('Error responding to task', e);
      return null;
    }
  }

  /// Отклонить задачу (работник)
  static Future<TaskAssignment?> declineTask({
    required String assignmentId,
    String? reason,
  }) async {
    try {
      Logger.debug('Declining task: $assignmentId');

      return await BaseHttpService.post<TaskAssignment>(
        endpoint: '$_assignmentsEndpoint/$assignmentId/decline',
        body: {
          'reason': reason,
        },
        fromJson: (json) => TaskAssignment.fromJson(json),
        itemKey: 'assignment',
      );
    } catch (e) {
      Logger.error('Error declining task', e);
      return null;
    }
  }

  /// Проверить задачу (админ)
  static Future<TaskAssignment?> reviewTask({
    required String assignmentId,
    required bool approved,
    required String reviewedBy,
    String? reviewComment,
  }) async {
    try {
      Logger.debug('Reviewing task: $assignmentId, approved: $approved');

      return await BaseHttpService.post<TaskAssignment>(
        endpoint: '$_assignmentsEndpoint/$assignmentId/review',
        body: {
          'approved': approved,
          'reviewedBy': reviewedBy,
          'reviewComment': reviewComment,
        },
        fromJson: (json) => TaskAssignment.fromJson(json),
        itemKey: 'assignment',
      );
    } catch (e) {
      Logger.error('Error reviewing task', e);
      return null;
    }
  }

  /// Получить статистику по задачам
  static Future<Map<String, int>> getTaskStats({String? month}) async {
    try {
      Logger.debug('Loading task stats...');

      final queryParams = <String, String>{};
      if (month != null) queryParams['month'] = month;

      final result = await BaseHttpService.getRaw(
        endpoint: '$_assignmentsEndpoint/stats',
        queryParams: queryParams.isNotEmpty ? queryParams : null,
      );

      if (result != null && result['stats'] != null) {
        final stats = result['stats'] as Map<String, dynamic>;
        return {
          'total': stats['total'] ?? 0,
          'pending': stats['pending'] ?? 0,
          'submitted': stats['submitted'] ?? 0,
          'approved': stats['approved'] ?? 0,
          'rejected': stats['rejected'] ?? 0,
          'expired': stats['expired'] ?? 0,
          'declined': stats['declined'] ?? 0,
        };
      }

      return {};
    } catch (e) {
      Logger.error('Error loading task stats', e);
      return {};
    }
  }
}

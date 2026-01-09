import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/task_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

/// Сервис для работы с задачами
class TaskService {
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

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/tasks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'description': description,
          'responseType': responseType.code,
          'deadline': deadline.toIso8601String(),
          'recipients': recipients.map((r) => r.toJson()).toList(),
          'createdBy': createdBy,
          'attachments': attachments ?? [],
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['task'] != null) {
          Logger.debug('Task created: ${result['task']['id']}');
          return Task.fromJson(result['task']);
        }
      }

      Logger.error('Failed to create task: ${response.statusCode}');
      return null;
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

      final uri = Uri.parse('${ApiConstants.serverUrl}/api/tasks')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final tasks = (result['tasks'] as List<dynamic>)
              .map((json) => Task.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('Loaded ${tasks.length} tasks');
          return tasks;
        }
      }

      Logger.error('Failed to load tasks: ${response.statusCode}');
      return [];
    } catch (e) {
      Logger.error('Error loading tasks', e);
      return [];
    }
  }

  /// Получить задачу по ID с назначениями
  static Future<Map<String, dynamic>?> getTaskWithAssignments(String taskId) async {
    try {
      Logger.debug('Loading task: $taskId');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/tasks/$taskId'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return {
            'task': Task.fromJson(result['task']),
            'assignments': (result['assignments'] as List<dynamic>)
                .map((json) => TaskAssignment.fromJson(json as Map<String, dynamic>))
                .toList(),
          };
        }
      }

      Logger.error('Failed to load task: ${response.statusCode}');
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

      final uri = Uri.parse('${ApiConstants.serverUrl}/api/task-assignments')
          .replace(queryParameters: queryParams);

      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final assignments = (result['assignments'] as List<dynamic>)
              .map((json) => TaskAssignment.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('Loaded ${assignments.length} assignments');
          return assignments;
        }
      }

      Logger.error('Failed to load assignments: ${response.statusCode}');
      return [];
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

      final uri = Uri.parse('${ApiConstants.serverUrl}/api/task-assignments')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final assignments = (result['assignments'] as List<dynamic>)
              .map((json) => TaskAssignment.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('Loaded ${assignments.length} assignments');
          return assignments;
        }
      }

      Logger.error('Failed to load assignments: ${response.statusCode}');
      return [];
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

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/task-assignments/$assignmentId/respond'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'responseText': responseText,
          'responsePhotos': responsePhotos ?? [],
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['assignment'] != null) {
          Logger.debug('Task response submitted');
          return TaskAssignment.fromJson(result['assignment']);
        }
      }

      Logger.error('Failed to respond to task: ${response.statusCode} - ${response.body}');
      return null;
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

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/task-assignments/$assignmentId/decline'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'reason': reason,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['assignment'] != null) {
          Logger.debug('Task declined');
          return TaskAssignment.fromJson(result['assignment']);
        }
      }

      Logger.error('Failed to decline task: ${response.statusCode}');
      return null;
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

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/task-assignments/$assignmentId/review'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'approved': approved,
          'reviewedBy': reviewedBy,
          'reviewComment': reviewComment,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['assignment'] != null) {
          Logger.debug('Task reviewed');
          return TaskAssignment.fromJson(result['assignment']);
        }
      }

      Logger.error('Failed to review task: ${response.statusCode}');
      return null;
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

      final uri = Uri.parse('${ApiConstants.serverUrl}/api/task-assignments/stats')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['stats'] != null) {
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
      }

      return {};
    } catch (e) {
      Logger.error('Error loading task stats', e);
      return {};
    }
  }
}

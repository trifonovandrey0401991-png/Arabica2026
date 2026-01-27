import '../models/task_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/cache_manager.dart';

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

  // === Константы кэширования ===
  static const String _cacheKeyPrefix = 'tasks';
  static const Duration _shortCacheDuration = Duration(minutes: 2);  // Текущий месяц
  static const Duration _longCacheDuration = Duration(minutes: 15);  // Старые месяцы

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
      // Форматируем deadline как ISO строку без timezone
      final deadlineStr = '${deadline.year.toString().padLeft(4, '0')}-'
          '${deadline.month.toString().padLeft(2, '0')}-'
          '${deadline.day.toString().padLeft(2, '0')}T'
          '${deadline.hour.toString().padLeft(2, '0')}:'
          '${deadline.minute.toString().padLeft(2, '0')}:00';

      Logger.debug('Creating task: $title, deadline: $deadlineStr');

      return await BaseHttpService.post<Task>(
        endpoint: _tasksEndpoint,
        body: {
          'title': title,
          'description': description,
          'responseType': responseType.code,
          'deadline': deadlineStr,
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

  /// Получить количество непросмотренных просроченных задач (для админа)
  static Future<int> getUnviewedExpiredCount() async {
    try {
      Logger.debug('Loading unviewed expired count...');

      final result = await BaseHttpService.getRaw(
        endpoint: '$_assignmentsEndpoint/unviewed-expired-count',
      );

      if (result != null && result['count'] != null) {
        return result['count'] as int;
      }

      return 0;
    } catch (e) {
      Logger.error('Error loading unviewed expired count', e);
      return 0;
    }
  }

  /// Отметить все просроченные задачи как просмотренные
  static Future<bool> markExpiredAsViewed() async {
    try {
      Logger.debug('Marking expired tasks as viewed...');

      final result = await BaseHttpService.postRaw(
        endpoint: '$_assignmentsEndpoint/mark-expired-viewed',
        body: {},
      );

      return result != null && result['success'] == true;
    } catch (e) {
      Logger.error('Error marking expired tasks as viewed', e);
      return false;
    }
  }

  // === МЕТОДЫ С КЭШИРОВАНИЕМ ===

  /// Получить TTL кэша в зависимости от месяца
  static Duration _getCacheDuration(int year, int month) {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final requestedMonth = DateTime(year, month);

    // Текущий месяц - короткий TTL
    if (requestedMonth.year == currentMonth.year &&
        requestedMonth.month == currentMonth.month) {
      return _shortCacheDuration;
    }
    // Старые месяцы - длинный TTL
    return _longCacheDuration;
  }

  /// Создать ключ кэша для назначений сотрудника
  static String _createMyAssignmentsCacheKey(String assigneeId, int year, int month) {
    return '${_cacheKeyPrefix}_my_${assigneeId}_${year}_${month.toString().padLeft(2, '0')}';
  }

  /// Создать ключ кэша для всех назначений
  static String _createAllAssignmentsCacheKey(int year, int month) {
    return '${_cacheKeyPrefix}_all_${year}_${month.toString().padLeft(2, '0')}';
  }

  /// Получить назначения задач для работника за месяц (С КЭШИРОВАНИЕМ)
  static Future<List<TaskAssignment>> getMyAssignmentsCached({
    required String assigneeId,
    required int year,
    required int month,
    bool forceRefresh = false,
  }) async {
    final cacheKey = _createMyAssignmentsCacheKey(assigneeId, year, month);
    final monthStr = '$year-${month.toString().padLeft(2, '0')}';

    if (forceRefresh) {
      CacheManager.remove(cacheKey);
    }

    return await CacheManager.getOrFetch<List<TaskAssignment>>(
      cacheKey,
      () async {
        Logger.debug('📥 Загрузка задач для $assigneeId за $monthStr с сервера...');

        final queryParams = <String, String>{
          'assigneeId': assigneeId,
          'month': monthStr,
        };

        return await BaseHttpService.getList<TaskAssignment>(
          endpoint: _assignmentsEndpoint,
          fromJson: (json) => TaskAssignment.fromJson(json),
          listKey: 'assignments',
          queryParams: queryParams,
        );
      },
      duration: _getCacheDuration(year, month),
    );
  }

  /// Получить все назначения за месяц (С КЭШИРОВАНИЕМ)
  static Future<List<TaskAssignment>> getAllAssignmentsCached({
    required int year,
    required int month,
    bool forceRefresh = false,
  }) async {
    final cacheKey = _createAllAssignmentsCacheKey(year, month);
    final monthStr = '$year-${month.toString().padLeft(2, '0')}';

    if (forceRefresh) {
      CacheManager.remove(cacheKey);
    }

    return await CacheManager.getOrFetch<List<TaskAssignment>>(
      cacheKey,
      () async {
        Logger.debug('📥 Загрузка всех задач за $monthStr с сервера...');

        return await BaseHttpService.getList<TaskAssignment>(
          endpoint: _assignmentsEndpoint,
          fromJson: (json) => TaskAssignment.fromJson(json),
          listKey: 'assignments',
          queryParams: {'month': monthStr},
        );
      },
      duration: _getCacheDuration(year, month),
    );
  }

  /// Очистить весь кэш задач
  static void clearCache() {
    CacheManager.clearByPattern(_cacheKeyPrefix);
    Logger.debug('🗑️ Кэш задач очищен');
  }

  /// Очистить кэш для конкретного месяца
  static void clearCacheForMonth(int year, int month) {
    final pattern = '${_cacheKeyPrefix}_${year}_${month.toString().padLeft(2, '0')}';
    CacheManager.clearByPattern(pattern);
    Logger.debug('🗑️ Кэш задач очищен для $year-$month');
  }

  /// Очистить кэш для конкретного сотрудника
  static void clearCacheForAssignee(String assigneeId) {
    final pattern = '${_cacheKeyPrefix}_my_$assigneeId';
    CacheManager.clearByPattern(pattern);
    Logger.debug('🗑️ Кэш задач очищен для сотрудника $assigneeId');
  }
}

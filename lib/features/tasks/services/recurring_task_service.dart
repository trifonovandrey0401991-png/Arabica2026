import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/recurring_task_model.dart';
import '../models/task_model.dart' show TaskResponseType, TaskResponseTypeExtension;

/// Сервис для работы с циклическими задачами
class RecurringTaskService {
  static const String _baseEndpoint = ApiConstants.recurringTasksEndpoint;

  // ==================== ШАБЛОНЫ ====================

  /// Получить все шаблоны циклических задач
  static Future<List<RecurringTask>> getAllTemplates() async {
    try {
      final tasks = await BaseHttpService.getList<RecurringTask>(
        endpoint: _baseEndpoint,
        fromJson: (json) => RecurringTask.fromJson(json),
        listKey: 'tasks',
      );

      Logger.debug('Загружено ${tasks.length} шаблонов циклических задач');
      return tasks;
    } catch (e) {
      Logger.error('Ошибка загрузки шаблонов задач', e);
      rethrow;
    }
  }

  /// Получить шаблон по ID
  static Future<RecurringTask?> getTemplateById(String id) async {
    try {
      return await BaseHttpService.get<RecurringTask>(
        endpoint: '$_baseEndpoint/$id',
        fromJson: (json) => RecurringTask.fromJson(json),
        itemKey: 'task',
      );
    } catch (e) {
      Logger.error('Ошибка загрузки шаблона задачи', e);
      rethrow;
    }
  }

  /// Создать новый шаблон
  static Future<RecurringTask> createTemplate({
    required String title,
    required String description,
    required TaskResponseType responseType,
    required List<int> daysOfWeek,
    required String startTime,
    required String endTime,
    required List<String> reminderTimes,
    required List<TaskRecipient> assignees,
    required String createdBy,
  }) async {
    try {
      final result = await BaseHttpService.post<RecurringTask>(
        endpoint: _baseEndpoint,
        body: {
          'title': title,
          'description': description,
          'responseType': responseType.code,
          'daysOfWeek': daysOfWeek,
          'startTime': startTime,
          'endTime': endTime,
          'reminderTimes': reminderTimes,
          'assignees': assignees.map((e) => e.toJson()).toList(),
          'createdBy': createdBy,
        },
        fromJson: (json) => RecurringTask.fromJson(json),
        itemKey: 'task',
      );

      if (result == null) {
        throw Exception('Не удалось создать задачу');
      }

      Logger.info('Создан шаблон циклической задачи: $title');
      return result;
    } catch (e) {
      Logger.error('Ошибка создания шаблона задачи', e);
      rethrow;
    }
  }

  /// Обновить шаблон
  static Future<RecurringTask> updateTemplate(
    String id, {
    String? title,
    String? description,
    TaskResponseType? responseType,
    List<int>? daysOfWeek,
    String? startTime,
    String? endTime,
    List<String>? reminderTimes,
    List<TaskRecipient>? assignees,
  }) async {
    try {
      final body = <String, dynamic>{};

      if (title != null) body['title'] = title;
      if (description != null) body['description'] = description;
      if (responseType != null) body['responseType'] = responseType.code;
      if (daysOfWeek != null) body['daysOfWeek'] = daysOfWeek;
      if (startTime != null) body['startTime'] = startTime;
      if (endTime != null) body['endTime'] = endTime;
      if (reminderTimes != null) body['reminderTimes'] = reminderTimes;
      if (assignees != null) {
        body['assignees'] = assignees.map((e) => e.toJson()).toList();
      }

      final result = await BaseHttpService.put<RecurringTask>(
        endpoint: '$_baseEndpoint/$id',
        body: body,
        fromJson: (json) => RecurringTask.fromJson(json),
        itemKey: 'task',
      );

      if (result == null) {
        throw Exception('Не удалось обновить задачу');
      }

      Logger.info('Обновлен шаблон циклической задачи: $id');
      return result;
    } catch (e) {
      Logger.error('Ошибка обновления шаблона задачи', e);
      rethrow;
    }
  }

  /// Переключить паузу шаблона
  static Future<RecurringTask> togglePause(String id) async {
    try {
      final result = await BaseHttpService.put<RecurringTask>(
        endpoint: '$_baseEndpoint/$id/toggle-pause',
        body: {},
        fromJson: (json) => RecurringTask.fromJson(json),
        itemKey: 'task',
      );

      if (result == null) {
        throw Exception('Не удалось изменить статус задачи');
      }

      Logger.info(
          'Шаблон ${result.isPaused ? "приостановлен" : "возобновлен"}: $id');
      return result;
    } catch (e) {
      Logger.error('Ошибка переключения паузы', e);
      rethrow;
    }
  }

  /// Удалить шаблон
  static Future<void> deleteTemplate(String id) async {
    try {
      final success = await BaseHttpService.delete(
        endpoint: '$_baseEndpoint/$id',
      );

      if (!success) {
        throw Exception('Не удалось удалить задачу');
      }

      Logger.info('Удален шаблон циклической задачи: $id');
    } catch (e) {
      Logger.error('Ошибка удаления шаблона задачи', e);
      rethrow;
    }
  }

  // ==================== ЭКЗЕМПЛЯРЫ ====================

  /// Получить экземпляры задач для сотрудника
  static Future<List<RecurringTaskInstance>> getInstancesForAssignee({
    required String assigneePhone,
    String? date,
    String? status,
    String? yearMonth,
  }) async {
    try {
      final params = <String, String>{
        'assigneePhone': assigneePhone,
      };
      if (date != null) params['date'] = date;
      if (status != null) params['status'] = status;
      if (yearMonth != null) params['yearMonth'] = yearMonth;

      final instances = await BaseHttpService.getList<RecurringTaskInstance>(
        endpoint: '$_baseEndpoint/instances/list',
        fromJson: (json) => RecurringTaskInstance.fromJson(json),
        listKey: 'instances',
        queryParams: params,
      );

      Logger.debug(
          'Загружено ${instances.length} экземпляров задач для $assigneePhone');
      return instances;
    } catch (e) {
      Logger.error('Ошибка загрузки экземпляров задач', e);
      rethrow;
    }
  }

  /// Получить все экземпляры за период (для отчетов)
  static Future<List<RecurringTaskInstance>> getAllInstances({
    String? date,
    String? status,
    String? yearMonth,
  }) async {
    try {
      final params = <String, String>{};
      if (date != null) params['date'] = date;
      if (status != null) params['status'] = status;
      if (yearMonth != null) params['yearMonth'] = yearMonth;

      final instances = await BaseHttpService.getList<RecurringTaskInstance>(
        endpoint: '$_baseEndpoint/instances/list',
        fromJson: (json) => RecurringTaskInstance.fromJson(json),
        listKey: 'instances',
        queryParams: params.isNotEmpty ? params : null,
      );

      Logger.debug('Загружено ${instances.length} экземпляров задач');
      return instances;
    } catch (e) {
      Logger.error('Ошибка загрузки экземпляров задач', e);
      rethrow;
    }
  }

  /// Выполнить задачу
  static Future<RecurringTaskInstance> completeInstance({
    required String instanceId,
    String? responseText,
    List<String>? responsePhotos,
  }) async {
    try {
      final body = <String, dynamic>{};

      if (responseText != null) body['responseText'] = responseText;
      if (responsePhotos != null) body['responsePhotos'] = responsePhotos;

      final result = await BaseHttpService.post<RecurringTaskInstance>(
        endpoint: '$_baseEndpoint/instances/$instanceId/complete',
        body: body,
        fromJson: (json) => RecurringTaskInstance.fromJson(json),
        itemKey: 'instance',
      );

      if (result == null) {
        throw Exception('Не удалось выполнить задачу');
      }

      Logger.info('Выполнена циклическая задача: $instanceId');
      return result;
    } catch (e) {
      Logger.error('Ошибка выполнения задачи', e);
      rethrow;
    }
  }

  // ==================== УТИЛИТЫ ====================

  /// Ручная генерация задач на дату (для тестирования)
  static Future<int> generateDailyTasks({String? date}) async {
    try {
      final body = <String, dynamic>{};
      if (date != null) body['date'] = date;

      final result = await BaseHttpService.postRaw(
        endpoint: '$_baseEndpoint/generate-daily',
        body: body,
      );

      if (result == null) {
        throw Exception('Не удалось сгенерировать задачи');
      }

      final count = result['generatedCount'] as int? ?? 0;
      Logger.info('Сгенерировано $count задач на ${result['date']}');
      return count;
    } catch (e) {
      Logger.error('Ошибка генерации задач', e);
      rethrow;
    }
  }
}

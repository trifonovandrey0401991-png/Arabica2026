/// Модели для циклических задач
import 'task_model.dart';

export 'task_model.dart' show TaskResponseType;

/// Получатель задачи
class TaskRecipient {
  final String id;
  final String name;
  final String phone;

  const TaskRecipient({
    required this.id,
    required this.name,
    required this.phone,
  });

  factory TaskRecipient.fromJson(Map<String, dynamic> json) {
    return TaskRecipient(
      id: json['id']?.toString() ?? json['phone']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
    };
  }
}

/// Шаблон циклической задачи
class RecurringTask {
  final String id;
  final String title;
  final String description;
  final TaskResponseType responseType;
  final List<int> daysOfWeek; // 0=Вс, 1=Пн, 2=Вт, 3=Ср, 4=Чт, 5=Пт, 6=Сб
  final String startTime; // "HH:mm"
  final String endTime; // "HH:mm"
  final List<String> reminderTimes; // ["HH:mm", ...]
  final List<TaskRecipient> assignees;
  final bool isPaused;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RecurringTask({
    required this.id,
    required this.title,
    required this.description,
    required this.responseType,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
    required this.reminderTimes,
    required this.assignees,
    required this.isPaused,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RecurringTask.fromJson(Map<String, dynamic> json) {
    return RecurringTask(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      responseType: TaskResponseTypeExtension.fromCode(json['responseType']?.toString() ?? 'text'),
      daysOfWeek: (json['daysOfWeek'] as List<dynamic>?)
              ?.map((e) => int.tryParse(e.toString()) ?? 0)
              .toList() ??
          [],
      startTime: json['startTime']?.toString() ?? '08:00',
      endTime: json['endTime']?.toString() ?? '18:00',
      reminderTimes: (json['reminderTimes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['09:00', '12:00', '17:00'],
      assignees: (json['assignees'] as List<dynamic>?)
              ?.map((e) => TaskRecipient.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isPaused: json['isPaused'] == true,
      createdBy: json['createdBy']?.toString() ?? 'admin',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'responseType': responseType.code,
      'daysOfWeek': daysOfWeek,
      'startTime': startTime,
      'endTime': endTime,
      'reminderTimes': reminderTimes,
      'assignees': assignees.map((e) => e.toJson()).toList(),
      'isPaused': isPaused,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Копирование с изменениями
  RecurringTask copyWith({
    String? id,
    String? title,
    String? description,
    TaskResponseType? responseType,
    List<int>? daysOfWeek,
    String? startTime,
    String? endTime,
    List<String>? reminderTimes,
    List<TaskRecipient>? assignees,
    bool? isPaused,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RecurringTask(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      responseType: responseType ?? this.responseType,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      reminderTimes: reminderTimes ?? this.reminderTimes,
      assignees: assignees ?? this.assignees,
      isPaused: isPaused ?? this.isPaused,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Получить названия дней недели
  String get daysOfWeekDisplay {
    const dayNames = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
    return daysOfWeek.map((d) => dayNames[d]).join(', ');
  }

  /// Получить период выполнения
  String get periodDisplay => '$startTime - $endTime';
}

/// Экземпляр циклической задачи (сгенерированный)
class RecurringTaskInstance {
  final String id;
  final String recurringTaskId;
  final String assigneeId;
  final String assigneeName;
  final String assigneePhone;
  final String date; // "YYYY-MM-DD"
  final DateTime deadline;
  final List<String> reminderTimes;
  final String status; // 'pending' | 'completed' | 'expired'
  final String? responseText;
  final List<String> responsePhotos;
  final DateTime? completedAt;
  final DateTime? expiredAt;
  final bool isRecurring;
  final String title;
  final String description;
  final TaskResponseType responseType;
  final DateTime createdAt;

  const RecurringTaskInstance({
    required this.id,
    required this.recurringTaskId,
    required this.assigneeId,
    required this.assigneeName,
    required this.assigneePhone,
    required this.date,
    required this.deadline,
    required this.reminderTimes,
    required this.status,
    this.responseText,
    required this.responsePhotos,
    this.completedAt,
    this.expiredAt,
    required this.isRecurring,
    required this.title,
    required this.description,
    required this.responseType,
    required this.createdAt,
  });

  factory RecurringTaskInstance.fromJson(Map<String, dynamic> json) {
    return RecurringTaskInstance(
      id: json['id']?.toString() ?? '',
      recurringTaskId: json['recurringTaskId']?.toString() ?? '',
      assigneeId: json['assigneeId']?.toString() ?? '',
      assigneeName: json['assigneeName']?.toString() ?? '',
      assigneePhone: json['assigneePhone']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      deadline: DateTime.tryParse(json['deadline']?.toString() ?? '') ??
          DateTime.now(),
      reminderTimes: (json['reminderTimes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      status: json['status']?.toString() ?? 'pending',
      responseText: json['responseText']?.toString(),
      responsePhotos: (json['responsePhotos'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'].toString())
          : null,
      expiredAt: json['expiredAt'] != null
          ? DateTime.tryParse(json['expiredAt'].toString())
          : null,
      isRecurring: json['isRecurring'] == true,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      responseType: TaskResponseTypeExtension.fromCode(json['responseType']?.toString() ?? 'text'),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'recurringTaskId': recurringTaskId,
      'assigneeId': assigneeId,
      'assigneeName': assigneeName,
      'assigneePhone': assigneePhone,
      'date': date,
      'deadline': deadline.toIso8601String(),
      'reminderTimes': reminderTimes,
      'status': status,
      'responseText': responseText,
      'responsePhotos': responsePhotos,
      'completedAt': completedAt?.toIso8601String(),
      'expiredAt': expiredAt?.toIso8601String(),
      'isRecurring': isRecurring,
      'title': title,
      'description': description,
      'responseType': responseType.code,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Проверить, просрочена ли задача
  bool get isExpired => status == 'expired' || DateTime.now().isAfter(deadline);

  /// Проверить, выполнена ли задача
  bool get isCompleted => status == 'completed';

  /// Проверить, ожидает ли выполнения
  bool get isPending => status == 'pending';

  /// Получить отображаемый статус
  String get statusDisplay {
    switch (status) {
      case 'completed':
        return 'Выполнено';
      case 'expired':
        return 'Просрочено';
      case 'pending':
      default:
        return 'Ожидает';
    }
  }
}

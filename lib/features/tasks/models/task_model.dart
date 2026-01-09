/// Тип ответа на задачу
enum TaskResponseType {
  photo,        // Только фото
  photoAndText, // Фото и текст
  text,         // Только текст
}

extension TaskResponseTypeExtension on TaskResponseType {
  String get displayName {
    switch (this) {
      case TaskResponseType.photo:
        return 'Только фото';
      case TaskResponseType.photoAndText:
        return 'Фото и текст';
      case TaskResponseType.text:
        return 'Только текст';
    }
  }

  String get code {
    switch (this) {
      case TaskResponseType.photo:
        return 'photo';
      case TaskResponseType.photoAndText:
        return 'photoAndText';
      case TaskResponseType.text:
        return 'text';
    }
  }

  static TaskResponseType fromCode(String code) {
    switch (code) {
      case 'photo':
        return TaskResponseType.photo;
      case 'photoAndText':
        return TaskResponseType.photoAndText;
      case 'text':
        return TaskResponseType.text;
      default:
        return TaskResponseType.photo;
    }
  }
}

/// Статус назначения задачи
enum TaskStatus {
  pending,    // Ожидает ответа работника
  submitted,  // Работник ответил, ожидает проверки
  approved,   // Админ подтвердил (+1 балл)
  rejected,   // Админ отклонил (-3 балла)
  expired,    // Дедлайн прошел (-3 балла)
  declined,   // Работник отклонил (-3 балла)
}

extension TaskStatusExtension on TaskStatus {
  String get displayName {
    switch (this) {
      case TaskStatus.pending:
        return 'Ожидает ответа';
      case TaskStatus.submitted:
        return 'На проверке';
      case TaskStatus.approved:
        return 'Выполнено';
      case TaskStatus.rejected:
        return 'Отклонено';
      case TaskStatus.expired:
        return 'Просрочено';
      case TaskStatus.declined:
        return 'Отказано';
    }
  }

  String get code {
    switch (this) {
      case TaskStatus.pending:
        return 'pending';
      case TaskStatus.submitted:
        return 'submitted';
      case TaskStatus.approved:
        return 'approved';
      case TaskStatus.rejected:
        return 'rejected';
      case TaskStatus.expired:
        return 'expired';
      case TaskStatus.declined:
        return 'declined';
    }
  }

  static TaskStatus fromCode(String code) {
    switch (code) {
      case 'pending':
        return TaskStatus.pending;
      case 'submitted':
        return TaskStatus.submitted;
      case 'approved':
        return TaskStatus.approved;
      case 'rejected':
        return TaskStatus.rejected;
      case 'expired':
        return TaskStatus.expired;
      case 'declined':
        return TaskStatus.declined;
      default:
        return TaskStatus.pending;
    }
  }

  bool get isActive => this == TaskStatus.pending || this == TaskStatus.submitted;
  bool get isCompleted => this == TaskStatus.approved;
  bool get isFailed => this == TaskStatus.rejected || this == TaskStatus.expired || this == TaskStatus.declined;
}

/// Задача (создается админом)
class Task {
  final String id;
  final String title;
  final String description;
  final TaskResponseType responseType;
  final DateTime deadline;
  final String createdBy;
  final DateTime createdAt;
  final List<String> attachments; // Прикрепленные фото при создании задачи

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.responseType,
    required this.deadline,
    required this.createdBy,
    required this.createdAt,
    this.attachments = const [],
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      responseType: TaskResponseTypeExtension.fromCode(json['responseType'] ?? 'photo'),
      deadline: DateTime.tryParse(json['deadline'] ?? '') ?? DateTime.now(),
      createdBy: json['createdBy'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      attachments: (json['attachments'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'responseType': responseType.code,
    'deadline': deadline.toIso8601String(),
    'createdBy': createdBy,
    'createdAt': createdAt.toIso8601String(),
    'attachments': attachments,
  };

  bool get isOverdue => DateTime.now().isAfter(deadline);
}

/// Назначение задачи (связь задачи с работником)
class TaskAssignment {
  final String id;
  final String taskId;
  final String assigneeId;
  final String assigneeName;
  final String assigneeRole;
  final TaskStatus status;
  final DateTime deadline;
  final DateTime createdAt;
  final String? responseText;
  final List<String> responsePhotos;
  final DateTime? respondedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewComment;
  final DateTime? declinedAt;
  final String? declineReason;
  final DateTime? expiredAt;

  // Вложенный объект задачи (может быть загружен с сервера)
  final Task? task;

  TaskAssignment({
    required this.id,
    required this.taskId,
    required this.assigneeId,
    required this.assigneeName,
    required this.assigneeRole,
    required this.status,
    required this.deadline,
    required this.createdAt,
    this.responseText,
    this.responsePhotos = const [],
    this.respondedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewComment,
    this.declinedAt,
    this.declineReason,
    this.expiredAt,
    this.task,
  });

  factory TaskAssignment.fromJson(Map<String, dynamic> json) {
    return TaskAssignment(
      id: json['id'] ?? '',
      taskId: json['taskId'] ?? '',
      assigneeId: json['assigneeId'] ?? '',
      assigneeName: json['assigneeName'] ?? '',
      assigneeRole: json['assigneeRole'] ?? 'employee',
      status: TaskStatusExtension.fromCode(json['status'] ?? 'pending'),
      deadline: DateTime.tryParse(json['deadline'] ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      responseText: json['responseText'],
      responsePhotos: (json['responsePhotos'] as List<dynamic>?)?.cast<String>() ?? [],
      respondedAt: json['respondedAt'] != null ? DateTime.tryParse(json['respondedAt']) : null,
      reviewedBy: json['reviewedBy'],
      reviewedAt: json['reviewedAt'] != null ? DateTime.tryParse(json['reviewedAt']) : null,
      reviewComment: json['reviewComment'],
      declinedAt: json['declinedAt'] != null ? DateTime.tryParse(json['declinedAt']) : null,
      declineReason: json['declineReason'],
      expiredAt: json['expiredAt'] != null ? DateTime.tryParse(json['expiredAt']) : null,
      task: json['task'] != null ? Task.fromJson(json['task']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'assigneeId': assigneeId,
    'assigneeName': assigneeName,
    'assigneeRole': assigneeRole,
    'status': status.code,
    'deadline': deadline.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    if (responseText != null) 'responseText': responseText,
    'responsePhotos': responsePhotos,
    if (respondedAt != null) 'respondedAt': respondedAt!.toIso8601String(),
    if (reviewedBy != null) 'reviewedBy': reviewedBy,
    if (reviewedAt != null) 'reviewedAt': reviewedAt!.toIso8601String(),
    if (reviewComment != null) 'reviewComment': reviewComment,
    if (declinedAt != null) 'declinedAt': declinedAt!.toIso8601String(),
    if (declineReason != null) 'declineReason': declineReason,
    if (expiredAt != null) 'expiredAt': expiredAt!.toIso8601String(),
    if (task != null) 'task': task!.toJson(),
  };

  bool get isOverdue => DateTime.now().isAfter(deadline);

  /// Название задачи (из вложенного объекта или пустая строка)
  String get taskTitle => task?.title ?? '';

  /// Описание задачи
  String get taskDescription => task?.description ?? '';

  /// Тип ответа
  TaskResponseType get responseType => task?.responseType ?? TaskResponseType.photo;
}

/// Получатель задачи (для выбора при создании)
class TaskRecipient {
  final String id;
  final String name;
  final String role; // 'manager' или 'employee'

  TaskRecipient({
    required this.id,
    required this.name,
    required this.role,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role,
  };
}

/// Настройки баллов за задачи
class TaskPointsSettings {
  final double approvedPoints;   // +1
  final double rejectedPoints;   // -3
  final double expiredPoints;    // -3
  final double declinedPoints;   // -3

  TaskPointsSettings({
    this.approvedPoints = 1.0,
    this.rejectedPoints = -3.0,
    this.expiredPoints = -3.0,
    this.declinedPoints = -3.0,
  });

  factory TaskPointsSettings.fromJson(Map<String, dynamic> json) {
    return TaskPointsSettings(
      approvedPoints: (json['approvedPoints'] ?? 1.0).toDouble(),
      rejectedPoints: (json['rejectedPoints'] ?? -3.0).toDouble(),
      expiredPoints: (json['expiredPoints'] ?? -3.0).toDouble(),
      declinedPoints: (json['declinedPoints'] ?? -3.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'approvedPoints': approvedPoints,
    'rejectedPoints': rejectedPoints,
    'expiredPoints': expiredPoints,
    'declinedPoints': declinedPoints,
  };

  /// Получить баллы за статус
  double getPointsForStatus(TaskStatus status) {
    switch (status) {
      case TaskStatus.approved:
        return approvedPoints;
      case TaskStatus.rejected:
        return rejectedPoints;
      case TaskStatus.expired:
        return expiredPoints;
      case TaskStatus.declined:
        return declinedPoints;
      default:
        return 0;
    }
  }
}

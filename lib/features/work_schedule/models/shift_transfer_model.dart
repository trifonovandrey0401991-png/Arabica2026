import 'work_schedule_model.dart';

/// Статус запроса на передачу смены
enum ShiftTransferStatus {
  pending,   // Ожидает ответа сотрудника
  accepted,  // Сотрудник принял, ждет одобрения админа
  rejected,  // Сотрудник отклонил
  approved,  // Админ одобрил, график обновлен
  declined,  // Админ отклонил
  expired,   // Истек срок (30 дней)
}

extension ShiftTransferStatusExtension on ShiftTransferStatus {
  String get name {
    switch (this) {
      case ShiftTransferStatus.pending:
        return 'pending';
      case ShiftTransferStatus.accepted:
        return 'accepted';
      case ShiftTransferStatus.rejected:
        return 'rejected';
      case ShiftTransferStatus.approved:
        return 'approved';
      case ShiftTransferStatus.declined:
        return 'declined';
      case ShiftTransferStatus.expired:
        return 'expired';
    }
  }

  String get label {
    switch (this) {
      case ShiftTransferStatus.pending:
        return 'Ожидает ответа';
      case ShiftTransferStatus.accepted:
        return 'Принято';
      case ShiftTransferStatus.rejected:
        return 'Отклонено';
      case ShiftTransferStatus.approved:
        return 'Одобрено';
      case ShiftTransferStatus.declined:
        return 'Отказано';
      case ShiftTransferStatus.expired:
        return 'Истек срок';
    }
  }

  static ShiftTransferStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'pending':
        return ShiftTransferStatus.pending;
      case 'accepted':
        return ShiftTransferStatus.accepted;
      case 'rejected':
        return ShiftTransferStatus.rejected;
      case 'approved':
        return ShiftTransferStatus.approved;
      case 'declined':
        return ShiftTransferStatus.declined;
      case 'expired':
        return ShiftTransferStatus.expired;
      default:
        return ShiftTransferStatus.pending;
    }
  }
}

/// Запрос на передачу смены
class ShiftTransferRequest {
  final String id;
  final String fromEmployeeId;
  final String fromEmployeeName;
  final String? toEmployeeId;
  final String? toEmployeeName;
  final String scheduleEntryId;
  final DateTime shiftDate;
  final String shopAddress;
  final String shopName;
  final ShiftType shiftType;
  final String? comment;
  final ShiftTransferStatus status;
  final String? acceptedByEmployeeId;
  final String? acceptedByEmployeeName;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? resolvedAt;
  final bool isReadByRecipient;
  final bool isReadByAdmin;

  ShiftTransferRequest({
    required this.id,
    required this.fromEmployeeId,
    required this.fromEmployeeName,
    this.toEmployeeId,
    this.toEmployeeName,
    required this.scheduleEntryId,
    required this.shiftDate,
    required this.shopAddress,
    required this.shopName,
    required this.shiftType,
    this.comment,
    this.status = ShiftTransferStatus.pending,
    this.acceptedByEmployeeId,
    this.acceptedByEmployeeName,
    required this.createdAt,
    this.acceptedAt,
    this.resolvedAt,
    this.isReadByRecipient = false,
    this.isReadByAdmin = false,
  });

  /// Запрос отправлен всем сотрудникам
  bool get isBroadcast => toEmployeeId == null;

  /// Запрос активен (можно принять/отклонить)
  bool get isActive => status == ShiftTransferStatus.pending;

  /// Запрос ожидает одобрения админа
  bool get isPendingApproval => status == ShiftTransferStatus.accepted;

  /// Запрос завершен
  bool get isCompleted =>
      status == ShiftTransferStatus.approved ||
      status == ShiftTransferStatus.declined ||
      status == ShiftTransferStatus.rejected ||
      status == ShiftTransferStatus.expired;

  factory ShiftTransferRequest.fromJson(Map<String, dynamic> json) {
    return ShiftTransferRequest(
      id: json['id'] ?? '',
      fromEmployeeId: json['fromEmployeeId'] ?? '',
      fromEmployeeName: json['fromEmployeeName'] ?? '',
      toEmployeeId: json['toEmployeeId'],
      toEmployeeName: json['toEmployeeName'],
      scheduleEntryId: json['scheduleEntryId'] ?? '',
      shiftDate: DateTime.parse(json['shiftDate']),
      shopAddress: json['shopAddress'] ?? '',
      shopName: json['shopName'] ?? '',
      shiftType: ShiftTypeExtension.fromString(json['shiftType'] ?? 'morning') ?? ShiftType.morning,
      comment: json['comment'],
      status: ShiftTransferStatusExtension.fromString(json['status'] ?? 'pending'),
      acceptedByEmployeeId: json['acceptedByEmployeeId'],
      acceptedByEmployeeName: json['acceptedByEmployeeName'],
      createdAt: DateTime.parse(json['createdAt']),
      acceptedAt: json['acceptedAt'] != null ? DateTime.parse(json['acceptedAt']) : null,
      resolvedAt: json['resolvedAt'] != null ? DateTime.parse(json['resolvedAt']) : null,
      isReadByRecipient: json['isReadByRecipient'] ?? false,
      isReadByAdmin: json['isReadByAdmin'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromEmployeeId': fromEmployeeId,
      'fromEmployeeName': fromEmployeeName,
      'toEmployeeId': toEmployeeId,
      'toEmployeeName': toEmployeeName,
      'scheduleEntryId': scheduleEntryId,
      'shiftDate': shiftDate.toIso8601String().split('T')[0],
      'shopAddress': shopAddress,
      'shopName': shopName,
      'shiftType': shiftType.name,
      'comment': comment,
      'status': status.name,
      'acceptedByEmployeeId': acceptedByEmployeeId,
      'acceptedByEmployeeName': acceptedByEmployeeName,
      'createdAt': createdAt.toIso8601String(),
      'acceptedAt': acceptedAt?.toIso8601String(),
      'resolvedAt': resolvedAt?.toIso8601String(),
      'isReadByRecipient': isReadByRecipient,
      'isReadByAdmin': isReadByAdmin,
    };
  }

  ShiftTransferRequest copyWith({
    String? id,
    String? fromEmployeeId,
    String? fromEmployeeName,
    String? toEmployeeId,
    String? toEmployeeName,
    String? scheduleEntryId,
    DateTime? shiftDate,
    String? shopAddress,
    String? shopName,
    ShiftType? shiftType,
    String? comment,
    ShiftTransferStatus? status,
    String? acceptedByEmployeeId,
    String? acceptedByEmployeeName,
    DateTime? createdAt,
    DateTime? acceptedAt,
    DateTime? resolvedAt,
    bool? isReadByRecipient,
    bool? isReadByAdmin,
  }) {
    return ShiftTransferRequest(
      id: id ?? this.id,
      fromEmployeeId: fromEmployeeId ?? this.fromEmployeeId,
      fromEmployeeName: fromEmployeeName ?? this.fromEmployeeName,
      toEmployeeId: toEmployeeId ?? this.toEmployeeId,
      toEmployeeName: toEmployeeName ?? this.toEmployeeName,
      scheduleEntryId: scheduleEntryId ?? this.scheduleEntryId,
      shiftDate: shiftDate ?? this.shiftDate,
      shopAddress: shopAddress ?? this.shopAddress,
      shopName: shopName ?? this.shopName,
      shiftType: shiftType ?? this.shiftType,
      comment: comment ?? this.comment,
      status: status ?? this.status,
      acceptedByEmployeeId: acceptedByEmployeeId ?? this.acceptedByEmployeeId,
      acceptedByEmployeeName: acceptedByEmployeeName ?? this.acceptedByEmployeeName,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      isReadByRecipient: isReadByRecipient ?? this.isReadByRecipient,
      isReadByAdmin: isReadByAdmin ?? this.isReadByAdmin,
    );
  }

  @override
  String toString() {
    return 'ShiftTransferRequest(id: $id, from: $fromEmployeeName, to: ${toEmployeeName ?? 'всем'}, date: ${shiftDate.day}.${shiftDate.month}, status: ${status.label})';
  }
}

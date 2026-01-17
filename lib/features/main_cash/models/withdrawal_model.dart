import 'package:uuid/uuid.dart';
import 'withdrawal_expense_model.dart';

/// Модель выемки денег из кассы
class Withdrawal {
  final String id;
  final String shopAddress;
  final String employeeName;
  final String employeeId;
  final String type; // "ooo" или "ip"
  final double totalAmount; // Общая сумма всех расходов
  final List<WithdrawalExpense> expenses; // Список расходов
  final String? adminName;
  final DateTime createdAt;
  final bool confirmed; // Подтверждена ли выемка

  Withdrawal({
    String? id,
    required this.shopAddress,
    required this.employeeName,
    required this.employeeId,
    required this.type,
    required this.totalAmount,
    required this.expenses,
    this.adminName,
    DateTime? createdAt,
    this.confirmed = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  factory Withdrawal.fromJson(Map<String, dynamic> json) {
    // Обратная совместимость со старым форматом
    final expensesJson = json['expenses'] as List<dynamic>? ?? [];
    final expenses = expensesJson
        .map((e) => WithdrawalExpense.fromJson(e as Map<String, dynamic>))
        .toList();

    // Поддержка старого формата: amount -> totalAmount
    final totalAmount = json['totalAmount'] != null
        ? (json['totalAmount'] as num).toDouble()
        : (json['amount'] as num?)?.toDouble() ?? 0.0;

    // Поддержка старого формата: может не быть employeeName и employeeId
    final employeeName = json['employeeName'] as String? ?? json['adminName'] as String? ?? 'Неизвестно';
    final employeeId = json['employeeId'] as String? ?? '';

    return Withdrawal(
      id: json['id'] as String,
      shopAddress: json['shopAddress'] as String,
      employeeName: employeeName,
      employeeId: employeeId,
      type: json['type'] as String,
      totalAmount: totalAmount,
      expenses: expenses,
      adminName: json['adminName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      confirmed: json['confirmed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shopAddress': shopAddress,
      'employeeName': employeeName,
      'employeeId': employeeId,
      'type': type,
      'totalAmount': totalAmount,
      'expenses': expenses.map((e) => e.toJson()).toList(),
      'adminName': adminName,
      'createdAt': createdAt.toIso8601String(),
      'confirmed': confirmed,
    };
  }

  Withdrawal copyWith({
    String? id,
    String? shopAddress,
    String? employeeName,
    String? employeeId,
    String? type,
    double? totalAmount,
    List<WithdrawalExpense>? expenses,
    String? adminName,
    DateTime? createdAt,
    bool? confirmed,
  }) {
    return Withdrawal(
      id: id ?? this.id,
      shopAddress: shopAddress ?? this.shopAddress,
      employeeName: employeeName ?? this.employeeName,
      employeeId: employeeId ?? this.employeeId,
      type: type ?? this.type,
      totalAmount: totalAmount ?? this.totalAmount,
      expenses: expenses ?? this.expenses,
      adminName: adminName ?? this.adminName,
      createdAt: createdAt ?? this.createdAt,
      confirmed: confirmed ?? this.confirmed,
    );
  }

  String get typeDisplayName => type == 'ooo' ? 'ООО' : 'ИП';

  String get formattedDate {
    return '${createdAt.day.toString().padLeft(2, '0')}.'
        '${createdAt.month.toString().padLeft(2, '0')}.'
        '${createdAt.year}';
  }

  String get formattedTime {
    return '${createdAt.hour.toString().padLeft(2, '0')}:'
        '${createdAt.minute.toString().padLeft(2, '0')}';
  }

  String get formattedDateTime => '$formattedDate, $formattedTime';
}

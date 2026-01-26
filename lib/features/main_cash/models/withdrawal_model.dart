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
  final String? status; // "active" или "cancelled"
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelReason;
  final String category; // "withdrawal" | "deposit" | "transfer"
  final String? transferDirection; // "ooo_to_ip" | "ip_to_ooo" (для переносов)

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
    this.status,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
    this.category = 'withdrawal',
    this.transferDirection,
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
      status: json['status'] as String?,
      cancelledAt: json['cancelledAt'] != null
        ? DateTime.parse(json['cancelledAt'] as String)
        : null,
      cancelledBy: json['cancelledBy'] as String?,
      cancelReason: json['cancelReason'] as String?,
      category: json['category'] as String? ?? 'withdrawal',
      transferDirection: json['transferDirection'] as String?,
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
      'category': category,
      if (status != null) 'status': status,
      if (cancelledAt != null) 'cancelledAt': cancelledAt!.toIso8601String(),
      if (cancelledBy != null) 'cancelledBy': cancelledBy,
      if (cancelReason != null) 'cancelReason': cancelReason,
      if (transferDirection != null) 'transferDirection': transferDirection,
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
    String? status,
    DateTime? cancelledAt,
    String? cancelledBy,
    String? cancelReason,
    String? category,
    String? transferDirection,
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
      status: status ?? this.status,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      cancelReason: cancelReason ?? this.cancelReason,
      category: category ?? this.category,
      transferDirection: transferDirection ?? this.transferDirection,
    );
  }

  String get typeDisplayName => type == 'ooo' ? 'ООО' : 'ИП';

  /// Название категории операции
  String get categoryDisplayName {
    switch (category) {
      case 'deposit':
        return 'ВНЕСЕНИЕ';
      case 'transfer':
        if (transferDirection == 'ooo_to_ip') {
          return 'ПЕРЕНОС ООО→ИП';
        } else if (transferDirection == 'ip_to_ooo') {
          return 'ПЕРЕНОС ИП→ООО';
        }
        return 'ПЕРЕНОС';
      case 'withdrawal':
      default:
        return 'ВЫЕМКА';
    }
  }

  /// Проверить, является ли это внесением
  bool get isDeposit => category == 'deposit';

  /// Проверить, является ли это переносом
  bool get isTransfer => category == 'transfer';

  /// Проверить, является ли это выемкой
  bool get isWithdrawal => category == 'withdrawal';

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

  /// Проверить, отменена ли выемка
  bool get isCancelled => status == 'cancelled';

  /// Проверить, активна ли выемка
  bool get isActive => status != 'cancelled';

  /// Валидация: проверить что totalAmount соответствует сумме всех расходов
  bool validateTotalAmount() {
    if (expenses.isEmpty) {
      return totalAmount == 0;
    }

    final calculatedTotal = expenses.fold<double>(
      0.0,
      (sum, expense) => sum + expense.amount,
    );

    // Используем небольшую погрешность для сравнения float чисел
    return (calculatedTotal - totalAmount).abs() <= 0.01;
  }

  /// Получить вычисленную сумму всех расходов
  double get calculatedTotal {
    return expenses.fold<double>(
      0.0,
      (sum, expense) => sum + expense.amount,
    );
  }

  /// Валидация: проверить что все расходы имеют положительные суммы
  bool validateExpenseAmounts() {
    return expenses.every((expense) => expense.amount > 0);
  }

  /// Полная валидация выемки
  String? validate() {
    if (!validateExpenseAmounts()) {
      return 'Все расходы должны иметь положительные суммы';
    }

    if (!validateTotalAmount()) {
      return 'Общая сумма (${totalAmount.toStringAsFixed(2)}) не соответствует сумме расходов (${calculatedTotal.toStringAsFixed(2)})';
    }

    return null; // Нет ошибок
  }
}

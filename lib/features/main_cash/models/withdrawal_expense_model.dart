/// Модель расхода в рамках выемки
class WithdrawalExpense {
  final String? supplierId;
  final String? supplierName;
  final double amount;
  final String comment;

  const WithdrawalExpense({
    this.supplierId,
    this.supplierName,
    required this.amount,
    required this.comment,
  });

  /// Проверка, является ли это "Другим расходом" (без поставщика)
  bool get isOtherExpense => supplierId == null;

  /// Отображаемое название (поставщик или "Другой расход")
  String get displayName => supplierName ?? 'Другой расход';

  factory WithdrawalExpense.fromJson(Map<String, dynamic> json) {
    return WithdrawalExpense(
      supplierId: json['supplierId'] as String?,
      supplierName: json['supplierName'] as String?,
      amount: (json['amount'] as num).toDouble(),
      comment: json['comment'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'supplierId': supplierId,
      'supplierName': supplierName,
      'amount': amount,
      'comment': comment,
    };
  }

  WithdrawalExpense copyWith({
    String? supplierId,
    String? supplierName,
    double? amount,
    String? comment,
  }) {
    return WithdrawalExpense(
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      amount: amount ?? this.amount,
      comment: comment ?? this.comment,
    );
  }
}

import 'package:arabica_app/core/utils/date_formatter.dart';

/// Модель недостачи товара при пересменке
/// Записывается когда сотрудник подтверждает что товар отсутствует,
/// но на остатках (DBF) он есть
class ShiftShortage {
  final String productId;
  final String barcode;
  final String productName;
  final int stockQuantity; // Кол-во на остатках (из DBF)
  final DateTime confirmedAt;
  final String employeeName;

  ShiftShortage({
    required this.productId,
    required this.barcode,
    required this.productName,
    required this.stockQuantity,
    required this.confirmedAt,
    required this.employeeName,
  });

  factory ShiftShortage.fromJson(Map<String, dynamic> json) {
    return ShiftShortage(
      productId: json['productId'] ?? '',
      barcode: json['barcode'] ?? '',
      productName: json['productName'] ?? '',
      stockQuantity: json['stockQuantity'] ?? 0,
      confirmedAt: parseServerDateOrNow(json['confirmedAt']),
      employeeName: json['employeeName'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'barcode': barcode,
      'productName': productName,
      'stockQuantity': stockQuantity,
      'confirmedAt': confirmedAt.toIso8601String(),
      'employeeName': employeeName,
    };
  }

  @override
  String toString() {
    return 'ShiftShortage(productId: $productId, barcode: $barcode, productName: $productName, stockQuantity: $stockQuantity)';
  }
}

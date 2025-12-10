import 'dart:convert';

/// Метаданные РКО
class RKOMetadata {
  final String fileName;
  final String employeeName;
  final String shopAddress;
  final DateTime date;
  final double amount;
  final String rkoType;
  final DateTime createdAt;

  RKOMetadata({
    required this.fileName,
    required this.employeeName,
    required this.shopAddress,
    required this.date,
    required this.amount,
    required this.rkoType,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'employeeName': employeeName,
    'shopAddress': shopAddress,
    'date': date.toIso8601String(),
    'amount': amount,
    'rkoType': rkoType,
    'createdAt': createdAt.toIso8601String(),
  };

  factory RKOMetadata.fromJson(Map<String, dynamic> json) {
    return RKOMetadata(
      fileName: json['fileName'] ?? '',
      employeeName: json['employeeName'] ?? '',
      shopAddress: json['shopAddress'] ?? '',
      date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
      amount: (json['amount'] ?? 0).toDouble(),
      rkoType: json['rkoType'] ?? '',
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  /// Получить месяц в формате YYYY-MM
  String get monthKey => '${date.year}-${date.month.toString().padLeft(2, '0')}';

  /// Получить год-месяц для группировки
  String get yearMonth => monthKey;
}

/// Список метаданных РКО
class RKOMetadataList {
  final List<RKOMetadata> items;

  RKOMetadataList({required this.items});

  Map<String, dynamic> toJson() => {
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory RKOMetadataList.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>?)
        ?.map((item) => RKOMetadata.fromJson(item as Map<String, dynamic>))
        .toList() ?? [];
    return RKOMetadataList(items: items);
  }

  /// Получить последние N РКО сотрудника
  List<RKOMetadata> getLatestForEmployee(String employeeName, int count) {
    final employeeRKOs = items
        .where((rko) => rko.employeeName == employeeName)
        .toList();
    employeeRKOs.sort((a, b) => b.date.compareTo(a.date));
    return employeeRKOs.take(count).toList();
  }

  /// Получить РКО сотрудника за месяц
  List<RKOMetadata> getForEmployeeByMonth(String employeeName, String monthKey) {
    return items
        .where((rko) => rko.employeeName == employeeName && rko.monthKey == monthKey)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Получить РКО магазина за месяц
  List<RKOMetadata> getForShopByMonth(String shopAddress, String monthKey) {
    return items
        .where((rko) => rko.shopAddress == shopAddress && rko.monthKey == monthKey)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Получить уникальные месяцы для сотрудника
  List<String> getMonthsForEmployee(String employeeName) {
    final months = items
        .where((rko) => rko.employeeName == employeeName)
        .map((rko) => rko.monthKey)
        .toSet()
        .toList();
    months.sort((a, b) => b.compareTo(a)); // Новые первыми
    return months;
  }

  /// Получить уникальные месяцы для магазина
  List<String> getMonthsForShop(String shopAddress) {
    final months = items
        .where((rko) => rko.shopAddress == shopAddress)
        .map((rko) => rko.monthKey)
        .toSet()
        .toList();
    months.sort((a, b) => b.compareTo(a)); // Новые первыми
    return months;
  }

  /// Получить уникальных сотрудников
  List<String> getUniqueEmployees() {
    return items.map((rko) => rko.employeeName).toSet().toList();
  }

  /// Получить уникальные магазины
  List<String> getUniqueShops() {
    return items.map((rko) => rko.shopAddress).toSet().toList();
  }
}





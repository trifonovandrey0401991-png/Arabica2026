/// A row in the OOS table: product + stock per shop
class OosTableRow {
  final String barcode;
  final String productName;
  final Map<String, int?> shopStocks; // shopId → stock (null = not in shop)

  OosTableRow({
    required this.barcode,
    required this.productName,
    this.shopStocks = const {},
  });

  factory OosTableRow.fromJson(Map<String, dynamic> json) {
    final shops = json['shops'] as Map<String, dynamic>? ?? {};
    return OosTableRow(
      barcode: json['barcode'] ?? '',
      productName: json['productName'] ?? '',
      shopStocks: shops.map((k, v) => MapEntry(k, v as int?)),
    );
  }
}

/// Shop info for table columns
class OosShopInfo {
  final String id;
  final String name;
  final DateTime? lastSync;

  OosShopInfo({required this.id, required this.name, this.lastSync});

  /// Is DBF data stale (more than 5 minutes since last sync)?
  bool get isStale {
    if (lastSync == null) return true;
    return DateTime.now().difference(lastSync!) > const Duration(minutes: 5);
  }

  /// Has any DBF data at all?
  bool get hasData => lastSync != null;

  factory OosShopInfo.fromJson(Map<String, dynamic> json) {
    return OosShopInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      lastSync: json['lastSync'] != null
          ? DateTime.tryParse(json['lastSync'])
          : null,
    );
  }
}

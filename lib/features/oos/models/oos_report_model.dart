/// Shop summary in OOS report
class OosShopSummary {
  final String shopId;
  final String shopName;
  final int oosCount;
  final bool hasDbf;

  OosShopSummary({
    required this.shopId,
    required this.shopName,
    this.oosCount = 0,
    this.hasDbf = false,
  });

  factory OosShopSummary.fromJson(Map<String, dynamic> json) {
    return OosShopSummary(
      shopId: json['shopId'] ?? '',
      shopName: json['shopName'] ?? '',
      oosCount: json['oosCount'] ?? 0,
      hasDbf: json['hasDbf'] ?? false,
    );
  }
}

/// Detailed OOS report for one shop + one month
class OosReportDetail {
  final String shopId;
  final String shopName;
  final String month;
  final int daysInMonth;
  final List<OosProductDayGrid> products;

  OosReportDetail({
    required this.shopId,
    required this.shopName,
    required this.month,
    required this.daysInMonth,
    this.products = const [],
  });

  factory OosReportDetail.fromJson(Map<String, dynamic> json) {
    final list = json['products'] as List? ?? [];
    return OosReportDetail(
      shopId: json['shopId'] ?? '',
      shopName: json['shopName'] ?? '',
      month: json['month'] ?? '',
      daysInMonth: json['daysInMonth'] ?? 30,
      products: list.map((e) => OosProductDayGrid.fromJson(e)).toList(),
    );
  }
}

/// Product x days grid row
class OosProductDayGrid {
  final String barcode;
  final String productName;
  final Map<int, int> daysOos; // day number → stock value (0 or negative)

  OosProductDayGrid({
    required this.barcode,
    required this.productName,
    this.daysOos = const {},
  });

  factory OosProductDayGrid.fromJson(Map<String, dynamic> json) {
    final days = json['days'] as Map<String, dynamic>? ?? {};
    return OosProductDayGrid(
      barcode: json['barcode'] ?? '',
      productName: json['productName'] ?? '',
      daysOos: days.map((k, v) => MapEntry(int.parse(k), v as int)),
    );
  }

  int get oosCount => daysOos.length;
}

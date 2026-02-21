class ZReportParseResult {
  final bool success;
  final String? error;
  final String? rawText;
  final ZReportData? data;
  final Map<String, dynamic>? expectedRanges; // Intelligence: ожидаемые диапазоны

  ZReportParseResult({
    required this.success,
    this.error,
    this.rawText,
    this.data,
    this.expectedRanges,
  });

  factory ZReportParseResult.fromJson(Map<String, dynamic> json) {
    return ZReportParseResult(
      success: json['success'] ?? false,
      error: json['error'],
      rawText: json['rawText'],
      data: json['data'] != null ? ZReportData.fromJson(json['data']) : null,
      expectedRanges: json['expectedRanges'] as Map<String, dynamic>?,
    );
  }
}

class ZReportData {
  final double? totalSum;
  final double? cashSum;
  final int? ofdNotSent;
  final int? resourceKeys; // Ресурс ключей
  final Map<String, String> confidence;

  ZReportData({
    this.totalSum,
    this.cashSum,
    this.ofdNotSent,
    this.resourceKeys,
    this.confidence = const {},
  });

  factory ZReportData.fromJson(Map<String, dynamic> json) {
    return ZReportData(
      totalSum: _toDouble(json['totalSum']),
      cashSum: _toDouble(json['cashSum']),
      ofdNotSent: _toInt(json['ofdNotSent']),
      resourceKeys: _toInt(json['resourceKeys']),
      confidence: Map<String, String>.from(json['confidence'] ?? {}),
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  Map<String, dynamic> toJson() => {
    'totalSum': totalSum,
    'cashSum': cashSum,
    'ofdNotSent': ofdNotSent,
    'resourceKeys': resourceKeys,
  };
}


class ZReportParseResult {
  final bool success;
  final String? error;
  final String? rawText;
  final ZReportData? data;

  ZReportParseResult({
    required this.success,
    this.error,
    this.rawText,
    this.data,
  });

  factory ZReportParseResult.fromJson(Map<String, dynamic> json) {
    return ZReportParseResult(
      success: json['success'] ?? false,
      error: json['error'],
      rawText: json['rawText'],
      data: json['data'] != null ? ZReportData.fromJson(json['data']) : null,
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
      totalSum: json['totalSum']?.toDouble(),
      cashSum: json['cashSum']?.toDouble(),
      ofdNotSent: json['ofdNotSent']?.toInt(),
      resourceKeys: json['resourceKeys']?.toInt(),
      confidence: Map<String, String>.from(json['confidence'] ?? {}),
    );
  }
}


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

class ZReportValidationResult {
  final bool success;
  final String? error;
  final ZReportData? recognized;
  final ValidationData? validation;

  ZReportValidationResult({
    required this.success,
    this.error,
    this.recognized,
    this.validation,
  });

  factory ZReportValidationResult.fromJson(Map<String, dynamic> json) {
    return ZReportValidationResult(
      success: json['success'] ?? false,
      error: json['error'],
      recognized: json['recognized'] != null
          ? ZReportData.fromJson(json['recognized'])
          : null,
      validation: json['validation'] != null
          ? ValidationData.fromJson(json['validation'])
          : null,
    );
  }
}

class ValidationData {
  final bool isValid;
  final List<ValidationError> errors;
  final List<ValidationWarning> warnings;

  ValidationData({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  factory ValidationData.fromJson(Map<String, dynamic> json) {
    return ValidationData(
      isValid: json['isValid'] ?? false,
      errors: (json['errors'] as List?)
              ?.map((e) => ValidationError.fromJson(e))
              .toList() ??
          [],
      warnings: (json['warnings'] as List?)
              ?.map((e) => ValidationWarning.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class ValidationError {
  final String field;
  final dynamic recognized;
  final dynamic entered;
  final String message;

  ValidationError({
    required this.field,
    this.recognized,
    this.entered,
    required this.message,
  });

  factory ValidationError.fromJson(Map<String, dynamic> json) {
    return ValidationError(
      field: json['field'] ?? '',
      recognized: json['recognized'],
      entered: json['entered'],
      message: json['message'] ?? '',
    );
  }
}

class ValidationWarning {
  final String field;
  final String message;

  ValidationWarning({
    required this.field,
    required this.message,
  });

  factory ValidationWarning.fromJson(Map<String, dynamic> json) {
    return ValidationWarning(
      field: json['field'] ?? '',
      message: json['message'] ?? '',
    );
  }
}

class ZReportSample {
  final String id;
  final DateTime createdAt;
  final String shopAddress;
  final String employeeName;
  final Map<String, dynamic> correctData;

  ZReportSample({
    required this.id,
    required this.createdAt,
    required this.shopAddress,
    required this.employeeName,
    required this.correctData,
  });

  factory ZReportSample.fromJson(Map<String, dynamic> json) {
    return ZReportSample(
      id: json['id'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      shopAddress: json['shopAddress'] ?? '',
      employeeName: json['employeeName'] ?? '',
      correctData: Map<String, dynamic>.from(json['correctData'] ?? {}),
    );
  }
}

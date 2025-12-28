import 'dart:convert';

/// Модель регистрации сотрудника
class EmployeeRegistration {
  final String phone; // Ключ для связи с "Лист11"
  final String fullName; // ФИО
  final String passportSeries; // Серия паспорта (4 цифры)
  final String passportNumber; // Номер паспорта (6 цифр)
  final String issuedBy; // Кем выдан
  final String issueDate; // Дата выдачи (ДД.ММ.ГГГГ)
  final String? passportFrontPhotoUrl; // Фото лицевой страницы
  final String? passportRegistrationPhotoUrl; // Фото прописки
  final String? additionalPhotoUrl; // Дополнительное фото
  final bool isVerified; // Верифицирован ли сотрудник
  final DateTime? verifiedAt; // Дата верификации
  final String? verifiedBy; // Кто верифицировал (админ)
  final DateTime createdAt; // Дата создания записи
  final DateTime updatedAt; // Дата последнего обновления

  EmployeeRegistration({
    required this.phone,
    required this.fullName,
    required this.passportSeries,
    required this.passportNumber,
    required this.issuedBy,
    required this.issueDate,
    this.passportFrontPhotoUrl,
    this.passportRegistrationPhotoUrl,
    this.additionalPhotoUrl,
    this.isVerified = false,
    this.verifiedAt,
    this.verifiedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'phone': phone,
    'fullName': fullName,
    'passportSeries': passportSeries,
    'passportNumber': passportNumber,
    'issuedBy': issuedBy,
    'issueDate': issueDate,
    'passportFrontPhotoUrl': passportFrontPhotoUrl,
    'passportRegistrationPhotoUrl': passportRegistrationPhotoUrl,
    'additionalPhotoUrl': additionalPhotoUrl,
    'isVerified': isVerified,
    'verifiedAt': verifiedAt?.toIso8601String(),
    'verifiedBy': verifiedBy,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory EmployeeRegistration.fromJson(Map<String, dynamic> json) {
    return EmployeeRegistration(
      phone: json['phone'] ?? '',
      fullName: json['fullName'] ?? '',
      passportSeries: json['passportSeries'] ?? '',
      passportNumber: json['passportNumber'] ?? '',
      issuedBy: json['issuedBy'] ?? '',
      issueDate: json['issueDate'] ?? '',
      passportFrontPhotoUrl: json['passportFrontPhotoUrl'],
      passportRegistrationPhotoUrl: json['passportRegistrationPhotoUrl'],
      additionalPhotoUrl: json['additionalPhotoUrl'],
      isVerified: json['isVerified'] ?? false,
      verifiedAt: json['verifiedAt'] != null ? DateTime.parse(json['verifiedAt']) : null,
      verifiedBy: json['verifiedBy'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : DateTime.now(),
    );
  }

  EmployeeRegistration copyWith({
    String? phone,
    String? fullName,
    String? passportSeries,
    String? passportNumber,
    String? issuedBy,
    String? issueDate,
    String? passportFrontPhotoUrl,
    String? passportRegistrationPhotoUrl,
    String? additionalPhotoUrl,
    bool? isVerified,
    DateTime? verifiedAt,
    String? verifiedBy,
    DateTime? updatedAt,
  }) {
    return EmployeeRegistration(
      phone: phone ?? this.phone,
      fullName: fullName ?? this.fullName,
      passportSeries: passportSeries ?? this.passportSeries,
      passportNumber: passportNumber ?? this.passportNumber,
      issuedBy: issuedBy ?? this.issuedBy,
      issueDate: issueDate ?? this.issueDate,
      passportFrontPhotoUrl: passportFrontPhotoUrl ?? this.passportFrontPhotoUrl,
      passportRegistrationPhotoUrl: passportRegistrationPhotoUrl ?? this.passportRegistrationPhotoUrl,
      additionalPhotoUrl: additionalPhotoUrl ?? this.additionalPhotoUrl,
      isVerified: isVerified ?? this.isVerified,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}


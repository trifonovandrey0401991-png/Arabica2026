import 'package:flutter/material.dart';

/// Модель поставщика
class Supplier {
  final String id;
  final String name; // Наименование поставщика (обязательное)
  final String? inn; // ИНН поставщика (необязательное)
  final String legalType; // Тип организации: "ООО" или "ИП" (обязательное)
  final List<String> deliveryDays; // Дни недели привоза товара
  final String? phone; // Номер телефона (необязательное)
  final String paymentType; // Тип оплаты: "Нал" или "БезНал" (обязательное)
  final String? createdAt; // Дата создания
  final String? updatedAt; // Дата обновления

  Supplier({
    required this.id,
    required this.name,
    this.inn,
    required this.legalType,
    required this.deliveryDays,
    this.phone,
    required this.paymentType,
    this.createdAt,
    this.updatedAt,
  });

  /// Создать Supplier из JSON
  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      inn: json['inn'],
      legalType: json['legalType'] ?? '',
      deliveryDays: json['deliveryDays'] != null
          ? List<String>.from(json['deliveryDays'])
          : [],
      phone: json['phone'],
      paymentType: json['paymentType'] ?? '',
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
    );
  }

  /// Преобразовать Supplier в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (inn != null) 'inn': inn,
      'legalType': legalType,
      'deliveryDays': deliveryDays,
      if (phone != null) 'phone': phone,
      'paymentType': paymentType,
      if (createdAt != null) 'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }

  /// Создать копию с измененными полями
  Supplier copyWith({
    String? id,
    String? name,
    String? inn,
    String? legalType,
    List<String>? deliveryDays,
    String? phone,
    String? paymentType,
    String? createdAt,
    String? updatedAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      inn: inn ?? this.inn,
      legalType: legalType ?? this.legalType,
      deliveryDays: deliveryDays ?? this.deliveryDays,
      phone: phone ?? this.phone,
      paymentType: paymentType ?? this.paymentType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Валидация обязательных полей
  bool isValid() {
    return name.isNotEmpty &&
        (legalType == 'ООО' || legalType == 'ИП') &&
        (paymentType == 'Нал' || paymentType == 'БезНал');
  }

  /// Валидация ИНН (10 или 12 цифр)
  static bool isValidInn(String? inn) {
    if (inn == null || inn.isEmpty) return true; // Необязательное поле
    final digitsOnly = inn.replaceAll(RegExp(r'[^\d]'), '');
    return digitsOnly.length == 10 || digitsOnly.length == 12;
  }

  /// Валидация телефона (базовая проверка)
  static bool isValidPhone(String? phone) {
    if (phone == null || phone.isEmpty) return true; // Необязательное поле
    final digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
    return digitsOnly.length >= 10 && digitsOnly.length <= 15;
  }
}


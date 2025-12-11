import 'dart:convert';

/// Модель настроек магазина для РКО
class ShopSettings {
  final String shopAddress; // Адрес магазина (ключ)
  final String address; // Фактический адрес для РКО
  final String inn; // ИНН
  final String directorName; // Руководитель организации (например, "ИП Горовой Р. В.")
  final int lastDocumentNumber; // Последний номер документа (1-50000)

  ShopSettings({
    required this.shopAddress,
    required this.address,
    required this.inn,
    required this.directorName,
    this.lastDocumentNumber = 0,
  });

  Map<String, dynamic> toJson() => {
    'shopAddress': shopAddress,
    'address': address,
    'inn': inn,
    'directorName': directorName,
    'lastDocumentNumber': lastDocumentNumber,
  };

  factory ShopSettings.fromJson(Map<String, dynamic> json) {
    return ShopSettings(
      shopAddress: json['shopAddress'] ?? '',
      address: json['address'] ?? '',
      inn: json['inn'] ?? '',
      directorName: json['directorName'] ?? '',
      lastDocumentNumber: json['lastDocumentNumber'] ?? 0,
    );
  }

  ShopSettings copyWith({
    String? address,
    String? inn,
    String? directorName,
    int? lastDocumentNumber,
  }) {
    return ShopSettings(
      shopAddress: shopAddress,
      address: address ?? this.address,
      inn: inn ?? this.inn,
      directorName: directorName ?? this.directorName,
      lastDocumentNumber: lastDocumentNumber ?? this.lastDocumentNumber,
    );
  }

  /// Получить следующий номер документа (1-50000, затем сброс до 1)
  int getNextDocumentNumber() {
    int next = lastDocumentNumber + 1;
    if (next > 50000) {
      next = 1;
    }
    return next;
  }
}






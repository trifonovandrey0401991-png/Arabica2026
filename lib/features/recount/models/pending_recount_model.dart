/// Модель непройденного пересчёта (магазин + смена)
class PendingRecount {
  final String shopAddress;
  final String shiftType; // 'morning' или 'evening'
  final String shiftName; // 'Утренняя смена' или 'Вечерняя смена'

  PendingRecount({
    required this.shopAddress,
    required this.shiftType,
    required this.shiftName,
  });

  /// Уникальный ключ для сравнения (магазин + смена)
  String get uniqueKey => '${shopAddress.toLowerCase().trim()}_$shiftType';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PendingRecount && other.uniqueKey == uniqueKey;
  }

  @override
  int get hashCode => uniqueKey.hashCode;
}

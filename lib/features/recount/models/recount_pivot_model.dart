/// Модели для pivot-таблицы отчётов пересчёта
/// Показывает товары (строки) × магазины (столбцы) с разницей (факт - программа)

/// Строка pivot-таблицы (один товар)
class RecountPivotRow {
  final String productName;
  final String productBarcode;
  final Map<String, int?> shopDifferences; // shopId -> difference (null = не было пересчёта)

  const RecountPivotRow({
    required this.productName,
    required this.productBarcode,
    required this.shopDifferences,
  });

  /// Проверяет есть ли расхождения по товару (хотя бы в одном магазине != 0)
  bool get hasMismatch => shopDifferences.values.any((d) => d != null && d != 0);

  /// Количество магазинов с расхождениями
  int get mismatchCount => shopDifferences.values.where((d) => d != null && d != 0).length;
}

/// Информация о магазине в pivot-таблице
class RecountPivotShop {
  final String shopId;
  final String shopName;
  final String? shopAddress;

  const RecountPivotShop({
    required this.shopId,
    required this.shopName,
    this.shopAddress,
  });
}

/// Полная pivot-таблица за день
class RecountPivotTable {
  final DateTime date;
  final List<RecountPivotShop> shops;
  final List<RecountPivotRow> rows;

  const RecountPivotTable({
    required this.date,
    required this.shops,
    required this.rows,
  });

  /// Список ID магазинов (для построения таблицы)
  List<String> get shopIds => shops.map((s) => s.shopId).toList();

  /// Список названий магазинов
  List<String> get shopNames => shops.map((s) => s.shopName).toList();

  /// Есть ли данные
  bool get isEmpty => rows.isEmpty;
  bool get isNotEmpty => rows.isNotEmpty;

  /// Количество товаров с расхождениями
  int get mismatchProductsCount => rows.where((r) => r.hasMismatch).length;

  /// Общее количество расхождений
  int get totalMismatchCount => rows.fold(0, (sum, r) => sum + r.mismatchCount);

  /// Пустая таблица
  factory RecountPivotTable.empty(DateTime date) => RecountPivotTable(
        date: date,
        shops: [],
        rows: [],
      );
}

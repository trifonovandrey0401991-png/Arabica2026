import 'package:flutter/material.dart';
import '../models/recount_report_model.dart';
import '../../shops/models/shop_model.dart';

/// Страница сводного отчёта по пересчёту (таблица товары x магазины)
class RecountSummaryReportPage extends StatefulWidget {
  final DateTime date;
  final String shiftType;
  final String shiftName;
  final List<RecountReport> reports;
  final List<Shop> allShops;

  const RecountSummaryReportPage({
    super.key,
    required this.date,
    required this.shiftType,
    required this.shiftName,
    required this.reports,
    required this.allShops,
  });

  @override
  State<RecountSummaryReportPage> createState() => _RecountSummaryReportPageState();
}

class _RecountSummaryReportPageState extends State<RecountSummaryReportPage> {
  // Map: shopAddress -> RecountReport
  Map<String, RecountReport> _reportsByShop = {};

  // Уникальные товары из всех отчётов
  List<String> _products = [];

  // Map: productName -> Map<shopAddress, difference>
  Map<String, Map<String, int?>> _pivotData = {};

  // Контроллеры для синхронного скролла
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyScrollController = ScrollController();

  static const _months = [
    '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
  ];

  @override
  void initState() {
    super.initState();
    _loadData();

    // Синхронизация скролла заголовка и тела
    _headerScrollController.addListener(() {
      if (_bodyScrollController.hasClients &&
          _headerScrollController.offset != _bodyScrollController.offset) {
        _bodyScrollController.jumpTo(_headerScrollController.offset);
      }
    });
    _bodyScrollController.addListener(() {
      if (_headerScrollController.hasClients &&
          _bodyScrollController.offset != _headerScrollController.offset) {
        _headerScrollController.jumpTo(_bodyScrollController.offset);
      }
    });
  }

  @override
  void dispose() {
    _headerScrollController.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }

  void _loadData() {
    // Создаём map отчётов по магазинам
    for (final report in widget.reports) {
      _reportsByShop[report.shopAddress.toLowerCase().trim()] = report;
    }

    // Собираем уникальные товары и данные для pivot-таблицы
    final productsSet = <String>{};

    for (final report in widget.reports) {
      for (final answer in report.answers) {
        final productName = answer.question;
        productsSet.add(productName);

        // Инициализируем строку если нужно
        if (!_pivotData.containsKey(productName)) {
          _pivotData[productName] = {};
        }

        // Вычисляем разницу
        int? diff;
        if (answer.isMatching) {
          diff = 0;
        } else if (answer.moreBy != null && answer.moreBy! > 0) {
          diff = answer.moreBy;
        } else if (answer.lessBy != null && answer.lessBy! > 0) {
          diff = -(answer.lessBy!);
        } else if (answer.difference != null) {
          diff = -(answer.difference!);
        }

        _pivotData[productName]![report.shopAddress] = diff;
      }
    }

    _products = productsSet.toList()..sort();
  }

  /// Получить название магазина для вертикального отображения
  String _getShopName(String address) {
    // Убираем "г. " или "г." в начале
    var name = address.replaceFirst(RegExp(r'^г\.?\s*'), '');
    return name.trim();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = '${widget.date.day} ${_months[widget.date.month]}';
    final isMorning = widget.shiftType == 'morning';

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.shiftName} - $dateStr'),
        backgroundColor: isMorning ? Colors.orange.shade700 : Colors.indigo.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isMorning
                ? [Colors.orange.shade50, Colors.white]
                : [Colors.indigo.shade50, Colors.white],
          ),
        ),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Нет товаров для отображения',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (widget.allShops.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Нет магазинов для отображения',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // Фиксированная ширина столбца товара и ячеек
    const double productColumnWidth = 120;
    const double cellWidth = 36;
    const double cellHeight = 32;
    const double headerHeight = 100;

    return Column(
      children: [
        // Легенда
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('0', 'Сходится', Colors.green),
              const SizedBox(width: 12),
              _buildLegendItem('+N', 'Больше', Colors.blue),
              const SizedBox(width: 12),
              _buildLegendItem('-N', 'Меньше', Colors.red),
              const SizedBox(width: 12),
              _buildLegendItem('—', 'Нет данных', Colors.grey),
            ],
          ),
        ),

        // Таблица
        Expanded(
          child: Row(
            children: [
              // Фиксированный столбец товаров
              SizedBox(
                width: productColumnWidth,
                child: Column(
                  children: [
                    // Заголовок "Товар"
                    Container(
                      height: headerHeight,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade100,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade300),
                          right: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      alignment: Alignment.bottomLeft,
                      child: const Text(
                        'Товар',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ),
                    // Список товаров
                    Expanded(
                      child: ListView.builder(
                        itemCount: _products.length,
                        itemBuilder: (context, index) {
                          final product = _products[index];
                          final hasMismatch = _pivotData[product]?.values.any((d) => d != null && d != 0) ?? false;

                          return Container(
                            height: cellHeight,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: index % 2 == 0 ? Colors.white : Colors.grey.shade50,
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade200),
                                right: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              product,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: hasMismatch ? FontWeight.bold : FontWeight.normal,
                                color: hasMismatch ? Colors.red.shade700 : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Прокручиваемая часть с магазинами
              Expanded(
                child: Column(
                  children: [
                    // Заголовки магазинов (горизонтальный скролл)
                    SizedBox(
                      height: headerHeight,
                      child: SingleChildScrollView(
                        controller: _headerScrollController,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: widget.allShops.map((shop) {
                            final hasReport = _reportsByShop.containsKey(shop.address.toLowerCase().trim());
                            return Container(
                              width: cellWidth,
                              height: headerHeight,
                              decoration: BoxDecoration(
                                color: hasReport ? Colors.deepPurple.shade100 : Colors.grey.shade200,
                                border: Border(
                                  bottom: BorderSide(color: Colors.grey.shade300),
                                  right: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                              alignment: Alignment.bottomCenter,
                              padding: const EdgeInsets.only(bottom: 4),
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: SizedBox(
                                  width: headerHeight - 6,
                                  child: Text(
                                    _getShopName(shop.address),
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: hasReport ? Colors.black87 : Colors.grey,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    // Данные (вертикальный + горизонтальный скролл)
                    Expanded(
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          controller: _bodyScrollController,
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            children: _products.asMap().entries.map((entry) {
                              final index = entry.key;
                              final product = entry.value;

                              return Row(
                                children: widget.allShops.map((shop) {
                                  final diff = _pivotData[product]?[shop.address];

                                  return Container(
                                    width: cellWidth,
                                    height: cellHeight,
                                    decoration: BoxDecoration(
                                      color: index % 2 == 0 ? Colors.white : Colors.grey.shade50,
                                      border: Border(
                                        bottom: BorderSide(color: Colors.grey.shade200),
                                        right: BorderSide(color: Colors.grey.shade200),
                                      ),
                                    ),
                                    child: _buildDifferenceCell(diff),
                                  );
                                }).toList(),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String symbol, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            symbol,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildDifferenceCell(int? difference) {
    if (difference == null) {
      return const Center(
        child: Text('—', style: TextStyle(color: Colors.grey, fontSize: 10)),
      );
    }
    if (difference == 0) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.2),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text(
            '0',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 9),
          ),
        ),
      );
    }

    final isPositive = difference > 0;
    final color = isPositive ? Colors.blue : Colors.red;
    final sign = isPositive ? '+' : '';

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          '$sign$difference',
          style: TextStyle(color: color.shade700, fontWeight: FontWeight.bold, fontSize: 9),
        ),
      ),
    );
  }
}

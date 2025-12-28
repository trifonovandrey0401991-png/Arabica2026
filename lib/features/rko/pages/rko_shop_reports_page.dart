import 'package:flutter/material.dart';
import '../shops/models/shop_model.dart';
import 'services/rko_reports_service.dart';
import 'rko_pdf_viewer_page.dart';

/// Страница отчетов по магазинам
class RKOShopReportsPage extends StatefulWidget {
  const RKOShopReportsPage({super.key});

  @override
  State<RKOShopReportsPage> createState() => _RKOShopReportsPageState();
}

class _RKOShopReportsPageState extends State<RKOShopReportsPage> {
  List<Shop> _shops = [];
  Shop? _selectedShop;
  List<dynamic> _currentMonthRKOs = [];
  List<dynamic> _months = [];
  bool _isLoading = true;
  bool _showAllTime = false;

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final shops = await Shop.loadShopsFromGoogleSheets();
      setState(() {
        _shops = shops;
        _isLoading = false;
      });
    } catch (e) {
      print('Ошибка загрузки магазинов: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadShopRKOs(String shopAddress) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await RKOReportsService.getShopRKOs(shopAddress);
      if (data != null) {
        setState(() {
          _currentMonthRKOs = data['currentMonth'] ?? [];
          _months = data['months'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Ошибка загрузки РКО магазина: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedShop == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Отчет по магазину'),
          backgroundColor: const Color(0xFF004D40),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _shops.length,
                itemBuilder: (context, index) {
                  final shop = _shops[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Icon(shop.icon, color: const Color(0xFF004D40)),
                      title: Text(
                        shop.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(shop.address),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        setState(() {
                          _selectedShop = shop;
                        });
                        _loadShopRKOs(shop.address);
                      },
                    ),
                  );
                },
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('РКО: ${_selectedShop!.name}'),
        backgroundColor: const Color(0xFF004D40),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _selectedShop = null;
              _currentMonthRKOs = [];
              _months = [];
            });
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadShopRKOs(_selectedShop!.address),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(8),
              children: [
                // РКО за текущий месяц
                if (_currentMonthRKOs.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'Текущий месяц',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ..._currentMonthRKOs.map((rko) => _buildRKOItem(rko)),
                ],
                
                // Папка "За все время"
                if (_months.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.blue.shade50,
                    child: ListTile(
                      leading: const Icon(Icons.folder, color: Colors.blue),
                      title: const Text(
                        'За все время',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: Icon(
                        _showAllTime ? Icons.expand_less : Icons.expand_more,
                      ),
                      onTap: () {
                        setState(() {
                          _showAllTime = !_showAllTime;
                        });
                      },
                    ),
                  ),
                  
                  if (_showAllTime) ...[
                    ..._months.map((monthData) => _buildMonthFolder(monthData)),
                  ],
                ],
                
                if (_currentMonthRKOs.isEmpty && _months.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text('РКО не найдены'),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildRKOItem(dynamic rko) {
    final fileName = rko['fileName'] ?? '';
    final employeeName = rko['employeeName'] ?? '';
    final date = rko['date'] ?? '';
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(
          fileName.toLowerCase().endsWith('.docx') 
            ? Icons.description 
            : Icons.picture_as_pdf,
          color: fileName.toLowerCase().endsWith('.docx') 
            ? Colors.blue 
            : Colors.red,
        ),
        title: Text(employeeName),
        subtitle: Text('Дата: ${date.substring(0, 10)}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RKOPDFViewerPage(fileName: fileName),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMonthFolder(dynamic monthData) {
    final monthKey = monthData['monthKey'] ?? '';
    final items = monthData['items'] ?? [];
    
    return Padding(
      padding: const EdgeInsets.only(left: 16.0),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: Colors.grey.shade100,
        child: ExpansionTile(
          leading: const Icon(Icons.folder, color: Colors.orange),
          title: Text(_formatMonth(monthKey)),
          children: items.map<Widget>((rko) => _buildRKOItem(rko)).toList(),
        ),
      ),
    );
  }

  String _formatMonth(String monthKey) {
    // monthKey в формате YYYY-MM
    final parts = monthKey.split('-');
    if (parts.length == 2) {
      final year = parts[0];
      final month = int.tryParse(parts[1]) ?? 0;
      const monthNames = [
        'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
        'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
      ];
      if (month >= 1 && month <= 12) {
        return '${monthNames[month - 1]} $year';
      }
    }
    return monthKey;
  }
}




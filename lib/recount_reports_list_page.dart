import 'package:flutter/material.dart';
import 'recount_report_model.dart';
import 'recount_service.dart';
import 'recount_report_view_page.dart';

/// Страница со списком отчетов по пересчету
class RecountReportsListPage extends StatefulWidget {
  const RecountReportsListPage({super.key});

  @override
  State<RecountReportsListPage> createState() => _RecountReportsListPageState();
}

class _RecountReportsListPageState extends State<RecountReportsListPage> {
  late Future<List<RecountReport>> _reportsFuture;
  String? _selectedShop;
  String? _selectedEmployee;
  DateTime? _selectedDate;
  List<RecountReport> _allReports = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _reportsFuture = RecountService.getReports();
    });
    _allReports = await _reportsFuture;
    setState(() {});
  }

  List<RecountReport> get _filteredReports {
    var reports = _allReports;

    if (_selectedShop != null) {
      reports = reports.where((r) => r.shopAddress == _selectedShop).toList();
    }

    if (_selectedEmployee != null) {
      reports = reports.where((r) => r.employeeName == _selectedEmployee).toList();
    }

    if (_selectedDate != null) {
      reports = reports.where((r) {
        return r.completedAt.year == _selectedDate!.year &&
               r.completedAt.month == _selectedDate!.month &&
               r.completedAt.day == _selectedDate!.day;
      }).toList();
    }

    // Сортируем по дате (новые сначала)
    reports.sort((a, b) => b.completedAt.compareTo(a.completedAt));

    return reports;
  }

  List<String> get _uniqueShops {
    return _allReports.map((r) => r.shopAddress).toSet().toList()..sort();
  }

  List<String> get _uniqueEmployees {
    return _allReports.map((r) => r.employeeName).toSet().toList()..sort();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчеты по пересчету'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: Column(
          children: [
            // Фильтры
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white.withOpacity(0.95),
              child: Column(
                children: [
                  // Магазин
                  DropdownButtonFormField<String>(
                    value: _selectedShop,
                    decoration: const InputDecoration(
                      labelText: 'Магазин',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Все магазины'),
                      ),
                      ..._uniqueShops.map((shop) => DropdownMenuItem<String>(
                        value: shop,
                        child: Text(shop),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedShop = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  // Сотрудник
                  DropdownButtonFormField<String>(
                    value: _selectedEmployee,
                    decoration: const InputDecoration(
                      labelText: 'Сотрудник',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Все сотрудники'),
                      ),
                      ..._uniqueEmployees.map((employee) => DropdownMenuItem<String>(
                        value: employee,
                        child: Text(employee),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedEmployee = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  // Дата
                  InkWell(
                    onTap: () => _selectDate(context),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Дата',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        _selectedDate != null
                            ? '${_selectedDate!.day}.${_selectedDate!.month}.${_selectedDate!.year}'
                            : 'Все даты',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Сброс фильтров
                  if (_selectedShop != null || _selectedEmployee != null || _selectedDate != null)
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedShop = null;
                          _selectedEmployee = null;
                          _selectedDate = null;
                        });
                      },
                      icon: const Icon(Icons.clear),
                      label: const Text('Сбросить фильтры'),
                    ),
                ],
              ),
            ),
            // Список отчетов
            Expanded(
              child: FutureBuilder<List<RecountReport>>(
                future: _reportsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(
                            'Ошибка загрузки: ${snapshot.error}',
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadData,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    );
                  }

                  final filteredReports = _filteredReports;

                  if (filteredReports.isEmpty) {
                    return const Center(
                      child: Text(
                        'Отчеты не найдены',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredReports.length,
                      itemBuilder: (context, index) {
                        final report = filteredReports[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: report.isRated
                                  ? Colors.green
                                  : Colors.orange,
                              child: Icon(
                                report.isRated ? Icons.check : Icons.pending,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              '${report.shopAddress}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Сотрудник: ${report.employeeName}'),
                                Text('Время: ${report.formattedDuration}'),
                                Text(
                                  'Дата: ${report.completedAt.day}.${report.completedAt.month}.${report.completedAt.year} '
                                  '${report.completedAt.hour.toString().padLeft(2, '0')}:${report.completedAt.minute.toString().padLeft(2, '0')}',
                                ),
                                if (report.isRated)
                                  Text(
                                    'Оценка: ${report.adminRating}/10',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RecountReportViewPage(
                                    report: report,
                                    onReportUpdated: () {
                                      _loadData();
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}













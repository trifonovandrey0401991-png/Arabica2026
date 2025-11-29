import 'package:flutter/material.dart';
import 'shift_report_model.dart';
import 'shift_report_view_page.dart';

/// Страница со списком отчетов по пересменкам
class ShiftReportsListPage extends StatefulWidget {
  const ShiftReportsListPage({super.key});

  @override
  State<ShiftReportsListPage> createState() => _ShiftReportsListPageState();
}

class _ShiftReportsListPageState extends State<ShiftReportsListPage> {
  late Future<List<String>> _shopsFuture;
  String? _selectedShop;
  String? _selectedEmployee;
  DateTime? _selectedDate;
  List<ShiftReport> _allReports = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _shopsFuture = ShiftReport.getUniqueShopAddresses();
    });
    _allReports = await ShiftReport.loadAllReports();
    setState(() {});
  }

  List<ShiftReport> get _filteredReports {
    var reports = _allReports;

    if (_selectedShop != null) {
      reports = reports.where((r) => r.shopAddress == _selectedShop).toList();
    }

    if (_selectedEmployee != null) {
      reports = reports.where((r) => r.employeeName == _selectedEmployee).toList();
    }

    if (_selectedDate != null) {
      reports = reports.where((r) {
        return r.createdAt.year == _selectedDate!.year &&
               r.createdAt.month == _selectedDate!.month &&
               r.createdAt.day == _selectedDate!.day;
      }).toList();
    }

    return reports;
  }

  List<String> get _uniqueEmployees {
    return _allReports.map((r) => r.employeeName).toSet().toList()..sort();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
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
        title: const Text('Отчеты по пересменкам'),
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
              color: Colors.white.withOpacity(0.1),
              child: Column(
                children: [
                  // Фильтр по магазину
                  FutureBuilder<List<String>>(
                    future: _shopsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return DropdownButtonFormField<String>(
                          value: _selectedShop,
                          decoration: InputDecoration(
                            labelText: 'Магазин',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Все магазины'),
                            ),
                            ...snapshot.data!.map((shop) => DropdownMenuItem(
                              value: shop,
                              child: Text(shop),
                            )),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedShop = value;
                            });
                          },
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                  const SizedBox(height: 12),
                  // Фильтр по сотруднику
                  DropdownButtonFormField<String>(
                    value: _selectedEmployee,
                    decoration: InputDecoration(
                      labelText: 'Сотрудник',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Все сотрудники'),
                      ),
                      ..._uniqueEmployees.map((emp) => DropdownMenuItem(
                        value: emp,
                        child: Text(emp),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedEmployee = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  // Фильтр по дате
                  InkWell(
                    onTap: () => _selectDate(context),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Дата',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        _selectedDate == null
                            ? 'Все даты'
                            : '${_selectedDate!.day}.${_selectedDate!.month}.${_selectedDate!.year}',
                      ),
                    ),
                  ),
                  if (_selectedShop != null || _selectedEmployee != null || _selectedDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedShop = null;
                            _selectedEmployee = null;
                            _selectedDate = null;
                          });
                        },
                        child: const Text('Сбросить фильтры'),
                      ),
                    ),
                ],
              ),
            ),

            // Список отчетов
            Expanded(
              child: _filteredReports.isEmpty
                  ? const Center(
                      child: Text(
                        'Отчеты не найдены',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredReports.length,
                      itemBuilder: (context, index) {
                        final report = _filteredReports[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF004D40),
                              child: const Icon(Icons.receipt_long, color: Colors.white),
                            ),
                            title: Text(
                              report.shopAddress,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Сотрудник: ${report.employeeName}'),
                                Text(
                                  '${report.createdAt.day}.${report.createdAt.month}.${report.createdAt.year} '
                                  '${report.createdAt.hour}:${report.createdAt.minute.toString().padLeft(2, '0')}',
                                ),
                                Text('Вопросов: ${report.answers.length}'),
                              ],
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ShiftReportViewPage(
                                    report: report,
                                  ),
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


import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'employees_page.dart';
import 'rko_reports_service.dart';
import 'rko_pdf_viewer_page.dart';

/// Страница отчетов по сотрудникам
class RKOEmployeeReportsPage extends StatefulWidget {
  const RKOEmployeeReportsPage({super.key});

  @override
  State<RKOEmployeeReportsPage> createState() => _RKOEmployeeReportsPageState();
}

class _RKOEmployeeReportsPageState extends State<RKOEmployeeReportsPage> {
  List<Employee> _employees = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final employees = await EmployeesPage.loadEmployeesForNotifications();
      setState(() {
        _employees = employees;
        _isLoading = false;
      });
    } catch (e) {
      print('Ошибка загрузки сотрудников: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчет по сотруднику'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEmployees,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск сотрудника...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim().toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _employees.isEmpty
                    ? const Center(child: Text('Сотрудники не найдены'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _employees.length,
                        itemBuilder: (context, index) {
                          final employee = _employees[index];
                          
                          // Фильтрация по поисковому запросу
                          if (_searchQuery.isNotEmpty) {
                            final name = employee.name.toLowerCase();
                            if (!name.contains(_searchQuery)) {
                              return const SizedBox.shrink();
                            }
                          }

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const Icon(
                                Icons.person,
                                color: Color(0xFF004D40),
                              ),
                              title: Text(
                                employee.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(employee.position ?? ''),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => RKOEmployeeDetailPage(
                                      employeeName: employee.name,
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
    );
  }
}

/// Страница детального просмотра РКО сотрудника
class RKOEmployeeDetailPage extends StatefulWidget {
  final String employeeName;

  const RKOEmployeeDetailPage({
    super.key,
    required this.employeeName,
  });

  @override
  State<RKOEmployeeDetailPage> createState() => _RKOEmployeeDetailPageState();
}

class _RKOEmployeeDetailPageState extends State<RKOEmployeeDetailPage> {
  List<dynamic> _latest = [];
  List<dynamic> _months = [];
  bool _isLoading = true;
  bool _showAllTime = false;

  @override
  void initState() {
    super.initState();
    _loadRKOs();
  }

  Future<void> _loadRKOs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await RKOReportsService.getEmployeeRKOs(widget.employeeName);
      if (data != null) {
        setState(() {
          _latest = data['latest'] ?? [];
          _months = data['months'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Ошибка загрузки РКО: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('РКО: ${widget.employeeName}'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRKOs,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(8),
              children: [
                // Последние 25 РКО
                if (_latest.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'Последние РКО',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ..._latest.map((rko) => _buildRKOItem(rko)),
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
                
                if (_latest.isEmpty && _months.isEmpty)
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
    final date = rko['date'] ?? '';
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
        title: Text(fileName),
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


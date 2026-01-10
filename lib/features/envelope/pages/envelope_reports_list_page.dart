import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../models/envelope_report_model.dart';
import '../services/envelope_report_service.dart';
import 'envelope_report_view_page.dart';

/// Страница со списком отчетов по конвертам
class EnvelopeReportsListPage extends StatefulWidget {
  const EnvelopeReportsListPage({super.key});

  @override
  State<EnvelopeReportsListPage> createState() => _EnvelopeReportsListPageState();
}

class _EnvelopeReportsListPageState extends State<EnvelopeReportsListPage> {
  String? _selectedShop;
  String? _selectedEmployee;
  DateTime? _selectedDate;
  List<EnvelopeReport> _allReports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final reports = await EnvelopeReportService.getReports();
      // Сортируем по дате (новые сверху)
      reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() {
        _allReports = reports;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки отчетов', e);
      setState(() => _isLoading = false);
    }
  }

  List<EnvelopeReport> get _filteredReports {
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
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
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
        title: const Text('Отчеты (Конверты)'),
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
                  DropdownButtonFormField<String>(
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
                      ..._uniqueShops.map((shop) => DropdownMenuItem(
                        value: shop,
                        child: Text(shop, overflow: TextOverflow.ellipsis),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedShop = value;
                      });
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
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _filteredReports.isEmpty
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
                            return _buildReportCard(report);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(EnvelopeReport report) {
    final isExpired = report.isExpired;
    final isConfirmed = report.status == 'confirmed';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isConfirmed
              ? Colors.green
              : isExpired
                  ? Colors.red
                  : const Color(0xFF004D40),
          child: Icon(
            isConfirmed ? Icons.check : Icons.mail,
            color: Colors.white,
          ),
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
              '${report.createdAt.hour}:${report.createdAt.minute.toString().padLeft(2, '0')} '
              '• ${report.shiftTypeText}',
            ),
            Row(
              children: [
                Text(
                  'Итого: ${report.totalEnvelopeAmount.toStringAsFixed(0)} ₽',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF004D40),
                  ),
                ),
                const SizedBox(width: 8),
                if (isConfirmed)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 4),
                      const Text(
                        'Подтвержден',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  )
                else if (isExpired)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning, color: Colors.red, size: 16),
                      const SizedBox(width: 4),
                      const Text(
                        'Просрочен',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EnvelopeReportViewPage(report: report),
            ),
          ).then((_) => _loadData());
        },
      ),
    );
  }
}

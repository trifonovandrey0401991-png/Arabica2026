import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../models/envelope_report_model.dart';
import '../models/pending_envelope_report_model.dart';
import '../services/envelope_report_service.dart';
import 'envelope_report_view_page.dart';

/// Страница со списком отчетов по конвертам
class EnvelopeReportsListPage extends StatefulWidget {
  const EnvelopeReportsListPage({super.key});

  @override
  State<EnvelopeReportsListPage> createState() => _EnvelopeReportsListPageState();
}

class _EnvelopeReportsListPageState extends State<EnvelopeReportsListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedShop;
  String? _selectedEmployee;
  DateTime? _selectedDate;
  List<EnvelopeReport> _allReports = [];
  List<PendingEnvelopeReport> _pendingReports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final reports = await EnvelopeReportService.getReports();
      final pendingReports = await EnvelopeReportService.getPendingReports();
      // Сортируем по дате (новые сверху)
      reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      pendingReports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() {
        _allReports = reports;
        _pendingReports = pendingReports;
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

  // Вкладка 1: В Очереди (pending отчеты из автоматизации)
  List<PendingEnvelopeReport> get _queueReports {
    var reports = _pendingReports.where((r) => r.status == 'pending').toList();

    // Применяем фильтры
    if (_selectedShop != null) {
      reports = reports.where((r) => r.shopAddress == _selectedShop).toList();
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

  // Вкладка 2: Не Сданы (failed отчеты из автоматизации)
  List<PendingEnvelopeReport> get _notSubmittedReports {
    var reports = _pendingReports.where((r) => r.status == 'failed').toList();

    // Применяем фильтры
    if (_selectedShop != null) {
      reports = reports.where((r) => r.shopAddress == _selectedShop).toList();
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

  // Вкладка 3: Ожидают (все pending)
  List<EnvelopeReport> get _awaitingReports {
    return _filteredReports.where((r) => r.status == 'pending').toList();
  }

  // Вкладка 4: Подтверждены
  List<EnvelopeReport> get _confirmedReports {
    return _filteredReports.where((r) => r.status == 'confirmed').toList();
  }

  // Вкладка 5: Отклонены (просроченные)
  List<EnvelopeReport> get _rejectedReports {
    return _filteredReports.where((r) => r.isExpired).toList();
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
            // Tab buttons (2 rows)
            Container(
              color: Colors.white.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                children: [
                  // Первый ряд
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(child: _buildTabButton(0, 'В Очереди', _queueReports.length)),
                      Expanded(child: _buildTabButton(1, 'Не Сданы', _notSubmittedReports.length)),
                      Expanded(child: _buildTabButton(2, 'Ожидают', _awaitingReports.length)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Второй ряд
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(child: _buildTabButton(3, 'Подтверждены', _confirmedReports.length)),
                      Expanded(child: _buildTabButton(4, 'Отклонены', _rejectedReports.length)),
                    ],
                  ),
                ],
              ),
            ),

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

            // TabBarView с отчетами
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildPendingReportsList(_queueReports, 'В очереди отчетов нет'),
                        _buildPendingReportsList(_notSubmittedReports, 'Несданных отчетов нет'),
                        _buildReportsList(_awaitingReports, 'Ожидающих отчетов нет'),
                        _buildReportsList(_confirmedReports, 'Подтвержденных отчетов нет'),
                        _buildReportsList(_rejectedReports, 'Отклоненных отчетов нет'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String label, int count) {
    final isSelected = _tabController.index == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            _tabController.animateTo(index);
          });
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? Colors.white : Colors.white.withOpacity(0.2),
          foregroundColor: isSelected ? const Color(0xFF004D40) : Colors.white,
          elevation: isSelected ? 4 : 0,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF004D40) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF004D40),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReportsList(List<EnvelopeReport> reports, String emptyMessage) {
    if (reports.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final report = reports[index];
        return _buildReportCard(report);
      },
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
                  'Итого: ${report.totalEnvelopeAmount.toStringAsFixed(0)} руб',
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

  Widget _buildPendingReportCard(PendingEnvelopeReport report) {
    final isFailed = report.status == 'failed';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isFailed ? Colors.red : Colors.orange,
          child: Icon(
            isFailed ? Icons.cancel : Icons.access_time,
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
            Text('Смена: ${report.shiftTypeText}'),
            Text(
              'Дата: ${report.date} • Дедлайн: ${report.deadline}',
            ),
            Row(
              children: [
                Icon(
                  isFailed ? Icons.warning : Icons.schedule,
                  color: isFailed ? Colors.red : Colors.orange,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  report.statusText,
                  style: TextStyle(
                    color: isFailed ? Colors.red : Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingReportsList(List<PendingEnvelopeReport> reports, String emptyMessage) {
    if (reports.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final report = reports[index];
        return _buildPendingReportCard(report);
      },
    );
  }
}

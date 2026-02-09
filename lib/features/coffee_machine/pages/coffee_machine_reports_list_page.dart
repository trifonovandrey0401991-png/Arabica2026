import 'package:flutter/material.dart';
import '../models/coffee_machine_report_model.dart';
import '../models/pending_coffee_machine_report_model.dart';
import '../services/coffee_machine_report_service.dart';
import 'coffee_machine_report_view_page.dart';

/// Список отчётов по счётчикам кофемашин (5 вкладок)
class CoffeeMachineReportsListPage extends StatefulWidget {
  const CoffeeMachineReportsListPage({super.key});

  @override
  State<CoffeeMachineReportsListPage> createState() => _CoffeeMachineReportsListPageState();
}

class _CoffeeMachineReportsListPageState extends State<CoffeeMachineReportsListPage>
    with SingleTickerProviderStateMixin {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  late TabController _tabController;
  int _selectedTab = 0;

  bool _isLoading = true;
  List<CoffeeMachineReport> _allReports = [];
  List<PendingCoffeeMachineReport> _pendingReports = [];
  List<PendingCoffeeMachineReport> _failedReports = [];

  // Фильтры
  String? _selectedShop;
  String? _selectedEmployee;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() => _selectedTab = _tabController.index);
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
      final results = await Future.wait([
        CoffeeMachineReportService.getReportsForCurrentUser(),
        CoffeeMachineReportService.getPendingReports(),
        CoffeeMachineReportService.getFailedReports(),
      ]);

      setState(() {
        _allReports = results[0] as List<CoffeeMachineReport>;
        _pendingReports = results[1] as List<PendingCoffeeMachineReport>;
        _failedReports = results[2] as List<PendingCoffeeMachineReport>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<CoffeeMachineReport> _filterReports(String status) {
    var reports = _allReports.where((r) => r.status == status).toList();
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
    reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return reports;
  }

  List<PendingCoffeeMachineReport> _filterPending(String status) {
    var reports = status == 'pending' ? _pendingReports : _failedReports;
    if (_selectedShop != null) {
      reports = reports.where((r) => r.shopAddress == _selectedShop).toList();
    }
    return reports;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildTabs(),
              _buildFilters(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: _gold))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPendingList('pending'),
                          _buildPendingList('failed'),
                          _buildReportsList('pending'),
                          _buildReportsList('confirmed'),
                          _buildReportsList('rejected'),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const Icon(Icons.coffee_outlined, color: _gold, size: 22),
          const SizedBox(width: 8),
          const Text(
            'Счётчик кофемашин',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final tabNames = ['В очереди', 'Не сданы', 'Ожидают', 'Подтверждены', 'Отклонены'];
    final counts = [
      _filterPending('pending').length,
      _filterPending('failed').length,
      _filterReports('pending').length,
      _filterReports('confirmed').length,
      _filterReports('rejected').length,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildTabButton(0, tabNames[0], counts[0])),
              Expanded(child: _buildTabButton(1, tabNames[1], counts[1])),
              Expanded(child: _buildTabButton(2, tabNames[2], counts[2])),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildTabButton(3, tabNames[3], counts[3])),
              Expanded(child: _buildTabButton(4, tabNames[4], counts[4])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, int count) {
    final isSelected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTab = index;
            _tabController.animateTo(index);
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _gold.withOpacity(0.2) : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? _gold.withOpacity(0.5) : Colors.white.withOpacity(0.1),
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
                    fontSize: 12,
                    color: isSelected ? _gold : Colors.white.withOpacity(0.6),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? _gold : Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: isSelected ? _night : Colors.white.withOpacity(0.7),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final shops = _allReports.map((r) => r.shopAddress).toSet().toList()..sort();
    final employees = _allReports.map((r) => r.employeeName).toSet().toList()..sort();
    final hasFilter = _selectedShop != null || _selectedEmployee != null || _selectedDate != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Магазин
          Expanded(
            child: _buildFilterDropdown<String>(
              value: _selectedShop,
              hint: 'Магазин',
              items: shops,
              onChanged: (v) => setState(() => _selectedShop = v),
            ),
          ),
          const SizedBox(width: 8),
          // Сотрудник
          Expanded(
            child: _buildFilterDropdown<String>(
              value: _selectedEmployee,
              hint: 'Сотрудник',
              items: employees,
              onChanged: (v) => setState(() => _selectedEmployee = v),
            ),
          ),
          const SizedBox(width: 8),
          // Дата
          GestureDetector(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _selectedDate ?? DateTime.now(),
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
              );
              if (date != null) setState(() => _selectedDate = date);
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.calendar_today,
                color: _selectedDate != null ? _gold : Colors.white54,
                size: 18,
              ),
            ),
          ),
          // Сброс
          if (hasFilter) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() {
                _selectedShop = null;
                _selectedEmployee = null;
                _selectedDate = null;
              }),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close, color: Colors.red, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    T? value,
    required String hint,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
          isExpanded: true,
          dropdownColor: _emeraldDark,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          icon: Icon(Icons.arrow_drop_down, color: Colors.white.withOpacity(0.4)),
          items: [
            DropdownMenuItem<T>(value: null, child: Text('Все', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
            ...items.map((item) => DropdownMenuItem<T>(
              value: item,
              child: Text(
                item.toString(),
                overflow: TextOverflow.ellipsis,
              ),
            )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildPendingList(String status) {
    final reports = _filterPending(status);
    if (reports.isEmpty) return _buildEmpty(status == 'pending' ? 'Нет ожидающих' : 'Нет несданных');

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _gold,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: reports.length,
        itemBuilder: (_, i) => _buildPendingCard(reports[i]),
      ),
    );
  }

  Widget _buildReportsList(String status) {
    final reports = _filterReports(status);
    if (reports.isEmpty) return _buildEmpty('Нет отчётов');

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _gold,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: reports.length,
        itemBuilder: (_, i) => _buildReportCard(reports[i]),
      ),
    );
  }

  Widget _buildEmpty(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.coffee_outlined, size: 48, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildPendingCard(PendingCoffeeMachineReport report) {
    final isFailed = report.status == 'failed';
    final statusColor = isFailed ? Colors.red : Colors.orange;
    final icon = isFailed ? Icons.close : Icons.hourglass_empty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.shopAddress,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${report.shiftTypeText} / ${report.date}',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    report.statusText,
                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(CoffeeMachineReport report) {
    Color statusColor;
    IconData icon;
    switch (report.status) {
      case 'confirmed':
        statusColor = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'rejected':
        statusColor = Colors.red;
        icon = Icons.cancel;
        break;
      default:
        statusColor = _gold;
        icon = Icons.mail_outline;
    }

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CoffeeMachineReportViewPage(report: report)),
        );
        _loadData();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: statusColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.shopAddress,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    report.employeeName,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${report.shiftTypeText} / ${report.date}',
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Сумма: ${report.sumOfMachines}',
                        style: TextStyle(color: _gold, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      if (report.hasDiscrepancy) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Расхождение: ${report.discrepancyAmount}',
                            style: const TextStyle(color: Colors.orange, fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
          ],
        ),
      ),
    );
  }
}

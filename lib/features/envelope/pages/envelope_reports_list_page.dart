import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../models/envelope_report_model.dart';
import '../models/pending_envelope_report_model.dart';
import '../services/envelope_report_service.dart';
import '../../employees/services/user_role_service.dart';
import '../../employees/models/user_role_model.dart';
import 'envelope_report_view_page.dart';

/// Страница со списком отчетов по конвертам
class EnvelopeReportsListPage extends StatefulWidget {
  const EnvelopeReportsListPage({super.key});

  @override
  State<EnvelopeReportsListPage> createState() => _EnvelopeReportsListPageState();
}

class _EnvelopeReportsListPageState extends State<EnvelopeReportsListPage>
    with SingleTickerProviderStateMixin {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  late TabController _tabController;
  String? _selectedShop;
  String? _selectedEmployee;
  DateTime? _selectedDate;
  List<EnvelopeReport> _allReports = [];
  List<PendingEnvelopeReport> _pendingReports = [];
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _detectRole();
    _loadData();
  }

  Future<void> _detectRole() async {
    final roleData = await UserRoleService.loadUserRole();
    if (roleData != null && mounted) {
      setState(() {
        _isAdmin = roleData.role == UserRole.admin ||
                   roleData.role == UserRole.developer;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final reports = await EnvelopeReportService.getReportsForCurrentUser();
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
    return _allReports.map((r) => r.shopAddress).where((a) => a.trim().isNotEmpty).toSet().toList()..sort();
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
      backgroundColor: _night,
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
              // Custom AppBar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Отчеты (Конверты)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadData,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // Tab buttons (2 rows)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                ),
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                ),
                child: Column(
                  children: [
                    // Фильтр по магазину
                    _buildDarkDropdown<String>(
                      value: _selectedShop,
                      hint: 'Все магазины',
                      icon: Icons.store,
                      items: _uniqueShops.map((shop) => DropdownMenuItem(
                        value: shop,
                        child: Text(shop, overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (value) {
                        setState(() => _selectedShop = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    // Фильтр по сотруднику
                    _buildDarkDropdown<String>(
                      value: _selectedEmployee,
                      hint: 'Все сотрудники',
                      icon: Icons.person,
                      items: _uniqueEmployees.map((emp) => DropdownMenuItem(
                        value: emp,
                        child: Text(emp),
                      )).toList(),
                      onChanged: (value) {
                        setState(() => _selectedEmployee = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    // Фильтр по дате + кнопка сброса
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _selectDate(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 18, color: _gold),
                                  const SizedBox(width: 8),
                                  Text(
                                    _selectedDate == null
                                        ? 'Все даты'
                                        : '${_selectedDate!.day}.${_selectedDate!.month}.${_selectedDate!.year}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_selectedShop != null || _selectedEmployee != null || _selectedDate != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedShop = null;
                                _selectedEmployee = null;
                                _selectedDate = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red.withOpacity(0.3)),
                              ),
                              child: const Icon(Icons.clear, color: Colors.red, size: 18),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // TabBarView с отчетами
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: _gold))
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
      ),
    );
  }

  Widget _buildDarkDropdown<T>({
    required T? value,
    required String hint,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: _emeraldDark,
          icon: Icon(Icons.arrow_drop_down, color: _gold),
          hint: Row(
            children: [
              Icon(icon, size: 18, color: _gold),
              const SizedBox(width: 8),
              Text(hint, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
            ],
          ),
          selectedItemBuilder: (context) => [
            ...items.map((item) => Row(
              children: [
                Icon(icon, size: 18, color: _gold),
                const SizedBox(width: 8),
                Expanded(
                  child: DefaultTextStyle(
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                    child: item.child,
                  ),
                ),
              ],
            )),
          ],
          items: [
            DropdownMenuItem<T>(
              value: null,
              child: Text(hint, style: TextStyle(color: Colors.white.withOpacity(0.5))),
            ),
            ...items,
          ],
          onChanged: onChanged,
          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String label, int count) {
    final isSelected = _tabController.index == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: () {
          setState(() {
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

  Widget _buildReportsList(List<EnvelopeReport> reports, String emptyMessage) {
    if (reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.mail_outline, size: 40, color: Colors.white.withOpacity(0.3)),
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _gold,
      backgroundColor: _emeraldDark,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        itemBuilder: (context, index) {
          final report = reports[index];
          return _buildReportCard(report);
        },
      ),
    );
  }

  Widget _buildReportCard(EnvelopeReport report) {
    final isExpired = report.isExpired;
    final isConfirmed = report.status == 'confirmed';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EnvelopeReportViewPage(report: report, isAdmin: _isAdmin),
              ),
            ).then((_) => _loadData());
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isConfirmed
                        ? Colors.green.withOpacity(0.2)
                        : isExpired
                            ? Colors.red.withOpacity(0.2)
                            : _emerald,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isConfirmed ? Icons.check : Icons.mail,
                    color: isConfirmed
                        ? Colors.green
                        : isExpired
                            ? Colors.red
                            : Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.shopAddress,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Сотрудник: ${report.employeeName}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                      Text(
                        '${report.createdAt.day}.${report.createdAt.month}.${report.createdAt.year} '
                        '${report.createdAt.hour}:${report.createdAt.minute.toString().padLeft(2, '0')} '
                        '• ${report.shiftTypeText}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            'Итого: ${report.totalEnvelopeAmount.toStringAsFixed(0)} руб',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _gold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isConfirmed)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle, color: Colors.green, size: 14),
                                const SizedBox(width: 4),
                                const Text(
                                  'Подтвержден',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            )
                          else if (isExpired)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning, color: Colors.red, size: 14),
                                const SizedBox(width: 4),
                                const Text(
                                  'Просрочен',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingReportCard(PendingEnvelopeReport report) {
    final isFailed = report.status == 'failed';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFailed ? Colors.red.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isFailed ? Colors.red.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isFailed ? Icons.cancel : Icons.access_time,
                color: isFailed ? Colors.red : Colors.orange,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.shopAddress,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Смена: ${report.shiftTypeText}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                  Text(
                    'Дата: ${report.date} • Дедлайн: ${report.deadline}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        isFailed ? Icons.warning : Icons.schedule,
                        color: isFailed ? Colors.red : Colors.orange,
                        size: 14,
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
          ],
        ),
      ),
    );
  }

  Widget _buildPendingReportsList(List<PendingEnvelopeReport> reports, String emptyMessage) {
    if (reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.mail_outline, size: 40, color: Colors.white.withOpacity(0.3)),
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _gold,
      backgroundColor: _emeraldDark,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        itemBuilder: (context, index) {
          final report = reports[index];
          return _buildPendingReportCard(report);
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/shift_report_model.dart';
import '../models/pending_shift_report_model.dart';
import '../services/shift_report_service.dart';
import '../services/pending_shift_service.dart';
import 'shift_report_view_page.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/report_notification_service.dart';

/// Страница со списком отчетов по пересменкам с вкладками
class ShiftReportsListPage extends StatefulWidget {
  const ShiftReportsListPage({super.key});

  @override
  State<ShiftReportsListPage> createState() => _ShiftReportsListPageState();
}

class _ShiftReportsListPageState extends State<ShiftReportsListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<List<String>> _shopsFuture;
  String? _selectedShop;
  String? _selectedEmployee;
  DateTime? _selectedDate;
  List<ShiftReport> _allReports = [];
  List<PendingShiftReport> _pendingShifts = [];
  List<ShiftReport> _expiredReports = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
    // Отмечаем все уведомления этого типа как просмотренные
    ReportNotificationService.markAllAsViewed(reportType: ReportType.shiftHandover);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<String>> _loadShopAddresses() async {
    try {
      final serverReports = await ShiftReportService.getReports();
      final localReports = await ShiftReport.loadAllReports();

      final addresses = <String>{};
      for (var report in serverReports) {
        addresses.add(report.shopAddress);
      }
      for (var report in localReports) {
        addresses.add(report.shopAddress);
      }

      final addressList = addresses.toList()..sort();
      return addressList;
    } catch (e) {
      Logger.error('Ошибка загрузки адресов магазинов', e);
      return await ShiftReport.getUniqueShopAddresses();
    }
  }

  Future<void> _loadData() async {
    Logger.info('Загрузка отчетов пересменки...');
    setState(() {
      _shopsFuture = _loadShopAddresses();
    });

    // Загружаем непройденные пересменки
    try {
      final pendingShifts = await PendingShiftService.getPendingReports();
      _pendingShifts = pendingShifts;
      Logger.success('Загружено непройденных пересменок: ${pendingShifts.length}');
    } catch (e) {
      Logger.error('Ошибка загрузки непройденных пересменок', e);
    }

    // Загружаем просроченные отчёты
    try {
      final expiredReports = await ShiftReportService.getExpiredReports();
      _expiredReports = expiredReports;
      Logger.success('Загружено просроченных отчётов: ${expiredReports.length}');
    } catch (e) {
      Logger.error('Ошибка загрузки просроченных отчётов', e);
    }

    // Загружаем отчеты с сервера
    try {
      final serverReports = await ShiftReportService.getReports();
      Logger.success('Загружено отчетов с сервера: ${serverReports.length}');

      final localReports = await ShiftReport.loadAllReports();
      Logger.success('Загружено локальных отчетов: ${localReports.length}');

      final Map<String, ShiftReport> reportsMap = {};

      for (var report in localReports) {
        reportsMap[report.id] = report;
      }

      for (var report in serverReports) {
        reportsMap[report.id] = report;
      }

      _allReports = reportsMap.values.toList();
      _allReports.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      Logger.success('Всего отчетов после объединения: ${_allReports.length}');
      setState(() {});
    } catch (e) {
      Logger.error('Ошибка загрузки отчетов', e);
      _allReports = await ShiftReport.loadAllReports();
      setState(() {});
    }
  }

  List<ShiftReport> _applyFilters(List<ShiftReport> reports) {
    var filtered = reports;

    if (_selectedShop != null) {
      filtered = filtered.where((r) => r.shopAddress == _selectedShop).toList();
    }

    if (_selectedEmployee != null) {
      filtered = filtered.where((r) => r.employeeName == _selectedEmployee).toList();
    }

    if (_selectedDate != null) {
      filtered = filtered.where((r) {
        return r.createdAt.year == _selectedDate!.year &&
               r.createdAt.month == _selectedDate!.month &&
               r.createdAt.day == _selectedDate!.day;
      }).toList();
    }

    return filtered;
  }

  /// Неподтверждённые отчёты (ожидают проверки) - только менее 5 часов
  List<ShiftReport> get _awaitingReports {
    final now = DateTime.now();
    final pending = _allReports.where((r) {
      if (r.isConfirmed) return false;
      // Показываем только отчёты, которые ожидают менее 5 часов
      final hours = now.difference(r.createdAt).inHours;
      return hours < 5;
    }).toList();
    return _applyFilters(pending);
  }

  /// Отчёты, которые ожидают более 5 часов (не подтверждённые)
  List<ShiftReport> get _overdueUnconfirmedReports {
    final now = DateTime.now();
    return _allReports.where((r) {
      if (r.isConfirmed) return false;
      final hours = now.difference(r.createdAt).inHours;
      return hours >= 5;
    }).toList();
  }

  /// Подтверждённые отчёты
  List<ShiftReport> get _confirmedReports {
    final confirmed = _allReports.where((r) => r.isConfirmed).toList();
    return _applyFilters(confirmed);
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber, size: 16),
                  const SizedBox(width: 4),
                  Text('Не пройдены (${_pendingShifts.length})',
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.hourglass_empty, size: 16),
                  const SizedBox(width: 4),
                  Text('Ожидают (${_awaitingReports.length})',
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 16),
                  const SizedBox(width: 4),
                  Text('Подтверждённые (${_allReports.where((r) => r.isConfirmed).length})',
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cancel, size: 16),
                  const SizedBox(width: 4),
                  Text('Не подтверждённые (${_expiredReports.length + _overdueUnconfirmedReports.length})',
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
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
            // Фильтры (только для вкладок с отчётами)
            if (_tabController.index != 0)
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white.withOpacity(0.1),
                child: Column(
                  children: [
                    FutureBuilder<List<String>>(
                      future: _shopsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return DropdownButtonFormField<String>(
                            value: _selectedShop,
                            isExpanded: true,
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

            // Вкладки с отчётами
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Вкладка "Не пройдены"
                  _buildPendingShiftsList(),
                  // Вкладка "Ожидают"
                  _buildReportsList(_awaitingReports, isPending: true),
                  // Вкладка "Подтверждённые"
                  _buildReportsList(_confirmedReports, isPending: false),
                  // Вкладка "Не подтверждённые" (просроченные)
                  _buildExpiredReportsList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Виджет для списка непройденных пересменок
  Widget _buildPendingShiftsList() {
    if (_pendingShifts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.white70),
            SizedBox(height: 16),
            Text(
              'Все пересменки пройдены!',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingShifts.length,
      itemBuilder: (context, index) {
        final pending = _pendingShifts[index];
        final isOverdue = pending.isOverdue;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: isOverdue ? Colors.red.shade50 : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isOverdue ? Colors.red : Colors.orange,
              child: Icon(
                pending.shiftType == 'morning' ? Icons.wb_sunny : Icons.nights_stay,
                color: Colors.white,
              ),
            ),
            title: Text(
              pending.shopAddress,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: pending.shiftType == 'morning'
                            ? Colors.orange.shade100
                            : Colors.indigo.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        pending.shiftLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: pending.shiftType == 'morning'
                              ? Colors.orange.shade800
                              : Colors.indigo.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'до ${pending.deadline}',
                      style: TextStyle(
                        color: isOverdue ? Colors.red : Colors.grey,
                        fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                if (isOverdue)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'ПРОСРОЧЕНО!',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: Icon(
              isOverdue ? Icons.error : Icons.schedule,
              color: isOverdue ? Colors.red : Colors.orange,
              size: 28,
            ),
          ),
        );
      },
    );
  }

  /// Виджет для списка просроченных (не подтверждённых) отчётов
  Widget _buildExpiredReportsList() {
    // Объединяем просроченные с сервера и отчеты ожидающие более 5 часов
    final allUnconfirmed = [
      ..._expiredReports,
      ..._overdueUnconfirmedReports,
    ];

    // Сортируем по дате создания (новые сначала)
    allUnconfirmed.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Убираем дубликаты по ID
    final Map<String, ShiftReport> uniqueReports = {};
    for (final report in allUnconfirmed) {
      uniqueReports[report.id] = report;
    }
    final reports = uniqueReports.values.toList();
    reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (reports.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.thumb_up, size: 64, color: Colors.white70),
            SizedBox(height: 16),
            Text(
              'Нет не подтверждённых отчётов',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              'Все отчёты были проверены вовремя',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final report = reports[index];
        final now = DateTime.now();
        final waitingHours = now.difference(report.createdAt).inHours;
        final isFromExpiredList = report.isExpired || report.expiredAt != null;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: Colors.red.shade50,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isFromExpiredList ? Colors.red : Colors.orange,
              child: Icon(
                isFromExpiredList ? Icons.cancel : Icons.access_time,
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
                  'Сдан: ${report.createdAt.day}.${report.createdAt.month}.${report.createdAt.year} '
                  '${report.createdAt.hour}:${report.createdAt.minute.toString().padLeft(2, '0')}',
                ),
                if (isFromExpiredList && report.expiredAt != null)
                  Text(
                    'Просрочен: ${report.expiredAt!.day}.${report.expiredAt!.month}.${report.expiredAt!.year}',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  )
                else
                  Text(
                    'Ожидает: $waitingHours ч. (более 5 часов)',
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
                Text('Вопросов: ${report.answers.length}'),
              ],
            ),
            trailing: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility, color: Colors.grey),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShiftReportViewPage(
                    report: report,
                    isReadOnly: true, // Только просмотр
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Color _getRatingColor(int rating) {
    if (rating <= 3) return Colors.red;
    if (rating <= 5) return Colors.orange;
    if (rating <= 7) return Colors.amber.shade700;
    return Colors.green;
  }

  Widget _buildReportsList(List<ShiftReport> reports, {required bool isPending}) {
    if (reports.isEmpty) {
      return Center(
        child: Text(
          isPending ? 'Нет отчётов, ожидающих подтверждения' : 'Нет подтверждённых отчётов',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final report = reports[index];
        final status = report.verificationStatus;

        Widget statusIcon;
        if (status == 'confirmed') {
          statusIcon = const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 24,
          );
        } else if (status == 'not_verified') {
          statusIcon = const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cancel,
                color: Colors.red,
                size: 24,
              ),
              SizedBox(width: 4),
              Text(
                'не проверено',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          );
        } else {
          statusIcon = const Icon(
            Icons.hourglass_empty,
            color: Colors.orange,
            size: 24,
          );
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: report.isConfirmed ? Colors.green : const Color(0xFF004D40),
              child: Icon(
                report.isConfirmed ? Icons.check : Icons.receipt_long,
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
                  '${report.createdAt.hour}:${report.createdAt.minute.toString().padLeft(2, '0')}',
                ),
                Text('Вопросов: ${report.answers.length}'),
                if (report.isConfirmed && report.confirmedAt != null) ...[
                  Row(
                    children: [
                      const Text(
                        'Подтверждено: ',
                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${report.confirmedAt!.day}.${report.confirmedAt!.month}.${report.confirmedAt!.year} '
                        '${report.confirmedAt!.hour}:${report.confirmedAt!.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.green),
                      ),
                    ],
                  ),
                  if (report.rating != null)
                    Row(
                      children: [
                        const Text('Оценка: ', style: TextStyle(fontSize: 13)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getRatingColor(report.rating!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${report.rating}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (report.confirmedByAdmin != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Проверил: ${report.confirmedByAdmin}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                statusIcon,
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_ios),
              ],
            ),
            onTap: () async {
              final allReports = await ShiftReport.loadAllReports();

              if (!mounted) return;

              final updatedReport = allReports.firstWhere(
                (r) => r.id == report.id,
                orElse: () => report,
              );

              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShiftReportViewPage(
                    report: updatedReport,
                  ),
                ),
              ).then((_) {
                _loadData();
              });
            },
          ),
        );
      },
    );
  }
}

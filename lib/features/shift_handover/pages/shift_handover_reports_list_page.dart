import 'package:flutter/material.dart';
import '../models/shift_handover_report_model.dart';
import '../models/pending_shift_handover_model.dart';
import '../services/shift_handover_report_service.dart';
import 'shift_handover_report_view_page.dart';
import '../../envelope/models/envelope_report_model.dart';
import '../../envelope/services/envelope_report_service.dart';
import '../../envelope/pages/envelope_report_view_page.dart';
import '../../shops/models/shop_model.dart';

/// Страница со списком отчетов по сдаче смены с вкладками
class ShiftHandoverReportsListPage extends StatefulWidget {
  const ShiftHandoverReportsListPage({super.key});

  @override
  State<ShiftHandoverReportsListPage> createState() => _ShiftHandoverReportsListPageState();
}

class _ShiftHandoverReportsListPageState extends State<ShiftHandoverReportsListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Future<List<String>>? _shopsFuture;
  String? _selectedShop;
  String? _selectedEmployee;
  DateTime? _selectedDate;
  List<ShiftHandoverReport> _allReports = [];
  List<Shop> _allShops = [];
  List<PendingShiftHandover> _pendingHandovers = []; // Непройденные сдачи смен (магазин + смена)
  List<ShiftHandoverReport> _expiredReports = [];
  List<EnvelopeReport> _envelopeReports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadData();
  }

  void _handleTabChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  Future<List<String>> _loadShopAddresses() async {
    try {
      final serverReports = await ShiftHandoverReportService.getReports();
      final localReports = await ShiftHandoverReport.loadAllLocal();

      final addresses = <String>{};
      for (var report in serverReports) {
        addresses.add(report.shopAddress);
      }
      for (var report in localReports) {
        addresses.add(report.shopAddress);
      }
      for (var report in _envelopeReports) {
        addresses.add(report.shopAddress);
      }

      final addressList = addresses.toList()..sort();
      return addressList;
    } catch (e) {
      print('❌ Ошибка загрузки адресов магазинов: $e');
      return await ShiftHandoverReport.getUniqueShopAddresses();
    }
  }

  /// Определить тип смены по времени отчёта
  String _getShiftType(DateTime dateTime) {
    final hour = dateTime.hour;
    // Утренняя смена: до 14:00
    // Вечерняя смена: после 14:00
    return hour < 14 ? 'morning' : 'evening';
  }

  /// Вычислить непройденные сдачи смен за сегодня (магазин + смена)
  void _calculatePendingHandovers() {
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final currentHour = today.hour;

    // Собираем пройденные сдачи смен за сегодня (ключ: магазин_смена)
    final completedHandovers = <String>{};
    for (final report in _allReports) {
      final reportDate = '${report.createdAt.year}-${report.createdAt.month.toString().padLeft(2, '0')}-${report.createdAt.day.toString().padLeft(2, '0')}';
      if (reportDate == todayStr) {
        final shiftType = _getShiftType(report.createdAt);
        final key = '${report.shopAddress.toLowerCase().trim()}_$shiftType';
        completedHandovers.add(key);
      }
    }

    // Формируем список непройденных сдач смен
    _pendingHandovers = [];
    for (final shop in _allShops) {
      final shopKey = shop.address.toLowerCase().trim();

      // Утренняя смена - показываем если текущее время >= 7:00
      if (currentHour >= 7) {
        final morningKey = '${shopKey}_morning';
        if (!completedHandovers.contains(morningKey)) {
          _pendingHandovers.add(PendingShiftHandover(
            shopAddress: shop.address,
            shiftType: 'morning',
            shiftName: 'Утренняя смена',
          ));
        }
      }

      // Вечерняя смена - показываем если текущее время >= 14:00
      if (currentHour >= 14) {
        final eveningKey = '${shopKey}_evening';
        if (!completedHandovers.contains(eveningKey)) {
          _pendingHandovers.add(PendingShiftHandover(
            shopAddress: shop.address,
            shiftType: 'evening',
            shiftName: 'Вечерняя смена',
          ));
        }
      }
    }

    // Сортируем: сначала по магазину, потом по смене
    _pendingHandovers.sort((a, b) {
      final shopCompare = a.shopAddress.compareTo(b.shopAddress);
      if (shopCompare != 0) return shopCompare;
      // Утренняя смена первой
      return a.shiftType == 'morning' ? -1 : 1;
    });

    print('📋 Непройденных сдач смен сегодня: ${_pendingHandovers.length}');
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    print('📥 Загрузка отчетов сдачи смены...');

    // Загружаем отчеты конвертов
    try {
      final envelopeReports = await EnvelopeReportService.getReports();
      _envelopeReports = envelopeReports;
      _envelopeReports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      print('✅ Загружено отчетов конвертов: ${envelopeReports.length}');
    } catch (e) {
      print('❌ Ошибка загрузки отчетов конвертов: $e');
    }

    _shopsFuture = _loadShopAddresses();

    // Загружаем магазины из API
    try {
      final shops = await Shop.loadShopsFromServer();
      _allShops = shops;
      print('✅ Загружено магазинов: ${shops.length}');
    } catch (e) {
      print('❌ Ошибка загрузки магазинов: $e');
    }

    // Загружаем просроченные отчёты
    try {
      final expiredReports = await ShiftHandoverReportService.getExpiredReports();
      _expiredReports = expiredReports;
      print('✅ Загружено просроченных отчётов: ${expiredReports.length}');
    } catch (e) {
      print('❌ Ошибка загрузки просроченных отчётов: $e');
    }

    // Загружаем отчеты с сервера
    try {
      final serverReports = await ShiftHandoverReportService.getReports();
      print('✅ Загружено отчетов с сервера: ${serverReports.length}');

      final localReports = await ShiftHandoverReport.loadAllLocal();
      print('✅ Загружено локальных отчетов: ${localReports.length}');

      final Map<String, ShiftHandoverReport> reportsMap = {};

      for (var report in localReports) {
        reportsMap[report.id] = report;
      }

      for (var report in serverReports) {
        reportsMap[report.id] = report;
      }

      _allReports = reportsMap.values.toList();
      _allReports.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Вычисляем непройденные сдачи смен за сегодня (магазин + смена)
      _calculatePendingHandovers();

      print('✅ Всего отчетов после объединения: ${_allReports.length}');
    } catch (e) {
      print('❌ Ошибка загрузки отчетов: $e');
      _allReports = await ShiftHandoverReport.loadAllLocal();
      _calculatePendingHandovers();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<ShiftHandoverReport> _applyFilters(List<ShiftHandoverReport> reports) {
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

  List<EnvelopeReport> _applyEnvelopeFilters(List<EnvelopeReport> reports) {
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
  List<ShiftHandoverReport> get _awaitingReports {
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
  List<ShiftHandoverReport> get _overdueUnconfirmedReports {
    final now = DateTime.now();
    return _allReports.where((r) {
      if (r.isConfirmed) return false;
      final hours = now.difference(r.createdAt).inHours;
      return hours >= 5;
    }).toList();
  }

  /// Подтверждённые отчёты
  List<ShiftHandoverReport> get _confirmedReports {
    final confirmed = _allReports.where((r) => r.isConfirmed).toList();
    return _applyFilters(confirmed);
  }

  /// Отфильтрованные отчеты конвертов
  List<EnvelopeReport> get _filteredEnvelopeReports {
    return _applyEnvelopeFilters(_envelopeReports);
  }

  /// Неподтверждённые конверты
  int get _unconfirmedEnvelopesCount {
    return _envelopeReports.where((r) => r.status != 'confirmed').length;
  }

  List<String> get _uniqueEmployees {
    final employees = <String>{};
    for (var r in _allReports) {
      employees.add(r.employeeName);
    }
    for (var r in _envelopeReports) {
      employees.add(r.employeeName);
    }
    return employees.toList()..sort();
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
        title: const Text('Отчеты (Сдача Смены)'),
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
                  const Icon(Icons.mail, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    _unconfirmedEnvelopesCount > 0
                        ? 'Конверты (${_envelopeReports.length}) ⚠️$_unconfirmedEnvelopesCount'
                        : 'Конверты (${_envelopeReports.length})',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber, size: 16),
                  const SizedBox(width: 4),
                  Text('Не пройдены (${_pendingHandovers.length})',
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
            if (_tabController.index != 1)
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white.withOpacity(0.1),
                child: Column(
                  children: [
                    if (_shopsFuture != null)
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
                          return const LinearProgressIndicator();
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
                  // Вкладка "Конверты"
                  _buildEnvelopeReportsList(),
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

  /// Виджет для списка отчетов конвертов
  Widget _buildEnvelopeReportsList() {
    final reports = _filteredEnvelopeReports;

    if (reports.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mail_outline, size: 64, color: Colors.white70),
            SizedBox(height: 16),
            Text(
              'Нет отчетов конвертов',
              style: TextStyle(color: Colors.white, fontSize: 18),
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
        final isConfirmed = report.status == 'confirmed';
        final isExpired = report.isExpired;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: isExpired && !isConfirmed ? Colors.red.shade50 : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isConfirmed
                  ? Colors.green
                  : (isExpired ? Colors.red : Colors.orange),
              child: Icon(
                report.shiftType == 'morning' ? Icons.wb_sunny : Icons.nights_stay,
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: report.shiftType == 'morning'
                            ? Colors.orange.shade100
                            : Colors.indigo.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        report.shiftTypeText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: report.shiftType == 'morning'
                              ? Colors.orange.shade800
                              : Colors.indigo.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${report.createdAt.day.toString().padLeft(2, '0')}.${report.createdAt.month.toString().padLeft(2, '0')}.${report.createdAt.year} '
                      '${report.createdAt.hour.toString().padLeft(2, '0')}:${report.createdAt.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'Итого: ${report.totalEnvelopeAmount.toStringAsFixed(0)} ₽',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF004D40),
                      ),
                    ),
                    if (report.expenses.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '(расходы: ${report.totalExpenses.toStringAsFixed(0)} ₽)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
                if (isConfirmed && report.rating != null)
                  Row(
                    children: [
                      const Text('Оценка: ', style: TextStyle(fontSize: 12)),
                      ...List.generate(5, (i) => Icon(
                        i < report.rating! ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 16,
                      )),
                    ],
                  ),
                if (isConfirmed && report.confirmedByAdmin != null)
                  Text(
                    'Подтвердил: ${report.confirmedByAdmin}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isConfirmed
                      ? Icons.check_circle
                      : (isExpired ? Icons.error : Icons.hourglass_empty),
                  color: isConfirmed
                      ? Colors.green
                      : (isExpired ? Colors.red : Colors.orange),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_ios),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EnvelopeReportViewPage(
                    report: report,
                    isAdmin: true, // TODO: check actual admin status
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

  /// Виджет для списка непройденных сдач смен
  Widget _buildPendingShiftsList() {
    if (_pendingHandovers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.white70),
            SizedBox(height: 16),
            Text(
              'Все сдачи смен пройдены!',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingHandovers.length,
      itemBuilder: (context, index) {
        final pending = _pendingHandovers[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: pending.shiftType == 'morning'
                  ? Colors.blue
                  : Colors.purple,
              child: Icon(
                pending.shiftType == 'morning' ? Icons.wb_sunny : Icons.nights_stay,
                color: Colors.white,
              ),
            ),
            title: Text(
              pending.shopAddress,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: pending.shiftType == 'morning'
                        ? Colors.blue.shade100
                        : Colors.purple.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    pending.shiftName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: pending.shiftType == 'morning'
                          ? Colors.blue.shade800
                          : Colors.purple.shade800,
                    ),
                  ),
                ),
              ],
            ),
            trailing: Icon(
              Icons.schedule,
              color: pending.shiftType == 'morning' ? Colors.blue : Colors.purple,
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
    final Map<String, ShiftHandoverReport> uniqueReports = {};
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
                  'Сдан: ${report.createdAt.day.toString().padLeft(2, '0')}.${report.createdAt.month.toString().padLeft(2, '0')}.${report.createdAt.year} '
                  '${report.createdAt.hour.toString().padLeft(2, '0')}:${report.createdAt.minute.toString().padLeft(2, '0')}',
                ),
                if (isFromExpiredList && report.expiredAt != null)
                  Text(
                    'Просрочен: ${report.expiredAt!.day.toString().padLeft(2, '0')}.${report.expiredAt!.month.toString().padLeft(2, '0')}.${report.expiredAt!.year}',
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
                  builder: (context) => ShiftHandoverReportViewPage(
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

  Widget _buildReportsList(List<ShiftHandoverReport> reports, {required bool isPending}) {
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
                report.isConfirmed ? Icons.check : Icons.assignment_turned_in,
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
                  '${report.createdAt.day.toString().padLeft(2, '0')}.${report.createdAt.month.toString().padLeft(2, '0')}.${report.createdAt.year} '
                  '${report.createdAt.hour.toString().padLeft(2, '0')}:${report.createdAt.minute.toString().padLeft(2, '0')}',
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
                        '${report.confirmedAt!.day.toString().padLeft(2, '0')}.${report.confirmedAt!.month.toString().padLeft(2, '0')}.${report.confirmedAt!.year} '
                        '${report.confirmedAt!.hour.toString().padLeft(2, '0')}:${report.confirmedAt!.minute.toString().padLeft(2, '0')}',
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
              final allReports = await ShiftHandoverReport.loadAllLocal();
              final updatedReport = allReports.firstWhere(
                (r) => r.id == report.id,
                orElse: () => report,
              );

              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ShiftHandoverReportViewPage(
                      report: updatedReport,
                    ),
                  ),
                ).then((_) {
                  _loadData();
                });
              }
            },
          ),
        );
      },
    );
  }
}

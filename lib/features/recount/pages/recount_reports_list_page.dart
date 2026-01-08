import 'package:flutter/material.dart';
import '../models/recount_report_model.dart';
import '../models/pending_recount_model.dart';
import '../services/recount_service.dart';
import '../../shops/models/shop_model.dart';
import 'recount_report_view_page.dart';

/// Страница со списком отчетов по пересчету с вкладками
class RecountReportsListPage extends StatefulWidget {
  const RecountReportsListPage({super.key});

  @override
  State<RecountReportsListPage> createState() => _RecountReportsListPageState();
}

class _RecountReportsListPageState extends State<RecountReportsListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedShop;
  String? _selectedEmployee;
  DateTime? _selectedDate;
  List<RecountReport> _allReports = [];
  List<Shop> _allShops = [];
  List<PendingRecount> _pendingRecounts = []; // Непройденные пересчёты (магазин + смена)
  List<RecountReport> _expiredReports = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Для обновления фильтров при смене вкладки
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    print('📥 Загрузка отчетов пересчёта...');

    // Загружаем магазины из API
    try {
      final shops = await Shop.loadShopsFromGoogleSheets();
      _allShops = shops;
      print('✅ Загружено магазинов: ${shops.length}');
    } catch (e) {
      print('❌ Ошибка загрузки магазинов: $e');
    }

    // Загружаем просроченные отчёты
    try {
      final expiredReports = await RecountService.getExpiredReports();
      _expiredReports = expiredReports;
      print('✅ Загружено просроченных отчётов: ${expiredReports.length}');
    } catch (e) {
      print('❌ Ошибка загрузки просроченных отчётов: $e');
    }

    // Загружаем отчеты с сервера
    try {
      final serverReports = await RecountService.getReports();
      print('✅ Загружено отчетов с сервера: ${serverReports.length}');

      _allReports = serverReports;
      _allReports.sort((a, b) => b.completedAt.compareTo(a.completedAt));

      // Вычисляем непройденные пересчёты за сегодня (магазин + смена)
      _calculatePendingRecounts();

      print('✅ Всего отчетов: ${_allReports.length}');
      setState(() {});
    } catch (e) {
      print('❌ Ошибка загрузки отчетов: $e');
      setState(() {});
    }
  }

  /// Определить тип смены по времени отчёта
  String _getShiftType(DateTime dateTime) {
    final hour = dateTime.hour;
    // Утренняя смена: до 14:00
    // Вечерняя смена: после 14:00
    return hour < 14 ? 'morning' : 'evening';
  }

  /// Вычислить непройденные пересчёты за сегодня (магазин + смена)
  void _calculatePendingRecounts() {
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final currentHour = today.hour;

    // Собираем пройденные пересчёты за сегодня (ключ: магазин_смена)
    final completedRecounts = <String>{};
    for (final report in _allReports) {
      final reportDate = '${report.completedAt.year}-${report.completedAt.month.toString().padLeft(2, '0')}-${report.completedAt.day.toString().padLeft(2, '0')}';
      if (reportDate == todayStr) {
        final shiftType = _getShiftType(report.completedAt);
        final key = '${report.shopAddress.toLowerCase().trim()}_$shiftType';
        completedRecounts.add(key);
      }
    }

    // Формируем список непройденных пересчётов
    _pendingRecounts = [];
    for (final shop in _allShops) {
      final shopKey = shop.address.toLowerCase().trim();

      // Утренняя смена - показываем если текущее время >= 8:00
      if (currentHour >= 8) {
        final morningKey = '${shopKey}_morning';
        if (!completedRecounts.contains(morningKey)) {
          _pendingRecounts.add(PendingRecount(
            shopAddress: shop.address,
            shiftType: 'morning',
            shiftName: 'Утренняя смена',
          ));
        }
      }

      // Вечерняя смена - показываем если текущее время >= 14:00
      if (currentHour >= 14) {
        final eveningKey = '${shopKey}_evening';
        if (!completedRecounts.contains(eveningKey)) {
          _pendingRecounts.add(PendingRecount(
            shopAddress: shop.address,
            shiftType: 'evening',
            shiftName: 'Вечерняя смена',
          ));
        }
      }
    }

    // Сортируем: сначала по магазину, потом по смене
    _pendingRecounts.sort((a, b) {
      final shopCompare = a.shopAddress.compareTo(b.shopAddress);
      if (shopCompare != 0) return shopCompare;
      // Утренняя смена первой
      return a.shiftType == 'morning' ? -1 : 1;
    });

    print('📋 Непройденных пересчётов сегодня: ${_pendingRecounts.length}');
  }

  List<RecountReport> _applyFilters(List<RecountReport> reports) {
    var filtered = reports;

    if (_selectedShop != null) {
      filtered = filtered.where((r) => r.shopAddress == _selectedShop).toList();
    }

    if (_selectedEmployee != null) {
      filtered = filtered.where((r) => r.employeeName == _selectedEmployee).toList();
    }

    if (_selectedDate != null) {
      filtered = filtered.where((r) {
        return r.completedAt.year == _selectedDate!.year &&
               r.completedAt.month == _selectedDate!.month &&
               r.completedAt.day == _selectedDate!.day;
      }).toList();
    }

    return filtered;
  }

  /// Не оценённые отчёты (ожидают проверки) - только менее 5 часов
  List<RecountReport> get _awaitingReports {
    final now = DateTime.now();
    final pending = _allReports.where((r) {
      if (r.isRated) return false;
      if (r.isExpired) return false;
      // Показываем только отчёты, которые ожидают менее 5 часов
      final hours = now.difference(r.completedAt).inHours;
      return hours < 5;
    }).toList();
    return _applyFilters(pending);
  }

  /// Отчёты, которые ожидают более 5 часов (не оценённые)
  List<RecountReport> get _overdueUnratedReports {
    final now = DateTime.now();
    return _allReports.where((r) {
      if (r.isRated) return false;
      if (r.isExpired) return true; // Просроченные тоже включаем
      final hours = now.difference(r.completedAt).inHours;
      return hours >= 5;
    }).toList();
  }

  /// Оценённые отчёты
  List<RecountReport> get _ratedReports {
    final rated = _allReports.where((r) => r.isRated).toList();
    return _applyFilters(rated);
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
                  Text('Не пройдены (${_pendingRecounts.length})',
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
                  Text('Оценённые (${_allReports.where((r) => r.isRated).length})',
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
                  Text('Не оценённые (${_expiredReports.length + _overdueUnratedReports.length})',
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
            // Фильтры (только для вкладок с отчётами, не для "Не пройдены")
            if (_tabController.index != 0)
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white.withOpacity(0.95),
                child: Column(
                  children: [
                    // Магазин
                    DropdownButtonFormField<String>(
                      value: _selectedShop,
                      isExpanded: true,
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
                    // Сотрудник
                    DropdownButtonFormField<String>(
                      value: _selectedEmployee,
                      isExpanded: true,
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
                          child: Text(employee, overflow: TextOverflow.ellipsis),
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

            // Вкладки с отчётами
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Вкладка "Не пройдены"
                  _buildPendingRecountsList(),
                  // Вкладка "Ожидают"
                  _buildReportsList(_awaitingReports, isPending: true),
                  // Вкладка "Оценённые"
                  _buildReportsList(_ratedReports, isPending: false),
                  // Вкладка "Не оценённые" (просроченные)
                  _buildExpiredReportsList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Виджет для списка непройденных пересчётов
  Widget _buildPendingRecountsList() {
    if (_pendingRecounts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.white70),
            SizedBox(height: 16),
            Text(
              'Все пересчёты пройдены!',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      );
    }

    final today = DateTime.now();
    final todayStr = '${today.day}.${today.month}.${today.year}';

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingRecounts.length,
      itemBuilder: (context, index) {
        final pending = _pendingRecounts[index];
        final isMorning = pending.shiftType == 'morning';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isMorning ? Colors.orange : Colors.deepOrange,
              child: Icon(
                isMorning ? Icons.wb_sunny : Icons.nights_stay,
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
                Text('Дата: $todayStr'),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: isMorning ? Colors.blue.shade100 : Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        pending.shiftName,
                        style: TextStyle(
                          color: isMorning ? Colors.blue.shade700 : Colors.purple.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Пересчёт не проведён',
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            trailing: const Icon(
              Icons.schedule,
              color: Colors.orange,
              size: 28,
            ),
          ),
        );
      },
    );
  }

  /// Виджет для списка просроченных (не оценённых) отчётов
  Widget _buildExpiredReportsList() {
    // Объединяем просроченные с сервера и отчеты ожидающие более 5 часов
    final allUnrated = [
      ..._expiredReports,
      ..._overdueUnratedReports,
    ];

    // Сортируем по дате (новые сначала)
    allUnrated.sort((a, b) => b.completedAt.compareTo(a.completedAt));

    // Убираем дубликаты по ID
    final Map<String, RecountReport> uniqueReports = {};
    for (final report in allUnrated) {
      uniqueReports[report.id] = report;
    }
    final reports = uniqueReports.values.toList();
    reports.sort((a, b) => b.completedAt.compareTo(a.completedAt));

    if (reports.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.thumb_up, size: 64, color: Colors.white70),
            SizedBox(height: 16),
            Text(
              'Нет не оценённых отчётов',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              'Все отчёты были оценены вовремя',
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
        final waitingHours = now.difference(report.completedAt).inHours;
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
                Text('Время: ${report.formattedDuration}'),
                Text(
                  'Сдан: ${report.completedAt.day}.${report.completedAt.month}.${report.completedAt.year} '
                  '${report.completedAt.hour.toString().padLeft(2, '0')}:${report.completedAt.minute.toString().padLeft(2, '0')}',
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
                  builder: (context) => RecountReportViewPage(
                    report: report,
                    isReadOnly: true, // Только просмотр
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
    );
  }

  Color _getRatingColor(int rating) {
    if (rating <= 3) return Colors.red;
    if (rating <= 5) return Colors.orange;
    if (rating <= 7) return Colors.amber.shade700;
    return Colors.green;
  }

  Widget _buildReportsList(List<RecountReport> reports, {required bool isPending}) {
    if (reports.isEmpty) {
      return Center(
        child: Text(
          isPending ? 'Нет отчётов, ожидающих оценки' : 'Нет оценённых отчётов',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        itemBuilder: (context, index) {
          final report = reports[index];

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: report.isRated ? Colors.green : Colors.orange,
                child: Icon(
                  report.isRated ? Icons.check : Icons.pending,
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
                  Text('Время: ${report.formattedDuration}'),
                  Text(
                    'Дата: ${report.completedAt.day}.${report.completedAt.month}.${report.completedAt.year} '
                    '${report.completedAt.hour.toString().padLeft(2, '0')}:${report.completedAt.minute.toString().padLeft(2, '0')}',
                  ),
                  if (report.isRated) ...[
                    Row(
                      children: [
                        const Text('Оценка: ', style: TextStyle(fontSize: 13)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getRatingColor(report.adminRating!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${report.adminRating}/10',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (report.adminName != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Проверил: ${report.adminName}',
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
  }
}

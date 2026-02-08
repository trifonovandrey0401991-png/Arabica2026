import 'package:flutter/material.dart';
import '../models/shift_handover_report_model.dart';
import '../models/pending_shift_handover_model.dart';
import '../services/shift_handover_report_service.dart';
import '../services/pending_shift_handover_service.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/report_notification_service.dart';
import 'shift_handover_report_view_page.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../../efficiency/models/points_settings_model.dart';
import '../../efficiency/services/points_settings_service.dart';

/// Тип группы для иерархической группировки отчётов
enum HandoverReportGroupType { today, yesterday, day, week, month }

/// Группа отчётов для иерархического отображения
class HandoverReportGroup {
  final HandoverReportGroupType type;
  final String title;
  final String key; // Уникальный ключ для хранения состояния
  final int count;
  final int confirmedCount; // Количество подтверждённых
  final DateTime startDate;
  final List<dynamic> children; // List<ShiftHandoverReport> или List<HandoverReportGroup>

  HandoverReportGroup({
    required this.type,
    required this.title,
    required this.key,
    required this.count,
    this.confirmedCount = 0,
    required this.startDate,
    required this.children,
  });
}

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
  List<PendingShiftHandover> _pendingHandovers = []; // Непройденные сдачи смен (в срок)
  List<PendingShiftHandover> _overdueHandovers = []; // Просроченные сдачи смен (не в срок)
  List<ShiftHandoverReport> _expiredReports = [];
  ShiftHandoverPointsSettings? _handoverSettings; // Настройки временных окон
  bool _isLoading = true;
  int _overdueViewedCount = 0; // Количество просмотренных просроченных (для бейджа)

  // Состояние раскрытия групп (ключ = уникальный идентификатор группы)
  final Map<String, bool> _expandedGroups = {};

  // Dark emerald color palette
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadData();
    // Отмечаем все уведомления этого типа как просмотренные
    ReportNotificationService.markAllAsViewed(reportType: ReportType.shiftReport);
  }

  void _handleTabChange() {
    // Если перешли на вкладку "Не в срок" (index 2), сбрасываем счётчик бейджа
    if (_tabController.index == 2) {
      _overdueViewedCount = _overdueHandovers.length;
    }
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
      final serverReports = await ShiftHandoverReportService.getReportsForCurrentUser();
      final localReports = await ShiftHandoverReport.loadAllLocal();

      final addresses = <String>{};
      for (var report in serverReports) {
        if (report.shopAddress.trim().isNotEmpty) addresses.add(report.shopAddress);
      }
      for (var report in localReports) {
        if (report.shopAddress.trim().isNotEmpty) addresses.add(report.shopAddress);
      }

      final addressList = addresses.toList()..sort();
      return addressList;
    } catch (e) {
      Logger.error('Ошибка загрузки адресов магазинов', e);
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

  /// Парсинг времени из строки формата "HH:MM"
  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: parts.length > 1 ? int.parse(parts[1]) : 0,
    );
  }

  /// Проверить, прошёл ли дедлайн для смены
  bool _isOverdue(String shiftType, DateTime now, ShiftHandoverPointsSettings settings) {
    final currentMinutes = now.hour * 60 + now.minute;

    if (shiftType == 'morning') {
      final deadline = _parseTime(settings.morningEndTime);
      final deadlineMinutes = deadline.hour * 60 + deadline.minute;
      return currentMinutes > deadlineMinutes;
    } else {
      final deadline = _parseTime(settings.eveningEndTime);
      final deadlineMinutes = deadline.hour * 60 + deadline.minute;
      return currentMinutes > deadlineMinutes;
    }
  }

  /// Загрузить непройденные и просроченные сдачи смен с сервера
  Future<void> _loadPendingHandovers() async {
    Logger.info('Загрузка сдач смен с сервера...');

    // Очищаем списки
    _pendingHandovers = [];
    _overdueHandovers = [];

    try {
      // Загружаем pending отчёты с сервера
      final pendingReports = await PendingShiftHandoverService.getPendingReports();
      Logger.info('Получено pending отчётов: ${pendingReports.length}');

      for (final report in pendingReports) {
        _pendingHandovers.add(PendingShiftHandover(
          shopAddress: report.shopAddress,
          shiftType: report.shiftType,
          shiftName: report.shiftType == 'morning' ? 'Утренняя смена' : 'Вечерняя смена',
        ));
      }
    } catch (e) {
      Logger.error('Ошибка загрузки pending отчётов', e);
      // Fallback: локальное вычисление если сервер недоступен
      _calculatePendingHandoversLocal();
      return;
    }

    try {
      // Загружаем failed отчёты с сервера
      final failedReports = await PendingShiftHandoverService.getFailedReports();
      Logger.info('Получено failed отчётов: ${failedReports.length}');

      for (final report in failedReports) {
        _overdueHandovers.add(PendingShiftHandover(
          shopAddress: report.shopAddress,
          shiftType: report.shiftType,
          shiftName: report.shiftType == 'morning' ? 'Утренняя смена' : 'Вечерняя смена',
        ));
      }
    } catch (e) {
      Logger.error('Ошибка загрузки failed отчётов', e);
    }

    // Сортируем: сначала по магазину, потом по смене
    void sortHandovers(List<PendingShiftHandover> list) {
      list.sort((a, b) {
        final shopCompare = a.shopAddress.compareTo(b.shopAddress);
        if (shopCompare != 0) return shopCompare;
        return a.shiftType == 'morning' ? -1 : 1;
      });
    }

    sortHandovers(_pendingHandovers);
    sortHandovers(_overdueHandovers);

    Logger.info('Непройденных сдач смен (в срок): ${_pendingHandovers.length}');
    Logger.info('Просроченных сдач смен (не в срок): ${_overdueHandovers.length}');
  }

  /// Локальное вычисление (fallback если сервер недоступен)
  void _calculatePendingHandoversLocal() {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final settings = _handoverSettings ?? ShiftHandoverPointsSettings.defaults();

    Logger.info('Локальное вычисление сдач смен. Магазинов: ${_allShops.length}');
    Logger.info('Дедлайны из настроек: утро до ${settings.morningEndTime}, вечер до ${settings.eveningEndTime}');

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

    _pendingHandovers = [];
    _overdueHandovers = [];

    for (final shop in _allShops) {
      final shopKey = shop.address.toLowerCase().trim();

      // Утренняя смена
      final morningKey = '${shopKey}_morning';
      if (!completedHandovers.contains(morningKey)) {
        final pending = PendingShiftHandover(
          shopAddress: shop.address,
          shiftType: 'morning',
          shiftName: 'Утренняя смена',
        );

        if (_isOverdue('morning', now, settings)) {
          _overdueHandovers.add(pending);
        } else {
          _pendingHandovers.add(pending);
        }
      }

      // Вечерняя смена
      final eveningKey = '${shopKey}_evening';
      if (!completedHandovers.contains(eveningKey)) {
        final pending = PendingShiftHandover(
          shopAddress: shop.address,
          shiftType: 'evening',
          shiftName: 'Вечерняя смена',
        );

        if (_isOverdue('evening', now, settings)) {
          _overdueHandovers.add(pending);
        } else {
          _pendingHandovers.add(pending);
        }
      }
    }

    // Сортируем
    void sortHandovers(List<PendingShiftHandover> list) {
      list.sort((a, b) {
        final shopCompare = a.shopAddress.compareTo(b.shopAddress);
        if (shopCompare != 0) return shopCompare;
        return a.shiftType == 'morning' ? -1 : 1;
      });
    }

    sortHandovers(_pendingHandovers);
    sortHandovers(_overdueHandovers);

    Logger.info('Непройденных сдач смен (в срок): ${_pendingHandovers.length}');
    Logger.info('Просроченных сдач смен (не в срок): ${_overdueHandovers.length}');
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    Logger.info('Загрузка отчетов сдачи смены...');

    // Загружаем настройки временных окон для сдачи смены
    try {
      final settings = await PointsSettingsService.getShiftHandoverPointsSettings();
      _handoverSettings = settings;
      Logger.success('Загружены настройки времени сдачи смены: утро ${settings.morningEndTime}, вечер ${settings.eveningEndTime}');
    } catch (e) {
      Logger.error('Ошибка загрузки настроек времени', e);
      _handoverSettings = ShiftHandoverPointsSettings.defaults();
    }

    _shopsFuture = _loadShopAddresses();

    // Загружаем магазины из API
    try {
      final shops = await ShopService.getShopsForCurrentUser();
      _allShops = shops;
      Logger.success('Загружено магазинов (с учётом роли): ${shops.length}');
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов', e);
    }

    // Загружаем просроченные отчёты
    try {
      final expiredReports = await ShiftHandoverReportService.getExpiredReports();
      _expiredReports = expiredReports;
      Logger.success('Загружено просроченных отчётов: ${expiredReports.length}');
    } catch (e) {
      Logger.error('Ошибка загрузки просроченных отчётов', e);
    }

    // Загружаем отчеты с сервера
    try {
      final serverReports = await ShiftHandoverReportService.getReportsForCurrentUser();
      Logger.success('Загружено отчетов с сервера: ${serverReports.length}');

      final localReports = await ShiftHandoverReport.loadAllLocal();
      Logger.success('Загружено локальных отчетов: ${localReports.length}');

      final Map<String, ShiftHandoverReport> reportsMap = {};

      for (var report in localReports) {
        reportsMap[report.id] = report;
      }

      for (var report in serverReports) {
        reportsMap[report.id] = report;
      }

      _allReports = reportsMap.values.toList();
      _allReports.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Загружаем непройденные сдачи смен с сервера
      await _loadPendingHandovers();

      Logger.success('Всего отчетов после объединения: ${_allReports.length}');
    } catch (e) {
      Logger.error('Ошибка загрузки отчетов', e);
      _allReports = await ShiftHandoverReport.loadAllLocal();
      await _loadPendingHandovers();
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

  List<String> get _uniqueEmployees {
    final employees = <String>{};
    for (var r in _allReports) {
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
              // Красивый заголовок
              _buildHeader(),
              // Вкладки (3 + 2)
              _buildTwoRowTabs(),
              // Фильтры (только для вкладок с отчётами, не для "Не пройдены" и "Не в срок")
              if (_tabController.index != 0 && _tabController.index != 1) _buildFiltersSection(),

              // Вкладки с отчётами
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Вкладка "Не пройдены" (в срок)
                    _buildPendingShiftsList(),
                    // Вкладка "Не в срок" (просроченные)
                    _buildOverdueShiftsList(),
                    // Вкладка "Ожидают" (с иерархической группировкой)
                    _buildGroupedHandoverReportsList(_awaitingReports, isConfirmed: false, prefix: 'awaiting'),
                    // Вкладка "Подтверждённые" (с иерархической группировкой)
                    _buildGroupedHandoverReportsList(_confirmedReports, isConfirmed: true, prefix: 'confirmed'),
                    // Вкладка "Не подтверждённые" (с иерархической группировкой)
                    _buildGroupedExpiredReportsList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Красивый заголовок страницы
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Row(
        children: [
          // Кнопка назад
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          // Заголовок
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Отчёты (Сдача Смены)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Всего: ${_allReports.length} отчётов',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Кнопка обновления
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadData,
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
    );
  }

  /// Вычислить количество непросмотренных просроченных (для бейджа)
  int get _overdueUnviewedBadge {
    final newCount = _overdueHandovers.length - _overdueViewedCount;
    return newCount > 0 ? newCount : 0;
  }

  /// Построение двухрядных вкладок (3 сверху, 2 снизу)
  Widget _buildTwoRowTabs() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        children: [
          // Первый ряд: 3 вкладки
          Row(
            children: [
              _buildTabButton(0, Icons.schedule, 'Не пройдены', _pendingHandovers.length, Colors.orange),
              const SizedBox(width: 6),
              _buildTabButton(1, Icons.warning_amber, 'Не в срок', _overdueHandovers.length, Colors.red, badge: _overdueUnviewedBadge),
              const SizedBox(width: 6),
              _buildTabButton(2, Icons.hourglass_empty, 'Ожидают', _awaitingReports.length, Colors.blue),
            ],
          ),
          const SizedBox(height: 6),
          // Второй ряд: 2 вкладки
          Row(
            children: [
              _buildTabButton(3, Icons.check_circle, 'Подтверждённые', _allReports.where((r) => r.isConfirmed).length, Colors.green),
              const SizedBox(width: 6),
              _buildTabButton(4, Icons.cancel, 'Отклонённые', _expiredReports.length + _overdueUnconfirmedReports.length, Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  /// Построение одной кнопки-вкладки
  Widget _buildTabButton(int index, IconData icon, String label, int count, Color accentColor, {int badge = 0}) {
    final isSelected = _tabController.index == index;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _tabController.animateTo(index);
            setState(() {});
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [accentColor.withOpacity(0.8), accentColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isSelected ? null : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? accentColor : Colors.white.withOpacity(0.15),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withOpacity(0.3) : accentColor.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : accentColor,
                    ),
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 2),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Секция фильтров (компактная)
  Widget _buildFiltersSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Компактная строка фильтров
          Row(
            children: [
              // Магазин
              Expanded(
                child: _shopsFuture != null
                    ? FutureBuilder<List<String>>(
                        future: _shopsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return _buildCompactDropdown(
                              icon: Icons.store,
                              value: _selectedShop,
                              hint: 'Магазин',
                              items: snapshot.data!,
                              onChanged: (v) => setState(() => _selectedShop = v),
                            );
                          }
                          return const SizedBox();
                        },
                      )
                    : const SizedBox(),
              ),
              const SizedBox(width: 8),
              // Дата
              _buildDateButton(),
            ],
          ),
          const SizedBox(height: 8),
          // Сотрудник + сброс
          Row(
            children: [
              Expanded(
                child: _buildCompactDropdown(
                  icon: Icons.person,
                  value: _selectedEmployee,
                  hint: 'Сотрудник',
                  items: _uniqueEmployees,
                  onChanged: (v) => setState(() => _selectedEmployee = v),
                ),
              ),
              if (_selectedShop != null || _selectedEmployee != null || _selectedDate != null) ...[
                const SizedBox(width: 8),
                _buildResetButton(),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Компактный dropdown
  Widget _buildCompactDropdown({
    required IconData icon,
    required String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: _emeraldDark,
          icon: const Icon(Icons.arrow_drop_down, color: _gold),
          hint: Row(
            children: [
              Icon(icon, size: 18, color: Colors.white.withOpacity(0.5)),
              const SizedBox(width: 8),
              Text(hint, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5))),
            ],
          ),
          selectedItemBuilder: (context) {
            return [
              Row(
                children: [
                  Icon(icon, size: 18, color: _gold),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Все', style: TextStyle(fontSize: 13, color: Colors.white))),
                ],
              ),
              ...items.map((item) => Row(
                children: [
                  Icon(icon, size: 18, color: _gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )),
            ];
          },
          items: [
            DropdownMenuItem<String>(value: null, child: Text('Все $hint', style: const TextStyle(color: Colors.white))),
            ...items.map((item) => DropdownMenuItem(value: item, child: Text(item, style: const TextStyle(color: Colors.white)))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  /// Кнопка выбора даты
  Widget _buildDateButton() {
    return InkWell(
      onTap: () => _selectDate(context),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today, size: 18, color: _gold),
            const SizedBox(width: 8),
            Text(
              _selectedDate == null
                  ? 'Дата'
                  : '${_selectedDate!.day}.${_selectedDate!.month}',
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  /// Кнопка сброса фильтров
  Widget _buildResetButton() {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedShop = null;
          _selectedEmployee = null;
          _selectedDate = null;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.clear, size: 20, color: Colors.white),
      ),
    );
  }


  /// Виджет для списка непройденных сдач смен (в срок)
  Widget _buildPendingShiftsList() {
    final settings = _handoverSettings ?? ShiftHandoverPointsSettings.defaults();

    if (_pendingHandovers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text(
              'Все сдачи смен в срок пройдены!',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Дедлайны: утро до ${settings.morningEndTime}, вечер до ${settings.eveningEndTime}',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingHandovers.length + 1, // +1 для заголовка с временем
      itemBuilder: (context, index) {
        if (index == 0) {
          // Информационный заголовок с дедлайнами
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white.withOpacity(0.5), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Дедлайны: утро до ${settings.morningEndTime}, вечер до ${settings.eveningEndTime}',
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        }

        final pending = _pendingHandovers[index - 1];

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
              CircleAvatar(
                backgroundColor: pending.shiftType == 'morning'
                    ? Colors.orange.withOpacity(0.8)
                    : Colors.indigo.withOpacity(0.8),
                child: Icon(
                  pending.shiftType == 'morning' ? Icons.wb_sunny : Icons.nights_stay,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pending.shopAddress,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: pending.shiftType == 'morning'
                                ? Colors.orange.withOpacity(0.2)
                                : Colors.indigo.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            pending.shiftName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: pending.shiftType == 'morning'
                                  ? Colors.orange.shade300
                                  : Colors.indigo.shade200,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'до ${pending.shiftType == 'morning' ? settings.morningEndTime : settings.eveningEndTime}',
                          style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.schedule,
                color: pending.shiftType == 'morning' ? Colors.orange.withOpacity(0.7) : Colors.indigo.withOpacity(0.7),
                size: 28,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Виджет для списка просроченных сдач смен (не в срок)
  Widget _buildOverdueShiftsList() {
    final settings = _handoverSettings ?? ShiftHandoverPointsSettings.defaults();

    if (_overdueHandovers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.thumb_up, size: 64, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text(
              'Нет просроченных сдач смен!',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Все сдачи выполнены в срок',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _overdueHandovers.length + 1, // +1 для заголовка
      itemBuilder: (context, index) {
        if (index == 0) {
          // Предупреждающий заголовок
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Просроченные сдачи смен',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        'Штраф: ${settings.missedPenalty} баллов за пропуск',
                        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final pending = _overdueHandovers[index - 1];

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Colors.red,
                child: Icon(
                  Icons.warning_amber,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pending.shopAddress,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            pending.shiftName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade300,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Просрочено',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 24),
                  Text(
                    '${settings.missedPenalty}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.thumb_up, size: 64, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text(
              'Нет не подтверждённых отчётов',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Все отчёты были проверены вовремя',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
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

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: InkWell(
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
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: isFromExpiredList ? Colors.red.withOpacity(0.8) : Colors.orange.withOpacity(0.8),
                  child: Icon(
                    isFromExpiredList ? Icons.cancel : Icons.access_time,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.shopAddress,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text('Сотрудник: ${report.employeeName}', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                      Text(
                        'Сдан: ${report.createdAt.day.toString().padLeft(2, '0')}.${report.createdAt.month.toString().padLeft(2, '0')}.${report.createdAt.year} '
                        '${report.createdAt.hour.toString().padLeft(2, '0')}:${report.createdAt.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(color: Colors.white.withOpacity(0.6)),
                      ),
                      if (isFromExpiredList && report.expiredAt != null)
                        Text(
                          'Просрочен: ${report.expiredAt!.day.toString().padLeft(2, '0')}.${report.expiredAt!.month.toString().padLeft(2, '0')}.${report.expiredAt!.year}',
                          style: TextStyle(color: Colors.red.shade300, fontWeight: FontWeight.bold),
                        )
                      else
                        Text(
                          'Ожидает: $waitingHours ч. (более 5 часов)',
                          style: TextStyle(color: Colors.orange.shade300, fontWeight: FontWeight.bold),
                        ),
                      Text('Вопросов: ${report.answers.length}', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility, color: Colors.white.withOpacity(0.4)),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.4)),
                  ],
                ),
              ],
            ),
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
          statusIcon = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cancel,
                color: Colors.red,
                size: 24,
              ),
              const SizedBox(width: 4),
              Text(
                'не проверено',
                style: TextStyle(
                  color: Colors.red.shade300,
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

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: InkWell(
            onTap: () async {
              final allReports = await ShiftHandoverReport.loadAllLocal();

              if (!mounted) return;

              final updatedReport = allReports.firstWhere(
                (r) => r.id == report.id,
                orElse: () => report,
              );

              if (!context.mounted) return;
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
            },
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: report.isConfirmed ? Colors.green.withOpacity(0.8) : _emerald,
                  child: Icon(
                    report.isConfirmed ? Icons.check : Icons.assignment_turned_in,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.shopAddress,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text('Сотрудник: ${report.employeeName}', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                      Text(
                        '${report.createdAt.day.toString().padLeft(2, '0')}.${report.createdAt.month.toString().padLeft(2, '0')}.${report.createdAt.year} '
                        '${report.createdAt.hour.toString().padLeft(2, '0')}:${report.createdAt.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(color: Colors.white.withOpacity(0.6)),
                      ),
                      Text('Вопросов: ${report.answers.length}', style: TextStyle(color: Colors.white.withOpacity(0.6))),
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
                              Text('Оценка: ', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7))),
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
                                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    statusIcon,
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.4)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // ИЕРАРХИЧЕСКАЯ ГРУППИРОВКА ОТЧЁТОВ
  // ============================================================

  /// Названия месяцев в родительном падеже
  static const _monthNamesGenitive = [
    '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
  ];

  /// Названия месяцев в именительном падеже
  static const _monthNamesNominative = [
    '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
  ];

  /// Получить начало недели (понедельник)
  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday; // Пн=1, Вс=7
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: weekday - 1));
  }

  /// Форматировать название дня
  String _formatDayTitle(DateTime day) {
    return '${day.day} ${_monthNamesGenitive[day.month]}';
  }

  /// Получить цвет для типа группы
  Color _getGroupColor(HandoverReportGroupType type) {
    switch (type) {
      case HandoverReportGroupType.today:
        return Colors.green;
      case HandoverReportGroupType.yesterday:
        return Colors.blue;
      case HandoverReportGroupType.day:
        return Colors.orange;
      case HandoverReportGroupType.week:
        return Colors.purple;
      case HandoverReportGroupType.month:
        return Colors.indigo;
    }
  }

  /// Получить иконку для типа группы
  IconData _getGroupIcon(HandoverReportGroupType type) {
    switch (type) {
      case HandoverReportGroupType.today:
        return Icons.today;
      case HandoverReportGroupType.yesterday:
        return Icons.history;
      case HandoverReportGroupType.day:
        return Icons.calendar_today;
      case HandoverReportGroupType.week:
        return Icons.date_range;
      case HandoverReportGroupType.month:
        return Icons.calendar_month;
    }
  }

  /// Группировать отчёты по сдаче смены по времени
  List<HandoverReportGroup> _groupHandoverReports(List<ShiftHandoverReport> reports, String prefix) {
    if (reports.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    List<HandoverReportGroup> result = [];

    // Группируем по дням
    Map<DateTime, List<ShiftHandoverReport>> byDay = {};
    for (final report in reports) {
      final day = DateTime(report.createdAt.year, report.createdAt.month, report.createdAt.day);
      byDay.putIfAbsent(day, () => []).add(report);
    }

    // Сортируем дни (новые первые)
    final sortedDays = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    // Сегодня - по умолчанию развёрнуто
    if (byDay.containsKey(today)) {
      final key = '${prefix}_today';
      _expandedGroups.putIfAbsent(key, () => true);
      result.add(HandoverReportGroup(
        type: HandoverReportGroupType.today,
        title: 'Сегодня',
        key: key,
        count: byDay[today]!.length,
        startDate: today,
        children: byDay[today]!,
      ));
    }

    // Вчера
    if (byDay.containsKey(yesterday)) {
      final key = '${prefix}_yesterday';
      _expandedGroups.putIfAbsent(key, () => false);
      result.add(HandoverReportGroup(
        type: HandoverReportGroupType.yesterday,
        title: 'Вчера (${yesterday.day})',
        key: key,
        count: byDay[yesterday]!.length,
        startDate: yesterday,
        children: byDay[yesterday]!,
      ));
    }

    // Дни 2-6 дней назад (отдельные строки)
    for (final day in sortedDays) {
      if (day == today || day == yesterday) continue;
      if (day.isAfter(weekAgo) || day == weekAgo) {
        final key = '${prefix}_day_${day.year}_${day.month}_${day.day}';
        _expandedGroups.putIfAbsent(key, () => false);
        result.add(HandoverReportGroup(
          type: HandoverReportGroupType.day,
          title: _formatDayTitle(day),
          key: key,
          count: byDay[day]!.length,
          startDate: day,
          children: byDay[day]!,
        ));
      }
    }

    // Недели и месяцы (7+ дней назад)
    Map<String, Map<String, Map<DateTime, List<ShiftHandoverReport>>>> byMonthWeek = {};

    for (final day in sortedDays) {
      if (day == today || day == yesterday) continue;
      if (day.isAfter(weekAgo) || day == weekAgo) continue;

      final monthKey = '${day.year}-${day.month.toString().padLeft(2, '0')}';
      final weekStart = _getWeekStart(day);
      final weekKey = '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';

      byMonthWeek.putIfAbsent(monthKey, () => {});
      byMonthWeek[monthKey]!.putIfAbsent(weekKey, () => {});
      byMonthWeek[monthKey]![weekKey]![day] = byDay[day]!;
    }

    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    // Сортируем месяцы (новые первые)
    final sortedMonths = byMonthWeek.keys.toList()..sort((a, b) => b.compareTo(a));

    for (final monthKey in sortedMonths) {
      final weeks = byMonthWeek[monthKey]!;
      final sortedWeeks = weeks.keys.toList()..sort((a, b) => b.compareTo(a));

      if (monthKey == currentMonth) {
        // Текущий месяц - показываем недели напрямую
        for (final weekKey in sortedWeeks) {
          final weekDays = weeks[weekKey]!;
          final sortedWeekDays = weekDays.keys.toList()..sort((a, b) => b.compareTo(a));

          // Создаём дни внутри недели
          final dayGroups = sortedWeekDays.map((day) {
            final dayKey = '${prefix}_week_${weekKey}_day_${day.year}_${day.month}_${day.day}';
            _expandedGroups.putIfAbsent(dayKey, () => false);
            return HandoverReportGroup(
              type: HandoverReportGroupType.day,
              title: _formatDayTitle(day),
              key: dayKey,
              count: weekDays[day]!.length,
              startDate: day,
              children: weekDays[day]!,
            );
          }).toList();

          final weekStart = _getWeekStart(sortedWeekDays.last);
          final weekEnd = weekStart.add(const Duration(days: 6));
          final totalCount = dayGroups.fold(0, (sum, d) => sum + d.count);

          final wKey = '${prefix}_week_$weekKey';
          _expandedGroups.putIfAbsent(wKey, () => false);
          result.add(HandoverReportGroup(
            type: HandoverReportGroupType.week,
            title: 'Неделя ${weekStart.day}-${weekEnd.day} ${_monthNamesGenitive[weekStart.month]}',
            key: wKey,
            count: totalCount,
            startDate: weekStart,
            children: dayGroups,
          ));
        }
      } else {
        // Прошлый месяц - группируем всё в месяц
        final parts = monthKey.split('-');
        final monthDate = DateTime(int.parse(parts[0]), int.parse(parts[1]));

        final allWeeks = sortedWeeks.map((weekKey) {
          final weekDays = weeks[weekKey]!;
          final sortedWeekDays = weekDays.keys.toList()..sort((a, b) => b.compareTo(a));

          final dayGroups = sortedWeekDays.map((day) {
            final dayKey = '${prefix}_month_${monthKey}_week_${weekKey}_day_${day.year}_${day.month}_${day.day}';
            _expandedGroups.putIfAbsent(dayKey, () => false);
            return HandoverReportGroup(
              type: HandoverReportGroupType.day,
              title: _formatDayTitle(day),
              key: dayKey,
              count: weekDays[day]!.length,
              startDate: day,
              children: weekDays[day]!,
            );
          }).toList();

          final weekStart = _getWeekStart(sortedWeekDays.last);
          final weekEnd = weekStart.add(const Duration(days: 6));
          final totalCount = dayGroups.fold(0, (sum, d) => sum + d.count);

          final wKey = '${prefix}_month_${monthKey}_week_$weekKey';
          _expandedGroups.putIfAbsent(wKey, () => false);
          return HandoverReportGroup(
            type: HandoverReportGroupType.week,
            title: 'Неделя ${weekStart.day}-${weekEnd.day}',
            key: wKey,
            count: totalCount,
            startDate: weekStart,
            children: dayGroups,
          );
        }).toList();

        final monthTotalCount = allWeeks.fold(0, (sum, w) => sum + w.count);

        final mKey = '${prefix}_month_$monthKey';
        _expandedGroups.putIfAbsent(mKey, () => false);
        result.add(HandoverReportGroup(
          type: HandoverReportGroupType.month,
          title: '${_monthNamesNominative[monthDate.month]} ${monthDate.year}',
          key: mKey,
          count: monthTotalCount,
          startDate: monthDate,
          children: allWeeks,
        ));
      }
    }

    return result;
  }


  /// Построить сгруппированный список отчётов по сдаче смены
  Widget _buildGroupedHandoverReportsList(List<ShiftHandoverReport> reports, {required bool isConfirmed, required String prefix}) {
    final groups = _groupHandoverReports(reports, prefix);

    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isConfirmed ? Icons.check_circle_outline : Icons.cancel_outlined,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              isConfirmed ? 'Нет подтверждённых отчётов' : 'Нет не подтверждённых отчётов',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: groups.length,
      itemBuilder: (context, index) => _buildHandoverGroupTile(groups[index], 0),
    );
  }

  /// Построить сгруппированный список не подтверждённых отчётов
  Widget _buildGroupedExpiredReportsList() {
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

    return _buildGroupedHandoverReportsList(reports, isConfirmed: false, prefix: 'expired');
  }

  /// Рекурсивно построить плитку группы для отчётов сдачи смены
  Widget _buildHandoverGroupTile(HandoverReportGroup group, int depth) {
    final isExpanded = _expandedGroups[group.key] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGroupHeader(group, depth),
        if (isExpanded)
          ...group.children.map((child) {
            if (child is HandoverReportGroup) {
              return Padding(
                padding: EdgeInsets.only(left: 12.0 * (depth + 1)),
                child: _buildHandoverGroupTile(child, depth + 1),
              );
            } else if (child is ShiftHandoverReport) {
              return Padding(
                padding: EdgeInsets.only(left: 12.0 * (depth + 1)),
                child: _buildHandoverReportCard(child),
              );
            }
            return const SizedBox();
          }),
      ],
    );
  }

  /// Построить заголовок группы
  Widget _buildGroupHeader(HandoverReportGroup group, int depth) {
    final color = _getGroupColor(group.type);
    final icon = _getGroupIcon(group.type);
    final isExpanded = _expandedGroups[group.key] ?? false;

    return GestureDetector(
      onTap: () {
        setState(() {
          _expandedGroups[group.key] = !isExpanded;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isExpanded ? color.withOpacity(0.15) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isExpanded ? color : color.withOpacity(0.3),
            width: isExpanded ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedRotation(
              turns: isExpanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.chevron_right,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                group.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isExpanded ? color : Colors.white.withOpacity(0.85),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${group.count}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Построить карточку отчёта по сдаче смены
  Widget _buildHandoverReportCard(ShiftHandoverReport report) {
    final isConfirmed = report.isConfirmed;

    return GestureDetector(
      onTap: () async {
        final allReports = await ShiftHandoverReport.loadAllLocal();
        if (!mounted) return;

        final updatedReport = allReports.firstWhere(
          (r) => r.id == report.id,
          orElse: () => report,
        );

        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShiftHandoverReportViewPage(report: updatedReport),
          ),
        ).then((_) => _loadData());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isConfirmed ? Colors.green.withOpacity(0.15) : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isConfirmed ? Colors.green.withOpacity(0.15) : _emerald.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isConfirmed ? Icons.check : Icons.assignment_turned_in,
                color: isConfirmed ? Colors.green : _gold,
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
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person, size: 14, color: Colors.white.withOpacity(0.4)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          report.employeeName,
                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${report.createdAt.hour.toString().padLeft(2, '0')}:${report.createdAt.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                      ),
                    ],
                  ),
                  if (isConfirmed && report.rating != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Оценка: ', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getRatingColor(report.rating!),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${report.rating}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (report.confirmedByAdmin != null) ...[
                          const Spacer(),
                          Text(
                            report.confirmedByAdmin!,
                            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ],
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

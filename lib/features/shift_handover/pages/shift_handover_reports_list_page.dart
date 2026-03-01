import 'package:flutter/material.dart';
import '../../../core/utils/cache_manager.dart';
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
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/report_list_widgets.dart';
import '../widgets/handover_report_card.dart';
import '../widgets/pending_shifts_list.dart';
import '../widgets/overdue_shifts_list.dart';

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
  bool _isLoading = true;
  String? _selectedShop;
  String? _selectedEmployee;
  DateTime? _selectedDate;
  List<ShiftHandoverReport> _allReports = [];
  List<Shop> _allShops = [];
  List<PendingShiftHandover> _pendingHandovers = []; // Непройденные сдачи смен (в срок)
  List<PendingShiftHandover> _overdueHandovers = []; // Просроченные сдачи смен (не в срок)
  List<ShiftHandoverReport> _expiredReports = [];
  ShiftHandoverPointsSettings? _handoverSettings; // Настройки временных окон
  int _overdueViewedCount = 0; // Количество просмотренных просроченных (для бейджа)

  // Состояние раскрытия групп (ключ = уникальный идентификатор группы)
  final Map<String, bool> _expandedGroups = {};

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
      final pendingReports = await PendingShiftHandoverService.getPendingReportsForCurrentUser();
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
      final failedReports = await PendingShiftHandoverService.getFailedReportsForCurrentUser();
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
    Logger.info('Загрузка отчетов сдачи смены...');

    // Step 1: Show cached data instantly
    final cached = CacheManager.get<Map<String, dynamic>>('reports_shift_handover');
    if (cached != null && mounted) {
      setState(() {
        _allReports = cached['allReports'] as List<ShiftHandoverReport>;
        _allShops = cached['allShops'] as List<Shop>;
        _pendingHandovers = cached['pendingHandovers'] as List<PendingShiftHandover>;
        _overdueHandovers = cached['overdueHandovers'] as List<PendingShiftHandover>;
        _expiredReports = cached['expiredReports'] as List<ShiftHandoverReport>;
        _handoverSettings = cached['handoverSettings'] as ShiftHandoverPointsSettings?;
        _isLoading = false;
      });
    }

    // Step 2: Fetch fresh data in parallel (5 requests)
    ShiftHandoverPointsSettings? settings;
    List<Shop> shops = [];
    List<ShiftHandoverReport> expiredReports = [];
    List<ShiftHandoverReport> serverReports = [];
    List<ShiftHandoverReport> localReports = [];

    await Future.wait([
      () async {
        try {
          settings = await PointsSettingsService.getShiftHandoverPointsSettings();
        } catch (e) {
          Logger.error('Ошибка загрузки настроек времени', e);
        }
      }(),
      () async {
        try { shops = await ShopService.getShopsForCurrentUser(); }
        catch (e) { Logger.error('Ошибка загрузки магазинов', e); }
      }(),
      () async {
        try { expiredReports = await ShiftHandoverReportService.getExpiredReportsForCurrentUser(); }
        catch (e) { Logger.error('Ошибка загрузки просроченных отчётов', e); }
      }(),
      () async {
        try { serverReports = await ShiftHandoverReportService.getReportsForCurrentUser(); }
        catch (e) { Logger.error('Ошибка загрузки отчетов с сервера', e); }
      }(),
      () async {
        try { localReports = await ShiftHandoverReport.loadAllLocal(); }
        catch (e) { Logger.error('Ошибка загрузки локальных отчетов', e); }
      }(),
    ]);

    // Apply settings
    _handoverSettings = settings ?? _handoverSettings ?? ShiftHandoverPointsSettings.defaults();
    _allShops = shops;
    _expiredReports = expiredReports;

    // Merge server + local reports
    final Map<String, ShiftHandoverReport> reportsMap = {};
    for (var report in localReports) {
      reportsMap[report.id] = report;
    }
    for (var report in serverReports) {
      reportsMap[report.id] = report;
    }
    _allReports = reportsMap.values.toList();
    _allReports.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    await _loadPendingHandovers();
    Logger.success('Всего отчетов после объединения: ${_allReports.length}');

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });

    // Step 3: Save to cache
    CacheManager.set('reports_shift_handover', {
      'allReports': _allReports,
      'allShops': _allShops,
      'pendingHandovers': _pendingHandovers,
      'overdueHandovers': _overdueHandovers,
      'expiredReports': _expiredReports,
      'handoverSettings': _handoverSettings,
    });
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
      // Exclude scheduler-created records (no employee name)
      if (r.employeeName.isEmpty) return false;
      // Exclude pending/failed/rejected/expired records
      if (r.status == 'pending' || r.status == 'failed' || r.status == 'rejected' || r.status == 'expired') return false;
      // Показываем только отчёты, которые ожидают менее 5 часов
      final hours = now.difference(r.createdAt).inHours;
      return hours < 5;
    }).toList();
    return _applyFilters(pending);
  }

  /// Просроченные отчёты (rejected + ожидающие более 5 часов)
  List<ShiftHandoverReport> get _overdueUnconfirmedReports {
    final now = DateTime.now();
    return _allReports.where((r) {
      if (r.isConfirmed) return false;
      // rejected-отчёты всегда показываем в «Просроченные»
      if (r.status == 'rejected') return true;
      // Exclude scheduler-created records (no employee name)
      if (r.employeeName.isEmpty) return false;
      // Exclude pending/failed/expired records
      if (r.status == 'pending' || r.status == 'failed' || r.status == 'expired') return false;
      final hours = now.difference(r.createdAt).inHours;
      return hours >= 5;
    }).toList();
  }

  /// Подтверждённые отчёты
  List<ShiftHandoverReport> get _confirmedReports {
    final confirmed = _allReports.where((r) => r.isConfirmed).toList();
    return _applyFilters(confirmed);
  }

  List<String> get _uniqueShops {
    final shops = <String>{};
    for (var r in _allReports) {
      if (r.shopAddress.trim().isNotEmpty) shops.add(r.shopAddress);
    }
    return shops.toList()..sort();
  }

  List<String> get _uniqueEmployees {
    final employees = <String>{};
    for (var r in _allReports) {
      if (r.employeeName.trim().isNotEmpty) employees.add(r.employeeName);
    }
    return employees.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
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
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          PendingShiftsList(
                            pendingHandovers: _pendingHandovers,
                            settings: _handoverSettings ?? ShiftHandoverPointsSettings.defaults(),
                          ),
                          OverdueShiftsList(
                            overdueHandovers: _overdueHandovers,
                            settings: _handoverSettings ?? ShiftHandoverPointsSettings.defaults(),
                          ),
                          _buildGroupedHandoverReportsList(_awaitingReports, isConfirmed: false, prefix: 'awaiting'),
                          _buildGroupedHandoverReportsList(_confirmedReports, isConfirmed: true, prefix: 'confirmed'),
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
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 8.w, 12.h),
      child: Row(
        children: [
          // Кнопка назад
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
          // Заголовок
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Отчёты (Сдача Смены)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Всего: ${_allReports.length} отчётов',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13.sp,
                  ),
                ),
              ],
            ),
          ),
          // Кнопка обновления
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.white),
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
      padding: EdgeInsets.fromLTRB(8.w, 0.h, 8.w, 8.h),
      child: Column(
        children: [
          // Первый ряд: 3 вкладки
          Row(
            children: [
              ReportTabButton(
                isSelected: _tabController.index == 0,
                onTap: () { _tabController.animateTo(0); if (mounted) setState(() {}); },
                icon: Icons.schedule,
                label: 'Не пройдены',
                count: _pendingHandovers.length,
                accentColor: Colors.orange,
              ),
              SizedBox(width: 6),
              ReportTabButton(
                isSelected: _tabController.index == 1,
                onTap: () { _tabController.animateTo(1); if (mounted) setState(() {}); },
                icon: Icons.warning_amber,
                label: 'Не в срок',
                count: _overdueHandovers.length,
                accentColor: Colors.red,
                badge: _overdueUnviewedBadge,
              ),
              SizedBox(width: 6),
              ReportTabButton(
                isSelected: _tabController.index == 2,
                onTap: () { _tabController.animateTo(2); if (mounted) setState(() {}); },
                icon: Icons.hourglass_empty,
                label: 'Ожидают',
                count: _awaitingReports.length,
                accentColor: Colors.blue,
              ),
            ],
          ),
          SizedBox(height: 6),
          // Второй ряд: 2 вкладки
          Row(
            children: [
              ReportTabButton(
                isSelected: _tabController.index == 3,
                onTap: () { _tabController.animateTo(3); if (mounted) setState(() {}); },
                icon: Icons.check_circle,
                label: 'Подтверждённые',
                count: _allReports.where((r) => r.isConfirmed).length,
                accentColor: Colors.green,
              ),
              SizedBox(width: 6),
              ReportTabButton(
                isSelected: _tabController.index == 4,
                onTap: () { _tabController.animateTo(4); if (mounted) setState(() {}); },
                icon: Icons.timer_off,
                label: 'Просроченные',
                count: _expiredReports.length + _overdueUnconfirmedReports.length,
                accentColor: Colors.orange.shade700,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Секция фильтров (компактная) — использует общий ReportFiltersWidget
  Widget _buildFiltersSection() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      child: ReportFiltersWidget(
        shops: _uniqueShops,
        employees: _uniqueEmployees,
        selectedShop: _selectedShop,
        selectedEmployee: _selectedEmployee,
        selectedDate: _selectedDate,
        onShopChanged: (v) { if (mounted) setState(() => _selectedShop = v); },
        onEmployeeChanged: (v) { if (mounted) setState(() => _selectedEmployee = v); },
        onDateChanged: (v) { if (mounted) setState(() => _selectedDate = v); },
        onReset: () {
          if (mounted) {
            setState(() {
              _selectedShop = null;
              _selectedEmployee = null;
              _selectedDate = null;
            });
          }
        },
      ),
    );
  }

  /// Виджет для списка непройденных сдач смен (в срок)




  // ============================================================
  // ИЕРАРХИЧЕСКАЯ ГРУППИРОВКА ОТЧЁТОВ
  // ============================================================

  /// Названия месяцев в родительном падеже
  static final _monthNamesGenitive = [
    '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
  ];

  /// Названия месяцев в именительном падеже
  static final _monthNamesNominative = [
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
    final yesterday = today.subtract(Duration(days: 1));
    final weekAgo = today.subtract(Duration(days: 7));

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
          final weekEnd = weekStart.add(Duration(days: 6));
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
          final weekEnd = weekStart.add(Duration(days: 6));
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
      return ReportEmptyState(
        icon: isConfirmed ? Icons.check_circle_outline : Icons.cancel_outlined,
        title: isConfirmed ? 'Нет подтверждённых отчётов' : 'Нет неподтверждённых отчётов',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(12.w),
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
                padding: EdgeInsets.only(left: 12.0.w * (depth + 1)),
                child: _buildHandoverGroupTile(child, depth + 1),
              );
            } else if (child is ShiftHandoverReport) {
              return Padding(
                padding: EdgeInsets.only(left: 12.0.w * (depth + 1)),
                child: HandoverReportCard(
                  report: child,
                  onTap: () async {
                    final allReports = await ShiftHandoverReport.loadAllLocal();
                    if (!mounted) return;
                    final updatedReport = allReports.firstWhere(
                      (r) => r.id == child.id,
                      orElse: () => child,
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ShiftHandoverReportViewPage(
                          report: updatedReport,
                          isReadOnly: updatedReport.status == 'rejected' || updatedReport.status == 'expired',
                        ),
                      ),
                    ).then((_) => _loadData());
                  },
                ),
              );
            }
            return SizedBox();
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
        if (mounted) {
          setState(() {
            _expandedGroups[group.key] = !isExpanded;
          });
        }
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isExpanded ? color.withOpacity(0.15) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isExpanded ? color : color.withOpacity(0.3),
            width: isExpanded ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedRotation(
              turns: isExpanded ? 0.25 : 0,
              duration: Duration(milliseconds: 200),
              child: Icon(
                Icons.chevron_right,
                color: color,
                size: 24,
              ),
            ),
            SizedBox(width: 8),
            Container(
              padding: EdgeInsets.all(6.w),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                group.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.sp,
                  color: isExpanded ? color : Colors.white.withOpacity(0.85),
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Text(
                '${group.count}',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.sp,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

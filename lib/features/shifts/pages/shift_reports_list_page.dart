import 'package:flutter/material.dart';
import '../models/shift_report_model.dart';
import '../models/pending_shift_report_model.dart';
import '../models/shift_question_model.dart';
import '../services/shift_report_service.dart';
import '../services/shift_question_service.dart';
import 'shift_report_view_page.dart';
import 'shift_summary_report_page.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/report_notification_service.dart';
import '../../../features/shops/models/shop_model.dart';
import '../../../features/efficiency/models/points_settings_model.dart';
import '../../../features/efficiency/services/points_settings_service.dart';

/// Модель строки сводного отчёта (дата + смена)
class ShiftSummaryItem {
  final DateTime date;
  final String shiftType; // 'morning' | 'evening'
  final String shiftName; // 'Утренняя' | 'Вечерняя'
  final int passedCount;  // Сколько магазинов прошли
  final int totalCount;   // Всего магазинов
  final List<ShiftReport> reports; // Отчёты за эту смену

  ShiftSummaryItem({
    required this.date,
    required this.shiftType,
    required this.shiftName,
    required this.passedCount,
    required this.totalCount,
    required this.reports,
  });

  String get displayTitle {
    const months = ['', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
                   'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    return '${date.day} ${months[date.month]}, $shiftName ($passedCount/$totalCount)';
  }
}

/// Тип группы для иерархической группировки отчётов
enum ReportGroupType { today, yesterday, day, week, month }

/// Группа отчётов для иерархического отображения
class ReportGroup {
  final ReportGroupType type;
  final String title;
  final String key; // Уникальный ключ для хранения состояния
  final int count;
  final DateTime startDate;
  final List<dynamic> children; // List<ShiftReport> или List<ReportGroup>

  ReportGroup({
    required this.type,
    required this.title,
    required this.key,
    required this.count,
    required this.startDate,
    required this.children,
  });
}

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
  List<PendingShiftReport> _failedShifts = []; // Просроченные непройденные пересменки
  List<ShiftReport> _expiredReports = [];
  List<Shop> _allShops = [];
  ShiftPointsSettings? _shiftSettings;
  int _failedShiftsBadgeCount = 0;
  List<ShiftSummaryItem> _summaryItems = []; // Сводные данные за 30 дней

  // Состояние раскрытия групп (ключ = уникальный идентификатор группы)
  final Map<String, bool> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadSettings();
    _loadData();
    // Отмечаем все уведомления этого типа как просмотренные
    ReportNotificationService.markAllAsViewed(reportType: ReportType.shiftHandover);
  }

  void _onTabChanged() {
    // Когда открываем вкладку "Не прошли" (index 1), обнуляем счётчик
    if (_tabController.index == 1 && _failedShiftsBadgeCount > 0) {
      setState(() {
        _failedShiftsBadgeCount = 0;
      });
    } else {
      // Обновляем UI для подсветки активной вкладки
      setState(() {});
    }
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await PointsSettingsService.getShiftPointsSettings();
      setState(() {
        _shiftSettings = settings;
      });
      Logger.success('Загружены настройки пересменки: утро ${settings.morningStartTime}-${settings.morningEndTime}, вечер ${settings.eveningStartTime}-${settings.eveningEndTime}');
    } catch (e) {
      Logger.error('Ошибка загрузки настроек пересменки', e);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
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

    // Загружаем магазины для вычисления непройденных пересменок
    try {
      final shops = await Shop.loadShopsFromServer();
      _allShops = shops;
      Logger.success('Загружено магазинов: ${shops.length}');
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов', e);
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

      // Вычисляем непройденные пересменки на клиенте
      _calculatePendingShifts();
      // Вычисляем сводные данные за 30 дней
      _calculateSummaryItems();

      Logger.success('Всего отчетов после объединения: ${_allReports.length}');
      setState(() {});
    } catch (e) {
      Logger.error('Ошибка загрузки отчетов', e);
      _allReports = await ShiftReport.loadAllReports();
      _calculatePendingShifts();
      _calculateSummaryItems();
      setState(() {});
    }
  }

  /// Определить тип смены по времени отчёта
  String _getShiftType(DateTime time) {
    final hour = time.hour;
    // Утренняя смена: 7:00 - 13:59
    // Вечерняя смена: 14:00 - 23:59 и 0:00 - 6:59
    if (hour >= 7 && hour < 14) {
      return 'morning';
    }
    return 'evening';
  }

  /// Вычислить непройденные пересменки за сегодня (магазин + смена)
  void _calculatePendingShifts() {
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    // Получаем дедлайны из настроек или используем значения по умолчанию
    final morningDeadline = _shiftSettings?.morningEndTime ?? '13:00';
    final eveningDeadline = _shiftSettings?.eveningEndTime ?? '23:00';

    Logger.info('Вычисление непройденных пересменок. Магазинов: ${_allShops.length}');
    Logger.info('Дедлайны: утро до $morningDeadline, вечер до $eveningDeadline');

    // Собираем пройденные пересменки за сегодня (ключ: магазин_смена)
    final completedShifts = <String>{};
    for (final report in _allReports) {
      final reportDate = '${report.createdAt.year}-${report.createdAt.month.toString().padLeft(2, '0')}-${report.createdAt.day.toString().padLeft(2, '0')}';
      if (reportDate == todayStr) {
        final shiftType = _getShiftType(report.createdAt);
        final key = '${report.shopAddress.toLowerCase().trim()}_$shiftType';
        completedShifts.add(key);
        Logger.debug('Найден отчёт за сегодня: ${report.shopAddress} - $shiftType');
      }
    }

    Logger.info('Пройденных пересменок сегодня: ${completedShifts.length}');

    // Формируем списки: ожидающие и просроченные
    final allPending = <PendingShiftReport>[];

    for (final shop in _allShops) {
      final shopKey = shop.address.toLowerCase().trim();

      // Утренняя смена
      final morningKey = '${shopKey}_morning';
      if (!completedShifts.contains(morningKey)) {
        allPending.add(PendingShiftReport(
          id: 'pending_${shop.id}_morning',
          shopAddress: shop.address,
          shiftType: 'morning',
          shiftLabel: 'Утро',
          date: todayStr,
          deadline: morningDeadline,
          status: 'pending',
          createdAt: today,
        ));
      }

      // Вечерняя смена
      final eveningKey = '${shopKey}_evening';
      if (!completedShifts.contains(eveningKey)) {
        allPending.add(PendingShiftReport(
          id: 'pending_${shop.id}_evening',
          shopAddress: shop.address,
          shiftType: 'evening',
          shiftLabel: 'Вечер',
          date: todayStr,
          deadline: eveningDeadline,
          status: 'pending',
          createdAt: today,
        ));
      }
    }

    // Разделяем на ожидающие и просроченные
    _pendingShifts = allPending.where((p) => !p.isOverdue).toList();
    _failedShifts = allPending.where((p) => p.isOverdue).toList();

    // Обновляем счётчик бейджа (только если не на вкладке "Не прошли")
    if (_tabController.index != 1) {
      _failedShiftsBadgeCount = _failedShifts.length;
    }

    // Сортируем: сначала по магазину, потом по смене
    _pendingShifts.sort((a, b) {
      final shopCompare = a.shopAddress.compareTo(b.shopAddress);
      if (shopCompare != 0) return shopCompare;
      return a.shiftType == 'morning' ? -1 : 1;
    });

    _failedShifts.sort((a, b) {
      final shopCompare = a.shopAddress.compareTo(b.shopAddress);
      if (shopCompare != 0) return shopCompare;
      return a.shiftType == 'morning' ? -1 : 1;
    });

    Logger.info('Ожидающих пересменок: ${_pendingShifts.length}');
    Logger.info('Просроченных пересменок: ${_failedShifts.length}');
  }

  /// Вычислить сводные данные за последние 30 дней
  void _calculateSummaryItems() {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    _summaryItems = [];

    // Группируем отчёты по дням и сменам
    Map<String, List<ShiftReport>> grouped = {};

    for (final report in _allReports) {
      if (report.createdAt.isBefore(thirtyDaysAgo)) continue;

      final dateKey = '${report.createdAt.year}-${report.createdAt.month.toString().padLeft(2, '0')}-${report.createdAt.day.toString().padLeft(2, '0')}';
      final shiftType = _getShiftType(report.createdAt);
      final key = '${dateKey}_$shiftType';

      grouped.putIfAbsent(key, () => []).add(report);
    }

    // Создаём строки для каждого дня и смены за 30 дней
    for (int i = 0; i < 30; i++) {
      final date = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      // Утренняя смена
      final morningKey = '${dateKey}_morning';
      final morningReports = grouped[morningKey] ?? [];
      _summaryItems.add(ShiftSummaryItem(
        date: date,
        shiftType: 'morning',
        shiftName: 'Утренняя',
        passedCount: morningReports.length,
        totalCount: _allShops.length,
        reports: morningReports,
      ));

      // Вечерняя смена
      final eveningKey = '${dateKey}_evening';
      final eveningReports = grouped[eveningKey] ?? [];
      _summaryItems.add(ShiftSummaryItem(
        date: date,
        shiftType: 'evening',
        shiftName: 'Вечерняя',
        passedCount: eveningReports.length,
        totalCount: _allShops.length,
        reports: eveningReports,
      ));
    }

    Logger.info('Сводных записей за 30 дней: ${_summaryItems.length}');
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

  /// Построение двухрядных вкладок (3 сверху, 2 снизу)
  Widget _buildTwoRowTabs() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        children: [
          // Первый ряд: 3 вкладки
          Row(
            children: [
              _buildTabButton(0, Icons.schedule, 'Ожидают', _pendingShifts.length, Colors.orange),
              const SizedBox(width: 6),
              _buildTabButton(1, Icons.warning_amber, 'Не прошли', _failedShifts.length, Colors.red, badge: _failedShiftsBadgeCount),
              const SizedBox(width: 6),
              _buildTabButton(2, Icons.hourglass_empty, 'Проверка', _awaitingReports.length, Colors.blue),
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
          const SizedBox(height: 6),
          // Третий ряд: 1 вкладка "Отчёт"
          Row(
            children: [
              _buildTabButton(5, Icons.table_chart, 'Отчёт', _summaryItems.where((s) => s.passedCount > 0).length, Colors.deepPurple),
            ],
          ),
        ],
      ),
    );
  }

  /// Построение одной кнопки-вкладки (компактная версия)
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
              color: isSelected ? null : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? accentColor : Colors.white30,
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

  // Градиентные цвета для страницы
  static const _gradientColors = [Color(0xFF00695C), Color(0xFF004D40)];

  /// Красивый заголовок страницы
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Row(
        children: [
          // Кнопка назад
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                  'Отчёты по пересменкам',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Всего отчётов: ${_allReports.length}',
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
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
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

  /// Секция фильтров
  Widget _buildFiltersSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          // Компактная строка фильтров
          Row(
            children: [
              // Магазин
              Expanded(
                child: FutureBuilder<List<String>>(
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
                ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: _gradientColors[1]),
          hint: Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Text(hint, style: const TextStyle(fontSize: 13)),
            ],
          ),
          selectedItemBuilder: (context) {
            return [
              Row(
                children: [
                  Icon(icon, size: 18, color: _gradientColors[1]),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Все', style: TextStyle(fontSize: 13))),
                ],
              ),
              ...items.map((item) => Row(
                children: [
                  Icon(icon, size: 18, color: _gradientColors[1]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )),
            ];
          },
          items: [
            DropdownMenuItem<String>(value: null, child: Text('Все $hint')),
            ...items.map((item) => DropdownMenuItem(value: item, child: Text(item))),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 18, color: _gradientColors[1]),
            const SizedBox(width: 8),
            Text(
              _selectedDate == null
                  ? 'Дата'
                  : '${_selectedDate!.day}.${_selectedDate!.month}',
              style: const TextStyle(fontSize: 13),
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

  /// Красивый пустой стейт
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _gradientColors,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Красивый заголовок
              _buildHeader(),
              // Вкладки
              _buildTwoRowTabs(),
              // Фильтры (только для вкладок с отчётами, не для "Ожидают" и "Не прошли")
              if (_tabController.index >= 2) _buildFiltersSection(),

              // Вкладки с отчётами
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Вкладка 0: "Ожидают" - непройденные пересменки (время ещё не истекло)
                    _buildPendingShiftsList(),
                    // Вкладка 1: "Не прошли" - просроченные пересменки
                    _buildFailedShiftsList(),
                    // Вкладка 2: "На проверке" - сданные отчёты ожидают подтверждения
                    _buildReportsList(_awaitingReports, isPending: true),
                    // Вкладка 3: "Подтверждённые" (с иерархической группировкой)
                    _buildGroupedReportsList(_confirmedReports, isConfirmed: true),
                    // Вкладка 4: "Не подтверждённые" (с иерархической группировкой)
                    _buildGroupedReportsList([..._expiredReports, ..._overdueUnconfirmedReports], isConfirmed: false),
                    // Вкладка 5: "Отчёт" - сводные данные за 30 дней
                    _buildSummaryReportsList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Виджет для списка непройденных пересменок (ещё не просроченных)
  Widget _buildPendingShiftsList() {
    if (_pendingShifts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'Нет ожидающих пересменок',
        subtitle: 'Все пересменки пройдены или просрочены',
        color: Colors.green,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pendingShifts.length,
      itemBuilder: (context, index) {
        final pending = _pendingShifts[index];
        final isMorning = pending.shiftType == 'morning';
        final shiftColor = isMorning ? Colors.orange : Colors.indigo;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: shiftColor.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    // Иконка смены
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isMorning
                              ? [Colors.orange.shade300, Colors.orange.shade600]
                              : [Colors.indigo.shade300, Colors.indigo.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: shiftColor.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        isMorning ? Icons.wb_sunny : Icons.nights_stay,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Информация
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pending.shopAddress,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: shiftColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: shiftColor.withOpacity(0.3)),
                                ),
                                child: Text(
                                  pending.shiftLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: shiftColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                'до ${pending.deadline}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Статус
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.schedule,
                        color: Colors.orange,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Виджет для списка просроченных (непройденных) пересменок
  Widget _buildFailedShiftsList() {
    if (_failedShifts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.thumb_up,
        title: 'Нет просроченных пересменок',
        subtitle: 'Все пересменки пройдены вовремя',
        color: Colors.green,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _failedShifts.length,
      itemBuilder: (context, index) {
        final failed = _failedShifts[index];
        final isMorning = failed.shiftType == 'morning';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.red.shade50, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Иконка с предупреждением
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade400, Colors.red.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        isMorning ? Icons.wb_sunny : Icons.nights_stay,
                        color: Colors.white,
                        size: 24,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.error, color: Colors.red, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Информация
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        failed.shopAddress,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isMorning ? Colors.orange.withOpacity(0.2) : Colors.indigo.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              failed.shiftLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isMorning ? Colors.orange.shade800 : Colors.indigo.shade800,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ПРОСРОЧЕНО',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.red[400]),
                          const SizedBox(width: 4),
                          Text(
                            'Дедлайн: ${failed.deadline}',
                            style: TextStyle(fontSize: 12, color: Colors.red[600]),
                          ),
                          if (_shiftSettings != null) ...[
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${_shiftSettings!.missedPenalty.toStringAsFixed(1)} б.',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
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
                      Flexible(
                        child: Text(
                          '${report.confirmedAt!.day}.${report.confirmedAt!.month}.${report.confirmedAt!.year} '
                          '${report.confirmedAt!.hour}:${report.confirmedAt!.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: Colors.green),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (report.rating != null)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
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
                          ],
                        ),
                        if (report.confirmedByAdmin != null)
                          Text(
                            'Проверил: ${report.confirmedByAdmin}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
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

  /// Группировать отчёты по времени
  List<ReportGroup> _groupReports(List<ShiftReport> reports) {
    if (reports.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    List<ReportGroup> result = [];

    // Группируем по дням
    Map<DateTime, List<ShiftReport>> byDay = {};
    for (final report in reports) {
      final day = DateTime(report.createdAt.year, report.createdAt.month, report.createdAt.day);
      byDay.putIfAbsent(day, () => []).add(report);
    }

    // Сортируем дни (новые первые)
    final sortedDays = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    // Сегодня - по умолчанию развёрнуто
    if (byDay.containsKey(today)) {
      const key = 'today';
      _expandedGroups.putIfAbsent(key, () => true); // По умолчанию развёрнуто
      result.add(ReportGroup(
        type: ReportGroupType.today,
        title: 'Сегодня',
        key: key,
        count: byDay[today]!.length,
        startDate: today,
        children: byDay[today]!,
      ));
    }

    // Вчера
    if (byDay.containsKey(yesterday)) {
      const key = 'yesterday';
      _expandedGroups.putIfAbsent(key, () => false);
      result.add(ReportGroup(
        type: ReportGroupType.yesterday,
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
        final key = 'day_${day.year}_${day.month}_${day.day}';
        _expandedGroups.putIfAbsent(key, () => false);
        result.add(ReportGroup(
          type: ReportGroupType.day,
          title: _formatDayTitle(day),
          key: key,
          count: byDay[day]!.length,
          startDate: day,
          children: byDay[day]!,
        ));
      }
    }

    // Недели и месяцы (7+ дней назад)
    Map<String, Map<String, Map<DateTime, List<ShiftReport>>>> byMonthWeek = {};

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
            final dayKey = 'week_${weekKey}_day_${day.year}_${day.month}_${day.day}';
            _expandedGroups.putIfAbsent(dayKey, () => false);
            return ReportGroup(
              type: ReportGroupType.day,
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

          final wKey = 'week_$weekKey';
          _expandedGroups.putIfAbsent(wKey, () => false);
          result.add(ReportGroup(
            type: ReportGroupType.week,
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
            final dayKey = 'month_${monthKey}_week_${weekKey}_day_${day.year}_${day.month}_${day.day}';
            _expandedGroups.putIfAbsent(dayKey, () => false);
            return ReportGroup(
              type: ReportGroupType.day,
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

          final wKey = 'month_${monthKey}_week_$weekKey';
          _expandedGroups.putIfAbsent(wKey, () => false);
          return ReportGroup(
            type: ReportGroupType.week,
            title: 'Неделя ${weekStart.day}-${weekEnd.day}',
            key: wKey,
            count: totalCount,
            startDate: weekStart,
            children: dayGroups,
          );
        }).toList();

        final monthTotalCount = allWeeks.fold(0, (sum, w) => sum + w.count);

        final mKey = 'month_$monthKey';
        _expandedGroups.putIfAbsent(mKey, () => false);
        result.add(ReportGroup(
          type: ReportGroupType.month,
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

  /// Получить цвет для типа группы
  Color _getGroupColor(ReportGroupType type) {
    switch (type) {
      case ReportGroupType.today:
        return Colors.green;
      case ReportGroupType.yesterday:
        return Colors.blue;
      case ReportGroupType.day:
        return Colors.orange;
      case ReportGroupType.week:
        return Colors.purple;
      case ReportGroupType.month:
        return Colors.indigo;
    }
  }

  /// Получить иконку для типа группы
  IconData _getGroupIcon(ReportGroupType type) {
    switch (type) {
      case ReportGroupType.today:
        return Icons.today;
      case ReportGroupType.yesterday:
        return Icons.history;
      case ReportGroupType.day:
        return Icons.calendar_today;
      case ReportGroupType.week:
        return Icons.date_range;
      case ReportGroupType.month:
        return Icons.calendar_month;
    }
  }

  /// Построить сгруппированный список отчётов
  Widget _buildGroupedReportsList(List<ShiftReport> reports, {required bool isConfirmed}) {
    final groups = _groupReports(reports);

    if (groups.isEmpty) {
      return _buildEmptyState(
        icon: isConfirmed ? Icons.check_circle_outline : Icons.cancel_outlined,
        title: isConfirmed ? 'Нет подтверждённых отчётов' : 'Нет отклонённых отчётов',
        subtitle: isConfirmed
            ? 'Подтверждённые отчёты появятся здесь'
            : 'Отклонённые отчёты появятся здесь',
        color: isConfirmed ? Colors.green : Colors.grey,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: groups.length,
      itemBuilder: (context, index) => _buildGroupTile(groups[index], 0),
    );
  }

  /// Рекурсивно построить плитку группы
  Widget _buildGroupTile(ReportGroup group, int depth) {
    final isExpanded = _expandedGroups[group.key] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Заголовок группы
        _buildGroupHeader(group, depth),

        // Дети (если развёрнуто)
        if (isExpanded)
          ...group.children.map((child) {
            if (child is ReportGroup) {
              return Padding(
                padding: EdgeInsets.only(left: 12.0 * (depth + 1)),
                child: _buildGroupTile(child, depth + 1),
              );
            } else if (child is ShiftReport) {
              return Padding(
                padding: EdgeInsets.only(left: 12.0 * (depth + 1)),
                child: _buildReportCard(child),
              );
            }
            return const SizedBox();
          }),
      ],
    );
  }

  /// Построить заголовок группы
  Widget _buildGroupHeader(ReportGroup group, int depth) {
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
          color: isExpanded ? color.withOpacity(0.15) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isExpanded ? color : color.withOpacity(0.3),
            width: isExpanded ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Стрелка разворачивания
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
            // Иконка типа
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            // Название
            Expanded(
              child: Text(
                group.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isExpanded ? color : Colors.black87,
                ),
              ),
            ),
            // Счётчик
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

  /// Построить карточку отчёта
  Widget _buildReportCard(ShiftReport report) {
    final isConfirmed = report.isConfirmed;

    return GestureDetector(
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
            builder: (context) => ShiftReportViewPage(report: updatedReport),
          ),
        ).then((_) => _loadData());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isConfirmed ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Иконка
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isConfirmed ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isConfirmed ? Icons.check_circle : Icons.receipt_long,
                color: isConfirmed ? Colors.green : Colors.grey,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            // Информация
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.shopAddress,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          report.employeeName,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${report.createdAt.hour}:${report.createdAt.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  if (isConfirmed && report.rating != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('Оценка: ', style: TextStyle(fontSize: 12)),
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
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Стрелка
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // СВОДНЫЙ ОТЧЁТ ЗА 30 ДНЕЙ
  // ============================================================

  /// Проверить, является ли дата сегодняшней
  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  /// Построить список сводных отчётов за 30 дней
  Widget _buildSummaryReportsList() {
    if (_summaryItems.isEmpty) {
      return _buildEmptyState(
        icon: Icons.table_chart_outlined,
        title: 'Нет данных за последние 30 дней',
        subtitle: 'Сводные отчёты появятся здесь',
        color: Colors.deepPurple,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _summaryItems.length,
      itemBuilder: (context, index) {
        final item = _summaryItems[index];
        final isToday = _isToday(item.date);
        final allPassed = item.passedCount == item.totalCount && item.totalCount > 0;
        final nonePassed = item.passedCount == 0;
        final isMorning = item.shiftType == 'morning';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: allPassed
                  ? [Colors.green.shade50, Colors.white]
                  : nonePassed
                      ? [Colors.red.shade50, Colors.white]
                      : [Colors.white, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: allPassed
                  ? Colors.green.withOpacity(0.4)
                  : nonePassed
                      ? Colors.red.withOpacity(0.3)
                      : Colors.grey.withOpacity(0.2),
              width: isToday ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openSummaryReport(item),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Иконка смены
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isMorning
                              ? [Colors.orange.shade300, Colors.orange.shade600]
                              : [Colors.indigo.shade300, Colors.indigo.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: (isMorning ? Colors.orange : Colors.indigo).withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        isMorning ? Icons.wb_sunny : Icons.nights_stay,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Информация
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.displayTitle,
                            style: TextStyle(
                              fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            allPassed
                                ? 'Все магазины прошли'
                                : nonePassed
                                    ? 'Никто не прошёл'
                                    : 'Не прошли: ${item.totalCount - item.passedCount}',
                            style: TextStyle(
                              fontSize: 12,
                              color: allPassed
                                  ? Colors.green
                                  : nonePassed
                                      ? Colors.red
                                      : Colors.orange,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Бейдж с количеством
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: allPassed
                            ? Colors.green
                            : nonePassed
                                ? Colors.red.shade400
                                : Colors.deepPurple,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${item.passedCount}/${item.totalCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Открыть страницу сводного отчёта
  void _openSummaryReport(ShiftSummaryItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShiftSummaryReportPage(
          date: item.date,
          shiftType: item.shiftType,
          shiftName: item.shiftName,
          reports: item.reports,
          allShops: _allShops,
        ),
      ),
    );
  }
}

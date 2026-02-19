import 'package:flutter/material.dart';
import '../../../core/utils/cache_manager.dart';
import '../../employees/pages/employees_page.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../services/rko_reports_service.dart';
import 'rko_employee_reports_page.dart';
import 'rko_shop_reports_page.dart';
import '../../../core/services/multitenancy_filter_service.dart';
import '../../../core/services/report_notification_service.dart';
import '../../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Главная страница отчетов по РКО с вкладками
class RKOReportsPage extends StatefulWidget {
  const RKOReportsPage({super.key});

  @override
  State<RKOReportsPage> createState() => _RKOReportsPageState();
}

class _RKOReportsPageState extends State<RKOReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Данные
  List<Employee> _employees = [];
  List<Shop> _shops = [];
  List<dynamic> _pendingRKOs = [];
  List<dynamic> _failedRKOs = [];
  bool _isLoading = true;
  String _employeeSearchQuery = '';
  String _shopSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
    // Отмечаем все уведомления этого типа как просмотренные
    ReportNotificationService.markAllAsViewed(reportType: ReportType.rko);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<Map<String, dynamic>>('reports_rko');
    if (cached != null && mounted) {
      _employees = cached['employees'] as List<Employee>;
      _shops = cached['shops'] as List<Shop>;
      _pendingRKOs = cached['pendingRKOs'] as List<dynamic>;
      _failedRKOs = cached['failedRKOs'] as List<dynamic>;
      _isLoading = false;
      setState(() {});
    }

    // Step 2: Fetch fresh data
    try {
      final results = await Future.wait([
        EmployeesPage.loadEmployeesForNotifications(),
        ShopService.getShopsForCurrentUser(),
        RKOReportsService.getPendingRKOsForCurrentUser(),
        RKOReportsService.getFailedRKOsForCurrentUser(),
      ]);

      final allEmployees = results[0] as List<Employee>;
      final filteredEmployees = await MultitenancyFilterService.filterByEmployeePhone<Employee>(
        allEmployees,
        (emp) => emp.phone ?? '',
      );

      if (!mounted) return;
      setState(() {
        _employees = filteredEmployees;
        _shops = results[1] as List<Shop>;
        _pendingRKOs = results[2] as List<dynamic>;
        _failedRKOs = results[3] as List<dynamic>;
        _isLoading = false;
      });
      // Step 3: Save to cache
      CacheManager.set('reports_rko', {
        'employees': _employees,
        'shops': _shops,
        'pendingRKOs': _pendingRKOs,
        'failedRKOs': _failedRKOs,
      });

      Logger.success('Загружено: ${_employees.length} сотрудников, ${_shops.length} магазинов, ${_pendingRKOs.length} pending, ${_failedRKOs.length} failed');
    } catch (e) {
      Logger.error('Ошибка загрузки данных', e);
      if (cached == null && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
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
              // Заголовок
              _buildHeader(),
              // Вкладки
              _buildTwoRowTabs(),
              // Содержимое вкладок
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: AppColors.gold),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          // Вкладка 0: Отчёт по сотрудникам
                          _buildEmployeesTab(),
                          // Вкладка 1: Отчёт по магазинам
                          _buildShopsTab(),
                          // Вкладка 2: Ожидают
                          _buildPendingTab(),
                          // Вкладка 3: Не прошли
                          _buildFailedTab(),
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
              icon: Icon(Icons.arrow_back, color: Colors.white),
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
                  'Отчёты по РКО',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Сотрудников: ${_employees.length}, Магазинов: ${_shops.length}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
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

  /// Построение двухрядных вкладок
  Widget _buildTwoRowTabs() {
    return Container(
      padding: EdgeInsets.fromLTRB(8.w, 0.h, 8.w, 8.h),
      child: Column(
        children: [
          // Первый ряд: 2 вкладки
          Row(
            children: [
              _buildTabButton(0, Icons.person_rounded, 'По сотрудникам', _employees.length, Colors.blue),
              SizedBox(width: 6),
              _buildTabButton(1, Icons.store_rounded, 'По магазинам', _shops.length, Colors.orange),
            ],
          ),
          SizedBox(height: 6),
          // Второй ряд: 2 вкладки
          Row(
            children: [
              _buildTabButton(2, Icons.schedule, 'Ожидают', _pendingRKOs.length, Colors.amber),
              SizedBox(width: 6),
              _buildTabButton(3, Icons.warning_amber, 'Не прошли', _failedRKOs.length, Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  /// Построение одной кнопки-вкладки
  Widget _buildTabButton(int index, IconData icon, String label, int count, Color accentColor) {
    final isSelected = _tabController.index == index;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _tabController.animateTo(index);
            if (mounted) setState(() {});
          },
          borderRadius: BorderRadius.circular(10.r),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [accentColor.withOpacity(0.8), accentColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isSelected ? null : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(
                color: isSelected ? accentColor : Colors.white.withOpacity(0.1),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 6),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withOpacity(0.3) : accentColor.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
        padding: EdgeInsets.all(32.w),
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
              child: Icon(icon, size: 40, color: Colors.white.withOpacity(0.3)),
            ),
            SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14.sp,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ВКЛАДКА: ОТЧЁТ ПО СОТРУДНИКАМ
  // ============================================================

  Widget _buildEmployeesTab() {
    return Column(
      children: [
        // Поиск
        Padding(
          padding: EdgeInsets.all(12.w),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: TextField(
              style: TextStyle(color: Colors.white),
              cursorColor: AppColors.gold,
              decoration: InputDecoration(
                hintText: 'Поиск сотрудника...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                prefixIcon: Icon(Icons.search, color: AppColors.gold),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              ),
              onChanged: (value) {
                if (mounted) setState(() {
                  _employeeSearchQuery = value.trim().toLowerCase();
                });
              },
            ),
          ),
        ),
        // Список сотрудников
        Expanded(
          child: _employees.isEmpty
              ? _buildEmptyState(
                  icon: Icons.person_off_rounded,
                  title: 'Сотрудники не найдены',
                  subtitle: 'Добавьте сотрудников для просмотра их РКО',
                  color: Colors.blue,
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  itemCount: _employees.length,
                  itemBuilder: (context, index) {
                    final employee = _employees[index];

                    // Фильтрация по поисковому запросу
                    if (_employeeSearchQuery.isNotEmpty) {
                      final name = employee.name.toLowerCase();
                      if (!name.contains(_employeeSearchQuery)) {
                        return SizedBox.shrink();
                      }
                    }

                    return _buildEmployeeCard(employee);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmployeeCard(Employee employee) {
    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () {
            final normalizedName = employee.name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RKOEmployeeDetailPage(
                  employeeName: normalizedName,
                ),
              ),
            );
          },
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                // Аватар
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade300, Colors.blue.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                SizedBox(width: 14),
                // Информация
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.sp,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (employee.position != null && employee.position!.isNotEmpty) ...[
                        SizedBox(height: 4),
                        Text(
                          employee.position!,
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Стрелка
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppColors.gold,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ВКЛАДКА: ОТЧЁТ ПО МАГАЗИНАМ
  // ============================================================

  Widget _buildShopsTab() {
    return Column(
      children: [
        // Поиск
        Padding(
          padding: EdgeInsets.all(12.w),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: TextField(
              style: TextStyle(color: Colors.white),
              cursorColor: AppColors.gold,
              decoration: InputDecoration(
                hintText: 'Поиск магазина...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                prefixIcon: Icon(Icons.search, color: AppColors.gold),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              ),
              onChanged: (value) {
                if (mounted) setState(() {
                  _shopSearchQuery = value.trim().toLowerCase();
                });
              },
            ),
          ),
        ),
        // Список магазинов
        Expanded(
          child: _shops.isEmpty
              ? _buildEmptyState(
                  icon: Icons.store_mall_directory_outlined,
                  title: 'Магазины не найдены',
                  subtitle: 'Добавьте магазины для просмотра их РКО',
                  color: Colors.orange,
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  itemCount: _shops.length,
                  itemBuilder: (context, index) {
                    final shop = _shops[index];

                    // Фильтрация по поисковому запросу
                    if (_shopSearchQuery.isNotEmpty) {
                      final address = shop.address.toLowerCase();
                      if (!address.contains(_shopSearchQuery)) {
                        return SizedBox.shrink();
                      }
                    }

                    return _buildShopCard(shop);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildShopCard(Shop shop) {
    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RKOShopDetailPage(
                  shopAddress: shop.address,
                ),
              ),
            );
          },
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                // Иконка магазина
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade300, Colors.orange.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Icon(
                    Icons.store_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                SizedBox(width: 14),
                // Адрес
                Expanded(
                  child: Text(
                    shop.address,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.sp,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Стрелка
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppColors.gold,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ВКЛАДКА: ОЖИДАЮТ
  // ============================================================

  Widget _buildPendingTab() {
    if (_pendingRKOs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'Нет ожидающих РКО',
        subtitle: 'Все РКО обработаны',
        color: Colors.green,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(12.w),
      itemCount: _pendingRKOs.length,
      itemBuilder: (context, index) {
        final rko = _pendingRKOs[index];
        return _buildPendingRKOCard(rko);
      },
    );
  }

  Widget _buildPendingRKOCard(dynamic rko) {
    final employeeName = rko['employeeName']?.toString() ?? '';
    final shopName = rko['shopName']?.toString() ?? '';
    final shopAddress = rko['shopAddress']?.toString() ?? '';
    final amount = rko['amount']?.toString() ?? '';
    final shiftType = rko['shiftType']?.toString() ?? '';
    final deadline = rko['deadline']?.toString() ?? '';

    // Определяем что показывать в заголовке
    final title = employeeName.isNotEmpty ? employeeName : shopName;
    final subtitle = employeeName.isNotEmpty ? shopAddress : shopAddress;
    final shiftLabel = shiftType == 'morning' ? 'Утренняя смена' : 'Вечерняя смена';

    // Форматируем дедлайн
    String deadlineText = '';
    if (deadline.isNotEmpty) {
      try {
        final dt = DateTime.parse(deadline);
        deadlineText = 'до ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Row(
          children: [
            // Иконка
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber.shade300, Colors.amber.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: Icon(
                Icons.schedule,
                color: Colors.white,
                size: 26,
              ),
            ),
            SizedBox(width: 14),
            // Информация
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.sp,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      if (shiftType.isNotEmpty)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          margin: EdgeInsets.only(right: 6.w),
                          decoration: BoxDecoration(
                            color: shiftType == 'morning'
                                ? Colors.orange.withOpacity(0.1)
                                : Colors.indigo.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(
                            shiftLabel,
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w500,
                              color: shiftType == 'morning' ? Colors.orange[800] : Colors.indigo[800],
                            ),
                          ),
                        ),
                      if (deadlineText.isNotEmpty)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(
                            deadlineText,
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w500,
                              color: Colors.red[800],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Сумма
            if (amount.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Text(
                  '$amount руб.',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    color: AppColors.gold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ВКЛАДКА: НЕ ПРОШЛИ
  // ============================================================

  Widget _buildFailedTab() {
    if (_failedRKOs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.thumb_up,
        title: 'Нет отклонённых РКО',
        subtitle: 'Все РКО успешно обработаны',
        color: Colors.green,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(12.w),
      itemCount: _failedRKOs.length,
      itemBuilder: (context, index) {
        final rko = _failedRKOs[index];
        return _buildFailedRKOCard(rko);
      },
    );
  }

  Widget _buildFailedRKOCard(dynamic rko) {
    final employeeName = rko['employeeName'] ?? '';
    final shopAddress = rko['shopAddress'] ?? '';
    final amount = rko['amount']?.toString() ?? '';
    final rkoType = rko['rkoType'] ?? '';
    final reason = rko['reason'] ?? 'Причина не указана';

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(14.w),
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
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 26,
              ),
            ),
            SizedBox(width: 14),
            // Информация
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employeeName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.sp,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    shopAddress,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      if (rkoType.isNotEmpty)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            rkoType,
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w500,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      Spacer(),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: Text(
                          'ОТКЛОНЕНО',
                          style: TextStyle(
                            fontSize: 10.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    reason,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.red[600],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Сумма
            if (amount.isNotEmpty) ...[
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Text(
                  '$amount руб.',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

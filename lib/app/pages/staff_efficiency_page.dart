import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/logger.dart';
import '../../features/employees/pages/employees_page.dart';
import '../../features/employees/services/employee_service.dart';
import '../../features/employees/services/employee_registration_service.dart';
import '../../features/efficiency/models/efficiency_data_model.dart';
import '../../features/efficiency/models/manager_efficiency_model.dart';
import '../../features/efficiency/services/efficiency_data_service.dart';
import '../../features/efficiency/services/manager_efficiency_service.dart';
import '../../features/efficiency/pages/shop_efficiency_detail_page.dart';
import '../../features/efficiency/utils/efficiency_utils.dart';
import '../../features/shops/services/shop_service.dart';

// Colors per role
const _colorAdmin = AppColors.gold;
const _colorManager = AppColors.turquoise;
const _colorEmployee = AppColors.success;

/// Экран эффективности всех сотрудников (только для разработчика)
class StaffEfficiencyPage extends StatefulWidget {
  const StaffEfficiencyPage({super.key});

  @override
  State<StaffEfficiencyPage> createState() => _StaffEfficiencyPageState();
}

class _StaffEfficiencyPageState extends State<StaffEfficiencyPage>
    with SingleTickerProviderStateMixin {
  DateTime _selectedMonth = DateTime.now();
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late TabController _tabController;

  List<Employee> _admins = [];
  List<Employee> _managers = [];
  List<Employee> _employees = [];

  EfficiencyData? _efficiencyData;
  // phone → ManagerEfficiencyData
  Map<String, ManagerEfficiencyData> _adminEfficiency = {};

  // Shops tab: all shops aggregated from allRecords (unfiltered by role)
  List<EfficiencySummary> _allShopSummaries = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // Smart search: all query words must be found somewhere in the name
  bool _matchesSearch(String name) {
    if (_searchQuery.isEmpty) return true;
    final nameLower = name.toLowerCase();
    final words = _searchQuery.toLowerCase().trim().split(RegExp(r'\s+'));
    return words.every((w) => w.isEmpty || nameLower.contains(w));
  }

  Future<void> _load() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      var employees = await EmployeeService.getEmployees();

      // Фильтруем только верифицированных сотрудников
      try {
        final registrations = await EmployeeRegistrationService.getAllRegistrations();
        final verifiedPhones = <String>{};
        for (var reg in registrations) {
          if (reg.isVerified) {
            verifiedPhones.add(reg.phone.replaceAll(RegExp(r'[\s\+]'), ''));
          }
        }
        employees = employees.where((e) {
          if (e.phone == null || e.phone!.isEmpty) return false;
          final phone = e.phone!.replaceAll(RegExp(r'[\s\+]'), '');
          return verifiedPhones.contains(phone);
        }).toList();
      } catch (e) {
        Logger.error('Ошибка фильтрации верификации', e);
      }

      _admins = employees.where((e) => e.isAdmin == true && e.isManager != true).toList();
      _managers = employees.where((e) => e.isManager == true).toList();
      _employees = employees.where((e) => e.isAdmin != true && e.isManager != true).toList();

      // Sort all groups by name
      for (final list in [_admins, _managers, _employees]) {
        list.sort((a, b) => (a.employeeName ?? a.name).compareTo(b.employeeName ?? b.name));
      }

      final monthStr = '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

      // Load employee efficiency (all at once)
      final effData = await EfficiencyDataService.loadMonthData(
        _selectedMonth.year,
        _selectedMonth.month,
        forceRefresh: true,
      );

      // Load admin efficiency in parallel
      final adminFutures = _admins
          .where((a) => a.phone != null && a.phone!.isNotEmpty)
          .map((a) => ManagerEfficiencyService.getManagerEfficiency(
                phone: a.phone!,
                month: monthStr,
              ).then((data) => MapEntry(a.phone!, data)));

      final adminResults = await Future.wait(adminFutures);
      final adminMap = <String, ManagerEfficiencyData>{};
      for (final entry in adminResults) {
        if (entry.value != null) adminMap[entry.key] = entry.value!;
      }

      // Aggregate shops from allRecords (unfiltered — all shops)
      final allShops = await ShopService.getShops();
      final allAddresses = allShops.map((s) => s.address).toSet();
      final Map<String, List<EfficiencyRecord>> byShopMap = {};
      for (final record in effData.allRecords) {
        if (record.shopAddress.isEmpty) continue;
        if (!allAddresses.contains(record.shopAddress)) continue;
        byShopMap.putIfAbsent(record.shopAddress, () => []);
        byShopMap[record.shopAddress]!.add(record);
      }
      final shopSummaries = byShopMap.entries.map((entry) {
        return EfficiencySummary.fromRecords(
          entityId: entry.key,
          entityName: entry.key,
          records: entry.value,
        );
      }).toList()
        ..sort((a, b) => b.totalPoints.compareTo(a.totalPoints));

      if (mounted) {
        setState(() {
          _efficiencyData = effData;
          _adminEfficiency = adminMap;
          _allShopSummaries = shopSummaries;
        });
      }
    } catch (e) {
      Logger.error('StaffEfficiencyPage: ошибка загрузки', e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  EfficiencySummary? _getSummary(Employee e) {
    if (_efficiencyData == null) return null;
    final name = (e.employeeName ?? e.name).toLowerCase().trim();
    try {
      return _efficiencyData!.byEmployee.firstWhere(
        (s) => s.entityId == name || s.entityName.toLowerCase().trim() == name,
      );
    } catch (_) {
      return null;
    }
  }

  // Find shop efficiency for a manager by their preferredShops
  EfficiencySummary? _getShopSummary(Employee e) {
    if (_efficiencyData == null || e.preferredShops.isEmpty) return null;
    final shopHint = e.preferredShops.first.toLowerCase().trim();
    try {
      return _efficiencyData!.byShop.firstWhere(
        (s) => s.entityName.toLowerCase().contains(shopHint) ||
               s.entityId.contains(shopHint),
      );
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────── BUILD ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: const BoxDecoration(
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
              _buildHeader(),
              _buildMonthSelector(),
              _buildTabBar(),
              _buildSearchBar(),
              if (_isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: _colorAdmin),
                  ),
                )
              else
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildList(),
                      _buildShopList(),
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
      padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 0),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white.withOpacity(0.8),
                  size: 20,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'Эффективность сотрудников',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            // Refresh button
            GestureDetector(
              onTap: _load,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Icon(
                  Icons.refresh_rounded,
                  color: Colors.white.withOpacity(0.7),
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    const months = ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн',
                    'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
    final label = '${months[_selectedMonth.month - 1]} ${_selectedMonth.year}';
    final now = DateTime.now();
    final canGoForward = _selectedMonth.year < now.year ||
        (_selectedMonth.year == now.year && _selectedMonth.month < now.month);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left_rounded,
                color: Colors.white.withOpacity(0.7), size: 26),
            onPressed: () {
              setState(() => _selectedMonth =
                  DateTime(_selectedMonth.year, _selectedMonth.month - 1));
              _load();
            },
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right_rounded,
                color: canGoForward
                    ? Colors.white.withOpacity(0.7)
                    : Colors.white.withOpacity(0.2),
                size: 26),
            onPressed: canGoForward
                ? () {
                    setState(() => _selectedMonth =
                        DateTime(_selectedMonth.year, _selectedMonth.month + 1));
                    _load();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 8.h),
      child: Container(
        height: 40.h,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(
          children: [
            SizedBox(width: 10.w),
            Icon(Icons.search_rounded,
                color: Colors.white.withOpacity(0.4), size: 18),
            SizedBox(width: 8.w),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: TextStyle(
                    color: Colors.white.withOpacity(0.9), fontSize: 13.sp),
                decoration: InputDecoration(
                  hintText: _tabController.index == 0
                      ? 'Поиск по имени или фамилии...'
                      : 'Поиск по адресу магазина...',
                  hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.3), fontSize: 13.sp),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10.w),
                  child: Icon(Icons.close_rounded,
                      color: Colors.white.withOpacity(0.5), size: 16),
                ),
              )
            else
              SizedBox(width: 10.w),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 4.h),
      child: Container(
        height: 36.h,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: AppColors.emerald,
            borderRadius: BorderRadius.circular(9.r),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.4),
          labelStyle: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w400),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Сотрудники'),
            Tab(text: 'Магазины'),
          ],
        ),
      ),
    );
  }

  Widget _buildShopList() {
    final filtered = _allShopSummaries
        .where((s) => _matchesSearch(s.entityName))
        .toList();
    final total = _allShopSummaries.length;

    if (filtered.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                color: Colors.white.withOpacity(0.2), size: 48),
            SizedBox(height: 12.h),
            Text('Ничего не найдено',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 14.sp)),
          ],
        ),
      );
    }

    if (_allShopSummaries.isEmpty) {
      return Center(
        child: Text('Нет данных за этот месяц',
            style: TextStyle(
                color: Colors.white.withOpacity(0.4), fontSize: 14.sp)),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 24.h),
      itemCount: filtered.length,
      itemBuilder: (_, index) {
        final summary = filtered[index];
        // Find real position in the full (unfiltered) sorted list
        final position = _allShopSummaries.indexOf(summary) + 1;
        return _buildShopTile(summary, position: position, total: total);
      },
    );
  }

  Widget _buildShopTile(EfficiencySummary summary, {required int position, required int total}) {
    final isPositive = summary.totalPoints >= 0;
    final posColor = position == 1
        ? AppColors.gold
        : position == 2
            ? Colors.grey.shade300
            : position == 3
                ? Colors.orange.shade400
                : Colors.white.withOpacity(0.5);

    final months = ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн',
                    'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
    final monthName = '${months[_selectedMonth.month - 1]} ${_selectedMonth.year}';

    return Padding(
      padding: EdgeInsets.only(bottom: 5.h),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ShopEfficiencyDetailPage(
                summary: summary,
                monthName: monthName,
              ),
            ),
          ),
          borderRadius: BorderRadius.circular(14.r),
          splashColor: AppColors.turquoise.withOpacity(0.1),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: AppColors.turquoise.withOpacity(0.25)),
              gradient: LinearGradient(
                colors: [AppColors.turquoise.withOpacity(0.1), AppColors.turquoise.withOpacity(0.03)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: Row(
              children: [
                // Position badge
                Container(
                  width: 28.w,
                  height: 28.w,
                  margin: EdgeInsets.only(right: 10.w),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: posColor.withOpacity(0.15),
                    border: Border.all(color: posColor.withOpacity(0.5), width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      '$position',
                      style: TextStyle(
                        color: posColor,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                // Shop name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.entityName,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2.h),
                      Row(
                        children: [
                          Text(
                            '+${summary.earnedPoints.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: AppColors.success,
                            ),
                          ),
                          Text(' / ',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.3),
                                  fontSize: 10.sp)),
                          Text(
                            '-${summary.lostPoints.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: const Color(0xFFEF5350),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Text(
                            '${summary.recordsCount} зап.',
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Points + position badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                      decoration: BoxDecoration(
                        color: isPositive
                            ? Colors.green.withOpacity(0.15)
                            : Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(
                          color: isPositive
                              ? AppColors.success.withOpacity(0.35)
                              : const Color(0xFFEF5350).withOpacity(0.35),
                        ),
                      ),
                      child: Text(
                        summary.formattedTotal,
                        style: TextStyle(
                          color: isPositive ? AppColors.success : const Color(0xFFEF5350),
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      '$position/$total',
                      style: TextStyle(
                        fontSize: 9.sp,
                        color: posColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 4.w),
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.turquoise.withOpacity(0.5), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    final filteredAdmins = _admins
        .where((e) => _matchesSearch(e.employeeName ?? e.name))
        .toList();
    final filteredManagers = _managers
        .where((e) => _matchesSearch(e.employeeName ?? e.name))
        .toList();
    final filteredEmployees = _employees
        .where((e) => _matchesSearch(e.employeeName ?? e.name))
        .toList();

    final hasResults = filteredAdmins.isNotEmpty ||
        filteredManagers.isNotEmpty ||
        filteredEmployees.isNotEmpty;

    return ListView(
      padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 24.h),
      children: [
        if (!hasResults && _searchQuery.isNotEmpty) ...[
          SizedBox(height: 40.h),
          Center(
            child: Column(
              children: [
                Icon(Icons.search_off_rounded,
                    color: Colors.white.withOpacity(0.2), size: 48),
                SizedBox(height: 12.h),
                Text(
                  'Никого не нашли',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4), fontSize: 14.sp),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Попробуйте другое имя',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.25), fontSize: 12.sp),
                ),
              ],
            ),
          ),
        ],
        if (filteredAdmins.isNotEmpty) ...[
          _buildGroupHeader('Управляющие', _colorAdmin),
          ...filteredAdmins.map(_buildAdminTile),
        ],
        if (filteredManagers.isNotEmpty) ...[
          SizedBox(height: 10.h),
          _buildGroupHeader('Заведующие', _colorManager),
          ...filteredManagers.map(_buildManagerTile),
        ],
        if (filteredEmployees.isNotEmpty) ...[
          SizedBox(height: 10.h),
          _buildGroupHeader('Сотрудники', _colorEmployee),
          ...filteredEmployees.map(_buildEmployeeTile),
        ],
      ],
    );
  }

  Widget _buildGroupHeader(String title, Color color) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h, top: 2.h),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14.h,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminTile(Employee e) {
    final data = e.phone != null ? _adminEfficiency[e.phone] : null;
    final name = e.employeeName ?? e.name;

    String? badge;
    String? badgeLabel;
    if (data != null) {
      badge = '${data.reviewEfficiencyPercentage.toStringAsFixed(0)}% / '
          '${data.shopEfficiencyPercentage.toStringAsFixed(0)}%';
      badgeLabel = 'Лич. / Маг.';
    }

    return _buildTile(
      name: name,
      color: _colorAdmin,
      badge: badge,
      badgeLabel: badgeLabel,
      onTap: data != null
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _AdminDetailPage(name: name, data: data),
                ),
              )
          : null,
    );
  }

  Widget _buildManagerTile(Employee e) {
    final summary = _getSummary(e);
    final shopSummary = _getShopSummary(e);
    final name = e.employeeName ?? e.name;

    String? badge;
    String? badgeLabel;
    if (summary != null) {
      final pts = summary.totalPoints.toStringAsFixed(0);
      if (shopSummary != null) {
        final shopPts = shopSummary.totalPoints.toStringAsFixed(0);
        badge = '$pts б / $shopPts б';
        badgeLabel = 'Лич. / Маг.';
      } else {
        badge = '$pts б';
        badgeLabel = 'Личная';
      }
    }

    return _buildTile(
      name: name,
      color: _colorManager,
      badge: badge,
      badgeLabel: badgeLabel,
      onTap: summary != null
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _PersonDetailPage(
                    name: name,
                    summary: summary,
                    color: _colorManager,
                  ),
                ),
              )
          : null,
    );
  }

  Widget _buildEmployeeTile(Employee e) {
    final summary = _getSummary(e);
    final name = e.employeeName ?? e.name;

    String? badge;
    if (summary != null) {
      badge = '${summary.totalPoints.toStringAsFixed(0)} б';
    }

    return _buildTile(
      name: name,
      color: _colorEmployee,
      badge: badge,
      badgeLabel: badge != null ? 'Личная' : null,
      onTap: summary != null
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _PersonDetailPage(
                    name: name,
                    summary: summary,
                    color: _colorEmployee,
                  ),
                ),
              )
          : null,
    );
  }

  Widget _buildTile({
    required String name,
    required Color color,
    String? badge,
    String? badgeLabel,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 5.h),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14.r),
          splashColor: color.withOpacity(0.1),
          highlightColor: color.withOpacity(0.05),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: color.withOpacity(0.25)),
              gradient: LinearGradient(
                colors: [color.withOpacity(0.1), color.withOpacity(0.03)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: Row(
              children: [
                // Colored left bar
                Container(
                  width: 3,
                  height: 34.h,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: 10.w),
                // Name
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Badge
                if (badge != null) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: color.withOpacity(0.35)),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: color,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (badgeLabel != null)
                        Padding(
                          padding: EdgeInsets.only(top: 2.h),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.35),
                              fontSize: 9.sp,
                            ),
                          ),
                        ),
                    ],
                  ),
                ] else
                  Text(
                    '— нет данных',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.3), fontSize: 11.sp),
                  ),
                SizedBox(width: 6.w),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded,
                      color: color.withOpacity(0.5), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// DETAIL PAGE — Employee / Manager (EfficiencySummary)
// ═══════════════════════════════════════════════════════════

class _PersonDetailPage extends StatelessWidget {
  final String name;
  final EfficiencySummary summary;
  final Color color;

  const _PersonDetailPage({
    required this.name,
    required this.summary,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final categories = summary.categorySummaries
      ..sort((a, b) => b.points.compareTo(a.points));

    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: const BoxDecoration(
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
              _buildHeader(context),
              SizedBox(height: 8.h),
              // Summary card
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                child: Container(
                  padding:
                      EdgeInsets.symmetric(vertical: 14.h, horizontal: 12.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withOpacity(0.2),
                        color.withOpacity(0.07)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statCol('Итого',
                          summary.totalPoints >= 0
                              ? '+${summary.totalPoints.toStringAsFixed(1)}'
                              : summary.totalPoints.toStringAsFixed(1),
                          color),
                      _statCol('Заработано',
                          '+${summary.earnedPoints.toStringAsFixed(1)}',
                          AppColors.success),
                      _statCol('Потеряно',
                          '-${summary.lostPoints.toStringAsFixed(1)}',
                          AppColors.error),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              // Category list
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 24.h),
                  itemCount: categories.length,
                  itemBuilder: (_, i) {
                    final cat = categories[i];
                    final isPos = cat.points >= 0;
                    return Padding(
                      padding: EdgeInsets.only(bottom: 5.h),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 14.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10.r),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                cat.name,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 13.sp,
                                ),
                              ),
                            ),
                            Text(
                              '${isPos ? '+' : ''}${cat.points.toStringAsFixed(1)} б',
                              style: TextStyle(
                                color: isPos
                                    ? AppColors.success
                                    : AppColors.error,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 0),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white.withOpacity(0.8), size: 20),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  name,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(width: 40),
          ],
        ),
      ),
    );
  }

  Widget _statCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
              color: color, fontSize: 18.sp, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 2.h),
        Text(
          label,
          style: TextStyle(
              color: Colors.white.withOpacity(0.5), fontSize: 10.sp),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// DETAIL PAGE — Admin (ManagerEfficiencyData)
// ═══════════════════════════════════════════════════════════

class _AdminDetailPage extends StatelessWidget {
  final String name;
  final ManagerEfficiencyData data;

  const _AdminDetailPage({required this.name, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: const BoxDecoration(
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
              _buildHeader(context),
              SizedBox(height: 8.h),
              // Summary card
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                child: Container(
                  padding:
                      EdgeInsets.symmetric(vertical: 14.h, horizontal: 12.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _colorAdmin.withOpacity(0.2),
                        _colorAdmin.withOpacity(0.07)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: _colorAdmin.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statCol('Личная',
                          '${data.reviewEfficiencyPercentage.toStringAsFixed(1)}%',
                          _colorAdmin),
                      _statCol('Магазины',
                          '${data.shopEfficiencyPercentage.toStringAsFixed(1)}%',
                          AppColors.turquoise),
                      _statCol('Итого',
                          '${data.totalPercentage.toStringAsFixed(1)}%',
                          AppColors.success),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              // Shop breakdown
              if (data.shopBreakdown.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 6.h),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 14.h,
                        decoration: BoxDecoration(
                          color: AppColors.turquoise,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        'По магазинам',
                        style: TextStyle(
                          color: AppColors.turquoise,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 24.h),
                  children: data.shopBreakdown.map((shop) {
                    final pct = shop.percentage;
                    final color = pct >= 80
                        ? AppColors.success
                        : pct >= 50
                            ? AppColors.warning
                            : AppColors.error;
                    return Padding(
                      padding: EdgeInsets.only(bottom: 5.h),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 14.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10.r),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                shop.shopAddress.isNotEmpty
                                    ? shop.shopAddress
                                    : shop.shopName,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12.sp,
                                ),
                              ),
                            ),
                            Text(
                              '${pct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: color,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 0),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white.withOpacity(0.8), size: 20),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  name,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(width: 40),
          ],
        ),
      ),
    );
  }

  Widget _statCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
              color: color, fontSize: 16.sp, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 2.h),
        Text(
          label,
          style: TextStyle(
              color: Colors.white.withOpacity(0.5), fontSize: 10.sp),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/efficiency_data_model.dart';
import '../models/manager_efficiency_model.dart';
import '../services/efficiency_data_service.dart';
import '../services/manager_efficiency_service.dart';
import '../utils/efficiency_utils.dart';
import '../../employees/pages/employees_page.dart';
import '../../employees/services/user_role_service.dart';
import '../../employees/models/user_role_model.dart';
import '../../bonuses/models/bonus_penalty_model.dart';
import '../../bonuses/services/bonus_penalty_service.dart';
import '../../bonuses/pages/bonus_penalty_history_page.dart';
import '../../referrals/models/referral_stats_model.dart';
import '../../referrals/services/referral_service.dart';
import '../../rating/pages/my_rating_page.dart';
import '../../tests/services/test_result_service.dart';
import 'shop_efficiency_detail_page.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/cache_manager.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница "Моя эффективность" для сотрудника
class MyEfficiencyPage extends StatefulWidget {
  const MyEfficiencyPage({super.key});

  @override
  State<MyEfficiencyPage> createState() => _MyEfficiencyPageState();
}

class _MyEfficiencyPageState extends State<MyEfficiencyPage> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  EfficiencySummary? _summary;
  EfficiencySummary? _previousMonthSummary; // Для сравнения
  List<EfficiencyRecord> _sortedRecentRecords = []; // cached sorted records
  String? _error;
  String? _employeeName;
  String? _employeeId;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  BonusPenaltySummary? _bonusSummary;
  EmployeeReferralPoints? _referralPoints;
  double? _avgTestScore; // Средний балл тестирования
  int _totalTests = 0; // Количество тестов

  // Manager efficiency data (для admin с managedShopIds)
  UserRoleData? _userRole;
  ManagerEfficiencyData? _managerEfficiency;
  EfficiencyData? _efficiencyData; // Full data for shop detail navigation
  bool _isManagerWithShops = false; // true если admin с managedShopIds
  Map<String, dynamic>? _teamTaskPenalties; // Штрафы команды за задачи

  late TabController _tabController;
  int _currentTabIndex = 0; // 0 = текущий месяц, 1 = прошлый месяц

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final newIndex = _tabController.index;
    if (newIndex != _currentTabIndex) {
      if (mounted) setState(() {
        _currentTabIndex = newIndex;
        // Переключаем месяц
        if (newIndex == 0) {
          // Текущий месяц
          _selectedMonth = DateTime.now().month;
          _selectedYear = DateTime.now().year;
        } else {
          // Прошлый месяц
          final prevMonth = DateTime(DateTime.now().year, DateTime.now().month - 1);
          _selectedMonth = prevMonth.month;
          _selectedYear = prevMonth.year;
        }
      });
      _loadData();
    }
  }

  String get _cacheKey => 'my_efficiency_${_selectedYear}_$_selectedMonth';

  Future<void> _loadData({bool forceRefresh = false}) async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<Map<String, dynamic>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _summary = cached['summary'] as EfficiencySummary?;
        _previousMonthSummary = cached['prevSummary'] as EfficiencySummary?;
        _bonusSummary = cached['bonusSummary'] as BonusPenaltySummary?;
        _referralPoints = cached['referralPoints'] as EmployeeReferralPoints?;
        _avgTestScore = cached['avgTestScore'] as double?;
        _totalTests = cached['totalTests'] as int? ?? 0;
        _managerEfficiency = cached['managerEfficiency'] as ManagerEfficiencyData?;
        _isManagerWithShops = cached['isManagerWithShops'] as bool? ?? false;
        _employeeName = cached['employeeName'] as String?;
        _employeeId = cached['employeeId'] as String?;
        _teamTaskPenalties = cached['teamTaskPenalties'] as Map<String, dynamic>?;
        _sortedRecentRecords = _summary != null
            ? (List<EfficiencyRecord>.from(_summary!.records)
                ..sort((a, b) => b.date.compareTo(a.date)))
                .take(20).toList()
            : [];
        _isLoading = false;
        _error = null;
      });
    }

    if (mounted && _summary == null && _managerEfficiency == null) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      // Получаем имя текущего сотрудника и роль
      final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
      var roleData = await UserRoleService.loadUserRole();
      final employeeName = systemEmployeeName ?? roleData?.displayName;

      // Если phone пустой, пробуем получить из SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      if (roleData != null && roleData.phone.isEmpty) {
        final savedPhone = prefs.getString('user_phone') ?? prefs.getString('phone') ?? '';
        if (savedPhone.isNotEmpty) {
          Logger.debug('Phone was empty, restored from prefs: ${Logger.maskPhone(savedPhone)}');
          roleData = roleData.copyWith(phone: savedPhone);
        }
      }

      // Если роль admin/developer, но нет managedShopIds - перезагружаем с сервера
      if ((roleData?.role == UserRole.admin || roleData?.role == UserRole.developer) &&
          (roleData?.managedShopIds.isEmpty ?? true) &&
          roleData?.phone != null &&
          roleData!.phone.isNotEmpty) {
        Logger.debug('Admin without managedShopIds - updating role from server...');
        try {
          final freshRole = await UserRoleService.getUserRole(roleData.phone);
          await UserRoleService.saveUserRole(freshRole);
          roleData = freshRole;
          Logger.debug('Role updated: managedShopIds = ${freshRole.managedShopIds}');
        } catch (e) {
          Logger.debug('Failed to update role: $e');
        }
      }

      _userRole = roleData;

      // DEBUG: Логируем данные роли для отладки
      Logger.debug('MyEfficiencyPage: roleData = $roleData');
      Logger.debug('   role: ${roleData?.role}');
      Logger.debug('   phone: "${Logger.maskPhone(roleData?.phone)}"');
      Logger.debug('   managedShopIds: ${roleData?.managedShopIds}');

      // Проверяем, является ли пользователь admin/developer с managedShopIds
      final isAdmin = roleData?.role == UserRole.admin || roleData?.role == UserRole.developer;
      final hasManagedShops = roleData?.managedShopIds.isNotEmpty ?? false;
      _isManagerWithShops = isAdmin && hasManagedShops;

      Logger.debug('   isAdmin: $isAdmin, hasManagedShops: $hasManagedShops');
      Logger.debug('   _isManagerWithShops: $_isManagerWithShops');

      if (_isManagerWithShops && roleData?.phone != null && roleData!.phone.isNotEmpty) {
        // Загружаем данные эффективности управляющего
        Logger.debug('Loading manager efficiency data...');
        await _loadManagerEfficiency(roleData.phone);
        return;
      }

      if (employeeName == null || employeeName.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'Не удалось определить сотрудника';
          _isLoading = false;
        });
        return;
      }

      _employeeName = employeeName;

      // Получаем ID сотрудника для загрузки премий/штрафов и рефералов
      _employeeId = prefs.getString('currentEmployeeId');

      // Вычисляем предыдущий месяц для сравнения
      final prevMonthDate = DateTime(_selectedYear, _selectedMonth - 1);
      final prevYear = prevMonthDate.year;
      final prevMonth = prevMonthDate.month;

      // Загружаем данные за выбранный месяц И предыдущий месяц параллельно
      final results = await Future.wait([
        EfficiencyDataService.loadMonthData(
          _selectedYear,
          _selectedMonth,
          forceRefresh: forceRefresh,
        ),
        EfficiencyDataService.loadMonthData(
          prevYear,
          prevMonth,
          forceRefresh: false, // Не форсируем для предыдущего месяца
        ),
      ]);

      final data = results[0];
      final prevData = results[1];

      // Build personal summary from allRecords (unfiltered by managed shops).
      // byEmployee is filtered by the user's managed shops, which can exclude
      // records from shops the employee worked at but doesn't manage.
      final lowerEmployeeName = employeeName?.trim().toLowerCase() ?? '';
      // Нормализуем телефон: оставляем только цифры
      final normalizedPhone = (roleData?.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');

      // Фильтрация: по телефону (надёжнее) с fallback по имени
      bool isMyRecord(EfficiencyRecord r) {
        // Приоритет 1: сравнение по телефону (оба не пустые)
        if (normalizedPhone.isNotEmpty && r.employeePhone.isNotEmpty) {
          final recordPhone = r.employeePhone.replaceAll(RegExp(r'[^0-9]'), '');
          if (recordPhone == normalizedPhone) return true;
        }
        // Приоритет 2: fallback по имени
        if (lowerEmployeeName.isNotEmpty && r.employeeName.trim().toLowerCase() == lowerEmployeeName) {
          return true;
        }
        return false;
      }

      Logger.debug('MyEfficiency: фильтрация по phone=$normalizedPhone, name=$lowerEmployeeName');

      EfficiencySummary? mySummary;
      if (lowerEmployeeName.isNotEmpty || normalizedPhone.isNotEmpty) {
        final myRecords = data.allRecords.where(isMyRecord).toList();
        Logger.debug('MyEfficiency: найдено ${myRecords.length} записей из ${data.allRecords.length}');
        if (myRecords.isNotEmpty) {
          mySummary = EfficiencySummary.fromRecords(
            entityId: lowerEmployeeName,
            entityName: employeeName ?? lowerEmployeeName,
            records: myRecords,
          );
        }
      }

      // Build previous month summary the same way
      EfficiencySummary? prevSummary;
      if (lowerEmployeeName.isNotEmpty || normalizedPhone.isNotEmpty) {
        final prevRecords = prevData.allRecords.where(isMyRecord).toList();
        if (prevRecords.isNotEmpty) {
          prevSummary = EfficiencySummary.fromRecords(
            entityId: lowerEmployeeName,
            entityName: employeeName ?? lowerEmployeeName,
            records: prevRecords,
          );
        }
      }

      // Загружаем премии/штрафы, баллы за приглашения и тесты ПАРАЛЛЕЛЬНО
      final hasEmployeeId = _employeeId != null && _employeeId!.isNotEmpty;
      final parallelResults = await Future.wait([
        if (hasEmployeeId) BonusPenaltyService.getSummary(_employeeId!) else Future.value(null),
        if (hasEmployeeId) ReferralService.getEmployeePoints(_employeeId!) else Future.value(null),
        TestResultService.getResults(),
      ]);

      final BonusPenaltySummary? bonusSummary = parallelResults[0] as BonusPenaltySummary?;
      final EmployeeReferralPoints? referralPoints = parallelResults[1] as EmployeeReferralPoints?;

      double? avgScore;
      int totalTests = 0;
      try {
        final testResults = parallelResults[2] as List<dynamic>;
        // Фильтруем по телефону текущего сотрудника
        final myTests = testResults.where((t) {
          final phone = _employeeId?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
          final testPhone = t.employeePhone.replaceAll(RegExp(r'[^0-9]'), '');
          return testPhone == phone || t.employeeName == employeeName;
        }).toList();

        if (myTests.isNotEmpty) {
          totalTests = myTests.length;
          final totalScore = myTests.fold<int>(0, (sum, t) => sum + (t.score as int));
          // Средний балл = сумма баллов / количество тестов
          avgScore = totalScore / totalTests;
        }
      } catch (e) {
        // Игнорируем ошибки загрузки тестов
      }

      if (!mounted) return;
      setState(() {
        _summary = mySummary;
        _previousMonthSummary = prevSummary;
        _bonusSummary = bonusSummary;
        _referralPoints = referralPoints;
        _avgTestScore = avgScore;
        _totalTests = totalTests;
        _sortedRecentRecords = mySummary != null
            ? (List<EfficiencyRecord>.from(mySummary.records)
                ..sort((a, b) => b.date.compareTo(a.date)))
                .take(20).toList()
            : [];
        _isLoading = false;
      });

      // Step 3: Save to cache
      CacheManager.set(_cacheKey, {
        'summary': mySummary,
        'prevSummary': prevSummary,
        'bonusSummary': bonusSummary,
        'referralPoints': referralPoints,
        'avgTestScore': avgScore,
        'totalTests': totalTests,
        'managerEfficiency': null,
        'isManagerWithShops': false,
        'employeeName': employeeName,
        'employeeId': _employeeId,
      });
    } catch (e) {
      if (!mounted) return;
      if (_summary == null && _managerEfficiency == null) {
        setState(() {
          _error = 'Ошибка загрузки данных: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Загружает данные эффективности для управляющего (admin)
  Future<void> _loadManagerEfficiency(String phone) async {
    try {
      final month = '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';

      // Load manager summary, full efficiency data, and team task penalties in parallel
      final results = await Future.wait([
        ManagerEfficiencyService.getManagerEfficiencyWithComparison(
          phone: phone,
          currentMonth: month,
        ),
        EfficiencyDataService.loadMonthData(
          _selectedYear,
          _selectedMonth,
          forceRefresh: false,
        ),
        ManagerEfficiencyService.getTeamTaskPenalties(month: month),
      ]);

      final efficiency = results[0] as ManagerEfficiencyData?;
      final efficiencyData = results[1] as EfficiencyData;
      final teamPenalties = results[2] as Map<String, dynamic>?;

      if (!mounted) return;
      setState(() {
        _managerEfficiency = efficiency ?? ManagerEfficiencyData.empty();
        _efficiencyData = efficiencyData;
        _teamTaskPenalties = teamPenalties;
        _employeeName = _userRole?.displayName;
        _isLoading = false;
      });

      // Step 3: Save to cache (manager path)
      CacheManager.set(_cacheKey, {
        'summary': null,
        'prevSummary': null,
        'bonusSummary': null,
        'referralPoints': null,
        'avgTestScore': null,
        'totalTests': 0,
        'managerEfficiency': efficiency ?? ManagerEfficiencyData.empty(),
        'isManagerWithShops': true,
        'employeeName': _userRole?.displayName,
        'employeeId': null,
        'teamTaskPenalties': teamPenalties,
      });
    } catch (e) {
      if (!mounted) return;
      if (_managerEfficiency == null && _summary == null) {
        setState(() {
          _error = 'Ошибка загрузки данных: $e';
          _isLoading = false;
        });
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
              // Custom AppBar
              Padding(
                padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 4.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: EdgeInsets.all(8.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Моя эффективность',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Tab bar
              Container(
                margin: EdgeInsets.symmetric(horizontal: 8.w),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppColors.gold,
                  indicatorWeight: 3,
                  labelColor: AppColors.gold,
                  unselectedLabelColor: Colors.white.withOpacity(0.5),
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(text: 'Текущий месяц'),
                    Tab(text: 'Прошлый месяц'),
                  ],
                ),
              ),
              // Body
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.gold),
            SizedBox(height: 16),
            Text(
              'Загрузка данных...',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.8)),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.night,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              ),
              child: Text('Повторить'),
            ),
          ],
        ),
      );
    }

    // Если это управляющий с магазинами - показываем специальный UI
    if (_isManagerWithShops && _managerEfficiency != null) {
      return _buildManagerEfficiencyBody();
    }

    // Проверяем есть ли хоть какие-то данные (эффективность, премии или приглашения)
    final hasBonusData = _bonusSummary != null &&
        (_bonusSummary!.currentMonthTotal != 0 || _bonusSummary!.previousMonthTotal != 0 ||
         _bonusSummary!.currentMonthRecords.isNotEmpty || _bonusSummary!.previousMonthRecords.isNotEmpty);
    final hasReferralData = _referralPoints != null &&
        (_referralPoints!.currentMonthPoints > 0 || _referralPoints!.previousMonthPoints > 0 ||
         _referralPoints!.currentMonthReferrals > 0 || _referralPoints!.previousMonthReferrals > 0);

    if (_summary == null && !hasBonusData && !hasReferralData) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up, size: 64, color: Colors.white.withOpacity(0.3)),
            SizedBox(height: 16),
            Text(
              'Нет данных за ${EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear)}',
              style: TextStyle(
                fontSize: 16.sp,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Баллы появятся после оценки ваших отчетов',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
            if (_employeeName != null) ...[
              SizedBox(height: 16),
              Text(
                _employeeName!,
                style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.white.withOpacity(0.3),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Если есть только премии/приглашения, но нет данных эффективности - показываем только их
    if (_summary == null) {
      return RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.gold,
        backgroundColor: AppColors.emeraldDark,
        child: SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Показываем заглушку вместо основной карточки
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                padding: EdgeInsets.all(20.w),
                child: Column(
                  children: [
                    Text(
                      EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear),
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '0',
                      style: TextStyle(
                        fontSize: 48.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                    Text(
                      'баллов за отчёты',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              _buildBonusPenaltySection(),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTotalCard(),
            SizedBox(height: 16),
            _buildRatingButton(),
            SizedBox(height: 16),
            _buildTestScoreCard(),
            _buildBonusPenaltySection(),
            _buildCategoriesCard(),
            SizedBox(height: 16),
            _buildShopsCard(),
            SizedBox(height: 16),
            _buildRecentRecordsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: InkWell(
        onTap: () {
          if (_employeeId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MyRatingPage(
                  employeeId: 'employee_${_employeeId!.replaceAll(RegExp(r'[^0-9]'), '')}',
                  employeeName: _employeeName ?? '',
                ),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(14.r),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  Icons.leaderboard,
                  color: AppColors.gold,
                  size: 28,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Мой рейтинг',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Позиция среди сотрудников',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestScoreCard() {
    // Если нет данных о тестах - не показываем карточку
    if (_avgTestScore == null || _totalTests == 0) {
      return SizedBox.shrink();
    }

    // Определяем цвет в зависимости от среднего балла (из 20)
    Color scoreColor;
    if (_avgTestScore! >= 16) {
      scoreColor = AppColors.success;
    } else if (_avgTestScore! >= 12) {
      scoreColor = Color(0xFFFFB74D);
    } else {
      scoreColor = Color(0xFFEF5350);
    }

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          padding: EdgeInsets.all(16.w),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.emerald.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  Icons.quiz,
                  color: Colors.white.withOpacity(0.8),
                  size: 28,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Тестирование',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Пройдено тестов: $_totalTests',
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_avgTestScore!.toStringAsFixed(1)}/20',
                    style: TextStyle(
                      fontSize: 24.sp,
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                  Text(
                    'средний балл',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTotalCard() {
    final isPositive = _summary!.totalPoints >= 0;

    // Вычисляем изменение по сравнению с предыдущим месяцем
    double? change;
    if (_previousMonthSummary != null) {
      change = _summary!.totalPoints - _previousMonthSummary!.totalPoints;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: EdgeInsets.all(20.w),
      child: Column(
        children: [
          Text(
            EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear),
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          SizedBox(height: 8),
          Text(
            _summary!.formattedTotal,
            style: TextStyle(
              fontSize: 48.sp,
              fontWeight: FontWeight.bold,
              color: isPositive ? AppColors.success : Color(0xFFEF5350),
            ),
          ),
          Text(
            'баллов',
            style: TextStyle(
              fontSize: 16.sp,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          // Сравнение с прошлым месяцем
          if (change != null) ...[
            SizedBox(height: 8),
            _buildComparisonRow(change),
          ],
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem(
                '+${_summary!.earnedPoints.toStringAsFixed(1)}',
                'Заработано',
                AppColors.success,
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withOpacity(0.1),
              ),
              _buildStatItem(
                '-${_summary!.lostPoints.toStringAsFixed(1)}',
                'Потеряно',
                Color(0xFFEF5350),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Строка сравнения с прошлым месяцем
  Widget _buildComparisonRow(double change) {
    final isImproved = change >= 0;
    final changeText = isImproved
        ? '+${change.toStringAsFixed(1)}'
        : change.toStringAsFixed(1);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: isImproved
            ? AppColors.success.withOpacity(0.15)
            : Color(0xFFEF5350).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isImproved ? Icons.trending_up : Icons.trending_down,
            size: 18,
            color: isImproved ? AppColors.success : Color(0xFFEF5350),
          ),
          SizedBox(width: 4),
          Text(
            '$changeText к прошлому месяцу',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: isImproved ? AppColors.success : Color(0xFFEF5350),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24.sp,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            color: Colors.white.withOpacity(0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildBonusPenaltySection() {
    if (_bonusSummary == null) return SizedBox.shrink();

    final hasCurrentMonth = _bonusSummary!.currentMonthTotal != 0 ||
        _bonusSummary!.currentMonthRecords.isNotEmpty;
    final hasPreviousMonth = _bonusSummary!.previousMonthTotal != 0 ||
        _bonusSummary!.previousMonthRecords.isNotEmpty;

    if (!hasCurrentMonth && !hasPreviousMonth) return SizedBox.shrink();

    return Column(
      children: [
        if (hasCurrentMonth)
          _buildBonusPenaltyCard(
            title: 'Премия/Штрафы',
            total: _bonusSummary!.currentMonthTotal,
            records: _bonusSummary!.currentMonthRecords,
            isPreviousMonth: false,
          ),
        if (hasPreviousMonth)
          _buildBonusPenaltyCard(
            title: 'Премия/Штрафы (прошлый месяц)',
            total: _bonusSummary!.previousMonthTotal,
            records: _bonusSummary!.previousMonthRecords,
            isPreviousMonth: true,
          ),
        _buildReferralPointsSection(),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildReferralPointsSection() {
    if (_referralPoints == null) return SizedBox.shrink();

    final hasCurrentMonth = _referralPoints!.currentMonthPoints > 0 ||
        _referralPoints!.currentMonthReferrals > 0;
    final hasPreviousMonth = _referralPoints!.previousMonthPoints > 0 ||
        _referralPoints!.previousMonthReferrals > 0;

    if (!hasCurrentMonth && !hasPreviousMonth) return SizedBox.shrink();

    return Column(
      children: [
        if (hasCurrentMonth)
          _buildReferralPointsCard(
            title: 'Приглашения',
            points: _referralPoints!.currentMonthPoints,
            referralsCount: _referralPoints!.currentMonthReferrals,
            isPreviousMonth: false,
          ),
        if (hasPreviousMonth)
          _buildReferralPointsCard(
            title: 'Приглашения (прошлый месяц)',
            points: _referralPoints!.previousMonthPoints,
            referralsCount: _referralPoints!.previousMonthReferrals,
            isPreviousMonth: true,
          ),
      ],
    );
  }

  Widget _buildReferralPointsCard({
    required String title,
    required int points,
    required int referralsCount,
    required bool isPreviousMonth,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: isPreviousMonth ? 0 : 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: EdgeInsets.all(16.w),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(0xFF42A5F5).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(
              Icons.person_add,
              color: Color(0xFF42A5F5),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w500,
                    color: isPreviousMonth
                        ? Colors.white.withOpacity(0.5)
                        : Colors.white.withOpacity(0.9),
                  ),
                ),
                Text(
                  '$referralsCount ${_getReferralsLabel(referralsCount)}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '+',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: Color(0xFF42A5F5),
            ),
          ),
          Text(
            '$points',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: Color(0xFF42A5F5),
            ),
          ),
          SizedBox(width: 4),
          Text(
            'балл${_getPointsEnding(points)}',
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  String _getReferralsLabel(int count) {
    if (count == 1) return 'приглашение';
    if (count >= 2 && count <= 4) return 'приглашения';
    return 'приглашений';
  }

  String _getPointsEnding(int count) {
    final lastTwo = count % 100;
    if (lastTwo >= 11 && lastTwo <= 14) return 'ов';
    final lastOne = count % 10;
    if (lastOne == 1) return '';
    if (lastOne >= 2 && lastOne <= 4) return 'а';
    return 'ов';
  }

  Widget _buildBonusPenaltyCard({
    required String title,
    required double total,
    required List<BonusPenalty> records,
    required bool isPreviousMonth,
  }) {
    final isPositive = total >= 0;
    final color = isPositive ? AppColors.success : Color(0xFFEF5350);
    final formattedTotal = '${isPositive ? '+' : ''}${total.toStringAsFixed(0)} руб';

    return Container(
      margin: EdgeInsets.only(bottom: isPreviousMonth ? 0 : 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BonusPenaltyHistoryPage(
                title: title,
                records: records,
                total: total,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(14.r),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  Icons.monetization_on,
                  color: color,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w500,
                        color: isPreviousMonth
                            ? Colors.white.withOpacity(0.5)
                            : Colors.white.withOpacity(0.9),
                      ),
                    ),
                    if (records.isNotEmpty)
                      Text(
                        '${records.length} ${_getRecordsLabel(records.length)}',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                formattedTotal,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withOpacity(0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getRecordsLabel(int count) {
    if (count == 1) return 'запись';
    if (count >= 2 && count <= 4) return 'записи';
    return 'записей';
  }

  /// Все категории эффективности для отображения
  static List<_CategoryInfo> _allCategories = [
    _CategoryInfo(EfficiencyCategory.shiftHandover, 'Сдать смену', 'Оценка пересменки 1-10'),
    _CategoryInfo(EfficiencyCategory.shift, 'Пересменка', 'Оценка смены 1-10'),
    _CategoryInfo(EfficiencyCategory.recount, 'Пересчёт', 'Оценка пересчёта 1-10'),
    _CategoryInfo(EfficiencyCategory.attendance, 'Посещаемость', '"Я на работе" вовремя'),
    _CategoryInfo(EfficiencyCategory.rko, 'РКО', 'Расходный кассовый ордер'),
    _CategoryInfo(EfficiencyCategory.orders, 'Заказы', 'Обработка заказов клиентов'),
    _CategoryInfo(EfficiencyCategory.reviews, 'Отзывы', 'Отзывы клиентов'),
    _CategoryInfo(EfficiencyCategory.productSearch, 'Поиск товара', 'Ответы на вопросы клиентов'),
    _CategoryInfo(EfficiencyCategory.tasks, 'Задачи', 'Выполнение задач'),
    _CategoryInfo(EfficiencyCategory.test, 'Тестирование', 'Прохождение тестов'),
  ];

  Widget _buildCategoriesCard() {
    // Собираем данные по категориям из summary
    final Map<String, double> pointsByCategory = {};
    if (_summary != null) {
      for (final cat in _summary!.categorySummaries) {
        pointsByCategory[cat.name] = cat.points;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Критерии оценки',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'По этим показателям оценивается ваша эффективность',
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          SizedBox(height: 12),
          // Сначала показываем категории с данными (из summary)
          if (_summary != null)
            ..._summary!.categorySummaries.map((cat) => _buildCategoryRow(cat)),
          // Затем показываем остальные категории с 0 баллов
          ..._allCategories
              .where((info) => !pointsByCategory.containsKey(info.name) &&
                  !_summary!.categorySummaries.any((c) => c.baseCategory == info.category))
              .map((info) => _buildEmptyCategoryRow(info)),
        ],
      ),
    );
  }

  Widget _buildEmptyCategoryRow(_CategoryInfo info) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(
              _getCategoryIcon(info.category),
              size: 20,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.name,
                  style: TextStyle(
                    fontSize: 15.sp,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                Text(
                  info.description,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '0.00',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(CategoryData categoryData) {
    final isPositive = categoryData.points >= 0;
    final formattedPoints = isPositive
        ? '+${categoryData.points.toStringAsFixed(2)}'
        : categoryData.points.toStringAsFixed(2);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _getCategoryColor(categoryData.baseCategory).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(
              _getCategoryIcon(categoryData.baseCategory),
              size: 20,
              color: _getCategoryColor(categoryData.baseCategory),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              categoryData.name,  // Используем настоящее имя категории
              style: TextStyle(
                fontSize: 15.sp,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ),
          Text(
            formattedPoints,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: isPositive ? AppColors.success : Color(0xFFEF5350),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(EfficiencyCategory category) {
    switch (category) {
      case EfficiencyCategory.shift:
        return Icons.swap_horiz;
      case EfficiencyCategory.recount:
        return Icons.inventory_2;
      case EfficiencyCategory.shiftHandover:
        return Icons.assignment_turned_in;
      case EfficiencyCategory.attendance:
        return Icons.access_time;
      case EfficiencyCategory.test:
        return Icons.quiz;
      case EfficiencyCategory.reviews:
        return Icons.star;
      case EfficiencyCategory.productSearch:
        return Icons.search;
      case EfficiencyCategory.rko:
        return Icons.receipt_long;
      case EfficiencyCategory.orders:
        return Icons.shopping_cart;
      case EfficiencyCategory.shiftPenalty:
        return Icons.warning;
      case EfficiencyCategory.tasks:
        return Icons.assignment;
    }
  }

  Color _getCategoryColor(EfficiencyCategory category) {
    switch (category) {
      case EfficiencyCategory.shift:
        return Color(0xFF42A5F5);
      case EfficiencyCategory.recount:
        return Color(0xFFAB47BC);
      case EfficiencyCategory.shiftHandover:
        return Color(0xFF26A69A);
      case EfficiencyCategory.attendance:
        return Color(0xFFFFB74D);
      case EfficiencyCategory.test:
        return Color(0xFF5C6BC0);
      case EfficiencyCategory.reviews:
        return AppColors.gold;
      case EfficiencyCategory.productSearch:
        return Color(0xFF26C6DA);
      case EfficiencyCategory.rko:
        return Color(0xFF8D6E63);
      case EfficiencyCategory.orders:
        return Color(0xFF66BB6A);
      case EfficiencyCategory.shiftPenalty:
        return Color(0xFFEF5350);
      case EfficiencyCategory.tasks:
        return Color(0xFF7E57C2);
    }
  }

  Widget _buildShopsCard() {
    // Группируем записи по магазинам
    final Map<String, double> pointsByShop = {};
    for (final record in _summary!.records) {
      // Для штрафов берем shopAddress из rawValue
      String shop = record.shopAddress;
      if (shop.isEmpty && record.category == EfficiencyCategory.shiftPenalty) {
        if (record.rawValue is Map && record.rawValue['shopAddress'] != null) {
          shop = record.rawValue['shopAddress'];
        }
      }
      if (shop.isNotEmpty) {
        pointsByShop[shop] = (pointsByShop[shop] ?? 0) + record.points;
      }
    }

    if (pointsByShop.isEmpty) {
      return SizedBox.shrink();
    }

    // Сортируем по баллам
    final sortedShops = pointsByShop.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'По магазинам',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          SizedBox(height: 12),
          ...sortedShops.map((entry) => _buildShopRow(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _buildShopRow(String shopAddress, double points) {
    final isPositive = points >= 0;
    final formattedPoints = isPositive
        ? '+${points.toStringAsFixed(2)}'
        : points.toStringAsFixed(2);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.emerald.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(
              Icons.store,
              size: 20,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              shopAddress,
              style: TextStyle(
                fontSize: 15.sp,
                color: Colors.white.withOpacity(0.9),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formattedPoints,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: isPositive ? AppColors.success : Color(0xFFEF5350),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRecordsCard() {
    final recentRecords = _sortedRecentRecords;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Последние записи',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.gold,
                ),
              ),
              Text(
                'Всего: ${_summary!.recordsCount}',
                style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          if (recentRecords.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Text(
                  'Нет записей',
                  style: TextStyle(color: Colors.white.withOpacity(0.4)),
                ),
              ),
            )
          else
            ...recentRecords.map((record) => _buildRecordRow(record)),
        ],
      ),
    );
  }

  Widget _buildRecordRow(EfficiencyRecord record) {
    final dateFormat = DateFormat('dd.MM');
    final isPositive = record.points >= 0;

    // Для штрафов берем shopAddress из rawValue
    String shop = record.shopAddress;
    if (shop.isEmpty && record.category == EfficiencyCategory.shiftPenalty) {
      if (record.rawValue is Map && record.rawValue['shopAddress'] != null) {
        shop = record.rawValue['shopAddress'];
      }
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 45,
            child: Text(
              dateFormat.format(record.date),
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.categoryName,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  record.formattedRawValue,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white.withOpacity(0.5),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (shop.isNotEmpty)
                  Text(
                    shop,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          SizedBox(width: 8),
          Text(
            record.formattedPoints,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: isPositive ? AppColors.success : Color(0xFFEF5350),
            ),
          ),
        ],
      ),
    );
  }

  // ============= MANAGER EFFICIENCY UI =============

  /// UI для управляющего (admin с managedShopIds) - КОМПАКТНЫЙ ДИЗАЙН
  Widget _buildManagerEfficiencyBody() {
    final efficiency = _managerEfficiency!;

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Хедер с общим % и двумя компонентами
            _buildManagerHeaderCard(efficiency),
            SizedBox(height: 10),
            // Компактные категории
            _buildManagerCategoriesCompact(efficiency),
            SizedBox(height: 10),
            // Магазины в виде сетки
            _buildManagerShopsGrid(efficiency),
            SizedBox(height: 10),
            // Штрафы команды за задачи
            _buildTeamTaskPenaltiesCard(),
          ],
        ),
      ),
    );
  }

  /// Компактная карточка-хедер с общим процентом и статистикой
  Widget _buildManagerHeaderCard(ManagerEfficiencyData efficiency) {
    final totalPercent = efficiency.totalPercentage;
    final color = totalPercent >= 70
        ? AppColors.emerald
        : totalPercent >= 40
            ? Color(0xFFFFB74D)
            : Color(0xFFEF5350);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.r),
      ),
      padding: EdgeInsets.all(16.w),
      child: Column(
        children: [
          // Общий процент
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  Icons.analytics,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Общая эффективность',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13.sp,
                      ),
                    ),
                    Text(
                      '${totalPercent.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Сравнение с прошлым месяцем
              if (efficiency.comparison != null)
                _buildCompactComparisonBadge(efficiency.comparison!.totalChange),
            ],
          ),
          SizedBox(height: 16),
          // Магазины и Отчёты - компактная строка
          Container(
            padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildCompactEfficiencyItem(
                    icon: Icons.store,
                    label: 'Магазины',
                    value: efficiency.shopEfficiencyPercentage,
                    change: efficiency.comparison?.shopEfficiencyChange,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white.withOpacity(0.2),
                ),
                Expanded(
                  child: _buildCompactEfficiencyItem(
                    icon: Icons.assignment_turned_in,
                    label: 'Отчёты',
                    value: efficiency.reviewEfficiencyPercentage,
                    change: efficiency.comparison?.reviewEfficiencyChange,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          // Баллы: Заработано / Потеряно / Итого
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCompactStatItem(
                '+${efficiency.totalEarned.toStringAsFixed(0)}',
                'Заработано',
                Color(0xFF69F0AE),
              ),
              _buildCompactStatItem(
                '-${efficiency.totalLost.toStringAsFixed(0)}',
                'Потеряно',
                Color(0xFFFF8A80),
              ),
              _buildCompactStatItem(
                efficiency.totalPoints.toStringAsFixed(0),
                'Итого',
                Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactComparisonBadge(double change) {
    final isPositive = change >= 0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive ? Icons.trending_up : Icons.trending_down,
            size: 16,
            color: Colors.white,
          ),
          SizedBox(width: 4),
          Text(
            '${isPositive ? '+' : ''}${change.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactEfficiencyItem({
    required IconData icon,
    required String label,
    required double value,
    double? change,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 11.sp,
              ),
            ),
            Row(
              children: [
                Text(
                  '${value.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (change != null && change != 0) ...[
                  SizedBox(width: 4),
                  Icon(
                    change >= 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    color: Colors.white70,
                    size: 18,
                  ),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactStatItem(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11.sp,
          ),
        ),
      ],
    );
  }

  /// Магазины в виде сетки (2 в ряд)
  /// Карточка штрафов команды управляющего за невыполненные задачи
  Widget _buildTeamTaskPenaltiesCard() {
    final data = _teamTaskPenalties;
    final employees = data != null ? (data['employees'] as List<dynamic>? ?? []) : <dynamic>[];

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Color(0xFFEF5350).withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.w),
                decoration: BoxDecoration(
                  color: Color(0xFFEF5350).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(Icons.assignment_late, color: Color(0xFFEF5350), size: 18),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Штрафы команды за задачи',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (data != null && employees.isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: Color(0xFFEF5350).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    '${data['totalPoints'] ?? 0} б.',
                    style: TextStyle(
                      color: Color(0xFFEF5350),
                      fontSize: 13.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          if (data == null) ...[
            SizedBox(height: 12),
            Center(
              child: Text(
                'Нет данных',
                style: TextStyle(color: Colors.white54, fontSize: 13.sp),
              ),
            ),
          ] else if (employees.isEmpty) ...[
            SizedBox(height: 12),
            Center(
              child: Text(
                'Штрафов за задачи нет',
                style: TextStyle(color: Colors.white54, fontSize: 13.sp),
              ),
            ),
          ] else ...[
            SizedBox(height: 8),
            // Итоговая строка
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                children: [
                  Text(
                    'Сотрудников: ${employees.length}',
                    style: TextStyle(color: Colors.white70, fontSize: 12.sp),
                  ),
                  Spacer(),
                  Text(
                    'Штрафов: ${data['totalCount'] ?? 0}',
                    style: TextStyle(color: Colors.white70, fontSize: 12.sp),
                  ),
                ],
              ),
            ),
            SizedBox(height: 6),
            // Список сотрудников (до 10)
            ...employees.take(10).map((e) {
              final emp = e as Map<String, dynamic>;
              final name = emp['name'] as String? ?? '';
              final count = emp['count'] as int? ?? 0;
              final pts = emp['totalPoints'] as int? ?? 0;
              final parts = name.split(' ');
              final shortName = parts.length >= 2
                  ? '${parts[0]} ${parts.skip(1).map((p) => p.isNotEmpty ? '${p[0]}.' : '').join()}'
                  : name;
              return Padding(
                padding: EdgeInsets.only(bottom: 4.h),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        shortName,
                        style: TextStyle(color: Colors.white, fontSize: 12.sp),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '$count шт.',
                      style: TextStyle(color: Colors.white54, fontSize: 12.sp),
                    ),
                    SizedBox(width: 8),
                    Text(
                      '$pts б.',
                      style: TextStyle(
                        color: Color(0xFFEF5350),
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (employees.length > 10)
              Padding(
                padding: EdgeInsets.only(top: 4.h),
                child: Text(
                  'и ещё ${employees.length - 10} сотрудников...',
                  style: TextStyle(color: Colors.white38, fontSize: 11.sp),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildManagerShopsGrid(ManagerEfficiencyData efficiency) {
    if (efficiency.shopBreakdown.isEmpty) {
      return SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.store, size: 16, color: AppColors.gold),
              SizedBox(width: 6),
              Text(
                'Магазины',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.gold,
                ),
              ),
              Spacer(),
              Text(
                '${efficiency.shopBreakdown.length} шт.',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          // Сетка магазинов 2 в ряд
          _buildShopsGridRows(efficiency.shopBreakdown),
        ],
      ),
    );
  }

  Widget _buildShopsGridRows(List<ShopEfficiencyItem> shops) {
    final List<Widget> rows = [];

    for (int i = 0; i < shops.length; i += 2) {
      final hasSecond = i + 1 < shops.length;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < shops.length ? 8 : 0),
          child: Row(
            children: [
              Expanded(child: _buildGridShopCard(shops[i])),
              SizedBox(width: 8),
              Expanded(
                child: hasSecond
                    ? _buildGridShopCard(shops[i + 1])
                    : SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _buildGridShopCard(ShopEfficiencyItem shop) {
    final isPositive = shop.totalPoints >= 0;
    final color = isPositive ? AppColors.emerald : Color(0xFFEF5350);

    // Извлекаем короткое название магазина
    String shortName = shop.shopName;
    if (shortName.contains(',')) {
      shortName = shortName.split(',').first;
    }

    // Find matching EfficiencySummary for detail navigation.
    // entityId in byShop is lowercase (normalized by efficiency_data_service),
    // but shopAddress from server may be original case — compare case-insensitively.
    final normalizedShopAddress = shop.shopAddress.trim().toLowerCase();
    final normalizedShopName = shop.shopName.trim().toLowerCase();
    final summary = _efficiencyData?.byShop.firstWhere(
      (s) => s.entityId.trim().toLowerCase() == normalizedShopAddress ||
             s.entityName.trim().toLowerCase() == normalizedShopName,
      orElse: () => EfficiencySummary(
        entityId: shop.shopAddress.isNotEmpty ? shop.shopAddress : shop.shopId,
        entityName: shop.shopName,
        earnedPoints: shop.earnedPoints,
        lostPoints: shop.lostPoints,
        totalPoints: shop.totalPoints,
        recordsCount: shop.recordsCount,
        records: [],
        categorySummaries: [],
      ),
    );

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: summary != null
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ShopEfficiencyDetailPage(
                      summary: summary,
                      monthName: EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear),
                    ),
                  ),
                );
              }
            : null,
        child: Container(
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shortName,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.85),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                shop.totalPoints.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: isPositive ? AppColors.success : Color(0xFFEF5350),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '+${shop.earnedPoints.toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 10.sp, color: AppColors.success),
                      ),
                      Text(
                        '/',
                        style: TextStyle(fontSize: 10.sp, color: Colors.white.withOpacity(0.3)),
                      ),
                      Text(
                        '-${shop.lostPoints.toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 10.sp, color: Color(0xFFEF5350)),
                      ),
                    ],
                  ),
                  Text(
                    '${shop.recordsCount} зап.',
                    style: TextStyle(
                      fontSize: 9.sp,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
        ),
      ),
    );
  }

  /// Компактные категории в одной карточке
  Widget _buildManagerCategoriesCompact(ManagerEfficiencyData efficiency) {
    final c = efficiency.categoryBreakdown;

    // All 12 categories with icon, name, points, color
    final items = [
      (Icons.swap_horiz,           'Пересменка',   c.shiftPoints,          const Color(0xFFf093fb)),
      (Icons.inventory_2,          'Пересчёт',     c.recountPoints,        const Color(0xFF4facfe)),
      (Icons.assignment_turned_in, 'Сдать смену',  c.shiftHandoverPoints,  const Color(0xFF30cfd0)),
      (Icons.assignment,           'Задачи',       c.tasksPoints,          const Color(0xFF7E57C2)),
      (Icons.access_time,          'Посещаемость', c.attendancePoints,     const Color(0xFFf7971e)),
      (Icons.star_outline,         'Отзывы',       c.reviewsPoints,        const Color(0xFF56ab2f)),
      (Icons.receipt_long,         'РКО',          c.rkoPoints,            const Color(0xFFe96c1e)),
      (Icons.coffee,               'Кофемашина',   c.coffeeMachinePoints,  const Color(0xFF8B5E3C)),
      (Icons.mail_outline,         'Конверты',     c.envelopePoints,       const Color(0xFFe040fb)),
      (Icons.search,               'Поиск товара', c.productSearchPoints,  const Color(0xFF00bcd4)),
      (Icons.shopping_cart,        'Заказы',       c.orderPoints,          const Color(0xFF43a047)),
      (Icons.person_add,           'Приглашения',  c.referralPoints,       const Color(0xFF26C6DA)),
    ];

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.category, size: 16, color: AppColors.gold),
              SizedBox(width: 6),
              Text(
                'Категории оценки',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.gold,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          // Grid 2 columns
          for (int i = 0; i < items.length; i += 2) ...[
            Row(
              children: [
                Expanded(
                  child: _buildCompactCategoryItem(
                    items[i].$1, items[i].$2, items[i].$3, items[i].$4,
                  ),
                ),
                if (i + 1 < items.length)
                  Expanded(
                    child: _buildCompactCategoryItem(
                      items[i + 1].$1, items[i + 1].$2, items[i + 1].$3, items[i + 1].$4,
                    ),
                  )
                else
                  const Expanded(child: SizedBox()),
              ],
            ),
            if (i + 2 < items.length) SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactCategoryItem(
    IconData icon,
    String name,
    double points,
    Color color,
  ) {
    final isPositive = points >= 0;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.w),
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 10.w),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                Text(
                  '${isPositive && points > 0 ? '+' : ''}${points.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? AppColors.success : Color(0xFFEF5350),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Информация о категории эффективности
class _CategoryInfo {
  final EfficiencyCategory category;
  final String name;
  final String description;

  _CategoryInfo(this.category, this.name, this.description);
}

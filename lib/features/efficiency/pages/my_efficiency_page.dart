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
import '../../../core/utils/logger.dart';

/// Страница "Моя эффективность" для сотрудника
class MyEfficiencyPage extends StatefulWidget {
  const MyEfficiencyPage({super.key});

  @override
  State<MyEfficiencyPage> createState() => _MyEfficiencyPageState();
}

class _MyEfficiencyPageState extends State<MyEfficiencyPage> with SingleTickerProviderStateMixin {
  // Dark emerald palette
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  bool _isLoading = true;
  EfficiencySummary? _summary;
  EfficiencySummary? _previousMonthSummary; // Для сравнения
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
  bool _isManagerWithShops = false; // true если admin с managedShopIds

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
      setState(() {
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

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

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
          Logger.debug('Phone was empty, restored from prefs: $savedPhone');
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
      Logger.debug('   phone: "${roleData?.phone}"');
      Logger.debug('   managedShopIds: ${roleData?.managedShopIds}');

      // Проверяем, является ли пользователь admin/developer с managedShopIds
      final isAdmin = roleData?.role == UserRole.admin || roleData?.role == UserRole.developer;
      final hasManagedShops = roleData?.managedShopIds?.isNotEmpty ?? false;
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

      // Находим данные текущего сотрудника за выбранный месяц
      EfficiencySummary? mySummary;
      for (final summary in data.byEmployee) {
        if (summary.entityName == employeeName) {
          mySummary = summary;
          break;
        }
      }

      // Находим данные за предыдущий месяц (для сравнения)
      EfficiencySummary? prevSummary;
      for (final summary in prevData.byEmployee) {
        if (summary.entityName == employeeName) {
          prevSummary = summary;
          break;
        }
      }

      // Загружаем премии/штрафы
      BonusPenaltySummary? bonusSummary;
      if (_employeeId != null && _employeeId!.isNotEmpty) {
        bonusSummary = await BonusPenaltyService.getSummary(_employeeId!);
      }

      // Загружаем баллы за приглашения
      EmployeeReferralPoints? referralPoints;
      if (_employeeId != null && _employeeId!.isNotEmpty) {
        referralPoints = await ReferralService.getEmployeePoints(_employeeId!);
      }

      // Загружаем результаты тестирования для текущего сотрудника
      double? avgScore;
      int totalTests = 0;
      try {
        final testResults = await TestResultService.getResults();
        // Фильтруем по телефону текущего сотрудника
        final myTests = testResults.where((t) {
          final phone = _employeeId?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
          final testPhone = t.employeePhone.replaceAll(RegExp(r'[^0-9]'), '');
          return testPhone == phone || t.employeeName == employeeName;
        }).toList();

        if (myTests.isNotEmpty) {
          totalTests = myTests.length;
          final totalScore = myTests.fold<int>(0, (sum, t) => sum + t.score);
          // Средний балл = сумма баллов / количество тестов
          avgScore = totalScore / totalTests;
        }
      } catch (e) {
        // Игнорируем ошибки загрузки тестов
      }

      setState(() {
        _summary = mySummary;
        _previousMonthSummary = prevSummary;
        _bonusSummary = bonusSummary;
        _referralPoints = referralPoints;
        _avgTestScore = avgScore;
        _totalTests = totalTests;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки данных: $e';
        _isLoading = false;
      });
    }
  }

  /// Загружает данные эффективности для управляющего (admin)
  Future<void> _loadManagerEfficiency(String phone) async {
    try {
      final month = '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';

      final efficiency = await ManagerEfficiencyService.getManagerEfficiencyWithComparison(
        phone: phone,
        currentMonth: month,
      );

      setState(() {
        _managerEfficiency = efficiency ?? ManagerEfficiencyData.empty();
        _employeeName = _userRole?.displayName;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки данных: $e';
        _isLoading = false;
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
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Моя эффективность',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Tab bar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: _gold,
                  indicatorWeight: 3,
                  labelColor: _gold,
                  unselectedLabelColor: Colors.white.withOpacity(0.5),
                  dividerColor: Colors.transparent,
                  tabs: const [
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
            const CircularProgressIndicator(color: _gold),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.8)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _night,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Повторить'),
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
            const SizedBox(height: 16),
            Text(
              'Нет данных за ${EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear)}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Баллы появятся после оценки ваших отчетов',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
            if (_employeeName != null) ...[
              const SizedBox(height: 16),
              Text(
                _employeeName!,
                style: TextStyle(
                  fontSize: 13,
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
        color: _gold,
        backgroundColor: _emeraldDark,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Показываем заглушку вместо основной карточки
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '0',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                    Text(
                      'баллов за отчёты',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildBonusPenaltySection(),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      color: _gold,
      backgroundColor: _emeraldDark,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTotalCard(),
            const SizedBox(height: 16),
            _buildRatingButton(),
            const SizedBox(height: 16),
            _buildTestScoreCard(),
            _buildBonusPenaltySection(),
            _buildCategoriesCard(),
            const SizedBox(height: 16),
            _buildShopsCard(),
            const SizedBox(height: 16),
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
        borderRadius: BorderRadius.circular(14),
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
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.leaderboard,
                  color: _gold,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Мой рейтинг',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Позиция среди сотрудников',
                      style: TextStyle(
                        fontSize: 14,
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
      return const SizedBox.shrink();
    }

    // Определяем цвет в зависимости от среднего балла (из 20)
    Color scoreColor;
    if (_avgTestScore! >= 16) {
      scoreColor = const Color(0xFF4CAF50);
    } else if (_avgTestScore! >= 12) {
      scoreColor = const Color(0xFFFFB74D);
    } else {
      scoreColor = const Color(0xFFEF5350);
    }

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _emerald.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.quiz,
                  color: Colors.white.withOpacity(0.8),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Тестирование',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Пройдено тестов: $_totalTests',
                      style: TextStyle(
                        fontSize: 13,
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
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                  Text(
                    'средний балл',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear),
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _summary!.formattedTotal,
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: isPositive ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
            ),
          ),
          Text(
            'баллов',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          // Сравнение с прошлым месяцем
          if (change != null) ...[
            const SizedBox(height: 8),
            _buildComparisonRow(change),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem(
                '+${_summary!.earnedPoints.toStringAsFixed(1)}',
                'Заработано',
                const Color(0xFF4CAF50),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withOpacity(0.1),
              ),
              _buildStatItem(
                '-${_summary!.lostPoints.toStringAsFixed(1)}',
                'Потеряно',
                const Color(0xFFEF5350),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isImproved
            ? const Color(0xFF4CAF50).withOpacity(0.15)
            : const Color(0xFFEF5350).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isImproved ? Icons.trending_up : Icons.trending_down,
            size: 18,
            color: isImproved ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
          ),
          const SizedBox(width: 4),
          Text(
            '$changeText к прошлому месяцу',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isImproved ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
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
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withOpacity(0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildBonusPenaltySection() {
    if (_bonusSummary == null) return const SizedBox.shrink();

    final hasCurrentMonth = _bonusSummary!.currentMonthTotal != 0 ||
        _bonusSummary!.currentMonthRecords.isNotEmpty;
    final hasPreviousMonth = _bonusSummary!.previousMonthTotal != 0 ||
        _bonusSummary!.previousMonthRecords.isNotEmpty;

    if (!hasCurrentMonth && !hasPreviousMonth) return const SizedBox.shrink();

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
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildReferralPointsSection() {
    if (_referralPoints == null) return const SizedBox.shrink();

    final hasCurrentMonth = _referralPoints!.currentMonthPoints > 0 ||
        _referralPoints!.currentMonthReferrals > 0;
    final hasPreviousMonth = _referralPoints!.previousMonthPoints > 0 ||
        _referralPoints!.previousMonthReferrals > 0;

    if (!hasCurrentMonth && !hasPreviousMonth) return const SizedBox.shrink();

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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF42A5F5).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.person_add,
              color: Color(0xFF42A5F5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isPreviousMonth
                        ? Colors.white.withOpacity(0.5)
                        : Colors.white.withOpacity(0.9),
                  ),
                ),
                Text(
                  '$referralsCount ${_getReferralsLabel(referralsCount)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
          const Text(
            '+',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF42A5F5),
            ),
          ),
          Text(
            '$points',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF42A5F5),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'балл${_getPointsEnding(points)}',
            style: TextStyle(
              fontSize: 12,
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
    final color = isPositive ? const Color(0xFF4CAF50) : const Color(0xFFEF5350);
    final formattedTotal = '${isPositive ? '+' : ''}${total.toStringAsFixed(0)} руб';

    return Container(
      margin: EdgeInsets.only(bottom: isPreviousMonth ? 0 : 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
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
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.monetization_on,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
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
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                formattedTotal,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
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
  static const List<_CategoryInfo> _allCategories = [
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Критерии оценки',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _gold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'По этим показателям оценивается ваша эффективность',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 12),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getCategoryIcon(info.category),
              size: 20,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.name,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                Text(
                  info.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '0.00',
            style: TextStyle(
              fontSize: 16,
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _getCategoryColor(categoryData.baseCategory).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getCategoryIcon(categoryData.baseCategory),
              size: 20,
              color: _getCategoryColor(categoryData.baseCategory),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              categoryData.name,  // Используем настоящее имя категории
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ),
          Text(
            formattedPoints,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isPositive ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
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
        return const Color(0xFF42A5F5);
      case EfficiencyCategory.recount:
        return const Color(0xFFAB47BC);
      case EfficiencyCategory.shiftHandover:
        return const Color(0xFF26A69A);
      case EfficiencyCategory.attendance:
        return const Color(0xFFFFB74D);
      case EfficiencyCategory.test:
        return const Color(0xFF5C6BC0);
      case EfficiencyCategory.reviews:
        return _gold;
      case EfficiencyCategory.productSearch:
        return const Color(0xFF26C6DA);
      case EfficiencyCategory.rko:
        return const Color(0xFF8D6E63);
      case EfficiencyCategory.orders:
        return const Color(0xFF66BB6A);
      case EfficiencyCategory.shiftPenalty:
        return const Color(0xFFEF5350);
      case EfficiencyCategory.tasks:
        return const Color(0xFF7E57C2);
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
      return const SizedBox.shrink();
    }

    // Сортируем по баллам
    final sortedShops = pointsByShop.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'По магазинам',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _gold,
            ),
          ),
          const SizedBox(height: 12),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _emerald.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.store,
              size: 20,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              shopAddress,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withOpacity(0.9),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formattedPoints,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isPositive ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRecordsCard() {
    // Сортируем записи по дате (новые сначала)
    final sortedRecords = List<EfficiencyRecord>.from(_summary!.records)
      ..sort((a, b) => b.date.compareTo(a.date));

    // Берем последние 20 записей
    final recentRecords = sortedRecords.take(20).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Последние записи',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _gold,
                ),
              ),
              Text(
                'Всего: ${_summary!.recordsCount}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recentRecords.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 45,
            child: Text(
              dateFormat.format(record.date),
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.categoryName,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  record.formattedRawValue,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (shop.isNotEmpty)
                  Text(
                    shop,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            record.formattedPoints,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isPositive ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
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
      color: _gold,
      backgroundColor: _emeraldDark,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Хедер с общим % и двумя компонентами
            _buildManagerHeaderCard(efficiency),
            const SizedBox(height: 10),
            // Компактные категории
            _buildManagerCategoriesCompact(efficiency),
            const SizedBox(height: 10),
            // Магазины в виде сетки
            _buildManagerShopsGrid(efficiency),
          ],
        ),
      ),
    );
  }

  /// Компактная карточка-хедер с общим процентом и статистикой
  Widget _buildManagerHeaderCard(ManagerEfficiencyData efficiency) {
    final totalPercent = efficiency.totalPercentage;
    final color = totalPercent >= 70
        ? _emerald
        : totalPercent >= 40
            ? const Color(0xFFFFB74D)
            : const Color(0xFFEF5350);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Общий процент
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.analytics,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Общая эффективность',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${totalPercent.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
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
          const SizedBox(height: 16),
          // Магазины и Отчёты - компактная строка
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
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
          const SizedBox(height: 12),
          // Баллы: Заработано / Потеряно / Итого
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCompactStatItem(
                '+${efficiency.totalEarned.toStringAsFixed(0)}',
                'Заработано',
                const Color(0xFF69F0AE),
              ),
              _buildCompactStatItem(
                '-${efficiency.totalLost.toStringAsFixed(0)}',
                'Потеряно',
                const Color(0xFFFF8A80),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive ? Icons.trending_up : Icons.trending_down,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            '${isPositive ? '+' : ''}${change.toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 13,
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
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 11,
              ),
            ),
            Row(
              children: [
                Text(
                  '${value.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (change != null && change != 0) ...[
                  const SizedBox(width: 4),
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
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  /// Магазины в виде сетки (2 в ряд)
  Widget _buildManagerShopsGrid(ManagerEfficiencyData efficiency) {
    if (efficiency.shopBreakdown.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.store, size: 16, color: _gold),
              const SizedBox(width: 6),
              const Text(
                'Магазины',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _gold,
                ),
              ),
              const Spacer(),
              Text(
                '${efficiency.shopBreakdown.length} шт.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
              const SizedBox(width: 8),
              Expanded(
                child: hasSecond
                    ? _buildGridShopCard(shops[i + 1])
                    : const SizedBox.shrink(),
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
    final color = isPositive ? _emerald : const Color(0xFFEF5350);

    // Извлекаем короткое название магазина
    String shortName = shop.shopName;
    if (shortName.contains(',')) {
      shortName = shortName.split(',').first;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shortName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.85),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                shop.totalPoints.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isPositive ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
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
                        style: const TextStyle(fontSize: 10, color: Color(0xFF4CAF50)),
                      ),
                      Text(
                        '/',
                        style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.3)),
                      ),
                      Text(
                        '-${shop.lostPoints.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 10, color: Color(0xFFEF5350)),
                      ),
                    ],
                  ),
                  Text(
                    '${shop.recordsCount} зап.',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Компактные категории в одной карточке
  Widget _buildManagerCategoriesCompact(ManagerEfficiencyData efficiency) {
    final categories = efficiency.categoryBreakdown;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.category, size: 16, color: _gold),
              SizedBox(width: 6),
              Text(
                'Категории оценки',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCompactCategoryItem(
                  Icons.swap_horiz,
                  'Пересменка',
                  categories.shiftPoints,
                  const Color(0xFFf093fb),
                ),
              ),
              Expanded(
                child: _buildCompactCategoryItem(
                  Icons.inventory_2,
                  'Пересчёт',
                  categories.recountPoints,
                  const Color(0xFF4facfe),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildCompactCategoryItem(
                  Icons.assignment_turned_in,
                  'Сдать смену',
                  categories.shiftHandoverPoints,
                  const Color(0xFF30cfd0),
                ),
              ),
              Expanded(
                child: _buildCompactCategoryItem(
                  Icons.assignment,
                  'Задачи',
                  categories.tasksPoints,
                  const Color(0xFF7E57C2),
                ),
              ),
            ],
          ),
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
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                Text(
                  '${isPositive && points > 0 ? '+' : ''}${points.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
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

  const _CategoryInfo(this.category, this.name, this.description);
}

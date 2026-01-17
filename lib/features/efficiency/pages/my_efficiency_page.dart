import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/efficiency_data_model.dart';
import '../services/efficiency_data_service.dart';
import '../utils/efficiency_utils.dart';
import '../widgets/my_efficiency_widgets.dart';
import '../widgets/efficiency_common_widgets.dart';
import '../../employees/pages/employees_page.dart';
import '../../employees/services/user_role_service.dart';
import '../../bonuses/models/bonus_penalty_model.dart';
import '../../bonuses/services/bonus_penalty_service.dart';
import '../../bonuses/pages/bonus_penalty_history_page.dart';
import '../../referrals/models/referral_stats_model.dart';
import '../../referrals/services/referral_service.dart';
import '../../rating/pages/my_rating_page.dart';
import '../../tests/services/test_result_service.dart';

/// Страница "Моя эффективность" для сотрудника
class MyEfficiencyPage extends StatefulWidget {
  const MyEfficiencyPage({super.key});

  @override
  State<MyEfficiencyPage> createState() => _MyEfficiencyPageState();
}

class _MyEfficiencyPageState extends State<MyEfficiencyPage> {
  bool _isLoading = true;
  EfficiencySummary? _summary;
  String? _error;
  String? _employeeName;
  String? _employeeId;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  BonusPenaltySummary? _bonusSummary;
  EmployeeReferralPoints? _referralPoints;
  double? _avgTestScore; // Средний балл тестирования
  int _totalTests = 0; // Количество тестов

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Получаем имя текущего сотрудника
      final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
      final roleData = await UserRoleService.loadUserRole();
      final employeeName = systemEmployeeName ?? roleData?.displayName;

      if (employeeName == null || employeeName.isEmpty) {
        setState(() {
          _error = 'Не удалось определить сотрудника';
          _isLoading = false;
        });
        return;
      }

      _employeeName = employeeName;

      // Получаем ID сотрудника для загрузки премий/штрафов (используем телефон)
      final prefs = await SharedPreferences.getInstance();
      _employeeId = prefs.getString('user_phone');

      // Загружаем данные эффективности за выбранный месяц
      final data = await EfficiencyDataService.loadMonthData(
        _selectedYear,
        _selectedMonth,
        forceRefresh: forceRefresh,
      );

      // Находим данные текущего сотрудника
      EfficiencySummary? mySummary;
      for (final summary in data.byEmployee) {
        if (summary.entityName == employeeName) {
          mySummary = summary;
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Моя эффективность'),
        backgroundColor: EfficiencyUtils.primaryColor,
        actions: [
          MonthPickerButton(
            selectedMonth: _selectedMonth,
            selectedYear: _selectedYear,
            onMonthSelected: (selection) {
              setState(() {
                _selectedYear = selection['year']!;
                _selectedMonth = selection['month']!;
              });
              _loadData();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF004D40)),
            SizedBox(height: 16),
            Text('Загрузка данных...'),
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
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
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
            Icon(Icons.trending_up, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Нет данных за ${EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear)}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Баллы появятся после оценки ваших отчетов',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            if (_employeeName != null) ...[
              const SizedBox(height: 16),
              Text(
                _employeeName!,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[400],
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
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Показываем заглушку вместо основной карточки
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '0',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[400],
                        ),
                      ),
                      const Text(
                        'баллов за отчёты',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
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
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF004D40).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.leaderboard,
                  color: Color(0xFF004D40),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Мой рейтинг',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Позиция среди сотрудников',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
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
      scoreColor = Colors.green;
    } else if (_avgTestScore! >= 12) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = Colors.red;
    }

    return Column(
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.quiz,
                    color: Colors.indigo,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Тестирование',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Пройдено тестов: $_totalTests',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
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
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTotalCard() {
    final isPositive = _summary!.totalPoints >= 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _summary!.formattedTotal,
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: isPositive ? Colors.green[700] : Colors.red[700],
              ),
            ),
            const Text(
              'баллов',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatItem(
                  '+${_summary!.earnedPoints.toStringAsFixed(1)}',
                  'Заработано',
                  Colors.green,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey[300],
                ),
                _buildStatItem(
                  '-${_summary!.lostPoints.toStringAsFixed(1)}',
                  'Потеряно',
                  Colors.red,
                ),
              ],
            ),
          ],
        ),
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
            color: Colors.grey[600],
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
    return Card(
      margin: EdgeInsets.only(bottom: isPreviousMonth ? 0 : 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.person_add,
                color: Colors.blue,
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
                      color: isPreviousMonth ? Colors.grey[600] : Colors.black,
                    ),
                  ),
                  Text(
                    '$referralsCount ${_getReferralsLabel(referralsCount)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '+$points',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'балл${_getPointsEnding(points)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
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
    final color = isPositive ? Colors.green : Colors.red;
    final formattedTotal = '${isPositive ? '+' : ''}${total.toStringAsFixed(0)} руб';

    return Card(
      margin: EdgeInsets.only(bottom: isPreviousMonth ? 0 : 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
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
                        color: isPreviousMonth ? Colors.grey[600] : Colors.black,
                      ),
                    ),
                    if (records.isNotEmpty)
                      Text(
                        '${records.length} ${_getRecordsLabel(records.length)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
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
                color: Colors.grey[400],
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

  Widget _buildCategoriesCard() {
    // Сортируем категории по баллам (от большего к меньшему по абсолютному значению)
    final sortedCategories = _summary!.pointsByCategory.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'По категориям',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 12),
            if (sortedCategories.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Нет данных',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ...sortedCategories.map((entry) => _buildCategoryRow(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRow(EfficiencyCategory category, double points) {
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
              color: _getCategoryColor(category).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getCategoryIcon(category),
              size: 20,
              color: _getCategoryColor(category),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              category.displayName,
              style: const TextStyle(fontSize: 15),
            ),
          ),
          Text(
            formattedPoints,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isPositive ? Colors.green[700] : Colors.red[700],
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
        return Colors.blue;
      case EfficiencyCategory.recount:
        return Colors.purple;
      case EfficiencyCategory.shiftHandover:
        return Colors.teal;
      case EfficiencyCategory.attendance:
        return Colors.orange;
      case EfficiencyCategory.test:
        return Colors.indigo;
      case EfficiencyCategory.reviews:
        return Colors.amber;
      case EfficiencyCategory.productSearch:
        return Colors.cyan;
      case EfficiencyCategory.rko:
        return Colors.brown;
      case EfficiencyCategory.orders:
        return Colors.green;
      case EfficiencyCategory.shiftPenalty:
        return Colors.red;
      case EfficiencyCategory.tasks:
        return Colors.deepPurple;
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

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'По магазинам',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 12),
            ...sortedShops.map((entry) => _buildShopRow(entry.key, entry.value)),
          ],
        ),
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
              color: const Color(0xFFE0F2F1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.store,
              size: 20,
              color: Color(0xFF004D40),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              shopAddress,
              style: const TextStyle(fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formattedPoints,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isPositive ? Colors.green[700] : Colors.red[700],
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

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
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
                    color: Color(0xFF004D40),
                  ),
                ),
                Text(
                  'Всего: ${_summary!.recordsCount}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
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
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ...recentRecords.map((record) => _buildRecordRow(record)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordRow(EfficiencyRecord record) {
    final dateFormat = DateFormat('dd.MM');
    final isPositive = record.points >= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 45,
            child: Text(
              dateFormat.format(record.date),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
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
                  style: const TextStyle(fontSize: 14),
                ),
                // Для штрафов берем shopAddress из rawValue
                Builder(builder: (context) {
                  String shop = record.shopAddress;
                  if (shop.isEmpty && record.category == EfficiencyCategory.shiftPenalty) {
                    if (record.rawValue is Map && record.rawValue['shopAddress'] != null) {
                      shop = record.rawValue['shopAddress'];
                    }
                  }
                  if (shop.isNotEmpty) {
                    return Text(
                      shop,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                      overflow: TextOverflow.ellipsis,
                    );
                  }
                  return const SizedBox.shrink();
                }),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(${record.formattedRawValue})',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            record.formattedPoints,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isPositive ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ],
      ),
    );
  }
}

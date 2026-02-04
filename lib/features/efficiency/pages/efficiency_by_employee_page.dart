import 'package:flutter/material.dart';
import '../models/efficiency_data_model.dart';
import '../services/efficiency_data_service.dart';
import '../widgets/efficiency_common_widgets.dart';
import '../utils/efficiency_utils.dart';
import 'employee_efficiency_detail_page.dart';
import '../../referrals/services/referral_service.dart';
import '../../referrals/models/referral_stats_model.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/services/employee_registration_service.dart';

/// Страница списка эффективности по сотрудникам
class EfficiencyByEmployeePage extends StatefulWidget {
  const EfficiencyByEmployeePage({super.key});

  @override
  State<EfficiencyByEmployeePage> createState() => _EfficiencyByEmployeePageState();
}

class _EfficiencyByEmployeePageState extends State<EfficiencyByEmployeePage> {
  bool _isLoading = true;
  EfficiencyData? _data;
  List<EfficiencySummary> _filteredEmployees = []; // Только верифицированные
  String? _error;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  Map<String, EmployeeReferralPoints> _referralPointsByEmployee = {};
  bool _isLoadingReferrals = false;

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
      // Загружаем данные эффективности и информацию о верификации параллельно
      final results = await Future.wait([
        EfficiencyDataService.loadMonthData(
          _selectedYear,
          _selectedMonth,
          forceRefresh: forceRefresh,
        ),
        _loadVerifiedEmployeeNames(),
      ]);

      final data = results[0] as EfficiencyData;
      final verifiedNames = results[1] as Set<String>;

      // Фильтруем только верифицированных сотрудников
      final filtered = data.byEmployee.where((summary) {
        return verifiedNames.contains(summary.entityName.toLowerCase());
      }).toList();

      setState(() {
        _data = data;
        _filteredEmployees = filtered;
        _isLoading = false;
      });

      // Загружаем данные о приглашениях после основных данных
      _loadReferralPoints();
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки данных: $e';
        _isLoading = false;
      });
    }
  }

  /// Загрузить Set имён верифицированных сотрудников (в нижнем регистре)
  Future<Set<String>> _loadVerifiedEmployeeNames() async {
    try {
      // Загружаем сотрудников и регистрации параллельно
      final results = await Future.wait([
        EmployeeService.getEmployees(),
        EmployeeRegistrationService.getAllRegistrations(),
      ]);

      final employees = results[0] as List<dynamic>;
      final registrations = results[1] as List<dynamic>;

      // Создаём Map телефон -> isVerified
      final phoneToVerified = <String, bool>{};
      for (final reg in registrations) {
        final phone = reg.phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
        if (phone.isNotEmpty) {
          phoneToVerified[phone] = reg.isVerified;
        }
      }

      // Создаём Set верифицированных имён
      final verifiedNames = <String>{};
      for (final emp in employees) {
        final phone = emp.phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
        if (phone.isNotEmpty && phoneToVerified[phone] == true) {
          verifiedNames.add(emp.name.toLowerCase());
        }
      }

      return verifiedNames;
    } catch (e) {
      // При ошибке возвращаем пустой Set - не показываем никого
      return <String>{};
    }
  }

  Future<void> _loadReferralPoints() async {
    if (_filteredEmployees.isEmpty) return;

    setState(() => _isLoadingReferrals = true);

    try {
      // Загружаем всех сотрудников чтобы получить Map: имя -> ID
      final employees = await EmployeeService.getEmployees();
      final nameToIdMap = <String, String>{};
      for (final emp in employees) {
        nameToIdMap[emp.name.toLowerCase()] = emp.id;
      }

      final Map<String, EmployeeReferralPoints> pointsMap = {};

      // Для каждого сотрудника в отфильтрованном списке
      for (final summary in _filteredEmployees) {
        final employeeName = summary.entityId.toLowerCase();
        final employeeId = nameToIdMap[employeeName];

        if (employeeId != null) {
          try {
            final points = await ReferralService.getEmployeePoints(employeeId);
            if (points != null) {
              // Сохраняем по имени (entityId), чтобы легко найти в UI
              pointsMap[summary.entityId] = points;
            }
          } catch (e) {
            // Игнорируем ошибки для отдельных сотрудников
          }
        }
      }

      if (mounted) {
        setState(() {
          _referralPointsByEmployee = pointsMap;
          _isLoadingReferrals = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingReferrals = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('По сотрудникам'),
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
      return const EfficiencyLoadingState();
    }

    if (_error != null) {
      return EfficiencyErrorState(
        error: _error!,
        onRetry: _loadData,
      );
    }

    if (_data == null || _filteredEmployees.isEmpty) {
      return EfficiencyEmptyState(
        monthName: EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredEmployees.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildSummaryCard();
          }
          return _buildEmployeeCard(_filteredEmployees[index - 1], index);
        },
      ),
    );
  }

  Widget _buildSummaryCard() {
    return EfficiencySummaryCard(
      summaries: _filteredEmployees,
      additionalInfo: '${_filteredEmployees.length} сотрудников',
    );
  }

  Widget _buildEmployeeCard(EfficiencySummary summary, int position) {
    final isPositive = summary.totalPoints >= 0;

    // Определяем цвет медали для топ-3
    Color? medalColor;
    if (position == 1) medalColor = const Color(0xFFFFD700); // Золото
    if (position == 2) medalColor = const Color(0xFFC0C0C0); // Серебро
    if (position == 3) medalColor = const Color(0xFFCD7F32); // Бронза

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EmployeeEfficiencyDetailPage(
                summary: summary,
                monthName: EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear),
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Позиция / Медаль
                  if (medalColor != null)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: medalColor.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.emoji_events,
                          color: medalColor,
                          size: 20,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$position',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      summary.entityName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isPositive ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      summary.formattedTotal,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isPositive ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Row(
                  children: [
                    Text(
                      '+${summary.earnedPoints.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.green[600],
                      ),
                    ),
                    const Text(' / ', style: TextStyle(color: Colors.grey)),
                    Text(
                      '-${summary.lostPoints.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.red[600],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${summary.recordsCount} записей',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.grey[400],
                      size: 20,
                    ),
                  ],
                ),
              ),
              if (_referralPointsByEmployee.containsKey(summary.entityId) &&
                  (_referralPointsByEmployee[summary.entityId]!.currentMonthPoints > 0 ||
                   _referralPointsByEmployee[summary.entityId]!.currentMonthReferrals > 0))
                Padding(
                  padding: const EdgeInsets.only(left: 44, top: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_add_alt_outlined,
                        size: 14,
                        color: Colors.teal[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Приглашения: ${_referralPointsByEmployee[summary.entityId]!.currentMonthReferrals} клиент${_getReferralsEnding(_referralPointsByEmployee[summary.entityId]!.currentMonthReferrals)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '+${_referralPointsByEmployee[summary.entityId]!.currentMonthPoints}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal[600],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: EfficiencyProgressBar(summary: summary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getReferralsEnding(int count) {
    if (count % 10 == 1 && count % 100 != 11) return '';
    if (count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20)) {
      return 'а';
    }
    return 'ов';
  }
}

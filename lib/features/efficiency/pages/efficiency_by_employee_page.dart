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
import '../../../core/services/multitenancy_filter_service.dart';

/// Страница списка эффективности по сотрудникам
class EfficiencyByEmployeePage extends StatefulWidget {
  const EfficiencyByEmployeePage({super.key});

  @override
  State<EfficiencyByEmployeePage> createState() => _EfficiencyByEmployeePageState();
}

class _EfficiencyByEmployeePageState extends State<EfficiencyByEmployeePage> {
  // Dark emerald palette
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  bool _isLoading = true;
  EfficiencyData? _data;
  List<EfficiencySummary> _filteredEmployees = []; // Только верифицированные
  String? _error;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  Map<String, EmployeeReferralPoints> _referralPointsByEmployee = {};

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
      var filtered = data.byEmployee.where((summary) {
        return verifiedNames.contains(summary.entityName.toLowerCase());
      }).toList();

      // Фильтрация по мультитенантности — управляющий видит только сотрудников своих магазинов
      final allowedAddresses = await MultitenancyFilterService.getAllowedShopAddresses();
      if (allowedAddresses != null) {
        filtered = filtered.where((summary) {
          // Сотрудник отображается, если у него есть хотя бы одна запись из разрешённого магазина
          return summary.records.any((record) =>
            record.shopAddress.isNotEmpty && allowedAddresses.contains(record.shopAddress),
          );
        }).toList();
      }

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
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {});
      }
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
            colors: [_emeraldDark, _night],
            stops: [0.0, 0.3],
          ),
        ),
        child: Column(
          children: [
            // Custom AppBar
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'По сотрудникам',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
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
              ),
            ),
            // Body
            Expanded(child: _buildBody()),
          ],
        ),
      ),
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
      color: _gold,
      backgroundColor: _emerald,
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _emeraldDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _emerald.withOpacity(0.5)),
      ),
      child: Material(
        color: Colors.transparent,
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
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$position',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white.withOpacity(0.5),
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
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isPositive
                            ? Colors.green.withOpacity(0.15)
                            : Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        summary.formattedTotal,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isPositive
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFEF5350),
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
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF4CAF50),
                        ),
                      ),
                      Text(
                        ' / ',
                        style: TextStyle(color: Colors.white.withOpacity(0.3)),
                      ),
                      Text(
                        '-${summary.lostPoints.toStringAsFixed(1)}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFFEF5350),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${summary.recordsCount} записей',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.white.withOpacity(0.3),
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
                        const Icon(
                          Icons.person_add_alt_outlined,
                          size: 14,
                          color: _gold,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Приглашения: ${_referralPointsByEmployee[summary.entityId]!.currentMonthReferrals} клиент${_getReferralsEnding(_referralPointsByEmployee[summary.entityId]!.currentMonthReferrals)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '+${_referralPointsByEmployee[summary.entityId]!.currentMonthPoints}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _gold,
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

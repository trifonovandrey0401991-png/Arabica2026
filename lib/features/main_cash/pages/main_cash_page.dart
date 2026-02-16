import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/multitenancy_filter_service.dart';
import '../models/shop_cash_balance_model.dart';
import '../models/withdrawal_model.dart';
import '../models/withdrawal_expense_model.dart';
import '../services/main_cash_service.dart';
import '../services/withdrawal_service.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/services/user_role_service.dart';
import '../../employees/pages/employees_page.dart' show Employee;
import 'shop_balance_details_page.dart';
import 'withdrawal_shop_selection_page.dart';
import 'revenue_analytics_page.dart';
import 'store_managers_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Главная страница отчета по кассе
class MainCashPage extends StatefulWidget {
  const MainCashPage({super.key});

  @override
  State<MainCashPage> createState() => _MainCashPageState();
}

class _MainCashPageState extends State<MainCashPage> with SingleTickerProviderStateMixin {
  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);
  static final Color _gold = Color(0xFFD4AF37);

  late TabController _tabController;
  List<ShopCashBalance> _balances = [];
  List<Withdrawal> _withdrawals = [];
  bool _isLoading = true;
  bool _isDeveloper = false;
  String? _selectedShopFilter;
  int _withdrawalTabIndex = 0; // 0 = Все, 1 = Подтвержденные

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkRole();
    _loadData();
  }

  Future<void> _checkRole() async {
    final roleData = await UserRoleService.loadUserRole();
    if (mounted && roleData != null) {
      setState(() {
        _isDeveloper = roleData.isDeveloper;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      Logger.debug('🔄 Начало загрузки данных главной кассы');

      final balances = await MainCashService.getShopBalances();
      Logger.debug('✅ Загружено балансов: ${balances.length}');

      final allWithdrawals = await WithdrawalService.getWithdrawals();
      // Фильтрация по мультитенантности — управляющий видит только выемки своих магазинов
      final withdrawals = await MultitenancyFilterService.filterByShopAddress(
        allWithdrawals,
        (w) => w.shopAddress,
      );
      Logger.debug('✅ Загружено выемок: ${withdrawals.length}');

      // Логирование для отладки
      for (final b in balances) {
        Logger.debug('=== Баланс магазина: ${b.shopAddress}');
        Logger.debug('    ООО: ${b.oooBalance}');
        Logger.debug('    ИП: ${b.ipBalance}');
        Logger.debug('    Итого: ${b.totalBalance}');
      }

      for (final w in withdrawals) {
        Logger.debug('=== Выемка: ${w.id}');
        Logger.debug('    Магазин: ${w.shopAddress}');
        Logger.debug('    Сумма: ${w.totalAmount}');
        Logger.debug('    Расходов: ${w.expenses.length}');
      }

      if (!mounted) return;
      setState(() {
        _balances = balances;
        _withdrawals = withdrawals;
        _isLoading = false;
      });

      Logger.debug('✅ Состояние обновлено: балансов=${_balances.length}, выемок=${_withdrawals.length}');
    } catch (e, stackTrace) {
      Logger.error('❌ Ошибка загрузки данных', e);
      Logger.debug('Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  List<Withdrawal> get _filteredWithdrawals {
    var filtered = _withdrawals;

    // Исключаем отменённые выемки из всех вкладок
    filtered = filtered.where((w) => w.isActive).toList();

    // Фильтр по подтверждению
    if (_withdrawalTabIndex == 0) {
      filtered = filtered.where((w) => !w.confirmed).toList();
    } else {
      filtered = filtered.where((w) => w.confirmed).toList();
    }

    // Фильтр по магазину
    if (_selectedShopFilter != null) {
      filtered = filtered.where((w) => w.shopAddress == _selectedShopFilter).toList();
    }

    return filtered;
  }

  /// Группировка балансов по магазинам
  Map<String, ShopCashBalance> get _balancesByShop {
    final map = <String, ShopCashBalance>{};
    for (final balance in _balances) {
      map[balance.shopAddress] = balance;
    }
    return map;
  }

  List<String> get _shopAddresses {
    final addresses = <String>{};
    for (final b in _balances) {
      addresses.add(b.shopAddress);
    }
    for (final w in _withdrawals) {
      addresses.add(w.shopAddress);
    }
    final list = addresses.toList()..sort();
    return list;
  }

  Future<void> _navigateToWithdrawal() async {
    // Получить имя текущего пользователя
    final prefs = await SharedPreferences.getInstance();
    final currentUserName = prefs.getString('employeeName') ?? 'Администратор';

    if (!mounted) return;

    // Перейти к выбору магазина
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WithdrawalShopSelectionPage(
          currentUserName: currentUserName,
        ),
      ),
    );

    // Обновить данные после возврата
    _loadData();
  }

  /// Показать диалог внесения денег
  Future<void> _showDepositDialog() async {
    // Загружаем сотрудников и магазины
    List<Employee> employees = [];
    try {
      employees = await EmployeeService.getEmployees();
    } catch (e) {
      Logger.error('Ошибка загрузки сотрудников', e);
    }

    if (!mounted) return;

    String? selectedShop;
    String? selectedType; // 'ooo' или 'ip'
    String? selectedEmployeeId;
    String? selectedEmployeeName;
    final amountController = TextEditingController();
    final commentController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.add_circle, color: Colors.green[700]),
              SizedBox(width: 8),
              Text('Внесение денег'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Выбор магазина
                DropdownButtonFormField<String>(
                  value: selectedShop,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Магазин *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                  ),
                  items: _shopAddresses.map((address) => DropdownMenuItem(
                    value: address,
                    child: Text(address, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedShop = value);
                  },
                ),
                SizedBox(height: 16),
                // Выбор типа (ООО/ИП)
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: InputDecoration(
                    labelText: 'Куда вносить *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.account_balance),
                  ),
                  items: [
                    DropdownMenuItem(value: 'ooo', child: Text('ООО')),
                    DropdownMenuItem(value: 'ip', child: Text('ИП')),
                  ],
                  onChanged: (value) {
                    setDialogState(() => selectedType = value);
                  },
                ),
                SizedBox(height: 16),
                // Выбор сотрудника
                DropdownButtonFormField<String>(
                  value: selectedEmployeeId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Кто вносит *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  items: employees.map((e) => DropdownMenuItem(
                    value: e.id,
                    child: Text(e.name, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedEmployeeId = value;
                      selectedEmployeeName = employees.firstWhere((e) => e.id == value).name;
                    });
                  },
                ),
                SizedBox(height: 16),
                // Сумма
                TextField(
                  controller: amountController,
                  decoration: InputDecoration(
                    labelText: 'Сумма *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                    suffixText: 'руб',
                  ),
                  keyboardType: TextInputType.number,
                ),
                SizedBox(height: 16),
                // Комментарий (обязательный)
                TextField(
                  controller: commentController,
                  decoration: InputDecoration(
                    labelText: 'Комментарий *',
                    hintText: 'Укажите причину внесения',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.comment),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                // Валидация
                if (selectedShop == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Выберите магазин'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                if (selectedType == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Выберите куда вносить (ООО/ИП)'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                if (selectedEmployeeId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Выберите сотрудника'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Введите корректную сумму'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                if (commentController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Комментарий обязателен'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
              child: Text('Внести', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedShop != null && selectedType != null && selectedEmployeeId != null) {
      setState(() => _isLoading = true);

      try {
        final prefs = await SharedPreferences.getInstance();
        final adminName = prefs.getString('employeeName') ?? 'Администратор';
        final amount = double.parse(amountController.text);

        final deposit = Withdrawal(
          shopAddress: selectedShop!,
          employeeName: selectedEmployeeName!,
          employeeId: selectedEmployeeId!,
          type: selectedType!,
          totalAmount: amount,
          expenses: [
            WithdrawalExpense(
              amount: amount,
              comment: commentController.text.trim(),
              supplierName: 'Внесение',
            ),
          ],
          adminName: adminName,
          category: 'deposit',
        );

        final created = await WithdrawalService.createWithdrawal(deposit);

        if (created != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Внесение создано и ожидает подтверждения'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadData();
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка создания внесения'), backgroundColor: Colors.red),
          );
          setState(() => _isLoading = false);
        }
      } catch (e) {
        Logger.error('Ошибка создания внесения', e);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  /// Показать диалог переноса денег
  Future<void> _showTransferDialog() async {
    if (!mounted) return;

    String? selectedShop;
    String? transferDirection; // 'ooo_to_ip' или 'ip_to_ooo'
    final amountController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.swap_horiz, color: Colors.blue[700]),
              SizedBox(width: 8),
              Text('Перенос денег'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Выбор магазина
                DropdownButtonFormField<String>(
                  value: selectedShop,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Магазин *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                  ),
                  items: _shopAddresses.map((address) => DropdownMenuItem(
                    value: address,
                    child: Text(address, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedShop = value);
                  },
                ),
                SizedBox(height: 16),
                // Выбор направления
                Text(
                  'Направление переноса:',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setDialogState(() => transferDirection = 'ooo_to_ip');
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 12.w),
                          decoration: BoxDecoration(
                            color: transferDirection == 'ooo_to_ip'
                                ? Colors.blue.withOpacity(0.1)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(
                              color: transferDirection == 'ooo_to_ip'
                                  ? Colors.blue
                                  : Colors.grey[300]!,
                              width: transferDirection == 'ooo_to_ip' ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.arrow_forward,
                                color: transferDirection == 'ooo_to_ip'
                                    ? Colors.blue
                                    : Colors.grey,
                              ),
                              SizedBox(height: 4),
                              Text(
                                'ООО → ИП',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: transferDirection == 'ooo_to_ip'
                                      ? Colors.blue
                                      : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setDialogState(() => transferDirection = 'ip_to_ooo');
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 12.w),
                          decoration: BoxDecoration(
                            color: transferDirection == 'ip_to_ooo'
                                ? Colors.orange.withOpacity(0.1)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(
                              color: transferDirection == 'ip_to_ooo'
                                  ? Colors.orange
                                  : Colors.grey[300]!,
                              width: transferDirection == 'ip_to_ooo' ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.arrow_back,
                                color: transferDirection == 'ip_to_ooo'
                                    ? Colors.orange
                                    : Colors.grey,
                              ),
                              SizedBox(height: 4),
                              Text(
                                'ИП → ООО',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: transferDirection == 'ip_to_ooo'
                                      ? Colors.orange
                                      : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                // Сумма
                TextField(
                  controller: amountController,
                  decoration: InputDecoration(
                    labelText: 'Сумма *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                    suffixText: 'руб',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                // Валидация
                if (selectedShop == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Выберите магазин'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                if (transferDirection == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Выберите направление переноса'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Введите корректную сумму'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700]),
              child: Text('Перенести', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedShop != null && transferDirection != null) {
      setState(() => _isLoading = true);

      try {
        final prefs = await SharedPreferences.getInstance();
        final adminName = prefs.getString('employeeName') ?? 'Администратор';
        final amount = double.parse(amountController.text);

        // Определяем тип (откуда снимаем)
        final sourceType = transferDirection == 'ooo_to_ip' ? 'ooo' : 'ip';
        final directionText = transferDirection == 'ooo_to_ip' ? 'ООО → ИП' : 'ИП → ООО';

        final transfer = Withdrawal(
          shopAddress: selectedShop!,
          employeeName: adminName,
          employeeId: '',
          type: sourceType,
          totalAmount: amount,
          expenses: [
            WithdrawalExpense(
              amount: amount,
              comment: 'Перенос $directionText',
              supplierName: 'Перенос',
            ),
          ],
          adminName: adminName,
          category: 'transfer',
          transferDirection: transferDirection,
        );

        final created = await WithdrawalService.createWithdrawal(transfer);

        if (created != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Перенос создан и ожидает подтверждения'),
              backgroundColor: Colors.blue,
            ),
          );
          await _loadData();
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка создания переноса'), backgroundColor: Colors.red),
          );
          setState(() => _isLoading = false);
        }
      } catch (e) {
        Logger.error('Ошибка создания переноса', e);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatAmount(double amount) {
    final isNegative = amount < 0;
    final absAmount = amount.abs();
    String result;

    if (absAmount >= 1000000) {
      result = '${(absAmount / 1000000).toStringAsFixed(1)}M';
    } else if (absAmount >= 1000) {
      final k = absAmount / 1000;
      result = '${k.toStringAsFixed(k % 1 == 0 ? 0 : 1)}k';
    } else {
      result = absAmount.toStringAsFixed(0);
    }

    if (isNegative) {
      result = '-$result';
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: BoxDecoration(
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
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Главная Касса',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_isDeveloper) ...[
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => StoreManagersPage(),
                            ),
                          );
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Icon(Icons.people, color: Colors.white, size: 20),
                        ),
                      ),
                      SizedBox(width: 8),
                    ],
                    GestureDetector(
                      onTap: _loadData,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // TabBar
              Container(
                margin: EdgeInsets.symmetric(horizontal: 16.w),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: _gold,
                  indicatorWeight: 3,
                  labelColor: _gold,
                  unselectedLabelColor: Colors.white.withOpacity(0.5),
                  labelStyle: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerHeight: 0,
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_balance_wallet, size: 18),
                          SizedBox(width: 6),
                          Text('Касса'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.upload, size: 18),
                          SizedBox(width: 6),
                          Text('Выемки'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bar_chart, size: 18),
                          SizedBox(width: 6),
                          Text('Аналитика'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8),

              // Body
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: _gold))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildCashTab(),
                          _buildWithdrawalsTab(),
                          RevenueAnalyticsPage(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCashTab() {
    if (_balances.isEmpty) {
      return Center(
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
              child: Icon(Icons.inbox, size: 40, color: Colors.white.withOpacity(0.3)),
            ),
            SizedBox(height: 16),
            Text(
              'Нет данных о кассе',
              style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.5)),
            ),
            SizedBox(height: 8),
            Text(
              'Данные появятся после сдачи смен',
              style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.3)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Заголовок таблицы
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: _emerald.withOpacity(0.5),
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Магазин',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp, color: Colors.white.withOpacity(0.7)),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  'ООО',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp, color: Colors.white.withOpacity(0.7)),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  'ИП',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp, color: Colors.white.withOpacity(0.7)),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  'Итого',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp, color: Colors.white.withOpacity(0.7)),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(width: 28), // место для стрелки
            ],
          ),
        ),
        // Список магазинов с раскрывающимися деталями
        Expanded(
          child: ListView.builder(
            itemCount: _balances.length,
            itemBuilder: (context, index) {
              final balance = _balances[index];
              return _buildExpandableBalanceRow(balance);
            },
          ),
        ),
        // Кнопки действий
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: _emerald.withOpacity(0.6),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
          ),
          child: Row(
            children: [
              // Кнопка Выемка
              Expanded(
                child: GestureDetector(
                  onTap: _navigateToWithdrawal,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                    decoration: BoxDecoration(
                      color: _emeraldDark,
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.remove_circle_outline, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('Выемка', style: TextStyle(color: Colors.white, fontSize: 12.sp)),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              // Кнопка Внести
              Expanded(
                child: GestureDetector(
                  onTap: _showDepositDialog,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                    decoration: BoxDecoration(
                      color: Colors.green[700],
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('Внести', style: TextStyle(color: Colors.white, fontSize: 12.sp)),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              // Кнопка Перенести
              Expanded(
                child: GestureDetector(
                  onTap: _showTransferDialog,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                    decoration: BoxDecoration(
                      color: Colors.blue[700],
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.swap_horiz, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('Перенос', style: TextStyle(color: Colors.white, fontSize: 12.sp)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Итого по всем магазинам
        Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: _emeraldDark,
            border: Border(
              top: BorderSide(color: _gold.withOpacity(0.3)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'ИТОГО:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _gold,
                    fontSize: 14.sp,
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  _formatAmount(_balances.fold(0.0, (sum, b) => sum + b.oooBalance)),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 12.sp,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  _formatAmount(_balances.fold(0.0, (sum, b) => sum + b.ipBalance)),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 12.sp,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  _formatAmount(_balances.fold(0.0, (sum, b) => sum + b.totalBalance)),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _gold,
                    fontSize: 14.sp,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(width: 28), // для выравнивания со стрелкой
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpandableBalanceRow(ShopCashBalance balance) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShopBalanceDetailsPage(
                shopAddress: balance.shopAddress,
              ),
            ),
          ).then((_) => _loadData());
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  balance.shopAddress,
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12.sp, color: Colors.white.withOpacity(0.8)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  _formatAmount(balance.oooBalance),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    color: balance.oooBalance < 0 ? Colors.red[300] : Colors.white.withOpacity(0.7),
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  _formatAmount(balance.ipBalance),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    color: balance.ipBalance < 0 ? Colors.red[300] : Colors.white.withOpacity(0.7),
                  ),
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  _formatAmount(balance.totalBalance),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    color: balance.totalBalance < 0 ? Colors.red[300] : _gold,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 20, color: Colors.white.withOpacity(0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWithdrawalsTab() {
    return Column(
      children: [
        // Подвкладки: Все / Подтвержденные
        Container(
          margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _withdrawalTabIndex = 0),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    decoration: BoxDecoration(
                      color: _withdrawalTabIndex == 0 ? _gold.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(11.r),
                        bottomLeft: Radius.circular(11.r),
                      ),
                      border: _withdrawalTabIndex == 0
                          ? Border.all(color: _gold.withOpacity(0.3))
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.list_alt,
                          size: 18,
                          color: _withdrawalTabIndex == 0 ? _gold : Colors.white.withOpacity(0.4),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Все',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: _withdrawalTabIndex == 0 ? FontWeight.bold : FontWeight.w500,
                            color: _withdrawalTabIndex == 0 ? _gold : Colors.white.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _withdrawalTabIndex = 1),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    decoration: BoxDecoration(
                      color: _withdrawalTabIndex == 1 ? _gold.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(11.r),
                        bottomRight: Radius.circular(11.r),
                      ),
                      border: _withdrawalTabIndex == 1
                          ? Border.all(color: _gold.withOpacity(0.3))
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 18,
                          color: _withdrawalTabIndex == 1 ? _gold : Colors.white.withOpacity(0.4),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Подтверждённые',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: _withdrawalTabIndex == 1 ? FontWeight.bold : FontWeight.w500,
                            color: _withdrawalTabIndex == 1 ? _gold : Colors.white.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Фильтр по магазину
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 8.h),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedShopFilter,
                isExpanded: true,
                dropdownColor: _emeraldDark,
                icon: Icon(Icons.arrow_drop_down, color: _gold),
                hint: Row(
                  children: [
                    Icon(Icons.store, size: 18, color: _gold),
                    SizedBox(width: 8),
                    Text('Все магазины', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14.sp)),
                  ],
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text('Все магазины', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                  ),
                  ..._shopAddresses.map((address) => DropdownMenuItem(
                    value: address,
                    child: Text(address, overflow: TextOverflow.ellipsis),
                  )),
                ],
                onChanged: (value) {
                  setState(() => _selectedShopFilter = value);
                },
                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14.sp),
              ),
            ),
          ),
        ),
        // Список выемок
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: _gold))
              : _filteredWithdrawals.isEmpty
                  ? Center(
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
                            child: Icon(Icons.upload, size: 40, color: Colors.white.withOpacity(0.3)),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Выемок пока нет',
                            style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.5)),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Всего загружено: ${_withdrawals.length}',
                            style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.3)),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      itemCount: _filteredWithdrawals.length,
                      itemBuilder: (context, index) {
                        final withdrawal = _filteredWithdrawals[index];
                        return _buildWithdrawalCard(withdrawal);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildWithdrawalCard(Withdrawal withdrawal) {
    // Определить цвет границы и фона для отмененных выемок
    final isCancelled = withdrawal.isCancelled;

    // Определить цвет и иконку в зависимости от категории
    Color getCategoryColor() {
      if (isCancelled) return Colors.red;
      switch (withdrawal.category) {
        case 'deposit':
          return Colors.green;
        case 'transfer':
          return Colors.blue;
        case 'withdrawal':
        default:
          return withdrawal.type == 'ooo' ? Colors.blue : Colors.orange;
      }
    }

    IconData getCategoryIcon() {
      if (isCancelled) return Icons.cancel;
      switch (withdrawal.category) {
        case 'deposit':
          return Icons.add_circle;
        case 'transfer':
          return Icons.swap_horiz;
        case 'withdrawal':
        default:
          return withdrawal.type == 'ooo' ? Icons.business : Icons.store;
      }
    }

    final categoryColor = getCategoryColor();
    final categoryIcon = getCategoryIcon();

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isCancelled ? Colors.red.withOpacity(0.3) : Colors.white.withOpacity(0.1),
          width: isCancelled ? 2 : 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          expansionTileTheme: ExpansionTileThemeData(
            iconColor: Colors.white.withOpacity(0.4),
            collapsedIconColor: Colors.white.withOpacity(0.4),
          ),
        ),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
          childrenPadding: EdgeInsets.fromLTRB(12.w, 0.h, 12.w, 12.h),
          title: Row(
            children: [
              // Левая часть: иконка типа (или иконка отмены)
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: categoryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  categoryIcon,
                  size: 20,
                  color: categoryColor,
                ),
              ),
              SizedBox(width: 12),
              // Средняя часть: информация
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (isCancelled)
                          Text(
                            'ОТМЕНЕНО',
                            style: TextStyle(
                              color: Colors.red[300],
                              fontWeight: FontWeight.bold,
                              fontSize: 10.sp,
                            ),
                          ),
                        // Показываем категорию операции
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: categoryColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(
                            withdrawal.categoryDisplayName,
                            style: TextStyle(
                              color: isCancelled ? Colors.white.withOpacity(0.3) : categoryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 8.sp,
                              decoration: isCancelled ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        // Показываем тип (ООО/ИП) если это не перенос
                        if (!withdrawal.isTransfer)
                          Text(
                            withdrawal.typeDisplayName,
                            style: TextStyle(
                              color: isCancelled
                                  ? Colors.white.withOpacity(0.3)
                                  : (withdrawal.type == 'ooo' ? Colors.blue[300] : Colors.orange[300]),
                              fontWeight: FontWeight.bold,
                              fontSize: 10.sp,
                              decoration: isCancelled ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        Text(
                          withdrawal.formattedDateTime,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 9.sp,
                          ),
                        ),
                        if (withdrawal.confirmed && !isCancelled)
                          Icon(
                            Icons.check_circle,
                            size: 12,
                            color: Colors.green[400],
                          ),
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(
                      withdrawal.shopAddress,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.sp,
                        color: Colors.white.withOpacity(0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 1),
                    Text(
                      '${withdrawal.employeeName} • ${withdrawal.expenses.length} расход${_getExpenseEnding(withdrawal.expenses.length)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11.sp,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Правая часть: сумма
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${withdrawal.totalAmount.toStringAsFixed(0)} руб',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: _gold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(height: 1, color: Colors.white.withOpacity(0.1)),
                SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                  child: Text(
                    'Детализация расходов:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.sp,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ),
                SizedBox(height: 8),
                ...withdrawal.expenses.asMap().entries.map((entry) {
                  final index = entry.key;
                  final expense = entry.value;
                  return Container(
                    margin: EdgeInsets.only(bottom: 6.h),
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        // Номер
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _emerald.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11.sp,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        // Информация
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                expense.displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.sp,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                              if (expense.comment.isNotEmpty) ...[
                                SizedBox(height: 2),
                                Text(
                                  expense.comment,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.4),
                                    fontSize: 10.sp,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Сумма
                        Text(
                          '${expense.amount.toStringAsFixed(0)} руб',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.sp,
                            color: _gold,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (withdrawal.adminName != null && withdrawal.adminName!.isNotEmpty) ...[
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.w),
                    child: Text(
                      'Создал: ${withdrawal.adminName}',
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: Colors.white.withOpacity(0.3),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                // Кнопка подтверждения
                if (!withdrawal.confirmed) ...[
                  SizedBox(height: 12),
                  Divider(height: 1, color: Colors.white.withOpacity(0.1)),
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmWithdrawal(withdrawal),
                      icon: Icon(Icons.check_circle_outline, size: 18),
                      label: Text(
                        'Подтвердить выемку',
                        style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
                // Кнопка отмены (для активных выемок)
                if (withdrawal.isActive) ...[
                  SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: () => _cancelWithdrawal(withdrawal),
                      icon: Icon(Icons.cancel_outlined, size: 16),
                      label: Text(
                        'Отменить выемку',
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[300],
                        side: BorderSide(color: Colors.red[300]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                      ),
                    ),
                  ),
                ],
                // Показать статус отмены
                if (withdrawal.isCancelled) ...[
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.cancel, color: Colors.red[300], size: 18),
                            SizedBox(width: 8),
                            Text(
                              'ВЫЕМКА ОТМЕНЕНА',
                              style: TextStyle(
                                color: Colors.red[300],
                                fontWeight: FontWeight.bold,
                                fontSize: 12.sp,
                              ),
                            ),
                          ],
                        ),
                        if (withdrawal.cancelReason != null) ...[
                          SizedBox(height: 6),
                          Text(
                            'Причина: ${withdrawal.cancelReason}',
                            style: TextStyle(
                              color: Colors.red[200],
                              fontSize: 11.sp,
                            ),
                          ),
                        ],
                        if (withdrawal.cancelledBy != null) ...[
                          SizedBox(height: 4),
                          Text(
                            'Отменил: ${withdrawal.cancelledBy}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 10.sp,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        if (withdrawal.cancelledAt != null) ...[
                          SizedBox(height: 2),
                          Text(
                            'Дата отмены: ${_formatDate(withdrawal.cancelledAt!)}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 10.sp,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                SizedBox(height: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmWithdrawal(Withdrawal withdrawal) async {
    // Показать диалог подтверждения
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Подтверждение выемки'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Вы уверены, что хотите подтвердить эту выемку?'),
            SizedBox(height: 16),
            Text(
              'Магазин: ${withdrawal.shopAddress}',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey),
            ),
            Text(
              'Сумма: ${withdrawal.totalAmount.toStringAsFixed(0)} руб',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'После подтверждения выемка переместится в раздел "Подтвержденные".',
              style: TextStyle(fontSize: 11.sp, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Подтвердить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);

      try {
        final success = await WithdrawalService.confirmWithdrawal(withdrawal.id);

        if (success) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Выемка подтверждена'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadData();
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка подтверждения выемки'),
              backgroundColor: Colors.red,
            ),
          );
          if (!mounted) return;
          setState(() => _isLoading = false);
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _cancelWithdrawal(Withdrawal withdrawal) async {
    // Показать диалог с причиной отмены
    final TextEditingController reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Отмена выемки'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Вы уверены, что хотите отменить эту выемку?'),
            SizedBox(height: 16),
            Text(
              'Магазин: ${withdrawal.shopAddress}',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey),
            ),
            Text(
              'Сумма: ${withdrawal.totalAmount.toStringAsFixed(0)} руб',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey),
            ),
            SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Причина отмены',
                hintText: 'Укажите причину (необязательно)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 3,
            ),
            SizedBox(height: 8),
            Text(
              'После отмены выемка не будет учитываться в балансе.',
              style: TextStyle(fontSize: 11.sp, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Назад'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Отменить выемку', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);

      try {
        // Получить имя текущего пользователя
        final prefs = await SharedPreferences.getInstance();
        final currentUserName = prefs.getString('employeeName') ?? 'Администратор';

        final result = await WithdrawalService.cancelWithdrawal(
          id: withdrawal.id,
          cancelledBy: currentUserName,
          cancelReason: reasonController.text.isEmpty ? null : reasonController.text,
        );

        if (result != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Выемка отменена'),
              backgroundColor: Colors.orange,
            ),
          );
          await _loadData();
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка отмены выемки'),
              backgroundColor: Colors.red,
            ),
          );
          if (!mounted) return;
          setState(() => _isLoading = false);
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getExpenseEnding(int count) {
    if (count == 1) return '';
    if (count >= 2 && count <= 4) return 'а';
    return 'ов';
  }
}

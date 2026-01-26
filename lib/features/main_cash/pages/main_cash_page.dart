import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/logger.dart';
import '../models/shop_cash_balance_model.dart';
import '../models/withdrawal_model.dart';
import '../services/main_cash_service.dart';
import '../services/withdrawal_service.dart';
import 'shop_balance_details_page.dart';
import 'withdrawal_shop_selection_page.dart';

/// Главная страница отчета по кассе
class MainCashPage extends StatefulWidget {
  const MainCashPage({super.key});

  @override
  State<MainCashPage> createState() => _MainCashPageState();
}

class _MainCashPageState extends State<MainCashPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ShopCashBalance> _balances = [];
  List<Withdrawal> _withdrawals = [];
  bool _isLoading = true;
  String? _selectedShopFilter;
  int _withdrawalTabIndex = 0; // 0 = Все, 1 = Подтвержденные

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
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

      final withdrawals = await WithdrawalService.getWithdrawals();
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

  String _formatAmount(double amount) {
    String result;
    if (amount >= 1000000) {
      result = '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      final k = amount / 1000;
      result = '${k.toStringAsFixed(k % 1 == 0 ? 0 : 1)}k';
    } else {
      result = amount.toStringAsFixed(0);
    }
    Logger.debug('_formatAmount($amount) => "$result"');
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная Касса'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Обновить',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF004D40),
              indicatorWeight: 3,
              labelColor: const Color(0xFF004D40),
              unselectedLabelColor: Colors.grey[500],
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.account_balance_wallet, size: 20),
                      SizedBox(width: 8),
                      Text('Касса'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.upload, size: 20),
                      SizedBox(width: 8),
                      Text('Выемки'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCashTab(),
                _buildWithdrawalsTab(),
              ],
            ),
    );
  }

  Widget _buildCashTab() {
    if (_balances.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Нет данных о кассе',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Данные появятся после сдачи смен',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Заголовок таблицы
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: const Color(0xFF00796B),
          child: const Row(
            children: [
              Expanded(
                child: Text(
                  'Магазин',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  'ООО',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  'ИП',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  'Итого',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
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
        // Кнопка Выемка
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF00695C),
          child: ElevatedButton.icon(
            onPressed: _navigateToWithdrawal,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Сделать выемку', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        // Итого по всем магазинам
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF004D40),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'ИТОГО:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  _formatAmount(_balances.fold(0.0, (sum, b) => sum + b.oooBalance)),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  _formatAmount(_balances.fold(0.0, (sum, b) => sum + b.ipBalance)),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  _formatAmount(_balances.fold(0.0, (sum, b) => sum + b.totalBalance)),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 28), // для выравнивания со стрелкой
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpandableBalanceRow(ShopCashBalance balance) {
    return InkWell(
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Color(0xFF009688),
          border: Border(bottom: BorderSide(color: Color(0xFF00796B))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                balance.shopAddress,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: Colors.white),
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
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: balance.oooBalance < 0 ? Colors.red[200] : Colors.white,
                ),
              ),
            ),
            SizedBox(
              width: 60,
              child: Text(
                _formatAmount(balance.ipBalance),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: balance.ipBalance < 0 ? Colors.red[200] : Colors.white,
                ),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                _formatAmount(balance.totalBalance),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: balance.totalBalance < 0 ? Colors.red[200] : Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _buildWithdrawalsTab() {
    return Column(
      children: [
        // Подвкладки: Все / Подтвержденные
        Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
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
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _withdrawalTabIndex = 0),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _withdrawalTabIndex == 0 ? const Color(0xFF004D40) : Colors.transparent,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                      boxShadow: _withdrawalTabIndex == 0
                          ? [
                              BoxShadow(
                                color: const Color(0xFF004D40).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.list_alt,
                          size: 18,
                          color: _withdrawalTabIndex == 0 ? Colors.white : Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Все',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: _withdrawalTabIndex == 0 ? FontWeight.bold : FontWeight.w500,
                            color: _withdrawalTabIndex == 0 ? Colors.white : Colors.grey[600],
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _withdrawalTabIndex = 1),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _withdrawalTabIndex == 1 ? const Color(0xFF004D40) : Colors.transparent,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      boxShadow: _withdrawalTabIndex == 1
                          ? [
                              BoxShadow(
                                color: const Color(0xFF004D40).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 18,
                          color: _withdrawalTabIndex == 1 ? Colors.white : Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Подтверждённые',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: _withdrawalTabIndex == 1 ? FontWeight.bold : FontWeight.w500,
                            color: _withdrawalTabIndex == 1 ? Colors.white : Colors.grey[600],
                            letterSpacing: 0.2,
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
        // Фильтр по магазину + кнопка обновления
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: DropdownButtonFormField<String>(
                    value: _selectedShopFilter,
                    decoration: InputDecoration(
                      labelText: 'Фильтр по магазину',
                      labelStyle: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.store,
                        color: const Color(0xFF004D40),
                        size: 20,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                    dropdownColor: Colors.white,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.select_all,
                              size: 18,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            const Text('Все магазины'),
                          ],
                        ),
                      ),
                      ..._shopAddresses.map((address) => DropdownMenuItem(
                            value: address,
                            child: Text(
                              address,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedShopFilter = value);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF004D40)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF004D40).withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _isLoading ? null : _loadData,
                  icon: _isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: const Color(0xFF004D40),
                          ),
                        )
                      : const Icon(
                          Icons.refresh,
                          color: Color(0xFF004D40),
                        ),
                  tooltip: 'Обновить',
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(),
                ),
              ),
            ],
          ),
        ),
        // Список выемок
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredWithdrawals.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.upload, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'Выемок пока нет',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Всего загружено: ${_withdrawals.length}',
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _loadData,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Обновить'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
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
    final borderColor = isCancelled ? Colors.red[200]! : Colors.grey[200]!;
    final cardColor = isCancelled ? Colors.red[50] : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: isCancelled ? 2 : 1),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              // Левая часть: иконка типа (или иконка отмены)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isCancelled
                      ? Colors.red.withOpacity(0.1)
                      : (withdrawal.type == 'ooo'
                          ? Colors.blue.withOpacity(0.1)
                          : Colors.orange.withOpacity(0.1)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isCancelled
                      ? Icons.cancel
                      : (withdrawal.type == 'ooo' ? Icons.business : Icons.store),
                  size: 20,
                  color: isCancelled
                      ? Colors.red[700]
                      : (withdrawal.type == 'ooo' ? Colors.blue : Colors.orange),
                ),
              ),
              const SizedBox(width: 12),
              // Средняя часть: информация
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isCancelled) ...[
                          Text(
                            'ОТМЕНЕНО',
                            style: TextStyle(
                              color: Colors.red[700],
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          withdrawal.typeDisplayName,
                          style: TextStyle(
                            color: isCancelled
                                ? Colors.grey
                                : (withdrawal.type == 'ooo' ? Colors.blue : Colors.orange),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            decoration: isCancelled ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          withdrawal.formattedDateTime,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 10,
                          ),
                        ),
                        if (withdrawal.confirmed && !isCancelled) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: Colors.green[600],
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      withdrawal.shopAddress,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${withdrawal.employeeName} • ${withdrawal.expenses.length} расход${_getExpenseEnding(withdrawal.expenses.length)}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
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
                    '${withdrawal.totalAmount.toStringAsFixed(0)} ₽',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF004D40),
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
                const Divider(height: 1),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Детализация расходов:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...withdrawal.expenses.asMap().entries.map((entry) {
                  final index = entry.key;
                  final expense = entry.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      children: [
                        // Номер
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xFF004D40).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: Color(0xFF004D40),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Информация
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                expense.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              if (expense.comment.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  expense.comment,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 10,
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
                          '${expense.amount.toStringAsFixed(0)} ₽',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF004D40),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                if (withdrawal.adminName != null && withdrawal.adminName!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Создал: ${withdrawal.adminName}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                // Кнопка подтверждения
                if (!withdrawal.confirmed) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmWithdrawal(withdrawal),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text(
                        'Подтвердить выемку',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
                // Кнопка отмены (для активных выемок)
                if (withdrawal.isActive) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: () => _cancelWithdrawal(withdrawal),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text(
                        'Отменить выемку',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[700],
                        side: BorderSide(color: Colors.red[300]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
                // Показать статус отмены
                if (withdrawal.isCancelled) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.cancel, color: Colors.red[700], size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'ВЫЕМКА ОТМЕНЕНА',
                              style: TextStyle(
                                color: Colors.red[700],
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        if (withdrawal.cancelReason != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Причина: ${withdrawal.cancelReason}',
                            style: TextStyle(
                              color: Colors.red[600],
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (withdrawal.cancelledBy != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Отменил: ${withdrawal.cancelledBy}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        if (withdrawal.cancelledAt != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Дата отмены: ${_formatDate(withdrawal.cancelledAt!)}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 4),
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
        title: const Text('Подтверждение выемки'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Вы уверены, что хотите подтвердить эту выемку?'),
            const SizedBox(height: 16),
            Text(
              'Магазин: ${withdrawal.shopAddress}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              'Сумма: ${withdrawal.totalAmount.toStringAsFixed(0)} ₽',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'После подтверждения выемка переместится в раздел "Подтвержденные".',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Подтвердить', style: TextStyle(color: Colors.white)),
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
            const SnackBar(
              content: Text('Выемка подтверждена'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadData();
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
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
        title: const Text('Отмена выемки'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Вы уверены, что хотите отменить эту выемку?'),
            const SizedBox(height: 16),
            Text(
              'Магазин: ${withdrawal.shopAddress}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              'Сумма: ${withdrawal.totalAmount.toStringAsFixed(0)} ₽',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Причина отмены',
                hintText: 'Укажите причину (необязательно)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            const Text(
              'После отмены выемка не будет учитываться в балансе.',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Назад'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Отменить выемку', style: TextStyle(color: Colors.white)),
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
            const SnackBar(
              content: Text('Выемка отменена'),
              backgroundColor: Colors.orange,
            ),
          );
          await _loadData();
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
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

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

      setState(() {
        _balances = balances;
        _withdrawals = withdrawals;
        _isLoading = false;
      });

      Logger.debug('✅ Состояние обновлено: балансов=${_balances.length}, выемок=${_withdrawals.length}');
    } catch (e, stackTrace) {
      Logger.error('❌ Ошибка загрузки данных', e);
      Logger.debug('Stack trace: $stackTrace');
      setState(() => _isLoading = false);
    }
  }

  List<Withdrawal> get _filteredWithdrawals {
    var filtered = _withdrawals;

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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF004D40),
          labelColor: const Color(0xFF004D40),
          unselectedLabelColor: Colors.grey,
          indicator: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(
                color: Color(0xFF004D40),
                width: 3,
              ),
            ),
          ),
          tabs: const [
            Tab(text: 'Касса', icon: Icon(Icons.account_balance_wallet)),
            Tab(text: 'Выемки', icon: Icon(Icons.upload)),
          ],
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
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        backgroundColor: const Color(0xFF009688),
        collapsedBackgroundColor: const Color(0xFF009688),
        iconColor: Colors.white,
        collapsedIconColor: Colors.white70,
        title: Row(
          children: [
            Expanded(
              child: Text(
                balance.shopAddress,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatAmount(balance.totalBalance),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: balance.totalBalance < 0 ? Colors.red[200] : Colors.white,
              ),
            ),
          ],
        ),
        children: [
          Container(
            color: const Color(0xFF00796B),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            child: Column(
              children: [
                // ООО строка
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ООО',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _formatAmount(balance.oooBalance),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: balance.oooBalance < 0 ? Colors.red[200] : Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // ИП строка
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ИП',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _formatAmount(balance.ipBalance),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: balance.ipBalance < 0 ? Colors.red[200] : Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 8),
                // Кнопка перехода к деталям
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ShopBalanceDetailsPage(
                            shopAddress: balance.shopAddress,
                          ),
                        ),
                      ).then((_) => _loadData());
                    },
                    icon: const Icon(Icons.info_outline, size: 16, color: Colors.white),
                    label: const Text(
                      'Детали',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWithdrawalsTab() {
    return Column(
      children: [
        // Подвкладки: Все / Подтвержденные
        Container(
          color: Colors.grey[100],
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _withdrawalTabIndex = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _withdrawalTabIndex == 0 ? Colors.white : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: _withdrawalTabIndex == 0 ? const Color(0xFF004D40) : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Text(
                      'Все',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: _withdrawalTabIndex == 0 ? FontWeight.bold : FontWeight.normal,
                        color: _withdrawalTabIndex == 0 ? const Color(0xFF004D40) : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _withdrawalTabIndex = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _withdrawalTabIndex == 1 ? Colors.white : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: _withdrawalTabIndex == 1 ? const Color(0xFF004D40) : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Text(
                      'Подтвержденные',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: _withdrawalTabIndex == 1 ? FontWeight.bold : FontWeight.normal,
                        color: _withdrawalTabIndex == 1 ? const Color(0xFF004D40) : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Фильтр по магазину + кнопка обновления
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedShopFilter,
                  decoration: const InputDecoration(
                    labelText: 'Фильтр по магазину',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Все магазины'),
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
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isLoading ? null : _loadData,
                icon: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: 'Обновить',
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    withdrawal.formattedDateTime,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: withdrawal.type == 'ooo'
                              ? Colors.blue.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          withdrawal.typeDisplayName,
                          style: TextStyle(
                            color: withdrawal.type == 'ooo' ? Colors.blue : Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (withdrawal.confirmed) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '✓',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                withdrawal.shopAddress,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                withdrawal.employeeName,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${withdrawal.expenses.length} расход${_getExpenseEnding(withdrawal.expenses.length)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    '${withdrawal.totalAmount.toStringAsFixed(0)} ₽',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF004D40),
                    ),
                  ),
                ],
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Детализация расходов:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  ...withdrawal.expenses.asMap().entries.map((entry) {
                    final index = entry.key;
                    final expense = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${index + 1}. ${expense.displayName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Сумма:',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                              Text(
                                '${expense.amount.toStringAsFixed(0)} ₽',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          if (expense.comment.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Комментарий: ${expense.comment}',
                              style: TextStyle(color: Colors.grey[700], fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  if (withdrawal.adminName != null && withdrawal.adminName!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Создал: ${withdrawal.adminName}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  // Кнопка подтверждения
                  if (!withdrawal.confirmed) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _confirmWithdrawal(withdrawal),
                        icon: const Icon(Icons.check_circle, color: Colors.white),
                        label: const Text(
                          'Подтвердить выемку',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
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
        setState(() => _isLoading = false);
      }
    }
  }

  String _getExpenseEnding(int count) {
    if (count == 1) return '';
    if (count >= 2 && count <= 4) return 'а';
    return 'ов';
  }
}

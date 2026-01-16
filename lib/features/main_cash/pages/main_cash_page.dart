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
      final balances = await MainCashService.getShopBalances();
      final withdrawals = await WithdrawalService.getWithdrawals();

      // Логирование для отладки
      for (final b in balances) {
        Logger.debug('=== Баланс магазина: ${b.shopAddress}');
        Logger.debug('    ООО: ${b.oooBalance}');
        Logger.debug('    ИП: ${b.ipBalance}');
        Logger.debug('    Итого: ${b.totalBalance}');
      }

      setState(() {
        _balances = balances;
        _withdrawals = withdrawals;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки данных', e);
      setState(() => _isLoading = false);
    }
  }

  List<Withdrawal> get _filteredWithdrawals {
    if (_selectedShopFilter == null) return _withdrawals;
    return _withdrawals.where((w) => w.shopAddress == _selectedShopFilter).toList();
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
          indicatorColor: Colors.white,
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
        // Список магазинов
        Expanded(
          child: ListView.builder(
            itemCount: _balances.length,
            itemBuilder: (context, index) {
              final balance = _balances[index];
              return _buildBalanceRow(balance);
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

  Widget _buildBalanceRow(ShopCashBalance balance) {
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
        // Фильтр по магазину
        Padding(
          padding: const EdgeInsets.all(16),
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
        // Список выемок
        Expanded(
          child: _filteredWithdrawals.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.upload, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Выемок пока нет',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getExpenseEnding(int count) {
    if (count == 1) return '';
    if (count >= 2 && count <= 4) return 'а';
    return 'ов';
  }
}

import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../models/shop_cash_balance_model.dart';
import '../services/main_cash_service.dart';
import '../widgets/turnover_calendar.dart';

/// Страница деталей магазина (баланс и оборот)
class ShopBalanceDetailsPage extends StatefulWidget {
  final String shopAddress;

  const ShopBalanceDetailsPage({
    super.key,
    required this.shopAddress,
  });

  @override
  State<ShopBalanceDetailsPage> createState() => _ShopBalanceDetailsPageState();
}

class _ShopBalanceDetailsPageState extends State<ShopBalanceDetailsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  ShopCashBalance? _balance;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBalance();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    setState(() => _isLoading = true);

    try {
      final balance = await MainCashService.getShopBalance(widget.shopAddress);
      setState(() {
        _balance = balance;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки баланса', e);
      setState(() => _isLoading = false);
    }
  }

  String _formatFullAmount(double amount) {
    final formatter = amount.toStringAsFixed(0);
    // Добавляем разделители тысяч
    final chars = formatter.split('');
    final result = <String>[];
    for (int i = 0; i < chars.length; i++) {
      if (i > 0 && (chars.length - i) % 3 == 0 && chars[i] != '-') {
        result.add(' ');
      }
      result.add(chars[i]);
    }
    return result.join('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.shopAddress,
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBalance,
            tooltip: 'Обновить',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Баланс', icon: Icon(Icons.account_balance_wallet)),
            Tab(text: 'Оборот', icon: Icon(Icons.calendar_today)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildBalanceTab(),
                TurnoverCalendarWidget(shopAddress: widget.shopAddress),
              ],
            ),
    );
  }

  Widget _buildBalanceTab() {
    if (_balance == null) {
      return const Center(
        child: Text(
          'Нет данных о балансе',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Text(
            'Текущий баланс кассы',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF004D40),
            ),
          ),
          const SizedBox(height: 40),

          // ООО
          _buildBalanceRow(
            'ООО',
            _balance!.oooBalance,
            Colors.blue,
          ),
          const SizedBox(height: 24),

          // ИП
          _buildBalanceRow(
            'ИП',
            _balance!.ipBalance,
            Colors.orange,
          ),

          const SizedBox(height: 16),
          const Divider(thickness: 2),
          const SizedBox(height: 16),

          // Итого
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Итого:',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_formatFullAmount(_balance!.totalBalance)} руб',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _balance!.totalBalance < 0
                      ? Colors.red
                      : const Color(0xFF004D40),
                ),
              ),
            ],
          ),

          const SizedBox(height: 60),

          // Детальная информация
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Детали',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                _buildDetailRow('Поступления ООО:', _balance!.oooTotalIncome),
                _buildDetailRow('Выемки ООО:', -_balance!.oooTotalWithdrawals),
                const Divider(),
                _buildDetailRow('Поступления ИП:', _balance!.ipTotalIncome),
                _buildDetailRow('Выемки ИП:', -_balance!.ipTotalWithdrawals),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceRow(String label, double amount, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$label:',
              style: const TextStyle(
                fontSize: 20,
              ),
            ),
          ],
        ),
        Text(
          '${_formatFullAmount(amount)} руб',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: amount < 0 ? Colors.red : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
          Text(
            '${_formatFullAmount(amount)} руб',
            style: TextStyle(
              color: amount < 0 ? Colors.red : Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}

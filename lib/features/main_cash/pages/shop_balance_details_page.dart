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

  // Dark Emerald palette
  static const _emerald = Color(0xFF1A4D4D);
  static const _emeraldDark = Color(0xFF0D2E2E);
  static const _night = Color(0xFF051515);
  static const _gold = Color(0xFFD4AF37);

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
              // Custom header row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: Colors.white.withOpacity(0.9),
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.shopAddress,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _loadBalance,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.refresh,
                          color: Colors.white.withOpacity(0.9),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // TabBar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: _gold,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withOpacity(0.5),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Баланс', icon: Icon(Icons.account_balance_wallet)),
                    Tab(text: 'Оборот', icon: Icon(Icons.calendar_today)),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Body
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: _gold),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildBalanceTab(),
                          TurnoverCalendarWidget(shopAddress: widget.shopAddress),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceTab() {
    if (_balance == null) {
      return Center(
        child: Text(
          'Нет данных о балансе',
          style: TextStyle(
            fontSize: 18,
            color: Colors.white.withOpacity(0.5),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Text(
            'Текущий баланс кассы',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _gold,
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
          Divider(thickness: 2, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),

          // Итого
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Итого:',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              Text(
                '${_formatFullAmount(_balance!.totalBalance)} руб',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _balance!.totalBalance < 0
                      ? Colors.red
                      : _gold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 60),

          // Детальная информация
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Детали',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 12),
                _buildDetailRow('Поступления ООО:', _balance!.oooTotalIncome),
                _buildDetailRow('Выемки ООО:', -_balance!.oooTotalWithdrawals),
                Divider(color: Colors.white.withOpacity(0.1)),
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
              style: TextStyle(
                fontSize: 20,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
        Text(
          '${_formatFullAmount(amount)} руб',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: amount < 0 ? Colors.red : Colors.white.withOpacity(0.9),
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
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
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

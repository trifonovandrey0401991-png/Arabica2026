import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/logger.dart';
import '../models/shop_cash_balance_model.dart';
import '../services/main_cash_service.dart';
import '../widgets/turnover_calendar.dart';
import '../../../core/utils/cache_manager.dart';
import '../../employees/services/user_role_service.dart';
import '../../employees/models/user_role_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  bool _isDeveloper = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBalance();
    _checkRole();
  }

  Future<void> _checkRole() async {
    final role = await UserRoleService.loadUserRole();
    if (mounted && role != null) {
      setState(() => _isDeveloper = role.isDeveloper);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _cacheKey => 'shop_balance_${widget.shopAddress.hashCode}';

  Future<void> _loadBalance() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<ShopCashBalance>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _balance = cached;
        _isLoading = false;
      });
    }

    if (_balance == null && mounted) setState(() => _isLoading = true);

    try {
      final balance = await MainCashService.getShopBalance(widget.shopAddress);
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _isLoading = false;
      });
      // Step 3: Save to cache
      CacheManager.set(_cacheKey, balance);
    } catch (e) {
      Logger.error('Ошибка загрузки баланса', e);
      if (!mounted) return;
      if (_balance == null) setState(() => _isLoading = false);
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
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom header row
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: Colors.white.withOpacity(0.9),
                          size: 20,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.shopAddress,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 8),
                    if (_isDeveloper)
                      GestureDetector(
                        onTap: _showCorrectionDialog,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Icon(
                            Icons.edit,
                            color: AppColors.gold.withOpacity(0.9),
                            size: 20,
                          ),
                        ),
                      ),
                    SizedBox(width: 8),
                    GestureDetector(
                      onTap: _loadBalance,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
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
                margin: EdgeInsets.symmetric(horizontal: 16.w),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppColors.gold,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withOpacity(0.5),
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(text: 'Баланс', icon: Icon(Icons.account_balance_wallet)),
                    Tab(text: 'Оборот', icon: Icon(Icons.calendar_today)),
                  ],
                ),
              ),

              SizedBox(height: 8),

              // Body
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: AppColors.gold),
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

  Future<void> _showCorrectionDialog() async {
    if (_balance == null) return;

    final oooIncomeCtrl = TextEditingController(text: _balance!.oooTotalIncome.toStringAsFixed(0));
    final ipIncomeCtrl = TextEditingController(text: _balance!.ipTotalIncome.toStringAsFixed(0));
    final oooWithdrawalsCtrl = TextEditingController(text: _balance!.oooTotalWithdrawals.toStringAsFixed(0));
    final ipWithdrawalsCtrl = TextEditingController(text: _balance!.ipTotalWithdrawals.toStringAsFixed(0));

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        title: Text(
          'Корректировка баланса',
          style: TextStyle(color: Colors.white, fontSize: 18.sp),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.shopAddress,
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13.sp),
              ),
              SizedBox(height: 16.h),
              _buildCorrectionField(oooIncomeCtrl, 'Поступления ООО'),
              SizedBox(height: 12.h),
              _buildCorrectionField(oooWithdrawalsCtrl, 'Выемки ООО'),
              SizedBox(height: 12.h),
              _buildCorrectionField(ipIncomeCtrl, 'Поступления ИП'),
              SizedBox(height: 12.h),
              _buildCorrectionField(ipWithdrawalsCtrl, 'Выемки ИП'),
              SizedBox(height: 16.h),
              Text(
                'Введите желаемые итоговые суммы.\nСистема рассчитает корректировку автоматически.',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.sp),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Сохранить', style: TextStyle(color: AppColors.gold)),
          ),
        ],
      ),
    );

    if (result != true) {
      oooIncomeCtrl.dispose();
      ipIncomeCtrl.dispose();
      oooWithdrawalsCtrl.dispose();
      ipWithdrawalsCtrl.dispose();
      return;
    }

    // Calculate deltas
    final newOooIncome = double.tryParse(oooIncomeCtrl.text) ?? _balance!.oooTotalIncome;
    final newIpIncome = double.tryParse(ipIncomeCtrl.text) ?? _balance!.ipTotalIncome;
    final newOooWithdrawals = double.tryParse(oooWithdrawalsCtrl.text) ?? _balance!.oooTotalWithdrawals;
    final newIpWithdrawals = double.tryParse(ipWithdrawalsCtrl.text) ?? _balance!.ipTotalWithdrawals;

    oooIncomeCtrl.dispose();
    ipIncomeCtrl.dispose();
    oooWithdrawalsCtrl.dispose();
    ipWithdrawalsCtrl.dispose();

    // Load existing correction to compute the raw (uncorrected) values
    final existingCorrection = await MainCashService.getCashCorrection(widget.shopAddress);
    final rawOooIncome = _balance!.oooTotalIncome - (existingCorrection['oooIncomeDelta'] ?? 0);
    final rawIpIncome = _balance!.ipTotalIncome - (existingCorrection['ipIncomeDelta'] ?? 0);
    final rawOooWithdrawals = _balance!.oooTotalWithdrawals - (existingCorrection['oooWithdrawalsDelta'] ?? 0);
    final rawIpWithdrawals = _balance!.ipTotalWithdrawals - (existingCorrection['ipWithdrawalsDelta'] ?? 0);

    final deltas = {
      'oooIncomeDelta': newOooIncome - rawOooIncome,
      'ipIncomeDelta': newIpIncome - rawIpIncome,
      'oooWithdrawalsDelta': newOooWithdrawals - rawOooWithdrawals,
      'ipWithdrawalsDelta': newIpWithdrawals - rawIpWithdrawals,
    };

    final success = await MainCashService.saveCashCorrection(widget.shopAddress, deltas);
    if (success) {
      // Invalidate cache and reload
      CacheManager.remove(_cacheKey);
      await _loadBalance();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Корректировка сохранена'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка сохранения корректировки'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Widget _buildCorrectionField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: TextStyle(color: Colors.white, fontSize: 16.sp),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(8.r),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.gold),
          borderRadius: BorderRadius.circular(8.r),
        ),
        suffixText: 'руб',
        suffixStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
      ),
    );
  }

  Widget _buildBalanceTab() {
    if (_balance == null) {
      return Center(
        child: Text(
          'Нет данных о балансе',
          style: TextStyle(
            fontSize: 18.sp,
            color: Colors.white.withOpacity(0.5),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(24.w),
      child: Column(
        children: [
          SizedBox(height: 40),
          Text(
            'Текущий баланс кассы',
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          SizedBox(height: 40),

          // ООО
          _buildBalanceRow(
            'ООО',
            _balance!.oooBalance,
            Colors.blue,
          ),
          SizedBox(height: 24),

          // ИП
          _buildBalanceRow(
            'ИП',
            _balance!.ipBalance,
            Colors.orange,
          ),

          SizedBox(height: 16),
          Divider(thickness: 2, color: Colors.white.withOpacity(0.1)),
          SizedBox(height: 16),

          // Итого
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Итого:',
                style: TextStyle(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              Text(
                '${_formatFullAmount(_balance!.totalBalance)} руб',
                style: TextStyle(
                  fontSize: 28.sp,
                  fontWeight: FontWeight.bold,
                  color: _balance!.totalBalance < 0
                      ? Colors.red
                      : AppColors.gold,
                ),
              ),
            ],
          ),

          SizedBox(height: 60),

          // Детальная информация
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Детали',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16.sp,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                SizedBox(height: 12),
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
                borderRadius: BorderRadius.circular(3.r),
              ),
            ),
            SizedBox(width: 12),
            Text(
              '$label:',
              style: TextStyle(
                fontSize: 20.sp,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
        Text(
          '${_formatFullAmount(amount)} руб',
          style: TextStyle(
            fontSize: 22.sp,
            fontWeight: FontWeight.bold,
            color: amount < 0 ? Colors.red : Colors.white.withOpacity(0.9),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, double amount) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
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

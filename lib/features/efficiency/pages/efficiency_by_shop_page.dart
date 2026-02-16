import 'package:flutter/material.dart';
import '../models/efficiency_data_model.dart';
import '../services/efficiency_data_service.dart';
import '../widgets/efficiency_common_widgets.dart';
import '../utils/efficiency_utils.dart';
import 'shop_efficiency_detail_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница списка эффективности по магазинам
class EfficiencyByShopPage extends StatefulWidget {
  const EfficiencyByShopPage({super.key});

  @override
  State<EfficiencyByShopPage> createState() => _EfficiencyByShopPageState();
}

class _EfficiencyByShopPageState extends State<EfficiencyByShopPage> {
  // --- palette ---
  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);
  static final Color _gold = Color(0xFFD4AF37);

  bool _isLoading = true;
  EfficiencyData? _data;
  String? _error;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

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
      final data = await EfficiencyDataService.loadMonthData(
        _selectedYear,
        _selectedMonth,
        forceRefresh: forceRefresh,
      );
      setState(() {
        _data = data;
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
      backgroundColor: _night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emeraldDark, _night],
            stops: [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // --- custom app bar ---
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        'По магазинам',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
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
              // --- body ---
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return EfficiencyLoadingState();
    }

    if (_error != null) {
      return EfficiencyErrorState(
        error: _error!,
        onRetry: _loadData,
      );
    }

    if (_data == null || _data!.byShop.isEmpty) {
      return EfficiencyEmptyState(
        monthName: EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear),
        icon: Icons.store_outlined,
      );
    }

    return RefreshIndicator(
      color: _gold,
      backgroundColor: _emerald,
      onRefresh: () => _loadData(forceRefresh: true),
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: _data!.byShop.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildSummaryCard();
          }
          return _buildShopCard(_data!.byShop[index - 1]);
        },
      ),
    );
  }

  Widget _buildSummaryCard() {
    return EfficiencySummaryCard(summaries: _data!.byShop);
  }

  Widget _buildShopCard(EfficiencySummary summary) {
    final isPositive = summary.totalPoints >= 0;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: _emeraldDark,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: _emerald.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ShopEfficiencyDetailPage(
                  summary: summary,
                  monthName: EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear),
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary.entityName,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: isPositive
                            ? Colors.green.withOpacity(0.15)
                            : Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                      child: Text(
                        summary.formattedTotal,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: isPositive
                              ? Color(0xFF4CAF50)
                              : Color(0xFFEF5350),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '+${summary.earnedPoints.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Color(0xFF4CAF50),
                      ),
                    ),
                    Text(' / ', style: TextStyle(color: Colors.white.withOpacity(0.3))),
                    Text(
                      '-${summary.lostPoints.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Color(0xFFEF5350),
                      ),
                    ),
                    Spacer(),
                    Text(
                      '${summary.recordsCount} записей',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.white.withOpacity(0.3),
                      size: 20,
                    ),
                  ],
                ),
                SizedBox(height: 8),
                EfficiencyProgressBar(summary: summary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

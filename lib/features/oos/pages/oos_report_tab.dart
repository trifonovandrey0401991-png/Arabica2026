import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../models/oos_report_model.dart';
import '../services/oos_service.dart';
import 'oos_report_detail_page.dart';

/// Report tab: list of shops with monthly OOS incident counts
class OosReportTab extends StatefulWidget {
  const OosReportTab({super.key});

  @override
  State<OosReportTab> createState() => _OosReportTabState();
}

class _OosReportTabState extends State<OosReportTab>
    with AutomaticKeepAliveClientMixin {
  List<OosShopSummary> _shops = [];
  List<String> _availableMonths = [];
  String? _selectedMonth;
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({String? month}) async {
    setState(() => _isLoading = true);

    final result = await OosService.getReport(month: month);

    if (!mounted) return;
    setState(() {
      _shops = result.shops;
      _availableMonths = result.availableMonths;
      if (_selectedMonth == null && _availableMonths.isNotEmpty) {
        _selectedMonth = _availableMonths.first;
      }
      _isLoading = false;
    });
  }

  String _formatMonth(String month) {
    final parts = month.split('-');
    if (parts.length != 2) return month;
    const months = [
      '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
    ];
    final monthNum = int.tryParse(parts[1]) ?? 0;
    if (monthNum < 1 || monthNum > 12) return month;
    return '${months[monthNum]} ${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    return Column(
      children: [
        if (_availableMonths.length > 1) _buildMonthSelector(),
        Expanded(child: _buildShopList()),
      ],
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      height: 44.h,
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      color: AppColors.emeraldDark.withOpacity(0.3),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _availableMonths.length,
        separatorBuilder: (_, __) => SizedBox(width: 8.w),
        itemBuilder: (context, index) {
          final month = _availableMonths[index];
          final isSelected = month == _selectedMonth;
          return Center(
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedMonth = month);
                _loadData(month: month);
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.emerald : Colors.transparent,
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(
                    color: isSelected ? AppColors.emerald : Colors.white30,
                  ),
                ),
                child: Text(
                  _formatMonth(month),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 13.sp,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShopList() {
    if (_shops.isEmpty) {
      return Center(
        child: Text(
          'Нет данных за выбранный период',
          style: TextStyle(color: Colors.white38, fontSize: 15.sp),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(month: _selectedMonth),
      color: AppColors.gold,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(vertical: 8.h),
        itemCount: _shops.length,
        itemBuilder: (context, index) {
          final shop = _shops[index];
          return _buildShopTile(shop);
        },
      ),
    );
  }

  Widget _buildShopTile(OosShopSummary shop) {
    final bool noData = !shop.hasDbf;
    final bool hasOos = shop.hasDbf && shop.oosCount > 0;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: AppColors.emeraldDark.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: noData
              ? Colors.orange.withOpacity(0.3)
              : hasOos
                  ? Colors.red.withOpacity(0.3)
                  : AppColors.emerald.withOpacity(0.2),
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
        leading: Container(
          width: 40.w,
          height: 40.w,
          decoration: BoxDecoration(
            color: noData
                ? Colors.orange.withOpacity(0.2)
                : hasOos
                    ? Colors.red.withOpacity(0.2)
                    : AppColors.emerald.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Center(
            child: Icon(
              noData
                  ? Icons.link_off
                  : hasOos
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
              color: noData
                  ? Colors.orange
                  : hasOos
                      ? Colors.red.shade300
                      : AppColors.emeraldGreen,
              size: 22.sp,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                shop.shopName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (noData)
              Container(
                margin: EdgeInsets.only(left: 6.w),
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4.r),
                ),
                child: Text(
                  'DBF',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (noData)
              Text(
                'Нет данных',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12.sp,
                ),
              )
            else if (hasOos)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  '${shop.oosCount}',
                  style: TextStyle(
                    color: Colors.red.shade300,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            SizedBox(width: 8.w),
            Icon(Icons.chevron_right, color: Colors.white30, size: 20.sp),
          ],
        ),
        onTap: noData ? null : () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OosReportDetailPage(
                shopId: shop.shopId,
                shopName: shop.shopName,
                availableMonths: _availableMonths,
              ),
            ),
          );
        },
      ),
    );
  }
}

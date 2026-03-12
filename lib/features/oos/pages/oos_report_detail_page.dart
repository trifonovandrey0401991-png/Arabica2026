import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../models/oos_report_model.dart';
import '../services/oos_service.dart';

/// Detail page: shop → month → products x days grid
class OosReportDetailPage extends StatefulWidget {
  final String shopId;
  final String shopName;
  final List<String> availableMonths;

  const OosReportDetailPage({
    super.key,
    required this.shopId,
    required this.shopName,
    required this.availableMonths,
  });

  @override
  State<OosReportDetailPage> createState() => _OosReportDetailPageState();
}

class _OosReportDetailPageState extends State<OosReportDetailPage> {
  String? _selectedMonth;
  OosReportDetail? _detail;
  bool _isLoading = false;

  final ScrollController _fixedScrollController = ScrollController();
  final ScrollController _dataScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fixedScrollController.addListener(() {
      if (_dataScrollController.hasClients &&
          _dataScrollController.offset != _fixedScrollController.offset) {
        _dataScrollController.jumpTo(_fixedScrollController.offset);
      }
    });
    _dataScrollController.addListener(() {
      if (_fixedScrollController.hasClients &&
          _fixedScrollController.offset != _dataScrollController.offset) {
        _fixedScrollController.jumpTo(_dataScrollController.offset);
      }
    });
  }

  @override
  void dispose() {
    _fixedScrollController.dispose();
    _dataScrollController.dispose();
    super.dispose();
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

  Future<void> _loadDetail(String month) async {
    setState(() {
      _selectedMonth = month;
      _isLoading = true;
    });

    final detail = await OosService.getReportDetail(widget.shopId, month);

    if (!mounted) return;
    setState(() {
      _detail = detail;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8.h,
        left: 16.w,
        right: 16.w,
        bottom: 12.h,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.emeraldDark, AppColors.emerald],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              widget.shopName,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_selectedMonth == null) {
      // Show month list
      return _buildMonthList();
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    if (_detail == null || _detail!.products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Нет данных за ${_formatMonth(_selectedMonth!)}',
              style: TextStyle(color: Colors.white38, fontSize: 15.sp),
            ),
            SizedBox(height: 16.h),
            TextButton(
              onPressed: () => setState(() => _selectedMonth = null),
              child: const Text('Назад к месяцам',
                  style: TextStyle(color: AppColors.gold)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Back to months + title
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          color: AppColors.emeraldDark.withOpacity(0.3),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _selectedMonth = null),
                child: Row(
                  children: [
                    Icon(Icons.arrow_back, color: AppColors.gold, size: 18.sp),
                    SizedBox(width: 4.w),
                    Text(
                      'Месяцы',
                      style: TextStyle(color: AppColors.gold, fontSize: 14.sp),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 16.w),
              Text(
                _formatMonth(_selectedMonth!),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildDaysGrid()),
      ],
    );
  }

  Widget _buildMonthList() {
    if (widget.availableMonths.isEmpty) {
      return Center(
        child: Text(
          'Нет данных',
          style: TextStyle(color: Colors.white38, fontSize: 15.sp),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      itemCount: widget.availableMonths.length,
      itemBuilder: (context, index) {
        final month = widget.availableMonths[index];
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: AppColors.emeraldDark.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: AppColors.emerald.withOpacity(0.2)),
          ),
          child: ListTile(
            leading: Icon(Icons.calendar_month, color: AppColors.emeraldLight, size: 22.sp),
            title: Text(
              _formatMonth(month),
              style: TextStyle(color: Colors.white, fontSize: 15.sp),
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.white30, size: 20.sp),
            onTap: () => _loadDetail(month),
          ),
        );
      },
    );
  }

  Widget _buildDaysGrid() {
    final detail = _detail!;
    final borderColor = AppColors.emerald.withOpacity(0.2);
    final cellHeight = 40.h;
    final headerHeight = 40.h;
    final dayWidth = 32.w;

    return Row(
      children: [
        // Fixed left column: product names
        SizedBox(
          width: 140.w,
          child: Column(
            children: [
              Container(
                height: headerHeight,
                decoration: BoxDecoration(
                  color: AppColors.emeraldDark,
                  border: Border.all(color: borderColor, width: 0.5),
                ),
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                child: Text(
                  'Товар',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.sp,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _fixedScrollController,
                  itemCount: detail.products.length,
                  itemExtent: cellHeight,
                  itemBuilder: (context, index) {
                    return Container(
                      height: cellHeight,
                      decoration: BoxDecoration(
                        color: AppColors.night,
                        border: Border(
                          bottom: BorderSide(color: borderColor, width: 0.5),
                          left: BorderSide(color: borderColor, width: 0.5),
                          right: BorderSide(color: borderColor, width: 0.5),
                        ),
                      ),
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.symmetric(horizontal: 8.w),
                      child: Text(
                        detail.products[index].productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 11.sp),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // Scrollable right part: day columns
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: detail.daysInMonth * dayWidth,
              child: Column(
                children: [
                  // Header: day numbers
                  SizedBox(
                    height: headerHeight,
                    child: Row(
                      children: List.generate(detail.daysInMonth, (i) {
                        return Container(
                          width: dayWidth,
                          height: headerHeight,
                          decoration: BoxDecoration(
                            color: AppColors.emeraldDark,
                            border: Border.all(color: borderColor, width: 0.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.sp,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  // Data rows
                  Expanded(
                    child: ListView.builder(
                      controller: _dataScrollController,
                      itemCount: detail.products.length,
                      itemExtent: cellHeight,
                      itemBuilder: (context, index) {
                        final product = detail.products[index];
                        return SizedBox(
                          height: cellHeight,
                          child: Row(
                            children: List.generate(detail.daysInMonth, (i) {
                              final day = i + 1;
                              final isOos = product.daysOos.containsKey(day);
                              return Container(
                                width: dayWidth,
                                height: cellHeight,
                                decoration: BoxDecoration(
                                  color: isOos
                                      ? Colors.red.withOpacity(0.3)
                                      : AppColors.night,
                                  border: Border.all(color: borderColor, width: 0.5),
                                ),
                                alignment: Alignment.center,
                                child: isOos
                                    ? Text(
                                        '0',
                                        style: TextStyle(
                                          color: Colors.red.shade300,
                                          fontSize: 11.sp,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              );
                            }),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

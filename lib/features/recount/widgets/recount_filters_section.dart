import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Секция фильтров (магазин, сотрудник, дата) для отчётов пересчёта
class RecountFiltersSection extends StatelessWidget {
  final String? selectedShop;
  final String? selectedEmployee;
  final DateTime? selectedDate;
  final List<String> uniqueShops;
  final List<String> uniqueEmployees;
  final ValueChanged<String?> onShopChanged;
  final ValueChanged<String?> onEmployeeChanged;
  final VoidCallback onDateTap;
  final VoidCallback onReset;

  const RecountFiltersSection({
    super.key,
    required this.selectedShop,
    required this.selectedEmployee,
    required this.selectedDate,
    required this.uniqueShops,
    required this.uniqueEmployees,
    required this.onShopChanged,
    required this.onEmployeeChanged,
    required this.onDateTap,
    required this.onReset,
  });

  bool get _hasActiveFilters =>
      selectedShop != null || selectedEmployee != null || selectedDate != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Магазин
          DropdownButtonFormField<String>(
            value: selectedShop,
            isExpanded: true,
            dropdownColor: AppColors.emeraldDark,
            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14.sp),
            decoration: InputDecoration(
              labelText: 'Магазин',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: AppColors.gold)),
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            ),
            iconEnabledColor: AppColors.gold,
            items: [
              DropdownMenuItem<String>(
                value: null,
                child: Text('Все магазины', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              ),
              ...uniqueShops.map((shop) => DropdownMenuItem<String>(
                value: shop,
                child: Text(shop, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.9))),
              )),
            ],
            onChanged: onShopChanged,
          ),
          SizedBox(height: 10),
          // Сотрудник и Дата в одном ряду
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: selectedEmployee,
                  isExpanded: true,
                  dropdownColor: AppColors.emeraldDark,
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14.sp),
                  decoration: InputDecoration(
                    labelText: 'Сотрудник',
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: AppColors.gold)),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  ),
                  iconEnabledColor: AppColors.gold,
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text('Все', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    ),
                    ...uniqueEmployees.map((employee) => DropdownMenuItem<String>(
                      value: employee,
                      child: Text(employee, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    )),
                  ],
                  onChanged: onEmployeeChanged,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: onDateTap,
                  borderRadius: BorderRadius.circular(10.r),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Дата', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp)),
                              Text(
                                selectedDate != null
                                    ? '${selectedDate!.day}.${selectedDate!.month}'
                                    : 'Все',
                                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14.sp),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.calendar_today, size: 18, color: AppColors.gold),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Сброс фильтров
          if (_hasActiveFilters)
            Padding(
              padding: EdgeInsets.only(top: 10.h),
              child: GestureDetector(
                onTap: onReset,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.clear, size: 18, color: Colors.red),
                      SizedBox(width: 6),
                      Text('Сбросить фильтры', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

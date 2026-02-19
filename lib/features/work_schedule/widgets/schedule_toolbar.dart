import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Тулбар с кнопками управления графиком (период, месяц, автозаполнение, PDF, очистка)
class ScheduleToolbar extends StatelessWidget {
  final bool hasSchedule;
  final VoidCallback onSelectPeriod;
  final VoidCallback onSelectMonth;
  final VoidCallback onAutoFill;
  final VoidCallback onExportPdf;
  final VoidCallback onClear;

  const ScheduleToolbar({
    super.key,
    required this.hasSchedule,
    required this.onSelectPeriod,
    required this.onSelectMonth,
    required this.onAutoFill,
    required this.onExportPdf,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.06),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Ряд 1: Период | Месяц | Автозаполнение
          Row(
            children: [
              Expanded(
                child: _buildToolbarChip(
                  icon: Icons.date_range,
                  label: 'Период',
                  onTap: onSelectPeriod,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _buildToolbarChip(
                  icon: Icons.calendar_today,
                  label: 'Месяц',
                  onTap: onSelectMonth,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _buildToolbarChip(
                  icon: Icons.auto_fix_high,
                  label: 'Автозаполнение',
                  onTap: hasSchedule ? onAutoFill : null,
                  enabled: hasSchedule,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          // Ряд 2: PDF | Очистка (по центру)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 120,
                child: _buildToolbarChip(
                  icon: Icons.picture_as_pdf,
                  label: 'PDF',
                  onTap: hasSchedule ? onExportPdf : null,
                  enabled: hasSchedule,
                ),
              ),
              SizedBox(width: 16),
              SizedBox(
                width: 120,
                child: _buildToolbarChip(
                  icon: Icons.cleaning_services,
                  label: 'Очистка',
                  onTap: hasSchedule ? onClear : null,
                  enabled: hasSchedule,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarChip({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final isEnabled = enabled && onTap != null;

    return Container(
      decoration: BoxDecoration(
        color: isEnabled ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(
          color: isEnabled ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.06),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? onTap : null,
          borderRadius: BorderRadius.circular(8.r),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isEnabled ? Colors.white.withOpacity(0.8) : Colors.white.withOpacity(0.3),
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: isEnabled ? Colors.white.withOpacity(0.8) : Colors.white.withOpacity(0.3),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

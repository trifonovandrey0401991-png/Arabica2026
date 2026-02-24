import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Виджет редактирования временного окна
class TimeWindowPickerWidget extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String startTime;
  final String endTime;
  final ValueChanged<String> onStartChanged;
  final ValueChanged<String> onEndChanged;
  final Color primaryColor;
  final String startLabel;
  final String endLabel;

  const TimeWindowPickerWidget({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.onStartChanged,
    required this.onEndChanged,
    this.primaryColor = const Color(0xFFf46b45),
    this.startLabel = 'Начало',
    this.endLabel = 'Дедлайн',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TimePickerButton(
                label: startLabel,
                time: startTime,
                onChanged: onStartChanged,
                color: AppColors.emeraldGreen,
                primaryColor: primaryColor,
              ),
            ),
            SizedBox(width: 12),
            Icon(Icons.arrow_forward, color: Colors.white.withOpacity(0.3), size: 20),
            SizedBox(width: 12),
            Expanded(
              child: _TimePickerButton(
                label: endLabel,
                time: endTime,
                onChanged: onEndChanged,
                color: AppColors.error,
                primaryColor: primaryColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Кнопка выбора времени
class _TimePickerButton extends StatelessWidget {
  final String label;
  final String time;
  final ValueChanged<String> onChanged;
  final Color color;
  final Color primaryColor;

  _TimePickerButton({
    required this.label,
    required this.time,
    required this.onChanged,
    required this.color,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final parts = time.split(':');
        final initialTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );

        final picked = await showTimePicker(
          context: context,
          initialTime: initialTime,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.dark(
                    primary: primaryColor,
                    onPrimary: Colors.white,
                    surface: AppColors.emeraldDark,
                    onSurface: Colors.white,
                  ),
                ),
                child: child!,
              ),
            );
          },
        );

        if (picked != null) {
          final newTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          onChanged(newTime);
        }
      },
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.access_time, size: 18, color: color),
                SizedBox(width: 6),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Контейнер для нескольких временных окон
class TimeWindowsSection extends StatelessWidget {
  final List<TimeWindowPickerWidget> windows;

  const TimeWindowsSection({
    super.key,
    required this.windows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
      ),
      padding: EdgeInsets.all(20.w),
      child: Column(
        children: [
          for (int i = 0; i < windows.length; i++) ...[
            windows[i],
            if (i < windows.length - 1) ...[
              SizedBox(height: 16),
              Divider(color: AppColors.emerald.withOpacity(0.3)),
              SizedBox(height: 16),
            ],
          ],
        ],
      ),
    );
  }
}

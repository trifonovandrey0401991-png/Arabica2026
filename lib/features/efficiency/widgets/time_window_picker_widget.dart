import 'package:flutter/material.dart';

/// Виджет редактирования временного окна
///
/// Используется для настройки временных интервалов (утренняя/вечерняя смена).
/// Включает:
/// - Иконку с заголовком
/// - Две кнопки выбора времени (начало и конец)
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
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3436),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TimePickerButton(
                label: startLabel,
                time: startTime,
                onChanged: onStartChanged,
                color: Colors.green,
                primaryColor: primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.arrow_forward, color: Colors.grey[400], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: _TimePickerButton(
                label: endLabel,
                time: endTime,
                onChanged: onEndChanged,
                color: Colors.red,
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

  const _TimePickerButton({
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
                  colorScheme: ColorScheme.light(
                    primary: primaryColor,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black,
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.access_time, size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 18,
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
///
/// Используется для группировки утренней и вечерней смены.
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          for (int i = 0; i < windows.length; i++) ...[
            windows[i],
            if (i < windows.length - 1) ...[
              const SizedBox(height: 16),
              Divider(color: Colors.grey[200]),
              const SizedBox(height: 16),
            ],
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Переиспользуемый виджет слайдера для настроек баллов
///
/// Используется во всех settings pages для настройки числовых параметров.
/// Включает:
/// - Иконку с цветовым оформлением
/// - Заголовок и подзаголовок
/// - Слайдер с кастомным стилем
/// - Отображение текущего значения
class SettingsSliderWidget extends StatelessWidget {
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String? valueLabel;
  final bool isInteger;
  final Color accentColor;
  final IconData icon;

  const SettingsSliderWidget({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.valueLabel,
    this.isInteger = false,
    this.accentColor = const Color(0xFFf46b45),
    this.icon = Icons.tune,
  });

  String get _displayValue {
    if (valueLabel != null) return valueLabel!;
    if (isInteger) return value.round().toString();
    if (value >= 0) return '+${value.toStringAsFixed(1)}';
    return value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Icon container
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 14),
                // Title and subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3436),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                // Value badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    _displayValue,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Slider
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: accentColor,
                inactiveTrackColor: accentColor.withOpacity(0.2),
                thumbColor: accentColor,
                overlayColor: accentColor.withOpacity(0.2),
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
            // Min/max labels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isInteger ? min.toInt().toString() : min.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    isInteger ? max.toInt().toString() : max.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

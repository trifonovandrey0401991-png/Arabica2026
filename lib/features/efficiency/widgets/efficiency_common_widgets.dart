import 'package:flutter/material.dart';
import '../models/efficiency_data_model.dart';
import '../utils/efficiency_utils.dart';

/// Кнопка выбора месяца с модальным окном
class MonthPickerButton extends StatelessWidget {
  final int selectedMonth;
  final int selectedYear;
  final ValueChanged<Map<String, int>> onMonthSelected;

  const MonthPickerButton({
    super.key,
    required this.selectedMonth,
    required this.selectedYear,
    required this.onMonthSelected,
  });

  void _showMonthPicker(BuildContext context) async {
    final months = EfficiencyUtils.generateMonthsList();

    await showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Выберите месяц',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: months.length,
                itemBuilder: (context, index) {
                  final month = months[index];
                  final isSelected = month['year'] == selectedYear &&
                      month['month'] == selectedMonth;
                  return ListTile(
                    title: Text(
                      month['name'],
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? EfficiencyUtils.primaryColor
                            : Colors.black,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check,
                            color: EfficiencyUtils.primaryColor)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      onMonthSelected({
                        'year': month['year'] as int,
                        'month': month['month'] as int,
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _showMonthPicker(context),
      icon: const Icon(Icons.calendar_today, color: Colors.white, size: 18),
      label: Text(
        EfficiencyUtils.getMonthName(selectedMonth, selectedYear),
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}

/// Карточка общей статистики
class EfficiencySummaryCard extends StatelessWidget {
  final List<EfficiencySummary> summaries;
  final String? additionalInfo;

  const EfficiencySummaryCard({
    super.key,
    required this.summaries,
    this.additionalInfo,
  });

  @override
  Widget build(BuildContext context) {
    final totalEarned = summaries.fold(0.0, (sum, s) => sum + s.earnedPoints);
    final totalLost = summaries.fold(0.0, (sum, s) => sum + s.lostPoints);
    final total = totalEarned - totalLost;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: EfficiencyUtils.secondaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Общая статистика',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: EfficiencyUtils.primaryColor,
                  ),
                ),
                if (additionalInfo != null)
                  Text(
                    additionalInfo!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatColumn(
                  value: '+${totalEarned.toStringAsFixed(1)}',
                  label: 'Заработано',
                  color: Colors.green,
                ),
                _StatColumn(
                  value: '-${totalLost.toStringAsFixed(1)}',
                  label: 'Потеряно',
                  color: Colors.red,
                ),
                _StatColumn(
                  value: total >= 0
                      ? '+${total.toStringAsFixed(1)}'
                      : total.toStringAsFixed(1),
                  label: 'Итого',
                  color: total >= 0 ? EfficiencyUtils.primaryColor : Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Внутренний виджет для отображения статистики
class _StatColumn extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatColumn({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

/// Progress bar для earned/lost
class EfficiencyProgressBar extends StatelessWidget {
  final EfficiencySummary summary;

  const EfficiencyProgressBar({
    super.key,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final total = summary.earnedPoints + summary.lostPoints;
    if (total == 0) return const SizedBox.shrink();

    final earnedPercent = summary.earnedPoints / total;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Row(
        children: [
          Expanded(
            flex: (earnedPercent * 100).round(),
            child: Container(
              height: 4,
              color: Colors.green[400],
            ),
          ),
          Expanded(
            flex: ((1 - earnedPercent) * 100).round(),
            child: Container(
              height: 4,
              color: Colors.red[400],
            ),
          ),
        ],
      ),
    );
  }
}

/// Состояние загрузки
class EfficiencyLoadingState extends StatelessWidget {
  const EfficiencyLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: EfficiencyUtils.primaryColor),
          SizedBox(height: 16),
          Text('Загрузка данных...'),
        ],
      ),
    );
  }
}

/// Состояние ошибки
class EfficiencyErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const EfficiencyErrorState({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(error, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

/// Пустое состояние
class EfficiencyEmptyState extends StatelessWidget {
  final String monthName;
  final IconData icon;
  final String message;

  const EfficiencyEmptyState({
    super.key,
    required this.monthName,
    this.icon = Icons.person_outline,
    this.message = 'Баллы появятся после оценки отчетов',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Нет данных за $monthName',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

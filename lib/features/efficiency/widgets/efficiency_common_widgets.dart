import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

// ===== ВИДЖЕТЫ ДЛЯ DETAIL СТРАНИЦ =====

/// Карточка с общими баллами для detail страниц
class EfficiencyDetailTotalCard extends StatelessWidget {
  final EfficiencySummary summary;
  final String monthName;

  const EfficiencyDetailTotalCard({
    super.key,
    required this.summary,
    required this.monthName,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = summary.totalPoints >= 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              monthName,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              summary.formattedTotal,
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: isPositive ? Colors.green[700] : Colors.red[700],
              ),
            ),
            const Text(
              'баллов',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _DetailStatItem(
                  value: '+${summary.earnedPoints.toStringAsFixed(1)}',
                  label: 'Заработано',
                  color: Colors.green,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey[300],
                ),
                _DetailStatItem(
                  value: '-${summary.lostPoints.toStringAsFixed(1)}',
                  label: 'Потеряно',
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Внутренний виджет статистики для detail карточки
class _DetailStatItem extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _DetailStatItem({
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
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

/// Карточка с категориями для detail страниц
class EfficiencyDetailCategoriesCard extends StatelessWidget {
  final EfficiencySummary summary;

  const EfficiencyDetailCategoriesCard({
    super.key,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    // Категории уже отсортированы в categorySummaries
    final categories = summary.categorySummaries;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'По категориям',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: EfficiencyUtils.primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            if (categories.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Нет данных',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ...categories.map((cat) => _buildCategoryRow(cat)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRow(CategoryData categoryData) {
    final isPositive = categoryData.points >= 0;
    final formattedPoints = isPositive
        ? '+${categoryData.points.toStringAsFixed(2)}'
        : categoryData.points.toStringAsFixed(2);

    // Используем baseCategory для иконки и цвета
    final color = EfficiencyUtils.getCategoryColor(categoryData.baseCategory);
    final icon = EfficiencyUtils.getCategoryIcon(categoryData.baseCategory);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              categoryData.name,  // Используем настоящее имя категории
              style: const TextStyle(fontSize: 15),
            ),
          ),
          Text(
            formattedPoints,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isPositive ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточка с последними записями для detail страниц (с фильтрацией по категориям)
class EfficiencyDetailRecentRecordsCard extends StatefulWidget {
  final EfficiencySummary summary;
  /// Показывать имя сотрудника (для страницы магазина) или адрес магазина (для страницы сотрудника)
  final bool showEmployeeName;

  const EfficiencyDetailRecentRecordsCard({
    super.key,
    required this.summary,
    this.showEmployeeName = true,
  });

  @override
  State<EfficiencyDetailRecentRecordsCard> createState() => _EfficiencyDetailRecentRecordsCardState();
}

class _EfficiencyDetailRecentRecordsCardState extends State<EfficiencyDetailRecentRecordsCard> {
  /// Выбранная категория для фильтрации (null = все категории)
  EfficiencyCategory? _selectedCategory;

  /// Получить уникальные категории из записей
  List<EfficiencyCategory> get _availableCategories {
    final categories = widget.summary.records
        .map((r) => r.category)
        .toSet()
        .toList();
    // Сортируем по displayName
    categories.sort((a, b) => a.displayName.compareTo(b.displayName));
    return categories;
  }

  /// Отфильтрованные записи
  List<EfficiencyRecord> get _filteredRecords {
    var records = List<EfficiencyRecord>.from(widget.summary.records);

    // Фильтруем по категории если выбрана
    if (_selectedCategory != null) {
      records = records.where((r) => r.category == _selectedCategory).toList();
    }

    // Сортируем по дате (новые сначала)
    records.sort((a, b) => b.date.compareTo(a.date));

    // Берем последние 30 записей (увеличено для фильтрации)
    return records.take(30).toList();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _availableCategories;
    final filteredRecords = _filteredRecords;

    return Card(
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
                  'Записи',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: EfficiencyUtils.primaryColor,
                  ),
                ),
                Text(
                  _selectedCategory != null
                      ? '${filteredRecords.length} из ${widget.summary.recordsCount}'
                      : 'Всего: ${widget.summary.recordsCount}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            // Фильтр по категориям (показываем только если > 1 категории)
            if (categories.length > 1) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Чип "Все"
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('Все'),
                        selected: _selectedCategory == null,
                        onSelected: (_) {
                          setState(() => _selectedCategory = null);
                        },
                        selectedColor: EfficiencyUtils.secondaryColor,
                        checkmarkColor: EfficiencyUtils.primaryColor,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: _selectedCategory == null
                              ? EfficiencyUtils.primaryColor
                              : Colors.grey[700],
                        ),
                      ),
                    ),
                    // Чипы категорий
                    ...categories.map((category) {
                      final isSelected = _selectedCategory == category;
                      final color = EfficiencyUtils.getCategoryColor(category);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(category.displayName),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              _selectedCategory = isSelected ? null : category;
                            });
                          },
                          selectedColor: color.withOpacity(0.2),
                          checkmarkColor: color,
                          avatar: isSelected ? null : Icon(
                            EfficiencyUtils.getCategoryIcon(category),
                            size: 16,
                            color: color,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: isSelected ? color : Colors.grey[700],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (filteredRecords.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _selectedCategory != null
                        ? 'Нет записей в категории "${_selectedCategory!.displayName}"'
                        : 'Нет записей',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ...filteredRecords.map((record) => _buildRecordRow(record)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordRow(EfficiencyRecord record) {
    final dateFormat = DateFormat('dd.MM');
    final isPositive = record.points >= 0;

    // Определяем вторичную информацию (имя сотрудника или адрес магазина)
    String secondaryInfo = '';
    if (widget.showEmployeeName) {
      secondaryInfo = record.employeeName;
    } else {
      // Для штрафов берем shopAddress из rawValue
      secondaryInfo = record.shopAddress;
      if (secondaryInfo.isEmpty && record.category == EfficiencyCategory.shiftPenalty) {
        if (record.rawValue is Map && record.rawValue['shopAddress'] != null) {
          secondaryInfo = record.rawValue['shopAddress'];
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 45,
            child: Text(
              dateFormat.format(record.date),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.categoryName,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Показываем причину/значение под категорией
                Text(
                  record.formattedRawValue,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (secondaryInfo.isNotEmpty)
                  Text(
                    secondaryInfo,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[400],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            record.formattedPoints,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isPositive ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ],
      ),
    );
  }
}

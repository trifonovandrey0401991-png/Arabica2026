import 'package:flutter/material.dart';
import '../models/efficiency_data_model.dart';
import '../services/efficiency_data_service.dart';
import '../widgets/efficiency_common_widgets.dart';
import '../utils/efficiency_utils.dart';
import 'shop_efficiency_detail_page.dart';

/// Страница списка эффективности по магазинам
class EfficiencyByShopPage extends StatefulWidget {
  const EfficiencyByShopPage({super.key});

  @override
  State<EfficiencyByShopPage> createState() => _EfficiencyByShopPageState();
}

class _EfficiencyByShopPageState extends State<EfficiencyByShopPage> {
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
      appBar: AppBar(
        title: const Text('По магазинам'),
        backgroundColor: EfficiencyUtils.primaryColor,
        actions: [
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const EfficiencyLoadingState();
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
      onRefresh: () => _loadData(forceRefresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      summary.entityName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isPositive ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      summary.formattedTotal,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isPositive ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '+${summary.earnedPoints.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.green[600],
                    ),
                  ),
                  const Text(' / ', style: TextStyle(color: Colors.grey)),
                  Text(
                    '-${summary.lostPoints.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.red[600],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${summary.recordsCount} записей',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey[400],
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              EfficiencyProgressBar(summary: summary),
            ],
          ),
        ),
      ),
    );
  }
}

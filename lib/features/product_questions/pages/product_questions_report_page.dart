import 'package:flutter/material.dart';
import '../models/product_question_model.dart';
import '../services/product_question_service.dart';
import '../../../core/services/multitenancy_filter_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница отчёта по поиску товаров - статистика по магазинам
class ProductQuestionsReportPage extends StatefulWidget {
  const ProductQuestionsReportPage({super.key});

  @override
  State<ProductQuestionsReportPage> createState() => _ProductQuestionsReportPageState();
}

class _ProductQuestionsReportPageState extends State<ProductQuestionsReportPage> {
  bool _isLoading = true;
  Map<String, ShopQuestionStats> _shopStats = {};
  Map<String, int> _unreadByShop = {};
  String? _expandedShop;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() {
      _isLoading = true;
    });

    try {
      final allQuestions = await ProductQuestionService.getQuestions();
      final questions = await MultitenancyFilterService.filterByShopAddress(
        allQuestions,
        (question) => question.shopAddress,
      );

      final allUnviewedCounts = await ProductQuestionService.getUnviewedByAdminCounts();
      final allowedAddresses = await MultitenancyFilterService.getAllowedShopAddresses();
      final unviewedCounts = allowedAddresses == null
          ? allUnviewedCounts
          : Map.fromEntries(
              allUnviewedCounts.entries.where((e) => allowedAddresses.contains(e.key)),
            );

      final stats = <String, ShopQuestionStats>{};

      for (final question in questions) {
        final shopAddress = question.shopAddress;

        if (!stats.containsKey(shopAddress)) {
          stats[shopAddress] = ShopQuestionStats(shopAddress: shopAddress);
        }

        stats[shopAddress]!.addQuestion(question);
      }

      for (final shopAddress in unviewedCounts.keys) {
        if (!stats.containsKey(shopAddress)) {
          stats[shopAddress] = ShopQuestionStats(shopAddress: shopAddress);
        }
      }

      if (!mounted) return;
      setState(() {
        _shopStats = stats;
        _unreadByShop = unviewedCounts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Отчет (Поиск товаров)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadData,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : _shopStats.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.search_off, size: 40, color: Colors.white.withOpacity(0.3)),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Нет данных о вопросах',
                                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16.sp),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadData,
                            color: AppColors.gold,
                            backgroundColor: AppColors.emeraldDark,
                            child: ListView.builder(
                              padding: EdgeInsets.all(16.w),
                              itemCount: _shopStats.length,
                              itemBuilder: (context, index) {
                                final shopAddress = _shopStats.keys.elementAt(index);
                                final stats = _shopStats[shopAddress]!;
                                final isExpanded = _expandedShop == shopAddress;
                                final unreadCount = _unreadByShop[shopAddress] ?? 0;

                                return _buildShopCard(shopAddress, stats, isExpanded, unreadCount);
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShopCard(String shopAddress, ShopQuestionStats stats, bool isExpanded, int unreadCount) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Основная строка магазина
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14.r),
              onTap: () async {
                if (!isExpanded) {
                  await ProductQuestionService.markShopViewedByAdmin(shopAddress);
                  final allCounts = await ProductQuestionService.getUnviewedByAdminCounts();
                  final allowed = await MultitenancyFilterService.getAllowedShopAddresses();
                  final unviewedCounts = allowed == null
                      ? allCounts
                      : Map.fromEntries(
                          allCounts.entries.where((e) => allowed.contains(e.key)),
                        );
                  if (mounted) setState(() {
                    _expandedShop = shopAddress;
                    _unreadByShop = unviewedCounts;
                  });
                } else {
                  if (mounted) setState(() {
                    _expandedShop = null;
                  });
                }
              },
              child: Padding(
                padding: EdgeInsets.all(14.w),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.emerald,
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Icon(Icons.store, color: Colors.white, size: 22),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: EdgeInsets.all(4.w),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              child: Text(
                                unreadCount.toString(),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shopAddress,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                          Text(
                            'За всё время',
                            style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.4)),
                          ),
                        ],
                      ),
                    ),
                    _buildStatsChip(
                      total: stats.totalAll,
                      answered: stats.answeredAll,
                      unanswered: stats.unansweredAll,
                    ),
                    SizedBox(width: 8),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Развёрнутая информация
          if (isExpanded)
            Container(
              padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Colors.white.withOpacity(0.1)),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_month, size: 20, color: AppColors.gold),
                      SizedBox(width: 8),
                      Text(
                        'За текущий месяц (${_getCurrentMonthName()}):',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  _buildDetailedStats(stats),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsChip({
    required int total,
    required int answered,
    required int unanswered,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$total',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.8),
              fontSize: 13.sp,
            ),
          ),
          Text(' / ', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13.sp)),
          Text(
            '$answered',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green,
              fontSize: 13.sp,
            ),
          ),
          Text(' / ', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13.sp)),
          Text(
            '$unanswered',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: unanswered > 0 ? Colors.red : Colors.white.withOpacity(0.3),
              fontSize: 13.sp,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedStats(ShopQuestionStats stats) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              label: 'Всего',
              value: stats.totalMonth.toString(),
              color: Colors.blue[300]!,
              icon: Icons.help_outline,
            ),
            _buildStatItem(
              label: 'Отвечено',
              value: stats.answeredMonth.toString(),
              color: Colors.green,
              icon: Icons.check_circle_outline,
            ),
            _buildStatItem(
              label: 'Не отвечено',
              value: stats.unansweredMonth.toString(),
              color: stats.unansweredMonth > 0 ? Colors.red : Colors.white.withOpacity(0.3),
              icon: Icons.error_outline,
            ),
          ],
        ),
        SizedBox(height: 16),
        Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: AppColors.emerald.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Итого за месяц: ',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
              _buildStatsChip(
                total: stats.totalMonth,
                answered: stats.answeredMonth,
                unanswered: stats.unansweredMonth,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24.sp,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
      ],
    );
  }

  String _getCurrentMonthName() {
    final now = DateTime.now();
    final months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    return '${months[now.month - 1]} ${now.year}';
  }
}

/// Класс для хранения статистики по магазину
class ShopQuestionStats {
  final String shopAddress;

  int totalAll = 0;
  int answeredAll = 0;
  int unansweredAll = 0;

  int totalMonth = 0;
  int answeredMonth = 0;
  int unansweredMonth = 0;

  ShopQuestionStats({required this.shopAddress});

  void addQuestion(ProductQuestion question) {
    totalAll++;

    final hasAnswer = question.messages.any((msg) => msg.senderType == 'employee');

    if (hasAnswer) {
      answeredAll++;
    } else {
      unansweredAll++;
    }

    final now = DateTime.now();
    try {
      final questionDate = DateTime.parse(question.timestamp);
      if (questionDate.year == now.year && questionDate.month == now.month) {
        totalMonth++;
        if (hasAnswer) {
          answeredMonth++;
        } else {
          unansweredMonth++;
        }
      }
    } catch (e) {
      // Игнорируем ошибки парсинга даты
    }
  }
}

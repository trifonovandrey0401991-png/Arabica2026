import 'package:flutter/material.dart';
import '../models/product_question_model.dart';
import '../services/product_question_service.dart';
import '../../../core/services/multitenancy_filter_service.dart';

/// Страница отчёта по поиску товаров - статистика по магазинам
class ProductQuestionsReportPage extends StatefulWidget {
  const ProductQuestionsReportPage({super.key});

  @override
  State<ProductQuestionsReportPage> createState() => _ProductQuestionsReportPageState();
}

class _ProductQuestionsReportPageState extends State<ProductQuestionsReportPage> {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

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
    setState(() {
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

      setState(() {
        _shopStats = stats;
        _unreadByShop = unviewedCounts;
        _isLoading = false;
      });
    } catch (e) {
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
      backgroundColor: _night,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Отчет (Поиск товаров)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
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
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: _gold))
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
                                const SizedBox(height: 16),
                                Text(
                                  'Нет данных о вопросах',
                                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadData,
                            color: _gold,
                            backgroundColor: _emeraldDark,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
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
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Основная строка магазина
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
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
                  setState(() {
                    _expandedShop = shopAddress;
                    _unreadByShop = unviewedCounts;
                  });
                } else {
                  setState(() {
                    _expandedShop = null;
                  });
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _emerald,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.store, color: Colors.white, size: 22),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              child: Text(
                                unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
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
                            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
                          ),
                        ],
                      ),
                    ),
                    _buildStatsChip(
                      total: stats.totalAll,
                      answered: stats.answeredAll,
                      unanswered: stats.unansweredAll,
                    ),
                    const SizedBox(width: 8),
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_month, size: 20, color: _gold),
                      const SizedBox(width: 8),
                      Text(
                        'За текущий месяц (${_getCurrentMonthName()}):',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
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
              fontSize: 13,
            ),
          ),
          Text(' / ', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13)),
          Text(
            '$answered',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green,
              fontSize: 13,
            ),
          ),
          Text(' / ', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13)),
          Text(
            '$unanswered',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: unanswered > 0 ? Colors.red : Colors.white.withOpacity(0.3),
              fontSize: 13,
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
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _emerald.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10),
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
        const SizedBox(height: 4),
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
            fontSize: 12,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
      ],
    );
  }

  String _getCurrentMonthName() {
    final now = DateTime.now();
    const months = [
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

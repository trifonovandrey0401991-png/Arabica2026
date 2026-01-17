import 'package:flutter/material.dart';
import '../models/product_question_model.dart';
import '../services/product_question_service.dart';

/// Страница отчёта по поиску товаров - статистика по магазинам
class ProductQuestionsReportPage extends StatefulWidget {
  const ProductQuestionsReportPage({super.key});

  @override
  State<ProductQuestionsReportPage> createState() => _ProductQuestionsReportPageState();
}

class _ProductQuestionsReportPageState extends State<ProductQuestionsReportPage> {
  bool _isLoading = true;
  List<ProductQuestion> _allQuestions = [];
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
      // Загружаем все вопросы (общие, не персональные диалоги)
      final questions = await ProductQuestionService.getQuestions();

      // Загружаем количество непросмотренных админом диалогов по магазинам
      // (диалоги, на которые сотрудник ответил, но админ ещё не просмотрел)
      final unviewedCounts = await ProductQuestionService.getUnviewedByAdminCounts();

      // Группируем по магазинам и считаем статистику
      final stats = <String, ShopQuestionStats>{};

      for (final question in questions) {
        final shopAddress = question.shopAddress;

        if (!stats.containsKey(shopAddress)) {
          stats[shopAddress] = ShopQuestionStats(shopAddress: shopAddress);
        }

        stats[shopAddress]!.addQuestion(question);
      }

      // Добавляем магазины из непросмотренных диалогов, которых нет в stats
      for (final shopAddress in unviewedCounts.keys) {
        if (!stats.containsKey(shopAddress)) {
          stats[shopAddress] = ShopQuestionStats(shopAddress: shopAddress);
        }
      }

      setState(() {
        _allQuestions = questions;
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
      appBar: AppBar(
        title: const Text('Отчет (Поиск товаров)'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _shopStats.isEmpty
              ? const Center(
                  child: Text(
                    'Нет данных о вопросах',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _shopStats.length,
                  itemBuilder: (context, index) {
                    final shopAddress = _shopStats.keys.elementAt(index);
                    final stats = _shopStats[shopAddress]!;
                    final isExpanded = _expandedShop == shopAddress;

                    final unreadCount = _unreadByShop[shopAddress] ?? 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        children: [
                          // Основная строка магазина
                          ListTile(
                            leading: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(
                                  Icons.store,
                                  color: Color(0xFF004D40),
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
                            title: Text(
                              shopAddress,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: const Text('За всё время'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildStatsChip(
                                  total: stats.totalAll,
                                  answered: stats.answeredAll,
                                  unanswered: stats.unansweredAll,
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  isExpanded ? Icons.expand_less : Icons.expand_more,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                            onTap: () async {
                              if (!isExpanded) {
                                // При раскрытии магазина помечаем его диалоги как просмотренные админом
                                await ProductQuestionService.markShopViewedByAdmin(shopAddress);
                                // Обновляем счётчики непросмотренных админом диалогов
                                final unviewedCounts = await ProductQuestionService.getUnviewedByAdminCounts();
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
                          ),
                          // Развёрнутая информация - статистика за текущий месяц
                          if (isExpanded)
                            Container(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_month,
                                        size: 20,
                                        color: Color(0xFF004D40),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'За текущий месяц (${_getCurrentMonthName()}):',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
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
                  },
                ),
    );
  }

  Widget _buildStatsChip({
    required int total,
    required int answered,
    required int unanswered,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$total',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const Text(' / ', style: TextStyle(color: Colors.grey)),
          Text(
            '$answered',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const Text(' / ', style: TextStyle(color: Colors.grey)),
          Text(
            '$unanswered',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: unanswered > 0 ? Colors.red : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedStats(ShopQuestionStats stats) {
    return Column(
      children: [
        // Статистика за текущий месяц
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              label: 'Всего',
              value: stats.totalMonth.toString(),
              color: Colors.blue,
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
              color: stats.unansweredMonth > 0 ? Colors.red : Colors.grey,
              icon: Icons.error_outline,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Формат X/Y/Z за месяц
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF004D40).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Итого за месяц: ',
                style: TextStyle(fontWeight: FontWeight.w500),
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
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
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

  // За всё время
  int totalAll = 0;
  int answeredAll = 0;
  int unansweredAll = 0;

  // За текущий месяц
  int totalMonth = 0;
  int answeredMonth = 0;
  int unansweredMonth = 0;

  ShopQuestionStats({required this.shopAddress});

  void addQuestion(ProductQuestion question) {
    totalAll++;

    // Проверяем, отвечен ли вопрос (есть хотя бы один ответ от сотрудника)
    final hasAnswer = question.messages.any((msg) => msg.senderType == 'employee');

    if (hasAnswer) {
      answeredAll++;
    } else {
      unansweredAll++;
    }

    // Проверяем, относится ли вопрос к текущему месяцу
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

import 'package:flutter/material.dart';
import '../models/employee_rating_model.dart';
import '../services/rating_service.dart';
import '../widgets/rating_badge_widget.dart';

/// Страница "Мой рейтинг" с историей за 3 месяца
class MyRatingPage extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const MyRatingPage({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<MyRatingPage> createState() => _MyRatingPageState();
}

class _MyRatingPageState extends State<MyRatingPage> {
  List<MonthlyRating> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    final history = await RatingService.getEmployeeRatingHistory(
      widget.employeeId,
      months: 3,
    );

    if (mounted) {
      setState(() {
        _history = history;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой рейтинг'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHistory,
              child: _history.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        return _buildMonthCard(_history[index]);
                      },
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.leaderboard_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Нет данных о рейтинге',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Рейтинг появится после первых смен',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthCard(MonthlyRating rating) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: rating.isTop3 ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: rating.isTop3
            ? BorderSide(
                color: _getBorderColor(rating.position),
                width: 2,
              )
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок с месяцем и позицией
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  rating.monthName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                RatingBadgeInline(
                  position: rating.position,
                  totalEmployees: rating.totalEmployees,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Статистика
            Row(
              children: [
                _buildStatItem(
                  'Баллы',
                  rating.totalPoints.toStringAsFixed(1),
                  Icons.star,
                  Colors.amber,
                ),
                const SizedBox(width: 16),
                _buildStatItem(
                  'Смен',
                  rating.shiftsCount.toString(),
                  Icons.work,
                  Colors.blue,
                ),
                const SizedBox(width: 16),
                _buildStatItem(
                  'Рефералы',
                  rating.referralPoints.toInt().toString(),
                  Icons.person_add,
                  Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Нормализованный рейтинг
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF004D40).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.trending_up,
                    size: 20,
                    color: Color(0xFF004D40),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Нормализованный рейтинг: ${rating.normalizedRating.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF004D40),
                    ),
                  ),
                ],
              ),
            ),

            // Награда за топ-N (динамически: 1-10)
            if (rating.position >= 1 && rating.position <= 10) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _getGradientColors(rating.position),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(
                      rating.positionIcon,
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _getRewardText(rating.position),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
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
      ),
    );
  }

  Color _getBorderColor(int position) {
    switch (position) {
      case 1:
        return const Color(0xFFFFD700);
      case 2:
        return const Color(0xFFC0C0C0);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return Colors.transparent;
    }
  }

  List<Color> _getGradientColors(int position) {
    switch (position) {
      case 1:
        return [const Color(0xFFFFD700), const Color(0xFFFFA500)];
      case 2:
        return [const Color(0xFFC0C0C0), const Color(0xFF808080)];
      case 3:
        return [const Color(0xFFCD7F32), const Color(0xFF8B4513)];
      default:
        return [Colors.grey, Colors.grey];
    }
  }

  String _getRewardText(int position) {
    // Топ-1: 2 прокрутки, остальные (2-N): 1 прокрутка
    // N определяется настройкой topEmployeesCount (1-10)
    if (position == 1) {
      return '1 место! 2 прокрутки Колеса Удачи';
    } else if (position >= 2 && position <= 10) {
      // Показываем награду для позиций 2-10
      // (прокрутки выдаются только если position <= topEmployeesCount)
      return '$position место! 1 прокрутка Колеса Удачи';
    }
    return '';
  }
}

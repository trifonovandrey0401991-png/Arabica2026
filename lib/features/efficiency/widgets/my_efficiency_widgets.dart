import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/efficiency_data_model.dart';
import '../../bonuses/models/bonus_penalty_model.dart';
import '../../bonuses/pages/bonus_penalty_history_page.dart';
import '../../referrals/models/referral_stats_model.dart';
import '../../rating/pages/my_rating_page.dart';

/// Виджеты для страницы "Моя эффективность"

// ============================================================================
// КАРТОЧКА ИТОГОВ
// ============================================================================

class MyEfficiencyTotalCard extends StatelessWidget {
  final double earnedPoints;
  final double lostPoints;
  final double totalPoints;

  const MyEfficiencyTotalCard({
    super.key,
    required this.earnedPoints,
    required this.lostPoints,
    required this.totalPoints,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = totalPoints >= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xFFE0F2F1),
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
                  'Итого за месяц',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF004D40),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isPositive ? Colors.green[50] : Colors.red[50],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isPositive
                        ? '+${totalPoints.toStringAsFixed(1)}'
                        : totalPoints.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isPositive ? Colors.green[700] : Colors.red[700],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  value: '+${earnedPoints.toStringAsFixed(1)}',
                  label: 'Заработано',
                  color: Colors.green,
                ),
                _StatItem(
                  value: '-${lostPoints.toStringAsFixed(1)}',
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

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatItem({
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

// ============================================================================
// КНОПКА РЕЙТИНГА
// ============================================================================

class MyEfficiencyRatingButton extends StatelessWidget {
  const MyEfficiencyRatingButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MyRatingPage()),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.emoji_events,
                    color: Color(0xFFFFD700),
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Мой рейтинг',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Посмотреть место в общем рейтинге',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// КАРТОЧКА РЕЗУЛЬТАТОВ ТЕСТОВ
// ============================================================================

class MyEfficiencyTestScoreCard extends StatelessWidget {
  final double? avgTestScore;
  final int totalTests;

  const MyEfficiencyTestScoreCard({
    super.key,
    required this.avgTestScore,
    required this.totalTests,
  });

  @override
  Widget build(BuildContext context) {
    if (avgTestScore == null || totalTests == 0) {
      return const SizedBox.shrink();
    }

    final percentage = (avgTestScore! / 20 * 100).round();
    Color scoreColor;
    String scoreLabel;

    if (percentage >= 90) {
      scoreColor = Colors.green;
      scoreLabel = 'Отлично';
    } else if (percentage >= 70) {
      scoreColor = Colors.orange;
      scoreLabel = 'Хорошо';
    } else if (percentage >= 50) {
      scoreColor = Colors.deepOrange;
      scoreLabel = 'Удовлетворительно';
    } else {
      scoreColor = Colors.red;
      scoreLabel = 'Требует улучшения';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
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
                  'Результаты тестирования',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF004D40),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scoreColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    scoreLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scoreColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _TestStatColumn(
                  value: avgTestScore!.toStringAsFixed(1),
                  label: 'Средний балл',
                  subLabel: 'из 20',
                  color: scoreColor,
                ),
                _TestStatColumn(
                  value: '$percentage%',
                  label: 'Процент',
                  subLabel: 'правильных',
                  color: scoreColor,
                ),
                _TestStatColumn(
                  value: totalTests.toString(),
                  label: 'Пройдено',
                  subLabel: 'тестов',
                  color: const Color(0xFF004D40),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TestStatColumn extends StatelessWidget {
  final String value;
  final String label;
  final String subLabel;
  final Color color;

  const _TestStatColumn({
    required this.value,
    required this.label,
    required this.subLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          subLabel,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// СЕКЦИЯ ПРЕМИЙ/ШТРАФОВ
// ============================================================================

class MyEfficiencyBonusPenaltySection extends StatelessWidget {
  final BonusPenaltySummary? bonusSummary;
  final String? employeeId;

  const MyEfficiencyBonusPenaltySection({
    super.key,
    required this.bonusSummary,
    required this.employeeId,
  });

  @override
  Widget build(BuildContext context) {
    if (bonusSummary == null) {
      return const SizedBox.shrink();
    }

    return MyEfficiencyBonusPenaltyCard(
      title: 'Премии и штрафы',
      bonusTotal: bonusSummary!.bonusTotal,
      penaltyTotal: bonusSummary!.penaltyTotal,
      netTotal: bonusSummary!.netTotal,
      bonusCount: bonusSummary!.bonusCount,
      penaltyCount: bonusSummary!.penaltyCount,
      onTap: employeeId != null
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      BonusPenaltyHistoryPage(employeeId: employeeId!),
                ),
              );
            }
          : null,
    );
  }
}

class MyEfficiencyBonusPenaltyCard extends StatelessWidget {
  final String title;
  final double bonusTotal;
  final double penaltyTotal;
  final double netTotal;
  final int bonusCount;
  final int penaltyCount;
  final VoidCallback? onTap;

  const MyEfficiencyBonusPenaltyCard({
    super.key,
    required this.title,
    required this.bonusTotal,
    required this.penaltyTotal,
    required this.netTotal,
    required this.bonusCount,
    required this.penaltyCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = netTotal >= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF004D40),
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _BonusPenaltyStat(
                      value: '+${bonusTotal.toStringAsFixed(0)} ₽',
                      label: 'Премии',
                      count: bonusCount,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BonusPenaltyStat(
                      value: '-${penaltyTotal.toStringAsFixed(0)} ₽',
                      label: 'Штрафы',
                      count: penaltyCount,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Итого:',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    isPositive
                        ? '+${netTotal.toStringAsFixed(0)} ₽'
                        : '${netTotal.toStringAsFixed(0)} ₽',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isPositive ? Colors.green[700] : Colors.red[700],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BonusPenaltyStat extends StatelessWidget {
  final String value;
  final String label;
  final int count;
  final Color color;

  const _BonusPenaltyStat({
    required this.value,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
            ),
          ),
          Text(
            '$count записей',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// СЕКЦИЯ РЕФЕРАЛЬНЫХ БАЛЛОВ
// ============================================================================

class MyEfficiencyReferralPointsSection extends StatelessWidget {
  final EmployeeReferralPoints? referralPoints;

  const MyEfficiencyReferralPointsSection({
    super.key,
    required this.referralPoints,
  });

  @override
  Widget build(BuildContext context) {
    if (referralPoints == null ||
        (referralPoints!.totalPoints == 0 &&
            referralPoints!.totalReferrals == 0)) {
      return const SizedBox.shrink();
    }

    return MyEfficiencyReferralPointsCard(
      totalPoints: referralPoints!.totalPoints,
      totalReferrals: referralPoints!.totalReferrals,
      activeReferrals: referralPoints!.activeReferrals,
      pendingPoints: referralPoints!.pendingPoints,
    );
  }
}

class MyEfficiencyReferralPointsCard extends StatelessWidget {
  final double totalPoints;
  final int totalReferrals;
  final int activeReferrals;
  final double pendingPoints;

  const MyEfficiencyReferralPointsCard({
    super.key,
    required this.totalPoints,
    required this.totalReferrals,
    required this.activeReferrals,
    required this.pendingPoints,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF004D40).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.people,
                      color: Color(0xFF004D40),
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Баллы за приглашения',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF004D40),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ReferralStat(
                  value: '+${totalPoints.toStringAsFixed(0)}',
                  label: 'Баллы',
                  color: Colors.green,
                ),
                _ReferralStat(
                  value: totalReferrals.toString(),
                  label: 'Приглашено',
                  color: const Color(0xFF004D40),
                ),
                _ReferralStat(
                  value: activeReferrals.toString(),
                  label: 'Активны',
                  color: Colors.blue,
                ),
              ],
            ),
            if (pendingPoints > 0) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.hourglass_empty, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Ожидают начисления: +${pendingPoints.toStringAsFixed(0)} баллов',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReferralStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _ReferralStat({
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
        const SizedBox(height: 4),
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

// ============================================================================
// КАРТОЧКА КАТЕГОРИЙ
// ============================================================================

class MyEfficiencyCategoriesCard extends StatelessWidget {
  final Map<EfficiencyCategory, double> categoryTotals;

  const MyEfficiencyCategoriesCard({
    super.key,
    required this.categoryTotals,
  });

  @override
  Widget build(BuildContext context) {
    if (categoryTotals.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedEntries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
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
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 12),
            ...sortedEntries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MyCategoryRow(
                    category: entry.key,
                    points: entry.value,
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class MyCategoryRow extends StatelessWidget {
  final EfficiencyCategory category;
  final double points;

  const MyCategoryRow({
    super.key,
    required this.category,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = points >= 0;
    final categoryName = _getCategoryName(category);
    final icon = _getCategoryIcon(category);

    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            categoryName,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        Text(
          isPositive
              ? '+${points.toStringAsFixed(1)}'
              : points.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isPositive ? Colors.green[700] : Colors.red[700],
          ),
        ),
      ],
    );
  }

  String _getCategoryName(EfficiencyCategory category) {
    switch (category) {
      case EfficiencyCategory.shift:
        return 'Пересменка';
      case EfficiencyCategory.recount:
        return 'Пересчёт';
      case EfficiencyCategory.shiftHandover:
        return 'Сдача смены';
      case EfficiencyCategory.attendance:
        return 'Посещаемость';
      case EfficiencyCategory.test:
        return 'Тестирование';
      case EfficiencyCategory.reviews:
        return 'Отзывы';
      case EfficiencyCategory.productSearch:
        return 'Поиск товара';
      case EfficiencyCategory.rko:
        return 'РКО';
      case EfficiencyCategory.orders:
        return 'Заказы';
      case EfficiencyCategory.shiftPenalty:
        return 'Штрафы смены';
      case EfficiencyCategory.tasks:
        return 'Задачи';
      default:
        return 'Неизвестно';
    }
  }

  IconData _getCategoryIcon(EfficiencyCategory category) {
    switch (category) {
      case EfficiencyCategory.shift:
        return Icons.assignment_turned_in;
      case EfficiencyCategory.recount:
        return Icons.inventory;
      case EfficiencyCategory.shiftHandover:
        return Icons.transfer_within_a_station;
      case EfficiencyCategory.attendance:
        return Icons.schedule;
      case EfficiencyCategory.test:
        return Icons.quiz;
      case EfficiencyCategory.reviews:
        return Icons.star;
      case EfficiencyCategory.productSearch:
        return Icons.search;
      case EfficiencyCategory.rko:
        return Icons.attach_money;
      case EfficiencyCategory.orders:
        return Icons.shopping_cart;
      case EfficiencyCategory.shiftPenalty:
        return Icons.warning;
      case EfficiencyCategory.tasks:
        return Icons.task;
      default:
        return Icons.help_outline;
    }
  }
}

// ============================================================================
// КАРТОЧКА МАГАЗИНОВ
// ============================================================================

class MyEfficiencyShopsCard extends StatelessWidget {
  final Map<String, double> shopTotals;

  const MyEfficiencyShopsCard({
    super.key,
    required this.shopTotals,
  });

  @override
  Widget build(BuildContext context) {
    if (shopTotals.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedEntries = shopTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'По магазинам',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 12),
            ...sortedEntries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MyShopRow(
                    shopAddress: entry.key,
                    points: entry.value,
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class MyShopRow extends StatelessWidget {
  final String shopAddress;
  final double points;

  const MyShopRow({
    super.key,
    required this.shopAddress,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = points >= 0;

    return Row(
      children: [
        Icon(Icons.store, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            shopAddress,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        Text(
          isPositive
              ? '+${points.toStringAsFixed(1)}'
              : points.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isPositive ? Colors.green[700] : Colors.red[700],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// КАРТОЧКА ПОСЛЕДНИХ ЗАПИСЕЙ
// ============================================================================

class MyEfficiencyRecentRecordsCard extends StatelessWidget {
  final List<EfficiencyRecord> recentRecords;

  const MyEfficiencyRecentRecordsCard({
    super.key,
    required this.recentRecords,
  });

  @override
  Widget build(BuildContext context) {
    if (recentRecords.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Последние записи',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 12),
            ...recentRecords.take(10).map((record) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MyRecordRow(record: record),
                )),
          ],
        ),
      ),
    );
  }
}

class MyRecordRow extends StatelessWidget {
  final EfficiencyRecord record;

  const MyRecordRow({
    super.key,
    required this.record,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = record.points >= 0;
    final dateFormat = DateFormat('dd.MM HH:mm');
    final categoryName = _getCategoryName(record.category);

    return Row(
      children: [
        Icon(
          _getCategoryIcon(record.category),
          size: 18,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                categoryName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (record.shopAddress.isNotEmpty)
                Text(
                  record.shopAddress,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              isPositive
                  ? '+${record.points.toStringAsFixed(1)}'
                  : record.points.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isPositive ? Colors.green[700] : Colors.red[700],
              ),
            ),
            Text(
              dateFormat.format(record.date),
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getCategoryName(EfficiencyCategory category) {
    switch (category) {
      case EfficiencyCategory.shift:
        return 'Пересменка';
      case EfficiencyCategory.recount:
        return 'Пересчёт';
      case EfficiencyCategory.shiftHandover:
        return 'Сдача смены';
      case EfficiencyCategory.attendance:
        return 'Посещаемость';
      case EfficiencyCategory.test:
        return 'Тестирование';
      case EfficiencyCategory.reviews:
        return 'Отзывы';
      case EfficiencyCategory.productSearch:
        return 'Поиск товара';
      case EfficiencyCategory.rko:
        return 'РКО';
      case EfficiencyCategory.orders:
        return 'Заказы';
      case EfficiencyCategory.shiftPenalty:
        return 'Штрафы смены';
      case EfficiencyCategory.tasks:
        return 'Задачи';
      default:
        return 'Неизвестно';
    }
  }

  IconData _getCategoryIcon(EfficiencyCategory category) {
    switch (category) {
      case EfficiencyCategory.shift:
        return Icons.assignment_turned_in;
      case EfficiencyCategory.recount:
        return Icons.inventory;
      case EfficiencyCategory.shiftHandover:
        return Icons.transfer_within_a_station;
      case EfficiencyCategory.attendance:
        return Icons.schedule;
      case EfficiencyCategory.test:
        return Icons.quiz;
      case EfficiencyCategory.reviews:
        return Icons.star;
      case EfficiencyCategory.productSearch:
        return Icons.search;
      case EfficiencyCategory.rko:
        return Icons.attach_money;
      case EfficiencyCategory.orders:
        return Icons.shopping_cart;
      case EfficiencyCategory.shiftPenalty:
        return Icons.warning;
      case EfficiencyCategory.tasks:
        return Icons.task;
      default:
        return Icons.help_outline;
    }
  }
}

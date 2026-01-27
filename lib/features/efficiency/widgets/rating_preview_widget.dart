import 'package:flutter/material.dart';

/// Виджет предпросмотра расчёта баллов для рейтинговых настроек
///
/// Показывает таблицу соответствия оценок и баллов.
/// Используется в settings pages для Type A (rating + time windows) и Type B (rating simple).
class RatingPreviewWidget extends StatelessWidget {
  /// Список оценок для отображения в таблице
  final List<int> previewRatings;

  /// Функция расчёта баллов по оценке
  final double Function(int rating) calculatePoints;

  /// Gradient colors для заголовка таблицы
  final List<Color> gradientColors;

  /// Заголовок первой колонки
  final String ratingColumnTitle;

  /// Заголовок второй колонки
  final String pointsColumnTitle;

  /// Форматирование оценки (например "5 / 10")
  final String Function(int rating)? ratingFormatter;

  const RatingPreviewWidget({
    super.key,
    required this.previewRatings,
    required this.calculatePoints,
    this.gradientColors = const [Color(0xFFf46b45), Color(0xFFeea849)],
    this.ratingColumnTitle = 'Оценка',
    this.pointsColumnTitle = 'Баллы',
    this.ratingFormatter,
  });

  String _formatRating(int rating) {
    if (ratingFormatter != null) {
      return ratingFormatter!(rating);
    }
    return '$rating / 10';
  }

  String _formatPoints(double points) {
    if (points >= 0) {
      return '+${points.toStringAsFixed(2)}';
    }
    return points.toStringAsFixed(2);
  }

  Color _getPointsColor(double points) {
    if (points < 0) return Colors.red;
    if (points > 0) return Colors.green;
    return Colors.grey;
  }

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ratingColumnTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      pointsColumnTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            // Rows
            ...previewRatings.asMap().entries.map((entry) {
              final index = entry.key;
              final rating = entry.value;
              final points = calculatePoints(rating);
              final color = _getPointsColor(points);
              final isLast = index == previewRatings.length - 1;

              return Container(
                decoration: BoxDecoration(
                  color: index.isEven ? Colors.grey[50] : Colors.white,
                  border: isLast
                      ? null
                      : Border(bottom: BorderSide(color: Colors.grey[200]!)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatRating(rating),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _formatPoints(points),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Виджет предпросмотра для бинарных настроек (положительный/отрицательный)
///
/// Показывает две строки: результат "да" и результат "нет".
/// Используется в Type C, D, E settings pages.
class BinaryPreviewWidget extends StatelessWidget {
  final String positiveLabel;
  final String negativeLabel;
  final double positivePoints;
  final double negativePoints;
  final List<Color> gradientColors;
  final String valueColumnTitle;
  final String pointsColumnTitle;

  /// Customizable icon and color for negative row
  final IconData negativeIcon;
  final Color? negativeIconColor;

  const BinaryPreviewWidget({
    super.key,
    required this.positiveLabel,
    required this.negativeLabel,
    required this.positivePoints,
    required this.negativePoints,
    this.gradientColors = const [Color(0xFFf46b45), Color(0xFFeea849)],
    this.valueColumnTitle = 'Результат',
    this.pointsColumnTitle = 'Баллы',
    this.negativeIcon = Icons.cancel,
    this.negativeIconColor,
  });

  String _formatPoints(double points) {
    if (points >= 0) {
      return '+${points.toStringAsFixed(1)}';
    }
    return points.toStringAsFixed(1);
  }

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      valueColumnTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      pointsColumnTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            // Positive row
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          positiveLabel,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _formatPoints(positivePoints),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Negative row
            Builder(
              builder: (context) {
                final negColor = negativeIconColor ?? Colors.red[700]!;
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(negativeIcon, color: negColor, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              negativeLabel,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: negColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                          decoration: BoxDecoration(
                            color: negColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _formatPoints(negativePoints),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: negColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

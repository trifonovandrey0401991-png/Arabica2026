import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import 'review_shop_selection_page.dart';

/// Страница выбора типа отзыва (положительный/отрицательный)
class ReviewTypeSelectionPage extends StatelessWidget {
  const ReviewTypeSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    Logger.debug('ReviewTypeSelectionPage.build() вызван');
    try {
      return Scaffold(
        backgroundColor: const Color(0xFF004D40),
        appBar: AppBar(
          title: const Text(
            'Оставить отзыв',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF004D40),
          elevation: 0,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF004D40),
                const Color(0xFF00695C),
                const Color(0xFF00796B),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  // Заголовок
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.rate_review,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Выберите тип отзыва',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ваше мнение важно для нас',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Кнопки выбора
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Положительный отзыв
                        _buildReviewTypeCard(
                          context: context,
                          title: 'Положительный отзыв',
                          subtitle: 'Нам понравилось!',
                          icon: Icons.thumb_up_rounded,
                          gradientColors: [
                            const Color(0xFF43A047),
                            const Color(0xFF66BB6A),
                          ],
                          shadowColor: Colors.green,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ReviewShopSelectionPage(
                                  reviewType: 'positive',
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        // Отрицательный отзыв
                        _buildReviewTypeCard(
                          context: context,
                          title: 'Отрицательный отзыв',
                          subtitle: 'Есть замечания',
                          icon: Icons.thumb_down_rounded,
                          gradientColors: [
                            const Color(0xFFE53935),
                            const Color(0xFFEF5350),
                          ],
                          shadowColor: Colors.red,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ReviewShopSelectionPage(
                                  reviewType: 'negative',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e, stackTrace) {
      Logger.error('Ошибка в ReviewTypeSelectionPage.build()', e, stackTrace);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ошибка'),
          backgroundColor: const Color(0xFF004D40),
        ),
        body: Center(
          child: Text('Ошибка: $e'),
        ),
      );
    }
  }

  Widget _buildReviewTypeCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required Color shadowColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                // Иконка
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    icon,
                    size: 42,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 20),
                // Текст
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                // Стрелка
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

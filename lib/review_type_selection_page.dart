import 'package:flutter/material.dart';
import 'review_shop_selection_page.dart';

/// Страница выбора типа отзыва (положительный/отрицательный)
class ReviewTypeSelectionPage extends StatelessWidget {
  const ReviewTypeSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    print('🔵 ReviewTypeSelectionPage.build() вызван');
    try {
      return Scaffold(
      appBar: AppBar(
        title: const Text('Оставить отзыв'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Выберите тип отзыва',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                // Положительный отзыв
                SizedBox(
                  width: double.infinity,
                  height: 120,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ReviewShopSelectionPage(
                            reviewType: 'positive',
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.withOpacity(0.9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.thumb_up,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Положительный отзыв',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Отрицательный отзыв
                SizedBox(
                  width: double.infinity,
                  height: 120,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ReviewShopSelectionPage(
                            reviewType: 'negative',
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.thumb_down,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Отрицательный отзыв',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    } catch (e, stackTrace) {
      print('❌ Ошибка в ReviewTypeSelectionPage.build(): $e');
      print('❌ Stack trace: $stackTrace');
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
}


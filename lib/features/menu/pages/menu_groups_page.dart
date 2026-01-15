import 'package:flutter/material.dart';
import 'menu_page.dart';

/// Страница категорий меню в стиле Arabica
/// Минималистичный дизайн с фирменными цветами бренда
class MenuGroupsPage extends StatelessWidget {
  final List<String> groups;
  final String? selectedShop;

  // Фирменные цвета Arabica
  static const Color arabicaTeal = Color(0xFF004D40);
  static const Color arabicaTealLight = Color(0xFF0D5C52);
  static const Color arabicaTealDark = Color(0xFF003D33);

  const MenuGroupsPage({
    super.key,
    required this.groups,
    this.selectedShop,
  });

  /// Получить иконку для категории в стиле Arabica
  static IconData getCategoryIcon(String category) {
    final lowerCategory = category.toLowerCase();

    // Кофейные напитки
    if (lowerCategory.contains('кофе') ||
        lowerCategory.contains('эспрессо') ||
        lowerCategory.contains('американо')) {
      return Icons.coffee;
    }
    if (lowerCategory.contains('латте') ||
        lowerCategory.contains('капучино') ||
        lowerCategory.contains('раф')) {
      return Icons.local_cafe;
    }

    // Холодные напитки
    if (lowerCategory.contains('холодн') ||
        lowerCategory.contains('айс') ||
        lowerCategory.contains('ice') ||
        lowerCategory.contains('фраппе')) {
      return Icons.ac_unit;
    }

    // Горячие напитки
    if (lowerCategory.contains('горяч')) {
      return Icons.whatshot;
    }

    // Чай
    if (lowerCategory.contains('чай')) {
      return Icons.emoji_food_beverage;
    }

    // Какао и шоколад
    if (lowerCategory.contains('какао') || lowerCategory.contains('шоколад')) {
      return Icons.local_drink;
    }

    // Молочные напитки
    if (lowerCategory.contains('молоч') || lowerCategory.contains('коктейл')) {
      return Icons.icecream;
    }

    // Смузи и соки
    if (lowerCategory.contains('смузи') ||
        lowerCategory.contains('фреш') ||
        lowerCategory.contains('сок')) {
      return Icons.blender;
    }

    // Лимонады
    if (lowerCategory.contains('лимонад') || lowerCategory.contains('морс')) {
      return Icons.local_bar;
    }

    // Десерты
    if (lowerCategory.contains('десерт') ||
        lowerCategory.contains('выпечк') ||
        lowerCategory.contains('торт') ||
        lowerCategory.contains('пирож')) {
      return Icons.cake;
    }

    // Еда
    if (lowerCategory.contains('завтрак') ||
        lowerCategory.contains('еда') ||
        lowerCategory.contains('сэндвич')) {
      return Icons.restaurant;
    }

    // Новинки и специальное
    if (lowerCategory.contains('авторск') ||
        lowerCategory.contains('сезонн') ||
        lowerCategory.contains('специал') ||
        lowerCategory.contains('новинк')) {
      return Icons.auto_awesome;
    }

    // По умолчанию - кофейное зерно (символ Arabica)
    return Icons.local_cafe;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Меню',
          style: TextStyle(
            fontWeight: FontWeight.w300,
            letterSpacing: 2,
          ),
        ),
        backgroundColor: arabicaTeal,
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: arabicaTeal,
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.15,
          ),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final category = groups[index];
            final icon = getCategoryIcon(category);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MenuPage(
                          selectedCategory: category,
                          selectedShop: selectedShop,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white.withOpacity(0.08),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Иконка слева с вертикальной линией
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              bottomLeft: Radius.circular(16),
                            ),
                            border: Border(
                              right: BorderSide(
                                color: Colors.white.withOpacity(0.15),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Icon(
                            icon,
                            size: 28,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        // Название категории
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              category,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w400,
                                color: Colors.white.withOpacity(0.95),
                                letterSpacing: 0.5,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        // Стрелка справа
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Icon(
                            Icons.chevron_right,
                            color: Colors.white.withOpacity(0.5),
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

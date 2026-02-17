import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'menu_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница категорий меню в минималистичном стиле
class MenuGroupsPage extends StatelessWidget {
  final List<String> groups;
  final String? selectedShop;

  const MenuGroupsPage({
    super.key,
    required this.groups,
    this.selectedShop,
  });

  /// Получить иконку для категории (outline версии)
  static IconData getCategoryIcon(String category) {
    final lowerCategory = category.toLowerCase();

    // Кофейные напитки
    if (lowerCategory.contains('кофе') ||
        lowerCategory.contains('эспрессо') ||
        lowerCategory.contains('американо')) {
      return Icons.coffee_outlined;
    }
    if (lowerCategory.contains('латте') ||
        lowerCategory.contains('капучино') ||
        lowerCategory.contains('раф')) {
      return Icons.local_cafe_outlined;
    }

    // Холодные напитки
    if (lowerCategory.contains('холодн') ||
        lowerCategory.contains('айс') ||
        lowerCategory.contains('ice') ||
        lowerCategory.contains('фраппе')) {
      return Icons.ac_unit_outlined;
    }

    // Горячие напитки
    if (lowerCategory.contains('горяч')) {
      return Icons.whatshot_outlined;
    }

    // Чай
    if (lowerCategory.contains('чай')) {
      return Icons.emoji_food_beverage_outlined;
    }

    // Какао и шоколад
    if (lowerCategory.contains('какао') || lowerCategory.contains('шоколад')) {
      return Icons.local_drink_outlined;
    }

    // Молочные напитки
    if (lowerCategory.contains('молоч') || lowerCategory.contains('коктейл')) {
      return Icons.icecream_outlined;
    }

    // Смузи и соки
    if (lowerCategory.contains('смузи') ||
        lowerCategory.contains('фреш') ||
        lowerCategory.contains('сок')) {
      return Icons.blender_outlined;
    }

    // Лимонады
    if (lowerCategory.contains('лимонад') || lowerCategory.contains('морс')) {
      return Icons.local_bar_outlined;
    }

    // Десерты
    if (lowerCategory.contains('десерт') ||
        lowerCategory.contains('выпечк') ||
        lowerCategory.contains('торт') ||
        lowerCategory.contains('пирож')) {
      return Icons.cake_outlined;
    }

    // Малина и ягоды
    if (lowerCategory.contains('малин') || lowerCategory.contains('ягод')) {
      return Icons.local_cafe_outlined;
    }

    // Еда
    if (lowerCategory.contains('завтрак') ||
        lowerCategory.contains('еда') ||
        lowerCategory.contains('сэндвич')) {
      return Icons.restaurant_outlined;
    }

    // Новинки и специальное
    if (lowerCategory.contains('авторск') ||
        lowerCategory.contains('сезонн') ||
        lowerCategory.contains('специал') ||
        lowerCategory.contains('новинк')) {
      return Icons.auto_awesome_outlined;
    }

    // По умолчанию
    return Icons.local_cafe_outlined;
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
              _buildAppBar(context),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final category = groups[index];
                    return _buildCategoryRow(context, category);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 24.w, 16.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'Меню',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(BuildContext context, String category) {
    final icon = getCategoryIcon(category);

    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
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
          borderRadius: BorderRadius.circular(16.r),
          splashColor: Colors.white.withOpacity(0.1),
          highlightColor: Colors.white.withOpacity(0.05),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                // Иконка
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10.r),
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white.withOpacity(0.85),
                    size: 22,
                  ),
                ),
                SizedBox(width: 14),

                // Название категории
                Expanded(
                  child: Text(
                    category,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Стрелка
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.4),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

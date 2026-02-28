import 'package:flutter/material.dart';
import '../../fortune_wheel/pages/wheel_settings_page.dart';
import 'settings_tabs/test_points_settings_page.dart';
import 'settings_tabs/attendance_points_settings_page.dart';
import 'settings_tabs/shift_points_settings_page.dart';
import 'settings_tabs/recount_efficiency_points_settings_page.dart';
import 'settings_tabs/rko_points_settings_page.dart';
import 'settings_tabs/shift_handover_points_settings_page.dart';
import 'settings_tabs/reviews_points_settings_page.dart';
import 'settings_tabs/product_search_points_settings_page.dart';
import 'settings_tabs/orders_points_settings_page.dart';
import 'settings_tabs/task_points_settings_page.dart';
import 'settings_tabs/envelope_points_settings_page.dart';
import 'settings_tabs/coffee_machine_points_settings_page.dart';
import 'settings_tabs/manager_points_settings_page.dart';
import '../../referrals/pages/referrals_points_settings_page.dart';
import '../../loyalty/pages/loyalty_gamification_settings_page.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Page for configuring efficiency points settings
class PointsSettingsPage extends StatefulWidget {
  const PointsSettingsPage({super.key});

  @override
  State<PointsSettingsPage> createState() => _PointsSettingsPageState();
}

class _PointsSettingsPageState extends State<PointsSettingsPage> {

  final bool _isLoading = false;

  // Categories with colors
  final List<_PointsCategory> _categories = [
    _PointsCategory(
      id: 'testing',
      title: 'Тестирование',
      icon: Icons.quiz_outlined,
      description: 'Баллы за прохождение тестов',
      gradientColors: [Color(0xFF667eea), Color(0xFF764ba2)],
    ),
    _PointsCategory(
      id: 'attendance',
      title: 'Я на работе',
      icon: Icons.access_time_outlined,
      description: 'Баллы за пунктуальность',
      gradientColors: [Color(0xFF11998e), Color(0xFF38ef7d)],
    ),
    _PointsCategory(
      id: 'shift',
      title: 'Пересменка',
      icon: Icons.swap_horiz_outlined,
      description: 'Баллы за оценку пересменки',
      gradientColors: [Color(0xFFf093fb), Color(0xFFf5576c)],
    ),
    _PointsCategory(
      id: 'recount',
      title: 'Пересчет',
      icon: Icons.inventory_2_outlined,
      description: 'Баллы за оценку пересчета',
      gradientColors: [Color(0xFF4facfe), Color(0xFF00f2fe)],
    ),
    _PointsCategory(
      id: 'rko',
      title: 'РКО',
      icon: Icons.receipt_long_outlined,
      description: 'Баллы за наличие РКО',
      gradientColors: [Color(0xFFfa709a), Color(0xFFfee140)],
    ),
    _PointsCategory(
      id: 'shift_handover',
      title: 'Сдать смену',
      icon: Icons.assignment_turned_in_outlined,
      description: 'Баллы за оценку сдачи смены',
      gradientColors: [Color(0xFF30cfd0), Color(0xFF330867)],
    ),
    _PointsCategory(
      id: 'reviews',
      title: 'Отзывы',
      icon: Icons.star_outline_rounded,
      description: 'Баллы за отзывы на магазин',
      gradientColors: [Color(0xFFf7971e), Color(0xFFffd200)],
    ),
    _PointsCategory(
      id: 'product_search',
      title: 'Поиск товара',
      icon: Icons.manage_search_outlined,
      description: 'Баллы за ответ на запрос товара',
      gradientColors: [Color(0xFF43e97b), Color(0xFF38f9d7)],
    ),
    _PointsCategory(
      id: 'orders',
      title: 'Заказы клиентов',
      icon: Icons.shopping_cart_outlined,
      description: 'Баллы за обработку заказов',
      gradientColors: [Color(0xFFff0844), Color(0xFFffb199)],
    ),
    _PointsCategory(
      id: 'tasks',
      title: 'Задачи',
      icon: Icons.task_alt_outlined,
      description: 'Баллы за выполнение задач',
      gradientColors: [Color(0xFF6a11cb), Color(0xFF2575fc)],
    ),
    _PointsCategory(
      id: 'envelope',
      title: 'Конверт',
      icon: Icons.mark_email_read_outlined,
      description: 'Баллы за сдачу конверта',
      gradientColors: [Color(0xFFee0979), Color(0xFFff6a00)],
    ),
    _PointsCategory(
      id: 'coffee_machine',
      title: 'Счётчик кофе',
      icon: Icons.coffee_outlined,
      description: 'Баллы за показания счётчика',
      gradientColors: [AppColors.gold, Color(0xFFF0C850)],
    ),
    _PointsCategory(
      id: 'referrals',
      title: 'Приглашения',
      icon: Icons.person_add_alt_outlined,
      description: 'Баллы за приглашенных клиентов',
      gradientColors: [Color(0xFF00897B), Color(0xFF26A69A)],
    ),
    _PointsCategory(
      id: 'managers',
      title: 'Управляющие',
      icon: Icons.supervisor_account_outlined,
      description: 'Баллы за оценку работы подчинённых',
      gradientColors: [Color(0xFF9C27B0), Color(0xFF673AB7)],
    ),
    _PointsCategory(
      id: 'loyalty_program',
      title: 'Программа лояльности',
      icon: Icons.loyalty_outlined,
      description: 'Уровни и колесо удачи для клиентов',
      gradientColors: [Color(0xFFFF6B6B), Color(0xFFFFE66D)],
    ),
    _PointsCategory(
      id: 'fortune_wheel',
      title: 'Колесо Удачи',
      icon: Icons.casino_outlined,
      description: 'Настройка секторов колеса',
      gradientColors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
    ),
  ];

  void _openCategorySettings(String categoryId) {
    if (categoryId == 'testing') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TestPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'attendance') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AttendancePointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'shift') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ShiftPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'recount') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RecountEfficiencyPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'rko') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RkoPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'shift_handover') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ShiftHandoverPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'reviews') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReviewsPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'product_search') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductSearchPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'orders') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OrdersPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'tasks') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TaskPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'envelope') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EnvelopePointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'coffee_machine') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CoffeeMachinePointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'referrals') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReferralsPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'managers') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ManagerPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'loyalty_program') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LoyaltyGamificationSettingsPage(),
        ),
      );
    } else if (categoryId == 'fortune_wheel') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WheelSettingsPage(),
        ),
      );
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
            colors: [AppColors.emeraldDark, AppColors.night],
          ),
        ),
        child: Column(
          children: [
            // Custom Row AppBar
            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(8.w, 12.h, 20.w, 0.h),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Установка баллов',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Header section
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.emerald.withOpacity(0.3),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28.r),
                  bottomRight: Radius.circular(28.r),
                ),
              ),
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: AppColors.gold.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.gold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(
                              color: AppColors.gold.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.stars_rounded,
                            color: AppColors.gold,
                            size: 20,
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Настройка баллов',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${_categories.length} категорий',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 11.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Category list
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                  : ListView.builder(
                      padding: EdgeInsets.all(16.w),
                      itemCount: _categories.length,
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        return _buildCategoryCard(category);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(_PointsCategory category) {
    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: AppColors.emerald.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12.r),
        child: InkWell(
          onTap: () => _openCategorySettings(category.id),
          borderRadius: BorderRadius.circular(12.r),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            child: Row(
              children: [
                // Icon with gradient
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: category.gradientColors,
                    ),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    category.icon,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                SizedBox(width: 10),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        category.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                // Arrow
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.gold.withOpacity(0.7),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PointsCategory {
  final String id;
  final String title;
  final IconData icon;
  final String description;
  final List<Color> gradientColors;

  _PointsCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.description,
    required this.gradientColors,
  });
}

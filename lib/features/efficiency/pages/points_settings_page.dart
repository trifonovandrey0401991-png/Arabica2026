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

/// Page for configuring efficiency points settings
class PointsSettingsPage extends StatefulWidget {
  const PointsSettingsPage({super.key});

  @override
  State<PointsSettingsPage> createState() => _PointsSettingsPageState();
}

class _PointsSettingsPageState extends State<PointsSettingsPage> {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  bool _isLoading = false;

  // Categories with colors
  final List<_PointsCategory> _categories = [
    _PointsCategory(
      id: 'testing',
      title: 'Тестирование',
      icon: Icons.quiz_outlined,
      description: 'Баллы за прохождение тестов',
      gradientColors: [const Color(0xFF667eea), const Color(0xFF764ba2)],
    ),
    _PointsCategory(
      id: 'attendance',
      title: 'Я на работе',
      icon: Icons.access_time_outlined,
      description: 'Баллы за пунктуальность',
      gradientColors: [const Color(0xFF11998e), const Color(0xFF38ef7d)],
    ),
    _PointsCategory(
      id: 'shift',
      title: 'Пересменка',
      icon: Icons.swap_horiz_outlined,
      description: 'Баллы за оценку пересменки',
      gradientColors: [const Color(0xFFf093fb), const Color(0xFFf5576c)],
    ),
    _PointsCategory(
      id: 'recount',
      title: 'Пересчет',
      icon: Icons.inventory_2_outlined,
      description: 'Баллы за оценку пересчета',
      gradientColors: [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
    ),
    _PointsCategory(
      id: 'rko',
      title: 'РКО',
      icon: Icons.receipt_long_outlined,
      description: 'Баллы за наличие РКО',
      gradientColors: [const Color(0xFFfa709a), const Color(0xFFfee140)],
    ),
    _PointsCategory(
      id: 'shift_handover',
      title: 'Сдать смену',
      icon: Icons.assignment_turned_in_outlined,
      description: 'Баллы за оценку сдачи смены',
      gradientColors: [const Color(0xFF30cfd0), const Color(0xFF330867)],
    ),
    _PointsCategory(
      id: 'reviews',
      title: 'Отзывы',
      icon: Icons.star_outline_rounded,
      description: 'Баллы за отзывы на магазин',
      gradientColors: [const Color(0xFFf7971e), const Color(0xFFffd200)],
    ),
    _PointsCategory(
      id: 'product_search',
      title: 'Поиск товара',
      icon: Icons.manage_search_outlined,
      description: 'Баллы за ответ на запрос товара',
      gradientColors: [const Color(0xFF43e97b), const Color(0xFF38f9d7)],
    ),
    _PointsCategory(
      id: 'orders',
      title: 'Заказы клиентов',
      icon: Icons.shopping_cart_outlined,
      description: 'Баллы за обработку заказов',
      gradientColors: [const Color(0xFFff0844), const Color(0xFFffb199)],
    ),
    _PointsCategory(
      id: 'tasks',
      title: 'Задачи',
      icon: Icons.task_alt_outlined,
      description: 'Баллы за выполнение задач',
      gradientColors: [const Color(0xFF6a11cb), const Color(0xFF2575fc)],
    ),
    _PointsCategory(
      id: 'envelope',
      title: 'Конверт',
      icon: Icons.mark_email_read_outlined,
      description: 'Баллы за сдачу конверта',
      gradientColors: [const Color(0xFFee0979), const Color(0xFFff6a00)],
    ),
    _PointsCategory(
      id: 'coffee_machine',
      title: 'Счётчик кофе',
      icon: Icons.coffee_outlined,
      description: 'Баллы за показания счётчика',
      gradientColors: [const Color(0xFFD4AF37), const Color(0xFFF0C850)],
    ),
    _PointsCategory(
      id: 'referrals',
      title: 'Приглашения',
      icon: Icons.person_add_alt_outlined,
      description: 'Баллы за приглашенных клиентов',
      gradientColors: [const Color(0xFF00897B), const Color(0xFF26A69A)],
    ),
    _PointsCategory(
      id: 'managers',
      title: 'Управляющие',
      icon: Icons.supervisor_account_outlined,
      description: 'Баллы за оценку работы подчинённых',
      gradientColors: [const Color(0xFF9C27B0), const Color(0xFF673AB7)],
    ),
    _PointsCategory(
      id: 'loyalty_program',
      title: 'Программа лояльности',
      icon: Icons.loyalty_outlined,
      description: 'Уровни и колесо удачи для клиентов',
      gradientColors: [const Color(0xFFFF6B6B), const Color(0xFFFFE66D)],
    ),
    _PointsCategory(
      id: 'fortune_wheel',
      title: 'Колесо Удачи',
      icon: Icons.casino_outlined,
      description: 'Настройка секторов колеса',
      gradientColors: [const Color(0xFF8E2DE2), const Color(0xFF4A00E0)],
    ),
  ];

  void _openCategorySettings(String categoryId) {
    if (categoryId == 'testing') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const TestPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'attendance') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const AttendancePointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'shift') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ShiftPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'recount') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const RecountEfficiencyPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'rko') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const RkoPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'shift_handover') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ShiftHandoverPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'reviews') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ReviewsPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'product_search') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ProductSearchPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'orders') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const OrdersPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'tasks') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const TaskPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'envelope') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const EnvelopePointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'coffee_machine') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const CoffeeMachinePointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'referrals') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ReferralsPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'managers') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ManagerPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'loyalty_program') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const LoyaltyGamificationSettingsPage(),
        ),
      );
    } else if (categoryId == 'fortune_wheel') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const WheelSettingsPage(),
        ),
      );
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
            colors: [_emeraldDark, _night],
          ),
        ),
        child: Column(
          children: [
            // Custom Row AppBar
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Установка баллов',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
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
                color: _emerald.withOpacity(0.3),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _emerald.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _gold.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _gold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _gold.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.stars_rounded,
                            color: _gold,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Настройка баллов',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${_categories.length} категорий',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 13,
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
                  ? const Center(child: CircularProgressIndicator(color: _gold))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _emeraldDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _emerald.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _openCategorySettings(category.id),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon with gradient
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: category.gradientColors,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    category.icon,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        category.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                // Arrow
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _emerald.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: _gold.withOpacity(0.7),
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

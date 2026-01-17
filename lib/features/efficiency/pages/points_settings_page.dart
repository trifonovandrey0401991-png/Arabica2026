import 'package:flutter/material.dart';
import '../../fortune_wheel/pages/wheel_settings_page.dart';
import 'settings_tabs/test_points_settings_page.dart';
import 'settings_tabs/attendance_points_settings_page.dart';
import 'settings_tabs/shift_points_settings_page.dart';
import 'settings_tabs/shift_points_settings_page_v2.dart';
import 'settings_tabs/recount_efficiency_points_settings_page.dart';
import 'settings_tabs/rko_points_settings_page.dart';
import 'settings_tabs/shift_handover_points_settings_page.dart';
import 'settings_tabs/reviews_points_settings_page.dart';
import 'settings_tabs/product_search_points_settings_page.dart';
import 'settings_tabs/orders_points_settings_page.dart';
import 'settings_tabs/task_points_settings_page.dart';
import 'settings_tabs/envelope_points_settings_page.dart';

/// Page for configuring efficiency points settings
class PointsSettingsPage extends StatefulWidget {
  const PointsSettingsPage({super.key});

  @override
  State<PointsSettingsPage> createState() => _PointsSettingsPageState();
}

class _PointsSettingsPageState extends State<PointsSettingsPage> {
  bool _isLoading = false;

  // Categories
  final List<_PointsCategory> _categories = [
    _PointsCategory(
      id: 'testing',
      title: 'Тестирование',
      icon: Icons.quiz,
      description: 'Баллы за прохождение тестов',
    ),
    _PointsCategory(
      id: 'attendance',
      title: 'Я на работе',
      icon: Icons.access_time,
      description: 'Баллы за пунктуальность',
    ),
    _PointsCategory(
      id: 'shift',
      title: 'Пересменка',
      icon: Icons.swap_horiz,
      description: 'Баллы за оценку пересменки',
    ),
    _PointsCategory(
      id: 'recount',
      title: 'Пересчет',
      icon: Icons.inventory,
      description: 'Баллы за оценку пересчета',
    ),
    _PointsCategory(
      id: 'rko',
      title: 'РКО',
      icon: Icons.receipt_long,
      description: 'Баллы за наличие РКО',
    ),
    _PointsCategory(
      id: 'shift_handover',
      title: 'Сдать смену',
      icon: Icons.assignment_turned_in,
      description: 'Баллы за оценку сдачи смены',
    ),
    _PointsCategory(
      id: 'reviews',
      title: 'Отзывы',
      icon: Icons.star_rate,
      description: 'Баллы за отзывы на магазин',
    ),
    _PointsCategory(
      id: 'product_search',
      title: 'Поиск товара',
      icon: Icons.search,
      description: 'Баллы за ответ на запрос товара',
    ),
    _PointsCategory(
      id: 'orders',
      title: 'Заказы клиентов',
      icon: Icons.shopping_cart,
      description: 'Баллы за обработку заказов',
    ),
    _PointsCategory(
      id: 'tasks',
      title: 'Задачи',
      icon: Icons.assignment,
      description: 'Баллы за выполнение задач',
    ),
    _PointsCategory(
      id: 'envelope',
      title: 'Конверт',
      icon: Icons.mail,
      description: 'Баллы за сдачу конверта',
    ),
    _PointsCategory(
      id: 'fortune_wheel',
      title: 'Колесо Удачи',
      icon: Icons.casino,
      description: 'Настройка секторов колеса',
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
          builder: (context) => const ShiftPointsSettingsPageV2(),
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
      appBar: AppBar(
        title: const Text('Установка баллов'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(
                      category.icon,
                      color: const Color(0xFF004D40),
                      size: 32,
                    ),
                    title: Text(
                      category.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(category.description),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openCategorySettings(category.id),
                  ),
                );
              },
            ),
    );
  }
}

class _PointsCategory {
  final String id;
  final String title;
  final IconData icon;
  final String description;

  _PointsCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.description,
  });
}

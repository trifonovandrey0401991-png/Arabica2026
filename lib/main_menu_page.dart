import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'menu_groups_page.dart';
import 'cart_page.dart';
import 'orders_page.dart';
import 'employees_page.dart';
import 'test_notifications_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'loyalty_page.dart';
import 'loyalty_scanner_page.dart';

class MainMenuPage extends StatefulWidget {
  const MainMenuPage({super.key});

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> {
  String? _userName;

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name');
    if (mounted) {
      setState(() {
        _userName = name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Арабика')),
      body: Column(
        children: [
          // Приветствие с именем
          if (_userName != null && _userName!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: Colors.teal[50],
                border: Border(
                  bottom: BorderSide(
                    color: Colors.teal[200]!,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.waving_hand,
                    color: Colors.teal[700],
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Привет, $_userName!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[900],
                    ),
                  ),
                ],
              ),
            ),
          // Сетка меню
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: GridView.count(
          crossAxisCount: 2,           // 2 кнопки в строке
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1,         // делает плитки квадратными
          children: [
            _tile(context, Icons.local_cafe, 'Меню', () async {
  // при нажатии сначала загружаем все напитки, чтобы получить список категорий
  final categories = await _loadCategories(context);
  if (!context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => MenuGroupsPage(groups: categories),
    ),
  );
}),

            _tile(context, Icons.shopping_cart, 'Корзина', () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CartPage(),
                ),
              );
            }),
            _tile(context, Icons.receipt_long, 'Мои заказы', () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const OrdersPage(),
                ),
              );
            }),
            _tile(context, Icons.people, 'Сотрудники', () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const EmployeesPage(),
                ),
              );
            }),
            _tile(context, Icons.qr_code, 'Карта лояльности', () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoyaltyPage(),
                ),
              );
            }),
            _tile(context, Icons.qr_code_scanner, 'Списать бонусы', () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoyaltyScannerPage(),
                ),
              );
            }),
            _tile(context, Icons.rate_review, 'Отзывы', () {}),
            _tile(context, Icons.search, 'Наличие товара', () {}),
            _tile(context, Icons.menu_book, 'Обучение', () {}),
            _tile(context, Icons.quiz, 'Тестирование', () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TestNotificationsPage(),
                ),
              );
            }),
            _tile(context, Icons.receipt_long, 'Отчёт о смене', () {}),
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }

  Widget _tile(
      BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: Colors.teal[700],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 4,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.white),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  Future<List<String>> _loadCategories(BuildContext context) async {
  try {
    // Пробуем загрузить из menu.json (более надежно)
    final jsonString = await rootBundle.loadString('assets/menu.json');
    final List<dynamic> jsonData = json.decode(jsonString);
    final Set<String> categories = {};
    
    for (var item in jsonData) {
      final category = (item['category'] ?? '').toString().trim();
      if (category.isNotEmpty) {
        categories.add(category);
      }
    }
    
    final categoriesList = categories.toList()..sort();
    // ignore: avoid_print
    print("📋 Загружено категорий из menu.json: ${categoriesList.length}");
    // ignore: avoid_print
    print("📋 Категории: $categoriesList");
    return categoriesList;
  } catch (e) {
    // Если не получилось загрузить из JSON, пробуем из Google Sheets
    // ignore: avoid_print
    print("⚠️ Ошибка загрузки из menu.json: $e, пробуем Google Sheets...");
    
    const sheetUrl =
        'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Меню';
    final response = await http.get(Uri.parse(sheetUrl));
    if (response.statusCode != 200) {
      throw Exception('Ошибка загрузки категорий');
    }
    final lines = const LineSplitter().convert(response.body);
    final Set<String> categories = {};
    for (var i = 1; i < lines.length; i++) {
      final row = lines[i].split(',');
      if (row.length >= 3) {
        // Убираем кавычки и лишние пробелы
        String category = row[2].trim().replaceAll('"', '').trim();
        if (category.isNotEmpty) {
          categories.add(category);
        }
      }
    }
    final categoriesList = categories.toList()..sort();
    // ignore: avoid_print
    print("📋 Загружено категорий из Google Sheets: ${categoriesList.length}");
    return categoriesList;
  }
}

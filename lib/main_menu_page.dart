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
import 'shop_model.dart';
import 'training_page.dart';
import 'test_page.dart';

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
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40), // Темно-бирюзовый фон
          // Если есть изображение фона, раскомментируйте следующие строки:
          // image: DecorationImage(
          //   image: AssetImage('assets/images/arabica_background.png'),
          //   fit: BoxFit.cover,
          //   opacity: 0.3,
          // ),
        ),
        child: Column(
          children: [
          // Приветствие с именем
          if (_userName != null && _userName!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.waving_hand,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Привет, $_userName!',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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
                    // Сначала показываем диалог выбора магазина
                    final shop = await _showShopSelectionDialog(context);
                    if (!context.mounted || shop == null) return;
                    
                    // После выбора магазина загружаем категории для этого магазина
                    final categories = await _loadCategoriesForShop(context, shop.address);
                    if (!context.mounted) return;
                    
                    // Открываем страницу категорий с выбранным магазином
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MenuGroupsPage(
                          groups: categories,
                          selectedShop: shop.address,
                        ),
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
                  _tile(context, Icons.menu_book, 'Обучение', () {
                    _showTrainingDialog(context);
                  }),
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
        backgroundColor: Colors.white.withOpacity(0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withOpacity(0.5),
            width: 1,
          ),
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

  /// Показать диалог выбора магазина
  Future<Shop?> _showShopSelectionDialog(BuildContext context) async {
    try {
      final shops = await Shop.loadShopsFromGoogleSheets();
      if (!context.mounted) return null;

      return await showDialog<Shop>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF004D40).withOpacity(0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
          ),
          title: const Text(
            'Выберите магазин',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: shops.length,
              itemBuilder: (context, index) {
                final shop = shops[index];
                return GestureDetector(
                  onTap: () => Navigator.pop(context, shop),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          shop.icon,
                          size: 40,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            shop.address,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    } catch (e) {
      print('Ошибка загрузки магазинов: $e');
      return null;
    }
  }

  /// Загрузить категории для конкретного магазина
  Future<List<String>> _loadCategoriesForShop(BuildContext context, String shopAddress) async {
    try {
      // Загружаем меню из menu.json
      final jsonString = await rootBundle.loadString('assets/menu.json');
      final List<dynamic> jsonData = json.decode(jsonString);
      
      // Фильтруем по магазину и получаем уникальные категории
      final categories = jsonData
          .map((e) => {
                'category': (e['category'] ?? '').toString(),
                'shop': (e['shop'] ?? '').toString(),
              })
          .where((item) => item['shop'] == shopAddress)
          .map((e) => e['category'] as String)
          .toSet()
          .toList()
        ..sort();
      
      return categories;
    } catch (e) {
      print('Ошибка загрузки категорий: $e');
      return [];
    }
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

  /// Показать диалог выбора: Обучение или Тест
  void _showTrainingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Обучение',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF004D40),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TrainingPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.menu_book),
                label: const Text('Обучение'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TestPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.quiz),
                label: const Text('Сдать тест'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

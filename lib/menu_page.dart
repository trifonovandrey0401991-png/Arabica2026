import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'cart_provider.dart';
import 'shop_model.dart';

class MenuItem {
  final String name;
  final String price;
  final String category;
  final String shop;
  final String photoId;

  MenuItem({
    required this.name,
    required this.price,
    required this.category,
    required this.shop,
    required this.photoId,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      name: (json['name'] ?? '').toString(),
      price: (json['price'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      shop: (json['shop'] ?? '').toString(),
      photoId: (json['photo_id'] ?? '').toString(),
    );
  }
}

class MenuPage extends StatefulWidget {
  final String? selectedCategory;

  const MenuPage({super.key, this.selectedCategory});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  late Future<List<MenuItem>> _menuFuture;
  late Future<List<Shop>> _shopsFuture;
  String _searchQuery = '';
  String? _selectedShop; // null означает, что магазин еще не выбран
  bool _shopDialogShown = false;

  @override
  void initState() {
    super.initState();
    _menuFuture = _loadMenu();
    _shopsFuture = Shop.loadShopsFromGoogleSheets();
    // Показываем диалог выбора магазина после загрузки меню и магазинов
    Future.wait([_menuFuture, _shopsFuture]).then((_) {
      if (mounted && _selectedShop == null && !_shopDialogShown) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _selectedShop == null) {
            _showShopSelectionDialog();
          }
        });
      }
    });
  }

  Future<List<MenuItem>> _loadMenu() async {
    try {
      // Пробуем загрузить из Google Sheets
      const sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Меню';
      
      final response = await http.get(Uri.parse(sheetUrl));
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки данных из Google Sheets: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      final List<MenuItem> menuItems = [];
      
      // Парсим CSV, пропускаем заголовок (первая строка)
      for (var i = 1; i < lines.length; i++) {
        final row = Shop.parseCsvLine(lines[i]);
        
        // Столбцы: A=0 (название), B=1 (цена), C=2 (категория), D=3 (адрес магазина)
        if (row.length >= 4) {
          String name = row[0].trim().replaceAll('"', '').trim();
          String price = row[1].trim().replaceAll('"', '').trim();
          String category = row[2].trim().replaceAll('"', '').trim();
          String shopAddress = row[3].trim().replaceAll('"', '').trim();
          
          // Пропускаем пустые строки и заголовки
          if (name.isNotEmpty && 
              name.toLowerCase() != 'название' &&
              name.toLowerCase() != 'название напитка' &&
              price.isNotEmpty &&
              category.isNotEmpty &&
              shopAddress.isNotEmpty) {
            
            // Генерируем photo_id из названия (можно улучшить, если есть столбец с фото)
            String photoId = _generatePhotoId(name);
            
            menuItems.add(MenuItem(
              name: name,
              price: price,
              category: category,
              shop: shopAddress, // Используем адрес магазина из столбца D
              photoId: photoId,
            ));
          }
        }
      }

      print('✅ Загружено напитков из Google Sheets: ${menuItems.length}');
      return menuItems;
    } catch (e) {
      print('⚠️ Ошибка загрузки меню из Google Sheets: $e');
      print('Пробуем загрузить из menu.json...');
      
      // Fallback на JSON файл
      try {
        final jsonString = await rootBundle.loadString('assets/menu.json');
        final List<dynamic> jsonData = json.decode(jsonString);
        final items = jsonData.map((e) => MenuItem.fromJson(e)).toList();
        print('✅ Загружено напитков из menu.json: ${items.length}');
        return items;
      } catch (jsonError) {
        print('❌ Ошибка загрузки из menu.json: $jsonError');
        return [];
      }
    }
  }

  /// Генерирует photo_id из названия напитка
  String _generatePhotoId(String name) {
    // Преобразуем название в нижний регистр, убираем спецсимволы
    String id = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    return id.isEmpty ? 'no_photo' : id;
  }

  String _normalizeCategory(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _matchCategory(MenuItem item) {
    final selected = widget.selectedCategory;
    if (selected == null || selected.trim().isEmpty) return true;

    final normalizedSelected = _normalizeCategory(selected);
    final normalizedItem = _normalizeCategory(item.category);

    if (normalizedSelected == normalizedItem) return true;

    final searchTokens = normalizedSelected.split(' ');
    return searchTokens.every((token) => normalizedItem.contains(token));
  }

  /// Показать диалог выбора магазина
  Future<void> _showShopSelectionDialog() async {
    if (_selectedShop != null) {
      return; // Магазин уже выбран
    }

    if (_shopDialogShown) {
      return; // Диалог уже показывался
    }

    _shopDialogShown = true;

    // Загружаем магазины из Google Sheets
    final shops = await _shopsFuture;

    if (!mounted) return;

    final selected = await showDialog<Shop>(
      context: context,
      barrierDismissible: false, // Нельзя закрыть без выбора
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Выберите магазин',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF004D40),
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF004D40),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
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
                        color: const Color(0xFF004D40),
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
                            color: Color(0xFF004D40),
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

    if (selected != null && mounted) {
      setState(() {
        _selectedShop = selected.name;
      });
    } else if (selected == null && mounted) {
      // Если магазин не выбран, возвращаемся назад
      Navigator.pop(context);
    }
  }

  Widget _buildDialog(MenuItem item, String imagePath) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Text(item.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              imagePath,
              height: 150,
              width: 150,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.asset(
                'assets/images/no_photo.png',
                height: 150,
                width: 150,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${item.price} ₽',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      actions: [
        ElevatedButton.icon(
          onPressed: () {
            // Добавляем товар в корзину
            final cart = CartProvider.of(context);
            cart.addItem(item);
            Navigator.pop(context);
            // Показываем уведомление
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${item.name} добавлен в корзину'),
                backgroundColor: const Color(0xFF004D40),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('Добавить в корзину'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF004D40),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    print("📌 Категория: ${widget.selectedCategory}");

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectedCategory ?? 'Меню напитков'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: FutureBuilder<List<MenuItem>>(
        future: _menuFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Загрузка меню...'),
                ],
              ),
            );
          }

          // Если магазин не выбран, показываем диалог и ждем выбора
          if (_selectedShop == null) {
            if (!_shopDialogShown) {
              Future.microtask(() {
                if (mounted && _selectedShop == null) {
                  _showShopSelectionDialog();
                }
              });
            }
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Выберите магазин...'),
                ],
              ),
            );
          }

          final all = snapshot.data!;
          final shops = <String>{'Все магазины', ...all.map((e) => e.shop)}.toList();

          final filtered = all.where((item) {
            final byName = item.name.toLowerCase().contains(_searchQuery.toLowerCase());
            final byShop = _selectedShop == 'Все магазины' || item.shop == _selectedShop;
            final byCategory = _matchCategory(item);
            return byName && byShop && byCategory;
          }).toList();

          final categories = filtered.map((e) => e.category).toSet().toList()
            ..sort();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Поиск напитка...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: ElevatedButton.icon(
                        onPressed: () => _showShopSelectionDialog(),
                        icon: const Icon(Icons.store, size: 20),
                        label: Text(
                          _selectedShop ?? 'Выберите магазин',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF004D40),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Найдено напитков: ${filtered.length}",
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              ),

              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text("Нет напитков 😕"))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: categories.length,
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          final itemsOfCategory =
                              filtered.where((e) => e.category == category).toList();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 14),
                              Text(
                                category,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF004D40),
                                ),
                              ),
                              const SizedBox(height: 8),

                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                  childAspectRatio: 0.72,
                                ),
                                itemCount: itemsOfCategory.length,
                                itemBuilder: (context, i) {
                                  final item = itemsOfCategory[i];
                                  final imagePath =
                                      'assets/images/${item.photoId}.jpg';

                                  return GestureDetector(
                                    onTap: () => showDialog(
                                      context: context,
                                      builder: (_) =>
                                          _buildDialog(item, imagePath),
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.08),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                top: Radius.circular(18),
                                              ),
                                              child: Image.asset(
                                                imagePath,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    Image.asset(
                                                  'assets/images/no_photo.png',
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(10),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.name,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  "${item.price} ₽",
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF00695C),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

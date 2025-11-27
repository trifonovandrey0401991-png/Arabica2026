import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'cart_provider.dart';

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
  final String? selectedShop;

  const MenuPage({
    super.key,
    this.selectedCategory,
    this.selectedShop,
  });

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  late Future<List<MenuItem>> _menuFuture;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _menuFuture = _loadMenu();
  }

  Future<List<MenuItem>> _loadMenu() async {
    final jsonString = await rootBundle.loadString('assets/menu.json');
    final List<dynamic> jsonData = json.decode(jsonString);
    return jsonData.map((e) => MenuItem.fromJson(e)).toList();
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

          final all = snapshot.data!;

          // Фильтруем по выбранному магазину и категории
          final filtered = all.where((item) {
            final byName = item.name.toLowerCase().contains(_searchQuery.toLowerCase());
            final byShop = widget.selectedShop == null || item.shop == widget.selectedShop;
            final byCategory = widget.selectedCategory == null || _matchCategory(item);
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

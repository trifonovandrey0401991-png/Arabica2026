import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

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
  String _searchQuery = '';
  String? _selectedShop; // null означает, что магазин еще не выбран
  bool _shopSelected = false;
  bool _dialogShown = false; // Флаг, что диалог уже показывался

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

  Future<void> _showShopSelectionDialog() async {
    if (_selectedShop != null) {
      print('⚠️ Магазин уже выбран, пропускаем диалог');
      return; // Уже выбран магазин
    }
    
    print('🔍 Показываем диалог выбора магазина');
    
    try {
      final menuData = await _menuFuture;
      final shops = <String>{'Все магазины', ...menuData.map((e) => e.shop)}.toList()
        ..sort((a, b) {
          if (a == 'Все магазины') return -1;
          if (b == 'Все магазины') return 1;
          return a.compareTo(b);
        });

      if (!mounted) {
        print('⚠️ Виджет не mounted, пропускаем диалог');
        return;
      }
      
      print('✅ Список магазинов: ${shops.length}');
    
    final selected = await showDialog<String>(
      context: context,
      barrierDismissible: false, // Нельзя закрыть без выбора
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Выберите магазин',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: shops.length,
            itemBuilder: (context, index) {
              final shop = shops[index];
              return ListTile(
                leading: Icon(
                  shop == 'Все магазины' 
                    ? Icons.store_mall_directory 
                    : Icons.store,
                  color: const Color(0xFF004D40),
                ),
                title: Text(
                  shop,
                  style: const TextStyle(fontSize: 16),
                ),
                onTap: () => Navigator.pop(context, shop),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                tileColor: Colors.grey[50],
              );
            },
          ),
        ),
      ),
    );

      if (selected != null && mounted) {
        print('✅ Выбран магазин: $selected');
        setState(() {
          _selectedShop = selected;
          _shopSelected = true;
        });
      } else if (selected == null && mounted) {
        // Если магазин не выбран, возвращаемся назад
        print('⚠️ Магазин не выбран, возвращаемся назад');
        setState(() {
          _dialogShown = false; // Сбрасываем флаг, чтобы можно было попробовать снова
        });
        Navigator.pop(context);
      }
    } catch (e) {
      print('❌ Ошибка при показе диалога: $e');
      if (mounted) {
        setState(() {
          _dialogShown = false; // Сбрасываем флаг при ошибке
        });
      }
    }
  }

  Widget _buildItemDialog(MenuItem item, String imagePath) {
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
          onPressed: () => Navigator.pop(context),
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
    print("🔍 Состояние: _selectedShop=$_selectedShop, _dialogShown=$_dialogShown, _shopSelected=$_shopSelected");

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
            print("⚠️ Магазин не выбран, проверяем диалог. _dialogShown=$_dialogShown");
            // Показываем диалог только один раз
            if (!_dialogShown) {
              print("✅ Показываем диалог через Future.microtask");
              _dialogShown = true;
              // Используем Future.microtask для показа диалога после build
              Future.microtask(() {
                print("🔄 Future.microtask выполнен, mounted=$mounted, _selectedShop=$_selectedShop");
                if (mounted && _selectedShop == null) {
                  print("🚀 Вызываем _showShopSelectionDialog()");
                  _showShopSelectionDialog();
                } else {
                  print("❌ Не вызываем диалог: mounted=$mounted, _selectedShop=$_selectedShop");
                }
              });
            } else {
              print("⚠️ Диалог уже показывался, пропускаем");
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

          // Удаляем дубликаты по имени напитка (оставляем первое вхождение)
          final seenNames = <String>{};
          final uniqueFiltered = filtered.where((item) {
            final normalizedName = item.name.trim().toLowerCase();
            if (seenNames.contains(normalizedName)) {
              return false;
            }
            seenNames.add(normalizedName);
            return true;
          }).toList();

          final categories = uniqueFiltered.map((e) => e.category).toSet().toList()
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
                    "Найдено напитков: ${uniqueFiltered.length}",
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              ),

              Expanded(
                child: uniqueFiltered.isEmpty
                    ? const Center(child: Text("Нет напитков 😕"))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: categories.length,
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          final itemsOfCategory =
                              uniqueFiltered.where((e) => e.category == category).toList();

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
                                          _buildItemDialog(item, imagePath),
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

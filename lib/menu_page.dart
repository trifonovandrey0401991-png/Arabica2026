import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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
  String? _selectedCategory; // null означает, что категория еще не выбрана
  bool _shopDialogShown = false;
  bool _categoryDialogShown = false;

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
        _selectedCategory = null; // Сбрасываем категорию при смене магазина
      });
      // После выбора магазина показываем диалог выбора категории
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _showCategorySelectionDialog();
        }
      });
    } else if (selected == null && mounted) {
      // Если магазин не выбран, возвращаемся назад
      Navigator.pop(context);
    }
  }

  /// Показать диалог выбора категории
  Future<void> _showCategorySelectionDialog() async {
    if (_selectedShop == null) {
      return; // Магазин должен быть выбран сначала
    }

    if (_categoryDialogShown && _selectedCategory != null) {
      return; // Категория уже выбрана
    }

    _categoryDialogShown = true;

    // Получаем список категорий для выбранного магазина
    final menuItems = await _menuFuture;
    final categories = menuItems
        .where((item) => item.shop == _selectedShop)
        .map((e) => e.category)
        .toSet()
        .toList()
      ..sort();

    if (!mounted || categories.isEmpty) return;

    final selected = await showDialog<String>(
      context: context,
      barrierDismissible: false, // Нельзя закрыть без выбора
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Выберите категорию',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF004D40),
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  title: Text(
                    category,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF004D40),
                    ),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Color(0xFF004D40),
                  ),
                  onTap: () => Navigator.pop(context, category),
                ),
              );
            },
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedCategory = selected;
      });
    } else if (selected == null && mounted) {
      // Если категория не выбрана, возвращаемся к выбору магазина
      setState(() {
        _selectedShop = null;
        _categoryDialogShown = false;
      });
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _showShopSelectionDialog();
        }
      });
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
        title: Text(_selectedCategory ?? 'Меню напитков'),
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

          // Если категория не выбрана, показываем диалог выбора категории
          if (_selectedCategory == null) {
            if (!_categoryDialogShown) {
              Future.microtask(() {
                if (mounted && _selectedCategory == null && _selectedShop != null) {
                  _showCategorySelectionDialog();
                }
              });
            }
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Выберите категорию...'),
                ],
              ),
            );
          }

          final all = snapshot.data!;
          final shops = <String>{'Все магазины', ...all.map((e) => e.shop)}.toList();

          final filtered = all.where((item) {
            final byName = item.name.toLowerCase().contains(_searchQuery.toLowerCase());
            final byShop = item.shop == _selectedShop;
            final byCategory = _selectedCategory != null && item.category == _selectedCategory;
            return byName && byShop && byCategory;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
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
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedShop = null;
                                _selectedCategory = null;
                                _shopDialogShown = false;
                                _categoryDialogShown = false;
                              });
                              _showShopSelectionDialog();
                            },
                            icon: const Icon(Icons.store, size: 18),
                            label: Text(
                              _selectedShop ?? 'Выберите магазин',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF004D40),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedCategory = null;
                                _categoryDialogShown = false;
                              });
                              _showCategorySelectionDialog();
                            },
                            icon: const Icon(Icons.category, size: 18),
                            label: Text(
                              _selectedCategory ?? 'Выберите категорию',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00695C),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                      ],
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
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final item = filtered[i];
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
              ),
            ],
          );
        },
      ),
    );
  }
}

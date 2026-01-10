import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../orders/pages/cart_page.dart';
import '../../recipes/models/recipe_model.dart';

class MenuItem {
  final String id;
  final String name;
  final String price;
  final String category;
  final String shop;
  final String photoId;
  final String? photoUrl; // URL фото с сервера

  MenuItem({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    required this.shop,
    required this.photoId,
    this.photoUrl,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] ?? '',
      name: (json['name'] ?? '').toString(),
      price: (json['price'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      shop: (json['shop'] ?? '').toString(),
      photoId: (json['photo_id'] ?? '').toString(),
      photoUrl: json['photoUrl'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'category': category,
      'shop': shop,
      'photo_id': photoId,
      'photoUrl': photoUrl,
    };
  }

  /// Получить URL фото для отображения
  String? get imageUrl {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      if (photoUrl!.startsWith('http')) {
        return photoUrl;
      }
      return 'https://arabica26.ru$photoUrl';
    }
    return null;
  }

  /// Проверить, есть ли URL фото
  bool get hasNetworkPhoto => imageUrl != null;
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
    try {
      // Загружаем напитки из рецептов - в меню показываем только позиции с рецептами
      final recipes = await Recipe.loadRecipesFromServer();

      // Преобразуем рецепты в MenuItem
      return recipes.map((recipe) => MenuItem(
        id: recipe.id,
        name: recipe.name,
        price: recipe.price ?? '',
        category: recipe.category,
        shop: '', // Магазин не привязан к рецепту
        photoId: recipe.photoId ?? '',
        photoUrl: recipe.photoUrl,
      )).toList();
    } catch (e) {
      Logger.warning('Ошибка загрузки рецептов: $e');
      return [];
    }
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

  /// Строит виджет изображения для MenuItem
  Widget _buildItemImage(MenuItem item, {double? height, double? width, BoxFit fit = BoxFit.cover}) {
    if (item.hasNetworkPhoto) {
      return Image.network(
        item.imageUrl!,
        height: height,
        width: width,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return SizedBox(
            height: height,
            width: width,
            child: const Center(child: CircularProgressIndicator()),
          );
        },
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/images/no_photo.png',
          height: height,
          width: width,
          fit: fit,
        ),
      );
    } else {
      final imagePath = 'assets/images/${item.photoId}.jpg';
      return Image.asset(
        imagePath,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/images/no_photo.png',
          height: height,
          width: width,
          fit: fit,
        ),
      );
    }
  }

  Widget _buildDialog(MenuItem item) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Text(item.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _buildItemImage(item, height: 150, width: 150),
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
            // Сохраняем адрес магазина для заказа
            if (widget.selectedShop != null && widget.selectedShop!.isNotEmpty) {
              cart.setShopAddress(widget.selectedShop);
            }
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
    Logger.debug('Категория: ${widget.selectedCategory}');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectedCategory ?? 'Меню напитков'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40), // Темно-бирюзовый фон (fallback)
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6, // Прозрачность фона для хорошей видимости логотипа
          ),
        ),
        child: FutureBuilder<List<MenuItem>>(
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

          // Фильтруем по категории (магазин не учитываем - рецепты общие для всех)
          final filtered = all.where((item) {
            final byName = item.name.toLowerCase().contains(_searchQuery.toLowerCase());
            final byCategory = widget.selectedCategory == null || _matchCategory(item);
            return byName && byCategory;
          }).toList();

          final categories = filtered.map((e) => e.category).toSet().toList()
            ..sort();

          return ListenableBuilder(
            listenable: CartProvider.of(context),
            builder: (context, _) {
              final cart = CartProvider.of(context);
              final hasItems = !cart.isEmpty;

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
                            padding: EdgeInsets.only(
                              left: 8,
                              right: 8,
                              top: 8,
                              bottom: hasItems ? 80 : 8, // Отступ снизу для кнопки
                            ),
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

                                      return GestureDetector(
                                        onTap: () => showDialog(
                                          context: context,
                                          builder: (_) => _buildDialog(item),
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
                                                  child: _buildItemImage(item),
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

                  // Кнопка "К заказу" внизу экрана
                  if (hasItems)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CartPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.shopping_cart, size: 24),
                            label: Text(
                              'К заказу (${cart.itemCount})',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF004D40),
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 24,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
        ),
    );
  }
}

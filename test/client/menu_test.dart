import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P2 Тесты меню для роли КЛИЕНТ
/// Покрывает: Категории, товары, фильтрация, поиск
void main() {
  group('Menu Tests (P2)', () {
    late MockMenuService mockMenuService;

    setUp(() async {
      mockMenuService = MockMenuService();
    });

    tearDown(() async {
      mockMenuService.clear();
    });

    // ==================== КАТЕГОРИИ ====================

    group('Categories Tests', () {
      test('CT-MNU-001: Получение списка категорий', () async {
        // Act
        final categories = await mockMenuService.getCategories();

        // Assert
        expect(categories, isA<List>());
        expect(categories.length, greaterThan(0));
      });

      test('CT-MNU-002: Категория содержит id и name', () async {
        // Act
        final categories = await mockMenuService.getCategories();

        // Assert
        for (final category in categories) {
          expect(category['id'], isNotNull);
          expect(category['name'], isNotNull);
        }
      });

      test('CT-MNU-003: Категории отсортированы по порядку', () async {
        // Act
        final categories = await mockMenuService.getCategories();

        // Assert
        for (var i = 0; i < categories.length - 1; i++) {
          expect(
            categories[i]['order'] <= categories[i + 1]['order'],
            true,
          );
        }
      });
    });

    // ==================== ТОВАРЫ ====================

    group('Products Tests', () {
      test('CT-MNU-004: Получение товаров по категории', () async {
        // Arrange
        final categoryId = 'coffee';

        // Act
        final products = await mockMenuService.getProductsByCategory(categoryId);

        // Assert
        expect(products, isA<List>());
        for (final product in products) {
          expect(product['category'], categoryId);
        }
      });

      test('CT-MNU-005: Товар содержит все обязательные поля', () async {
        // Act
        final products = await mockMenuService.getAllProducts();

        // Assert
        for (final product in products) {
          expect(product['id'], isNotNull);
          expect(product['name'], isNotNull);
          expect(product['price'], isNotNull);
          expect(product['category'], isNotNull);
        }
      });

      test('CT-MNU-006: Товар может содержать описание', () async {
        // Act
        final products = await mockMenuService.getAllProducts();
        final withDescription = products.where((p) => p['description'] != null);

        // Assert
        expect(withDescription.isNotEmpty, true);
      });

      test('CT-MNU-007: Товар может содержать изображение', () async {
        // Act
        final products = await mockMenuService.getAllProducts();

        // Assert
        for (final product in products) {
          // imageUrl is optional but should be valid if present
          if (product['imageUrl'] != null) {
            expect(product['imageUrl'], isA<String>());
          }
        }
      });

      test('CT-MNU-008: Фильтрация только доступных товаров', () async {
        // Act
        final available = await mockMenuService.getAvailableProducts();

        // Assert
        for (final product in available) {
          expect(product['available'], true);
        }
      });

      test('CT-MNU-009: Скрытие недоступных товаров', () async {
        // Arrange
        mockMenuService.addProduct({
          'id': 'unavailable_001',
          'name': 'Недоступный товар',
          'price': 100,
          'category': 'coffee',
          'available': false,
        });

        // Act
        final available = await mockMenuService.getAvailableProducts();

        // Assert
        expect(available.any((p) => p['id'] == 'unavailable_001'), false);
      });
    });

    // ==================== ПОИСК ====================

    group('Search Tests', () {
      test('CT-MNU-010: Поиск товаров по названию', () async {
        // Arrange
        final query = 'Капучино';

        // Act
        final results = await mockMenuService.searchProducts(query);

        // Assert
        expect(results.every((p) =>
          p['name'].toString().toLowerCase().contains(query.toLowerCase())
        ), true);
      });

      test('CT-MNU-011: Поиск регистронезависимый', () async {
        // Arrange
        final query = 'капучино';

        // Act
        final results = await mockMenuService.searchProducts(query);

        // Assert
        expect(results.isNotEmpty, true);
      });

      test('CT-MNU-012: Пустой поиск возвращает все товары', () async {
        // Act
        final results = await mockMenuService.searchProducts('');
        final all = await mockMenuService.getAllProducts();

        // Assert
        expect(results.length, all.length);
      });

      test('CT-MNU-013: Поиск несуществующего товара', () async {
        // Arrange
        final query = 'НесуществующийТовар12345';

        // Act
        final results = await mockMenuService.searchProducts(query);

        // Assert
        expect(results.isEmpty, true);
      });
    });

    // ==================== ЦЕНЫ ====================

    group('Price Tests', () {
      test('CT-MNU-014: Цена товара положительная', () async {
        // Act
        final products = await mockMenuService.getAllProducts();

        // Assert
        for (final product in products) {
          expect(product['price'], greaterThan(0));
        }
      });

      test('CT-MNU-015: Форматирование цены с рублями', () async {
        // Arrange
        final price = 250.0;

        // Act
        final formatted = mockMenuService.formatPrice(price);

        // Assert
        expect(formatted, '250 ₽');
      });

      test('CT-MNU-016: Отображение старой цены при скидке', () async {
        // Arrange
        mockMenuService.addProduct({
          'id': 'discounted_001',
          'name': 'Товар со скидкой',
          'price': 200,
          'oldPrice': 250,
          'category': 'coffee',
          'available': true,
        });

        // Act
        final products = await mockMenuService.getAllProducts();
        final discounted = products.firstWhere((p) => p['id'] == 'discounted_001');

        // Assert
        expect(discounted['oldPrice'], greaterThan(discounted['price']));
      });
    });

    // ==================== ИЗБРАННОЕ ====================

    group('Favorites Tests', () {
      test('CT-MNU-017: Добавление товара в избранное', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];
        final productId = 'prod_001';

        // Act
        final result = await mockMenuService.addToFavorites(clientPhone, productId);

        // Assert
        expect(result['success'], true);
      });

      test('CT-MNU-018: Удаление товара из избранного', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];
        final productId = 'prod_001';
        await mockMenuService.addToFavorites(clientPhone, productId);

        // Act
        final result = await mockMenuService.removeFromFavorites(clientPhone, productId);

        // Assert
        expect(result['success'], true);
      });

      test('CT-MNU-019: Получение списка избранного', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];
        await mockMenuService.addToFavorites(clientPhone, 'prod_001');
        await mockMenuService.addToFavorites(clientPhone, 'prod_002');

        // Act
        final favorites = await mockMenuService.getFavorites(clientPhone);

        // Assert
        expect(favorites.length, 2);
      });

      test('CT-MNU-020: Проверка наличия товара в избранном', () async {
        // Arrange
        final clientPhone = MockClientData.validClient['phone'];
        await mockMenuService.addToFavorites(clientPhone, 'prod_001');

        // Act
        final isFavorite = await mockMenuService.isFavorite(clientPhone, 'prod_001');

        // Assert
        expect(isFavorite, true);
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockMenuService {
  final List<Map<String, dynamic>> _products = [
    {
      'id': 'prod_001',
      'name': 'Капучино',
      'price': 250,
      'category': 'coffee',
      'available': true,
      'description': 'Классический капучино',
    },
    {
      'id': 'prod_002',
      'name': 'Латте',
      'price': 350,
      'category': 'coffee',
      'available': true,
    },
    {
      'id': 'prod_003',
      'name': 'Американо',
      'price': 200,
      'category': 'coffee',
      'available': true,
    },
    {
      'id': 'prod_004',
      'name': 'Чизкейк',
      'price': 300,
      'category': 'dessert',
      'available': true,
    },
  ];

  final List<Map<String, dynamic>> _categories = [
    {'id': 'coffee', 'name': 'Кофе', 'order': 1},
    {'id': 'tea', 'name': 'Чай', 'order': 2},
    {'id': 'dessert', 'name': 'Десерты', 'order': 3},
    {'id': 'snacks', 'name': 'Снеки', 'order': 4},
  ];

  final Map<String, List<String>> _favorites = {};

  Future<List<Map<String, dynamic>>> getCategories() async {
    return _categories..sort((a, b) => a['order'].compareTo(b['order']));
  }

  Future<List<Map<String, dynamic>>> getAllProducts() async {
    return _products;
  }

  Future<List<Map<String, dynamic>>> getAvailableProducts() async {
    return _products.where((p) => p['available'] == true).toList();
  }

  Future<List<Map<String, dynamic>>> getProductsByCategory(String categoryId) async {
    return _products.where((p) => p['category'] == categoryId).toList();
  }

  Future<List<Map<String, dynamic>>> searchProducts(String query) async {
    if (query.isEmpty) return _products;
    return _products.where((p) =>
      p['name'].toString().toLowerCase().contains(query.toLowerCase())
    ).toList();
  }

  String formatPrice(double price) {
    return '${price.toInt()} ₽';
  }

  void addProduct(Map<String, dynamic> product) {
    _products.add(product);
  }

  Future<Map<String, dynamic>> addToFavorites(String clientPhone, String productId) async {
    _favorites.putIfAbsent(clientPhone, () => []);
    if (!_favorites[clientPhone]!.contains(productId)) {
      _favorites[clientPhone]!.add(productId);
    }
    return {'success': true};
  }

  Future<Map<String, dynamic>> removeFromFavorites(String clientPhone, String productId) async {
    _favorites[clientPhone]?.remove(productId);
    return {'success': true};
  }

  Future<List<String>> getFavorites(String clientPhone) async {
    return _favorites[clientPhone] ?? [];
  }

  Future<bool> isFavorite(String clientPhone, String productId) async {
    return _favorites[clientPhone]?.contains(productId) ?? false;
  }

  void clear() {
    _products.clear();
    _favorites.clear();
  }
}

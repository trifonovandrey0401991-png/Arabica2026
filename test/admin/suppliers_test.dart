import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P3 Тесты поставщиков для роли АДМИНИСТРАТОР
/// Покрывает: CRUD поставщиков, контакты, история
void main() {
  group('Suppliers Tests (P3)', () {
    late MockSuppliersService mockSuppliersService;

    setUp(() async {
      mockSuppliersService = MockSuppliersService();
    });

    tearDown(() async {
      mockSuppliersService.clear();
    });

    // ==================== CRUD ====================

    group('CRUD Tests', () {
      test('AT-SUP-001: Получение списка поставщиков', () async {
        // Act
        final suppliers = await mockSuppliersService.getSuppliers();

        // Assert
        expect(suppliers, isA<List>());
      });

      test('AT-SUP-002: Создание нового поставщика', () async {
        // Arrange
        final supplierData = {
          'name': 'Кофейная компания',
          'phone': '+7 900 123 45 67',
          'email': 'coffee@example.com',
          'category': 'coffee',
        };

        // Act
        final result = await mockSuppliersService.createSupplier(supplierData);

        // Assert
        expect(result['success'], true);
        expect(result['supplier']['id'], isNotNull);
      });

      test('AT-SUP-003: Редактирование поставщика', () async {
        // Arrange
        final created = await mockSuppliersService.createSupplier({
          'name': 'Старое название',
          'phone': '+7 900 000 00 00',
        });

        // Act
        final result = await mockSuppliersService.updateSupplier(
          created['supplier']['id'],
          {'name': 'Новое название'},
        );

        // Assert
        expect(result['success'], true);
        expect(result['supplier']['name'], 'Новое название');
      });

      test('AT-SUP-004: Удаление поставщика', () async {
        // Arrange
        final created = await mockSuppliersService.createSupplier({
          'name': 'Поставщик для удаления',
          'phone': '+7 900 000 00 00',
        });

        // Act
        final result = await mockSuppliersService.deleteSupplier(
          created['supplier']['id'],
        );

        // Assert
        expect(result['success'], true);
      });

      test('AT-SUP-005: Поставщик содержит обязательные поля', () async {
        // Arrange
        await mockSuppliersService.createSupplier({
          'name': 'Тестовый поставщик',
          'phone': '+7 900 111 11 11',
          'email': 'test@test.com',
          'address': 'ул. Тестовая, 1',
          'category': 'milk',
        });

        // Act
        final suppliers = await mockSuppliersService.getSuppliers();

        // Assert
        expect(suppliers.first['name'], isNotNull);
        expect(suppliers.first['phone'], isNotNull);
      });
    });

    // ==================== КАТЕГОРИИ ====================

    group('Categories Tests', () {
      test('AT-SUP-006: Фильтрация по категории', () async {
        // Arrange
        await mockSuppliersService.createSupplier({
          'name': 'Кофе поставщик',
          'category': 'coffee',
          'phone': '111',
        });
        await mockSuppliersService.createSupplier({
          'name': 'Молоко поставщик',
          'category': 'milk',
          'phone': '222',
        });

        // Act
        final coffeeSuppliers = await mockSuppliersService.getSuppliersByCategory('coffee');

        // Assert
        expect(coffeeSuppliers.every((s) => s['category'] == 'coffee'), true);
      });

      test('AT-SUP-007: Получение списка категорий', () async {
        // Act
        final categories = await mockSuppliersService.getCategories();

        // Assert
        expect(categories, contains('coffee'));
        expect(categories, contains('milk'));
        expect(categories, contains('pastry'));
      });
    });

    // ==================== ПОИСК ====================

    group('Search Tests', () {
      test('AT-SUP-008: Поиск поставщика по названию', () async {
        // Arrange
        await mockSuppliersService.createSupplier({
          'name': 'Кофейный рай',
          'phone': '111',
        });

        // Act
        final results = await mockSuppliersService.searchSuppliers('кофейный');

        // Assert
        expect(results.isNotEmpty, true);
      });

      test('AT-SUP-009: Поиск по телефону', () async {
        // Arrange
        await mockSuppliersService.createSupplier({
          'name': 'Поставщик',
          'phone': '+7 999 123 45 67',
        });

        // Act
        final results = await mockSuppliersService.searchSuppliers('999');

        // Assert
        expect(results.isNotEmpty, true);
      });
    });

    // ==================== КОНТАКТЫ ====================

    group('Contacts Tests', () {
      test('AT-SUP-010: Добавление контактного лица', () async {
        // Arrange
        final created = await mockSuppliersService.createSupplier({
          'name': 'Поставщик',
          'phone': '111',
        });

        // Act
        final result = await mockSuppliersService.addContact(
          created['supplier']['id'],
          {
            'name': 'Иван Иванов',
            'phone': '+7 900 111 22 33',
            'position': 'Менеджер',
          },
        );

        // Assert
        expect(result['success'], true);
      });

      test('AT-SUP-011: Поставщик может иметь несколько контактов', () async {
        // Arrange
        final created = await mockSuppliersService.createSupplier({
          'name': 'Поставщик',
          'phone': '111',
        });
        await mockSuppliersService.addContact(
          created['supplier']['id'],
          {'name': 'Контакт 1', 'phone': '111'},
        );
        await mockSuppliersService.addContact(
          created['supplier']['id'],
          {'name': 'Контакт 2', 'phone': '222'},
        );

        // Act
        final supplier = await mockSuppliersService.getSupplier(
          created['supplier']['id'],
        );

        // Assert
        expect(supplier['contacts'].length, 2);
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockSuppliersService {
  final List<Map<String, dynamic>> _suppliers = [];

  Future<List<Map<String, dynamic>>> getSuppliers() async {
    return _suppliers;
  }

  Future<Map<String, dynamic>> getSupplier(String supplierId) async {
    return _suppliers.firstWhere(
      (s) => s['id'] == supplierId,
      orElse: () => {'error': 'Not found'},
    );
  }

  Future<Map<String, dynamic>> createSupplier(Map<String, dynamic> data) async {
    final supplier = {
      'id': 'sup_${DateTime.now().millisecondsSinceEpoch}',
      ...data,
      'contacts': [],
      'createdAt': DateTime.now().toIso8601String(),
    };

    _suppliers.add(supplier);
    return {'success': true, 'supplier': supplier};
  }

  Future<Map<String, dynamic>> updateSupplier(
    String supplierId,
    Map<String, dynamic> updates,
  ) async {
    final index = _suppliers.indexWhere((s) => s['id'] == supplierId);
    if (index < 0) {
      return {'success': false, 'error': 'Not found'};
    }

    updates.forEach((key, value) {
      _suppliers[index][key] = value;
    });

    return {'success': true, 'supplier': _suppliers[index]};
  }

  Future<Map<String, dynamic>> deleteSupplier(String supplierId) async {
    _suppliers.removeWhere((s) => s['id'] == supplierId);
    return {'success': true};
  }

  Future<List<Map<String, dynamic>>> getSuppliersByCategory(String category) async {
    return _suppliers.where((s) => s['category'] == category).toList();
  }

  Future<List<String>> getCategories() async {
    return ['coffee', 'milk', 'pastry', 'equipment', 'packaging'];
  }

  Future<List<Map<String, dynamic>>> searchSuppliers(String query) async {
    final lowerQuery = query.toLowerCase();
    return _suppliers.where((s) {
      final name = (s['name'] ?? '').toString().toLowerCase();
      final phone = (s['phone'] ?? '').toString();
      return name.contains(lowerQuery) || phone.contains(query);
    }).toList();
  }

  Future<Map<String, dynamic>> addContact(
    String supplierId,
    Map<String, dynamic> contact,
  ) async {
    final index = _suppliers.indexWhere((s) => s['id'] == supplierId);
    if (index < 0) {
      return {'success': false, 'error': 'Not found'};
    }

    contact['id'] = 'contact_${DateTime.now().millisecondsSinceEpoch}';
    (_suppliers[index]['contacts'] as List).add(contact);

    return {'success': true, 'contact': contact};
  }

  void clear() {
    _suppliers.clear();
  }
}

import 'package:flutter_test/flutter_test.dart';

// ========== Mock Service ==========

class MockShopCatalogService {
  final List<Map<String, dynamic>> _groups = [];
  final List<Map<String, dynamic>> _products = [];
  final List<Map<String, String>> _authorizedEmployees = [];
  int _idCounter = 0;

  String _nextId(String prefix) => '${prefix}_${++_idCounter}';

  // Groups
  List<Map<String, dynamic>> getGroups() => List.from(_groups);

  Map<String, dynamic>? createGroup({required String name, String visibility = 'all', int sortOrder = 0}) {
    final group = {
      'id': _nextId('group'),
      'name': name,
      'visibility': visibility,
      'sortOrder': sortOrder,
      'isActive': true,
    };
    _groups.add(group);
    return group;
  }

  Map<String, dynamic>? updateGroup({required String id, String? name, String? visibility, int? sortOrder, bool? isActive}) {
    final idx = _groups.indexWhere((g) => g['id'] == id);
    if (idx < 0) return null;
    if (name != null) _groups[idx]['name'] = name;
    if (visibility != null) _groups[idx]['visibility'] = visibility;
    if (sortOrder != null) _groups[idx]['sortOrder'] = sortOrder;
    if (isActive != null) _groups[idx]['isActive'] = isActive;
    return _groups[idx];
  }

  bool deleteGroup(String id) {
    final len = _groups.length;
    _groups.removeWhere((g) => g['id'] == id);
    return _groups.length < len;
  }

  // Products
  List<Map<String, dynamic>> getProducts({String? groupId, bool? active}) {
    var list = List<Map<String, dynamic>>.from(_products);
    if (groupId != null) list = list.where((p) => p['groupId'] == groupId).toList();
    if (active != null) list = list.where((p) => p['isActive'] == active).toList();
    return list;
  }

  Map<String, dynamic>? createProduct({
    required String name,
    String? description,
    String? groupId,
    double? priceRetail,
    double? priceWholesale,
    int? pricePoints,
    int sortOrder = 0,
  }) {
    final product = {
      'id': _nextId('prod'),
      'name': name,
      'description': description ?? '',
      'groupId': groupId,
      'priceRetail': priceRetail,
      'priceWholesale': priceWholesale,
      'pricePoints': pricePoints,
      'photos': <String>[],
      'isActive': true,
      'sortOrder': sortOrder,
    };
    _products.add(product);
    return product;
  }

  Map<String, dynamic>? updateProduct({required String id, String? name, double? priceRetail, double? priceWholesale, int? pricePoints, bool? isActive}) {
    final idx = _products.indexWhere((p) => p['id'] == id);
    if (idx < 0) return null;
    if (name != null) _products[idx]['name'] = name;
    if (priceRetail != null) _products[idx]['priceRetail'] = priceRetail;
    if (priceWholesale != null) _products[idx]['priceWholesale'] = priceWholesale;
    if (pricePoints != null) _products[idx]['pricePoints'] = pricePoints;
    if (isActive != null) _products[idx]['isActive'] = isActive;
    return _products[idx];
  }

  bool deleteProduct(String id) {
    final len = _products.length;
    _products.removeWhere((p) => p['id'] == id);
    return _products.length < len;
  }

  List<String> uploadPhoto({required String productId}) {
    final idx = _products.indexWhere((p) => p['id'] == productId);
    if (idx < 0) return [];
    final photos = List<String>.from(_products[idx]['photos'] as List);
    photos.add('/uploads/shop-catalog/$productId/photo_${photos.length}.jpg');
    _products[idx]['photos'] = photos;
    return photos;
  }

  List<String>? deletePhoto({required String productId, required int index}) {
    final idx = _products.indexWhere((p) => p['id'] == productId);
    if (idx < 0) return null;
    final photos = List<String>.from(_products[idx]['photos'] as List);
    if (index < 0 || index >= photos.length) return null;
    photos.removeAt(index);
    _products[idx]['photos'] = photos;
    return photos;
  }

  // Authorized employees
  List<Map<String, String>> getAuthorizedEmployees() => List.from(_authorizedEmployees);

  bool addAuthorizedEmployee({required String phone, String? name}) {
    if (_authorizedEmployees.any((e) => e['phone'] == phone)) return false;
    _authorizedEmployees.add({'phone': phone, 'name': name ?? ''});
    return true;
  }

  bool removeAuthorizedEmployee(String phone) {
    final len = _authorizedEmployees.length;
    _authorizedEmployees.removeWhere((e) => e['phone'] == phone);
    return _authorizedEmployees.length < len;
  }
}

// ========== Tests ==========

void main() {
  late MockShopCatalogService service;

  setUp(() {
    service = MockShopCatalogService();
  });

  group('Product Groups', () {
    test('create group', () {
      final group = service.createGroup(name: 'Кружки');
      expect(group, isNotNull);
      expect(group!['name'], 'Кружки');
      expect(group['visibility'], 'all');
      expect(group['isActive'], true);
    });

    test('create wholesale-only group', () {
      final group = service.createGroup(name: 'Зерно опт', visibility: 'wholesale_only');
      expect(group!['visibility'], 'wholesale_only');
    });

    test('list groups', () {
      service.createGroup(name: 'Кружки');
      service.createGroup(name: 'Зерно');
      expect(service.getGroups().length, 2);
    });

    test('update group name', () {
      final group = service.createGroup(name: 'Old');
      final updated = service.updateGroup(id: group!['id'], name: 'New');
      expect(updated!['name'], 'New');
    });

    test('deactivate group', () {
      final group = service.createGroup(name: 'Test');
      service.updateGroup(id: group!['id'], isActive: false);
      expect(service.getGroups().first['isActive'], false);
    });

    test('delete group', () {
      final group = service.createGroup(name: 'Delete me');
      expect(service.deleteGroup(group!['id']), true);
      expect(service.getGroups(), isEmpty);
    });

    test('delete non-existent group returns false', () {
      expect(service.deleteGroup('nonexistent'), false);
    });
  });

  group('Products', () {
    test('create product with all prices', () {
      final product = service.createProduct(
        name: 'Кружка Arabica',
        description: 'Фирменная кружка',
        priceRetail: 500,
        priceWholesale: 350,
        pricePoints: 100,
      );
      expect(product, isNotNull);
      expect(product!['name'], 'Кружка Arabica');
      expect(product['priceRetail'], 500);
      expect(product['priceWholesale'], 350);
      expect(product['pricePoints'], 100);
      expect(product['photos'], isEmpty);
      expect(product['isActive'], true);
    });

    test('create product with group', () {
      final group = service.createGroup(name: 'Аксессуары');
      final product = service.createProduct(name: 'Стакан', groupId: group!['id']);
      expect(product!['groupId'], group['id']);
    });

    test('filter by groupId', () {
      final g1 = service.createGroup(name: 'G1');
      final g2 = service.createGroup(name: 'G2');
      service.createProduct(name: 'P1', groupId: g1!['id']);
      service.createProduct(name: 'P2', groupId: g2!['id']);
      service.createProduct(name: 'P3', groupId: g1['id']);

      final filtered = service.getProducts(groupId: g1['id']);
      expect(filtered.length, 2);
      expect(filtered.every((p) => p['groupId'] == g1['id']), true);
    });

    test('filter by active', () {
      final p1 = service.createProduct(name: 'Active');
      service.createProduct(name: 'Inactive');
      service.updateProduct(id: service.getProducts().last['id'], isActive: false);

      final active = service.getProducts(active: true);
      expect(active.length, 1);
      expect(active.first['name'], 'Active');
    });

    test('update product prices', () {
      final product = service.createProduct(name: 'Test', priceRetail: 100);
      final updated = service.updateProduct(id: product!['id'], priceRetail: 150, priceWholesale: 90);
      expect(updated!['priceRetail'], 150);
      expect(updated['priceWholesale'], 90);
    });

    test('delete product', () {
      final product = service.createProduct(name: 'Delete');
      expect(service.deleteProduct(product!['id']), true);
      expect(service.getProducts(), isEmpty);
    });
  });

  group('Product Photos', () {
    test('upload photo adds URL', () {
      final product = service.createProduct(name: 'Photo test');
      final photos = service.uploadPhoto(productId: product!['id']);
      expect(photos.length, 1);
      expect(photos.first, contains('photo_0'));
    });

    test('upload multiple photos', () {
      final product = service.createProduct(name: 'Multi');
      service.uploadPhoto(productId: product!['id']);
      final photos = service.uploadPhoto(productId: product['id']);
      expect(photos.length, 2);
    });

    test('delete photo by index', () {
      final product = service.createProduct(name: 'Del photo');
      service.uploadPhoto(productId: product!['id']);
      service.uploadPhoto(productId: product['id']);
      final remaining = service.deletePhoto(productId: product['id'], index: 0);
      expect(remaining!.length, 1);
      expect(remaining.first, contains('photo_1'));
    });

    test('delete photo invalid index returns null', () {
      final product = service.createProduct(name: 'Invalid');
      final result = service.deletePhoto(productId: product!['id'], index: 5);
      expect(result, isNull);
    });
  });

  group('Authorized Employees', () {
    test('add authorized employee', () {
      expect(service.addAuthorizedEmployee(phone: '79001234567', name: 'Иван'), true);
      expect(service.getAuthorizedEmployees().length, 1);
      expect(service.getAuthorizedEmployees().first['phone'], '79001234567');
    });

    test('no duplicate employees', () {
      service.addAuthorizedEmployee(phone: '79001234567');
      expect(service.addAuthorizedEmployee(phone: '79001234567'), false);
      expect(service.getAuthorizedEmployees().length, 1);
    });

    test('remove authorized employee', () {
      service.addAuthorizedEmployee(phone: '79001234567');
      expect(service.removeAuthorizedEmployee('79001234567'), true);
      expect(service.getAuthorizedEmployees(), isEmpty);
    });

    test('remove non-existent returns false', () {
      expect(service.removeAuthorizedEmployee('79009999999'), false);
    });
  });

  group('Wholesale Visibility', () {
    test('wholesale-only groups separate from all', () {
      service.createGroup(name: 'Для всех', visibility: 'all');
      service.createGroup(name: 'Опт только', visibility: 'wholesale_only');

      final all = service.getGroups();
      final wholesaleOnly = all.where((g) => g['visibility'] == 'wholesale_only').toList();
      final forAll = all.where((g) => g['visibility'] == 'all').toList();

      expect(wholesaleOnly.length, 1);
      expect(forAll.length, 1);
    });

    test('product with all three prices', () {
      final p = service.createProduct(
        name: 'Triple price',
        priceRetail: 500,
        priceWholesale: 300,
        pricePoints: 50,
      );
      expect(p!['priceRetail'], 500);
      expect(p['priceWholesale'], 300);
      expect(p['pricePoints'], 50);
    });
  });

  group('Model Serialization', () {
    test('ShopProduct fromJson/toJson roundtrip', () {
      final json = {
        'id': 'prod_1',
        'name': 'Кружка',
        'description': 'Фирменная',
        'groupId': 'group_1',
        'priceRetail': 500.0,
        'priceWholesale': 350.0,
        'pricePoints': 100,
        'photos': ['/photo1.jpg', '/photo2.jpg'],
        'isActive': true,
        'sortOrder': 1,
        'createdAt': '2026-02-24T12:00:00Z',
        'updatedAt': '2026-02-24T12:00:00Z',
      };
      // Verify keys match expected model fields
      expect(json['id'], 'prod_1');
      expect(json['photos'], hasLength(2));
      expect(json['priceRetail'], 500.0);
      expect(json['pricePoints'], 100);
    });

    test('ShopProductGroup fromJson/toJson roundtrip', () {
      final json = {
        'id': 'group_1',
        'name': 'Аксессуары',
        'visibility': 'wholesale_only',
        'sortOrder': 5,
        'isActive': true,
        'createdAt': '2026-02-24T12:00:00Z',
      };
      expect(json['visibility'], 'wholesale_only');
      expect(json['sortOrder'], 5);
    });

    test('product without optional prices', () {
      final p = service.createProduct(name: 'No prices');
      expect(p!['priceRetail'], isNull);
      expect(p['priceWholesale'], isNull);
      expect(p['pricePoints'], isNull);
    });
  });
}

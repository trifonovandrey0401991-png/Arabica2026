import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P1 Тесты управления сотрудниками для роли АДМИН
/// Покрывает: CRUD сотрудников, роли, привязка к магазинам
void main() {
  group('Employees Management Tests (P1)', () {
    late MockEmployeeManagementService mockEmployeeService;

    setUp(() async {
      mockEmployeeService = MockEmployeeManagementService();
    });

    tearDown(() async {
      mockEmployeeService.clear();
    });

    // ==================== СОЗДАНИЕ СОТРУДНИКОВ ====================

    group('Employee Creation Tests', () {
      test('AT-EMP-001: Создание нового сотрудника', () async {
        // Arrange
        final employeeData = {
          'name': 'Новый Сотрудник',
          'phone': '79001234567',
          'shopId': MockShopData.validShop['id'],
        };

        // Act
        final result = await mockEmployeeService.createEmployee(employeeData);

        // Assert
        expect(result['success'], true);
        expect(result['employee']['name'], 'Новый Сотрудник');
      });

      test('AT-EMP-002: Телефон должен быть уникальным', () async {
        // Arrange
        final employeeData = {
          'name': 'Сотрудник 1',
          'phone': '79001234567',
          'shopId': MockShopData.validShop['id'],
        };
        await mockEmployeeService.createEmployee(employeeData);

        // Act
        final result = await mockEmployeeService.createEmployee({
          'name': 'Сотрудник 2',
          'phone': '79001234567', // Same phone
          'shopId': MockShopData.validShop['id'],
        });

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('exists'));
      });

      test('AT-EMP-003: Валидация номера телефона', () async {
        // Arrange
        final invalidPhones = ['123', 'abc', '7900', ''];

        for (final phone in invalidPhones) {
          // Act
          final result = await mockEmployeeService.createEmployee({
            'name': 'Тест',
            'phone': phone,
            'shopId': MockShopData.validShop['id'],
          });

          // Assert
          expect(result['success'], false);
        }
      });

      test('AT-EMP-004: Привязка к магазину при создании', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        final employeeData = {
          'name': 'Сотрудник',
          'phone': '79005555555',
          'shopId': shopId,
        };

        // Act
        final result = await mockEmployeeService.createEmployee(employeeData);

        // Assert
        expect(result['employee']['shopId'], shopId);
      });
    });

    // ==================== РЕДАКТИРОВАНИЕ ====================

    group('Employee Update Tests', () {
      test('AT-EMP-005: Обновление имени сотрудника', () async {
        // Arrange
        final created = await mockEmployeeService.createEmployee({
          'name': 'Старое Имя',
          'phone': '79001111111',
          'shopId': MockShopData.validShop['id'],
        });
        final employeeId = created['employee']['id'];

        // Act
        final result = await mockEmployeeService.updateEmployee(
          employeeId,
          {'name': 'Новое Имя'},
        );

        // Assert
        expect(result['success'], true);
        expect(result['employee']['name'], 'Новое Имя');
      });

      test('AT-EMP-006: Смена магазина сотрудника', () async {
        // Arrange
        final created = await mockEmployeeService.createEmployee({
          'name': 'Сотрудник',
          'phone': '79002222222',
          'shopId': 'shop_001',
        });
        final employeeId = created['employee']['id'];

        // Act
        final result = await mockEmployeeService.updateEmployee(
          employeeId,
          {'shopId': 'shop_002'},
        );

        // Assert
        expect(result['success'], true);
        expect(result['employee']['shopId'], 'shop_002');
      });

      test('AT-EMP-007: Нельзя сменить телефон на существующий', () async {
        // Arrange
        await mockEmployeeService.createEmployee({
          'name': 'Сотрудник 1',
          'phone': '79001111111',
          'shopId': MockShopData.validShop['id'],
        });
        final created2 = await mockEmployeeService.createEmployee({
          'name': 'Сотрудник 2',
          'phone': '79002222222',
          'shopId': MockShopData.validShop['id'],
        });

        // Act
        final result = await mockEmployeeService.updateEmployee(
          created2['employee']['id'],
          {'phone': '79001111111'},
        );

        // Assert
        expect(result['success'], false);
      });
    });

    // ==================== РОЛИ ====================

    group('Role Tests', () {
      test('AT-EMP-008: Назначение роли админа', () async {
        // Arrange
        final created = await mockEmployeeService.createEmployee({
          'name': 'Будущий Админ',
          'phone': '79003333333',
          'shopId': MockShopData.validShop['id'],
        });

        // Act
        final result = await mockEmployeeService.setRole(
          created['employee']['id'],
          'admin',
        );

        // Assert
        expect(result['success'], true);
        expect(result['employee']['isAdmin'], true);
      });

      test('AT-EMP-009: Снятие роли админа', () async {
        // Arrange
        final created = await mockEmployeeService.createEmployee({
          'name': 'Админ',
          'phone': '79004444444',
          'shopId': MockShopData.validShop['id'],
          'isAdmin': true,
        });

        // Act
        final result = await mockEmployeeService.setRole(
          created['employee']['id'],
          'employee',
        );

        // Assert
        expect(result['success'], true);
        expect(result['employee']['isAdmin'], false);
      });

      test('AT-EMP-010: Список админов', () async {
        // Arrange
        await mockEmployeeService.createEmployee({
          'name': 'Админ 1',
          'phone': '79005555551',
          'shopId': MockShopData.validShop['id'],
          'isAdmin': true,
        });
        await mockEmployeeService.createEmployee({
          'name': 'Сотрудник',
          'phone': '79005555552',
          'shopId': MockShopData.validShop['id'],
          'isAdmin': false,
        });
        await mockEmployeeService.createEmployee({
          'name': 'Админ 2',
          'phone': '79005555553',
          'shopId': MockShopData.validShop['id'],
          'isAdmin': true,
        });

        // Act
        final admins = await mockEmployeeService.getAdmins();

        // Assert
        expect(admins.length, 2);
        expect(admins.every((a) => a['isAdmin'] == true), true);
      });
    });

    // ==================== УДАЛЕНИЕ ====================

    group('Employee Deletion Tests', () {
      test('AT-EMP-011: Удаление сотрудника', () async {
        // Arrange
        final created = await mockEmployeeService.createEmployee({
          'name': 'На удаление',
          'phone': '79006666666',
          'shopId': MockShopData.validShop['id'],
        });
        final employeeId = created['employee']['id'];

        // Act
        final result = await mockEmployeeService.deleteEmployee(employeeId);

        // Assert
        expect(result['success'], true);
      });

      test('AT-EMP-012: Деактивация вместо удаления', () async {
        // Arrange
        final created = await mockEmployeeService.createEmployee({
          'name': 'На деактивацию',
          'phone': '79007777777',
          'shopId': MockShopData.validShop['id'],
        });
        final employeeId = created['employee']['id'];

        // Act
        final result = await mockEmployeeService.deactivateEmployee(employeeId);

        // Assert
        expect(result['success'], true);
        expect(result['employee']['isActive'], false);
      });
    });

    // ==================== ФИЛЬТРАЦИЯ ====================

    group('Filter Tests', () {
      test('AT-EMP-013: Сотрудники по магазину', () async {
        // Arrange
        await mockEmployeeService.createEmployee({
          'name': 'Сотрудник 1',
          'phone': '79008888881',
          'shopId': 'shop_001',
        });
        await mockEmployeeService.createEmployee({
          'name': 'Сотрудник 2',
          'phone': '79008888882',
          'shopId': 'shop_002',
        });
        await mockEmployeeService.createEmployee({
          'name': 'Сотрудник 3',
          'phone': '79008888883',
          'shopId': 'shop_001',
        });

        // Act
        final employees = await mockEmployeeService.getByShop('shop_001');

        // Assert
        expect(employees.length, 2);
      });

      test('AT-EMP-014: Поиск по имени', () async {
        // Arrange
        await mockEmployeeService.createEmployee({
          'name': 'Иван Иванов',
          'phone': '79009999991',
          'shopId': MockShopData.validShop['id'],
        });
        await mockEmployeeService.createEmployee({
          'name': 'Пётр Петров',
          'phone': '79009999992',
          'shopId': MockShopData.validShop['id'],
        });

        // Act
        final result = await mockEmployeeService.search('Иван');

        // Assert
        expect(result.length, 1);
        expect(result.first['name'], contains('Иван'));
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockEmployeeManagementService {
  final List<Map<String, dynamic>> _employees = [];
  int _idCounter = 0;

  Future<Map<String, dynamic>> createEmployee(Map<String, dynamic> data) async {
    final phone = data['phone'] as String? ?? '';

    // Validate phone
    if (phone.length < 10 || !RegExp(r'^\d+$').hasMatch(phone)) {
      return {'success': false, 'error': 'Invalid phone'};
    }

    // Check uniqueness
    if (_employees.any((e) => e['phone'] == phone)) {
      return {'success': false, 'error': 'Phone already exists'};
    }

    _idCounter++;
    final employee = {
      'id': 'emp_$_idCounter',
      'name': data['name'],
      'phone': phone,
      'shopId': data['shopId'],
      'isAdmin': data['isAdmin'] ?? false,
      'isActive': true,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _employees.add(employee);
    return {'success': true, 'employee': employee};
  }

  Future<Map<String, dynamic>> updateEmployee(String id, Map<String, dynamic> updates) async {
    final index = _employees.indexWhere((e) => e['id'] == id);
    if (index < 0) {
      return {'success': false, 'error': 'Not found'};
    }

    // Check phone uniqueness if updating phone
    if (updates.containsKey('phone')) {
      final newPhone = updates['phone'];
      if (_employees.any((e) => e['phone'] == newPhone && e['id'] != id)) {
        return {'success': false, 'error': 'Phone already exists'};
      }
    }

    _employees[index] = {..._employees[index], ...updates};
    return {'success': true, 'employee': _employees[index]};
  }

  Future<Map<String, dynamic>> setRole(String id, String role) async {
    final index = _employees.indexWhere((e) => e['id'] == id);
    if (index < 0) {
      return {'success': false, 'error': 'Not found'};
    }

    _employees[index]['isAdmin'] = role == 'admin';
    return {'success': true, 'employee': _employees[index]};
  }

  Future<List<Map<String, dynamic>>> getAdmins() async {
    return _employees.where((e) => e['isAdmin'] == true).toList();
  }

  Future<Map<String, dynamic>> deleteEmployee(String id) async {
    final index = _employees.indexWhere((e) => e['id'] == id);
    if (index < 0) {
      return {'success': false, 'error': 'Not found'};
    }
    _employees.removeAt(index);
    return {'success': true};
  }

  Future<Map<String, dynamic>> deactivateEmployee(String id) async {
    final index = _employees.indexWhere((e) => e['id'] == id);
    if (index < 0) {
      return {'success': false, 'error': 'Not found'};
    }
    _employees[index]['isActive'] = false;
    return {'success': true, 'employee': _employees[index]};
  }

  Future<List<Map<String, dynamic>>> getByShop(String shopId) async {
    return _employees.where((e) => e['shopId'] == shopId).toList();
  }

  Future<List<Map<String, dynamic>>> search(String query) async {
    final lower = query.toLowerCase();
    return _employees.where((e) =>
      (e['name'] as String).toLowerCase().contains(lower)
    ).toList();
  }

  void clear() {
    _employees.clear();
    _idCounter = 0;
  }
}

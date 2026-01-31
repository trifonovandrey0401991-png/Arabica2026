// Mock services for testing
// This file contains mock implementations for testing purposes

import 'package:flutter/material.dart';

/// Mock данные сотрудника
class MockEmployeeData {
  static const Map<String, dynamic> validEmployee = {
    'id': 'emp_001',
    'name': 'Тестовый Сотрудник',
    'phone': '79001234567',
    'isAdmin': false,
    'referralCode': 12345,
    'preferredShops': ['Магазин 1', 'Магазин 2'],
  };

  static const Map<String, dynamic> adminEmployee = {
    'id': 'emp_admin',
    'name': 'Тестовый Админ',
    'phone': '79009999999',
    'isAdmin': true,
    'referralCode': 99999,
  };

  static const Map<String, dynamic> unverifiedEmployee = {
    'id': 'emp_unverified',
    'name': 'Неверифицированный',
    'phone': '79005555555',
    'isAdmin': false,
  };
}

/// Mock данные клиента
class MockClientData {
  static const Map<String, dynamic> validClient = {
    'phone': '79001111111',
    'name': 'Тестовый Клиент',
    'points': 5,
    'freeDrinksGiven': 2,
  };
}

/// Mock данные магазина
class MockShopData {
  static const Map<String, dynamic> validShop = {
    'id': 'shop_001',
    'name': 'Кофейня Центр',
    'address': 'ул. Центральная, 1',
    'latitude': 55.7558,
    'longitude': 37.6173,
  };

  static const List<Map<String, dynamic>> shopsList = [
    {
      'id': 'shop_001',
      'name': 'Кофейня Центр',
      'address': 'ул. Центральная, 1',
      'latitude': 55.7558,
      'longitude': 37.6173,
    },
    {
      'id': 'shop_002',
      'name': 'Кофейня Север',
      'address': 'ул. Северная, 10',
      'latitude': 55.8558,
      'longitude': 37.7173,
    },
  ];
}

/// Mock данные пересменки
class MockShiftReportData {
  static Map<String, dynamic> createPendingReport({
    required String shopAddress,
    required String employeeName,
  }) {
    return {
      'id': 'shift_${DateTime.now().millisecondsSinceEpoch}',
      'shopAddress': shopAddress,
      'employeeName': employeeName,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'answers': [],
    };
  }

  static Map<String, dynamic> createReviewReport({
    required String shopAddress,
    required String employeeName,
    required List<Map<String, dynamic>> answers,
  }) {
    return {
      'id': 'shift_${DateTime.now().millisecondsSinceEpoch}',
      'shopAddress': shopAddress,
      'employeeName': employeeName,
      'status': 'review',
      'createdAt': DateTime.now().toIso8601String(),
      'submittedAt': DateTime.now().toIso8601String(),
      'answers': answers,
    };
  }
}

/// Mock данные посещаемости
class MockAttendanceData {
  static Map<String, dynamic> createAttendance({
    required String employeeId,
    required String employeeName,
    required String shopAddress,
    required bool isOnTime,
  }) {
    return {
      'id': 'att_${DateTime.now().millisecondsSinceEpoch}',
      'employeeId': employeeId,
      'employeeName': employeeName,
      'shopAddress': shopAddress,
      'timestamp': DateTime.now().toIso8601String(),
      'isOnTime': isOnTime,
      'shiftType': 'morning',
    };
  }
}

/// Mock данные эффективности
class MockEfficiencyData {
  static const Map<String, dynamic> fullEfficiency = {
    'total': 15.5,
    'breakdown': {
      'shift': 3.0,
      'recount': 2.5,
      'handover': 1.5,
      'attendance': 5.0,
      'attendancePenalties': -2.0,
      'test': 2.5,
      'reviews': 1.5,
      'productSearch': 1.0,
      'rko': 0.5,
      'tasks': 2.0,
      'orders': 0.0,
      'envelope': -2.0,
    },
  };
}

/// Mock данные заказа
class MockOrderData {
  static Map<String, dynamic> createOrder({
    required String clientPhone,
    required String shopAddress,
    required List<Map<String, dynamic>> items,
  }) {
    return {
      'id': 'order_${DateTime.now().millisecondsSinceEpoch}',
      'clientPhone': clientPhone,
      'shopAddress': shopAddress,
      'items': items,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'totalAmount': items.fold<double>(
        0,
        (sum, item) => sum + (item['price'] as double) * (item['quantity'] as int),
      ),
    };
  }
}

/// Mock данные меню
class MockMenuData {
  static const Map<String, dynamic> validProduct = {
    'id': 'prod_001',
    'name': 'Капучино',
    'price': 250.0,
    'category': 'coffee',
    'available': true,
    'description': 'Классический капучино',
  };

  static const Map<String, dynamic> validProduct2 = {
    'id': 'prod_002',
    'name': 'Латте',
    'price': 350.0,
    'category': 'coffee',
    'available': true,
    'description': 'Латте с молоком',
  };

  static const List<Map<String, dynamic>> menuItems = [
    validProduct,
    validProduct2,
    {
      'id': 'prod_003',
      'name': 'Американо',
      'price': 200.0,
      'category': 'coffee',
      'available': true,
    },
    {
      'id': 'prod_004',
      'name': 'Чизкейк',
      'price': 300.0,
      'category': 'dessert',
      'available': true,
    },
  ];
}

/// Mock данные рейтинга
class MockRatingData {
  static const List<Map<String, dynamic>> topRatings = [
    {
      'employeeId': 'emp_top',
      'name': 'Топ Сотрудник',
      'normalizedRating': 14.525,
      'position': 1,
      'shiftsCount': 20,
    },
    {
      'employeeId': 'emp_second',
      'name': 'Второй Сотрудник',
      'normalizedRating': 13.0,
      'position': 2,
      'shiftsCount': 15,
    },
    {
      'employeeId': 'emp_third',
      'name': 'Третий Сотрудник',
      'normalizedRating': 8.78,
      'position': 3,
      'shiftsCount': 18,
    },
  ];
}

/// Mock данные конверта
class MockEnvelopeData {
  static Map<String, dynamic> createPendingEnvelope({
    required String shopId,
    required String shopAddress,
    required String window,
  }) {
    return {
      'id': 'env_pending_${DateTime.now().millisecondsSinceEpoch}',
      'shopId': shopId,
      'shopAddress': shopAddress,
      'window': window,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  static const Map<String, dynamic> envelopeSettings = {
    'morningWindow': {'start': '07:00', 'end': '09:00'},
    'eveningWindow': {'start': '19:00', 'end': '21:00'},
    'penaltyPoints': -5,
    'confirmPoints': 2,
  };
}

/// Mock данные задач
class MockTaskData {
  static Map<String, dynamic> createTask({
    required String title,
    required String assigneeId,
    required int points,
    String? deadline,
  }) {
    return {
      'id': 'task_${DateTime.now().millisecondsSinceEpoch}',
      'title': title,
      'assigneeId': assigneeId,
      'points': points,
      'deadline': deadline,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  static const Map<String, dynamic> recurringTask = {
    'id': 'recurring_001',
    'title': 'Ежедневная уборка',
    'frequency': 'daily',
    'time': '09:00',
    'points': 2,
    'status': 'active',
  };
}

/// Mock данные чата
class MockChatData {
  static const Map<String, dynamic> generalChat = {
    'id': 'general',
    'type': 'general',
    'name': 'Общий чат',
  };

  static Map<String, dynamic> createMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String text,
  }) {
    return {
      'id': 'msg_${DateTime.now().millisecondsSinceEpoch}',
      'chatId': chatId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }
}

/// Mock данные колеса удачи
class MockFortuneWheelData {
  static const List<Map<String, dynamic>> sectors = [
    {'label': 'Выходной день', 'probability': 6.67, 'color': '#FF5733'},
    {'label': '+500 к премии', 'probability': 6.67, 'color': '#33FF57'},
    {'label': 'Бесплатный обед', 'probability': 6.67, 'color': '#3357FF'},
    {'label': '+300 к премии', 'probability': 6.67, 'color': '#FF33F5'},
    {'label': 'Сертификат на кофе', 'probability': 6.67, 'color': '#F5FF33'},
    {'label': '+200 к премии', 'probability': 6.67, 'color': '#33FFF5'},
    {'label': 'Раньше уйти', 'probability': 6.67, 'color': '#FF8033'},
    {'label': '+100 к премии', 'probability': 6.67, 'color': '#8033FF'},
    {'label': 'Десерт в подарок', 'probability': 6.67, 'color': '#33FF80'},
    {'label': 'Скидка 20%', 'probability': 6.67, 'color': '#FF3380'},
    {'label': '+150 к премии', 'probability': 6.67, 'color': '#80FF33'},
    {'label': 'Кофе бесплатно неделю', 'probability': 6.67, 'color': '#3380FF'},
    {'label': '+250 к премии', 'probability': 6.67, 'color': '#FF5780'},
    {'label': 'Подарок от шефа', 'probability': 6.67, 'color': '#57FF80'},
    {'label': 'Позже прийти', 'probability': 6.65, 'color': '#8057FF'},
  ];
}

/// Mock HTTP responses
class MockHttpResponses {
  static Map<String, dynamic> success(dynamic data) {
    return {
      'success': true,
      ...?data is Map<String, dynamic> ? data : {'data': data},
    };
  }

  static Map<String, dynamic> error(String message) {
    return {
      'success': false,
      'error': message,
    };
  }

  static Map<String, dynamic> employeesList() {
    return {
      'success': true,
      'employees': [
        MockEmployeeData.validEmployee,
        MockEmployeeData.adminEmployee,
        MockEmployeeData.unverifiedEmployee,
      ],
    };
  }

  static Map<String, dynamic> shopsList() {
    return {
      'success': true,
      'shops': MockShopData.shopsList,
    };
  }

  static Map<String, dynamic> menuList() {
    return {
      'success': true,
      'items': MockMenuData.menuItems,
    };
  }

  static Map<String, dynamic> ratingsList() {
    return {
      'success': true,
      'ratings': MockRatingData.topRatings,
    };
  }
}

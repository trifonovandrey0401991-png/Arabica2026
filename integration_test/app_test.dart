/// Главный файл Integration тестов для приложения Arabica
///
/// Запуск всех тестов:
///   flutter test integration_test/app_test.dart
///
/// Запуск конкретного сценария:
///   flutter test integration_test/scenarios/create_order_test.dart
///
/// ВАЖНО: Требуется запущенный эмулятор или подключённое устройство!

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Импорт сценариев
import 'scenarios/create_order_test.dart' as create_order;
import 'scenarios/accept_order_test.dart' as accept_order;
import 'scenarios/reject_order_test.dart' as reject_order;
import 'scenarios/check_status_test.dart' as check_status;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('🧪 Integration Tests - Arabica App', () {
    group('📦 Сценарий 1: Создание заказа', () {
      create_order.main();
    });

    group('✅ Сценарий 2: Принятие заказа', () {
      accept_order.main();
    });

    group('❌ Сценарий 3: Отклонение заказа', () {
      reject_order.main();
    });

    group('📊 Сценарий 4: Проверка статусов', () {
      check_status.main();
    });
  });
}

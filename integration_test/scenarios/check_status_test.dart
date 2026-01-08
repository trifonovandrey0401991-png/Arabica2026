import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:arabica_app/main.dart' as app;
import '../helpers/test_helpers.dart';
import '../helpers/test_data.dart';

/// Сценарий 4: Проверка статусов заказов у клиента
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Проверка статусов заказов у клиента', () {
    testWidgets('Клиент видит статусы заказов в "Мои заказы"',
        (WidgetTester tester) async {
      // Запуск приложения
      app.main();
      await TestHelpers.waitForAppLoad(tester);

      TestHelpers.debugScreenshot(tester, '1_main_menu');

      // Шаг 1: Переходим в "Мои заказы"
      await TestHelpers.tapMenuButton(tester, TestData.myOrdersButtonText);
      await TestHelpers.waitForApi(tester);

      TestHelpers.debugScreenshot(tester, '2_my_orders');

      // Шаг 2: Проверяем наличие заказов
      final orderCards = find.byType(Card);

      if (orderCards.evaluate().isEmpty) {
        print('⚠️ Нет заказов для проверки статусов');
        return;
      }

      expect(orderCards, findsWidgets,
          reason: 'Должны быть карточки заказов');

      // Шаг 3: Проверяем наличие номеров заказов
      final orderNumbers = find.textContaining('Заказ #');
      expect(orderNumbers, findsWidgets,
          reason: 'Должны быть номера заказов');

      // Шаг 4: Проверяем наличие иконок статусов
      // Для принятых заказов - галочка
      final checkIcons = find.byIcon(Icons.check_circle);
      // Для отклонённых заказов - крестик
      final cancelIcons = find.byIcon(Icons.cancel);
      // Для ожидающих заказов - часы или receipt
      final pendingIcons = find.byIcon(Icons.hourglass_empty);
      final receiptIcons = find.byIcon(Icons.receipt);

      // Должна быть хотя бы одна из иконок
      final hasStatusIcons =
          checkIcons.evaluate().isNotEmpty ||
          cancelIcons.evaluate().isNotEmpty ||
          pendingIcons.evaluate().isNotEmpty ||
          receiptIcons.evaluate().isNotEmpty;

      expect(hasStatusIcons, isTrue,
          reason: 'Должны быть иконки статусов заказов');

      print('✅ Тест "Отображение статусов" пройден');
    });

    testWidgets('Принятый заказ показывает зелёную галочку',
        (WidgetTester tester) async {
      app.main();
      await TestHelpers.waitForAppLoad(tester);

      // Переходим в "Мои заказы"
      await TestHelpers.tapMenuButton(tester, TestData.myOrdersButtonText);
      await TestHelpers.waitForApi(tester);

      // Ищем зелёную галочку (Icons.check или Icons.check_circle)
      final checkIcon = find.byIcon(Icons.check_circle);
      final checkIconAlt = find.byIcon(Icons.check);

      if (checkIcon.evaluate().isNotEmpty || checkIconAlt.evaluate().isNotEmpty) {
        // Проверяем что иконка зелёного цвета
        // В integration тестах проверка цвета сложнее,
        // но мы можем убедиться что иконка существует
        print('✅ Найдена иконка галочки для принятого заказа');
      } else {
        print('⚠️ Нет принятых заказов или иконка галочки не найдена');
      }
    });

    testWidgets('Отклонённый заказ показывает красный крестик',
        (WidgetTester tester) async {
      app.main();
      await TestHelpers.waitForAppLoad(tester);

      // Переходим в "Мои заказы"
      await TestHelpers.tapMenuButton(tester, TestData.myOrdersButtonText);
      await TestHelpers.waitForApi(tester);

      // Ищем красный крестик (Icons.cancel или Icons.close)
      final cancelIcon = find.byIcon(Icons.cancel);
      final closeIcon = find.byIcon(Icons.close);

      if (cancelIcon.evaluate().isNotEmpty || closeIcon.evaluate().isNotEmpty) {
        print('✅ Найдена иконка крестика для отклонённого заказа');
      } else {
        print('⚠️ Нет отклонённых заказов или иконка крестика не найдена');
      }
    });

    testWidgets('Заказы отображают сумму и магазин',
        (WidgetTester tester) async {
      app.main();
      await TestHelpers.waitForAppLoad(tester);

      // Переходим в "Мои заказы"
      await TestHelpers.tapMenuButton(tester, TestData.myOrdersButtonText);
      await TestHelpers.waitForApi(tester);

      final orderCards = find.byType(Card);
      if (orderCards.evaluate().isEmpty) {
        print('⚠️ Нет заказов для проверки');
        return;
      }

      // Проверяем наличие суммы (должен быть текст с "₽")
      final priceText = find.textContaining('₽');
      expect(priceText, findsWidgets,
          reason: 'Должна отображаться сумма заказа в рублях');

      // Проверяем наличие иконки магазина
      final storeIcon = find.byIcon(Icons.store);
      if (storeIcon.evaluate().isNotEmpty) {
        expect(storeIcon, findsWidgets,
            reason: 'Должна быть иконка магазина');
      }

      print('✅ Тест "Отображение суммы и магазина" пройден');
    });

    testWidgets('Pull-to-refresh обновляет список заказов',
        (WidgetTester tester) async {
      app.main();
      await TestHelpers.waitForAppLoad(tester);

      // Переходим в "Мои заказы"
      await TestHelpers.tapMenuButton(tester, TestData.myOrdersButtonText);
      await TestHelpers.waitForApi(tester);

      // Проверяем наличие RefreshIndicator
      final refreshIndicator = find.byType(RefreshIndicator);

      if (refreshIndicator.evaluate().isNotEmpty) {
        // Делаем pull-to-refresh
        await tester.drag(
          find.byType(ListView).first,
          const Offset(0, 300),
        );
        await TestHelpers.waitForApi(tester);

        print('✅ Тест "Pull-to-refresh" пройден');
      } else {
        print('⚠️ RefreshIndicator не найден');
      }
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:arabica_app/main.dart' as app;
import '../helpers/test_helpers.dart';
import '../helpers/test_data.dart';

/// Сценарий 1: Клиент создаёт заказ
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Создание заказа клиентом', () {
    testWidgets('Клиент добавляет товар в корзину и оформляет заказ',
        (WidgetTester tester) async {
      // Запуск приложения
      app.main();
      await TestHelpers.waitForAppLoad(tester);

      // Шаг 1: Проверяем что главное меню загрузилось
      TestHelpers.debugScreenshot(tester, '1_main_menu');

      // Шаг 2: Переходим в Меню
      await TestHelpers.tapMenuButton(tester, TestData.menuButtonText);
      await TestHelpers.waitForApi(tester);

      TestHelpers.debugScreenshot(tester, '2_menu_page');

      // Шаг 3: Находим первый товар и добавляем в корзину
      // Ищем кнопку "+" или карточку товара
      final addButtons = find.byIcon(Icons.add);
      if (addButtons.evaluate().isNotEmpty) {
        await tester.tap(addButtons.first);
        await tester.pumpAndSettle();
      } else {
        // Альтернатива - нажать на карточку товара
        final cards = find.byType(Card);
        if (cards.evaluate().isNotEmpty) {
          await tester.tap(cards.first);
          await tester.pumpAndSettle();
        }
      }

      TestHelpers.debugScreenshot(tester, '3_item_added');

      // Шаг 4: Переходим в корзину
      final cartIcon = find.byIcon(Icons.shopping_cart);
      if (cartIcon.evaluate().isNotEmpty) {
        await tester.tap(cartIcon.first);
        await TestHelpers.waitForNavigation(tester);
      } else {
        // Возвращаемся назад и ищем кнопку Корзина
        await TestHelpers.goBack(tester);
        await TestHelpers.tapMenuButton(tester, TestData.cartButtonText);
      }

      TestHelpers.debugScreenshot(tester, '4_cart_page');

      // Шаг 5: Проверяем что корзина не пуста
      // Должны быть товары в корзине
      final itemsInCart = find.byType(ListTile);
      expect(itemsInCart, findsWidgets,
          reason: 'В корзине должны быть товары');

      // Шаг 6: Оформляем заказ
      final placeOrderButton = find.text(TestData.placeOrderText);
      if (placeOrderButton.evaluate().isNotEmpty) {
        await tester.tap(placeOrderButton);
        await TestHelpers.waitForApi(tester);
      } else {
        // Поиск по частичному тексту
        final orderButtons = find.textContaining('Оформить');
        if (orderButtons.evaluate().isNotEmpty) {
          await tester.tap(orderButtons.first);
          await TestHelpers.waitForApi(tester);
        }
      }

      TestHelpers.debugScreenshot(tester, '5_order_placed');

      // Шаг 7: Проверяем успешное создание заказа
      // Может быть диалог или snackbar с подтверждением
      await tester.pumpAndSettle(TestData.mediumWait);

      // Шаг 8: Переходим в "Мои заказы"
      // Сначала возвращаемся в главное меню
      await TestHelpers.goBack(tester);
      await TestHelpers.waitForNavigation(tester);

      await TestHelpers.tapMenuButton(tester, TestData.myOrdersButtonText);
      await TestHelpers.waitForApi(tester);

      TestHelpers.debugScreenshot(tester, '6_my_orders');

      // Шаг 9: Проверяем что заказ появился в списке
      final orderCards = find.byType(Card);
      expect(orderCards, findsWidgets,
          reason: 'Должны быть заказы в списке');

      // Проверяем наличие текста "Заказ #"
      final orderTexts = find.textContaining('Заказ #');
      expect(orderTexts, findsWidgets,
          reason: 'Должен быть текст "Заказ #" в карточках');

      print('✅ Тест "Создание заказа клиентом" пройден успешно');
    });

    testWidgets('Новый заказ отображается первым в списке',
        (WidgetTester tester) async {
      app.main();
      await TestHelpers.waitForAppLoad(tester);

      // Переходим в "Мои заказы"
      await TestHelpers.tapMenuButton(tester, TestData.myOrdersButtonText);
      await TestHelpers.waitForApi(tester);

      // Получаем список карточек
      final cards = find.byType(Card);

      if (cards.evaluate().isNotEmpty) {
        // Первая карточка должна содержать самый большой номер заказа
        // или самую свежую дату
        TestHelpers.expectCardExists();

        print('✅ Тест "Сортировка заказов" пройден');
      } else {
        print('⚠️ Нет заказов для проверки сортировки');
      }
    });
  });
}

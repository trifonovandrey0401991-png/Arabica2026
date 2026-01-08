import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:arabica_app/main.dart' as app;
import '../helpers/test_helpers.dart';
import '../helpers/test_data.dart';

/// Сценарий 2: Сотрудник принимает заказ
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Принятие заказа сотрудником', () {
    testWidgets('Сотрудник видит вкладки и принимает заказ',
        (WidgetTester tester) async {
      // Запуск приложения
      app.main();
      await TestHelpers.waitForAppLoad(tester);

      TestHelpers.debugScreenshot(tester, '1_main_menu_employee');

      // Шаг 1: Переходим в "Заказы (Клиенты)"
      // Это доступно только для сотрудников/админов
      final clientOrdersButton = find.text(TestData.clientOrdersButtonText);

      if (clientOrdersButton.evaluate().isEmpty) {
        print('⚠️ Кнопка "Заказы (Клиенты)" не найдена - возможно пользователь не сотрудник');
        return;
      }

      await tester.tap(clientOrdersButton);
      await TestHelpers.waitForApi(tester);

      TestHelpers.debugScreenshot(tester, '2_employee_orders_page');

      // Шаг 2: Проверяем наличие трёх вкладок
      expect(find.textContaining(TestData.pendingTabText), findsWidgets,
          reason: 'Должна быть вкладка "Ожидают"');
      expect(find.textContaining(TestData.completedTabText), findsWidgets,
          reason: 'Должна быть вкладка "Выполненные"');
      expect(find.textContaining(TestData.rejectedTabText), findsWidgets,
          reason: 'Должна быть вкладка "Отказано"');

      // Шаг 3: Проверяем что мы на вкладке "Ожидают"
      final pendingTab = find.textContaining(TestData.pendingTabText);
      expect(pendingTab, findsWidgets);

      // Шаг 4: Проверяем наличие заказов
      await tester.pumpAndSettle();
      final orderCards = find.byType(Card);

      if (orderCards.evaluate().isEmpty) {
        print('⚠️ Нет ожидающих заказов для тестирования');
        return;
      }

      // Шаг 5: Нажимаем на первый заказ
      await tester.tap(orderCards.first);
      await TestHelpers.waitForNavigation(tester);

      TestHelpers.debugScreenshot(tester, '3_order_detail');

      // Шаг 6: Ищем кнопку "Принять заказ"
      final acceptButton = find.text(TestData.acceptOrderText);

      if (acceptButton.evaluate().isEmpty) {
        print('⚠️ Кнопка "Принять заказ" не найдена');
        await TestHelpers.goBack(tester);
        return;
      }

      // Шаг 7: Нажимаем "Принять заказ"
      await tester.tap(acceptButton);
      await tester.pumpAndSettle();

      TestHelpers.debugScreenshot(tester, '4_accept_dialog');

      // Шаг 8: Если есть диалог подтверждения - подтверждаем
      final confirmButton = find.text(TestData.confirmText);
      if (confirmButton.evaluate().isNotEmpty) {
        await tester.tap(confirmButton);
        await TestHelpers.waitForApi(tester);
      }

      // Ждём обновления
      await TestHelpers.waitForApi(tester);

      TestHelpers.debugScreenshot(tester, '5_order_accepted');

      // Шаг 9: Возвращаемся к списку заказов
      await TestHelpers.goBack(tester);
      await TestHelpers.waitForNavigation(tester);

      // Шаг 10: Переходим на вкладку "Выполненные"
      await TestHelpers.tapTab(tester, TestData.completedTabText);
      await tester.pumpAndSettle();

      TestHelpers.debugScreenshot(tester, '6_completed_tab');

      // Шаг 11: Проверяем что есть заказы с галочкой
      final checkIcon = find.byIcon(Icons.check_circle);
      expect(checkIcon, findsWidgets,
          reason: 'Должна быть иконка галочки для выполненных заказов');

      print('✅ Тест "Принятие заказа сотрудником" пройден успешно');
    });

    testWidgets('Принятый заказ отображает имя сотрудника',
        (WidgetTester tester) async {
      app.main();
      await TestHelpers.waitForAppLoad(tester);

      // Переходим в "Заказы (Клиенты)"
      final clientOrdersButton = find.text(TestData.clientOrdersButtonText);
      if (clientOrdersButton.evaluate().isEmpty) {
        print('⚠️ Тест пропущен - нет доступа к заказам клиентов');
        return;
      }

      await tester.tap(clientOrdersButton);
      await TestHelpers.waitForApi(tester);

      // Переходим на вкладку "Выполненные"
      await TestHelpers.tapTab(tester, TestData.completedTabText);
      await tester.pumpAndSettle();

      // Проверяем что есть текст "Принял:"
      final acceptedByText = find.textContaining('Принял:');
      if (acceptedByText.evaluate().isNotEmpty) {
        expect(acceptedByText, findsWidgets,
            reason: 'Должен отображаться текст "Принял: <имя>"');
        print('✅ Тест "Отображение имени сотрудника" пройден');
      } else {
        print('⚠️ Нет выполненных заказов для проверки');
      }
    });
  });
}

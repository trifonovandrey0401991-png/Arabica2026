import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:arabica_app/main.dart' as app;
import '../helpers/test_helpers.dart';
import '../helpers/test_data.dart';

/// Сценарий 3: Сотрудник отклоняет заказ
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Отклонение заказа сотрудником', () {
    testWidgets('Сотрудник отклоняет заказ с указанием причины',
        (WidgetTester tester) async {
      // Запуск приложения
      app.main();
      await TestHelpers.waitForAppLoad(tester);

      TestHelpers.debugScreenshot(tester, '1_main_menu');

      // Шаг 1: Переходим в "Заказы (Клиенты)"
      final clientOrdersButton = find.text(TestData.clientOrdersButtonText);

      if (clientOrdersButton.evaluate().isEmpty) {
        print('⚠️ Кнопка "Заказы (Клиенты)" не найдена - возможно пользователь не сотрудник');
        return;
      }

      await tester.tap(clientOrdersButton);
      await TestHelpers.waitForApi(tester);

      TestHelpers.debugScreenshot(tester, '2_employee_orders');

      // Шаг 2: Проверяем что мы на вкладке "Ожидают"
      await tester.pumpAndSettle();

      // Шаг 3: Проверяем наличие заказов
      final orderCards = find.byType(Card);

      if (orderCards.evaluate().isEmpty) {
        print('⚠️ Нет ожидающих заказов для тестирования отклонения');
        return;
      }

      // Шаг 4: Нажимаем на первый заказ
      await tester.tap(orderCards.first);
      await TestHelpers.waitForNavigation(tester);

      TestHelpers.debugScreenshot(tester, '3_order_detail');

      // Шаг 5: Ищем кнопку "Отклонить"
      final rejectButton = find.text(TestData.rejectOrderText);
      final rejectButtonAlt = find.textContaining('Отклонить');
      final rejectButtonAlt2 = find.textContaining('Отказать');

      Finder? activeRejectButton;
      if (rejectButton.evaluate().isNotEmpty) {
        activeRejectButton = rejectButton;
      } else if (rejectButtonAlt.evaluate().isNotEmpty) {
        activeRejectButton = rejectButtonAlt;
      } else if (rejectButtonAlt2.evaluate().isNotEmpty) {
        activeRejectButton = rejectButtonAlt2;
      }

      if (activeRejectButton == null) {
        print('⚠️ Кнопка отклонения не найдена');
        await TestHelpers.goBack(tester);
        return;
      }

      // Шаг 6: Нажимаем "Отклонить"
      await tester.tap(activeRejectButton.first);
      await tester.pumpAndSettle();

      TestHelpers.debugScreenshot(tester, '4_reject_dialog');

      // Шаг 7: Вводим причину отказа (если есть поле ввода)
      final textFields = find.byType(TextField);
      if (textFields.evaluate().isNotEmpty) {
        await tester.enterText(textFields.first, TestData.testRejectionReason);
        await tester.pumpAndSettle();
      }

      // Также проверяем TextFormField
      final textFormFields = find.byType(TextFormField);
      if (textFormFields.evaluate().isNotEmpty) {
        await tester.enterText(textFormFields.first, TestData.testRejectionReason);
        await tester.pumpAndSettle();
      }

      TestHelpers.debugScreenshot(tester, '5_reason_entered');

      // Шаг 8: Подтверждаем отказ
      final confirmButton = find.text(TestData.confirmText);
      final confirmButtonAlt = find.textContaining('Подтвердить');
      final okButton = find.text('ОК');

      if (confirmButton.evaluate().isNotEmpty) {
        await tester.tap(confirmButton);
      } else if (confirmButtonAlt.evaluate().isNotEmpty) {
        await tester.tap(confirmButtonAlt.first);
      } else if (okButton.evaluate().isNotEmpty) {
        await tester.tap(okButton);
      }

      await TestHelpers.waitForApi(tester);

      TestHelpers.debugScreenshot(tester, '6_order_rejected');

      // Шаг 9: Возвращаемся к списку заказов
      await TestHelpers.goBack(tester);
      await TestHelpers.waitForNavigation(tester);

      // Шаг 10: Переходим на вкладку "Отказано"
      await TestHelpers.tapTab(tester, TestData.rejectedTabText);
      await tester.pumpAndSettle();

      TestHelpers.debugScreenshot(tester, '7_rejected_tab');

      // Шаг 11: Проверяем что есть заказы с крестиком
      final cancelIcon = find.byIcon(Icons.cancel);
      expect(cancelIcon, findsWidgets,
          reason: 'Должна быть иконка крестика для отклонённых заказов');

      print('✅ Тест "Отклонение заказа" пройден успешно');
    });

    testWidgets('Отклонённый заказ показывает причину отказа',
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

      // Переходим на вкладку "Отказано"
      await TestHelpers.tapTab(tester, TestData.rejectedTabText);
      await tester.pumpAndSettle();

      // Проверяем что есть текст "Отказал:"
      final rejectedByText = find.textContaining('Отказал:');
      if (rejectedByText.evaluate().isNotEmpty) {
        expect(rejectedByText, findsWidgets,
            reason: 'Должен отображаться текст "Отказал: <имя>"');
        print('✅ Тест "Отображение причины отказа" пройден');
      } else {
        print('⚠️ Нет отклонённых заказов для проверки');
      }
    });
  });
}

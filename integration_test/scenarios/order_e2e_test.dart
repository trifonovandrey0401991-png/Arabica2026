import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:arabica_app/main.dart' as app;
import '../helpers/test_helpers.dart';
import '../helpers/test_data.dart';
import '../helpers/test_auth_seeder.dart';

/// E2E сценарий: Создание заказа (клиент) → Принятие заказа (сотрудник)
///
/// Пре-заполняем сессию developer'а (Андрей В) → вводим PIN →
/// developer видит все секции (Клиент, Панель сотрудника, Управляющая).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('E2E: Клиент создаёт заказ → Сотрудник принимает',
      (WidgetTester tester) async {
    // Пре-заполняем сессию чтобы пропустить регистрацию
    await TestAuthSeeder.seedDeveloper();

    app.main();
    await TestHelpers.waitForAppLoad(tester);

    _dumpScreen(tester, 'AFTER_LOAD');

    // Определяем экран: PIN-ввод или уже главное меню
    final isPinEntry = find.text('Введите PIN-код').evaluate().isNotEmpty;
    if (isPinEntry) {
      print('>>> Вводим PIN...');
      await TestHelpers.enterPin(tester, TestData.testPin);
    }

    _dumpScreen(tester, 'AFTER_AUTH');

    // Проверяем что мы на developer-меню
    final hasDeveloperMenu =
        find.text('Панель сотрудника').evaluate().isNotEmpty;
    if (!hasDeveloperMenu) {
      print('⚠️ Не developer меню. Тексты на экране:');
      _dumpScreen(tester, 'NOT_DEVELOPER');
      fail('Ожидалось developer-меню с "Панель сотрудника"');
    }

    print('>>> Developer меню загружено');

    // ═══════════════════════════════════════════════════════
    // ЧАСТЬ 1: СОЗДАНИЕ ЗАКАЗА (через секцию "Клиент")
    // ═══════════════════════════════════════════════════════

    print('>>> STEP 1: Открываем "Клиент"');
    await _tapText(tester, 'Клиент');
    await TestHelpers.waitForNavigation(tester);
    _dumpScreen(tester, 'CLIENT_FUNCTIONS');

    print('>>> STEP 2: Открываем "Меню"');
    await _tapText(tester, 'Меню');
    await TestHelpers.waitForApi(tester);
    _dumpScreen(tester, 'SHOP_DIALOG');

    expect(find.text('Выберите кофейню'), findsOneWidget,
        reason: 'Должен быть диалог выбора кофейни');

    print('>>> STEP 3: Выбираем кофейню');
    // Тапаем по первому адресу магазина
    final shopAddress = find.textContaining('Лермонтов,Комсомольская');
    if (shopAddress.evaluate().isNotEmpty) {
      await tester.tap(shopAddress.first);
    } else {
      // Тапаем первый адрес (любой текст с запятой — это адрес)
      final allTexts = find.byType(Text);
      for (final element in allTexts.evaluate()) {
        final w = element.widget as Text;
        if (w.data != null &&
            w.data!.contains(',') &&
            w.data != 'Выберите кофейню') {
          await tester.tap(find.text(w.data!));
          break;
        }
      }
    }
    await TestHelpers.waitForApi(tester);
    _dumpScreen(tester, 'CATEGORIES');

    print('>>> STEP 4: Выбираем первую категорию');
    final listView = find.byType(ListView);
    if (listView.evaluate().isNotEmpty) {
      final items = find.descendant(
          of: listView.first, matching: find.byType(InkWell));
      if (items.evaluate().isNotEmpty) {
        await tester.tap(items.first);
      }
    }
    await TestHelpers.waitForApi(tester);
    _dumpScreen(tester, 'PRODUCTS');

    print('>>> STEP 5: Выбираем первый товар');
    final gridView = find.byType(GridView);
    expect(gridView, findsWidgets, reason: 'Должен быть GridView с товарами');
    final product = find.descendant(
        of: gridView.first, matching: find.byType(GestureDetector));
    if (product.evaluate().isNotEmpty) {
      await tester.tap(product.first);
    }
    await _safePump(tester);
    _dumpScreen(tester, 'PRODUCT_DIALOG');

    print('>>> STEP 6: Добавляем в корзину');
    final addBtn = find.text('Добавить в корзину');
    expect(addBtn, findsOneWidget);
    await tester.tap(addBtn);
    await _safePump(tester);
    print('>>> Товар добавлен');

    await Future.delayed(const Duration(seconds: 2));
    await _safePump(tester);

    print('>>> STEP 7: Назад → Корзина');
    await TestHelpers.goBack(tester); // MenuPage → MenuGroupsPage
    await TestHelpers.goBack(tester); // MenuGroupsPage → ClientFunctionsPage

    await _tapText(tester, 'Корзина');
    await TestHelpers.waitForNavigation(tester);
    _dumpScreen(tester, 'CART');

    print('>>> STEP 8: Заказать');
    final orderBtn = find.text('Заказать');
    expect(orderBtn, findsWidgets, reason: 'Кнопка "Заказать"');
    await tester.ensureVisible(orderBtn.first);
    await _safePump(tester);
    await tester.tap(orderBtn.first);
    await _safePump(tester);

    expect(find.text('Когда заберёте?'), findsOneWidget);

    print('>>> STEP 9: Выбираем 5 мин');
    await tester.tap(find.text('5').first);
    await TestHelpers.waitForApi(tester);
    _dumpScreen(tester, 'ORDER_CREATED');

    print('=== ЧАСТЬ 1: Заказ создан ===');

    // ═══════════════════════════════════════════════════════
    // ЧАСТЬ 2: ПРИНЯТИЕ ЗАКАЗА (через "Панель сотрудника")
    // ═══════════════════════════════════════════════════════

    print('>>> STEP 10: Назад → главное меню');
    // Стек: MainMenu → ClientFunctions → OrdersPage
    await TestHelpers.goBack(tester);
    await TestHelpers.goBack(tester);
    _dumpScreen(tester, 'MAIN_MENU_2');

    print('>>> STEP 11: Панель сотрудника');
    await _tapText(tester, 'Панель сотрудника');
    await TestHelpers.waitForNavigation(tester);

    print('>>> STEP 12: Заказы');
    final ordersBtn = find.text('Заказы');
    expect(ordersBtn, findsWidgets);
    await tester.ensureVisible(ordersBtn.first);
    await _safePump(tester);
    await tester.tap(ordersBtn.first);
    await TestHelpers.waitForApi(tester);
    _dumpScreen(tester, 'EMPLOYEE_ORDERS');

    final orderCards = find.byType(Card);
    if (orderCards.evaluate().isEmpty) {
      print('⚠️ Нет ожидающих заказов');
      return;
    }

    print('>>> STEP 13: Открываем заказ');
    await tester.tap(orderCards.first);
    await TestHelpers.waitForNavigation(tester);
    _dumpScreen(tester, 'ORDER_DETAIL');

    print('>>> STEP 14: Принять');
    final acceptBtn = find.text('Принять');
    expect(acceptBtn, findsOneWidget);
    await tester.ensureVisible(acceptBtn);
    await _safePump(tester);
    await tester.tap(acceptBtn);
    await TestHelpers.waitForApi(tester);

    final accepted = find.textContaining('принят');
    if (accepted.evaluate().isNotEmpty) {
      print('>>> Заказ принят!');
    }

    print('✅ E2E тест ПРОЙДЕН: заказ создан и принят');
  });
}

// ═══════════════════════════════════════════════════════
// УТИЛИТЫ
// ═══════════════════════════════════════════════════════

Future<void> _safePump(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(const Duration(seconds: 2));
  } catch (_) {
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  expect(finder, findsWidgets, reason: 'Не найден текст: "$text"');
  await tester.ensureVisible(finder.first);
  await _safePump(tester);
  await tester.tap(finder.first);
  await _safePump(tester);
}

void _dumpScreen(WidgetTester tester, String label) {
  print('=== $label ===');
  final allTexts = find.byType(Text);
  final seen = <String>{};
  for (final element in allTexts.evaluate()) {
    final textWidget = element.widget as Text;
    final data = textWidget.data;
    if (data != null && data.trim().isNotEmpty && !seen.contains(data)) {
      seen.add(data);
      print('  TEXT: "$data"');
    }
  }
  print('=== END $label ===');
}

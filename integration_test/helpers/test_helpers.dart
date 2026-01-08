import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_data.dart';

/// Вспомогательные функции для Integration тестов
class TestHelpers {
  /// Дождаться полной загрузки приложения
  static Future<void> waitForAppLoad(WidgetTester tester) async {
    // Ждём несколько циклов pumpAndSettle для асинхронной загрузки
    await tester.pumpAndSettle(TestData.longWait);

    // Дополнительное ожидание для сетевых запросов
    await Future.delayed(TestData.apiWait);
    await tester.pumpAndSettle();
  }

  /// Дождаться загрузки после навигации
  static Future<void> waitForNavigation(WidgetTester tester) async {
    await tester.pumpAndSettle(TestData.mediumWait);
    await Future.delayed(TestData.shortWait);
    await tester.pumpAndSettle();
  }

  /// Дождаться ответа API
  static Future<void> waitForApi(WidgetTester tester) async {
    await Future.delayed(TestData.apiWait);
    await tester.pumpAndSettle();
  }

  /// Нажать на кнопку меню по тексту
  static Future<void> tapMenuButton(WidgetTester tester, String text) async {
    final finder = find.text(text);

    // Прокрутить если нужно
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();

    await tester.tap(finder);
    await waitForNavigation(tester);
  }

  /// Нажать на первый найденный элемент по типу
  static Future<void> tapFirstOfType<T extends Widget>(WidgetTester tester) async {
    final finder = find.byType(T).first;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await waitForNavigation(tester);
  }

  /// Нажать на иконку
  static Future<void> tapIcon(WidgetTester tester, IconData icon) async {
    final finder = find.byIcon(icon).first;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Ввести текст в поле ввода
  static Future<void> enterText(
    WidgetTester tester,
    Finder finder,
    String text,
  ) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
  }

  /// Нажать на первое текстовое поле и ввести текст
  static Future<void> enterTextInFirstField(
    WidgetTester tester,
    String text,
  ) async {
    final finder = find.byType(TextField).first;
    await enterText(tester, finder, text);
  }

  /// Проверить что виджет с текстом существует
  static void expectTextExists(String text) {
    expect(find.text(text), findsWidgets,
        reason: 'Ожидался текст: "$text"');
  }

  /// Проверить что виджет с текстом НЕ существует
  static void expectTextNotExists(String text) {
    expect(find.text(text), findsNothing,
        reason: 'Не ожидался текст: "$text"');
  }

  /// Проверить что иконка существует
  static void expectIconExists(IconData icon) {
    expect(find.byIcon(icon), findsWidgets,
        reason: 'Ожидалась иконка: $icon');
  }

  /// Проверить что Card существует
  static void expectCardExists() {
    expect(find.byType(Card), findsWidgets,
        reason: 'Ожидались карточки (Card)');
  }

  /// Прокрутить список вниз
  static Future<void> scrollDown(WidgetTester tester) async {
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
  }

  /// Прокрутить список вверх
  static Future<void> scrollUp(WidgetTester tester) async {
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
  }

  /// Перейти назад (нажать кнопку Back)
  static Future<void> goBack(WidgetTester tester) async {
    final backButton = find.byType(BackButton);
    if (backButton.evaluate().isNotEmpty) {
      await tester.tap(backButton);
      await waitForNavigation(tester);
    } else {
      // Попробовать найти иконку стрелки назад
      final arrowBack = find.byIcon(Icons.arrow_back);
      if (arrowBack.evaluate().isNotEmpty) {
        await tester.tap(arrowBack.first);
        await waitForNavigation(tester);
      }
    }
  }

  /// Pull-to-refresh
  static Future<void> pullToRefresh(WidgetTester tester) async {
    await tester.drag(
      find.byType(RefreshIndicator).first,
      const Offset(0, 300),
    );
    await waitForApi(tester);
  }

  /// Нажать на вкладку TabBar
  static Future<void> tapTab(WidgetTester tester, String tabText) async {
    final finder = find.text(tabText);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Проверить количество элементов
  static void expectCount(Finder finder, int count) {
    expect(finder, findsNWidgets(count),
        reason: 'Ожидалось $count элементов');
  }

  /// Сделать скриншот для отладки (если включено)
  static Future<void> debugScreenshot(WidgetTester tester, String name) async {
    // В integration тестах можно использовать:
    // await binding.takeScreenshot(name);
    // Но это требует дополнительной настройки
    print('DEBUG: Скриншот "$name" - позиция в тесте');
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_data.dart';

/// Вспомогательные функции для Integration тестов
class TestHelpers {
  /// Дождаться полной загрузки приложения
  /// Использует pump-цикл вместо pumpAndSettle чтобы пережить
  /// начальные ошибки ScreenUtil (Matrix4 entries must be finite)
  static Future<void> waitForAppLoad(WidgetTester tester) async {
    // Даём время на инициализацию Firebase + ScreenUtil
    // pump вместо pumpAndSettle — устойчив к ошибкам рендеринга
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    // Дополнительное ожидание для сетевых запросов
    await Future.delayed(TestData.apiWait);

    // Теперь пробуем pumpAndSettle (ScreenUtil должен стабилизироваться)
    try {
      await tester.pumpAndSettle(const Duration(seconds: 1));
    } catch (_) {
      // Если pumpAndSettle не стабилизировался, ещё подождём
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
    }
  }

  /// Ввести PIN-код на экране авторизации
  /// PinInputWidget использует кастомную цифровую клавиатуру с Text('0'-'9')
  static Future<void> enterPin(WidgetTester tester, String pin) async {
    // Проверяем что мы на экране PIN
    final pinWidget = find.byType(LayoutBuilder);
    if (pinWidget.evaluate().isEmpty) return;

    for (final digit in pin.split('')) {
      // Находим кнопку с цифрой внутри InkWell
      final digitButton = find.text(digit);
      if (digitButton.evaluate().isNotEmpty) {
        await tester.tap(digitButton.last);
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // Ждём навигацию после ввода PIN
    await tester.pumpAndSettle(TestData.longWait);
    await Future.delayed(TestData.apiWait);
    await tester.pumpAndSettle();
  }

  /// Полный запуск: загрузка приложения + авторизация PIN
  static Future<void> launchAndLogin(WidgetTester tester) async {
    await waitForAppLoad(tester);

    // Определяем экран: PIN-ввод или регистрация
    final isRegistration = find.text('Зарегистрироваться').evaluate().isNotEmpty;
    final isPinEntry = find.text('Введите PIN-код').evaluate().isNotEmpty;

    if (isRegistration) {
      // На экране регистрации — вводим данные клиента по умолчанию
      await registerAsUser(tester, TestData.clientPhone, TestData.clientName);
    } else if (isPinEntry) {
      await enterPin(tester, TestData.testPin);
    }
    // Иначе — уже авторизованы
  }

  /// Запуск с конкретной ролью
  static Future<void> launchAs(WidgetTester tester, String phone, String name) async {
    await waitForAppLoad(tester);

    final isRegistration = find.text('Зарегистрироваться').evaluate().isNotEmpty;
    final isPinEntry = find.text('Введите PIN-код').evaluate().isNotEmpty;

    if (isRegistration) {
      await registerAsUser(tester, phone, name);
    } else if (isPinEntry) {
      await enterPin(tester, TestData.testPin);
    }
  }

  /// Заполнить форму регистрации и отправить
  static Future<void> registerAsUser(WidgetTester tester, String phone, String name) async {
    // Находим все TextField на экране регистрации
    final textFields = find.byType(TextField);
    final fieldCount = textFields.evaluate().length;

    // Поле телефона (первое числовое поле, после "+7 ")
    if (fieldCount >= 1) {
      // Убираем "7" из начала — форма уже показывает "+7 "
      final phoneDigits = phone.startsWith('7') ? phone.substring(1) : phone;
      await tester.enterText(textFields.at(0), phoneDigits);
      await tester.pumpAndSettle();
    }

    // Поле имени (второе)
    if (fieldCount >= 2) {
      await tester.enterText(textFields.at(1), name);
      await tester.pumpAndSettle();
    }

    // Поле PIN (третье)
    if (fieldCount >= 3) {
      await tester.enterText(textFields.at(2), TestData.testPin);
      await tester.pumpAndSettle();
    }

    // Повтор PIN (четвёртое)
    if (fieldCount >= 4) {
      await tester.enterText(textFields.at(3), TestData.testPin);
      await tester.pumpAndSettle();
    }

    // Нажимаем "Зарегистрироваться"
    final registerBtn = find.text('Зарегистрироваться');
    if (registerBtn.evaluate().isNotEmpty) {
      await tester.ensureVisible(registerBtn);
      await tester.pumpAndSettle();
      await tester.tap(registerBtn);
      await tester.pumpAndSettle(TestData.longWait);
      await Future.delayed(TestData.apiWait);
      await tester.pumpAndSettle();
    }
  }

  /// Дождаться загрузки после навигации
  static Future<void> waitForNavigation(WidgetTester tester) async {
    await _safePumpAndSettle(tester);
    await Future.delayed(TestData.shortWait);
    await _safePumpAndSettle(tester);
  }

  /// Дождаться ответа API
  static Future<void> waitForApi(WidgetTester tester) async {
    await Future.delayed(TestData.apiWait);
    await _safePumpAndSettle(tester);
  }

  /// Безопасный pumpAndSettle — не падает при ScreenUtil ошибках
  static Future<void> _safePumpAndSettle(WidgetTester tester) async {
    try {
      await tester.pumpAndSettle(const Duration(seconds: 2));
    } catch (_) {
      // Fallback: несколько pump если pumpAndSettle не стабилизируется
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
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

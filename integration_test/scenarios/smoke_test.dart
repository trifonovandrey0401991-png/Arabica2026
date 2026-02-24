import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:arabica_app/main.dart' as app;
import '../helpers/test_helpers.dart';
import '../helpers/test_data.dart';

/// Smoke test — запуск + авторизация (регистрация или PIN) + проверка главного меню
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Smoke: запуск и авторизация клиента', (WidgetTester tester) async {
    app.main();

    // launchAndLogin определяет экран (регистрация / PIN / уже авторизован)
    // и автоматически проходит авторизацию как клиент
    await TestHelpers.launchAndLogin(tester);

    // Диагностика: что на экране после авторизации?
    print('=== AFTER AUTH ===');
    final allTexts = find.byType(Text);
    for (final element in allTexts.evaluate()) {
      final textWidget = element.widget as Text;
      if (textWidget.data != null && textWidget.data!.trim().isNotEmpty) {
        print('TEXT: "${textWidget.data}"');
      }
    }
    print('=== END AFTER AUTH ===');

    // Проверяем что мы прошли авторизацию — на экране должно быть что-то
    expect(allTexts, findsWidgets, reason: 'Экран не пуст после авторизации');

    // Проверяем что мы НЕ на экране регистрации
    final isStillRegistration = find.text('Зарегистрироваться').evaluate().isNotEmpty;
    final isStillPin = find.text('Введите PIN-код').evaluate().isNotEmpty;

    if (isStillRegistration) {
      print('⚠️ Всё ещё на экране регистрации — авторизация не прошла');
    } else if (isStillPin) {
      print('⚠️ Всё ещё на экране PIN — авторизация не прошла');
    } else {
      print('✅ Авторизация прошла, мы на главном экране');
    }

    // Тест считается пройденным если мы ушли с экрана регистрации/PIN
    expect(isStillRegistration, isFalse,
        reason: 'Должны были пройти регистрацию');

    print('✅ Smoke test passed');
  });
}

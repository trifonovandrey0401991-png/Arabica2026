# Проверка кода пересменки

## Текущий код (правильный):

В файле `lib/main_menu_page.dart` строка 352-364:

```dart
items.add(_tile(context, Icons.work_history, 'Пересменка', () async {
  // Используем текущего пользователя (из роли или имени)
  final employeeName = _userRole?.displayName ?? _userName ?? 'Сотрудник';
  if (!context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => ShiftShopSelectionPage(
        employeeName: employeeName,
      ),
    ),
  );
}));
```

## Что должно быть:

1. При нажатии на "Пересменка" должен сразу открываться выбор магазина
2. НЕ должно быть страницы выбора сотрудника
3. Файл `lib/shift_employee_selection_page.dart` должен быть удален

## Если все еще появляется выбор сотрудника:

1. **Обновите код с GitHub:**
   ```powershell
   git pull origin main
   ```

2. **Очистите кэш Flutter:**
   ```powershell
   flutter clean
   ```

3. **Пересоберите приложение:**
   ```powershell
   flutter pub get
   flutter run
   ```

4. **Проверьте, что файл удален:**
   ```powershell
   Test-Path lib\shift_employee_selection_page.dart
   ```
   Должно вернуть `False`

5. **Проверьте импорты в main_menu_page.dart:**
   ```powershell
   Select-String -Path lib\main_menu_page.dart -Pattern "shift_employee_selection"
   ```
   Не должно быть результатов








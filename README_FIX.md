# Инструкция по исправлению проблемы с выбором сотрудника

## Проблема
При нажатии на "Пересменка" все еще появляется выбор сотрудника из листа "Работники".

## Решение

### Шаг 1: Обновите код с GitHub

```powershell
# Если есть конфликт с локальными файлами, сначала сохраните их:
git stash push -m "Локальные файлы" -- fix-firebase-imports.ps1 get-sha-certificates.ps1 run-sha-script.bat

# Обновите код
git pull origin main

# Восстановите локальные файлы (если нужны)
git stash pop
```

### Шаг 2: Запустите скрипт автоматического исправления

```powershell
.\FIX_LOCAL_ISSUES.ps1
```

Скрипт автоматически:
- ✅ Удалит старый файл `lib\shift_employee_selection_page.dart`
- ✅ Уберет старый импорт из `lib\main_menu_page.dart`
- ✅ Проверит правильность кода
- ✅ Проверит использование правильного листа (Лист11)

### Шаг 3: Или исправьте вручную

Если скрипт не работает, выполните вручную:

```powershell
# 1. Удалите старый файл
Remove-Item lib\shift_employee_selection_page.dart -Force

# 2. Откройте lib\main_menu_page.dart и удалите строку:
#    import 'shift_employee_selection_page.dart';

# 3. Убедитесь, что есть строка:
#    import 'shift_shop_selection_page.dart';
```

### Шаг 4: Пересоберите приложение

```powershell
flutter clean
flutter pub get
flutter run
```

## Проверка

После исправления проверьте:

```powershell
# Файл должен быть удален
Test-Path lib\shift_employee_selection_page.dart
# Должно вернуть: False

# Старый импорт должен отсутствовать
Select-String -Path lib\main_menu_page.dart -Pattern "shift_employee_selection"
# Не должно быть результатов

# Правильный импорт должен быть
Select-String -Path lib\main_menu_page.dart -Pattern "shift_shop_selection"
# Должно показать: import 'shift_shop_selection_page.dart';
```

## Что должно быть в коде

В файле `lib/main_menu_page.dart` строка 352-364 должна быть:

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

**НЕ должно быть:**
```dart
MaterialPageRoute(builder: (context) => const ShiftEmployeeSelectionPage())
```

## Текущее состояние на GitHub

✅ Файл `shift_employee_selection_page.dart` удален
✅ Импорт `shift_employee_selection_page.dart` удален
✅ Используется правильный код с `ShiftShopSelectionPage`
✅ Используется лист `Лист11` вместо `Работники`
✅ Сотрудник определяется автоматически из системы ролей








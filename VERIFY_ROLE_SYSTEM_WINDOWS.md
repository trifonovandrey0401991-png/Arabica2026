# Проверка системы ролей - Инструкция для Windows

## ✅ Все файлы на GitHub проверены и присутствуют!

## 🔧 Что нужно сделать на Windows:

### Шаг 1: Откройте PowerShell в папке проекта

```powershell
cd C:\Users\Admin\arabica2026
```

### Шаг 2: Обновите код с GitHub

```powershell
git fetch origin
git pull origin main
```

### Шаг 3: Запустите скрипт проверки (PowerShell версия)

```powershell
.\CHECK_ROLE_FILES.ps1
```

Если появится ошибка о политике выполнения, выполните:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\CHECK_ROLE_FILES.ps1
```

### Шаг 4: Проверьте файлы вручную (если скрипт не работает)

```powershell
# Проверьте наличие файла
Test-Path lib\role_test_page.dart

# Проверьте кнопку в коде
Select-String -Path lib\main_menu_page.dart -Pattern "Тест ролей"

# Проверьте импорт
Select-String -Path lib\main_menu_page.dart -Pattern "import 'role_test_page.dart'"
```

### Шаг 5: Полностью очистите и пересоберите проект

```powershell
flutter clean
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .dart_tool -ErrorAction SilentlyContinue
flutter pub get
```

### Шаг 6: Удалите старое приложение с устройства

```powershell
adb uninstall com.example.arabica_app
```

Или вручную:
- Настройки → Приложения → arabica_app → Удалить

### Шаг 7: Переустановите приложение

```powershell
flutter run
```

## 🔍 Ручная проверка файлов:

### 1. Проверьте наличие файла role_test_page.dart:

```powershell
Get-Item lib\role_test_page.dart
```

Должен показать файл.

### 2. Проверьте импорт в main_menu_page.dart:

```powershell
Select-String -Path lib\main_menu_page.dart -Pattern "role_test_page"
```

Должна быть строка: `import 'role_test_page.dart';`

### 3. Проверьте кнопку "Тест ролей":

```powershell
Select-String -Path lib\main_menu_page.dart -Pattern "Тест ролей" | Select-Object LineNumber, Line
```

Должны быть строки с кнопкой (около строки 331-337).

### 4. Проверьте метод _getMenuItems():

```powershell
Select-String -Path lib\main_menu_page.dart -Pattern "_getMenuItems" | Select-Object LineNumber, Line
```

Должны быть:
- Строка ~148: `children: _getMenuItems(),`
- Строка ~159: `List<Widget> _getMenuItems() {`

## 🐛 Если кнопка всё ещё не появляется:

### Вариант 1: Проблема с кэшем Flutter

```powershell
flutter clean
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .dart_tool -ErrorAction SilentlyContinue
flutter pub get
flutter run
```

### Вариант 2: Проверьте версию кода

```powershell
git log --oneline -1
```

Должен быть коммит: `7121f61 Add verification guide for role system`

Если нет, выполните:
```powershell
git pull origin main
```

### Вариант 3: Проверьте, что файлы действительно обновлены

```powershell
git diff HEAD lib\main_menu_page.dart
```

Если есть изменения, значит файл не обновлен. Выполните:
```powershell
git checkout lib\main_menu_page.dart
```

### Вариант 4: Полная переустановка

```powershell
# Остановите приложение (Ctrl+C)
flutter clean
flutter pub get
adb uninstall com.example.arabica_app
flutter run
```

## 📱 Проверка в приложении:

1. Запустите приложение
2. Откройте главное меню
3. **Прокрутите вниз** - кнопка "Тест ролей" должна быть в конце списка
4. Иконка: 🔬 (колба/наука)

## ⚠️ Важно:

- Кнопка "Тест ролей" должна быть видна **ВСЕМ** пользователям (независимо от роли)
- Она находится в **конце списка** всех кнопок
- Если вы не видите её, возможно нужно **прокрутить меню вниз**

## 📞 Если ничего не помогло:

Выполните и пришлите результат:

```powershell
.\CHECK_ROLE_FILES.ps1
git log --oneline -5
git status
flutter doctor
```

Это поможет найти проблему.





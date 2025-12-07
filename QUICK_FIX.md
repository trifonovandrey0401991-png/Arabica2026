# Быстрое исправление проблемы

## Выполните эти команды по порядку:

### 1. Сохраните и удалите конфликтующие файлы:

```powershell
# Сохраняем локальные файлы
Copy-Item fix-firebase-imports.ps1 fix-firebase-imports.ps1.backup -ErrorAction SilentlyContinue
Copy-Item get-sha-certificates.ps1 get-sha-certificates.ps1.backup -ErrorAction SilentlyContinue
Copy-Item run-sha-script.bat run-sha-script.bat.backup -ErrorAction SilentlyContinue

# Временно удаляем
Remove-Item fix-firebase-imports.ps1 -Force -ErrorAction SilentlyContinue
Remove-Item get-sha-certificates.ps1 -Force -ErrorAction SilentlyContinue
Remove-Item run-sha-script.bat -Force -ErrorAction SilentlyContinue
```

### 2. Сбросьте изменения в сгенерированных файлах:

```powershell
git restore linux/flutter/generated_plugin_registrant.cc
git restore linux/flutter/generated_plugin_registrant.h
git restore linux/flutter/generated_plugins.cmake
git restore macos/Flutter/GeneratedPluginRegistrant.swift
git restore pubspec.lock
git restore windows/flutter/generated_plugin_registrant.cc
git restore windows/flutter/generated_plugin_registrant.h
git restore windows/flutter/generated_plugins.cmake
```

### 3. Обновите код:

```powershell
git pull origin main
```

### 4. Восстановите локальные файлы:

```powershell
Copy-Item fix-firebase-imports.ps1.backup fix-firebase-imports.ps1 -Force -ErrorAction SilentlyContinue
Copy-Item get-sha-certificates.ps1.backup get-sha-certificates.ps1 -Force -ErrorAction SilentlyContinue
Copy-Item run-sha-script.bat.backup run-sha-script.bat -Force -ErrorAction SilentlyContinue

# Удаляем бэкапы
Remove-Item *.backup -Force -ErrorAction SilentlyContinue
```

### 5. Исправьте импорты вручную:

Откройте файл `lib\main_menu_page.dart` и:
- Найдите строку: `import 'shift_employee_selection_page.dart';`
- Удалите её
- Убедитесь, что есть: `import 'shift_shop_selection_page.dart';`

### 6. Пересоберите приложение:

```powershell
flutter clean
flutter pub get
flutter run
```

## Или используйте автоматический скрипт:

```powershell
# После обновления кода с GitHub
.\FIX_AND_UPDATE.ps1
```

# Диагностика проблемы с кнопками пересчета

## Проверка 1: Убедитесь, что код обновлен

Выполните в PowerShell:
```powershell
cd C:\Users\Admin\arabica2026
git status
```

Если видите "Your branch is behind 'origin/main'", выполните:
```powershell
git pull origin main
```

## Проверка 2: Проверьте наличие файлов

```powershell
ls lib/recount_*.dart
```

Должны быть файлы:
- recount_answer_model.dart
- recount_question_model.dart
- recount_questions_page.dart
- recount_report_model.dart
- recount_report_view_page.dart
- recount_reports_list_page.dart
- recount_service.dart
- recount_shop_selection_page.dart

## Проверка 3: Проверьте импорты в main_menu_page.dart

```powershell
Select-String -Path "lib/main_menu_page.dart" -Pattern "recount_shop_selection_page|recount_reports_list_page"
```

Должны быть строки:
- import 'recount_shop_selection_page.dart';
- import 'recount_reports_list_page.dart';

## Проверка 4: Проверьте наличие кнопок в коде

```powershell
Select-String -Path "lib/main_menu_page.dart" -Pattern "Пересчет товаров|Отчет по пересчету"
```

Должны быть найдены обе строки.

## Проверка 5: Проверьте компиляцию

```powershell
flutter analyze lib/main_menu_page.dart lib/recount_*.dart
```

Если есть ошибки, исправьте их.

## Проверка 6: Полная пересборка

```powershell
flutter clean
flutter pub get
flutter run
```

## Если кнопки все еще не появляются:

1. Проверьте консоль на ошибки компиляции
2. Убедитесь, что прокрутили меню вниз - кнопки могут быть в конце списка
3. Проверьте, что используете последний коммит: `git log --oneline -1`


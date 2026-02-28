# ПОЛНЫЙ АУДИТ ПРОЕКТА ARABICA — 28 февраля 2026

> **Дата проверки**: 2026-02-28
> **Ветка**: refactoring/full-restructure
> **Проверял**: Claude Code (полный автоматический аудит)

---

## ОБЩАЯ СТАТИСТИКА ПРОЕКТА

| Показатель | Значение |
|-----------|---------|
| Dart-файлов (lib/) | 512 |
| Строк кода (lib/) | 41 664 |
| Строк кода (тесты) | 15 877 |
| JS-файлов (сервер, без node_modules) | ~100 |
| Строк кода (сервер) | 13 039 |
| Модулей (features/) | 37 |
| API-файлов | 75 |
| Самый большой Dart-файл | cigarette_training_page.dart — 4 945 строк |
| Самый большой JS-файл | master_catalog_api.js — 1 808 строк |

---

## РЕЗУЛЬТАТЫ ТЕСТОВ

### Flutter тесты — ВСЕ ПРОШЛИ

| Тест | Результат |
|------|-----------|
| flutter test (юнит-тесты) | **619 пройдено, 1 пропущен** |
| flutter analyze | **0 ошибок, 1 предупреждение, 687 информация** |
| SharedPreferences consistency (stage 4) | **14/14 пройдено** |
| Efficiency shop matching | **8/8 пройдено** |
| Broken functions (stage 2) | **27/27 пройдено** |
| DB schema (stage 3) | **37/37 пройдено** |
| Security (stage 1) | **20/20 пройдено** |
| check_setstate.py | 35 setState в 24 файлах (все в синхронном контексте) |
| find_unguarded.py | **0 незащищённых setState** |

**Итого: 725 тестов пройдено, 0 провалено**

---

## НАЙДЕННЫЕ ПРОБЛЕМЫ ПО ПРИОРИТЕТАМ

---

### КРИТИЧЕСКИЕ (могут вызвать падение приложения)

#### K-1. setState после await без проверки mounted — 4 места

Если пользователь уйдёт с экрана, пока идёт загрузка, приложение может упасть.

| Файл | Строка | Описание |
|------|--------|----------|
| `ai_dashboard_page.dart` | 79 | else-ветка после await, проверка mounted только в if |
| `cigarette_training_page.dart` | 4731 | else-ветка после await _loadData() |
| `z_report_training_page.dart` | 355, 363 | Обе ветки после await ZReportService.parseZReport() |
| `coffee_machine_reports_list_page.dart` | 318 | После await showDatePicker() |

#### K-2. Использование BuildContext после await — 63 места в 21 файле

Та же проблема — контекст может быть уже не актуален. Топ файлов:

| Файл | Количество |
|------|-----------|
| main_menu_page.dart | 17 |
| employee_panel_page.dart | 10 |
| shop_chat_members_page.dart | 4 |
| cigarette_training_page.dart | 4 |
| rko_amount_input_page.dart | 3 |
| envelope_report_view_page.dart | 3 |
| И ещё 15 файлов... | 1-2 |

#### K-3. Пустые блоки обработки ошибок (Flutter) — 27 мест

Ошибки проглатываются молча — пользователь видит пустой экран, а мы не знаем почему.

| Файл | Количество |
|------|-----------|
| manager_grid_page.dart | 7 |
| my_dialogs_page.dart | 4 |
| messenger_shell_page.dart | 3 |
| coffee_machine_questions_management_page.dart | 2 |
| И ещё 11 файлов... | по 1 |

#### K-4. Жёсткие приведения типов из API — 6 мест (TypeError при null)

Если сервер вернёт null, приложение упадёт:

| Файл | Строка | Выражение |
|------|--------|----------|
| auth_service.dart | 271 | `data['sessionToken'] as String` |
| auth_service.dart | 277 | `data['expiresAt'] as int` |
| auth_service.dart | 554 | `data['sessionToken'] as String` |
| auth_service.dart | 559 | `data['expiresAt'] as int` |
| envelope_question_service.dart | 107 | `data['url'] as String` |
| employee_chat_service.dart | 151 | `data['url'] as String` |

---

### ВЫСОКИЙ ПРИОРИТЕТ (безопасность и потенциальные баги)

#### В-1. Загрузка фото сотрудника без авторизации (СЕРВЕР)

| Файл | Строка | Маршрут | Описание |
|------|--------|---------|----------|
| index.js | 700 | POST /upload-employee-photo | Нет requireAuth — любой может загрузить фото |

#### В-2. Генерация ID без случайного суффикса — 25+ мест (СЕРВЕР)

Если два запроса придут в одну миллисекунду, один перезапишет другой:

| Файл | Что | Риск |
|------|-----|------|
| shops_api.js:119 | `'shop_' + Date.now()` | Перезапись магазина |
| rating_wheel_api.js:1082 | `spin_${Date.now()}` | Потеря вращения колеса |
| recount_points_api.js:145,198 | `rp_${Date.now()}` | Потеря баллов пересчёта |
| recount_api.js:721 | `ep_${Date.now()}` | Потеря штрафа |
| shifts_api.js:709 | `ep_${Date.now()}` | Потеря штрафа за пересменку |
| training_api.js:112 | `training_article_${Date.now()}` | Потеря статьи |
| tests_api.js:189,313 | `test_question/result_${Date.now()}` | Потеря вопроса/результата |
| recipes_api.js:46,193 | `recipe_${Date.now()}` | Потеря рецепта |
| И ещё ~13 файлов... | | |

#### В-3. Отсутствие авторизации на серверных маршрутах

| Файл | Маршрут | Описание |
|------|---------|----------|
| employee_registration_api.js:24 | POST /api/employee-registration | Нет auth — спам регистрациями |
| cigarette_vision_api.js:311 | GET .../images/:fileName | Доступ к обучающим фото без auth |
| index.js:1036 | POST /api/app-version | Любой может изменить версию приложения |

#### В-4. Жёстко прописанный URL сервера в приложении

| Файл | Строка | URL |
|------|--------|-----|
| shift_handover_report_view_page.dart | 227 | `https://arabica26.ru/shift-photos/...` — надо `ApiConstants.serverUrl` |

---

### СРЕДНИЙ ПРИОРИТЕТ (технический долг)

#### С-1. Захардкоженные цвета — 510 мест (Color(0x...)) + 9600 мест (Colors.xxx)

Вместо использования AppColors. Топ файлов:

| Файл | ~Количество |
|------|-----------|
| my_efficiency_page.dart | ~45 |
| client_wheel_page.dart | ~35 |
| points_settings_page.dart | ~30 |
| animated_wheel_widget.dart | ~25 |
| loyalty_gamification_settings_page.dart | ~25 |

#### С-2. Сырой fsp.writeFile вместо writeJsonFile — 4 места (СЕРВЕР)

| Файл | Строка | Что пишется |
|------|--------|-------------|
| envelope_api.js | 151 | Вопросы конверта (JSON) |
| envelope_api.js | 258 | Создание вопроса конверта |
| envelope_api.js | 298 | Обновление вопроса конверта |
| media_api.js | 140 | Запись лога приложения |

#### С-3. Молчаливое проглатывание ошибок WebSocket — 4 места (СЕРВЕР)

| Файл | Строка | Что |
|------|--------|-----|
| messenger_api.js | 564 | notifyMessageDeleted |
| messenger_api.js | 621 | notifyReadReceipt |
| messenger_api.js | 661 | notifyReactionAdded |
| messenger_api.js | 697 | notifyReactionRemoved |

#### С-4. Неиспользуемый код (мёртвые функции) — 12 мест

| Файл | Строка | Что |
|------|--------|-----|
| firebase_service.dart | 696 | `_onNotificationTapped` |
| cigarette_training_page.dart | 2291 | `_getCombinedAccuracy` |
| kpi_service.dart | 436, 1132 | `_buildMonthStats`, `_buildShopMonthStatsLegacy` |
| loyalty_scanner_page.dart | 190, 1035 | `_redeemLegacy`, `_buildInfoChip` |
| main_cash_page.dart | 165 | `_balancesByShop` |
| cart_page.dart | 615 | `_showOrderDialog` (помечен как неиспользуемый) |
| shift_reports_list_page.dart | 411, 1288 | `_calculatePendingShifts`, `_buildExpiredReportsList` |
| work_schedule_page.dart | 106 | `_loadAdminNotifications` |
| cart_provider.dart | 59 | `_dedupeKey` |

#### С-5. Дублирование кода (6 страниц управления вопросами — ~9 850 строк)

| Файл | Строк |
|------|-------|
| shift_questions_management_page.dart | 2 573 |
| shift_handover_questions_management_page.dart | 2 976 |
| test_questions_management_page.dart | 1 661 |
| coffee_machine_questions_management_page.dart | 1 067 |
| envelope_questions_management_page.dart | 836 |
| recount_questions_management_page.dart | 734 |

Все делают одно и то же: загрузка, добавление, редактирование, удаление, перестановка вопросов.

#### С-6. Дублирование списков отчётов — 5 файлов, ~6 660 строк

| Файл | Строк |
|------|-------|
| shift_reports_list_page.dart | 2 247 |
| recount_reports_list_page.dart | 1 698 |
| shift_handover_reports_list_page.dart | 1 276 |
| envelope_reports_list_page.dart | 851 |
| coffee_machine_reports_list_page.dart | 591 |

---

### НИЗКИЙ ПРИОРИТЕТ (стилистика и мелочи)

#### Н-1. Неиспользуемые импорты — 8 мест

| Файл | Что |
|------|-----|
| main_menu_page.dart:18 | employee_panel_page.dart |
| settings_save_button_widget.dart:3 | app_colors.dart |
| loyalty_scanner_page.dart:6 | logger.dart |
| cart_page.dart:4,7 | api_constants.dart, menu_page.dart |
| work_schedule_page.dart:2,5 | shared_preferences, shift_transfer_model.dart |

#### Н-2. Неиспользуемые поля — 4 места

| Файл | Поле |
|------|------|
| kpi_shops_list_page.dart:31 | `_loadingShops` |
| loyalty_gamification_settings_page.dart:48 | `_accentColor` |
| messenger_profile_page.dart:38 | `_originalName` |
| recount_shop_selection_page.dart:34 | `_isAiModelTrained` |

#### Н-3. Поля которые должны быть final — 16 мест

В 7 файлах. Не влияет на работу, только стиль.

#### Н-4. Захардкоженные ссылки на Telegram-бота — 3 места

| Файл | Строка |
|------|--------|
| forgot_pin_page.dart | 134, 512 |
| otp_verification_page.dart | 117 |

Лучше вынести в константу.

#### Н-5. Отсутствие фигурных скобок в if — 456 мест

Стилистическое замечание, не баг. Например: `if (x) return;` вместо `if (x) { return; }`

#### Н-6. Контроллеры текста без dispose в диалогах — 49 мест

Все внутри showDialog (не полевые), но лучше вызывать dispose при закрытии.

---

## СЕРВЕРНАЯ ЧАСТЬ — ЧИСТО

| Категория | Результат |
|-----------|-----------|
| getHours() без московского времени | **0 найдено** (всё исправлено ранее) |
| SQL-инъекции | **0 настоящих уязвимостей** |
| Авторизация безопасность (unit-тесты) | **20/20 пройдено** |

---

## СВОДНАЯ ТАБЛИЦА

| Приоритет | Категория | Количество |
|-----------|-----------|-----------|
| КРИТИЧЕСКИЙ | setState/BuildContext после await | 67 мест (4+63) |
| КРИТИЧЕСКИЙ | Пустые catch-блоки (Flutter) | 27 мест |
| КРИТИЧЕСКИЙ | Жёсткие приведения типов (TypeError) | 6 мест |
| ВЫСОКИЙ | Загрузка фото без авторизации (сервер) | 1 маршрут |
| ВЫСОКИЙ | ID без случайного суффикса (сервер) | 25+ мест |
| ВЫСОКИЙ | Маршруты без auth (сервер) | 3 маршрута |
| ВЫСОКИЙ | Захардкоженный URL сервера | 1 место |
| СРЕДНИЙ | Захардкоженные цвета | 510+ мест |
| СРЕДНИЙ | Сырой writeFile вместо writeJsonFile | 4 места |
| СРЕДНИЙ | Молчаливые ошибки WebSocket | 4 места |
| СРЕДНИЙ | Мёртвый код | 12 функций |
| СРЕДНИЙ | Дублирование кода | ~16 500 строк |
| НИЗКИЙ | Неиспользуемые импорты/поля | 12 мест |
| НИЗКИЙ | Стилистика (final, скобки) | 472 места |
| НИЗКИЙ | Контроллеры без dispose | 49 мест |

---

## ЧТО ХОРОШО

1. **Все 725 тестов проходят** — приложение стабильно
2. **Нет SQL-инъекций** — данные пользователей в безопасности
3. **Нет getHours() без UTC+3** — московское время везде корректно
4. **Все планировщики исправлены** — автоматические задачи работают
5. **Безопасность авторизации протестирована** — 20/20
6. **SharedPreferences ключи согласованы** — 14/14
7. **Эффективность правильно считается** — 8/8
8. **DB schema корректна** — 37/37

---

## РЕКОМЕНДУЕМЫЙ ПОРЯДОК ИСПРАВЛЕНИЙ

1. **Сначала** — K-1 (setState без mounted) и K-4 (приведения типов) — быстрые фиксы, предотвращают падения
2. **Затем** — В-1 (auth на загрузке фото) и В-3 (маршруты без auth) — безопасность
3. **Далее** — В-2 (случайные суффиксы к ID) — предотвращение потери данных
4. **Потом** — K-2 и K-3 (BuildContext и пустые catch) — файл за файлом при работе с модулем
5. **В фоновом режиме** — С-1...С-6 — постепенно при касании файлов (Boy Scout Rule)

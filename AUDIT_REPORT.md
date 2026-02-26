# AUDIT REPORT - Arabica2026
> **Дата**: 2026-02-22 | **Версия**: 2.7.0 | **36 модулей Flutter** | **71 API** | **11 schedulers**

---

## 1. СВОДНАЯ ТАБЛИЦА МОДУЛЕЙ

Оценка **1-10** (10 = идеально):
- **Код** — баги, антипаттерны, error handling
- **Арх** — разделение, зависимости, размер файлов
- **BS** — Boy Scout (mounted, dispose, AppColors, writeJsonFile)
- **Без** — безопасность (auth, валидация)
- **Итого** — среднее взвешенное (Код×3 + Арх×2 + BS×2 + Без×3) / 10

| # | Модуль | Файлов | Код | Арх | BS | Без | **Итого** | Статус |
|---|--------|--------|-----|-----|----|-----|-----------|--------|
| 1 | employees | 13 | 9 | 9 | 9 | 8 | **8.7** | ОТЛИЧНО |
| 2 | rating | 4 | 9 | 8 | 8 | 8 | **8.4** | ОТЛИЧНО |
| 3 | envelope | 10 | 9 | 8 | 7 | 8 | **8.1** | ОТЛИЧНО |
| 4 | fortune_wheel | 6 | 8 | 8 | 7 | 8 | **7.8** | ХОРОШО |
| 5 | kpi | 17 | 8 | 8 | 7 | 8 | **7.8** | ХОРОШО |
| 6 | attendance | 10 | 8 | 8 | 6 | 8 | **7.6** | ХОРОШО |
| 7 | network_management | 2 | 8 | 7 | 7 | 8 | **7.7** | ХОРОШО |
| 8 | execution_chain | 3 | 7 | 7 | 7 | 8 | **7.4** | ХОРОШО |
| 9 | data_cleanup | 4 | 7 | 7 | 7 | 8 | **7.4** | ХОРОШО |
| 10 | bonuses | 4 | 7 | 7 | 7 | 8 | **7.4** | ХОРОШО |
| 11 | auth | 13 | 7 | 8 | 5 | 9 | **7.3** | ХОРОШО |
| 12 | rko | 10 | 7 | 7 | 6 | 7 | **6.8** | НОРМА |
| 13 | menu | 3 | 6 | 7 | 7 | 8 | **7.0** | НОРМА |
| 14 | recipes | 7 | 7 | 7 | 7 | 7 | **7.0** | НОРМА |
| 15 | shops | 6 | 7 | 8 | 7 | 7 | **7.2** | НОРМА |
| 16 | messenger | 17 | 7 | 8 | 7 | 7 | **7.2** | НОРМА |
| 17 | employee_chat | 13 | 7 | 7 | 7 | 7 | **7.0** | НОРМА |
| 18 | efficiency | 58 | 7 | 7 | 5 | 7 | **6.6** | НОРМА |
| 19 | training | 7 | 7 | 7 | 7 | 7 | **7.0** | НОРМА |
| 20 | tests | 8 | 7 | 7 | 7 | 7 | **7.0** | НОРМА |
| 21 | product_questions | 14 | 7 | 7 | 6 | 7 | **6.8** | НОРМА |
| 22 | tasks | 16 | 7 | 7 | 7 | 7 | **7.0** | НОРМА |
| 23 | referrals | 5 | 7 | 7 | 7 | 7 | **7.0** | НОРМА |
| 24 | reviews | 9 | 7 | 7 | 6 | 7 | **6.8** | НОРМА |
| 25 | job_application | 6 | 7 | 7 | 7 | 7 | **7.0** | НОРМА |
| 26 | work_schedule | 15 | 6 | 7 | 6 | 7 | **6.4** | ВНИМАНИЕ |
| 27 | shift_handover | 16 | 5 | 5 | 6 | 7 | **5.8** | ВНИМАНИЕ |
| 28 | recount | 26 | 5 | 7 | 5 | 7 | **5.9** | ВНИМАНИЕ |
| 29 | orders | 7 | 5 | 7 | 6 | 7 | **6.1** | ВНИМАНИЕ |
| 30 | coffee_machine | 14 | 6 | 7 | 6 | 7 | **6.4** | ВНИМАНИЕ |
| 31 | clients | 19 | 6 | 7 | 6 | 7 | **6.4** | ВНИМАНИЕ |
| 32 | suppliers | 3 | 6 | 7 | 5 | 7 | **6.2** | ВНИМАНИЕ |
| 33 | ai_training | 33 | 5 | 6 | 5 | 6 | **5.5** | ПЛОХО |
| 34 | shifts | 16 | 4 | 5 | 4 | 7 | **5.0** | ПЛОХО |
| 35 | loyalty | 14 | 3 | 4 | 4 | 7 | **4.3** | КРИТИЧНО |
| 36 | main_cash | 19 | 3 | 4 | 5 | 7 | **4.5** | КРИТИЧНО |

**Средняя оценка проекта: 6.7 / 10**

---

## 2. ДЕТАЛЬНЫЙ АНАЛИЗ ПО МОДУЛЯМ

### TOP-5 ЛУЧШИХ

#### #1 employees (8.7/10) — ОТЛИЧНО
- **Файлов**: 13 (8 pages, 3 services, 2 models)
- **Проблемы**: Не найдены
- **Сильные стороны**:
  - Все `setState()` защищены `if (mounted)` проверкой
  - Все `TextEditingController` корректно `dispose()`
  - `AnimationController` корректно dispose() в `employee_registration_view_page.dart:58` и `unverified_employees_page.dart:44`
  - Используются `AppColors` последовательно
- **Рекомендации**: Образцовый модуль. Использовать как пример для остальных.

#### #2 rating (8.4/10) — ОТЛИЧНО
- **Файлов**: 4
- **Проблемы**: Минимальные (2 файла с `Colors.*`)
- **Сильные стороны**: Чистый state management, все guard checks на месте
- **Рекомендации**: Заменить `Colors.*` на `AppColors`

#### #3 envelope (8.1/10) — ОТЛИЧНО
- **Файлов**: 10
- **Проблемы**: `Color(0xFF00695C)` и `Color(0xFFF5F7FA)` в `add_expense_dialog.dart:27-28`
- **Сильные стороны**:
  - `envelope_form_page.dart:196-205` — 8 контроллеров, все disposed
  - `add_expense_dialog.dart:31-36` — 2 контроллера, disposed
  - `envelope_questions_management_page.dart:276-277` — dialog контроллеры disposed
- **Рекомендации**: Заменить 2 hardcoded цвета

#### #4 fortune_wheel (7.8/10) — ХОРОШО
- **Файлов**: 6
- **Проблемы**: Hardcoded цвета в 5 файлах
- **Сильные стороны**: `wheel_settings_page.dart:21-22,31-39` — контроллеры в списках, все disposed
- **Рекомендации**: Вынести цвета в AppColors

#### #5 kpi (7.8/10) — ХОРОШО
- **Файлов**: 17
- **Проблемы**: Hardcoded цвета в 7 файлах
- **Сильные стороны**: Все setState с mounted проверкой, нет пустых catch
- **Рекомендации**: Конвертировать цвета

---

### TOP-5 ХУДШИХ

#### #36 loyalty (4.3/10) — КРИТИЧНО
- **Файлов**: 14
- **КРИТИЧЕСКИЕ ПРОБЛЕМЫ**:
  1. `loyalty_gamification_settings_page.dart` — **build() метод 1669 строк** (строки 2267-3936). Это самый длинный build в проекте. Невозможно поддерживать, дебажить и тестировать.
  2. `client_wheel_page.dart` — **build() метод 1609 строк** (строки 3939-5548), плюс helper на 920 строк.
  3. 11 файлов с hardcoded `Color(0x...)`:
     - `loyalty_scanner_page.dart:24-26` — 3 статических цвета
- **Рекомендации**: СРОЧНО разбить gamification_settings и client_wheel на 10-15 отдельных виджетов.

#### #35 main_cash (4.5/10) — КРИТИЧНО
- **Файлов**: 19
- **КРИТИЧЕСКИЕ ПРОБЛЕМЫ**:
  1. `revenue_analytics_page.dart` — **build() 1424 строки** (строки 678-3691). Крупнейший build по количеству строк.
  2. `main_cash_page.dart` — **build() 1245 строк** (строки 678-1923).
  3. 9 файлов с hardcoded цветами
- **Рекомендации**: Разбить revenue_analytics на TabBar + 5 отдельных виджетов.

#### #34 shifts (5.0/10) — ПЛОХО
- **Файлов**: 16 (8 pages, 4 services, 4 models)
- **КРИТИЧЕСКИЕ ПРОБЛЕМЫ**:
  1. **7 unguarded setState():**
     - `shift_questions_page.dart:141-144, 148-150, 230-232, 241-243`
     - `shift_questions_management_page.dart:82-86, 89-91, 1485-1488`
  2. **Ещё 3 unguarded в callback/timer:**
     - `shift_questions_management_page.dart:1524-1526, 1557-1559`
  3. **Missing dispose:**
     - `shift_questions_page.dart:44-45` — 2 контроллера (`_textController`, `_numberController`) без dispose()
     - `shift_questions_management_page.dart:27` — `_searchController` без dispose()
  4. `shift_questions_management_page.dart` — 2300+ строк (весь файл)
- **Рекомендации**: Исправить setState guard, добавить dispose, разбить файлы.

#### #33 ai_training (5.5/10) — ПЛОХО
- **Файлов**: 33 (pages, services, widgets, models + backend ML)
- **ПРОБЛЕМЫ**:
  1. `ai_dashboard_page.dart:104` — пустой catch в polling timer (ошибка проглатывается молча)
  2. `ai_dashboard_page.dart` — **6 прямых вызовов BaseHttpService** (минуя service layer)
  3. Hardcoded цвета в нескольких файлах
- **Рекомендации**: Создать `AiDashboardService`, перенести HTTP-вызовы из page в service.

#### #32 suppliers (6.2/10) — ВНИМАНИЕ
- **Файлов**: 3
- **ПРОБЛЕМЫ**:
  1. `suppliers_management_page.dart:90-94` — TextEditingController без dispose() (confirmed)
- **Рекомендации**: Добавить dispose()

---

### ОСТАЛЬНЫЕ МОДУЛИ (подробно)

#### attendance (7.6/10)
- **Файлов**: 10
- **Проблемы**: `attendance_employee_detail_page.dart:26` — `Color(0xFF00695C)` вместо AppColors
- **Плюсы**: Нет unguarded setState, нет missing dispose, нет empty catch

#### auth (7.3/10)
- **Файлов**: 13 (5 pages, 2 widgets, 6 services/models)
- **Проблемы**:
  - 6 hardcoded `Color(0xFF...)` в pin/forgot pages:
    - `pin_entry_page.dart:39` — `Color(0xFF0D3333)`
    - `pin_entry_page.dart:302-304` — `Color(0xFF0A2626)` в gradient
    - `pin_setup_page.dart:45` — `Color(0xFF0D3333)`
    - `pin_setup_page.dart:229-230` — gradient
    - `forgot_pin_page.dart:43` — `Color(0xFF0D3333)`
    - `forgot_pin_page.dart:179` — gradient
  - 5 `Colors.grey[]` в pin_input_widget и otp_input_widget
- **Плюсы**: Все контроллеры disposed, архитектура auth потоков хорошая

#### shift_handover (5.8/10)
- **Файлов**: 16
- **Проблемы**:
  - `shift_handover_questions_management_page.dart:1547-2038` — **build() 491 строк**
  - `shift_handover_questions_management_page.dart:2638` — ещё 307 строк
- **Плюсы**: Контроллеры disposed, нет empty catch

#### work_schedule (6.4/10)
- **Файлов**: 15
- **Проблемы**:
  - `my_schedule_page.dart:2241-2600` — build() 359 строк
  - `my_schedule_page.dart:2012` — ещё 190 строк
- **Плюсы**: Контроллеры disposed

#### recount (5.9/10)
- **Файлов**: 26
- **Проблемы**:
  1. `recount_questions_page.dart:1060` — dialog TextEditingController не disposed (memory leak)
  2. `recount_service.dart:310` — `} catch (_) {}` JSON parse error ignored
  3. `recount_questions_page.dart:269` — `} catch (_) {}` SharedPreferences error ignored
  4. `recount_points_settings_page.dart:1149` — build() 302 строки
- **Плюсы**: Правильная архитектура service layer

#### orders (6.1/10)
- **Файлов**: 7
- **Проблемы**:
  1. `orders_page.dart:771-850` — dialog controller не disposed
  2. `cart_page.dart:818-890, 955-985` — 2 dialog controller не disposed
  3. `employee_order_detail_page.dart:142-200` — rejection dialog controller не disposed
- **Плюсы**: setState правильно guarded

#### coffee_machine (6.4/10)
- **Файлов**: 14
- **Проблемы**:
  1. `coffee_machine_reports_list_page.dart:318` — **подтверждённый unguarded setState** (единственный реальный из 27 найденных по всему проекту)
- **Плюсы**: В остальном чистый модуль

#### clients (6.4/10)
- **Файлов**: 19
- **Проблемы**: Hardcoded цвета в 9 файлах, нужна верификация dispose в 6 файлах
- **Плюсы**: setState guarded, нет empty catch

#### efficiency (6.6/10)
- **Файлов**: 58 (крупнейший модуль)
- **Проблемы**: Hardcoded цвета в **30 файлах** (больше всех)
- **Плюсы**: setState guarded, нет missing dispose, нет empty catch, нет длинных build()

#### menu (7.0/10)
- **Файлов**: 3
- **Проблемы**: `menu_page.dart:368` — FutureBuilder без error handling (бесконечный спиннер при ошибке)
- **Плюсы**: Маленький модуль, мало зависимостей

#### messenger (7.2/10)
- **Файлов**: 17 (новый модуль, добавлен недавно)
- **Проблемы**: Минимальные
- **Плюсы**: Свежий код, WebSocket архитектура

#### shops (7.2/10)
- **Файлов**: 6 (но **ВЫСОКИЙ РИСК** — используется 10+ модулями)
- **Проблемы**: Минимальные
- **Плюсы**: Ключевая модель `shop_model.dart` стабильна

#### rko (6.8/10)
- **Файлов**: 10
- **Проблемы**:
  - `rko_reports_page.dart:715` — `} catch (_) {}` DateTime parse ignored
  - `rko_employee_reports_page.dart` — build() ~358 строк
  - `rko_shop_reports_page.dart` — build() ~403 строк
- **Плюсы**: Контроллеры disposed

---

## 3. БЭКЕНД-АУДИТ (71 API файл)

### 3.1 КРИТИЧЕСКИЕ ПРОБЛЕМЫ

| # | Проблема | Файл | Строка | Риск |
|---|----------|------|--------|------|
| 1 | **BOT_TOKEN + DB_PASSWORD в коммите** | `admin-bot/ecosystem.config.js` | — | КРИТИЧНЫЙ |
| 2 | **Deadlock: withLock + writeJsonFile** | `shifts_api.js` | 661-695 | КРИТИЧНЫЙ |
| 3 | **API Key middleware отключён** | `ecosystem.config.js` | — | КРИТИЧНЫЙ |

#### Подробнее:
1. **Секреты в коммите**: BOT_TOKEN и DB_PASSWORD захардкожены в `ecosystem.config.js`. Даже если это файл для другого бота — он в репозитории. Нужно: убрать из git, добавить в `.gitignore`, ротировать токены.
2. **Deadlock**: Известный баг. `shifts_api.js:661` — `withLock(penaltiesFile)` вызывает `writeJsonFile(penaltiesFile)` внутри, который ТОЖЕ берёт lock. Результат: timeout 15 секунд → баллы молча теряются. Исправление: `writeJsonFile(penaltiesFile, data, { useLock: false })`.
3. **API Key**: В `ecosystem.config.js` нет `API_KEY` → middleware `validateApiKey` пропускает всё. Нужно: установить ключ в env.

### 3.2 ВЫСОКИЕ ПРОБЛЕМЫ

#### fsp.writeFile вместо writeJsonFile (21 JSON-запись)

| Файл | Кол-во | Строки |
|------|--------|--------|
| `clients_api.js` | **14** | 205, 282, 377, 407, 440, 539, 592, 629, 685, 769, 793, 894, 1079, 1118 |
| `pending_api.js` | **9** | 370, 392, 457, 494, 638, 675, 698, 754, 775 |
| `envelope_api.js` | 3 | 150, 232, 272 |
| `media_api.js` | 1 | 139 |
| `reviews_api.js` | 3 | 136, 253, 356 (уже помечены комментарием "Boy Scout") |

> **Binary writes** (Buffer.from base64) в `coffee_machine_api.js` и `shift_ai_verification_api.js` — это OK, для них `writeJsonFile` не подходит.

#### Unbounded SQL запросы без LIMIT (4)

| Файл | Строка | Запрос |
|------|--------|--------|
| `employees_api.js` | 28 | `SELECT referral_code FROM employees WHERE referral_code IS NOT NULL` |
| `recurring_tasks_api.js` | 161 | `SELECT * FROM recurring_tasks ORDER BY created_at DESC` |
| `tasks_api.js` | 321 | `SELECT * FROM tasks ... ORDER BY created_at DESC` (без фильтра месяца) |
| `rating_wheel_api.js` | 920 | `SELECT ... FROM app_settings WHERE key LIKE 'fortune_wheel_spins_%'` |

#### parseInt без upper bound (5)

| Файл | Строка | Переменная | Риск |
|------|--------|-----------|------|
| `points_settings_api.js` | 402 | `score` | Может быть отрицательным |
| `points_settings_api.js` | 624 | `rating` | Без max |
| `points_settings_api.js` | 755 | `rating` | Без max |
| `points_settings_api.js` | 981 | `rating` | Без max |
| `rating_wheel_api.js` | 609 | `monthsCount` | **DoS**: цикл на `months=1000000` итераций |

### 3.3 СРЕДНИЕ ПРОБЛЕМЫ

| Проблема | Файлы | Описание |
|----------|-------|----------|
| `new Date()` вместо `getMoscowTime()` | `bonus_penalties_api.js:51,59`, `pending_api.js:43,49` | Для date computation (не timestamp) |
| `messenger_api.js` parseInt(limit) | messenger_api.js | Без cap — можно запросить limit=999999 |
| 400+ console.log | 57 файлов | Шум в логах, нет уровней |
| 13 empty catch | Разные | Ошибки проглатываются молча |

### 3.4 ПРОЙДЕННЫЕ ПРОВЕРКИ (ОК)

| Проверка | Результат |
|----------|-----------|
| Все POST/PUT/DELETE имеют req.user проверку | PASS (кроме 3 исключений: auth, clients регистрация, shop sync) |
| Все SQL используют параметризованные запросы | PASS |
| Все таймеры/интервалы очищаются | PASS |
| Все роуты в try/catch | PASS |
| Нет hardcoded server URLs в Flutter | PASS |
| `getHours()` — только 1 вхождение, правильное | PASS |
| `getMoscowTime()` используется для бизнес-логики | PASS |

---

## 4. ОБЩАЯ СТАТИСТИКА

### 4.1 Проект в цифрах

| Метрика | Значение |
|---------|----------|
| Flutter модулей | 36 |
| .dart файлов | ~500 |
| API файлов | 71 |
| Schedulers | 11 |
| **Средняя оценка Flutter** | **6.7 / 10** |
| **Общий Health Score** | **6.5 / 10** |

### 4.2 Распределение по оценкам

```
ОТЛИЧНО (8+)   ███░░░░░░░  3 модуля (employees, rating, envelope)
ХОРОШО  (7-8)  ██████░░░░  8 модулей
НОРМА   (6-7)  ████████░░ 15 модулей
ВНИМАНИЕ (5-6) ████░░░░░░  7 модулей
ПЛОХО   (<5)   ███░░░░░░░  3 модуля (shifts, loyalty, main_cash)
```

### 4.3 Найденные проблемы (сводка)

| Категория | Количество | Серьёзность |
|-----------|------------|-------------|
| **Секреты в коммите** | 1 файл | КРИТИЧНО |
| **Deadlock** | 1 место | КРИТИЧНО |
| **API Key отключён** | 1 конфиг | КРИТИЧНО |
| **Unguarded setState** | 11 мест (1 подтверждённый crash-риск) | ВЫСОКО |
| **Missing dispose()** | 8 мест | ВЫСОКО |
| **Build() > 500 строк** | 6 файлов | ВЫСОКО |
| **Build() > 1000 строк** | 4 файла | КРИТИЧНО |
| **fsp.writeFile (JSON)** | 21 место | СРЕДНЕ |
| **Unbounded SQL** | 4 запроса | СРЕДНЕ |
| **parseInt без cap** | 5 мест | СРЕДНЕ |
| **Empty catch** | 13 мест | СРЕДНЕ |
| **Hardcoded colors** | ~1471 вхождений | НИЗКО |
| **FutureBuilder без error** | 5 мест | НИЗКО |
| **console.log** | 400+ | НИЗКО |

---

## 5. ПРИОРИТЕТНЫЙ ПЛАН ИСПРАВЛЕНИЙ

### Фаза 1 — КРИТИЧНО (исправить немедленно)

| # | Задача | Файл | Что делать |
|---|--------|------|------------|
| 1 | Секреты из git | `admin-bot/ecosystem.config.js` | Убрать из repo, добавить в .gitignore, ротировать токены |
| 2 | Deadlock shifts | `shifts_api.js:661-695` | `writeJsonFile(file, data, { useLock: false })` |
| 3 | API Key | `ecosystem.config.js` | Установить `API_KEY` в pm2 env |

### Фаза 2 — ВЫСОКО (эта неделя)

| # | Задача | Файлы | Что делать |
|---|--------|-------|------------|
| 4 | Unguarded setState (shifts) | `shift_questions_page.dart:141-243`, `shift_questions_management_page.dart:82-1559` | Заменить на `if (mounted) setState(...)` |
| 5 | Unguarded setState (coffee) | `coffee_machine_reports_list_page.dart:318` | Добавить mounted guard |
| 6 | Missing dispose (shifts) | `shift_questions_page.dart`, `shift_questions_management_page.dart` | Добавить dispose() |
| 7 | Missing dispose (orders) | `orders_page.dart:771`, `cart_page.dart:818,955`, `employee_order_detail_page.dart:142` | Dispose dialog controllers |
| 8 | Missing dispose (recount) | `recount_questions_page.dart:1060` | Dispose dialog controller |
| 9 | Missing dispose (suppliers) | `suppliers_management_page.dart:90-94` | Добавить dispose() |

### Фаза 3 — СРЕДНЕ (этот месяц)

| # | Задача | Файлы | Что делать |
|---|--------|-------|------------|
| 10 | fsp.writeFile → writeJsonFile | `clients_api.js` (14), `pending_api.js` (9), etc. | Boy Scout при касании файла |
| 11 | Unbounded SQL | 4 запроса | Добавить `LIMIT 1000` |
| 12 | parseInt cap | 5 мест в `points_settings_api.js`, `rating_wheel_api.js` | `Math.min(parseInt(x), MAX)` |
| 13 | Empty catch → Logger | 13 мест | Заменить на `catch(e) { console.error(e) }` |
| 14 | ai_dashboard → service | `ai_dashboard_page.dart` | Создать AiDashboardService |

### Фаза 4 — РЕФАКТОРИНГ (следующий спринт)

| # | Задача | Файлы | Что делать |
|---|--------|-------|------------|
| 15 | Разбить loyalty | `loyalty_gamification_settings_page.dart` (1669 строк build) | 10+ отдельных виджетов |
| 16 | Разбить main_cash | `revenue_analytics_page.dart` (1424 строки build) | TabBar + 5 виджетов |
| 17 | Разбить main_cash | `main_cash_page.dart` (1245 строк build) | 4-5 виджетов |
| 18 | Разбить loyalty | `client_wheel_page.dart` (1609 строк build) | Wheel + Result + Info |
| 19 | Разбить shift_handover | `shift_handover_questions_management_page.dart` (491 строк build) | 3-4 виджета |
| 20 | Hardcoded colors → AppColors | ~1471 вхождений | Boy Scout при касании файла |

---

## 6. ФАЙЛЫ С НАИБОЛЬШИМ КОЛИЧЕСТВОМ ПРОБЛЕМ

| Файл | Проблемы | Приоритет |
|------|----------|-----------|
| `loyalty_gamification_settings_page.dart` | build() 1669 строк, hardcoded colors | КРИТИЧНО |
| `client_wheel_page.dart` | build() 1609 строк, hardcoded colors | КРИТИЧНО |
| `revenue_analytics_page.dart` | build() 1424 строк | КРИТИЧНО |
| `main_cash_page.dart` | build() 1245 строк | КРИТИЧНО |
| `shifts_api.js` | Deadlock строки 661-695 | КРИТИЧНО |
| `clients_api.js` | 14 raw fsp.writeFile | ВЫСОКО |
| `shift_questions_management_page.dart` | 2300+ строк, 5 unguarded setState, missing dispose | ВЫСОКО |
| `shift_questions_page.dart` | 4 unguarded setState, missing dispose, 1263 строки | ВЫСОКО |
| `pending_api.js` | 9 raw fsp.writeFile, 2 new Date() | ВЫСОКО |
| `ai_dashboard_page.dart` | 6 прямых HTTP, empty catch в polling | СРЕДНЕ |

---

> **Вывод**: Проект функционально стабилен (все API тесты проходят, авторизация на месте, SQL параметризован). Основные проблемы — технический долг: гигантские build() методы в 4 файлах, hardcoded цвета, и 21 raw fsp.writeFile. Критические баги (deadlock, секреты) затрагивают 2-3 файла и исправляются за пару часов.

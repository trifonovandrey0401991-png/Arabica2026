# Полный анализ приложения Arabica

**Дата:** 10 января 2026
**Версия:** v1.6.0-75percent

---

## КРИТИЧЕСКИЕ ПРОБЛЕМЫ (требуют немедленного исправления)

### 1. Tasks API не работает на сервере

**Статус:** КРИТИЧНО

**Проблема:** API endpoints `/api/tasks` и `/api/recurring-tasks` возвращают ошибку 404.

**Причина:** Файлы `tasks_api.js` и `recurring_tasks_api.js` находятся в папке `android/` вместо `loyalty-proxy/` и не задеплоены на сервер.

**Тест:**
```bash
curl -s "https://arabica26.ru/api/tasks"
# Результат: Cannot GET /api/tasks

curl -s "https://arabica26.ru/api/recurring-tasks"
# Результат: Cannot GET /api/recurring-tasks
```

**Решение:**
1. Переместить файлы в `loyalty-proxy/`:
   - `android/tasks_api.js` → `loyalty-proxy/tasks_api.js`
   - `android/recurring_tasks_api.js` → `loyalty-proxy/recurring_tasks_api.js`
2. Добавить в `index.js`:
   ```javascript
   const setupTasksAPI = require('./tasks_api');
   const setupRecurringTasksAPI = require('./recurring_tasks_api');
   // В конце файла:
   setupTasksAPI(app);
   setupRecurringTasksAPI(app);
   ```
3. Задеплоить на сервер

---

### 2. Расхождение локального и серверного кода

**Статус:** КРИТИЧНО

**Проблема:** Серверный `index.js` содержит подключения API модулей, которых нет в локальном файле.

**На сервере есть (строки 12-17):**
```javascript
const setupJobApplicationsAPI = require('./job_applications_api');
const setupRecountPointsAPI = require("./recount_points_api");
const setupRatingWheelAPI = require("./rating_wheel_api");
const setupReferralsAPI = require("./referrals_api");
```

**В локальном файле:** Эти строки отсутствуют!

**Решение:**
```bash
# Скачать актуальную версию с сервера
ssh root@arabica26.ru "cat /root/arabica_app/loyalty-proxy/index.js" > loyalty-proxy/index.js
```

---

### 3. JS файлы в неправильной папке

**Статус:** ВЫСОКИЙ

**Проблема:** 22 JavaScript файла находятся в папке `android/` вместо `loyalty-proxy/`.

**Список файлов в `android/`:**
- `tasks_api.js` - API задач (НЕ РАБОТАЕТ!)
- `recurring_tasks_api.js` - API периодических задач (НЕ РАБОТАЕТ!)
- `index_server.js` - устаревшая версия index.js
- `index_server_current.js` - ещё одна версия
- `efficiency_penalties_api.js`
- `pending_api.js`
- `product_questions_api.js`
- `shifts_api_server.js`
- И другие...

**Решение:**
1. Определить какие файлы актуальны
2. Переместить нужные в `loyalty-proxy/`
3. Удалить устаревшие

---

## РАБОТАЮЩИЕ API (проверено)

| API | Endpoint | Статус |
|-----|----------|--------|
| Ratings | `/api/ratings` | ✅ Работает |
| Fortune Wheel | `/api/fortune-wheel/settings` | ✅ Работает |
| Bonus Penalties | `/api/bonus-penalties` | ✅ Работает |
| Job Applications | `/api/job-applications` | ✅ Работает |
| Referrals | `/api/referrals/stats` | ✅ Работает |
| Recount Points | `/api/recount-points/settings` | ✅ Работает |
| Tasks | `/api/tasks` | ❌ НЕ РАБОТАЕТ |
| Recurring Tasks | `/api/recurring-tasks` | ❌ НЕ РАБОТАЕТ |

---

## СТРУКТУРА ПРОЕКТА

### Flutter (lib/)

| Категория | Файлов | Строк |
|-----------|--------|-------|
| features/ | ~200 | 91,641 |
| app/ | 10 | ~3,000 |
| core/ | 15 | ~2,500 |
| shared/ | 20 | ~3,000 |
| **ВСЕГО** | ~245 | ~100,000 |

### Features (30 модулей):
- attendance, bonuses, clients, efficiency, employee_chat
- employees, envelope, fortune_wheel, job_application, kpi
- loyalty, main_cash, menu, orders, product_questions
- rating, recipes, recount, referrals, reviews
- rko, shift_handover, shifts, shops, suppliers
- tasks, tests, training, work_schedule

### Сервисы (61 класс):
- AttendanceService, BonusPenaltyService, ClientService...
- EfficiencyDataService, FortuneWheelService, RatingService...
- TaskService, RecurringTaskService и другие

### Серверный код (loyalty-proxy/)

| Файл | Строк | Статус |
|------|-------|--------|
| index.js | ~4,300 | Основной файл |
| rating_wheel_api.js | 685 | Подключён |
| recount_points_api.js | 490 | Подключён |
| referrals_api.js | 460 | Подключён |
| job_applications_api.js | 200 | Подключён |

---

## ПРОБЛЕМЫ АРХИТЕКТУРЫ

### 1. Гигантские файлы

| Файл | Строк | Рекомендация |
|------|-------|--------------|
| points_settings_page.dart | 3,663 | Разбить на компоненты |
| shift_handover_questions_management_page.dart | 1,771 | Вынести виджеты |
| work_schedule_page.dart | 1,540 | Разбить логику |
| my_schedule_page.dart | 1,496 | Декомпозиция |
| index.js (сервер) | 4,300 | Модуляризация |

### 2. Отсутствие централизации

**Проблема:** SharedPreferences используется напрямую в 30+ файлах.

**Пример дублирования:**
```dart
// В 30+ файлах:
final prefs = await SharedPreferences.getInstance();
final employeeName = prefs.getString('employeeName');
```

**Решение:** Создать `UserPreferencesService`:
```dart
class UserPreferencesService {
  static Future<String?> getEmployeeName() async {...}
  static Future<String?> getEmployeeId() async {...}
  static Future<void> setEmployeeName(String name) async {...}
}
```

### 3. Прямые API вызовы в UI

**Проблема:** Некоторые страницы делают HTTP запросы напрямую вместо использования сервисов.

**Файлы с прямыми вызовами:**
- `shops_management_page.dart` (строки 69, 89)
- `work_schedule_page.dart` (строка 322)
- `employee_schedule_page.dart` (строка 86)
- `abbreviation_selection_dialog.dart` (строка 59)

### 4. Хардкод URL

**Проблема:** В `recount_points_service.dart` используется хардкод URL:
```dart
static const String _baseUrl = 'https://arabica26.ru/api';
```

**Решение:** Использовать `ApiConstants.serverUrl` как в других сервисах.

---

## TODO КОММЕНТАРИИ

| Файл | Строка | Комментарий |
|------|--------|-------------|
| data_management_page.dart | 210 | Логика будет добавлена позже |
| reports_page.dart | 354 | Логика будет добавлена позже |
| schedule_bulk_operations_dialog.dart | 359 | Реализовать удаление шаблона |
| efficiency_data_service.dart | 38 | Добавить загрузку остальных источников |
| shift_handover_reports_list_page.dart | 688 | check actual admin status |
| employee_panel_page.dart | 427 | Логика будет добавлена позже |
| review_detail_page.dart | 79 | Отправить push-уведомление |

---

## ОБРАБОТКА ОШИБОК

**Проблема:** 55 файлов используют `catch (e) { print(...) }` без proper error handling.

**Рекомендация:** Создать централизованный ErrorHandler:
```dart
class ErrorHandler {
  static void handle(dynamic error, {String? context}) {
    // Логирование
    // Показ пользователю (если нужно)
    // Отправка в аналитику
  }
}
```

---

## ДУБЛИРУЮЩИЙСЯ КОД

### 1. Загрузка employeeId

В 9 местах вызывается `EmployeesPage.getCurrentEmployeeId()`:
- main_menu_page.dart
- employee_panel_page.dart (4 раза)
- my_schedule_page.dart
- employees_page.dart (2 раза)

### 2. Парсинг JSON

Одинаковый код `.toDouble()` в 70+ местах моделей.

### 3. Настройки баллов

`points_settings_page.dart` содержит 8 почти идентичных секций для разных категорий.

---

## РЕКОМЕНДАЦИИ ПО ПРИОРИТЕТАМ

### Срочно (сделать сейчас):

1. **Исправить Tasks API:**
   - Переместить файлы из `android/` в `loyalty-proxy/`
   - Подключить в index.js
   - Задеплоить

2. **Синхронизировать код:**
   - Скачать index.js с сервера
   - Закоммитить актуальную версию

### Важно (на этой неделе):

3. **Очистить папку `android/`:**
   - Удалить устаревшие JS файлы
   - Организовать структуру

4. **Исправить хардкод URL:**
   - В `recount_points_service.dart`

### Улучшения (позже):

5. **Создать UserPreferencesService**
6. **Разбить большие файлы**
7. **Централизовать обработку ошибок**
8. **Убрать прямые API вызовы из UI**

---

## ИТОГ

| Метрика | Значение |
|---------|----------|
| Критических проблем | 3 |
| Работающих API | 6 из 8 |
| TODO комментариев | 7 |
| Файлов с print-обработкой ошибок | 55 |
| Гигантских файлов (>1000 строк) | 10 |
| Всего строк Flutter кода | ~100,000 |
| Всего строк серверного кода | ~6,000 |

**Общая оценка:** Приложение работает, но требует:
1. Срочного исправления Tasks API
2. Синхронизации кода
3. Постепенного рефакторинга

---

*Отчёт сгенерирован Claude Code*

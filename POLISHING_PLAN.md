# ПЛАН ПОЛИРОВКИ — Arabica 2026

> **Метод**: Boy Scout Rule + Rule of Three
> **Принцип**: Улучшай только то, что трогаешь. Обобщай только то, что повторяется 3+ раз.
> **Дата анализа**: 16.02.2026 (на основе реального кода, не документации)

---

## ПРАВИЛА КОДА

### Flutter — Обязательные правила

| # | Правило | Пример |
|---|---------|--------|
| F-01 | Цвета ТОЛЬКО через тему (создать `lib/core/theme/`) | `Theme.of(context).primaryColor` вместо `Color(0xFF1A4D4D)` |
| F-02 | `setState` ТОЛЬКО внутри `if (mounted)` | `if (mounted) setState(() { ... });` |
| F-03 | Любой `async` callback → проверка `mounted` перед setState | После `await` всегда `if (!mounted) return;` |
| F-04 | Фото через `pickImage` ВСЕГДА с `maxWidth: 1280, imageQuality: 75` | Без исключений — экономит 80% трафика |
| F-05 | Новые страницы: если уже есть 3+ похожих → scaffold/базовый класс | Rule of Three |
| F-06 | `AppCachedImage` для всех сетевых изображений | Уже выполнено (83 использования) |
| F-07 | Размер файла: максимум 500 строк на страницу | Выносить виджеты в отдельные файлы |
| F-08 | Константы — в отдельный файл, не хардкод | URL, размеры, тексты |

### Backend — Обязательные правила

| # | Правило | Пример |
|---|---------|--------|
| B-01 | Запись файлов ТОЛЬКО через `writeJsonFile` из `async_fs.js` | Атомарная запись: temp → rename |
| B-02 | Каждый шедулер ОБЯЗАН иметь `isRunning` guard | `if (isRunning) return; isRunning = true; try { ... } finally { isRunning = false; }` |
| B-03 | Каждый API-эндпоинт ОБЯЗАН проверять `req.user` | Кроме публичных (auth, job_application, loyalty scan) |
| B-04 | Утилиты (`getMoscowTime`, `sanitizeId` и т.д.) — ТОЛЬКО импорт из `utils/` | Нельзя копировать в каждый файл |
| B-05 | Все шедулеры — `setTimeout` при старте (5-15 сек задержка) | Чтобы сервер успел инициализироваться |
| B-06 | Время — ТОЛЬКО через `getMoscowTime()` или `getUTCHours() + 3` | Нельзя использовать голый `getHours()` |
| B-07 | Пагинация — Flutter ОБЯЗАН отправлять `?page=1` | Сервер не должен возвращать ВСЕ записи |
| B-08 | Новые файлы: если уже есть 3+ похожих → базовый класс/функция | Rule of Three |

### Запреты

| # | Нельзя | Почему |
|---|--------|--------|
| X-01 | Менять архитектуру хранения (flat-file JSON) | Работает, переход на БД = переписать всё |
| X-02 | Менять `setState` на другой state management | 1,570 использований, слишком рискованно |
| X-03 | Менять структуру папок `lib/features/` | Все 35 модулей уже организованы |
| X-04 | Трогать рабочий код без задачи | ГЛАВНОЕ ПРАВИЛО проекта |
| X-05 | Добавлять новые npm/pub зависимости без согласования | Каждая зависимость = риск |

---

## ФАЗА 0: КРИТИЧЕСКИЕ БАГИ (делать первым)

> Это реальные баги, найденные в коде. Без их исправления сервер нестабилен.

### 0.1 — Overlap protection для 8 шедулеров
**Риск**: 🔴 Потеря/повреждение отчётов
**Проблема**: Ни один из 8 шедулеров не проверяет, завершился ли предыдущий запуск. Если обработка занимает больше интервала — два процесса пишут в одни файлы одновременно.
**Файлы**:
- `loyalty-proxy/api/shift_automation_scheduler.js`
- `loyalty-proxy/api/recount_automation_scheduler.js`
- `loyalty-proxy/api/rko_automation_scheduler.js`
- `loyalty-proxy/api/shift_handover_automation_scheduler.js`
- `loyalty-proxy/api/attendance_automation_scheduler.js`
- `loyalty-proxy/api/envelope_automation_scheduler.js`
- `loyalty-proxy/api/coffee_machine_automation_scheduler.js`
- `loyalty-proxy/api/product_questions_penalty_scheduler.js`

**Решение**: Добавить в КАЖДЫЙ шедулер:
```javascript
let isRunning = false;

async function processReports() {
  if (isRunning) {
    console.log('[scheduler-name] Previous run still active, skipping');
    return;
  }
  isRunning = true;
  try {
    // ... существующий код ...
  } catch (err) {
    console.error('[scheduler-name] Error:', err.message);
  } finally {
    isRunning = false;
  }
}
```

### 0.2 — Auth проверки в 8 API-файлах
**Риск**: 🔴 Безопасность — любой с API-ключом может менять данные
**Проблема**: Эти файлы НЕ проверяют `req.user` (кто делает запрос):
- `loyalty-proxy/api/bonus_penalties_api.js`
- `loyalty-proxy/api/training_api.js`
- `loyalty-proxy/api/shops_api.js`
- `loyalty-proxy/api/work_schedule_api.js`
- `loyalty-proxy/api/rko_api.js`
- `loyalty-proxy/api/menu_api.js`
- `loyalty-proxy/api/withdrawals_api.js`
- `loyalty-proxy/api/points_settings_api.js`

**Решение**: Добавить проверку `req.user` в каждый endpoint, который изменяет данные (POST/PUT/DELETE). GET-эндпоинты можно оставить без проверки. Пример из `data_cleanup_api.js` (уже правильно сделано):
```javascript
router.post('/cleanup', isAdmin, async (req, res) => { ... });
```

### 0.3 — Баг getHours() в shift_handover
**Риск**: 🟠 Неправильное время → отчёты попадают в неправильный день
**Файл**: `loyalty-proxy/api/shift_handover_automation_scheduler.js`, строка ~270
**Проблема**: Используется голый `getHours()` — это системное время сервера (может быть UTC), а не московское.
**Решение**: Заменить на `getMoscowTime().getHours()` или `(date.getUTCHours() + 3) % 24`

### 0.4 — Startup delay для 2 шедулеров
**Риск**: 🟡 При pm2 restart шедулеры стартуют до готовности сервера
**Файлы**:
- `loyalty-proxy/api/envelope_automation_scheduler.js` — нет setTimeout
- `loyalty-proxy/api/coffee_machine_automation_scheduler.js` — нет setTimeout
**Решение**: Обернуть инициализацию в `setTimeout(() => { ... }, 10000)` как в остальных 6 шедулерах.

---

## ФАЗА 1: СТАБИЛЬНОСТЬ СЕРВЕРА

> Защита от падений при росте данных и нагрузки.

### 1.1 — Безопасная запись файлов в API
**Проблема**: Шедулеры используют безопасный `writeJsonFile` (атомарная запись), но некоторые API-файлы используют сырой `fsp.writeFile` (при сбое = потеря файла).
**Файлы с проблемой**:
- `loyalty-proxy/api/geofence_api.js`
- `loyalty-proxy/api/order_timeout_api.js`
- `loyalty-proxy/api/recurring_tasks_api.js`
- `loyalty-proxy/api/report_notifications_api.js`
**Решение**: Заменить `fsp.writeFile` на `writeJsonFile` из `utils/async_fs.js`

### 1.2 — getMoscowTime() → общая утилита
**Проблема**: Функция `getMoscowTime()` скопирована в 7 файлах шедулеров (идентичный код × 7).
**Решение**:
1. Создать `loyalty-proxy/utils/moscow_time.js` с единой функцией
2. В каждом шедулере заменить локальную копию на `const { getMoscowTime } = require('../utils/moscow_time')`

### 1.3 — Пагинация: обязательная отправка page из Flutter
**Проблема**: Если Flutter не отправляет `?page=`, сервер возвращает ВСЕ записи. Даже с пагинацией — все файлы читаются с диска, потом нарезаются в памяти.
**Решение (поэтапно)**:
1. **Сначала**: Flutter — добавить `?page=1&limit=50` во ВСЕ запросы списков
2. **Потом**: Сервер — дефолтная пагинация (page=1, limit=50) если параметры не переданы
3. **В будущем**: Индексные файлы вместо чтения всех файлов

### 1.4 — Расширить data_cache
**Проблема**: `data_cache.js` кэширует только employees + shops (2 из 35+ модулей). Остальные модули читают файлы с диска на КАЖДЫЙ запрос.
**Решение**: Добавить кэширование для частых запросов:
- Настройки точек (points_settings) — читаются на каждом экране эффективности
- Список магазинов (shops) — уже кэшируется
- Шаблоны вопросов (questions) — одинаковые для всех сотрудников

### 1.5 — Серверное сжатие фото
**Проблема**: 9 multer upload handlers принимают фото как есть. Sharp установлен, но используется ТОЛЬКО для OCR. Фото с камеры занимают 5-10 МБ каждое.
**Решение**: После multer upload добавить middleware:
```javascript
const sharp = require('sharp');
async function compressUpload(req, res, next) {
  if (req.file && req.file.mimetype.startsWith('image/')) {
    const compressed = await sharp(req.file.path)
      .resize(1920, 1920, { fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: 80 })
      .toBuffer();
    await fsp.writeFile(req.file.path, compressed);
  }
  next();
}
```

### 1.6 — Очистка chat-media
**Проблема**: `data_cleanup_api.js` чистит 6 категорий (shifts, handover, envelope, recount, rko, coffee-machine), но **chat-media НЕ включена**. Фото чатов копятся бесконечно.
**Решение**: Добавить категорию `chat-media` в data_cleanup_api.js

---

## ФАЗА 2: FLUTTER — СТАБИЛЬНОСТЬ

> Предотвращение крашей и утечек памяти.

### 2.1 — mounted guard для setState
**Проблема**: 1,570 вызовов setState, из них ~844 БЕЗ проверки `if (mounted)`. Краш при переходе между экранами если async-операция завершается после dispose.
**Правило (Boy Scout)**: При работе с ЛЮБЫМ файлом — проверить все setState в нём и добавить `if (mounted)` где отсутствует.
**Шаблон**:
```dart
// БЫЛО:
final data = await api.loadData();
setState(() { _data = data; });

// СТАЛО:
final data = await api.loadData();
if (!mounted) return;
setState(() { _data = data; });
```

### 2.2 — Сжатие фото в 3 страницах задач
**Проблема**: Эти страницы используют `pickImage` без параметров качества — загружают полноразмерные фото (5-10 МБ):
- `lib/features/tasks/pages/task_response_page.dart`
- `lib/features/tasks/pages/recurring_task_response_page.dart`
- `lib/features/tasks/pages/create_task_page.dart`
**Решение**: Добавить `maxWidth: 1280, imageQuality: 75` в вызовы pickImage

### 2.3 — Web-платформа: сжатие фото
**Проблема**: `PhotoUploadService` сжимает фото на мобильном (>500KB → 1280px, JPEG q75), но на web пропускает сжатие полностью.
**Решение**: Добавить web-сжатие через canvas API или пакет `image` для web

### 2.4 — Главное меню: 12 API-вызовов при открытии
**Файл**: `lib/app/pages/main_menu_page.dart`
**Проблема**: При открытии главного меню делается 12 отдельных HTTP-запросов.
**Решение**: Использовать существующий `dashboard_batch_api.js` — один запрос вместо 12.

---

## ФАЗА 3: BACKEND DRY (убрать дублирование)

> Применяем Rule of Three — эти паттерны повторяются 7-8 раз.

### 3.1 — BaseReportScheduler
**Проблема**: 8 шедулеров содержат ~95% одинакового кода (~700 строк × 8 = ~5,600 строк дублирования):
- Чтение конфигов → проверка времени → поиск pending → генерация отчёта → уведомление
**Решение**: Создать `loyalty-proxy/utils/base_report_scheduler.js`:
```javascript
class BaseReportScheduler {
  constructor({ name, dataDir, pendingDir, stateDir, configDir, intervalMs }) { ... }
  // Общая логика: isRunning guard, getMoscowTime, loadConfigs, findPending, saveFinalReport, sendPush
  // Абстрактные методы для переопределения:
  // - buildReport(pending, config) → reportData
  // - getReportFileName(date, shopId) → string
}
```
Каждый конкретный шедулер: ~50-100 строк вместо ~700.

### 3.2 — Вынести дублированные утилиты из API-файлов
**Проблема**: Многие API-файлы определяют ЛОКАЛЬНЫЕ копии функций вместо импорта из `utils/`:
- `sanitizeId()` — копии в нескольких файлах
- `fileExists()` — копии в нескольких файлах
- `getMoscowTime()` — 7 копий в шедулерах
**Решение**: При работе с файлом (Boy Scout Rule) — заменить локальную копию на импорт из `utils/file_helpers.js`

---

## ФАЗА 4: FLUTTER DRY (убрать дублирование)

> Применяем Rule of Three — только для паттернов с 3+ копиями.

### 4.1 — Централизовать тему (цвета)
**Проблема**:
- `Color(0xFF1A4D4D)` → 128 файлов
- `Color(0xFF0D2E2E)` → 116 файлов
- `Color(0xFF004D40)` → 70 файлов
**Решение**:
1. Создать `lib/core/theme/app_colors.dart`:
```dart
class AppColors {
  static const darkEmerald = Color(0xFF1A4D4D);
  static const deepDark = Color(0xFF0D2E2E);
  static const teal = Color(0xFF004D40);
  // ... остальные цвета
}
```
2. Применять по Boy Scout Rule: при работе с файлом заменять хардкод на `AppColors.xxx`

### 4.2 — Scaffold для страниц настроек баллов (15 страниц)
**Файлы**: `lib/features/efficiency/pages/settings_tabs/*_points_settings_page.dart` (15 файлов)
**Проблема**: 15 почти идентичных страниц настроек баллов. Каждая ~150-250 строк.
**Решение**: Создать `GenericPointsSettingsScaffold` с параметрами:
- Название модуля
- Список настроек (слайдеры, переключатели)
- API endpoint для сохранения

### 4.3 — Scaffold для страниц управления вопросами (7 страниц)
**Файлы**: `*_questions_management_page.dart` (shift, handover, envelope, recount, coffee_machine, product_questions, test)
**Проблема**: 7 страниц с одинаковой логикой: загрузить список → добавить/удалить/переупорядочить
**Решение**: `QuestionsManagementScaffold` с параметрами (тип вопроса, API-эндпоинт)

### 4.4 — Scaffold для страниц списка отчётов (7 страниц)
**Файлы**: `*_reports_list_page.dart` (shift, handover, envelope, recount, rko, coffee_machine, product_questions)
**Проблема**: 7 страниц с одинаковой логикой: фильтр по дате/магазину → список отчётов → детали
**Решение**: `ReportListScaffold` с параметрами (API-endpoint, поля отчёта, виджет деталей)

### 4.5 — Scaffold для страниц выбора магазина (6 страниц)
**Файлы**: `*_shop_selection_page.dart` (shift, handover, recount, review, product_questions, attendance)
**Проблема**: 6 одинаковых страниц: загрузить магазины → показать список → выбрать → перейти
**Решение**: `ShopSelectionScaffold` с параметром `onShopSelected`

### 4.6 — Разбить крупные файлы
**Проблема**:
- `cigarette_training_page.dart` — 4,002 строки
- `work_schedule_page.dart` — 2,949 строк
**Решение**: Вынести внутренние виджеты в отдельные файлы `widgets/`. Делать при работе с файлом (Boy Scout Rule), не специально.

---

## ФАЗА 5: МОНИТОРИНГ И ЗАЩИТА

### 5.1 — Health endpoint
**Решение**: Добавить `GET /api/health` который возвращает:
```json
{
  "status": "ok",
  "uptime": 123456,
  "memory": { "used": "180MB", "total": "2048MB" },
  "disk": { "used": "1.2GB", "free": "18GB" },
  "schedulers": { "shift": "running", "recount": "running", ... },
  "lastErrors": []
}
```

### 5.2 — Автоочистка старых фото по расписанию
**Проблема**: Фото-директории растут бесконечно. Ручная очистка через data_cleanup_api — только по запросу.
**Решение**: Добавить cron-задачу или шедулер для автоочистки фото старше N дней (настраиваемо).

### 5.3 — Логирование ошибок шедулеров
**Проблема**: Ошибки шедулеров идут в pm2 logs и теряются при ротации.
**Решение**: Писать ошибки в файл `/var/www/scheduler-errors/YYYY-MM-DD.json` для анализа.

---

## ПОРЯДОК ВЫПОЛНЕНИЯ

```
ФАЗА 0 → ФАЗА 1 → ФАЗА 2 → ФАЗА 3 → ФАЗА 4 → ФАЗА 5
 баги    сервер    Flutter    backend    Flutter    мониторинг
                  стабильн.    DRY        DRY
```

**Boy Scout Rule применяется ВСЕГДА**: при работе с любым файлом в рамках другой задачи — попутно исправляем:
- Добавляем `if (mounted)` к setState
- Заменяем хардкод цветов на `AppColors.xxx`
- Заменяем локальные утилиты на импорт из `utils/`
- Добавляем `req.user` проверку если отсутствует

---

## ЧТО УЖЕ СДЕЛАНО (не трогать)

| Пункт | Статус |
|-------|--------|
| Миграция `Image.network` → `AppCachedImage` | ✅ Готово (83 использования, 0 старых) |
| `dashboard_batch_api.js` создан | ✅ Существует и подключён |
| `print()` убран из кода | ✅ Только в logger.dart (7 шт) |
| Flutter сжатие фото на мобильном | ✅ PhotoUploadService: >500KB → 1280px, q75 |
| `BaseReportService<T>` для Flutter | ✅ 153 строки, используется модулями отчётов |
| `data_cache` для employees + shops | ✅ Работает, обновление каждые 5 мин |
| `file_lock.js` с withLock | ✅ Существует (30s lock, 15s operation timeout) |
| Rate limiting в index.js | ✅ 500/мин общий, 10/мин auth, 50/мин финансы |

---

## МЕТРИКИ ДО ПОЛИРОВКИ (замерено 16.02.2026)

| Метрика | Значение |
|---------|----------|
| setState без mounted guard | ~844 из 1,570 |
| Хардкод цветов (файлов) | 128 + 116 + 70 |
| Шедулеры без overlap protection | 8 из 8 |
| API без проверки req.user | 8 файлов |
| Копии getMoscowTime | 7 |
| API с сырым fsp.writeFile | 4 файла |
| Файлы >1000 строк | 2 (4002 и 2949) |
| pickImage без сжатия | 3 страницы |
| Модули без серверного кэша | ~33 из 35 |

---

## НАПОМИНАНИЕ

```
ЕСЛИ КОД РАБОТАЕТ — НЕ ТРОГАЙ ЕГО БЕЗ ЗАДАЧИ

Приоритеты:
1. НЕ СЛОМАТЬ
2. Сделать что просят
3. Сделать правильно
4. Сделать красиво (если просят)
```

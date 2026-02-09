# ПОЛНЫЙ АУДИТ ARABICA2026 — 12 ФАЗ

**Дата:** 9 февраля 2026
**Версия аудита:** v2.0 (12-фазный полный аудит)
**Проверено:** 67 API файлов, 8 schedulers, 36 Flutter модулей, 194 страницы, 82 сервиса, 68 моделей

---

## DASHBOARD

```
┌─────────────────────────────────────────────────┐
│            СВОДКА АУДИТА ARABICA2026            │
├───────────────────┬─────────────────────────────┤
│ 🔴 Критические    │ 12 проблем                  │
│ 🟠 Важные         │ 24 проблемы                 │
│ 🟡 Улучшения      │ 18 рекомендаций             │
│ 🟢 Оптимизации    │ 8 предложений               │
├───────────────────┼─────────────────────────────┤
│ ✅ Модулей ОК     │ 28 / 36                     │
│ ⚠️ Модулей с      │ 8 / 36                      │
│    проблемами     │                             │
├───────────────────┼─────────────────────────────┤
│ Архитектура       │ 9/10 ✅                     │
│ Безопасность      │ 5/10 ⚠️                     │
│ Потоки данных     │ 6/10 ⚠️                     │
│ Обработка ошибок  │ 5/10 ⚠️                     │
│ Производительность│ 6/10 ⚠️                     │
│ Надёжность        │ 6/10 ⚠️                     │
│ Качество кода     │ 6/10 ⚠️                     │
│ Масштабируемость  │ 4/10 ❌                     │
│ UX                │ 8/10 ✅                     │
│ Тесты             │ 2/10 ❌                     │
├───────────────────┼─────────────────────────────┤
│ ОБЩАЯ ОЦЕНКА      │ 5.7/10                      │
└───────────────────┴─────────────────────────────┘
```

---

## TOP-10 ПРОБЛЕМ (по влиянию на продакшн)

| # | Приоритет | Проблема | Файл | Влияние |
|---|-----------|----------|------|---------|
| 1 | 🔴 | **Timezone баг — `getHours()` вместо UTC+3** в 5 API | `attendance_api.js:76`, `shifts_api.js:200,579`, `pending_api.js:148`, `order_timeout_api.js:79` | Пересменки/посещения отклоняются как TIME_EXPIRED |
| 2 | 🔴 | **IDOR — нет проверки владельца данных** | `shifts_api.js`, `envelope_api.js`, `recount_api.js` | Любой сотрудник может просмотреть/изменить чужие отчёты |
| 3 | 🔴 | **Нет авторизации на CRUD employees** | `employees_api.js:130,186,248` | Сотрудник может создать/изменить/удалить любого + дать себе isAdmin |
| 4 | 🔴 | **6 пустых catch блоков** `catch (e) {}` | `employees_api.js:31`, `recount_api.js:98`, `rko_api.js:639`, `attendance_api.js:701`, `shifts_api.js:309,364` | Повреждённые JSON не обнаруживаются, данные молча теряются |
| 5 | 🔴 | **Незащищённый JSON.parse() в scheduler-ах** | `coffee_machine_automation_scheduler.js`, `envelope_automation_scheduler.js`, `attendance_automation_scheduler.js` | Один повреждённый файл валит scheduler |
| 6 | 🔴 | **Hardcoded Google Apps Script URL с токеном** | `index.js:532`, `recount_api.js:15` | Токен скрипта виден в коде |
| 7 | 🔴 | **Тесты — 90% placeholder-ы** `expect(true, true)` | `test/` (29 файлов) | Нет реальных тестов |
| 8 | 🔴 | **0 серверных тестов** | `loyalty-proxy/` | 67 API + 8 schedulers без единого теста |
| 9 | 🟠 | **30-дневные сессии** без refresh | `auth_api.js:29` | Украденный токен действует месяц |
| 10 | 🟠 | **efficiency_calc.js — до 500K+ файловых чтений** | `efficiency_calc.js:69-358` | При 100+ магазинах расчёт займёт 8-15 секунд |

---

## ФАЗА 1: АРХИТЕКТУРНАЯ ЦЕЛОСТНОСТЬ — 9/10 ✅

**Статус: ОТЛИЧНО с мелкими замечаниями**

### Инвентаризация

| Метрика | Количество |
|---------|-----------|
| Flutter модулей (features/) | 36 (35 документировано + execution_chain) |
| Файлов страниц (pages/) | 194 |
| Файлов сервисов (services/) | 82 |
| Файлов моделей (models/) | 68 |
| API файлов (server) | 67 |
| setupAPI() вызовов | 56 |
| API констант (Dart) | 47 |
| Навигационных маршрутов | 48 |

### Проблемы

| # | 🔴/🟡 | Файл | Проблема | Исправление |
|---|--------|------|----------|-------------|
| A-1 | 🟡 | `ARCHITECTURE_COMPLETE.md` | Модуль execution_chain не документирован | Добавить в раздел 4 |
| A-2 | 🟡 | `api_constants.dart` | Нет `coffeeMachineEndpoint` константы | Добавить `static const String coffeeMachineEndpoint = '/api/coffee-machine';` |
| A-3 | 🟡 | `api_constants.dart:69-70` | `shiftHandoverPendingEndpoint`/`FailedEndpoint` — нечёткий маршрут | Уточнить в документации |

### Что хорошо
- Все 36 модулей имеют правильную структуру pages/services/models
- 91% API констант совпадают с backend маршрутами
- Навигация полная — нет orphan-страниц
- Чёткое разделение ответственности

---

## ФАЗА 2: БЕЗОПАСНОСТЬ — 5/10 ⚠️

### Ранее исправлено (09.02 v1)
- ✅ API ключ вынесен из кода → `api_key.dart` (gitignored)
- ✅ API key auth включён по умолчанию
- ✅ Глобальный auth middleware на POST/PUT/DELETE/PATCH
- ✅ pinHash/salt удалены из ответа регистрации
- ✅ WebSocket auth обязательна
- ✅ Upload-photo убран из publicPaths
- ✅ Rate limiting на auth endpoints (10/мин)

### Новые находки (v2)

| # | Приоритет | Файл:строка | Проблема | Исправление | Влияние |
|---|-----------|-------------|----------|-------------|---------|
| S-1 | 🔴 | `employees_api.js:130,186,248` | POST/PUT/DELETE employees без requireAdmin — любой может создать/удалить сотрудника | Добавить `if (!req.user?.isAdmin) return res.status(403)` | Privilege escalation |
| S-2 | 🔴 | `shifts_api.js`, `envelope_api.js`, `recount_api.js` | IDOR — нет проверки что пользователь владеет данными | Добавить `if (report.employeePhone !== req.user.phone && !req.user.isAdmin)` | Утечка данных |
| S-3 | 🔴 | `index.js:532`, `recount_api.js:15` | Hardcoded Google Apps Script URL с токеном `AKfycbz...` | Перенести в `process.env.SCRIPT_URL`, удалить fallback | Несанкционированные запросы |
| S-4 | 🟠 | `auth_api.js:29` | `SESSION_LIFETIME_MS = 30 * 24 * 60 * 60 * 1000` (30 дней) | Сократить до 1 дня + refresh token | Украденный токен действует месяц |
| S-5 | 🟠 | `index.js:537` | `console.log("Request body:", JSON.stringify(req.body))` — чувствительные данные в логах | Удалить или sanitize: `delete safeBody.pin` | Пароли/PIN в логах |
| S-6 | 🟠 | helmet config | Нет HSTS заголовков | Добавить `hsts: { maxAge: 31536000, includeSubDomains: true }` | MITM возможен |
| S-7 | 🟠 | auth_api.js | PIN lockout без file locking — race condition | Использовать `withLock('pin_' + phone, ...)` | Brute-force обход lockout |
| S-8 | 🟡 | `index.js:319-365` | Rate limit только per-IP, нет per-user | Добавить `keyGenerator: (req) => req.user?.phone || req.ip` | 500 req/min на пользователя |
| S-9 | 🟡 | `index.js:234` | CORS: `if (!origin) return callback(null, true)` | OK для мобильных, но curl тоже пропускает | Минорный риск |
| S-10 | 🟡 | Множество API | Нет валидации email/phone формата | Добавить regex валидацию | Невалидные данные в БД |

---

## ФАЗА 3: ПОТОКИ ДАННЫХ — 6/10 ⚠️

### 🔴 Timezone баги (5 API файлов)

| # | Файл:строка | Текущий код | Исправление |
|---|-------------|-------------|-------------|
| T-1 | `attendance_api.js:76` | `const hour = time.getHours()` | `const moscow = new Date(time.getTime()+3*60*60*1000); const hour = moscow.getUTCHours()` |
| T-2 | `shifts_api.js:200` | `const currentHour = now.getHours()` | Аналогично T-1 |
| T-3 | `shifts_api.js:579` | `const createdHour = createdAt.getHours()` | Аналогично T-1 |
| T-4 | `pending_api.js:148` | `const hour = new Date(timestamp).getHours()` | Аналогично T-1 |
| T-5 | `order_timeout_api.js:79` | `const hour = date.getHours()` | Аналогично T-1 |

### 🟠 Null safety пробелы (Flutter)

| # | Файл:строка | Проблема | Исправление |
|---|-------------|----------|-------------|
| T-6 | `base_http_service.dart:59-76` | `result[listKey] as List<dynamic>` без null check | Добавить `if (result[listKey] == null) return []` перед cast |
| T-7 | `base_http_service.dart:106,148,190` | `fromJson(result[itemKey] as Map<String, dynamic>)` crashes если key отсутствует | Добавить null check перед cast |

### 🟠 Timezone math ошибка

| # | Файл:строка | Проблема | Исправление |
|---|-------------|----------|-------------|
| T-8 | `attendance_automation_scheduler.js:259` | `getUTCHours() + MOSCOW_OFFSET_HOURS` без modulo 24 | Добавить `% 24`: час 23 + 3 = 26 → должно быть 2 |

---

## ФАЗА 4: ОБРАБОТКА ОШИБОК — 5/10 ⚠️

### 🔴 Пустые catch блоки (6 мест)

| # | Файл:строка | Контекст | Исправление |
|---|-------------|----------|-------------|
| E-1 | `employees_api.js:31` | getNextReferralCode() | Добавить `console.error('Error reading employee:', file, e.message)` |
| E-2 | `recount_api.js:98` | Чтение настроек | Аналогично |
| E-3 | `rko_api.js:639` | Чтение файла | Аналогично |
| E-4 | `attendance_api.js:701` | Обработка записи | Аналогично |
| E-5 | `shifts_api.js:309` | Чтение daily файла | Аналогично |
| E-6 | `shifts_api.js:364` | Чтение отчёта | Аналогично |

### 🔴 Незащищённый JSON.parse() в scheduler-ах

| # | Файл | Строки | Исправление |
|---|------|--------|-------------|
| E-7 | `coffee_machine_automation_scheduler.js` | 78,95,114,127,152 | Обернуть в try-catch с `console.error` + fallback |
| E-8 | `envelope_automation_scheduler.js` | 66,101,144,161 | Аналогично |
| E-9 | `attendance_automation_scheduler.js` | 83,178,254,564 | Использовать `readJsonFile()` helper везде |

### 🟠 Дополнительные проблемы

| # | Файл | Проблема | Исправление |
|---|------|----------|-------------|
| E-10 | `envelope_report_service.dart:205-234` | getPendingReports()/getFailedReports() возвращают [] на ЛЮБУЮ ошибку | Добавить `Logger.error('Pending error:', e)` |
| E-11 | `coffee_machine_report_service.dart:159-196` | Аналогично E-10 | Аналогично |
| E-12 | `shifts_api.js:166-170` | Sort с null dates → Invalid Date | Добавить fallback: `Date.now()` для отсутствующих дат |

---

## ФАЗА 5: ПРОИЗВОДИТЕЛЬНОСТЬ — 6/10 ⚠️

### Ранее исправлено (09.02 v1)
- ✅ admin_cache.js → async preload + periodic rebuild 5 мин
- ✅ data_cache.js для employees/shops
- ✅ 11 API файлов с пагинацией (page/limit)
- ✅ Settings кэшируются в initBatchCache()
- ✅ AppCachedImage (82 вызова в 46 файлах)
- ✅ Сжатие фото (max 1920px, JPEG 85%)
- ✅ Batch endpoints: dashboard/counters + efficiency/supplementary-batch

### Backend — оставшиеся проблемы

| # | Приоритет | Файл | Проблема | Исправление |
|---|-----------|------|----------|-------------|
| P-1 | 🔴 | `efficiency_calc.js:301-826` | Single-employee: ~6500 файловых чтений | Всегда использовать batch cache |
| P-2 | 🟠 | `ml/yolo-wrapper.js:140-193` | 7 Sync вызовов (existsSync, mkdirSync, writeFileSync) при ML inference | Заменить на async fsp |
| P-3 | 🟠 | `tasks_api.js:54-77` | getEmployeePhoneById сканирует ВСЕХ сотрудников | Использовать data_cache.getEmployees() |
| P-4 | 🟠 | `clients_api.js:571-602` | Broadcast последовательно пишет по 1 файлу | Promise.all() для параллельной записи |
| P-5 | 🟠 | `pending_api.js:511` | generateDailyPendingShifts на КАЖДОМ GET | Кэшировать результат на 5 мин |
| P-6 | 🟠 | `shifts_api.js:298-319` | PUT сканирует ВСЕ daily файлы | Использовать index или прямой путь |

### Flutter — оставшиеся проблемы

| # | Приоритет | Проблема | Файлы |
|---|-----------|----------|-------|
| P-7 | 🟠 | 200+ setState перестраивают целые страницы | Все features |
| P-8 | 🟠 | Sort/filter в build() | efficiency, kpi, main_cash pages |
| P-9 | 🟠 | Нет lazy loading — Flutter не использует серверную пагинацию | Все list pages |
| P-10 | 🟠 | MainMenuPage — 10+ API вызовов (batch endpoint создан, не подключён) | main_menu_page.dart |
| P-11 | 🟠 | MyEfficiencyPage — 5-7 вызовов (batch endpoint создан, не подключён) | my_efficiency_page.dart |

---

## ФАЗА 6: НАДЁЖНОСТЬ — 6/10 ⚠️

### Ранее исправлено (09.02 v1)
- ✅ File locking в 8 schedulers + efficiency_penalties_api
- ✅ WebSocket auth обязательна
- ✅ onlineStatus очищается при disconnect
- ✅ Envelope/coffee scheduler окно: 5→30 мин

### Новые находки

| # | Приоритет | Файл | Проблема | Исправление |
|---|-----------|------|----------|-------------|
| R-1 | 🟠 | 8+ Flutter форм | Нет `_isSubmitting` guard — double-submit возможен | Добавить `if (_isSubmitting) return; setState(() => _isSubmitting = true)` |
| R-2 | 🟠 | `employee_chat_websocket.js` | WebSocket нет auto-reconnect на клиенте | Реализовать exponential backoff reconnect |
| R-3 | 🟠 | Все scheduler-ы | State файлы без atomic write (temp + rename) | Писать в `.tmp` → `rename()` |
| R-4 | 🟡 | 30% list pages | Нет пустого состояния "Нет данных" | Добавить placeholder виджет |
| R-5 | 🟡 | Flutter forms | Нет PopScope для защиты от потери данных при back | Обернуть формы в `PopScope(canPop: !_isSaving)` |

---

## ФАЗА 7: КАЧЕСТВО КОДА — 6/10 ⚠️

### Ранее исправлено (09.02 v1)
- ✅ flutter analyze: 0 errors, 0 warnings, 131 infos
- ✅ Удалён мёртвый код (loyalty_api.js)
- ✅ 45 warnings исправлены

### Новые находки

| # | Приоритет | Проблема | Масштаб | Исправление |
|---|-----------|----------|---------|-------------|
| Q-1 | 🟠 | **1060 console.log** в API файлах | 67 файлов | Заменить на structured logging (Winston) |
| Q-2 | 🟠 | **548 TODO/FIXME** комментариев | Весь проект | Завести issues или удалить неактуальные |
| Q-3 | 🟠 | Нестандартный формат API ответов (3+ формата) | 67 API | Стандартизировать `{success, data, error, meta}` |
| Q-4 | 🟠 | Duplicate CRUD patterns (copy-paste) в 55+ API файлов | ~2000 строк | Создать shared `createCrudRouter()` utility |
| Q-5 | 🟡 | 4 .backup файла в git | loyalty-proxy/api/ | Удалить, добавить *.backup* в .gitignore |
| Q-6 | 🟡 | `.then()` chain fire-and-forget | `cigarette_vision_api.js:500` | Конвертировать в async/await |
| Q-7 | 🟡 | Naming inconsistency (snake_case vs kebab-case) | API файлы | Стандартизировать на snake_case |
| Q-8 | 🟢 | 131 info из flutter analyze | lib/ | Постепенно исправлять |

---

## ФАЗА 8: МАСШТАБИРУЕМОСТЬ — 4/10 ❌

### Текущие ограничения

| Метрика | Текущее | Лимит | При 100 магазинах |
|---------|---------|-------|-------------------|
| Файлов в директории | ~1K-10K | ~50K | ~100K-1M (непригодно) |
| Размер JSON файла | ~5KB | ~100MB | Без проблем |
| Одновременных пользователей | ~20-50 | ~200 | ~500+ (OOM) |
| Upload размер | 10-20MB | Диск | Диск заполнится |
| Магазинов | ~10 | ~50 | readdir 2-5 сек |

### Точки отказа

| # | Приоритет | Проблема | При 100 магазинах / 1000 сотрудниках |
|---|-----------|----------|--------------------------------------|
| SC-1 | 🔴 | Файловая система как БД | readdir() на 100K+ файлов = 5-15 сек |
| SC-2 | 🔴 | efficiency_calc batch в память | 600MB+ RAM (сервер 2GB+2GB swap) |
| SC-3 | 🟠 | Пагинация необязательная | 10K записей в одном ответе |
| SC-4 | 🟠 | OCR (EasyOCR 800MB) + batch = OOM | При 10+ конкурентных запросов |
| SC-5 | 🟠 | Линейный поиск сотрудника для push | 100K лишних чтений/день |
| SC-6 | 🟡 | 8 schedulers × 5 мин × 100 магазинов | ~800 файл.операций/5мин |
| SC-7 | 🟡 | WebSocket broadcast O(N) | O(N²) distribution |

### Рекомендации по миграции
1. **Первым на SQLite:** attendance (самый большой volume)
2. **Вторым:** shift-reports, efficiency
3. **Кэширование:** settings (1-час TTL), employee index (in-memory)
4. **Без переписывания:** обязательная пагинация + cursor-based

---

## ФАЗА 9: UX — 8/10 ✅

### Что хорошо
- **307** loading indicators (CircularProgressIndicator)
- **1371** SnackBar для обратной связи
- **39** страниц с pull-to-refresh (RefreshIndicator)
- **60+** страниц с валидацией форм
- Кнопки disabled во время загрузки

### Проблемы

| # | Приоритет | Проблема | Исправление |
|---|-----------|----------|-------------|
| UX-1 | 🟠 | 30% list-страниц без пустого состояния | Добавить "Нет данных" виджет |
| UX-2 | 🟡 | Нет skeleton/shimmer при загрузке | Добавить shimmer эффект |
| UX-3 | 🟡 | Нет infinite scroll для больших списков | ListView.builder + серверная пагинация |

---

## ФАЗА 10: ТЕСТИРОВАНИЕ — 2/10 ❌

### Инвентаризация

| Тип | Файлов | Строк | Реальных тестов |
|-----|--------|-------|-----------------|
| Flutter unit | 29 | 12,857 | ~5% (остальные `expect(true, true)`) |
| Flutter integration | 5 | ~500 | ~10% |
| Server (jest/mocha) | **0** | **0** | **0%** |

### Критические пробелы
- **0 серверных тестов** для 67 API + 8 schedulers
- **90% Flutter тестов — placeholder-ы** (только структура + `expect(true, true)`)
- Нет тестов для efficiency_calc.js (самый сложный модуль)
- Нет regression тестов после фиксов

---

## ФАЗА 11: ТОЧКИ РОСТА

### Быстрые победы (1-2 недели)

| # | Задача | Трудозатраты | ROI |
|---|--------|-------------|-----|
| 1 | Обязательная пагинация на attendance/employees API | 1-2 дня | ⭐⭐⭐⭐⭐ |
| 2 | Employee ID index для push уведомлений | 1 день | ⭐⭐⭐⭐ |
| 3 | Пустые состояния на 30 list-страницах | 2-3 дня | ⭐⭐⭐ |
| 4 | Flutter интеграция batch endpoints (dashboard + efficiency) | 2-3 дня | ⭐⭐⭐⭐ |

### Среднесрочные (1-2 месяца)

| # | Задача | Трудозатраты |
|---|--------|-------------|
| 1 | Offline mode (SQLite cache + sync queue) | 2-3 недели |
| 2 | Оптимистичные обновления UI | 1-2 недели |
| 3 | Сжатие фото до WebP на сервере | 3-5 дней |
| 4 | Request deduplication (5-сек кэш) | 3-5 дней |

### Стратегические (3-6 месяцев)

| # | Задача | Трудозатраты |
|---|--------|-------------|
| 1 | Миграция на SQLite/PostgreSQL | 2-3 месяца |
| 2 | State management (Riverpod/Bloc) | 1 месяц |
| 3 | CI/CD pipeline (GitHub Actions) | 2 недели |
| 4 | Sentry для мониторинга ошибок | 1 неделя |

---

## КАРТА МОДУЛЕЙ

| Модуль | Здоровье | Главная проблема | Приоритет |
|--------|----------|-----------------|-----------|
| **auth** | ⚠️ 6/10 | 30-дневные сессии | 🟠 Нед.2 |
| **attendance** | ⚠️ 5/10 | Timezone `getHours()` | 🔴 Нед.1 |
| **shifts** | ⚠️ 5/10 | IDOR + timezone | 🔴 Нед.1 |
| **shift_handover** | ✅ 7/10 | Мелочи | 🟡 |
| **recount** | ⚠️ 6/10 | Пустой catch + IDOR | 🔴 Нед.1 |
| **envelope** | ⚠️ 6/10 | Scheduler JSON.parse | 🔴 Нед.1 |
| **rko** | ✅ 7/10 | Пустой catch | 🟠 Нед.2 |
| **orders** | ✅ 7/10 | Timezone order_timeout | 🔴 Нед.1 |
| **menu** | ✅ 8/10 | — | 🟢 |
| **recipes** | ✅ 8/10 | — | 🟢 |
| **employees** | ❌ 4/10 | **Нет auth на CRUD!** | 🔴 Нед.1 |
| **shops** | ✅ 8/10 | — | 🟢 |
| **work_schedule** | ✅ 7/10 | — | 🟢 |
| **efficiency** | ⚠️ 5/10 | 500K+ file reads | 🟠 Нед.2 |
| **rating** | ✅ 7/10 | — | 🟢 |
| **fortune_wheel** | ✅ 8/10 | — | 🟢 |
| **tasks** | ✅ 7/10 | Линейный поиск | 🟡 |
| **training** | ✅ 8/10 | — | 🟢 |
| **tests** | ✅ 7/10 | — | 🟢 |
| **reviews** | ✅ 8/10 | — | 🟢 |
| **product_questions** | ⚠️ 6/10 | Нет _isSubmitting | 🟠 Нед.2 |
| **loyalty** | ✅ 8/10 | — | 🟢 |
| **referrals** | ✅ 7/10 | — | 🟢 |
| **job_application** | ✅ 8/10 | — | 🟢 |
| **employee_chat** | ⚠️ 6/10 | Нет reconnect | 🟠 Нед.2 |
| **clients** | ✅ 7/10 | — | 🟢 |
| **bonuses** | ✅ 7/10 | — | 🟢 |
| **main_cash** | ✅ 7/10 | — | 🟢 |
| **suppliers** | ✅ 8/10 | — | 🟢 |
| **coffee_machine** | ⚠️ 6/10 | Scheduler crash | 🔴 Нед.1 |
| **kpi** | ✅ 7/10 | — | 🟡 |
| **ai_training** | ✅ 7/10 | .then() fire-and-forget | 🟡 |
| **network_management** | ✅ 8/10 | — | 🟢 |
| **data_cleanup** | ✅ 8/10 | — | 🟢 |
| **execution_chain** | ✅ 7/10 | Не в документации | 🟡 |

---

## ROADMAP ИСПРАВЛЕНИЙ

### Неделя 1 — 🔴 Критические

| # | Задача | Файлы | Оценка |
|---|--------|-------|--------|
| 1 | Timezone fix: `getHours()` → UTC+3 в 5 API | attendance_api, shifts_api, pending_api, order_timeout_api, recurring_tasks_api | 2-3 часа |
| 2 | requireAdmin на employees CRUD | employees_api.js | 1 час |
| 3 | IDOR fix: проверка владельца на reports | shifts_api, envelope_api, recount_api | 3-4 часа |
| 4 | Заменить 6 пустых catch на логирование | 5 файлов | 30 мин |
| 5 | try-catch для JSON.parse в 3 scheduler-ах | coffee_machine/envelope/attendance schedulers | 2 часа |
| 6 | SCRIPT_URL в env переменную | index.js, recount_api.js | 30 мин |

### Неделя 2 — 🟠 Важные

| # | Задача | Файлы | Оценка |
|---|--------|-------|--------|
| 7 | Сократить сессию + refresh token | auth_api.js | 4-6 часов |
| 8 | Валидация email/phone | employees_api, clients_api | 3 часа |
| 9 | _isSubmitting guard на 8 форм | Flutter forms | 3 часа |
| 10 | Пустые состояния на 30 страницах | Flutter list pages | 2-3 дня |
| 11 | HSTS заголовки | index.js helmet config | 30 мин |
| 12 | Обязательная пагинация | attendance_api, employees_api | 1 день |

### Неделя 3 — 🟡 Улучшения

| # | Задача | Оценка |
|---|--------|--------|
| 13 | `.then()` → async/await (cigarette_vision_api) | 2 часа |
| 14 | Стандартизация API ответов | 3 дня |
| 15 | Разобрать 548 TODO/FIXME | 1 день |
| 16 | Удалить backup файлы из git | 30 мин |
| 17 | Обновить ARCHITECTURE_COMPLETE.md (execution_chain) | 1 час |
| 18 | Timezone math fix: `% 24` в attendance scheduler | 30 мин |

### Неделя 4+ — 🟢 Стратегические

| # | Задача | Оценка |
|---|--------|--------|
| 19 | Реальные Flutter тесты (заменить 29 placeholder-ов) | 2-3 недели |
| 20 | Jest test suite для 67 API | 2-3 недели |
| 21 | Миграция attendance на SQLite | 2-3 месяца |
| 22 | CI/CD (GitHub Actions) | 2 недели |
| 23 | Sentry мониторинг | 1 неделя |
| 24 | State management (Riverpod) | 1 месяц |

---

## ИСТОРИЯ ИСПРАВЛЕНИЙ (09.02 v1)

### Выполнено ранее: 35 из 39 пунктов первого аудита

| Фаза | Всего | Исправлено | Осталось |
|------|-------|------------|----------|
| Критические | 8 | 8 | 0 |
| Важные | 9 | 9 | 0 |
| Рекомендации | 14 | 12 | 2 |
| Безопасность | 8 | 7 | 1 (cert pinning) |

### Ключевые исправления v1
- ✅ API key вынесен из кода
- ✅ Auth middleware на все write endpoints
- ✅ WebSocket auth обязательна
- ✅ File locking на 8 schedulers
- ✅ Data cache для employees/shops
- ✅ Пагинация на 11 API endpoints
- ✅ CachedNetworkImage (82 вызова)
- ✅ Сжатие фото при upload
- ✅ Batch endpoints (dashboard + efficiency)
- ✅ Auto-cleanup scheduler
- ✅ flutter analyze: 0 errors, 0 warnings

---

*Полный аудит v2: 9 февраля 2026*
*Проверено: 67 API, 8 schedulers, 36 Flutter модулей, 194 страницы, 82 сервиса*
*Следующий шаг: Неделя 1 — 6 критических фиксов (timezone, auth, IDOR, catch, JSON.parse, SCRIPT_URL)*

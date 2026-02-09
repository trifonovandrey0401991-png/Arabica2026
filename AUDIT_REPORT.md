# АУДИТ ARABICA — 2026-02-09

## СВОДКА
- 🔴 Критических проблем: **12** (8 исправлены 09.02)
- 🟠 Важных проблем: **24**
- 🟡 Рекомендаций: **31**
- ✅ Модулей без проблем: **22 / 35**
- flutter analyze: **0 ошибок, 45 warnings, 135 infos**

---

## ФАЗА 1: БЕЗОПАСНОСТЬ

**Проверено: 55 API файлов + 8 ключевых файлов инфраструктуры + Flutter auth**

### 🔴 Критические (5)

| # | Файл | Строка | Описание | Как исправить |
|---|------|--------|----------|---------------|
| C1 | `lib/core/constants/api_constants.dart` | 7 | ~~**API ключ захардкожен в исходниках**~~ ✅ ИСПРАВЛЕНО 09.02 — ключ вынесен в `api_key.dart` (gitignored) | ✅ Готово |
| C2 | `loyalty-proxy/index.js` | 148-149 | ~~**API key auth выключен по умолчанию**~~ ✅ ИСПРАВЛЕНО 09.02 — `!== 'false'` = включён по умолчанию | ✅ Готово |
| C3 | **Все API файлы** | — | ~~**Нет проверки ролей на write-эндпоинтах**~~ ✅ ЧАСТИЧНО ИСПРАВЛЕНО 09.02 — глобальный auth middleware на все POST/PUT/DELETE/PATCH. `requireAdmin` экспортирован для точечного применения | Добавить `requireAdmin` на admin-only endpoints |
| C4 | `loyalty-proxy/api/auth_api.js` | 282-283 | ~~**Регистрация возвращает pinHash и salt**~~ ✅ ИСПРАВЛЕНО 09.02 — удалены из ответа, Flutter создаёт локальные credentials | ✅ Готово |
| C5 | `loyalty-proxy/api/auth_api.js` | 657 | **GET /api/auth/session/:phone без аутентификации** — можно узнать кто онлайн | Требовать аутентификацию или удалить |

### 🟠 Важные (8)

| # | Файл | Строка | Описание | Как исправить |
|---|------|--------|----------|---------------|
| H1 | `loyalty-proxy/api/employee_chat_websocket.js` | 63 | ~~**WebSocket auth опциональна** — подключение без токена принимается~~ ✅ ИСПРАВЛЕНО 09.02 — token обязателен, без него ws.close(4002) | ✅ |
| H2 | `loyalty-proxy/api/auth_api.js` | 619 | **Biometric enable/disable без auth** — любой может переключить | Требовать session token |
| H3 | `loyalty-proxy/index.js` | 155 | ~~**Upload-photo без аутентификации** — в publicPaths~~ ✅ ИСПРАВЛЕНО 09.02 — удалено из PUBLIC_ENDPOINTS и PUBLIC_WRITE_PATHS | ✅ |
| H4 | `loyalty-proxy/api/data_cleanup_api.js` | 382 | **Admin операции без auth** — execSync для disk info, удаление данных | Добавить isAdmin проверку |
| H5 | `loyalty-proxy/index.js` | 326 | **application/octet-stream в upload** — обходит MIME фильтр | Убрать из allowed types |
| H6 | `loyalty-proxy/api/shop_products_api.js` | 43-50 | **Слабый default API ключ** `arabica-sync-2025` с wildcard доступом | Генерировать случайный ключ |
| H7 | `lib/core/services/base_http_service.dart` | — | **Нет certificate pinning** — возможна MITM атака | Добавить `http_certificate_pinning` |
| H8 | `lib/features/auth/services/secure_storage_service.dart` | 97 | **Слабый salt** — `DateTime.now().microsecondsSinceEpoch` предсказуем | Использовать `Random.secure()` |

### 🟡 Рекомендации (6)

| # | Описание | Файл |
|---|----------|------|
| M1 | Нет отдельного rate limit на auth эндпоинты (общий 500/мин слишком высок) | `index.js` |
| M2 | Telegram OTP можно запросить для чужого телефона | `telegram_bot_service.js` |
| M3 | Google Apps Script URL захардкожен | `index.js:479` |
| M4 | FCM token filename с минимальной санитизацией | `index.js:632` |
| M5 | Нет `--obfuscate` для Flutter build | Build scripts |
| M6 | product_questions_api.js — questionId без sanitizeId в path.join | `product_questions_api.js:286` |

### ✅ Что сделано хорошо
- Helmet.js headers, CORS whitelist, rate limiting (500/мин + 50/мин финансы)
- Bcrypt hashing + PIN brute force protection (5 попыток, 15мин lockout)
- Session tokens через crypto.randomBytes(32)
- sanitizeId() и isPathSafe() используются во многих API
- ProGuard/R8 включён для Android release
- key.properties и google-services.json в .gitignore

---

## ФАЗА 2: ЦЕПОЧКИ ДАННЫХ

### Группа A — Авторизация и сотрудники

| Модуль | URL | Модель | Сохранение | Ошибки | Push | Проблемы |
|--------|-----|--------|------------|--------|------|----------|
| auth | ✅ 8/8 | ⚠️ | ✅ | ✅ | N/A | ~~🔴 refresh-session~~ ✅ ИСПРАВЛЕНО 09.02 — endpoint добавлен. `AuthSession.role` не заполняется |
| employees | ✅ | ✅ | ⚠️ | ✅ | N/A | Flutter не отправляет position, department, email при create/update |
| shops | ✅ | ⚠️ | ✅ | ✅ | N/A | Flutter игнорирует поле icon с сервера |
| attendance | ✅ | ✅ | ✅ | ✅ | ✅ | Без проблем |
| work_schedule | ✅ | ✅ | ✅ | ✅ | ✅ | Без проблем |

### Группа B — Отчёты

| Модуль | URL | Модель | Сохранение | Ошибки | Push | Проблемы |
|--------|-----|--------|------------|--------|------|----------|
| shifts | ✅ | ✅ | ✅ | ✅ | ✅ | submitReport обходит BaseHttpService (дизайн) |
| shift_handover | ✅ | ✅ | ✅ | ✅ | ✅ | Без проблем |
| recount | ✅ | ✅ | ✅ | ⚠️ | ✅ | Сервер маскирует ошибки, возвращая пустой массив вместо 500 |
| envelope | ✅ | ✅ | ✅ | ⚠️ | ✅ | 🟠 pending/failed возвращают bare JSON array (нестандартно) |
| rko | ✅ | ✅ | ✅ | ✅ | N/A | Без проблем |
| coffee_machine | ✅ | ✅ | ✅ | ⚠️ | ✅ | 🟠 То же: pending/failed как bare JSON array |

### Группа C — Финансы и баллы

| Модуль | URL | Модель | Сохранение | Ошибки | Push | Проблемы |
|--------|-----|--------|------------|--------|------|----------|
| main_cash/withdrawals | ✅ | ✅ | ✅ | ✅ | ✅ | Без проблем |
| bonuses | ✅ | ✅ | ✅ | ✅ | N/A | Без проблем |
| efficiency | ✅ | ✅ | ✅ | ✅ | N/A | Без проблем |
| kpi | N/A | ✅ | N/A | ✅ | N/A | `ApiConstants.kpiEndpoint` не используется (мёртвый код) |

### Группа D — Клиенты и лояльность

| Модуль | URL | Модель | Сохранение | Ошибки | Push | Проблемы |
|--------|-----|--------|------------|--------|------|----------|
| clients | ✅ | ⚠️ | ✅ | ✅ | ✅ | ~~🔴 broadcast body mismatch~~ ✅ ИСПРАВЛЕНО 09.02 — сервер принимает оба формата |
| loyalty/promo | ✅ | ✅ | ✅ | ✅ | N/A | Без проблем |
| loyalty_gamification | ✅ | ✅ | ✅ | ✅ | ✅ | Без проблем |
| fortune_wheel | ✅ | ✅ | ✅ | ✅ | N/A | Без проблем |
| referrals | ✅ | ✅ | ✅ | ✅ | N/A | Deprecated ReferralSettings модель (можно удалить) |
| reviews | ✅ | ✅ | ✅ | ✅ | ✅ | 🟠 markMessageAsRead вызывает несуществующий роут (404) |
| orders | ⚠️ | ⚠️ | ✅ | ✅ | ⚠️ | Hardcoded endpoint, raw Map вместо моделей, нет push |

### Группы E-F — Обучение, задачи, AI, вспомогательные

| Модуль | Статус | Проблемы |
|--------|--------|----------|
| training | ⚠️ | Нет проверки admin на сервере для POST/PUT/DELETE |
| tests | ✅ | Без критических проблем |
| tasks | ⚠️ | getEmployeePhoneById сканирует всех сотрудников |
| product_questions | ⚠️ | calculateProductSearchPoints ищет несуществующие поля |
| recipes | ✅ | Без проблем |
| ai_training | В разработке | Модуль не завершён |
| employee_chat | ⚠️ | Нет auth на сервере, нет rate limiting |
| menu | ✅ | MenuService не используется (мёртвый код) |
| suppliers | ⚠️ | undefined getNextReferralCode() → ошибка 500 |
| job_application | ⚠️ | Нет auth check на PATCH endpoints |
| data_cleanup | ⚠️ | execSync, нет auth на admin операциях |

---

## ФАЗА 3: РАБОТОСПОСОБНОСТЬ МОДУЛЕЙ

### 8 Schedulers

| # | Scheduler | Интервал | Время | Дублирование | Штрафы | Push | Надёжность | Проблемы |
|---|-----------|----------|-------|--------------|--------|------|------------|----------|
| 1 | shift | 5 мин | UTC+3 ✅ | State + sourceId | -3 | ✅ | Robust | 🟡 Зависимость от TZ сервера |
| 2 | recount | 5 мин | UTC+3 ✅ | State + sourceId | -3 | ✅ | Robust | 🟡 Читает ВСЕ файлы отчётов |
| 3 | rko | 5 мин | UTC+3 ✅ | State + sourceId + metadata | -3 | ✅ | Robust | 🟡 metadata файл читается N раз |
| 4 | shift_handover | 5 мин | UTC+3 ✅ | State + sourceId | -3 | ✅ | Robust | 🟠 `getHours()` вместо Moscow часов |
| 5 | attendance | 5 мин | UTC+3 ✅ | State + sourceId | -2 | ✅ | Robust | 🟡 Hour overflow (23+3=26) |
| 6 | envelope | 5 мин | UTC+3 ✅ | Date + Map/Set | -5 | ✅ | Moderate | ~~🟠 5-мин окно~~ ✅ 30-мин окно 09.02 |
| 7 | coffee_machine | 5 мин | UTC+3 ✅ | Date + Map/Set | -3 | ✅ | Moderate | ~~🟠 5-мин окно~~ ✅ 30-мин окно 09.02 |
| 8 | product_questions | 5 мин | ✅ UTC+3 | Processed IDs | -1 | ❌ | Robust | ~~🔴 getHours()~~ ✅ ИСПРАВЛЕНО 09.02 — `(getUTCHours()+3)%24` |

### Критические проблемы schedulers:
1. ~~**🔴 product_questions**: `getHours()` возвращает серверное время вместо московского~~ ✅ ИСПРАВЛЕНО 09.02
2. **🟠 shift_handover**: Тип смены определяется по `getHours()` — ошибка на 3 часа на UTC сервере
3. ~~**🟠 envelope + coffee_machine**: 5-минутное окно генерации~~ ✅ ИСПРАВЛЕНО 09.02 — расширено до 30 минут
4. ~~**🟠 Все 8 schedulers**: Пишут в один penalty файл без блокировки~~ ✅ ИСПРАВЛЕНО 09.02 — все 8 используют `writeJsonFile` с locking

---

## ФАЗА 4: МАСШТАБИРУЕМОСТЬ

| # | Проблема | Уровень | Текущее влияние | При 100 магазинах |
|---|----------|---------|-----------------|-------------------|
| 1 | **Файловая система как БД** — полное сканирование директорий | 🔴 | ~50мс на список | ~5 сек на список, блокировка event loop |
| 2 | ~~**Нет кэширования**~~ ✅ ЧАСТИЧНО ИСПРАВЛЕНО 09.02 — data_cache.js для employees/shops (preload + 5мин rebuild + CRUD invalidation) | ✅ | Employees/shops из кэша | Settings ещё читаются с диска |
| 3 | ~~**File locks НЕ используются**~~ ✅ ЧАСТИЧНО ИСПРАВЛЕНО 09.02 — 8 schedulers + efficiency_penalties_api переведены на `writeJsonFile` с locking. Остальные 177 вызовов в API файлах пока без блокировки | 🟠 | Schedulers защищены | Остальные API файлы — потом |
| 4 | **Нет автоматической очистки** — данные растут бесконечно | 🟠 | Ручная очистка | 500K+ файлов через 12 месяцев |
| 5 | **Память сервера** — 2GB + 2GB swap, EasyOCR ~1GB | 🟠 | Работает впритык | Batch efficiency может упасть OOM |
| 6 | **8 schedulers × 5 мин** — все одновременно | 🟡 | ~64 файл.операций/5мин | ~800 файл.операций/5мин |
| 7 | **WebSocket** — broadcast всем, onlineStatus никогда не чистится | 🟡 | OK для малой команды | O(N²) distribution, memory leak |
| 8 | **Upload 10-20MB** — без проверки свободного места | 🟡 | OK | Диск может заполниться |

### Ключевая находка: 197 записей в файлы БЕЗ блокировки
`file_lock.js` и `async_fs.js` были созданы, но **ни один** API файл их не использует. Все 197 вызовов `fsp.writeFile()` в api/ файлах работают без блокировки.

---

## ФАЗА 5: ПРОИЗВОДИТЕЛЬНОСТЬ

### Backend — медленный код

| # | Уровень | Файл | Описание |
|---|---------|------|----------|
| B-1 | 🔴 | `admin_cache.js:80-103` | Синхронные `readdirSync`/`readFileSync` при cache miss — блокирует event loop на КАЖДОМ запросе |
| B-6 | 🔴 | `efficiency_calc.js:301-826` | Single-employee path: ~6500 файловых чтений на запрос (13 категорий × все файлы) |
| B-7 | 🟠 | `efficiency_calc.js:1077-1079` | Batch cache не покрывает 4 категории (productSearch, rko, tasks, orders) |
| B-8 | 🟠 | `efficiency_calc.js:883+` | Settings перечитываются с диска для каждого сотрудника в batch |
| B-9 | 🟠 | `tasks_api.js:54-77` | getEmployeePhoneById сканирует ВСЕХ сотрудников |
| B-10 | 🟠 | `clients_api.js:571-602` | Broadcast последовательно пишет по 1 файлу (100 клиентов = 10 сек) |
| B-11 | ✅ | 15+ API файлов | ~~**Нет пагинации**~~ ✅ ИСПРАВЛЕНО 09.02 — 11 API файлов поддерживают page/limit (backward compatible) |
| B-12 | 🟠 | `pending_api.js:511` | generateDailyPendingShifts вызывается на КАЖДОМ GET |
| B-13 | 🟠 | `shifts_api.js:298-319` | PUT /api/shift-reports/:id сканирует ВСЕ daily файлы для поиска одного отчёта |
| B-5 | 🟠 | `ml/yolo-wrapper.js` | writeFileSync, mkdirSync блокируют event loop при ML inference |

### Flutter — медленный UI

| # | Уровень | Описание | Файлы |
|---|---------|----------|-------|
| F-1 | 🟠 | **200+ setState** перестраивают целые страницы | Все features |
| F-3 | 🟠 | **Sort/filter в build()** — пересчёт на каждом rebuild | efficiency, kpi, main_cash pages |
| F-4 | 🟠 | **Нет lazy loading** — Flutter грузит ВСЕ данные сразу. Сервер поддерживает page/limit (11 endpoints), Flutter клиент пока не использует | Все list pages |
| F-5 | ✅ | ~~**30+ Image.network без кэширования**~~ ✅ ИСПРАВЛЕНО 09.02 — AppCachedImage (82 вызова в 46 файлах) | Множество страниц |
| F-6 | 🟠 | **Нет сжатия фото при загрузке** в PhotoUploadService (3-10MB вместо 200KB) | photo_upload_service.dart |
| F-7 | 🟠 | **MainMenuPage — 10+ API вызовов** одновременно при открытии | main_menu_page.dart:108-123 |
| F-8 | 🟠 | **MyEfficiencyPage — 5-7 последовательных** API вызовов | my_efficiency_page.dart:94-219 |

---

## ФАЗА 6: НАГРУЗОЧНЫЕ ТЕСТЫ

**Созданы в `loyalty-proxy/tests/`:**

| Скрипт | Описание | Endpoints | Запуск |
|--------|----------|-----------|--------|
| `load-test.js` | 5 сценариев нагрузки: 50 GET employees, 50 GET shift-reports, 20 POST attendance, 10 GET efficiency, 30 WebSocket | ~160 запросов | `SESSION_TOKEN=xxx node tests/load-test.js` |
| `smoke-test.js` | Smoke-тест 73 GET + 13 POST endpoints, классификация OK/BROKEN/ERROR, JSON отчёт | 86 endpoints | `SESSION_TOKEN=xxx node tests/smoke-test.js` |

**Метрики load-test.js:** min/avg/max/p95 время ответа, throughput (req/sec), error rate, WebSocket connections
**Зависимости:** Только стандартный Node.js `http` модуль (без внешних пакетов)

---

## ФАЗА 7: ОБЩАЯ РАБОТОСПОСОБНОСТЬ

### flutter analyze
```
Результат: 180 issues (0 errors, ~45 warnings, ~135 infos)
Время: 6.8s
```

**Warnings (ключевые):**
- 1 unused import: `flutter_local_notifications` в `firebase_service_stub.dart`
- 9 unused `_settings` fields в settings pages
- Множество `dead_null_aware_expression` — лишние `??` операторы
- Несколько `unused_local_variable` и `unused_field`
- `invalid_null_aware_operator` — лишние `?.`

**Infos (основные категории):**
- ~40 `use_build_context_synchronously` — BuildContext после async gap
- ~30 `avoid_print` в integration tests
- ~10 `dangling_library_doc_comments`
- ~10 `unused_element` — неиспользуемые приватные методы
- 4 `depend_on_referenced_packages` — импорт пакетов не из pubspec
- 2 `deprecated_member_use` — WillPopScope (заменить на PopScope)

**Вывод: Проект компилируется без ошибок. Warnings не влияют на работу.**

### Критические потоки

| Поток | Статус | Проблемы |
|-------|--------|----------|
| 1. Регистрация → PIN → Вход | ✅ | ~~`/api/auth/refresh-session` не существует~~ ✅ ИСПРАВЛЕНО 09.02 |
| 2. Пересменка → Фото → Отправить | ✅ | Работает |
| 3. Пересчёт → Заполнить → Штраф | ✅ | Работает |
| 4. Клиент → Бонусы → QR | ✅ | Работает (внешний loyalty API) |
| 5. Задача → Выполнить → Баллы | ⚠️ | Баллы не записываются при approve (из старого аудита) |
| 6. Расписание → Авто → Публикация | ✅ | Работает |
| 7. Кофемашина → OCR → Отчёт | ✅ | Работает |
| 8. Эффективность → KPI → Рейтинг | ✅ | ~~5 из 10 категорий не работают~~ ✅ ИСПРАВЛЕНО 09.02 — все категории работают |

---

## ПЛАН ИСПРАВЛЕНИЙ

### Неделя 1 — 🔴 Критические (блокеры)

| # | Задача | Файл(ы) | Оценка |
|---|--------|---------|--------|
| 1 | ~~**Добавить auth middleware** на все write-эндпоинты~~ ✅ ИСПРАВЛЕНО 09.02 | `index.js` + `session_middleware.js` | ✅ |
| 2 | ~~**Удалить pinHash/salt** из ответа регистрации~~ ✅ ИСПРАВЛЕНО 09.02 | `auth_api.js` | ✅ |
| 3 | ~~**Вынести API ключ** из Flutter кода~~ ✅ ИСПРАВЛЕНО 09.02 | `api_constants.dart` + `api_key.dart` (gitignored) | ✅ |
| 4 | ~~**Включить API key auth** по умолчанию~~ ✅ ИСПРАВЛЕНО 09.02 | `index.js` | ✅ |
| 5 | ~~**Исправить product_questions scheduler** — Moscow time вместо local~~ ✅ ИСПРАВЛЕНО 09.02 | `product_questions_penalty_scheduler.js` | ✅ |
| 6 | ~~**Подключить file_lock.js** к schedulers~~ ✅ ИСПРАВЛЕНО 09.02 (8 schedulers + efficiency_penalties_api) | 9 файлов | ✅ |
| 7 | ~~**Исправить clients broadcast** — field mismatch~~ ✅ ИСПРАВЛЕНО 09.02 | `clients_api.js` | ✅ |
| 8 | ~~**Добавить /api/auth/refresh-session** эндпоинт~~ ✅ ИСПРАВЛЕНО 09.02 | `auth_api.js` | ✅ |

### Неделя 2 — 🟠 Важные

| # | Задача | Файл(ы) | Оценка |
|---|--------|---------|--------|
| 9 | ~~**Добавить пагинацию**~~ ✅ ИСПРАВЛЕНО 09.02 — 11 API файлов поддерживают page/limit (backward compatible) | Все api/ файлы | ✅ |
| 10 | ~~**Исправить efficiency_calc.js** — 5 сломанных категорий~~ ✅ ИСПРАВЛЕНО 09.02 | `efficiency_calc.js` | ✅ |
| 11 | ~~**Заменить Image.network → CachedNetworkImage**~~ ✅ ИСПРАВЛЕНО 09.02 — AppCachedImage wrapper + замена в 46 файлах (82 вызова) | Flutter pages | ✅ |
| 12 | ~~**Добавить сжатие фото** в PhotoUploadService~~ ✅ ИСПРАВЛЕНО 09.02 (compute isolate, max 1920px, JPEG 85%) | `photo_upload_service.dart` | ✅ |
| 13 | ~~**Исправить envelope/coffee_machine schedulers** — расширить окно генерации~~ ✅ ИСПРАВЛЕНО 09.02 (5→30 мин) | 2 scheduler файла | ✅ |
| 14 | ~~**Сделать admin_cache.js async**~~ ✅ ИСПРАВЛЕНО 09.02 (async preload + periodic rebuild 5 мин) | `admin_cache.js` | ✅ |
| 15 | ~~**WebSocket auth обязательная**~~ ✅ ИСПРАВЛЕНО 09.02 | `employee_chat_websocket.js` | ✅ |
| 16 | ~~**Убрать /upload-photo из publicPaths**~~ ✅ ИСПРАВЛЕНО 09.02 | `index.js` | ✅ |
| 17 | ~~**Добавить кэш employees/shops**~~ ✅ ИСПРАВЛЕНО 09.02 — data_cache.js (preload + 5мин rebuild + invalidation на CRUD) | `utils/data_cache.js` | ✅ |

### Неделя 3+ — 🟡 Рекомендации

| # | Задача |
|---|--------|
| 18 | Certificate pinning в Flutter |
| 19 | `--obfuscate` для Flutter build |
| 20 | Автоматическая ротация/очистка данных (scheduler) |
| 21 | Rate limit на auth endpoints (10/мин) |
| 22 | Batch API для MainMenuPage (один запрос вместо 10) |
| 23 | Batch API для MyEfficiencyPage |
| 24 | Кэширование settings в efficiency_calc.js batch |
| 25 | Переход pending/failed endpoints на стандартный формат `{success, items}` |
| 26 | Очистка onlineStatus Map в WebSocket |
| 27 | Прекомпиляция sort/filter вне build() |
| 28 | Удалить мёртвый код (MenuService, deprecated ReferralSettings, unused elements) |
| 29 | Исправить 45 warnings из flutter analyze |
| 30 | Добавить get-by-ID endpoints для отчётов |
| 31 | Стабилизировать penalty file format (plain array везде) |

---

## ВЛИЯНИЕ НА FORTUNE WHEEL (из предыдущего аудита)

| Категория | Статус | Учитывается |
|-----------|--------|-------------|
| shifts | ✅ Работает | Да |
| recount | ✅ Работает | Да |
| envelope | ❌ Не загружается | Нет |
| attendance | ✅ Работает | Да |
| reviews | ❌ Неправильное поле | Нет |
| rko | ✅ Работает | Да |
| orders | ❌ Неправильная структура | Нет |
| productSearch | ❌ Неправильные поля | Нет |
| tests | ✅ Работает | Да |
| tasks | ❌ Баллы не записываются | Нет |

**Результат:** Рейтинг считается по 5 из 10 категорий — несправедливо для сотрудников.

---

*Аудит выполнен: 9 февраля 2026*
*Проверено: 55 API файлов, 8 schedulers, 35 Flutter модулей, flutter analyze*
*Агенты: 7 параллельных фаз аудита*

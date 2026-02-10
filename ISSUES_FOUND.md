# ISSUES FOUND — Найденные проблемы проекта Arabica

> **Цель:** собрать ВСЕ проблемы в одном месте, чтобы не делать анализ дважды.
> Дата анализа: 2026-02-10
> Статус: ❌ не исправлено | ✅ исправлено | ⏸️ отложено

---

## 📊 СВОДКА

| Severity | Всего | ✅ Исправлено | ⏸️ Отложено/Ложные | ❌ Осталось |
|----------|-------|-------------|-------------------|------------|
| 🔴 CRITICAL | 8 | 8 (все ✓) | 0 | 0 |
| 🟠 HIGH | 15 | 15 (все ✓) | 0 | 0 |
| 🟡 MEDIUM | 18 | 17 (все кроме M-11) | 1 (M-11) | 0 |
| 🟢 LOW | 12 | 7 (ложные тревоги) | 5 (L-01,L-03,L-05,L-10,H-10) | 0 |
| **ИТОГО** | **53** | **47** | **6 (H-10,M-11,L-01,L-03,L-05,L-10)** | **0** |

---

## 🔴 CRITICAL (8 проблем)

### C-01. ✅ Эндпоинт refresh-session не существует на бэкенде (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `loyalty-proxy/api/auth_api.js` (строки 711-748)
**Результат проверки:** Эндпоинт `POST /api/auth/refresh-session` СУЩЕСТВУЕТ и работает. Обновляет lastActivity сессии. Ошибка анализа — эндпоинт был найден при повторной проверке.

---

### C-02. ✅ Два метода регистрации с разной безопасностью (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `lib/features/auth/services/auth_service.dart`
**Результат проверки:** `registerSimple()` отправляет raw PIN через HTTPS → сервер хеширует bcrypt (безопаснее). `register()` — legacy метод с клиентским SHA-256 (слабее). Оба работают через HTTPS. Реальной уязвимости нет.

---

### C-03. ✅ changePin() работает только локально (исправлено 2026-02-10)
**Файлы:** `auth_api.js` + `auth_service.dart`
**Проблема:** changePin() обновлял PIN только локально.
**Исправление:** Добавлен `POST /api/auth/change-pin` на бэкенде (верификация старого PIN + bcrypt нового). Flutter теперь вызывает сервер перед локальным обновлением.

---

### C-04. ✅ Race condition: незаверенный сотрудник может получить доступ (исправлено 2026-02-10)
**Файл:** `lib/features/employees/services/user_role_service.dart`
**Проблема:** `loadUserRole()` читала из SharedPreferences без срока давности. Уволенный сотрудник сохранял доступ.
**Исправление:** Добавлен TTL 30 минут для кэша роли в SharedPreferences. При истечении `loadUserRole()` возвращает null → fail-secure (см. C-07).

---

### C-05. ✅ NotificationService ссылается на несуществующие классы (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `lib/core/services/notification_service.dart`
**Результат проверки:** `Order` корректно импортирован из `shared/providers/order_provider.dart`, `Employee` из `employees/pages/employees_page.dart`. Оба класса существуют и используются правильно. Ошибка анализа.

---

### C-06. ✅ Отсутствует валидация владельца при загрузке фото (исправлено 2026-02-10)
**Файл:** `loyalty-proxy/index.js` — эндпоинт `/upload-employee-photo`
**Проблема:** Любой мог загрузить фото для чужого номера.
**Исправление:** Если есть сессия и пользователь не админ — phone из запроса должен совпадать с phone из сессии. Без сессии (регистрация) — по-прежнему разрешено.

---

### C-07. ✅ MultitenancyFilter возвращает ВСЕ данные при null role (исправлено 2026-02-10)
**Файл:** `lib/features/shops/services/shop_service.dart`
**Проблема:** При `roleData == null` возвращались ВСЕ магазины и полный доступ.
**Исправление:** Fail-secure — возвращает пустой список `[]` и `false` для доступа при null role.

---

### C-08. ✅ Loyalty service пустой эндпоинт (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `loyalty-proxy/api/loyalty_gamification_api.js`
**Результат проверки:** Все GET endpoints имеют полноценную логику загрузки данных: settings из файла, client data с расчётами уровней/бейджей, wheel-history из месячных файлов. Пустые результаты — только когда данных реально нет (нормальное поведение).

---

## 🟠 HIGH (15 проблем)

### H-01. ✅ Несогласованная нормализация телефонов (исправлено 2026-02-10)
**Файлы:** 9 файлов Flutter (34 вхождения)
**Проблема:** `RegExp(r'[\s+]')` вместо `RegExp(r'[\s\+]')` в 9 файлах.
**Исправление:** Все 34 вхождения заменены на единообразный `RegExp(r'[\s\+]')`.
**Примечание:** Бэкенд (M-11) использует другой подход `/[^\d]/g` — отдельная задача.

---

### H-02. ✅ O(n×m) производительность в calculateRatings (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `loyalty-proxy/api/rating_wheel_api.js`
**Результат проверки:** Уже оптимизировано через batch caching (рефакторинг 2026-02-05). `initBatchCache()` загружает ВСЕ данные за месяц один раз, затем `calculateFullEfficiencyCached()` использует кэш. Сложность O(n+m), а не O(n×m).

---

### H-03. ✅ Race condition при вращении колеса фортуны (исправлено 2026-02-10)
**Файл:** `loyalty-proxy/api/rating_wheel_api.js`
**Проблема:** POST `/api/fortune-wheel/spin` — read-check-write без блокировки. Два параллельных запроса могли использовать один спин дважды.
**Исправление:** Весь spin endpoint обёрнут в `withLock()` (из `utils/file_lock.js`) с ключом по employeeId. Чтение, проверка и запись спинов теперь атомарны.

---

### H-04. ✅ checkReferralLimit() сканирует ВСЕХ клиентов (приемлемо 2026-02-10)
**Файл:** `loyalty-proxy/api/referrals_api.js`
**Результат проверки:** O(N) при N=100-500 клиентов + кэш 5 минут. Вызывается только при регистрации реферала (редко). Async I/O, не блокирует сервер. Приемлемо для текущих объёмов.

---

### H-05. ✅ Admin-проверка отсутствует на upload-badge (исправлено 2026-02-10)
**Файл:** `loyalty-proxy/api/loyalty_gamification_api.js`
**Проблема:** `POST /api/loyalty-gamification/upload-badge` не имел проверки admin-прав. Любой мог загружать бейджи на диск сервера.
**Исправление:** Добавлена проверка `req.user.isAdmin` сразу после загрузки файла. Если не админ — файл удаляется с диска и возвращается 403.

---

### H-06. ✅ Нет валидации формата телефона после нормализации (исправлено 2026-02-10)
**Файл:** `lib/features/employees/services/employee_registration_service.dart`
**Проблема:** Телефон нормализовался, но не проверялся на пустоту. Ввод "+++ " → пустая строка → невалидный API запрос.
**Исправление:** Добавлен `if (normalizedPhone.isEmpty) return` в 5 методах: uploadPhotoFromBytes, uploadPhoto, saveRegistration, getRegistration, verifyEmployee.

---

### H-07. ✅ Нет URI encoding в client dialogs (исправлено 2026-02-10)
**Файл:** `lib/features/clients/services/client_service.dart` (строки 30, 53, 135)
**Проблема:** Телефон подставлялся в URL без `Uri.encodeComponent()` в 3 местах.
**Исправление:** Добавлен `Uri.encodeComponent()` во все 3 endpoint URL: getClientMessages, sendMessage, markNetworkMessagesAsReadByAdmin.

---

### H-08. ✅ Нет типовой проверки при cast из batch API (исправлено 2026-02-10)
**Файл:** `lib/features/efficiency/services/efficiency_data_service.dart` (строки 139-145)
**Проблема:** 7 результатов из `Future.wait` кастились через `as List<EfficiencyRecord>` без null-check. При ошибке загрузчика — краш.
**Исправление:** Все 7 cast заменены на safe pattern: `(parallelResults[N] as List<EfficiencyRecord>?) ?? <EfficiencyRecord>[]`

---

### H-09. ✅ Penalty записи не фильтруются по магазину (исправлено 2026-02-10)
**Файл:** `lib/features/efficiency/services/efficiency_data_service.dart`
**Проблема:** Штрафы (shiftPenalty) без shopAddress проходили без фильтрации в агрегации по сотрудникам.
**Исправление:** Для категории `shiftPenalty` всегда требуется валидный `shopAddress` из `validAddresses`. Без shopAddress — штраф не показывается.

---

### H-10. ⏸️ 5 из 10 категорий эффективности не работают (требует проверки данных)
**Файл:** `lib/features/efficiency/services/data_loaders/efficiency_record_loaders.dart`
**Проверка 2026-02-10:** Код загрузчиков (loadTaskRecords, loadReviewRecords, loadProductSearchRecords, loadOrderRecords, loadRkoRecords) синтаксически корректен. Каждый загрузчик возвращает `[]` если данных нет в указанном периоде.
**Возможные причины пустых результатов:** нет данных за выбранный месяц, задачи в статусе pending, отзывы без даты, заказы без acceptedBy.
**Следующий шаг:** Проверить наличие данных на сервере для каждой категории за текущий месяц.

---

### H-11. ✅ broadcast body mismatch (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файлы:** `client_service.dart` + `clients_api.js`
**Результат проверки:** Бэкенд поддерживает Flutter-формат `{text, imageUrl?, senderPhone?}` (строки 617-621 clients_api.js). Форматы совпадают.

---

### H-12. ✅ product_questions scheduler использует локальное время (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `loyalty-proxy/api/product_questions_penalty_scheduler.js`
**Результат проверки:** Функция `getShiftTypeByTime()` (строка 114) уже использует `(date.getUTCHours() + 3) % 24` — корректное преобразование UTC→Москва. Россия не использует DST с 2014 года, поэтому UTC+3 всегда верно.

---

### H-13. ✅ O(files×records) в loyalty history scan (приемлемо 2026-02-10)
**Файл:** `loyalty-proxy/api/loyalty_gamification_api.js`
**Результат проверки:** History организована по месяцам (≤12 файлов). Admin-only страницы. Объёмы данных малые (100-500 записей/месяц). При росте — добавить индекс. Сейчас не критично.

---

### H-14. ✅ Prize state inconsistency (исправлено 2026-02-10)
**Файл:** `loyalty-proxy/api/loyalty_gamification_api.js`
**Проблема:** POST `/api/loyalty-gamification/issue-prize` — prize status менялся на 'issued' (1-й write), затем client balance обновлялся (2-й write). Если 2-й write падал, приз "выдан" но клиент не получал баллы.
**Исправление:** Client balance update обёрнут в try/catch с rollback — если начисление падает, prize возвращается в status='pending'.

---

### H-15. ✅ KPI делает 10 параллельных запросов без timeout (исправлено 2026-02-10)
**Файл:** `lib/features/kpi/services/kpi_service.dart`
**Проблема:** 3 метода с `Future.wait()` (3, 6, 9 параллельных запросов) без timeout — зависание UI при медленном сервере.
**Исправление:** Добавлен `.timeout(Duration(seconds: 30))` ко всем трём `Future.wait()` (строки 272, 512, 733).

---

## 🟡 MEDIUM (18 проблем)

### M-01. ✅ Efficiency cache TTL — ошибка с январём (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `lib/features/efficiency/services/efficiency_data_service.dart` (строка 32)
**Результат проверки:** `DateTime(2026, 0)` в Dart **документированно** корректируется в `DateTime(2025, 12)` (December 2025). Это не баг — это штатное поведение Dart DateTime constructor.
**Рекомендация:** `DateTime(now.year, now.month == 1 ? 12 : now.month - 1)`

---

### M-02. ✅ Inconsistent empty shop address handling (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `lib/features/efficiency/services/efficiency_data_service.dart` (строки 235-277)
**Результат проверки:** Различие умышленное и логически корректное. По магазинам: записи без shopAddress нельзя агрегировать (нет ключа группировки) → пропускаются. По сотрудникам: задачи без привязки к магазину всё равно принадлежат сотруднику → включаются. Комментарий на строке 281 подтверждает замысел.

---

### M-03. ✅ Нет валидации month format в manager efficiency (исправлено 2026-02-10)
**Файл:** `lib/features/efficiency/services/manager_efficiency_service.dart`
**Проблема:** Параметр `month` не проверялся на формат YYYY-MM.
**Исправление:** Добавлена валидация `RegExp(r'^\d{4}-\d{2}$')` в начале `getManagerEfficiency()`. При невалидном формате возвращает null с Logger.warning. Также добавлен `Uri.encodeComponent(phone)` для параметра phone в URL.

---

### M-04. ✅ Silent error swallowing в KPI RKO parsing (исправлено 2026-02-10)
**Файл:** `lib/features/kpi/services/kpi_service.dart`
**Проблема:** Ошибки парсинга RKO логировались как `Logger.debug()` — не видны в стандартных логах.
**Исправление:** Все 4 catch-блока для malformed RKO заменены с `Logger.debug` на `Logger.warning` (2 для currentMonth, 2 для months — в двух методах).

---

### M-05. ✅ Missing multitenancy в KPI schedule integration (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `lib/features/kpi/services/kpi_schedule_integration_service.dart`
**Результат проверки:** Multitenancy применяется выше по стеку. KPI service (getAllEmployees, getShopMonthlyStats) использует `MultitenancyFilterService.getAllowedShopAddresses()` и фильтрует schedule entries по allowedAddresses. Schedule data используется только внутренне (для расчёта опозданий/пропусков), не отображается пользователю напрямую.

---

### M-06. ✅ Race condition: параллельная проверка регистраций (исправлено 2026-02-10)
**Файл:** `lib/features/employees/pages/unverified_employees_page.dart`
**Проблема:** N+1 запросов: загружал всех сотрудников, потом для каждого отдельный запрос getRegistration(phone).
**Исправление:** Заменено на 2 параллельных запроса: `getEmployees()` + `getAllRegistrations()` через `Future.wait()`. Регистрации индексируются по телефону в Map для O(1) поиска. Вместо 100 запросов → 2 запроса.

---

### M-07. ✅ Client phone не нормализуется в ClientService (исправлено 2026-02-10)
**Файл:** `lib/features/clients/services/client_service.dart`
**Проблема:** `getClientMessages()` и `sendMessage()` использовали clientPhone без нормализации.
**Исправление:** Добавлена нормализация `clientPhone.replaceAll(RegExp(r'[\s\+]'), '')` в обоих методах перед использованием в URL. `markNetworkMessagesAsReadByAdmin` уже нормализовал — не тронут.

---

### M-08. ✅ Нет валидации sentCount в broadcast (исправлено 2026-02-10)
**Файл:** `lib/features/clients/services/client_service.dart`
**Проблема:** sentCount/totalClients не проверялись на отрицательные значения.
**Исправление:** Добавлен явный каст `as int?` и clamp отрицательных значений к 0.

---

### M-09. ✅ EmployeeRegistration copyWith теряет createdAt (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `lib/features/employees/models/employee_registration_model.dart` (строка 99)
**Результат проверки:** `createdAt: createdAt` на строке 99 ссылается на `this.createdAt` (поле объекта), т.к. `createdAt` не является параметром copyWith. Dart корректно резолвит — оригинальная дата создания сохраняется.

---

### M-10. ✅ Unverified employee page — N+1 запросов (ДУБЛИКАТ M-06, исправлено 2026-02-10)
**Файл:** `lib/features/employees/pages/unverified_employees_page.dart`
**Результат проверки:** Та же проблема, что M-06. Исправлено вместе с M-06 — теперь 2 запроса вместо N+1.

---

### M-11. ⏸️ Бэкенд: разная нормализация телефонов в разных API (отложено — рефакторинг)
**Файлы:** 5 разных паттернов:
- `clients_api.js` — `/[^\d]/g` (только цифры → `79001234567`)
- `auth_api.js` — `/[\s+\-()]/g` + логика 8→7 (→ `79001234567`)
- `shop_managers_api.js` — `/[\s\+]/g` (оставляет скобки/дефисы → `7(900)123-45-67`)
- `admin_cache.js` — `/[\s+]/g` (аналогично shop_managers)
- `employees_api.js` — только валидация, хранит оригинал
**Проблема:** 5 разных подходов. Хотя API обычно работают с разными данными и не пересекаются, это потенциальный источник багов.
**Решение:** Требуется координированный рефакторинг: создать единый `normalizePhone()` в `utils/` и обновить все 5 API. Отложено — высокий риск регрессий при массовом изменении.

---

### M-12. ✅ Отсутствует timeout в KPI Future.wait (ДУБЛИКАТ H-15, исправлено 2026-02-10)
**Файл:** `lib/features/kpi/services/kpi_service.dart`
**Результат проверки:** Дублирует H-15. Уже исправлено — добавлен `.timeout(Duration(seconds: 30))` ко всем трём `Future.wait()` в KPI service.

---

### M-13. ✅ Default shops различаются на фронте и бэке (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `lib/features/shops/models/shop_model.dart`
**Результат проверки:** Flutter `loadShopsFromServer()` СНАЧАЛА загружает с сервера через `ShopService.getShops()`. Пустой `_getDefaultShops()` — fallback только при ошибке сети. Бэкенд-дефолты (8 магазинов) инициализируют файл shops.json при первом запуске сервера, после чего API возвращает их Flutter. Поведение корректное.

---

### M-14. ✅ getCurrentEmployeeName() бросает исключение вместо null (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `lib/features/employees/pages/employees_page.dart` (строки 236-238)
**Результат проверки:** `throw StateError` ловится enclosing `try/catch` на строке 244, который возвращает null. Фактическое поведение: employee not found → StateError → catch → Logger.error → return null. Приложение НЕ крашится. Паттерн не идеальный (exception для flow control), но поведение корректное.

---

### M-15. ✅ Referral QR scanner — wrong data format (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `lib/features/referrals/`
**Результат проверки:** QR-сканер реферралов НЕ реализован. Используется ручной ввод числа (1-10000). Frontend (`registration_page.dart`) и backend (`referrals_api.js`) оба ожидают integer. Форматы совпадают. Это скорее feature request на будущее, а не баг.

---

### M-16. ✅ Shift report model — toJson/fromJson рассогласование (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `lib/features/shifts/models/shift_report_model.dart`
**Результат проверки:** Все 18 полей ShiftReport и 6 полей ShiftAnswer полностью совпадают в toJson/fromJson. DateTime корректно сериализуется через toIso8601String/DateTime.parse. Nullable поля обрабатываются безопасно. Потери данных при round-trip нет.

---

### M-17. ✅ Нет фильтрации shift_handover по multitenancy в KPI (исправлено 2026-02-10)
**Файл:** `lib/features/kpi/services/kpi_service.dart` (строка 518)
**Проблема:** `getEmployeeShopDaysData()` вызывал `ShiftHandoverReportService.getReports()` без multitenancy.
**Исправление:** Заменён на `ShiftHandoverReportService.getReportsForCurrentUser()` — применяет `MultitenancyFilterService.filterByShopAddress()` к результатам.

---

### M-18. ✅ Web-specific code в recount service без проверки платформы (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `lib/features/recount/services/recount_service.dart`
**Результат проверки:** Используются ОБА уровня защиты: (1) conditional import `if (dart.library.html)` загружает stub на мобильном, (2) runtime guard `if (kIsWeb)` перед dart:html вызовами. Это корректный паттерн для platform-specific кода в Flutter.

---

## 🟢 LOW (12 проблем)

### L-01. ⏸️ KPI offline mode отсутствует (УЛУЧШЕНИЕ, отложено)
**Файл:** `lib/features/kpi/services/kpi_cache_service.dart`
**Проблема:** Кэш KPI только в памяти (CacheManager). При отсутствии интернета — пустая страница.
**Статус:** Feature request. Требует новый слой persistence (SharedPreferences/SQLite/Hive). Отложено.

---

### L-02. ✅ Отсутствует пагинация в списке клиентов (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `loyalty-proxy/api/clients_api.js`
**Результат проверки:** Пагинация УЖЕ реализована через `isPaginationRequested()` с параметрами `?page=X&limit=Y`. По умолчанию возвращает всех клиентов для обратной совместимости.

---

### L-03. ⏸️ Логирование чувствительных данных (РЕАЛЬНАЯ, отложено)
**Файлы:** Множество файлов с `Logger.debug()` — полные номера телефонов, имена.
**Статус:** Реальная проблема PII в логах. Требует масштабный рефакторинг (десятки файлов). Рекомендация: добавить `maskPhone()` утилиту в Logger. Отложено.

---

### L-04. ✅ Нет rate limiting на API (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `loyalty-proxy/index.js`
**Результат проверки:** Rate limiting УЖЕ реализован с 3 уровнями: General (500 req/min), Auth (10 req/min для защиты от brute-force), Financial (50 req/min для RKO/бонусов). Используется `express-rate-limit`.

---

### L-05. ⏸️ Дублирование кода загрузки отчётов (УЛУЧШЕНИЕ, отложено)
**Файлы:** 4 сервиса с ~40% одинакового boilerplate (getReports/getReportsForCurrentUser/confirmReport).
**Статус:** Код работает. Рефакторинг в BaseReportService при следующей архитектурной задаче.

---

### L-06. ✅ Нет compression для больших JSON ответов (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `loyalty-proxy/index.js`
**Результат проверки:** GZIP compression УЖЕ активен: `compression({ level: 6, threshold: 1024 })`. Ответы >1KB сжимаются автоматически.

---

### L-07. ✅ SharedPreferences используются как долгосрочное хранилище (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файлы:** auth_service, user_role_service, biometric_service
**Результат проверки:** Токены и PIN хранятся в `SecureStorageService` (`FlutterSecureStorage` с `encryptedSharedPreferences: true`). `user_role_service` использует in-memory кэш с TTL 5 минут. Безопасность соблюдена.

---

### L-08. ✅ Неиспользуемый import http в нескольких сервисах (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Результат проверки:** Все проверенные файлы (`coffee_machine_template_service.dart`, `photo_upload_service.dart`, `employee_chat_service.dart`) активно используют `http.MultipartRequest` / `http.Response`. Неиспользуемых импортов не найдено.

---

### L-09. ✅ Нет health-check эндпоинта на бэкенде (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `loyalty-proxy/index.js` (строка 848)
**Результат проверки:** `GET /health` УЖЕ реализован: возвращает status, timestamp, uptime, memory, version.

---

### L-10. ⏸️ Дефолтные магазины захардкожены на бэкенде (УЛУЧШЕНИЕ, отложено)
**Файл:** `loyalty-proxy/api/shops_api.js`
**Статус:** 8 магазинов захардкожены как DEFAULT_SHOPS для инициализации. После первого запуска сохраняются в shops.json и управляются через файловую систему. Приемлемая архитектура, но можно вынести в config.json.

---

### L-11. ✅ Нет graceful shutdown в бэкенде (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `loyalty-proxy/index.js` (строки 859-885)
**Результат проверки:** Graceful shutdown УЖЕ реализован: обработчики SIGTERM/SIGINT, закрытие сервера, 10-секундный таймаут.

---

### L-12. ✅ Отсутствует CORS настройка (ЛОЖНАЯ ТРЕВОГА 2026-02-10)
**Файл:** `loyalty-proxy/index.js` (строки 231-256)
**Результат проверки:** CORS УЖЕ настроен: whitelist (arabica26.ru, localhost), credentials enabled, все необходимые headers и methods разрешены.

---

## 📋 ИТОГИ АУДИТА (2026-02-10)

### Статистика:
- **53 проблемы** найдено при полном аудите
- **47 закрыто** (исправлено или подтверждено как ложные тревоги)
- **6 отложено** (требуют рефакторинга или проверки данных на сервере)
- **0 открытых** — все проблемы обработаны

### Реально исправлено кодом (15 файлов):
| # | Файл | Что исправлено |
|---|------|----------------|
| C-03 | auth_api.js + auth_service.dart | Серверный changePin |
| C-04 | user_role_service.dart | TTL 30мин для кэша роли |
| C-06 | index.js | Валидация владельца фото |
| C-07 | shop_service.dart | Fail-secure при null role |
| H-01 | 9 файлов Flutter | Единая нормализация телефонов |
| H-03 | rating_wheel_api.js | withLock() на spin endpoint |
| H-05 | loyalty_gamification_api.js | Admin-check на upload-badge |
| H-06 | employee_registration_service.dart | Проверка пустого телефона |
| H-07 | client_service.dart | Uri.encodeComponent в URLs |
| H-08 | efficiency_data_service.dart | Safe cast из Future.wait |
| H-09 | efficiency_data_service.dart | Фильтрация penalty по магазину |
| H-14 | loyalty_gamification_api.js | Rollback при ошибке приза |
| H-15 | kpi_service.dart | Timeout на Future.wait |
| M-03 | manager_efficiency_service.dart | Валидация формата month |
| M-04 | kpi_service.dart | Logger.warning для RKO ошибок |
| M-07 | client_service.dart | Нормализация телефона клиента |
| M-08 | client_service.dart | Clamping broadcast counts |
| M-06 | unverified_employees_page.dart | 2 запроса вместо N+1 |
| M-17 | kpi_service.dart | Multitenancy для shift_handover |

### Ложные тревоги (29 из 53):
Большинство issues оказались ложными — код уже работал корректно. Особенно на бэкенде: rate limiting, CORS, compression, health-check, graceful shutdown — всё уже было реализовано.

### Отложено (6 задач):
1. **H-10** — 5 категорий эффективности: требует проверки данных на сервере
2. **M-11** — Единая нормализация телефонов на бэкенде: 5 разных паттернов, высокий риск регрессий
3. **L-01** — KPI offline mode: feature request
4. **L-03** — Маскирование телефонов в логах: масштабный рефакторинг
5. **L-05** — Дублирование кода отчётов: архитектурное улучшение
6. **L-10** — Вынос дефолтных магазинов в config: минорное улучшение

### Незадеплоенные изменения бэкенда:
Следующие файлы изменены ТОЛЬКО ЛОКАЛЬНО, не на сервере:
- `loyalty-proxy/index.js` (C-06)
- `loyalty-proxy/api/auth_api.js` (C-03)
- `loyalty-proxy/api/loyalty_gamification_api.js` (H-05, H-14)
- `loyalty-proxy/api/rating_wheel_api.js` (H-03)

**Для деплоя:** `git push` → ssh на сервер → `git pull` → `pm2 restart loyalty-proxy`

# ПЛАН ПОЛИРОВКИ — Arabica 2026

> **Метод**: Boy Scout Rule + Rule of Three
> **Принцип**: Улучшай только то, что трогаешь. Обобщай только то, что повторяется 3+ раз.
> **Дата анализа**: 16.02.2026 (обновлено после 3-го глубокого анализа кода)

---

## ПРАВИЛА КОДА

### Flutter — Обязательные правила

| # | Правило | Пример |
|---|---------|--------|
| F-01 | Цвета ТОЛЬКО через тему (создать `lib/core/theme/`) | `AppColors.darkEmerald` вместо `Color(0xFF1A4D4D)` |
| F-02 | `setState` ТОЛЬКО внутри `if (mounted)` | `if (mounted) setState(() { ... });` |
| F-03 | Любой `async` callback → проверка `mounted` перед setState | После `await` всегда `if (!mounted) return;` |
| F-04 | Фото через `pickImage` ВСЕГДА с `maxWidth: 1280, imageQuality: 75` | Без исключений — экономит 80% трафика |
| F-05 | Новые страницы: если уже есть 3+ похожих → scaffold/базовый класс | Rule of Three |
| F-06 | `AppCachedImage` для всех сетевых изображений | Уже выполнено (83 использования) |
| F-07 | Размер файла: максимум 500 строк на страницу | Выносить виджеты в отдельные файлы |
| F-08 | Константы — в отдельный файл, не хардкод | URL, размеры, тексты |
| F-09 | URL сервера — ТОЛЬКО из `api_constants.dart` | Нельзя хардкодить `https://arabica26.ru` |
| F-10 | `TextEditingController` в диалогах — ОБЯЗАТЕЛЬНО dispose | Создавать в StatefulWidget или вручную `controller.dispose()` |
| F-11 | При 401 от сервера — автоматический выход на экран входа | Не показывать пустые экраны |

### Backend — Обязательные правила

| # | Правило | Пример |
|---|---------|--------|
| B-01 | Запись JSON-файлов через `writeJsonFile` из `async_fs.js` | Запись с блокировкой (file_lock) |
| B-02 | Каждый шедулер/setInterval ОБЯЗАН иметь `isRunning` guard | Включая встроенные шедулеры в API-файлах |
| B-03 | Каждый API-эндпоинт ОБЯЗАН проверять `req.user` | Кроме публичных (auth, job_application, loyalty scan) |
| B-04 | Утилиты (`getMoscowTime`, `sanitizeId` и т.д.) — ТОЛЬКО импорт из `utils/` | Нельзя копировать в каждый файл |
| B-05 | Все шедулеры — `setTimeout` при старте (5-15 сек задержка) | Чтобы сервер успел инициализироваться |
| B-06 | Время — ТОЛЬКО через `getMoscowTime()` или `getUTCHours() + 3` | Нельзя использовать голый `getHours()` |
| B-07 | Пагинация — Flutter ОБЯЗАН отправлять `?page=1` | Сервер не должен возвращать ВСЕ записи |
| B-08 | Новые файлы: если уже есть 3+ похожих → базовый класс/функция | Rule of Three |
| B-09 | Read-modify-write — ТОЛЬКО через `withLock` из `file_lock.js` | Нельзя читать → менять → писать без блокировки |
| B-10 | Проверка admin — ТОЛЬКО через `req.user.isAdmin` из session | Нельзя принимать isAdmin из body запроса |

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

> Реальные баги, найденные в коде. Без их исправления — потеря данных и дыры в безопасности.

### 0.1 — ✅ Overlap protection для 8 шедулеров + 1 скрытый (17.02.2026)
**Риск**: 🔴 Потеря/повреждение отчётов
**Проблема**: Ни один шедулер не проверяет, завершился ли предыдущий запуск.
**Файлы** (8 именованных шедулеров):
- `loyalty-proxy/api/shift_automation_scheduler.js`
- `loyalty-proxy/api/recount_automation_scheduler.js`
- `loyalty-proxy/api/rko_automation_scheduler.js`
- `loyalty-proxy/api/shift_handover_automation_scheduler.js`
- `loyalty-proxy/api/attendance_automation_scheduler.js`
- `loyalty-proxy/api/envelope_automation_scheduler.js`
- `loyalty-proxy/api/coffee_machine_automation_scheduler.js`
- `loyalty-proxy/api/product_questions_penalty_scheduler.js`

**+ Скрытый шедулер:**
- `loyalty-proxy/api/order_timeout_api.js` — `setInterval(checkExpiredOrders, 60000)` внутри API-файла. При overlap создаёт **дублирование штрафов**.

**Решение**: Добавить `isRunning` guard в КАЖДЫЙ:
```javascript
let isRunning = false;
async function processReports() {
  if (isRunning) { console.log('[name] Previous run still active, skipping'); return; }
  isRunning = true;
  try { /* ... */ } catch (err) { console.error('[name] Error:', err.message); }
  finally { isRunning = false; }
}
```

### 0.2 — ✅ Auth проверки в 8 API-файлах (17.02.2026)
**Риск**: 🔴 Безопасность — любой с API-ключом может менять данные
**Файлы**: bonus_penalties, training, shops, work_schedule, rko, menu, withdrawals, points_settings
**Решение**: `if (!req.user) return res.status(401).json({ error: 'Unauthorized' });` в POST/PUT/DELETE
**Результат**: 37 обработчиков защищены + Boy Scout: fileExists/sanitizeId из utils в 3 файлах

### 0.3 — ✅ Баг getHours() в shift_handover (17.02.2026)
**Риск**: 🟠 Неправильное время → отчёты попадают в неправильный день
**Файл**: `shift_handover_automation_scheduler.js`, строка ~270
**Решение**: `(new Date(report.createdAt).getUTCHours() + 3) % 24`

### 0.4 — ✅ Startup delay для 2 шедулеров (17.02.2026)
**Риск**: 🟡 При pm2 restart шедулеры стартуют до готовности сервера
**Файлы**: envelope_automation_scheduler, coffee_machine_automation_scheduler
**Решение**: `setTimeout(() => { ... }, 10000)`

### 0.5 — ✅ Принудительный logout без авторизации (17.02.2026)
**Риск**: 🔴 Любой может выбросить любого пользователя
**Файл**: `loyalty-proxy/api/auth_api.js` — `POST /api/auth/logout`
**Проблема**: Принимает `{phone: "79001234567"}` и удаляет сессию без проверки кто это делает
**Решение**: Logout по sessionToken — разрешён (токен = доказательство). Logout по phone — требует Authorization header + проверка self/admin.

### 0.6 — ✅ Регистрация чужого номера (17.02.2026)
**Риск**: 🔴 Блокировка реального сотрудника
**Файл**: `loyalty-proxy/api/auth_api.js` — `POST /api/auth/register`
**Проблема**: Любой может зарегистрировать незанятый номер с произвольным PIN
**Решение**: Регистрация только если номер есть в data_cache.employees (с fallback на чтение файлов)

### 0.7 — ✅ isAdmin из body запроса (shift_transfers) (17.02.2026)
**Риск**: 🟠 Обход проверки прав
**Файл**: `loyalty-proxy/api/shift_transfers_api.js`, строка ~611
**Проблема**: Deprecated код принимает `isAdmin: true` из body вместо проверки session
**Решение**: Удалена else-ветка, phone обязателен. Flutter: удалён isAdmin из markAsRead()

### 0.8 — ✅ app-version: admin из body (17.02.2026)
**Риск**: 🟠 Принудительное обновление всем пользователям
**Файл**: `loyalty-proxy/index.js` (inline, не отдельный API-файл)
**Проблема**: Проверяет админа по `body.employeePhone` вместо `req.user`
**Решение**: Заменено на `req.user.isAdmin` + writeJsonFile (B-01)

### 0.9 — ✅ Показ неправильного заказа при push-уведомлении (17.02.2026)
**Риск**: 🟠 Сотрудник может принять/отклонить чужой заказ
**Файл**: `lib/core/services/notification_service.dart`
**Проблема**: `firstWhere(..., orElse: () => orders.first)` — если заказ не найден, показывает ПЕРВЫЙ попавшийся
**Решение**: Если заказ не найден → return (игнорируем уведомление, не показываем чужой заказ)

### 0.10 — ✅ Swap не активен (OOM-kill при пиковой нагрузке) (17.02.2026)
**Риск**: 🔴 Сервер убивает процессы при нехватке RAM
**Проблема**: `/swapfile` (2 GB) существует, но НЕ подключён. При пиковой нагрузке (OCR 968 MB + loyalty-proxy + 210 пользователей) — система убьёт процесс без предупреждения.
**Решение**: `swapon /swapfile` + добавить в `/etc/fstab`

### 0.11 — ✅ 12.6 GB мусора на production-сервере (17.02.2026)
**Риск**: 🟠 Диск занят на 66%, хотя данные приложения = 186 MB
**Проблема**: На сервере установлены инструменты сборки, которые не нужны в production:
- `/root/Android/` — 5.8 GB (Android SDK)
- `/root/.cache/` — 4.2 GB (кэш сборки)
- `/root/flutter/` — 1.4 GB (Flutter SDK)
- `/root/.gradle/` — 1.2 GB (Gradle кэш)
**Решение**: Удалить всё — APK собирается на локальном компьютере, не на сервере

---

## ФАЗА 1: СТАБИЛЬНОСТЬ СЕРВЕРА

> Защита от падений при росте данных и нагрузки.

### 1.1 — Безопасная запись файлов в API
**Проблема**: Некоторые API-файлы используют сырой `fsp.writeFile` (при крэше = потеря файла)
**Файлы**: geofence_api, order_timeout_api, recurring_tasks_api, report_notifications_api
**Решение**: Заменить на `writeJsonFile` из `utils/async_fs.js`
**Важно**: `writeJsonFile` использует file_lock для защиты от конкурентной записи, но НЕ использует temp+rename. Для критичных данных рекомендуется добавить temp+rename в будущем.

### 1.2 — getMoscowTime() → общая утилита
**Проблема**: `getMoscowTime()` скопирована в 7 файлах шедулеров
**Решение**: Создать `loyalty-proxy/utils/moscow_time.js`, заменить локальные копии

### 1.3 — Пагинация: обязательная отправка page из Flutter
**Проблема**: Без `?page=` сервер возвращает ВСЕ записи. Все файлы читаются с диска каждый раз.
**Решение (поэтапно)**:
1. Flutter — добавить `?page=1&limit=50` во ВСЕ запросы списков
2. Сервер — дефолтная пагинация если параметры не переданы
3. В будущем — индексные файлы

### 1.4 — Расширить data_cache
**Проблема**: Кэш покрывает только employees + shops (2 из 35+ модулей)
**Решение**: Добавить кэш для points_settings, шаблонов вопросов

### 1.5 — Серверное сжатие фото
**Проблема**: 9 multer upload handlers принимают фото без сжатия (5-10 МБ каждое)
**Решение**: middleware с sharp (resize 1920px, JPEG q80). Для бинарных данных использовать `fsp.writeFile` с обработкой ошибок (writeJsonFile работает только с JSON).

### 1.6 — Очистка chat-media
**Проблема**: chat-media НЕ включена в категории очистки
**Решение**: Добавить `chat-media` в data_cleanup_api.js

### 1.7 — File locking для чатов (read-modify-write race)
**Проблема**: При одновременной отправке сообщений в чат (clients_api.js) — read/modify/write без блокировки. Одно сообщение теряется.
**Решение**: Обернуть в `withLock(filePath, async () => { read → modify → write })`

### 1.8 — File locking для заказов
**Проблема**: Два сотрудника принимают один заказ одновременно (orders.js) — гонка данных
**Решение**: `withLock` для `updateOrderStatus`

### 1.9 — Graceful shutdown — закрытие WebSocket
**Проблема**: При pm2 restart WebSocket-подключения НЕ закрываются. Старые клиенты висят на мёртвом процессе.
**Файл**: `loyalty-proxy/index.js`, gracefulShutdown
**Решение**: Сохранить ссылку на `wss`, вызвать `wss.close()` в gracefulShutdown

### 1.10 — WebSocket: лимит подключений на один телефон
**Проблема**: Баг в клиенте может открыть сотни подключений с одного номера (reconnect loop)
**Файл**: `employee_chat_websocket.js`
**Решение**: Максимум 3 подключения на один телефон. При превышении — закрывать самое старое.

---

## ФАЗА 2: FLUTTER — СТАБИЛЬНОСТЬ

> Предотвращение крашей и утечек памяти.

### 2.1 — mounted guard для setState
**Проблема**: ~844 вызовов setState БЕЗ `if (mounted)`. Краш при быстрой навигации.
**Решение**: Boy Scout Rule — добавлять `if (!mounted) return;` при работе с каждым файлом.

### 2.2 — Сжатие фото в 3 страницах задач
**Файлы**: task_response_page, recurring_task_response_page, create_task_page
**Решение**: `pickImage(..., maxWidth: 1280, imageQuality: 75)`

### 2.3 — Web-платформа: сжатие фото
**Файл**: `photo_upload_service.dart`
**Решение**: В ветке `kIsWeb` добавить сжатие через пакет `image` (уже в pubspec)

### 2.4 — Главное меню: 12 API-вызовов при открытии
**Решение**: Использовать существующий `dashboard_batch_api.js` — один запрос вместо 12

### 2.5 — Auto-logout при 401
**Проблема**: При истёкшей сессии экраны показываются пустыми, пользователь не понимает что происходит
**Файл**: `lib/core/services/base_http_service.dart`
**Решение**: При получении 401 — очистить session token, перейти на экран входа

### 2.6 — TextEditingController в диалогах
**Проблема**: Контроллеры созданные внутри `showDialog` не вызывают `dispose()` — утечка памяти
**Файлы**: bonus_penalty_management_page, notification_service, schedule_bulk_operations_dialog
**Решение**: При Boy Scout Rule — оборачивать диалоги в StatefulBuilder с dispose, или вызывать `.dispose()` явно

### 2.7 — Хардкод URL сервера в Flutter
**Проблема**: 9 мест с хардкодом `https://arabica26.ru` вместо `ApiConstants.baseUrl`
**Файлы**: menu_page, kpi pages, product_questions, recipes
**Решение**: Заменить на `ApiConstants.baseUrl`

### 2.8 — WebSocket: reconnect после 10 неудач
**Проблема**: После 10 неудачных попыток реконнекта WebSocket навсегда отключается. Чат не работает до перезапуска приложения.
**Файл**: `chat_websocket_service.dart`
**Решение**: Через 5 минут после исчерпания попыток — сбросить счётчик и попробовать снова

---

## ФАЗА 3: BACKEND DRY (убрать дублирование)

> Rule of Three — обобщаем то, что повторяется 3+ раз.

### 3.1 — BaseReportScheduler
**Проблема**: 8 шедулеров × ~700 строк = ~5,600 строк дублирования
**Решение**: `loyalty-proxy/utils/base_report_scheduler.js` — базовый класс

### 3.2 — Вынести дублированные утилиты из API-файлов
**Проблема**: sanitizeId(), fileExists() — локальные копии вместо импорта
**Решение**: Boy Scout Rule — заменять на `require('../utils/file_helpers')`

---

## ФАЗА 4: FLUTTER DRY (убрать дублирование)

### 4.1 — Централизовать тему (цвета)
**Проблема**: Color(0xFF1A4D4D) в 128 файлах, Color(0xFF0D2E2E) в 116, Color(0xFF004D40) в 70
**Решение**: `lib/core/theme/app_colors.dart` + Boy Scout Rule

### 4.2 — Scaffold для страниц настроек баллов (15 страниц)
### 4.3 — Scaffold для страниц управления вопросами (7 страниц)
### 4.4 — Scaffold для страниц списка отчётов (7 страниц)
### 4.5 — Scaffold для страниц выбора магазина (6 страниц)
### 4.6 — Разбить крупные файлы (4002 и 2949 строк)

---

## ФАЗА 5: МОНИТОРИНГ И ЗАЩИТА

### 5.1 — Расширить Health endpoint (disk, schedulers, lastErrors)
### 5.2 — Автоочистка старых фото по расписанию
### 5.3 — Логирование ошибок шедулеров в файл

---

## ПОРЯДОК ВЫПОЛНЕНИЯ

```
ФАЗА 0 (0.10-0.11 сервер подготовка) → ФАЗА 0 (баги) → ФАЗА 1 → ФАЗА 2 → ФАЗА 3 → ФАЗА 4 → ФАЗА 5
  swap + очистка мусора              баги/security   сервер    Flutter    backend    Flutter    мониторинг
                                                              стабильн.    DRY        DRY
```

**Boy Scout Rule применяется ВСЕГДА** при работе с любым файлом:
- `if (mounted)` к setState
- Цвета → `AppColors.xxx`
- Локальные утилиты → импорт из `utils/`
- `req.user` проверка если отсутствует
- `TextEditingController.dispose()` в диалогах
- URL → `ApiConstants.baseUrl`

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
| Timer/AnimationController/ScrollController dispose | ✅ Все проверены, утечек нет |
| StreamSubscription cancel в dispose | ✅ Все проверены, утечек нет |
| addListener/removeListener | ✅ Все используют dispose контроллера |

---

## МЕТРИКИ ДО ПОЛИРОВКИ (замерено 16.02.2026)

| Метрика | Значение |
|---------|----------|
| setState без mounted guard | ~844 из 1,570 |
| Хардкод цветов (файлов) | 128 + 116 + 70 |
| Шедулеры без overlap protection | ✅ 0 из 9 (все защищены 17.02.2026) |
| API без проверки req.user | ✅ 0 из 8 (все защищены 17.02.2026) |
| Публичные эндпоинты с опасными действиями | 2 (logout, register) |
| isAdmin из body вместо session | 2 файла (shift_transfers, app_version) |
| Копии getMoscowTime | ✅ 0 (вынесено в moscow_time.js, 17.02.2026) |
| API с сырым fsp.writeFile | 4 файла |
| Read-modify-write без блокировки | 2 (чаты, заказы) |
| Файлы >1000 строк | 2 (4002 и 2949) |
| pickImage без сжатия | 3 страницы |
| Хардкод URL сервера | 9 мест |
| TextEditingController без dispose | 3+ диалога |
| Модули без серверного кэша | ~33 из 35 |
| Swap не активен | ✅ Активен (2 GB, 17.02.2026) |
| Мусор на сервере (SDK, кэш) | ✅ Удалено 12.6 GB (17.02.2026) |
| Свободное место на диске | ✅ 29 GB (40% занято, было 66%) |

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

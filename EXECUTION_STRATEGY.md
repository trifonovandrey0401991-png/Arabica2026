# БЕЗОПАСНАЯ СТРАТЕГИЯ ВЫПОЛНЕНИЯ POLISHING_PLAN

> Покрывает ВСЕ 39 пунктов POLISHING_PLAN.md без исключений.
> Каждый пункт = конкретные шаги с проверкой.

## Общий принцип: "Один файл — один деплой — одна проверка"

---

## ПРОТОКОЛ БЕЗОПАСНОСТИ

### Перед КАЖДЫМ изменением на сервере:
```bash
# 1. Бэкап
ssh root@arabica26.ru "cp <ФАЙЛ> <ФАЙЛ>.backup-$(date +%Y%m%d-%H%M%S)"
# 2. Деплой
ssh root@arabica26.ru "cd /root/arabica_app && git pull origin refactoring/full-restructure"
ssh root@arabica26.ru "pm2 restart loyalty-proxy"
# 3. Проверка (ВСЕ ТРИ обязательно)
ssh root@arabica26.ru "pm2 logs loyalty-proxy --lines 20 --nostream"
node tests/api-test.js
curl https://arabica26.ru/health
```

### Откат (30 секунд):
```bash
ssh root@arabica26.ru "cp <ФАЙЛ>.backup-<ДАТА> <ФАЙЛ> && pm2 restart loyalty-proxy"
```

### Перед КАЖДЫМ изменением Flutter:
```bash
flutter analyze --no-fatal-infos
flutter build apk --debug
# установить на телефон, проверить конкретный экран
```

---

## ФАЗА 0: КРИТИЧЕСКИЕ БАГИ (Шаги 0a–25)

### Шаг 0a → POLISHING_PLAN 0.10 (Активировать swap)

| Шаг | Что | Риск |
|-----|-----|------|
| 0a | Активировать swap + добавить в fstab | Безопасный |

**Изменение:**
```bash
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
swapon --show  # проверка
```
**Почему безопасно:** Swap-файл уже создан (2 GB). Просто подключаем его. Ничего не ломается. Защищает от OOM-kill при пиковой нагрузке.
**Проверка:** `swapon --show` должен показать /swapfile 2G, `free -h` должен показать Swap: 2.0Gi.

---

### Шаг 0b → POLISHING_PLAN 0.11 (Удалить мусор — освободить 12.6 GB)

| Шаг | Что | Размер | Риск |
|-----|-----|--------|------|
| 0b-1 | Удалить `/root/Android/` (Android SDK) | 5.8 GB | Безопасный |
| 0b-2 | Удалить `/root/.cache/` (кэш сборки) | 4.2 GB | Безопасный |
| 0b-3 | Удалить `/root/flutter/` (Flutter SDK) | 1.4 GB | Безопасный |
| 0b-4 | Удалить `/root/.gradle/` (Gradle кэш) | 1.2 GB | Безопасный |

**Почему безопасно:** Это инструменты для сборки APK. APK собирается на локальном компьютере, а не на сервере. Сервер только запускает Node.js (loyalty-proxy). Flutter/Android SDK ему не нужны.
**Проверка:** `df -h /` должен показать ~38% использования вместо 66%.

⚠️ **Перед удалением:** убедиться что `/root/arabica_app/` НЕ зависит от `/root/flutter/` (это git-репозиторий с исходниками — Flutter не запускается на сервере).

---

### Шаги 1-2 → POLISHING_PLAN 0.4 (Startup delay)

| Шаг | Файл | Риск |
|-----|------|------|
| 1 | `loyalty-proxy/api/envelope_automation_scheduler.js` | Безопасный |
| 2 | `loyalty-proxy/api/coffee_machine_automation_scheduler.js` | Безопасный |

**Изменение:** Обернуть тело start-функции в `setTimeout(() => { ... }, 10000)`
**Почему безопасно:** Файлы изолированы. Добавляется лишь пауза 10 сек.

---

### Шаг 3 → POLISHING_PLAN 0.3 (Баг getHours)

| Шаг | Файл | Риск |
|-----|------|------|
| 3 | `loyalty-proxy/api/shift_handover_automation_scheduler.js` строка ~270 | Безопасный |

**Изменение:** `new Date(report.createdAt).getHours()` → `(new Date(report.createdAt).getUTCHours() + 3) % 24`

---

### Шаги 4-11 → POLISHING_PLAN 0.1 (Overlap protection — 8 именованных шедулеров)

| Шаг | Файл | Риск |
|-----|------|------|
| 4 | `product_questions_penalty_scheduler.js` | Безопасный |
| 5 | `envelope_automation_scheduler.js` | Безопасный |
| 6 | `coffee_machine_automation_scheduler.js` | Безопасный |
| 7 | `rko_automation_scheduler.js` | Безопасный |
| 8 | `recount_automation_scheduler.js` | Безопасный |
| 9 | `shift_automation_scheduler.js` | Безопасный |
| 10 | `shift_handover_automation_scheduler.js` | Безопасный |
| 11 | `attendance_automation_scheduler.js` | Безопасный |

**Изменение:** `let isRunning = false;` + в главной функции: `if (isRunning) return; isRunning = true; try { ... } finally { isRunning = false; }`

---

### Шаг 12 → POLISHING_PLAN 0.1 (Скрытый шедулер order_timeout)

| Шаг | Файл | Риск |
|-----|------|------|
| 12 | `loyalty-proxy/api/order_timeout_api.js` | Средний |

**Изменение:** Добавить `isRunning` guard в функцию `checkExpiredOrders` + обернуть `savePenalties` в `withLock`.
**Почему средний:** Этот файл — и API и шедулер одновременно. При overlap создаёт дубли штрафов. Нужно проверить что штрафы корректно считаются после изменения.
**Проверка:** api-test.js, pm2 logs. Ручная: создать заказ, дождаться истечения таймаута, проверить что штраф один (не два).

---

### Шаги 13-20 → POLISHING_PLAN 0.2 (Auth проверки)

⚠️ Шаг 13 — тестовый. Если Flutter не отправляет session token — откатываем.

| Шаг | Файл | Риск |
|-----|------|------|
| 13 | `points_settings_api.js` (наименее используемый) | Средний |
| 14 | `menu_api.js` | Средний |
| 15 | `training_api.js` | Средний |
| 16 | `shops_api.js` | Средний |
| 17 | `bonus_penalties_api.js` | Средний |
| 18 | `withdrawals_api.js` | Средний |
| 19 | `work_schedule_api.js` | Средний |
| 20 | `rko_api.js` | Средний |

**Изменение:** В POST/PUT/DELETE: `if (!req.user) return res.status(401).json({ error: 'Unauthorized' });`
**Ручная проверка:** Зайти как админ и выполнить действие после каждого шага.

---

### Шаги 21-22 → POLISHING_PLAN 0.5-0.6 (Auth: logout + register)

| Шаг | Файл | Что | Риск |
|-----|------|-----|------|
| 21 | `auth_api.js` — POST /logout | Добавить: logout только себя (req.user.phone === body.phone) или isAdmin | Средний |
| 22 | `auth_api.js` — POST /register | Добавить: регистрация только если phone в data_cache.employees | ⚠️ Высокий |

**Шаг 22 — ТОЧКА ВНИМАНИЯ:** Если проверка слишком строгая — новые сотрудники не смогут зарегистрироваться. Нужно убедиться что data_cache.employees содержит ВСЕХ сотрудников (включая новых).
**Проверка:** api-test.js. Ручная: попробовать зарегистрироваться как существующий сотрудник. Попробовать зарегистрировать несуществующий номер — должен получить ошибку.

---

### Шаги 23-24 → POLISHING_PLAN 0.7-0.8 (isAdmin из body)

| Шаг | Файл | Что | Риск |
|-----|------|-----|------|
| 23 | `shift_transfers_api.js` строка ~611 | Удалить else-ветку (isAdmin из body) | Безопасный |
| 24 | `app_version_api.js` | Заменить `body.employeePhone` → `req.user.isAdmin` | Средний |

---

### Шаг 25 → POLISHING_PLAN 0.9 (Неправильный заказ при push)

| Шаг | Файл | Риск |
|-----|------|------|
| 25 | `lib/core/services/notification_service.dart` | Безопасный |

**Изменение:** `orElse: () => orders.first` → если не найден, navigate к списку заказов вместо конкретного.
**Проверка:** flutter analyze. Ручная: отправить push-уведомление о заказе.

### 🛑 КОНТРОЛЬНАЯ ТОЧКА #1 (после шага 25)
- api-test.js 55/55 OK
- pm2 logs чистые
- Подождать 24 часа — все шедулеры прошли утренний и вечерний цикл
- Ручная проверка: смены, конверты, пересчёт, чат, задачи

---

## ФАЗА 1: СТАБИЛЬНОСТЬ СЕРВЕРА (Шаги 26–48)

### Шаг 26 → POLISHING_PLAN 1.6 (chat-media cleanup)

| Шаг | Файл | Риск |
|-----|------|------|
| 26 | `loyalty-proxy/api/data_cleanup_api.js` | Безопасный |

**Изменение:** Добавить `chat-media` в массив CLEANUP_CATEGORIES.

---

### Шаги 27-30 → POLISHING_PLAN 1.1 (Безопасная запись)

| Шаг | Файл | Риск |
|-----|------|------|
| 27 | `geofence_api.js` | Безопасный |
| 28 | `order_timeout_api.js` | Безопасный |
| 29 | `recurring_tasks_api.js` | Безопасный |
| 30 | `report_notifications_api.js` | ⚠️ Средний |

**Изменение:** `fsp.writeFile` → `writeJsonFile` из `utils/async_fs.js`
**Шаг 30:** После деплоя ждём 15 мин, проверяем push-уведомления.

---

### Шаги 31-38 → POLISHING_PLAN 1.2 (getMoscowTime утилита)

| Шаг | Файл | Риск |
|-----|------|------|
| 31 | НОВЫЙ: `loyalty-proxy/utils/moscow_time.js` | Безопасный |
| 32 | `product_questions_penalty_scheduler.js` | Безопасный |
| 33 | `coffee_machine_automation_scheduler.js` | Безопасный |
| 34 | `envelope_automation_scheduler.js` | Безопасный |
| 35 | `rko_automation_scheduler.js` | Безопасный |
| 36 | `recount_automation_scheduler.js` | Безопасный |
| 37 | `attendance_automation_scheduler.js` | Безопасный |
| 38 | `shift_automation_scheduler.js` | Безопасный |

---

### Шаги 39-40 → POLISHING_PLAN 1.7-1.8 (File locking: чаты + заказы)

| Шаг | Файл | Что | Риск |
|-----|------|-----|------|
| 39 | `loyalty-proxy/api/clients_api.js` | Обернуть read-modify-write сообщений в `withLock(filePath, ...)` | Средний |
| 40 | `loyalty-proxy/modules/orders.js` | Обернуть `updateOrderStatus` в `withLock` | Средний |

**Проверка:** api-test.js, pm2 logs. Ручная: отправить 2 сообщения в чат быстро подряд — оба должны сохраниться. Два сотрудника пробуют принять один заказ — только один должен получить его.

---

### Шаг 41 → POLISHING_PLAN 1.9 (Graceful shutdown WebSocket)

| Шаг | Файл | Риск |
|-----|------|------|
| 41 | `loyalty-proxy/index.js` — gracefulShutdown | Средний |

**Изменение:** Сохранить ссылку на `wss` (WebSocket.Server) при создании. В `gracefulShutdown` добавить `wss.close()` перед `server.close()`.
**Проверка:** pm2 restart, проверить что чат переподключается без задержки.

---

### Шаг 42 → POLISHING_PLAN 1.10 (WebSocket: лимит подключений)

| Шаг | Файл | Риск |
|-----|------|------|
| 42 | `loyalty-proxy/api/employee_chat_websocket.js` | Средний |

**Изменение:** При добавлении нового WS в `connections.get(phone)` — если Set.size >= 3, закрыть самое старое подключение.
**Проверка:** pm2 logs. Открыть чат на 4 устройствах — 4-е должно работать, но 1-е должно отключиться.

---

### Шаги 43-44 → POLISHING_PLAN 1.3 (Пагинация — ОБЯЗАТЕЛЬНО ОБЕ СТОРОНЫ)

⚠️ Пагинация — это СЕРВЕРНАЯ + FLUTTER сторона. Обе нужны.

**Шаг 43 — Сервер: дефолтная пагинация**

| Шаг | Файл | Риск |
|-----|------|------|
| 43 | `loyalty-proxy/utils/pagination.js` | Средний |

**Изменение:** Добавить default page=1, limit=50 если параметры не переданы.

**Шаг 44 — Flutter: отправка ?page=1&limit=50 во всех списковых запросах**

| Шаг | Файлы | Риск |
|-----|-------|------|
| 44 | Все сервисы по одному (shifts_service, recount_service, envelope_service и т.д.) | Средний |

**Для подгрузки следующих страниц:** Добавить логику "загрузить ещё" вместе с scaffold-ами (Фаза 4.4).

### 🛑 КОНТРОЛЬНАЯ ТОЧКА #2 (после шага 44)
- Подождать 2-3 дня
- Все списки показывают данные, прокрутка работает
- Шедулеры стабильны

---

### Шаги 45a-45c → POLISHING_PLAN 1.4 (Расширение data_cache)

| Шаг | Файл | Риск |
|-----|------|------|
| 45a | `loyalty-proxy/utils/data_cache.js` — добавить кэш для points_settings | Средний |
| 45b | `loyalty-proxy/api/points_settings_api.js` — использовать кэш вместо чтения файлов | Средний |
| 45c | `loyalty-proxy/utils/data_cache.js` — добавить кэш для шаблонов вопросов | Средний |

**Изменение:** По аналогии с существующим кэшем employees/shops — добавить preload + периодическое обновление для частых данных.
**Проверка:** После каждого подшага — api-test.js, затем проверить что настройки баллов / вопросы отображаются корректно. Изменить настройку и убедиться что изменение видно (кэш инвалидируется).

---

### Шаги 46a-46j → POLISHING_PLAN 1.5 (Серверное сжатие фото)

| Шаг | Файл | Риск |
|-----|------|------|
| 46a | НОВЫЙ: `loyalty-proxy/utils/image_compress.js` — создать middleware | Безопасный |
| 46b | `loyalty-proxy/index.js` — подключить middleware к 1 upload handler (shift photos) | Средний |
| 46c-46j | `loyalty-proxy/index.js` — подключить к остальным 8 handlers по одному | Средний |

**Изменение:** Создать middleware с sharp:
```javascript
async function compressUpload(req, res, next) {
  if (req.file && req.file.mimetype.startsWith('image/')) {
    const compressed = await sharp(req.file.path)
      .resize(1920, 1920, { fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: 80 }).toBuffer();
    // Для бинарных данных — fsp.writeFile (НЕ writeJsonFile, он только для JSON)
    await fsp.writeFile(req.file.path, compressed);
  }
  next();
}
```
**Шаг 46b — тестовый:** Подключаем только к shift photos. Проверяем: сдать смену с фото → фото отображается нормально → размер файла на сервере уменьшился.
**Шаги 46c-46j:** По одному handler за раз, проверяя каждый.

---

## ФАЗА 2: FLUTTER — СТАБИЛЬНОСТЬ (Шаги 50–80)

### Шаги 50-52 → POLISHING_PLAN 2.2 (Сжатие фото в 3 task pages)

| Шаг | Файл | Риск |
|-----|------|------|
| 50 | `lib/features/tasks/pages/task_response_page.dart` | Безопасный |
| 51 | `lib/features/tasks/pages/recurring_task_response_page.dart` | Безопасный |
| 52 | `lib/features/tasks/pages/create_task_page.dart` | Безопасный |

**Изменение:** `pickImage(source: ...)` → `pickImage(source: ..., maxWidth: 1280, imageQuality: 75)`

---

### Шаг 53 → POLISHING_PLAN 2.3 (Web-сжатие фото)

| Шаг | Файл | Риск |
|-----|------|------|
| 53 | `lib/core/services/photo_upload_service.dart` | Средний |

**Изменение:** В ветке `kIsWeb` добавить сжатие через пакет `image` (уже есть в pubspec: `image: ^4.3.0`). Аналогично мобильной версии: если >500KB → resize до 1280px, JPEG q75.
**Проверка:** flutter analyze, открыть web-версию, загрузить фото, убедиться что фото отображается нормально и размер уменьшился.

---

### Шаги 54-59 → POLISHING_PLAN 2.1 (mounted guard — 6 самых важных + план для остальных)

**Первые 6 — явные шаги:**

| Шаг | Файл | Почему первый |
|-----|------|---------------|
| 54 | `lib/app/pages/main_menu_page.dart` | 12 async-вызовов |
| 55 | `lib/features/shifts/pages/shift_questions_page.dart` | Самый частый экран |
| 56 | `lib/features/attendance/pages/attendance_month_page.dart` | Ежедневный экран |
| 57 | `lib/features/tasks/pages/my_tasks_page.dart` | Часто открывают |
| 58 | `lib/features/employee_chat/pages/employee_chat_page.dart` | Быстрые переходы |
| 59 | `lib/features/efficiency/pages/my_efficiency_page.dart` | Много async |

**Изменение:** Перед каждым `setState(() {` после `await` добавить `if (!mounted) return;`

**Остальные ~199 файлов — план обхода по батчам:**

| Батч | Файлы | Когда |
|------|-------|-------|
| Батч A (шаги 60-69) | `lib/app/pages/` — все 6 hub-страниц | Сразу после шагов 54-59 |
| Батч B (шаги 70-79) | `lib/features/shifts/pages/` — все страницы модуля смен | Следующий |
| Батч C-Z | Остальные модули по алфавиту, по 5-10 файлов за сессию | По Boy Scout Rule + выделенные сессии |

**Правило:** При каждой работе с ЛЮБЫМ Flutter файлом — сначала проверить все setState в нём, добавить `if (!mounted)` где нет. После каждого батча — `flutter analyze`.

**Метрика:** Вести счётчик. Начали с 844 незащищённых. Цель: 0.

---

### Шаг 80 → POLISHING_PLAN 2.5 (Auto-logout при 401)

| Шаг | Файл | Риск |
|-----|------|------|
| 80 | `lib/core/services/base_http_service.dart` | Средний |

**Изменение:** В обработчике HTTP-ответов добавить проверку: если код ответа 401 → очистить session token → перейти на экран входа.
**Почему средний:** Это затрагивает ВСЕ HTTP-запросы в приложении. Нужно убедиться что 401 возвращается ТОЛЬКО при истёкшей сессии, а не при других ошибках.
**Проверка:** flutter analyze. Ручная: выйти из приложения, удалить сессию на сервере, вернуться в приложение — должен перенаправить на вход.

---

### Шаги 81-83 → POLISHING_PLAN 2.6 (TextEditingController dispose в диалогах)

| Шаг | Файл | Риск |
|-----|------|------|
| 81 | `lib/features/efficiency/pages/bonus_penalty_management_page.dart` | Безопасный |
| 82 | `lib/core/services/notification_service.dart` | Безопасный |
| 83 | `lib/features/work_schedule/pages/schedule_bulk_operations_dialog.dart` | Безопасный |

**Изменение:** Обернуть создание диалогов в StatefulBuilder с dispose, или вызывать `.dispose()` явно в `then()` после закрытия диалога.
**Проверка:** flutter analyze.

---

### Шаги 84-92 → POLISHING_PLAN 2.7 (Хардкод URL сервера → ApiConstants.baseUrl)

| Шаг | Файл | Риск |
|-----|------|------|
| 84 | Найти все 9 мест с хардкодом `https://arabica26.ru` | Безопасный (только анализ) |
| 85 | `lib/features/menu/pages/menu_page.dart` | Безопасный |
| 86 | `lib/features/kpi/pages/` (несколько файлов) | Безопасный |
| 87 | `lib/features/product_questions/` (файлы с URL) | Безопасный |
| 88-92 | Остальные файлы по одному | Безопасный |

**Изменение:** `'https://arabica26.ru/...'` → `'${ApiConstants.baseUrl}/...'`
**Проверка:** flutter analyze. Ручная: открыть каждый изменённый экран, убедиться что данные загружаются.

---

### Шаг 93 → POLISHING_PLAN 2.8 (WebSocket reconnect после 10 неудач)

| Шаг | Файл | Риск |
|-----|------|------|
| 93 | `lib/features/employee_chat/services/chat_websocket_service.dart` | Средний |

**Изменение:** После исчерпания 10 попыток реконнекта — запустить Timer на 5 минут, затем сбросить счётчик и попробовать снова.
**Почему средний:** WebSocket-логика сложная. Нужно убедиться что не создаются параллельные connect() при одновременных вызовах.
**Проверка:** flutter analyze. Ручная: отключить Wi-Fi на телефоне на 2 минуты (чтобы израсходовать попытки) → включить обратно → через 5 мин чат должен переподключиться автоматически.

---

### Шаг 100 → POLISHING_PLAN 2.4 (Batch endpoint для главного меню)

⚠️ Требует одновременного изменения Flutter + Backend.

| Шаг | Файл | Риск |
|-----|------|------|
| 100a | `loyalty-proxy/api/dashboard_batch_api.js` — проверить что он возвращает все 12 нужных полей | Безопасный (только чтение) |
| 100b | `lib/app/pages/main_menu_page.dart` — заменить 12 отдельных API-вызовов на один batch | Средний |

**Когда делать:** После контрольной точки #2 (пагинация стабильна).
**Проверка:** Открыть главное меню, убедиться что все счётчики (непрочитанные, задачи, смены) показываются правильно. Сравнить с тем что было до изменения.

### 🛑 КОНТРОЛЬНАЯ ТОЧКА #3 (после шага 100)
- flutter analyze — 0 ошибок
- Все экраны открываются без крашей
- Чат работает, переподключается
- Подождать 2-3 дня

---

## ФАЗА 3: BACKEND DRY (Шаги 110–125)

### Шаги 110-118 → POLISHING_PLAN 3.1 (BaseReportScheduler)

⚠️ **Делать ТОЛЬКО после 2+ недель стабильной работы фаз 0-2.**

| Шаг | Что | Риск |
|-----|-----|------|
| 110 | Создать `loyalty-proxy/utils/base_report_scheduler.js` | Безопасный |
| 111 | Перевести `product_questions_penalty_scheduler.js` на BaseReportScheduler | Средний |
| 112 | Проверка 3 дня. Если OK → перевести `envelope_automation_scheduler.js` | Средний |
| 113 | `coffee_machine_automation_scheduler.js` | Средний |
| 114 | `rko_automation_scheduler.js` | Средний |
| 115 | `recount_automation_scheduler.js` | Средний |
| 116 | `shift_handover_automation_scheduler.js` | Средний |
| 117 | `shift_automation_scheduler.js` (самый сложный — экспорт функций) | ⚠️ Высокий |
| 118 | `attendance_automation_scheduler.js` | Средний |

**Принцип:** Один шедулер за раз. После каждого — ждём полный цикл (24 часа). Если сломалось — откат одного файла, остальные не затронуты.

---

### Шаги 120-125 → POLISHING_PLAN 3.2 (Вынести дублированные утилиты)

| Шаг | Что | Файлы | Риск |
|-----|-----|-------|------|
| 120 | Найти все файлы с локальной копией `sanitizeId()` | grep по api/ | Безопасный (только анализ) |
| 121 | Заменить в первом файле `sanitizeId` → `require('../utils/file_helpers').sanitizeId` | 1 API файл | Безопасный |
| 122 | Повторить для остальных файлов по одному | Каждый API файл отдельно | Безопасный |
| 123 | Найти все файлы с локальной копией `fileExists()` | grep по api/ | Безопасный (только анализ) |
| 124 | Заменить `fileExists` → импорт из file_helpers, по одному файлу | Каждый отдельно | Безопасный |
| 125 | Проверить нет ли других дублированных утилит | grep | Безопасный (только анализ) |

**Принцип:** Один файл за раз. `file_helpers.js` НЕ трогаем (только импортируем из него).

---

## ФАЗА 4: FLUTTER DRY (Шаги 130–181)

### Шаги 130-133 → POLISHING_PLAN 4.1 (Цвета → AppColors)

**Первые шаги — явные:**

| Шаг | Файл | Риск |
|-----|------|------|
| 130 | НОВЫЙ: `lib/core/theme/app_colors.dart` | Безопасный |
| 131 | `lib/app/pages/main_menu_page.dart` | Безопасный |
| 132 | `lib/features/shifts/pages/shift_questions_page.dart` | Безопасный |
| 133 | `lib/features/efficiency/pages/my_efficiency_page.dart` | Безопасный |

**Остальные 125 файлов — план обхода по батчам:**

| Батч | Модуль | Файлов | Когда |
|------|--------|--------|-------|
| Батч 1 | `lib/app/pages/` | ~6 | Сразу после 131-133 |
| Батч 2 | `lib/features/shifts/` | ~8 | Следующий |
| Батч 3 | `lib/features/attendance/` | ~5 | Следующий |
| Батч 4-15 | Остальные модули по алфавиту | по 5-10 | Выделенные сессии |

**Правило:** При работе с ЛЮБЫМ Flutter файлом — заменять хардкод цветов на AppColors. После каждого батча — `flutter analyze`.
**Метрика:** Начали с 128+116+70 файлов. Цель: 0 хардкод цветов.

---

### Шаги 140-143 → POLISHING_PLAN 4.2 (Scaffold настроек баллов — 15 страниц)

⚠️ **Делать после стабилизации фаз 0-2.**

| Шаг | Что | Риск |
|-----|-----|------|
| 140 | Создать `lib/features/efficiency/widgets/generic_points_settings_scaffold.dart` | Безопасный |
| 141 | Перевести 1 страницу (`shift_points_settings_page.dart`) на scaffold | Средний |
| 142 | Проверка — flutter analyze + ручная. Если OK → перевести ещё 2 страницы | Средний |
| 143 | Оставшиеся 12 страниц — по 3-4 за сессию | Средний |

**Принцип:** Сначала одна страница. Проверить что настройки сохраняются. Потом массовая замена.

---

### Шаги 150-153 → POLISHING_PLAN 4.3 (Scaffold управления вопросами — 7 страниц)

| Шаг | Что | Риск |
|-----|-----|------|
| 150 | Создать `lib/shared/widgets/questions_management_scaffold.dart` | Безопасный |
| 151 | Перевести 1 страницу (`shift_questions_management_page.dart`) | Средний |
| 152 | Проверка. Если OK → ещё 2 | Средний |
| 153 | Оставшиеся 4 | Средний |

---

### Шаги 160-163 → POLISHING_PLAN 4.4 (Scaffold списка отчётов — 7 страниц)

| Шаг | Что | Риск |
|-----|-----|------|
| 160 | Создать `lib/shared/widgets/report_list_scaffold.dart` | Безопасный |
| 161 | Перевести 1 страницу (`shift_reports_list_page.dart`) | Средний |
| 162 | Проверка. Если OK → ещё 2 | Средний |
| 163 | Оставшиеся 4 | Средний |

---

### Шаги 170-173 → POLISHING_PLAN 4.5 (Scaffold выбора магазина — 6 страниц)

| Шаг | Что | Риск |
|-----|-----|------|
| 170 | Создать `lib/shared/widgets/shop_selection_scaffold.dart` | Безопасный |
| 171 | Перевести 1 страницу (`shift_shop_selection_page.dart`) | Средний |
| 172 | Проверка. Если OK → ещё 2 | Средний |
| 173 | Оставшиеся 3 | Средний |

---

### Шаги 180-181 → POLISHING_PLAN 4.6 (Разбить крупные файлы)

| Шаг | Файл | Строк | Риск |
|-----|------|-------|------|
| 180 | `lib/features/ai_training/pages/cigarette_training_page.dart` | 4,002 | Средний |
| 181 | `lib/features/work_schedule/pages/work_schedule_page.dart` | 2,949 | Средний |

**Изменение:** Вынести внутренние виджеты (private _WidgetName) в отдельные файлы `widgets/`. Не менять логику — только перенос кода.
**Шаг 180 по частям:**
- 180a: Определить все private-виджеты внутри файла
- 180b: Вынести первый виджет → flutter analyze → проверить страницу
- 180c: Вынести следующий → аналогично
- Повторять пока файл не станет <500 строк

**Шаг 181:** Аналогично.

---

## ФАЗА 5: МОНИТОРИНГ И ЗАЩИТА (Шаги 190–192)

### Шаг 190 → POLISHING_PLAN 5.1 (Расширить Health endpoint)

| Шаг | Файл | Риск |
|-----|------|------|
| 190 | `loyalty-proxy/index.js` строка ~862 (существующий /health) | Безопасный |

**Изменение:** Расширить существующий ответ `/health`:
```json
{
  "status": "ok",
  "uptime": 123456,
  "memory": { "used": "180MB", "total": "2048MB" },
  "disk": { "used": "1.2GB", "free": "18GB" },
  "schedulers": { "shift": "active", ... },
  "lastErrors": []
}
```
**Почему безопасно:** Только расширяем JSON-ответ. Старые поля остаются.

---

### Шаг 191 → POLISHING_PLAN 5.2 (Автоочистка фото по расписанию)

| Шаг | Файл | Риск |
|-----|------|------|
| 191a | `loyalty-proxy/api/auto_cleanup_scheduler.js` (уже существует, startAutoCleanupScheduler в index.js) — изучить что он делает | Безопасный (только чтение) |
| 191b | Расширить auto_cleanup_scheduler — добавить очистку фото старше N дней | Средний |

**Изменение:** В существующем autoCleanupScheduler (запускается ежедневно в 3:00) добавить проход по фото-директориям. Удалять файлы старше настраиваемого порога (по умолчанию 90 дней).
**Проверка:** pm2 logs после 3:00, проверить что файлы за последние 90 дней НЕ удалены, а более старые — удалены.

---

### Шаг 192 → POLISHING_PLAN 5.3 (Логирование ошибок шедулеров)

| Шаг | Файл | Риск |
|-----|------|------|
| 192a | НОВЫЙ: `loyalty-proxy/utils/scheduler_logger.js` | Безопасный |
| 192b | Подключить к 1 шедулеру (product_questions_penalty) | Безопасный |
| 192c-192i | Подключить к остальным 8 шедулерам по одному | Безопасный |

**Изменение:** Создать утилиту:
```javascript
function logSchedulerError(schedulerName, error) {
  const dir = '/var/www/scheduler-errors';
  const date = new Date().toISOString().split('T')[0];
  const file = `${dir}/${date}.json`;
  // append error to file
}
```
Затем в каждом шедулере в catch-блоке добавить `logSchedulerError(name, err)` рядом с существующим `console.error`.

---

## ПОРЯДОК ВЫПОЛНЕНИЯ (ПОЛНАЯ КАРТА)

```
ЭТАП 0 (День 1): Подготовка сервера
  Шаг 0a (swap) + Шаг 0b (удалить мусор) → проверка df -h и free -h

ЭТАП 1 (Неделя 1-2): Фаза 0 — критические баги
  Шаги 1-25 → Контрольная точка #1 (пауза 24 часа)

ЭТАП 2 (Неделя 2-3): Фаза 1 — стабильность сервера
  Шаги 26-48 → Контрольная точка #2 (пауза 2-3 дня)

ЭТАП 3 (Неделя 3-4): Фаза 2 — Flutter стабильность
  Шаги 50-93 (явные) + батчи mounted guard + батчи цветов
  Шаг 100 (batch endpoint) → Контрольная точка #3 (пауза 2-3 дня)

ЭТАП 4 (Неделя 5-6): Фаза 5 — мониторинг
  Шаги 190-192

ЭТАП 5 (Неделя 7+): Фаза 3 + Фаза 4 — DRY рефакторинг
  Шаги 110-125 (BaseReportScheduler + утилиты)
  Шаги 130-181 (AppColors + scaffolds + разбивка файлов)

Boy Scout Rule — НЕПРЕРЫВНО на каждом этапе:
  - mounted guard в каждом файле который трогаем
  - цвета → AppColors в каждом файле который трогаем
  - локальные утилиты → импорт из utils/ в каждом файле который трогаем
  - TextEditingController.dispose() в диалогах
  - URL → ApiConstants.baseUrl
```

---

## ПОЛНАЯ ТАБЛИЦА ПОКРЫТИЯ

| # | Пункт POLISHING_PLAN | Шаги выполнения | Статус |
|---|---|---|---|
| 0.10 | Swap не активен (OOM-kill) | Шаг 0a | Покрыт |
| 0.11 | 12.6 GB мусора на сервере | Шаг 0b | Покрыт |
| 0.1 | Overlap protection (9 шедулеров) | Шаги 4-12 | Покрыт |
| 0.2 | Auth проверки (8 API) | Шаги 13-20 | Покрыт |
| 0.3 | Баг getHours() | Шаг 3 | Покрыт |
| 0.4 | Startup delay (2 шедулера) | Шаги 1-2 | Покрыт |
| 0.5 | Принудительный logout без авторизации | Шаг 21 | Покрыт |
| 0.6 | Регистрация чужого номера | Шаг 22 | Покрыт |
| 0.7 | isAdmin из body (shift_transfers) | Шаг 23 | Покрыт |
| 0.8 | app-version: admin из body | Шаг 24 | Покрыт |
| 0.9 | Неправильный заказ при push | Шаг 25 | Покрыт |
| 1.1 | Безопасная запись (4 файла) | Шаги 27-30 | Покрыт |
| 1.2 | getMoscowTime утилита | Шаги 31-38 | Покрыт |
| 1.3 | Пагинация (сервер + Flutter) | Шаги 43-44 | Покрыт |
| 1.4 | Расширение data_cache | Шаги 45a-45c | Покрыт |
| 1.5 | Серверное сжатие фото | Шаги 46a-46j | Покрыт |
| 1.6 | chat-media cleanup | Шаг 26 | Покрыт |
| 1.7 | File locking для чатов | Шаг 39 | Покрыт |
| 1.8 | File locking для заказов | Шаг 40 | Покрыт |
| 1.9 | Graceful shutdown WebSocket | Шаг 41 | Покрыт |
| 1.10 | WebSocket: лимит подключений | Шаг 42 | Покрыт |
| 2.1 | mounted guard (844 файла) | Шаги 54-59 + батчи A-Z | Покрыт |
| 2.2 | Сжатие фото (3 task pages) | Шаги 50-52 | Покрыт |
| 2.3 | Web-сжатие фото | Шаг 53 | Покрыт |
| 2.4 | Batch endpoint для меню | Шаг 100 | Покрыт |
| 2.5 | Auto-logout при 401 | Шаг 80 | Покрыт |
| 2.6 | TextEditingController dispose | Шаги 81-83 | Покрыт |
| 2.7 | Хардкод URL сервера | Шаги 84-92 | Покрыт |
| 2.8 | WebSocket reconnect после 10 неудач | Шаг 93 | Покрыт |
| 3.1 | BaseReportScheduler | Шаги 110-118 | Покрыт |
| 3.2 | Вынести дублированные утилиты | Шаги 120-125 | Покрыт |
| 4.1 | Цвета → AppColors | Шаги 130-133 + батчи 1-15 | Покрыт |
| 4.2 | Scaffold настроек баллов (15) | Шаги 140-143 | Покрыт |
| 4.3 | Scaffold вопросов (7) | Шаги 150-153 | Покрыт |
| 4.4 | Scaffold списка отчётов (7) | Шаги 160-163 | Покрыт |
| 4.5 | Scaffold выбора магазина (6) | Шаги 170-173 | Покрыт |
| 4.6 | Разбить крупные файлы (2) | Шаги 180-181 | Покрыт |
| 5.1 | Расширить health endpoint | Шаг 190 | Покрыт |
| 5.2 | Автоочистка фото | Шаг 191 | Покрыт |
| 5.3 | Логирование ошибок шедулеров | Шаг 192 | Покрыт |

**Покрытие: 39/39 пунктов (100%)**

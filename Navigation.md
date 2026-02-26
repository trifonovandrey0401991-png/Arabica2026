# Navigation — Quick Reference Index
> **Цель**: найти нужную информацию в ARCHITECTURE_COMPLETE.md (ARCH) и PROJECT_MAP.md (MAP) без чтения всего файла.
> Указывай `offset` и `limit` при чтении: `Read(file, offset=LINE, limit=50)`
> Дата: 2026-02-25 | Версия: 2.7.3 | 37 модулей | 74 API | 11 schedulers

---

## По модулю Flutter (37 штук)

| Модуль | ARCH (строка) | MAP (строка) | Файлов | Риск |
|--------|--------------|-------------|--------|------|
| auth | 327 (flow), 550 (models), 1271 (API) | 221 | 13 | ВЫСШИЙ |
| attendance | 634 | 365 | 10 | Средний |
| shifts | 702 | 324 | 16 | Высокий |
| shift_handover | 1351 (API) | 430 | 16 | Средний |
| work_schedule | 1610 (API) | 395 | 15 | Средний |
| recount | 1340 (API) | 468 | 26 | Средний |
| envelope | 1379 (API) | 517 | 10 | Средний |
| rko | 1391 (API) | 548 | 10 | Средний |
| orders | 1403 (API), 1887 (flow) | 578 | 7 | Средний |
| menu | 1425 (API) | 605 | 3 | Низкий |
| recipes | 1437 (API) | 622 | 7 | Низкий |
| employees | 1447 (API) | 262 | 13 | Высокий |
| shops | 1459 (API) | 296 | 6 | Высокий |
| kpi | — | 644 | 17 | Низкий |
| efficiency | 785, 1620 (API), 2385 (баллы) | 679 | 58 | Средний |
| rating | 1648 (API) | 765 | 4 | Низкий |
| main_cash | 1687 (API) | 785 | 19 | Низкий |
| fortune_wheel | 1648 (API), 2618 (wheel) | 820 | 6 | Низкий |
| training | 923, 1540 (API) | 842 | 7 | Низкий |
| tests | 990, 1550 (API) | 864 | 8 | Низкий |
| product_questions | 1572 (API) | 887 | 14 | Низкий |
| ai_training | 1719 (cig API+embeddings), 1739 (catalog 17 endpoints), 1763 (AI verif), 1787 (dashboard) | 918 | 33 | Низкий |
| messenger | 1067 | 981 | 17 | Низкий |
| employee_chat | 863, 1597 (API) | 1030 | 13 | Низкий |
| clients | 1819 (API) | 1064 | 19 | Низкий |
| loyalty | 1469 (API), 1479 (gamif) | 1098 | 14 | Низкий |
| bonuses | — | 1129 | 4 | Низкий |
| referrals | 1658 (API) | 1148 | 5 | Низкий |
| reviews | 1561 (API) | 1168 | 9 | Низкий |
| tasks | 1515 (API) | 1192 | 16 | Низкий |
| coffee_machine | — | 1225 | 14 | Низкий |
| data_cleanup | 1801 (API) | 1258 | 4 | Низкий |
| job_application | 1667 (API) | 1278 | 6 | Низкий |
| suppliers | 1677 (API) | 1299 | 3 | Низкий |
| network_management | — | 1317 | 2 | Низкий |
| execution_chain | — | 1332 | 3 | Низкий |
| geofence | 1708 (API) | — | — | Низкий |
| recurring_tasks | 1527 (API) | — | — | Низкий |

---

## По теме (ARCHITECTURE_COMPLETE.md)

| Тема | Строка | Что найдёшь |
|------|--------|-------------|
| Общая архитектура | 29 | Обзор системы, стек, структура |
| Структура проекта (дерево) | 101 | Полное дерево lib/ и loyalty-proxy/ |
| Сетевая конфигурация | 181 | Порты, nginx, домены |
| Безопасность сервера | 193 | Firewall, SSH, HTTPS |
| Запуск приложения (main.dart) | 214 | Инициализация, провайдеры |
| Дерево решений при запуске | 259 | Роль → какая страница открывается |
| Система авторизации (полная) | 325 | Архитектура, flows, модели |
| Регистрация flow | 383 | Пошаговый flow с кодом |
| Вход по PIN flow | 453 | Пошаговый flow с кодом |
| Сброс PIN flow | 478 | Через Telegram OTP |
| Модули Flutter (обзор) | 587 | Таблица 37 модулей |
| Модули Flutter (детально) | 632 | Описание каждого модуля |
| Структура сервера (дерево) | 1129 | Полное дерево loyalty-proxy/ |
| Все API endpoints (таблицы) | 1274 | 240+ endpoints с описаниями |
| Потоки данных | 1856 | Attendance, Order, Shift, Handover, Penalty |
| Schedulers (все 11) | 2104 | Обзор + детальные блок-схемы |
| Баллы и эффективность | 2397 | 13 категорий, формулы, примеры |
| Формула рейтинга | 2417 | Линейная интерполяция |
| Формула тестов | 2481 | Score-based формула |
| Итоговый рейтинг | 2547 | Формула + пример расчёта |
| Batch-оптимизация | 2603 | Dashboard batch endpoint |
| Колесо удачи связь | 2632 | Рейтинг → спины |
| Роли и матрица доступа | 2697 | 6 ролей, иерархия, матрица |
| Определение роли в коде | 2727 | Логика UserRoleService |
| Матрица модули x роли | 2775 | Кто что видит |
| PostgreSQL структура | 2851 | Таблицы, dual-write, feature flags |
| Файловое хранилище /var/www | 2884 | 110+ директорий, карта |
| JSON Schemas сущностей | 3048 | Employee, Client, Shift, Order и др. |
| Слабые места и аудит | 3206 | Критические проблемы, план |
| Карта связей модулей | 3413 | Flutter→API→Files→Scheduler→Push |
| Результаты аудита | 3511 | Сводка, цепочки, масштабируемость |
| Глоссарий | 3654 | Термины, роли, сокращения |

---

## По теме (PROJECT_MAP.md)

| Тема | Строка | Что найдёшь |
|------|--------|-------------|
| Обзор архитектуры (числа) | 22 | Ключевые числа, дерево |
| Core: BaseHttpService | 54 | Центральный сервис, влияние |
| Core: BaseReportService | 68 | 5 отчётных модулей |
| Core: ApiConstants | 82 | Эндпоинты |
| Core сервисы (16 файлов) | 101 | Таблица: кто использует + влияние |
| Core утилиты (5 файлов) | 121 | CacheManager, Logger, PhoneNormalizer |
| Модули по категориям | 139 | Группировка 37 модулей |
| Зависимости каждого модуля | 219 | Файлы, API, зависимости, "ЕСЛИ ИЗМЕНИТЬ" |
| Матрица влияния изменений | 1375 | Высший/Высокий/Средний/Низкий риск |
| index.js (роутер) | 1431 | 74 API, middleware, WebSocket |
| Schedulers (11 штук) | 1442 | Таблица с файлами |
| Modules бэкенда (9 файлов) | 1458 | OCR, vision, orders, intelligence |
| ML система (5 файлов) | 1472 | YOLO wrapper, inference, server, embeddings |
| Utils бэкенда (15 файлов) | 1482 | db.js, async_fs, push_service и др. |
| Admin Bot (Telegram) | 1502 | /ai_status, /ai_train, /ai_train_status |
| Список API файлов (74) | 1519 | По категориям |
| PostgreSQL | 1539 | DB, dual-write, feature flags |
| Хранилище /var/www | 1561 | 110+ директорий по категориям |
| Общие модели данных | 1730 | Модели shared между модулями |
| Телефон как ключ | 1746 | Нормализация, ловушки |
| Shared и App слои | 1758 | Общие виджеты, навигация |

---

## Быстрый поиск по ключевому слову

| Ищешь... | Читай |
|----------|-------|
| Как работает авторизация | ARCH:325-585 |
| Как работает эффективность/баллы | ARCH:2397-2697 |
| Какие есть schedulers | ARCH:2104-2120 или MAP:1442 |
| Структура конкретного модуля | MAP: найди модуль в таблице выше |
| API endpoints модуля | ARCH:1274+ (найди модуль в таблице выше) |
| Что сломается если изменить файл | MAP:1375 (матрица рисков) |
| Зависимости модуля | MAP: найди модуль в секции 4 |
| Роли и права доступа | ARCH:2697-2849 |
| PostgreSQL таблицы и схема | ARCH:2851-2884 |
| JSON schemas сущностей | ARCH:3048-3206 |
| Файловое хранилище /var/www | MAP:1561-1730 |
| Потоки данных (data flows) | ARCH:1856-2104 |
| Слабые места и баги | ARCH:3206-3413 |
| Общие модели (shared) | MAP:1730-1758 |
| WebSocket (чат/мессенджер) | ARCH:863 (chat), 1067 (messenger) |
| OCR система | ARCH:1129 (modules/), MAP:1458 |
| YOLO / ML + Embeddings | ARCH:1225-1231, MAP:1472 |
| Embedding система (1000+ товаров) | ARCH:1719 (toggle + pipeline), MAP:918 (ai_training) |
| AI Dashboard API | ARCH:1787 (endpoints, retry, internal API) |
| Admin Telegram Bot (AI) | MAP:1502 (admin-bot, /ai_status, /ai_train) |
| Push уведомления | ARCH:3499 (потоки push) |
| Batch endpoint (dashboard) | ARCH:2603 |
| Batch approve/reject (master-catalog) | ARCH:1756-1757 |

---

## Файлы высшего и высокого риска (менять с осторожностью!)

| Файл | Риск | Влияние | Где подробности |
|------|------|---------|-----------------|
| `core/services/base_http_service.dart` | ВЫСШИЙ | ВСЕ 37 модулей | MAP:54 |
| `core/constants/api_constants.dart` | ВЫСШИЙ | Все с эндпоинтом | MAP:82 |
| `features/auth/services/auth_service.dart` | ВЫСШИЙ | ВСЕ модули | MAP:221 |
| `loyalty-proxy/index.js` | ВЫСШИЙ | ВСЕ API | MAP:1431 |
| `loyalty-proxy/utils/db.js` | ВЫСШИЙ | 41 модуль с DB | MAP:1482 |
| `loyalty-proxy/utils/db_schema.sql` | ВЫСШИЙ | Миграция на сервере | MAP:1482 |
| `core/services/base_report_service.dart` | Высокий | 5 отчётных модулей | MAP:68 |
| `core/services/multitenancy_filter_service.dart` | Высокий | 8+ модулей | MAP:101 |
| `features/employees/services/employee_service.dart` | Высокий | 8+ модулей | MAP:262 |
| `features/shops/models/shop_model.dart` | Высокий | 10+ модулей | MAP:296 |
| `features/employees/models/user_role_model.dart` | Высокий | Все с ролями | MAP:262 |

---

> **Как использовать**: Найди тему/модуль в таблице → возьми номер строки → `Read(file, offset=LINE, limit=50-100)`

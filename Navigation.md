# Navigation — Quick Reference Index
> **Цель**: найти нужную информацию в ARCHITECTURE_COMPLETE.md (ARCH) и PROJECT_MAP.md (MAP) без чтения всего файла.
> Указывай `offset` и `limit` при чтении: `Read(file, offset=LINE, limit=50)`
> Дата: 2026-03-01 | Версия: 2.8.1 | 39 модулей | 76 API | 11 schedulers

---

## По модулю Flutter (39 штук)

| Модуль | ARCH (строка) | MAP (строка) | Файлов | Риск |
|--------|--------------|-------------|--------|------|
| auth | 331 (flow), 554 (models), 1349 (API) | 225 | 13 | ВЫСШИЙ |
| attendance | 642 | 369 | 10 | Средний |
| shifts | 710 | 328 | 16 | Высокий |
| shift_handover | 1426 (API) | 434 | 16 | Средний |
| work_schedule | 1685 (API) | 399 | 15 | Средний |
| recount | 1415 (API) | 472 | 26 | Средний |
| envelope | 1454 (API) | 521 | 10 | Средний |
| rko | 1466 (API) | 552 | 10 | Средний |
| orders | 1478 (API), 1974 (flow) | 582 | 8 | Средний |
| menu | 1500 (API) | 609 | 3 | Низкий |
| recipes | 1512 (API) | 626 | 7 | Низкий |
| employees | 1522 (API) | 266 | 13 | Высокий |
| shops | 1534 (API) | 300 | 6 | Высокий |
| kpi | — | 648 | 17 | Низкий |
| efficiency | 793, 1695 (API), 2470 (баллы) | 683 | 58 | Средний |
| rating | 1723 (API) | 769 | 4 | Низкий |
| main_cash | 1762 (API) | 789 | 19 | Низкий |
| fortune_wheel | 1723 (API), 2705 (wheel) | 824 | 6 | Низкий |
| training | 931, 1615 (API) | 846 | 7 | Низкий |
| tests | 998, 1625 (API) | 868 | 8 | Низкий |
| product_questions | 1647 (API) | 891 | 14 | Низкий |
| ai_training | 1792 (cig API+embeddings), 1812 (catalog 17 endpoints), 1836 (AI verif), 1860 (dashboard) | 922 | 34 | Низкий |
| messenger | 1075 | 1008 | 17 | Низкий |
| employee_chat | 871, 1672 (API) | 1057 | 13 | Низкий |
| clients | 1906 (API) | 1091 | 19 | Низкий |
| loyalty | 1544 (API), 1554 (gamif) | 1125 | 16 | Низкий |
| bonuses | — | 1156 | 4 | Низкий |
| referrals | 1733 (API) | 1175 | 5 | Низкий |
| reviews | 1636 (API) | 1195 | 9 | Низкий |
| tasks | 1590 (API) | 1219 | 16 | Низкий |
| coffee_machine | — | 1252 | 14 | Низкий |
| data_cleanup | 1888 (API) | 1285 | 4 | Низкий |
| job_application | 1742 (API) | 1305 | 6 | Низкий |
| suppliers | 1752 (API) | 1326 | 3 | Низкий |
| network_management | — | 1344 | 2 | Низкий |
| execution_chain | — | 1359 | 3 | Низкий |
| shop_catalog | 1135 | 1377 | 6 | Низкий |
| onboarding | 1173 | 1403 | 1 | Низкий |
| settings | 1918 (API) | 1420 | 1 | Низкий |
| geofence | 1783 (API) | — | — | Низкий |
| recurring_tasks | 1602 (API) | — | — | Низкий |

---

## По теме (ARCHITECTURE_COMPLETE.md)

| Тема | Строка | Что найдёшь |
|------|--------|-------------|
| Общая архитектура | 29 | Обзор системы, стек, структура |
| Структура проекта (дерево) | 101 | Полное дерево lib/ и loyalty-proxy/ |
| Сетевая конфигурация | 187 | Порты, nginx, домены |
| Безопасность сервера | 199 | Firewall, SSH, HTTPS |
| Запуск приложения (main.dart) | 218 | Инициализация, провайдеры |
| Дерево решений при запуске | 265 | Роль → какая страница открывается |
| Система авторизации (полная) | 331 | Архитектура, flows, модели |
| Регистрация flow | 389 | Пошаговый flow с кодом |
| Вход по PIN flow | 459 | Пошаговый flow с кодом |
| Сброс PIN flow | 484 | Через Telegram OTP |
| Модули Flutter (обзор) | 593 | Таблица 39 модулей |
| Модули Flutter (детально) | 640 | Описание каждого модуля |
| Структура сервера (дерево) | 1196 | Полное дерево loyalty-proxy/ |
| Все API endpoints (таблицы) | 1347 | 240+ endpoints с описаниями |
| Store Links API | 1918 | QR-коды для скачивания приложения |
| Потоки данных | 1939 | Attendance, Order, Shift, Handover, Penalty |
| Schedulers (все 11) | 2187 | Обзор + детальные блок-схемы |
| Баллы и эффективность | 2480 | 13 категорий, формулы, примеры |
| Формула рейтинга | 2500 | Линейная интерполяция |
| Формула тестов | 2564 | Score-based формула |
| Итоговый рейтинг | 2630 | Формула + пример расчёта |
| Ссылки на магазины (QR) | 1918 | Store Links API, QR-коды |
| Batch-оптимизация | 2686 | Dashboard batch endpoint |
| Колесо удачи связь | 2715 | Рейтинг → спины |
| Роли и матрица доступа | 2780 | 6 ролей, иерархия, матрица |
| Определение роли в коде | 2810 | Логика UserRoleService |
| Матрица модули x роли | 2858 | Кто что видит |
| PostgreSQL структура | 2932 | Таблицы, dual-write, feature flags |
| Файловое хранилище /var/www | 2967 | 110+ директорий, карта |
| JSON Schemas сущностей | 3131 | Employee, Client, Shift, Order и др. |
| Слабые места и аудит | 3289 | Критические проблемы, план |
| Карта связей модулей | 3504 | Flutter→API→Files→Scheduler→Push |
| Результаты аудита | 3608 | Сводка, цепочки, масштабируемость |
| Глоссарий | 3754 | Термины, роли, сокращения |

---

## По теме (PROJECT_MAP.md)

| Тема | Строка | Что найдёшь |
|------|--------|-------------|
| Обзор архитектуры (числа) | 22 | Ключевые числа, дерево |
| Core: BaseHttpService | 54 | Центральный сервис, влияние |
| Core: BaseReportService | 68 | 5 отчётных модулей |
| Core: ApiConstants | 82 | Эндпоинты |
| Core сервисы (16 файлов) | 102 | Таблица: кто использует + влияние |
| Core утилиты (6 файлов) | 122 | CacheManager, DiskCache, Logger, PhoneNormalizer |
| Модули по категориям | 141 | Группировка 38 модулей |
| Зависимости каждого модуля | 223 | Файлы, API, зависимости, "ЕСЛИ ИЗМЕНИТЬ" |
| Модуль settings (ссылки) | 1420 | Настройки ссылок Google Play / App Store |
| Матрица влияния изменений | 1440 | Высший/Высокий/Средний/Низкий риск |
| index.js (роутер) | 1498 | 76 API, middleware, WebSocket |
| Schedulers (11 штук) | 1509 | Таблица с файлами |
| Modules бэкенда (9 файлов) | 1525 | OCR, vision, orders, intelligence |
| ML система (5 файлов) | 1539 | YOLO wrapper, inference, server, embeddings |
| Utils бэкенда (15 файлов) | 1549 | db.js, async_fs, push_service и др. |
| Admin Bot (Telegram) | 1569 | /ai_status, /ai_train, /ai_train_status |
| Список API файлов (76) | 1586 | По категориям |
| PostgreSQL | 1609 | DB, dual-write, feature flags |
| Хранилище /var/www | 1631 | 110+ директорий по категориям |
| Общие модели данных | 1800 | Модели shared между модулями |
| Телефон как ключ | 1816 | Нормализация, ловушки |
| Shared и App слои | 1828 | Общие виджеты, навигация |

---

## Быстрый поиск по ключевому слову

| Ищешь... | Читай |
|----------|-------|
| Как работает авторизация | ARCH:331-591 |
| Как работает эффективность/баллы | ARCH:2480-2780 |
| Какие есть schedulers | ARCH:2187-2205 или MAP:1509 |
| Структура конкретного модуля | MAP: найди модуль в таблице выше |
| API endpoints модуля | ARCH:1347+ (найди модуль в таблице выше) |
| Что сломается если изменить файл | MAP:1440 (матрица рисков) |
| Зависимости модуля | MAP: найди модуль в секции 4 |
| Роли и права доступа | ARCH:2780-2932 |
| PostgreSQL таблицы и схема | ARCH:2932-2967 |
| JSON schemas сущностей | ARCH:3131-3289 |
| Файловое хранилище /var/www | MAP:1631-1800 |
| Потоки данных (data flows) | ARCH:1939-2187 |
| Слабые места и баги | ARCH:3289-3504 |
| Общие модели (shared) | MAP:1800-1828 |
| WebSocket (чат/мессенджер) | ARCH:871 (chat), 1075 (messenger) |
| OCR система | ARCH:1196 (modules/), MAP:1525 |
| YOLO / ML + Embeddings | ARCH:1298-1304, MAP:1539 |
| Embedding система (1000+ товаров) | ARCH:1792 (toggle + pipeline), MAP:922 (ai_training) |
| AI Dashboard API | ARCH:1860 (endpoints, retry, internal API) |
| Admin Telegram Bot (AI) | MAP:1569 (admin-bot, /ai_status, /ai_train) |
| Push уведомления | ARCH:3596 (потоки push) |
| Batch endpoint (dashboard) | ARCH:2676 |
| Batch approve/reject (master-catalog) | ARCH:1836 |

---

## Файлы высшего и высокого риска (менять с осторожностью!)

| Файл | Риск | Влияние | Где подробности |
|------|------|---------|-----------------|
| `core/services/base_http_service.dart` | ВЫСШИЙ | ВСЕ 38 модулей | MAP:54 |
| `core/constants/api_constants.dart` | ВЫСШИЙ | Все с эндпоинтом | MAP:82 |
| `features/auth/services/auth_service.dart` | ВЫСШИЙ | ВСЕ модули | MAP:225 |
| `loyalty-proxy/index.js` | ВЫСШИЙ | ВСЕ API | MAP:1480 |
| `loyalty-proxy/utils/db.js` | ВЫСШИЙ | 41 модуль с DB | MAP:1531 |
| `loyalty-proxy/utils/db_schema.sql` | ВЫСШИЙ | Миграция на сервере | MAP:1531 |
| `core/services/base_report_service.dart` | Высокий | 5 отчётных модулей | MAP:68 |
| `core/services/multitenancy_filter_service.dart` | Высокий | 8+ модулей | MAP:102 |
| `features/employees/services/employee_service.dart` | Высокий | 8+ модулей | MAP:266 |
| `features/shops/models/shop_model.dart` | Высокий | 10+ модулей | MAP:300 |
| `features/employees/models/user_role_model.dart` | Высокий | Все с ролями | MAP:266 |

---

> **Как использовать**: Найди тему/модуль в таблице → возьми номер строки → `Read(file, offset=LINE, limit=50-100)`

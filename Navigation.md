# Navigation — Quick Reference Index
> **Цель**: найти нужную информацию в ARCHITECTURE_COMPLETE.md (ARCH) и PROJECT_MAP.md (MAP) без чтения всего файла.
> Указывай `offset` и `limit` при чтении: `Read(file, offset=LINE, limit=50)`
> Дата: 2026-03-10 | Версия: 2.10.0 | 39 модулей | 77 API files | 12 schedulers

---

## По модулю Flutter (39 штук)

| Модуль | ARCH (строка) | MAP (строка) | Файлов | Риск |
|--------|--------------|-------------|--------|------|
| auth | 331 (flow), 546 (device), 582 (models), 1411 (API) | 225 | 15 | ВЫСШИЙ |
| attendance | 671 | 376 | 10 | Средний |
| shifts | 739 | 335 | 16 | Высокий |
| shift_handover | 1493 (API) | 454 | 16 | Средний |
| work_schedule | 1752 (API) | 406 | 15 | Средний |
| recount | 1482 (API) | 495 | 26 | Средний |
| envelope | 1521 (API) | 544 | 10 | Средний |
| rko | 1533 (API) | 575 | 10 | Средний |
| orders | 1545 (API), 2040 (flow) | 605 | 8 | Средний |
| menu | 1567 (API) | 632 | 3 | Низкий |
| recipes | 1579 (API) | 649 | 7 | Низкий |
| employees | 1589 (API) | 273 | 13 | Высокий |
| shops | 1601 (API) | 307 | 6 | Высокий |
| kpi | — | 671 | 17 | Низкий |
| efficiency | 822, 1762 (API), 2549 (баллы) | 706 | 58 | Средний |
| rating | 1790 (API) | 792 | 4 | Низкий |
| main_cash | 1829 (API) | 812 | 19 | Низкий |
| fortune_wheel | 1790 (API), 2784 (wheel) | 847 | 6 | Низкий |
| training | 960, 1682 (API) | 869 | 7 | Низкий |
| tests | 1027, 1692 (API) | 891 | 8 | Низкий |
| product_questions | 1714 (API) | 914 | 14 | Низкий |
| ai_training | 1859 (cig API+embeddings), 1879 (catalog 17 endpoints), 1903 (AI verif), 1927 (dashboard) | 945 | 34 | Низкий |
| messenger | 1104 | 1031 | 39 | Средний |
| employee_chat | 900, 1739 (API) | 1110 | 13 | Низкий |
| clients | 1973 (API) | 1144 | 19 | Низкий |
| loyalty | 1611 (API), 1621 (gamif) | 1178 | 16 | Низкий |
| bonuses | — | 1209 | 4 | Низкий |
| referrals | 1800 (API) | 1228 | 5 | Низкий |
| reviews | 1703 (API) | 1248 | 9 | Низкий |
| tasks | 1657 (API) | 1272 | 16 | Низкий |
| coffee_machine | — | 1305 | 14 | Низкий |
| data_cleanup | 1955 (API) | 1338 | 4 | Низкий |
| job_application | 1809 (API) | 1358 | 6 | Низкий |
| suppliers | 1819 (API) | 1379 | 3 | Низкий |
| network_management | — | 1397 | 2 | Низкий |
| execution_chain | — | 1412 | 3 | Низкий |
| shop_catalog | 1197 | 1430 | 6 | Низкий |
| onboarding | 1235 | 1456 | 1 | Низкий |
| settings | 1984 (API) | 1473 | 1 | Низкий |
| geofence | 1850 (API) | — | — | Низкий |
| recurring_tasks | 1669 (API) | — | — | Низкий |

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
| Регистрация flow | 395 | Пошаговый flow с кодом |
| Вход по PIN flow | 465 | Пошаговый flow с кодом |
| Сброс PIN flow | 490 | Через Telegram OTP |
| Привязка к устройству | 546 | Device Binding, feature flag, flow |
| Модули Flutter (обзор) | 621 | Таблица 39 модулей |
| Модули Flutter (детально) | 669 | Описание каждого модуля |
| Структура сервера (дерево) | 1258 | Полное дерево loyalty-proxy/ |
| Все API endpoints (таблицы) | 1409 | 245+ endpoints с описаниями |
| Store Links API | 1984 | QR-коды для скачивания приложения |
| Потоки данных | 2005 | Attendance, Order, Shift, Handover, Penalty |
| Schedulers (все 12) | 2253 | Обзор + детальные блок-схемы |
| Баллы и эффективность | 2549 | 13 категорий, формулы, примеры |
| Формула рейтинга | 2569 | Линейная интерполяция |
| Формула тестов | 2633 | Score-based формула |
| Итоговый рейтинг | 2699 | Формула + пример расчёта |
| Ссылки на магазины (QR) | 1984 | Store Links API, QR-коды |
| Batch-оптимизация | 2755 | Dashboard batch endpoint |
| Колесо удачи связь | 2784 | Рейтинг → спины |
| Роли и матрица доступа | 2849 | 6 ролей, иерархия, матрица |
| Определение роли в коде | 2879 | Логика UserRoleService |
| Матрица модули x роли | 2927 | Кто что видит |
| PostgreSQL структура | 3001 | Таблицы, dual-write, feature flags |
| Файловое хранилище /var/www | 3042 | 110+ директорий, карта |
| JSON Schemas сущностей | 3208 | Employee, Client, Shift, Order и др. |
| Слабые места и аудит | 3366 | Критические проблемы, план |
| Карта связей модулей | 3581 | Flutter→API→Files→Scheduler→Push |
| Результаты аудита | 3685 | Сводка, цепочки, масштабируемость |
| Глоссарий | 3831 | Термины, роли, сокращения |

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
| Модули по категориям | 141 | Группировка 39 модулей |
| Зависимости каждого модуля | 223 | Файлы, API, зависимости, "ЕСЛИ ИЗМЕНИТЬ" |
| Модуль settings (ссылки) | 1473 | Настройки ссылок Google Play / App Store |
| Матрица влияния изменений | 1493 | Высший/Высокий/Средний/Низкий риск |
| index.js (роутер) | 1551 | 77 API, middleware, WebSocket |
| Schedulers (12 штук) | 1562 | Таблица с файлами |
| Modules бэкенда (9 файлов) | 1579 | OCR, vision, orders, intelligence |
| ML система (5 файлов) | 1593 | YOLO wrapper, inference, server, embeddings |
| Utils бэкенда (18 файлов) | 1603 | db.js, async_fs, push_service и др. |
| Admin Bot (Telegram) | 1626 | /ai_status, /ai_train, /ai_train_status |
| Список API файлов (77) | 1643 | По категориям |
| PostgreSQL | 1666 | DB, dual-write, feature flags |
| Хранилище /var/www | 1688 | 113+ директорий по категориям |
| Общие модели данных | 1859 | Модели shared между модулями |
| Телефон как ключ | 1875 | Нормализация, ловушки |
| Shared и App слои | 1887 | Общие виджеты, навигация |

---

## Быстрый поиск по ключевому слову

| Ищешь... | Читай |
|----------|-------|
| Как работает авторизация | ARCH:331-619 |
| Привязка к устройству | ARCH:546-580 |
| Как работает эффективность/баллы | ARCH:2549-2849 |
| Какие есть schedulers | ARCH:2253-2549 или MAP:1562 |
| Структура конкретного модуля | MAP: найди модуль в таблице выше |
| API endpoints модуля | ARCH:1409+ (найди модуль в таблице выше) |
| Что сломается если изменить файл | MAP:1493 (матрица рисков) |
| Зависимости модуля | MAP: найди модуль в секции 4 |
| Роли и права доступа | ARCH:2849-3001 |
| PostgreSQL таблицы и схема | ARCH:3001-3042 |
| JSON schemas сущностей | ARCH:3208-3366 |
| Файловое хранилище /var/www | MAP:1688-1859 |
| Потоки данных (data flows) | ARCH:2005-2253 |
| Слабые места и баги | ARCH:3366-3581 |
| Общие модели (shared) | MAP:1859-1887 |
| WebSocket (чат/мессенджер) | ARCH:900 (chat), 1104 (messenger) |
| OCR система | ARCH:1258 (modules/), MAP:1579 |
| YOLO / ML + Embeddings | ARCH:1364-1370, MAP:1593 |
| Embedding система (1000+ товаров) | ARCH:1859 (toggle + pipeline), MAP:945 (ai_training) |
| AI Dashboard API | ARCH:1927 (endpoints, retry, internal API) |
| Admin Telegram Bot (AI) | MAP:1626 (admin-bot, /ai_status, /ai_train) |
| Push уведомления | ARCH:3673 (потоки push) |
| Batch endpoint (dashboard) | ARCH:2755 |
| Batch approve/reject (master-catalog) | ARCH:1903 |

---

## Файлы высшего и высокого риска (менять с осторожностью!)

| Файл | Риск | Влияние | Где подробности |
|------|------|---------|-----------------|
| `core/services/base_http_service.dart` | ВЫСШИЙ | ВСЕ 39 модулей | MAP:54 |
| `core/constants/api_constants.dart` | ВЫСШИЙ | Все с эндпоинтом | MAP:82 |
| `features/auth/services/auth_service.dart` | ВЫСШИЙ | ВСЕ модули | MAP:225 |
| `loyalty-proxy/index.js` | ВЫСШИЙ | ВСЕ API | MAP:1551 |
| `loyalty-proxy/utils/db.js` | ВЫСШИЙ | 41 модуль с DB | MAP:1603 |
| `loyalty-proxy/utils/db_schema.sql` | ВЫСШИЙ | Миграция на сервере | MAP:1603 |
| `core/services/base_report_service.dart` | Высокий | 5 отчётных модулей | MAP:68 |
| `core/services/multitenancy_filter_service.dart` | Высокий | 8+ модулей | MAP:102 |
| `features/employees/services/employee_service.dart` | Высокий | 8+ модулей | MAP:273 |
| `features/shops/models/shop_model.dart` | Высокий | 10+ модулей | MAP:307 |
| `features/employees/models/user_role_model.dart` | Высокий | Все с ролями | MAP:273 |

---

> **Как использовать**: Найди тему/модуль в таблице → возьми номер строки → `Read(file, offset=LINE, limit=50-100)`

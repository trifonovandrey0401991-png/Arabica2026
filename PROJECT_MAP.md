# PROJECT MAP — Карта зависимостей проекта Arabica

> **Цель этого файла**: показать КАК модули связаны друг с другом.
> Перед изменением любого файла — найди его в карте и проверь **"Если изменить"**.
> Дата обновления: 2026-02-19 (верифицировано по реальной файловой структуре)

---

## СОДЕРЖАНИЕ

1. [Обзор архитектуры](#1-обзор-архитектуры)
2. [Ядро системы (Core)](#2-ядро-системы-core)
3. [Модули по категориям](#3-модули-по-категориям)
4. [Карта зависимостей каждого модуля](#4-карта-зависимостей-каждого-модуля)
5. [Матрица влияния изменений](#5-матрица-влияния-изменений)
6. [Бэкенд API зависимости](#6-бэкенд-api-зависимости)
7. [Общие модели данных](#7-общие-модели-данных)
8. [Shared и App слои](#8-shared-и-app-слои)

---

## 1. Обзор архитектуры

```
Flutter App (lib/)                    Backend (loyalty-proxy/)
├── core/                             ├── index.js (главный роутер)
│   ├── constants/ (3 файла)          ├── api/ (67 файлов)
│   ├── services/ (15 файлов)         ├── modules/ (7 файлов: OCR, vision)
│   ├── theme/ (1 файл)               │
│   ├── widgets/ (1 файл)             ├── utils/ (13 файлов, вкл. db.js)
│   └── utils/ (5 файлов)             ├── services/ (1 файл: telegram)
├── features/ (35 модулей, 415 dart)  ├── PostgreSQL (arabica_db, ~40 таблиц)
├── shared/ (17 файлов)               └── /var/www/ (110+ директорий JSON, backup)
└── app/ (10 файлов)
```

**Ключевые числа:**
- 35 Flutter модулей (415 .dart файлов в features/, 468 всего в lib/)
- 67 API файлов бэкенда (api/)
- 10 автоматических планировщиков (schedulers) — ВСЕ в api/, НЕ в modules/
- 7 модулей бэкенда (modules/): OCR, vision, orders push
- 13 утилит бэкенда (utils/): кэш, пагинация, сессии, файловые операции, db.js, moscow_time и др.
- 6 ролей пользователей
- PostgreSQL (arabica_db, ~44 таблицы, 10400+ записей) + JSON файлы как backup/fallback
- 44 feature flag (`USE_DB_*=true`) для переключения между PostgreSQL и JSON
- Auth middleware: `requireAuth`/`requireAdmin` на всех 570 route handlers (добавлено 19.02.2026)
- Opt-in пагинация на 28+ эндпоинтах

---

## 2. Ядро системы (Core)

### 2.1 BaseHttpService — ЦЕНТРАЛЬНЫЙ СЕРВИС
**Файл:** `lib/core/services/base_http_service.dart`

Все Flutter сервисы вызывают API через него. Это самый критичный файл.

**Методы:** getList, get, post, put, patch, delete, getRaw, postRaw, simplePost
**Добавляет к каждому запросу:** API key + session token

```
ЕСЛИ ИЗМЕНИТЬ BaseHttpService:
> Сломается ВСЁ приложение (все 35 модулей)
> НИКОГДА не менять без полного тестирования
```

### 2.1b BaseReportService<T> — Базовый сервис отчётов
**Файл:** `lib/core/services/base_report_service.dart`

Generic класс для общих CRUD-операций отчётов. Используется через композицию (static `_base` instance).

**Методы:** getReports, getReportsForCurrentUser, getExpiredReports, getReport, deleteReport, confirmViaEndpoint, rejectViaEndpoint, sendStatusPush, buildQueryParams
**Зависит от:** BaseHttpService, MultitenancyFilterService, EmployeePushService

```
ЕСЛИ ИЗМЕНИТЬ BaseReportService:
> Затронет 5 сервисов: ShiftReport, ShiftHandoverReport, Recount, Envelope, CoffeeMachine
> Public API этих сервисов НЕ меняется — вызывающие файлы не затронуты
```

### 2.2 ApiConstants — Все эндпоинты
**Файл:** `lib/core/constants/api_constants.dart`

Содержит URL сервера и 50+ констант эндпоинтов.

```
ЕСЛИ ИЗМЕНИТЬ ApiConstants:
> Все модули, использующие изменённый эндпоинт, перестанут работать
> Проверь "Кто использует" в разделе 4
```

### 2.3 Другие Core константы

| Файл | Назначение |
|------|-----------|
| `core/constants/api_constants.dart` | URL сервера, все эндпоинты, headers |
| `core/constants/api_key.dart` | API ключ (в .gitignore) |
| `core/constants/app_constants.dart` | Константы приложения |

### 2.4 Core сервисы (15 файлов)

| Сервис | Файл | Кто использует | Если изменить |
|--------|-------|----------------|---------------|
| **BaseHttpService** | `core/services/base_http_service.dart` | ВСЕ 35 модулей | Сломается ВСЁ |
| **BaseReportService** | `core/services/base_report_service.dart` | shifts, shift_handover, recount, envelope, coffee_machine | 5 отчётных модулей |
| **NotificationService** | `core/services/notification_service.dart` | auth, shifts, attendance, recount, envelope, rko, tasks, shift_handover | Push-уведомления |
| **MultitenancyFilterService** | `core/services/multitenancy_filter_service.dart` | kpi, efficiency, envelope, recount, shifts, rko, coffee_machine, shift_handover | Фильтрация по магазинам |
| **PhotoUploadService** | `core/services/photo_upload_service.dart` | recount, shift_handover, recipes, reviews, tests, training | Загрузка фото |
| **MediaUploadService** | `core/services/media_upload_service.dart` | employee_chat, clients | Медиа в чатах |
| **EmployeePushService** | `core/services/employee_push_service.dart` | envelope, recount, shifts, rko, tasks, shift_handover, coffee_machine | Push сотрудникам |
| **FirebaseService** | `core/services/firebase_service.dart` | orders (навигация по push), auth (FCM token) | Push-навигация |
| **FirebaseServiceStub** | `core/services/firebase_service_stub.dart` | Web-платформа (заглушка) | Только web |
| **FirebaseWrapper** | `core/services/firebase_wrapper.dart` | Обёртка для Firebase | Инициализация |
| **FirebaseCoreStub** | `core/services/firebase_core_stub.dart` | Web-платформа (заглушка) | Только web |
| **AppUpdateService** | `core/services/app_update_service.dart` | main, app | Проверка обновлений |
| **BackgroundGpsService** | `core/services/background_gps_service.dart` | attendance, geofence | GPS в фоне |
| **ReportNotificationService** | `core/services/report_notification_service.dart` | shifts, recount, envelope, shift_handover | Уведомления об отчётах |
| **HtmlStub** | `core/services/html_stub.dart` | Web-платформа | Совместимость |

### 2.5 Core утилиты (5 файлов)

| Утилита | Файл | Кто использует | Если изменить |
|---------|-------|----------------|---------------|
| **CacheManager** | `core/utils/cache_manager.dart` | employees, shops, kpi, efficiency, tasks, recurring_tasks | Данные будут грузиться заново |
| **Logger** | `core/utils/logger.dart` | ВСЕ модули | Только логирование — безопасно |
| **PhoneNormalizer** | `core/utils/phone_normalizer.dart` | auth, employees, clients, efficiency | Нормализация телефонов |
| **ErrorHandler** | `core/utils/error_handler.dart` | Все сервисы | Обработка ошибок |
| **DateFormatter** | `core/utils/date_formatter.dart` | kpi, efficiency, shifts, attendance | Форматирование дат |

### 2.6 Core виджеты (1 файл)

| Виджет | Файл | Кто использует |
|--------|-------|----------------|
| **ShopIcon** | `core/widgets/shop_icon.dart` | shops, pages с иконками магазинов |

---

## 3. Модули по категориям

### Авторизация и пользователи
| Модуль | Папка | Файлов | Зависимости Core |
|--------|-------|--------|-----------------|
| **auth** | `features/auth/` | 13 | BaseHttpService, ApiConstants, SharedPreferences |
| **employees** | `features/employees/` | 13 | BaseHttpService, ApiConstants, CacheManager, PhotoUploadService |
| **job_application** | `features/job_application/` | 6 | BaseHttpService, ApiConstants |

### Магазины и настройки
| Модуль | Папка | Файлов | Зависимости Core |
|--------|-------|--------|-----------------|
| **shops** | `features/shops/` | 6 | BaseHttpService, ApiConstants, CacheManager, MultitenancyFilterService |

### Смены и посещаемость
| Модуль | Папка | Файлов | Зависимости Core |
|--------|-------|--------|-----------------|
| **shifts** | `features/shifts/` | 16 | BaseHttpService, ApiConstants, PhotoUploadService, NotificationService, MultitenancyFilterService |
| **attendance** | `features/attendance/` | 10 | BaseHttpService, ApiConstants, BackgroundGpsService |
| **work_schedule** | `features/work_schedule/` | 15 | BaseHttpService, ApiConstants |
| **shift_handover** | `features/shift_handover/` | 16 | BaseHttpService, ApiConstants, PhotoUploadService, MultitenancyFilterService, EmployeePushService |

### Отчёты и инвентаризация
| Модуль | Папка | Файлов | Зависимости Core |
|--------|-------|--------|-----------------|
| **recount** | `features/recount/` | 26 | BaseHttpService, ApiConstants, PhotoUploadService, MultitenancyFilterService, EmployeePushService |
| **envelope** | `features/envelope/` | 10 | BaseHttpService, ApiConstants, MultitenancyFilterService, EmployeePushService |
| **rko** | `features/rko/` | 10 | BaseHttpService, ApiConstants, CacheManager, MultitenancyFilterService |

### Заказы и меню
| Модуль | Папка | Файлов | Зависимости Core |
|--------|-------|--------|-----------------|
| **orders** | `features/orders/` | 7 | BaseHttpService, ApiConstants |
| **menu** | `features/menu/` | 3 | BaseHttpService, ApiConstants |
| **recipes** | `features/recipes/` | 7 | BaseHttpService, ApiConstants, PhotoUploadService |

### Аналитика и эффективность
| Модуль | Папка | Файлов | Зависимости Core |
|--------|-------|--------|-----------------|
| **kpi** | `features/kpi/` | 17 | BaseHttpService, ApiConstants, CacheManager, MultitenancyFilterService |
| **efficiency** | `features/efficiency/` | 58 | BaseHttpService, ApiConstants, CacheManager, MultitenancyFilterService |
| **rating** | `features/rating/` | 4 | BaseHttpService, ApiConstants |
| **main_cash** | `features/main_cash/` | 19 | BaseHttpService, ApiConstants |

### Обучение и тесты
| Модуль | Папка | Файлов | Зависимости Core |
|--------|-------|--------|-----------------|
| **training** | `features/training/` | 7 | BaseHttpService, ApiConstants, PhotoUploadService |
| **tests** | `features/tests/` | 8 | BaseHttpService, ApiConstants, PhotoUploadService |
| **product_questions** | `features/product_questions/` | 14 | BaseHttpService, ApiConstants |
| **ai_training** | `features/ai_training/` | 30 | BaseHttpService, ApiConstants |

### Коммуникации
| Модуль | Папка | Файлов | Зависимости Core |
|--------|-------|--------|-----------------|
| **employee_chat** | `features/employee_chat/` | 13 | BaseHttpService, ApiConstants, MediaUploadService, WebSocket |
| **clients** | `features/clients/` | 19 | BaseHttpService, ApiConstants, MediaUploadService |
| **reviews** | `features/reviews/` | 9 | BaseHttpService, ApiConstants, PhotoUploadService |

### Лояльность и бонусы
| Модуль | Папка | Файлов | Зависимости Core |
|--------|-------|--------|-----------------|
| **loyalty** | `features/loyalty/` | 14 | BaseHttpService, ApiConstants |
| **bonuses** | `features/bonuses/` | 4 | BaseHttpService, ApiConstants |
| **fortune_wheel** | `features/fortune_wheel/` | 6 | BaseHttpService, ApiConstants |
| **referrals** | `features/referrals/` | 5 | BaseHttpService, ApiConstants |

### Утилиты и прочее
| Модуль | Папка | Файлов | Зависимости Core |
|--------|-------|--------|-----------------|
| **tasks** | `features/tasks/` | 16 | BaseHttpService, ApiConstants, CacheManager |
| **data_cleanup** | `features/data_cleanup/` | 4 | BaseHttpService, ApiConstants |
| **coffee_machine** | `features/coffee_machine/` | 13 | BaseHttpService, ApiConstants, MultitenancyFilterService, EmployeePushService |
| **suppliers** | `features/suppliers/` | 3 | BaseHttpService, ApiConstants |
| **network_management** | `features/network_management/` | 2 | BaseHttpService, ApiConstants |
| **execution_chain** | `features/execution_chain/` | 3 | BaseHttpService, ApiConstants |

---

## 4. Карта зависимостей каждого модуля

### AUTH (Авторизация) — 13 файлов

```
Файлы Flutter:
├── models/
│   ├── auth_credentials.dart
│   └── auth_session.dart
├── services/
│   ├── auth_service.dart
│   ├── biometric_service.dart
│   ├── device_service.dart
│   └── secure_storage_service.dart
├── pages/
│   ├── forgot_pin_page.dart
│   ├── otp_verification_page.dart
│   ├── phone_entry_page.dart
│   ├── pin_entry_page.dart
│   └── pin_setup_page.dart
└── widgets/
    ├── pin_input_widget.dart
    └── otp_input_widget.dart

API эндпоинты:
├── POST /api/auth/login
├── POST /api/auth/register
├── POST /api/auth/register-simple
├── POST /api/auth/verify-otp
├── POST /api/auth/change-pin (только локально)
└── GET  /api/auth/check-session

Бэкенд файлы:
└── loyalty-proxy/api/auth_api.js

Зависит от: BaseHttpService, SharedPreferences, FirebaseMessaging
От него зависят: ВСЕ модули (session token)

ЕСЛИ ИЗМЕНИТЬ AUTH:
> Все пользователи будут разлогинены
> Невозможен вход в приложение — МАКСИМАЛЬНЫЙ РИСК
```

### EMPLOYEES (Сотрудники) — 13 файлов

```
Файлы Flutter:
├── models/
│   ├── employee_registration_model.dart
│   └── user_role_model.dart
├── services/
│   ├── employee_service.dart (основной, кэш 30 сек)
│   ├── employee_registration_service.dart
│   └── user_role_service.dart (определение роли)
└── pages/
    ├── employees_page.dart
    ├── employee_panel_page.dart
    ├── employee_preferences_dialog.dart
    ├── employee_registration_page.dart
    ├── employee_registration_select_employee_page.dart
    ├── employee_registration_view_page.dart
    ├── employee_schedule_page.dart
    └── unverified_employees_page.dart

Бэкенд файлы:
├── loyalty-proxy/api/employees_api.js
├── loyalty-proxy/api/employee_registration_api.js
└── loyalty-proxy/api/shop_managers_api.js

Зависит от: BaseHttpService, CacheManager, PhotoUploadService, SharedPreferences
От него зависят: kpi, efficiency, shifts, rko, envelope, recount, clients, tasks, shops

ЕСЛИ ИЗМЕНИТЬ EMPLOYEES:
> 8+ модулей затронуты
> KPI, Efficiency, роли и права доступа сломаются
```

### SHOPS (Магазины) — 6 файлов

```
Файлы Flutter:
├── models/
│   ├── shop_model.dart
│   └── shop_settings_model.dart
├── services/
│   ├── shop_service.dart
│   └── shop_products_service.dart
└── pages/
    ├── shops_management_page.dart
    └── shops_on_map_page.dart

Бэкенд файлы:
├── loyalty-proxy/api/shops_api.js
├── loyalty-proxy/api/shop_settings_api.js
├── loyalty-proxy/api/shop_coordinates_api.js
└── loyalty-proxy/api/shop_products_api.js

Зависит от: BaseHttpService, CacheManager, UserRoleService
От него зависят: kpi, efficiency, rko, MultitenancyFilterService, все модули с фильтрацией

ЕСЛИ ИЗМЕНИТЬ SHOPS:
> Фильтрация по магазинам во ВСЕХ модулях сломается
> 10+ модулей затронуты
```

### SHIFTS (Пересменки) — 16 файлов

```
Файлы Flutter:
├── models/
│   ├── shift_report_model.dart
│   ├── shift_question_model.dart
│   ├── shift_shortage_model.dart
│   └── pending_shift_report_model.dart
├── services/
│   ├── shift_report_service.dart
│   ├── shift_question_service.dart
│   ├── shift_sync_service.dart
│   └── pending_shift_service.dart
└── pages/
    ├── shift_reports_list_page.dart
    ├── shift_report_view_page.dart
    ├── shift_questions_management_page.dart
    ├── shift_questions_page.dart
    ├── shift_shop_selection_page.dart
    ├── shift_photo_gallery_page.dart
    ├── shift_summary_report_page.dart
    └── shift_edit_dialog.dart

Бэкенд файлы:
├── loyalty-proxy/api/shifts_api.js (отчёты смен + передач)
├── loyalty-proxy/api/shift_questions_api.js
├── loyalty-proxy/api/shift_transfers_api.js
├── loyalty-proxy/api/shift_transfers_notifications.js
├── loyalty-proxy/api/shift_ai_verification_api.js
└── loyalty-proxy/api/shift_automation_scheduler.js (каждые 5 мин)

Зависит от: BaseHttpService, PhotoUploadService, MultitenancyFilterService, NotificationService
От него зависят: kpi, efficiency, rko

ЕСЛИ ИЗМЕНИТЬ SHIFTS:
> KPI перестанет считать пересменки
> Efficiency баллы за смены сломаются
> RKO не получит данные последней смены
```

### ATTENDANCE (Посещаемость) — 10 файлов

```
Файлы Flutter:
├── models/
│   ├── attendance_model.dart
│   ├── shop_attendance_summary.dart
│   └── pending_attendance_model.dart
├── services/
│   ├── attendance_service.dart
│   └── attendance_report_service.dart
└── pages/
    ├── attendance_month_page.dart
    ├── attendance_reports_page.dart
    ├── attendance_shop_selection_page.dart
    ├── attendance_employee_detail_page.dart
    └── attendance_day_details_dialog.dart

Бэкенд файлы:
├── loyalty-proxy/api/attendance_api.js
└── loyalty-proxy/api/attendance_automation_scheduler.js (каждые 5 мин)

Зависит от: BaseHttpService, BackgroundGpsService
От него зависят: kpi, efficiency

ЕСЛИ ИЗМЕНИТЬ ATTENDANCE:
> KPI не покажет посещаемость
> Efficiency потеряет категорию "Посещаемость"
```

### WORK_SCHEDULE (Рабочий график) — 13 файлов

```
Файлы Flutter:
├── models/
│   ├── work_schedule_model.dart
│   └── shift_transfer_model.dart
├── services/
│   ├── work_schedule_service.dart
│   ├── shift_transfer_service.dart
│   ├── auto_fill_schedule_service.dart
│   └── schedule_pdf_service.dart
├── pages/
│   ├── work_schedule_page.dart
│   ├── my_schedule_page.dart
│   ├── shift_transfer_requests_page.dart
│   ├── employee_bulk_schedule_dialog.dart
│   ├── period_selection_dialog.dart
│   └── pdf_preview_page.dart
├── widgets/
│   ├── employee_list_tab.dart              # Таб "По сотрудникам"
│   └── schedule_toolbar.dart               # Тулбар с кнопками управления
└── work_schedule_validator.dart

Бэкенд файлы:
└── loyalty-proxy/api/work_schedule_api.js

Зависит от: BaseHttpService
От него зависят: kpi (опоздания), attendance (автоматическая проверка)

ЕСЛИ ИЗМЕНИТЬ WORK_SCHEDULE:
> KPI неправильно посчитает опоздания
> Автоматическая посещаемость сломается
```

### SHIFT_HANDOVER (Передача смены) — 13 файлов

```
Файлы Flutter:
├── models/
│   ├── shift_handover_report_model.dart
│   ├── shift_handover_question_model.dart
│   ├── pending_shift_handover_report_model.dart
│   └── pending_shift_handover_model.dart
├── services/
│   ├── shift_handover_report_service.dart
│   ├── shift_handover_question_service.dart
│   └── pending_shift_handover_service.dart
├── pages/
│   ├── shift_handover_reports_list_page.dart
│   ├── shift_handover_report_view_page.dart
│   ├── shift_handover_questions_management_page.dart
│   ├── shift_handover_questions_page.dart
│   ├── shift_handover_role_selection_page.dart
│   └── shift_handover_shop_selection_page.dart
└── widgets/
    ├── handover_report_card.dart            # Карточка отчёта пересменки
    ├── pending_shifts_list.dart             # Список ожидающих сдач
    └── overdue_shifts_list.dart             # Список просроченных сдач

Бэкенд файлы:
├── loyalty-proxy/api/shifts_api.js (отчёты передач обслуживаются здесь же)
├── loyalty-proxy/api/shift_handover_questions_api.js
└── loyalty-proxy/api/shift_handover_automation_scheduler.js (scheduler)

Зависит от: BaseHttpService, PhotoUploadService, MultitenancyFilterService, EmployeePushService
От него зависят: kpi, efficiency

ЕСЛИ ИЗМЕНИТЬ SHIFT_HANDOVER:
> KPI потеряет данные передач смен
> Efficiency баллы за передачу смены сломаются
```

### RECOUNT (Пересчёт товаров) — 20 файлов

```
Файлы Flutter:
├── models/
│   ├── recount_report_model.dart
│   ├── recount_question_model.dart
│   ├── recount_answer_model.dart
│   ├── recount_pivot_model.dart
│   ├── recount_points_model.dart
│   ├── recount_settings_model.dart
│   ├── pending_recount_report_model.dart
│   └── pending_recount_model.dart
├── services/
│   ├── recount_service.dart
│   ├── recount_question_service.dart
│   ├── recount_points_service.dart
│   └── pending_recount_service.dart
├── pages/
│   ├── recount_reports_list_page.dart
│   ├── recount_report_view_page.dart
│   ├── recount_management_tabs_page.dart
│   ├── recount_questions_management_page.dart
│   ├── recount_questions_page.dart
│   ├── recount_shop_selection_page.dart
│   ├── recount_points_settings_page.dart
│   └── recount_summary_report_page.dart
└── widgets/
    ├── recount_report_card.dart             # Карточка отчёта пересчёта
    ├── expired_recount_report_card.dart     # Карточка просроченного отчёта
    ├── pending_recount_card.dart            # Карточка ожидающего пересчёта
    ├── failed_recount_card.dart             # Карточка непройденного пересчёта
    ├── recount_info_chip.dart              # Информационный чип
    └── recount_filters_section.dart         # Секция фильтров

Бэкенд файлы:
├── loyalty-proxy/api/recount_api.js
├── loyalty-proxy/api/recount_questions_api.js
├── loyalty-proxy/api/recount_points_api.js
└── loyalty-proxy/api/recount_automation_scheduler.js (scheduler)

Зависит от: BaseHttpService, PhotoUploadService, MultitenancyFilterService, EmployeePushService
От него зависят: kpi, efficiency

ЕСЛИ ИЗМЕНИТЬ RECOUNT:
> KPI потеряет данные пересчётов
> Efficiency баллы за пересчёт сломаются
```

### ENVELOPE (Конверты) — 10 файлов

```
Файлы Flutter:
├── models/
│   ├── envelope_report_model.dart
│   ├── envelope_question_model.dart
│   └── pending_envelope_report_model.dart
├── services/
│   ├── envelope_report_service.dart
│   └── envelope_question_service.dart
├── pages/
│   ├── envelope_reports_list_page.dart
│   ├── envelope_report_view_page.dart
│   ├── envelope_form_page.dart
│   └── envelope_questions_management_page.dart
└── widgets/
    └── add_expense_dialog.dart

Бэкенд файлы:
├── loyalty-proxy/api/envelope_api.js (включает и вопросы)
└── loyalty-proxy/api/envelope_automation_scheduler.js (scheduler)

Зависит от: BaseHttpService, MultitenancyFilterService, EmployeePushService
От него зависят: kpi, efficiency

ЕСЛИ ИЗМЕНИТЬ ENVELOPE:
> KPI потеряет данные конвертов
> Efficiency баллы за конверты сломаются
```

### RKO (Расходно-кассовые ордера) — 10 файлов

```
Файлы Flutter:
├── models/
│   └── rko_report_model.dart
├── services/
│   ├── rko_service.dart
│   ├── rko_reports_service.dart
│   └── rko_pdf_service.dart
└── pages/
    ├── rko_type_selection_page.dart
    ├── rko_amount_input_page.dart
    ├── rko_reports_page.dart
    ├── rko_employee_reports_page.dart
    ├── rko_shop_reports_page.dart
    └── rko_pdf_viewer_page.dart

Бэкенд файлы:
├── loyalty-proxy/api/rko_api.js
└── loyalty-proxy/api/rko_automation_scheduler.js (scheduler)

Зависит от: BaseHttpService, CacheManager, ShopSettings, EmployeeRegistrationService
От него зависят: kpi, efficiency, main_cash

ЕСЛИ ИЗМЕНИТЬ RKO:
> KPI потеряет финансовые данные
> Efficiency баллы за РКО сломаются
```

### ORDERS (Заказы) — 7 файлов

```
Файлы Flutter:
├── services/
│   ├── order_service.dart
│   └── order_timeout_settings_service.dart
└── pages/
    ├── orders_page.dart
    ├── orders_report_page.dart
    ├── employee_orders_page.dart
    ├── employee_order_detail_page.dart
    └── cart_page.dart

Бэкенд файлы:
├── loyalty-proxy/api/orders_api.js
├── loyalty-proxy/api/order_timeout_api.js (scheduler таймаутов)
└── loyalty-proxy/modules/orders.js (push-уведомления)

Зависит от: BaseHttpService, BonusService (списание бонусов)
От него зависят: efficiency (категория заказы), loyalty (бонусы)

ЕСЛИ ИЗМЕНИТЬ ORDERS:
> Efficiency потеряет категорию "Заказы"
> Бонусы при заказе перестанут начисляться
```

### MENU (Меню) — 3 файла

```
Файлы Flutter:
├── services/
│   └── menu_service.dart
└── pages/
    ├── menu_page.dart
    └── menu_groups_page.dart

Бэкенд файлы:
└── loyalty-proxy/api/menu_api.js

Зависит от: BaseHttpService
От него зависят: orders (список товаров для заказа)
```

### RECIPES (Рецепты) — 7 файлов

```
Файлы Flutter:
├── models/
│   └── recipe_model.dart
├── services/
│   └── recipe_service.dart
└── pages/
    ├── recipes_list_page.dart
    ├── recipe_form_page.dart
    ├── recipe_edit_page.dart
    ├── recipe_list_edit_page.dart
    └── recipe_view_page.dart

Бэкенд файлы:
└── loyalty-proxy/api/recipes_api.js

Зависит от: BaseHttpService, PhotoUploadService
От него зависят: (изолированный модуль)
```

### KPI (Ключевые показатели) — 17 файлов

```
Файлы Flutter:
├── models/
│   ├── kpi_models.dart
│   ├── kpi_employee_month_stats.dart
│   └── kpi_shop_month_stats.dart
├── services/
│   ├── kpi_service.dart (агрегирует 6+ источников)
│   ├── kpi_aggregation_service.dart
│   ├── kpi_cache_service.dart
│   ├── kpi_persistence_service.dart (offline fallback)
│   ├── kpi_schedule_integration_service.dart
│   ├── kpi_filters.dart
│   └── kpi_normalizers.dart
└── pages/
    ├── kpi_type_selection_page.dart
    ├── kpi_employees_list_page.dart
    ├── kpi_employee_detail_page.dart
    ├── kpi_employee_day_detail_page.dart
    ├── kpi_shops_list_page.dart
    ├── kpi_shop_calendar_page.dart
    └── kpi_shop_day_detail_dialog.dart

Бэкенд файлы: НЕТ (только агрегация на клиенте)

Зависит от: attendance, shifts, recount, rko, envelope, shift_handover, work_schedule, employees, shops
От него зависят: (конечный потребитель)

ЕСЛИ ИЗМЕНИТЬ KPI:
> Только KPI страница сломается (но критична для менеджеров)
> Если изменить ЛЮБОЙ из 9 модулей выше — KPI тоже сломается!
```

### EFFICIENCY (Эффективность) — 58 файлов

```
Файлы Flutter:
├── models/
│   ├── efficiency_data_model.dart
│   ├── manager_efficiency_model.dart
│   ├── points_settings_model.dart
│   └── settings/ (13 файлов настроек баллов)
│       ├── points_settings_base.dart
│       ├── points_settings.dart
│       ├── shift_points_settings.dart
│       ├── recount_points_settings.dart
│       ├── shift_handover_points_settings.dart
│       ├── attendance_points_settings.dart
│       ├── rko_points_settings.dart
│       ├── test_points_settings.dart
│       ├── reviews_points_settings.dart
│       ├── product_search_points_settings.dart
│       ├── orders_points_settings.dart
│       ├── task_points_settings.dart
│       ├── envelope_points_settings.dart
│       ├── manager_points_settings.dart
│       └── coffee_machine_points_settings.dart
├── services/
│   ├── efficiency_data_service.dart (batch загрузка)
│   ├── efficiency_calculation_service.dart
│   ├── manager_efficiency_service.dart
│   ├── points_settings_service.dart
│   └── data_loaders/
│       ├── data_loaders.dart
│       ├── efficiency_batch_parsers.dart
│       └── efficiency_record_loaders.dart
├── utils/
│   └── efficiency_utils.dart
├── pages/
│   ├── my_efficiency_page.dart
│   ├── employees_efficiency_page.dart
│   ├── employee_efficiency_detail_page.dart
│   ├── efficiency_by_shop_page.dart
│   ├── shop_efficiency_detail_page.dart
│   ├── efficiency_by_employee_page.dart
│   ├── efficiency_analytics_page.dart
│   ├── points_settings_page.dart
│   └── settings_tabs/ (17 файлов настроек)
│       ├── shift_points_settings_page.dart
│       ├── shift_points_settings_page_v2.dart
│       ├── recount_efficiency_points_settings_page.dart
│       ├── shift_handover_points_settings_page.dart
│       ├── attendance_points_settings_page.dart
│       ├── rko_points_settings_page.dart
│       ├── test_points_settings_page.dart
│       ├── reviews_points_settings_page.dart
│       ├── product_search_points_settings_page.dart
│       ├── orders_points_settings_page.dart
│       ├── task_points_settings_page.dart
│       ├── regular_task_points_settings_page.dart
│       ├── recurring_task_points_settings_page.dart
│       ├── envelope_points_settings_page.dart
│       ├── manager_points_settings_page.dart
│       ├── coffee_machine_points_settings_page.dart
│       └── generic_points_settings_page.dart
└── widgets/
    ├── efficiency_common_widgets.dart
    ├── points_settings_scaffold.dart
    ├── rating_preview_widget.dart
    ├── settings_save_button_widget.dart
    ├── settings_slider_widget.dart
    ├── settings_widgets.dart
    └── time_window_picker_widget.dart

Бэкенд файлы:
├── loyalty-proxy/api/efficiency_penalties_api.js
├── loyalty-proxy/api/points_settings_api.js
├── loyalty-proxy/api/task_points_settings_api.js
├── loyalty-proxy/api/manager_efficiency_api.js
└── loyalty-proxy/api/dashboard_batch_api.js

Зависит от: shifts, recount, shift_handover, attendance, tasks, reviews, product_questions, orders, rko, envelope
10 категорий данных! Самый "зависимый" модуль.

ЕСЛИ ИЗМЕНИТЬ EFFICIENCY:
> Баллы эффективности перестанут считаться
> Зарплатные расчёты будут неверными
```

### RATING (Рейтинг сотрудников) — 4 файла

```
Файлы Flutter:
├── models/
│   └── employee_rating_model.dart
├── services/
│   └── rating_service.dart
├── pages/
│   └── my_rating_page.dart
└── widgets/
    └── rating_badge_widget.dart

Бэкенд файлы:
└── loyalty-proxy/api/rating_wheel_api.js

Зависит от: BaseHttpService
От него зависят: fortune_wheel (рейтинг = кол-во спинов)
```

### MAIN_CASH (Главная касса) — 19 файлов

```
Файлы Flutter:
├── models/
│   ├── withdrawal_model.dart
│   ├── withdrawal_expense_model.dart
│   ├── shop_cash_balance_model.dart
│   └── shop_revenue_model.dart
├── services/
│   ├── main_cash_service.dart
│   ├── withdrawal_service.dart
│   ├── turnover_service.dart
│   ├── revenue_analytics_service.dart
│   └── store_manager_service.dart
├── pages/
│   ├── main_cash_page.dart
│   ├── revenue_analytics_page.dart
│   ├── shop_balance_details_page.dart
│   ├── store_managers_page.dart
│   ├── withdrawal_form_page.dart
│   ├── withdrawal_employee_selection_page.dart
│   └── withdrawal_shop_selection_page.dart
└── widgets/
    ├── withdrawal_dialog.dart
    ├── withdrawal_confirmation_dialog.dart
    └── turnover_calendar.dart

Бэкенд файлы:
└── loyalty-proxy/api/withdrawals_api.js

Зависит от: BaseHttpService, rko (финансовые данные)
От него зависят: (конечный потребитель финансов)
```

### FORTUNE_WHEEL (Колесо фортуны) — 6 файлов

```
Файлы Flutter:
├── models/
│   └── fortune_wheel_model.dart
├── services/
│   └── fortune_wheel_service.dart
├── pages/
│   ├── fortune_wheel_page.dart
│   ├── wheel_reports_page.dart
│   └── wheel_settings_page.dart
└── widgets/
    └── animated_wheel_widget.dart

Бэкенд файлы:
└── loyalty-proxy/api/rating_wheel_api.js (тот же файл что rating)

Зависит от: BaseHttpService, rating (количество спинов)
От него зависят: (изолированный модуль)
```

### TRAINING (Обучение) — 7 файлов

```
Файлы Flutter:
├── models/
│   ├── training_model.dart
│   └── content_block.dart
├── services/
│   └── training_article_service.dart
└── pages/
    ├── training_page.dart
    ├── training_articles_management_page.dart
    ├── training_article_editor_page.dart
    └── training_article_view_page.dart

Бэкенд файлы:
└── loyalty-proxy/api/training_api.js

Зависит от: BaseHttpService, PhotoUploadService
От него зависят: (изолированный модуль)
```

### TESTS (Тесты для сотрудников) — 8 файлов

```
Файлы Flutter:
├── models/
│   ├── test_model.dart
│   └── test_result_model.dart
├── services/
│   ├── test_question_service.dart
│   └── test_result_service.dart
└── pages/
    ├── test_page.dart
    ├── test_questions_management_page.dart
    ├── test_report_page.dart
    └── test_notifications_page.dart

Бэкенд файлы:
└── loyalty-proxy/api/tests_api.js (включает и вопросы)

Зависит от: BaseHttpService, PhotoUploadService
От него зависят: efficiency (категория tests)
```

### PRODUCT_QUESTIONS (Вопросы по товарам) — 14 файлов

```
Файлы Flutter:
├── models/
│   ├── product_question_model.dart
│   └── product_question_message_model.dart
├── services/
│   └── product_question_service.dart
└── pages/
    ├── product_search_page.dart
    ├── product_search_shop_selection_page.dart
    ├── product_questions_management_page.dart
    ├── product_questions_report_page.dart
    ├── product_question_input_page.dart
    ├── product_question_answer_page.dart
    ├── product_question_dialog_page.dart
    ├── product_question_client_dialog_page.dart
    ├── product_question_personal_dialog_page.dart
    ├── product_question_employee_dialog_page.dart
    └── product_question_shops_list_page.dart

Бэкенд файлы:
├── loyalty-proxy/api/product_questions_api.js
├── loyalty-proxy/api/product_questions_notifications.js
└── loyalty-proxy/api/product_questions_penalty_scheduler.js (scheduler)

Зависит от: BaseHttpService
От него зависят: efficiency (категория product_search)
```

### AI_TRAINING (ИИ обучение / Vision) — 30 файлов

```
Файлы Flutter:
├── models/
│   ├── cigarette_training_model.dart
│   ├── master_product_model.dart
│   ├── pending_code_model.dart
│   ├── photo_template.dart
│   ├── shift_ai_verification_model.dart
│   ├── z_report_template_model.dart
│   └── z_report_sample_model.dart
├── services/
│   ├── cigarette_vision_service.dart
│   ├── master_catalog_service.dart
│   ├── shift_ai_verification_service.dart
│   ├── z_report_service.dart
│   └── z_report_template_service.dart
├── pages/
│   ├── ai_training_page.dart
│   ├── cigarette_annotation_page.dart
│   ├── cigarette_photos_management_dialog.dart
│   ├── cigarette_shop_details_dialog.dart
│   ├── cigarette_shop_selection_dialog.dart
│   ├── cigarette_training_page.dart
│   ├── pending_codes_page.dart
│   ├── photo_templates_page.dart
│   ├── shift_training_page.dart
│   ├── shift_ai_verification_page.dart
│   ├── template_camera_page.dart
│   ├── template_editor_page.dart
│   ├── training_settings_page.dart
│   └── z_report_training_page.dart
└── widgets/
    └── bounding_box_painter.dart

Бэкенд файлы:
├── loyalty-proxy/api/cigarette_vision_api.js
├── loyalty-proxy/api/z_report_api.js
├── loyalty-proxy/api/shift_ai_verification_api.js
├── loyalty-proxy/api/master_catalog_api.js
├── loyalty-proxy/api/master_catalog_notifications.js
├── loyalty-proxy/modules/cigarette-vision.js
├── loyalty-proxy/modules/z-report-ocr.js
├── loyalty-proxy/modules/z-report-templates.js
└── loyalty-proxy/modules/z-report-vision.js

Зависит от: BaseHttpService
От него зависят: (изолированный, но связан с shifts через AI верификацию)
```

### EMPLOYEE_CHAT (Чат сотрудников) — 13 файлов

```
Файлы Flutter:
├── models/
│   ├── employee_chat_model.dart
│   └── employee_chat_message_model.dart
├── services/
│   ├── employee_chat_service.dart (HTTP + WebSocket)
│   ├── chat_websocket_service.dart
│   └── client_group_chat_service.dart
├── pages/
│   ├── employee_chat_page.dart
│   ├── employee_chats_list_page.dart
│   ├── create_group_page.dart
│   ├── group_info_page.dart
│   ├── new_chat_page.dart
│   └── shop_chat_members_page.dart
└── widgets/
    ├── chat_input_field.dart
    └── chat_message_bubble.dart

Бэкенд файлы:
├── loyalty-proxy/api/employee_chat_api.js
├── loyalty-proxy/api/employee_chat_websocket.js (WebSocket сервер)
└── loyalty-proxy/api/media_api.js (загрузка медиа)

Зависит от: BaseHttpService, MediaUploadService, WebSocket
От него зависят: (изолированный модуль)

ЕСЛИ ИЗМЕНИТЬ EMPLOYEE_CHAT:
> WebSocket может разорваться — сообщения не приходят в реальном времени
```

### CLIENTS (Клиенты / CRM) — 19 файлов

```
Файлы Flutter:
├── models/
│   ├── client_model.dart
│   ├── client_message_model.dart
│   ├── client_dialog_model.dart
│   ├── network_message_model.dart
│   └── management_message_model.dart
├── services/
│   ├── client_service.dart
│   ├── client_dialog_service.dart
│   ├── network_message_service.dart
│   ├── management_message_service.dart
│   └── registration_service.dart
└── pages/
    ├── clients_management_page.dart
    ├── client_chat_page.dart
    ├── client_dialog_page.dart
    ├── admin_management_dialog_page.dart
    ├── management_dialog_page.dart
    ├── management_dialogs_list_page.dart
    ├── network_dialog_page.dart
    ├── broadcast_messages_page.dart
    └── registration_page.dart

Бэкенд файлы:
└── loyalty-proxy/api/clients_api.js (включает диалоги)

Зависит от: BaseHttpService, MediaUploadService
От него зависят: (изолированный от других модулей)
```

### LOYALTY (Лояльность / Геймификация) — 14 файлов

```
Файлы Flutter:
├── models/
│   └── loyalty_gamification_model.dart
├── services/
│   ├── loyalty_service.dart
│   ├── loyalty_gamification_service.dart
│   └── loyalty_storage.dart
├── pages/
│   ├── loyalty_page.dart
│   ├── loyalty_scanner_page.dart
│   ├── loyalty_promo_management_page.dart
│   ├── loyalty_gamification_settings_page.dart
│   ├── client_wheel_page.dart
│   ├── client_wheel_prizes_report_page.dart
│   ├── pending_prize_page.dart
│   └── prize_scanner_page.dart
└── widgets/
    ├── qr_badges_widget.dart
    └── wheel_progress_widget.dart

Бэкенд файлы:
├── loyalty-proxy/api/loyalty_gamification_api.js
└── loyalty-proxy/api/loyalty_promo_api.js

Зависит от: BaseHttpService
От него зависят: bonuses (бонусная система связана)
```

### BONUSES (Бонусы / Штрафы) — 4 файла

```
Файлы Flutter:
├── models/
│   └── bonus_penalty_model.dart
├── services/
│   └── bonus_penalty_service.dart
└── pages/
    ├── bonus_penalty_management_page.dart
    └── bonus_penalty_history_page.dart

Бэкенд файлы:
└── loyalty-proxy/api/bonus_penalties_api.js

Зависит от: BaseHttpService
От него зависят: orders (списание бонусов при заказе)
```

### REFERRALS (Реферальная система) — 5 файлов

```
Файлы Flutter:
├── models/
│   └── referral_stats_model.dart
├── services/
│   └── referral_service.dart
└── pages/
    ├── referrals_report_page.dart
    ├── referrals_points_settings_page.dart
    └── employee_referrals_detail_page.dart

Бэкенд файлы:
└── loyalty-proxy/api/referrals_api.js

Зависит от: BaseHttpService
От него зависят: (изолированный)
```

### REVIEWS (Отзывы) — 9 файлов

```
Файлы Flutter:
├── models/
│   └── review_model.dart
├── services/
│   └── review_service.dart
└── pages/
    ├── review_shop_selection_page.dart
    ├── review_type_selection_page.dart
    ├── review_text_input_page.dart
    ├── review_detail_page.dart
    ├── reviews_list_page.dart
    ├── reviews_shop_detail_page.dart
    └── client_reviews_list_page.dart

Бэкенд файлы:
└── loyalty-proxy/api/reviews_api.js

Зависит от: BaseHttpService, PhotoUploadService
От него зависят: efficiency (категория reviews)
```

### TASKS (Задачи) — 16 файлов

```
Файлы Flutter:
├── models/
│   ├── task_model.dart
│   └── recurring_task_model.dart
├── services/
│   ├── task_service.dart
│   └── recurring_task_service.dart
├── pages/
│   ├── my_tasks_page.dart
│   ├── task_management_page.dart
│   ├── task_detail_page.dart
│   ├── task_response_page.dart
│   ├── task_reports_page.dart
│   ├── task_analytics_page.dart
│   ├── create_task_page.dart
│   ├── create_recurring_task_page.dart
│   ├── recurring_task_response_page.dart
│   ├── task_recipient_selection_page.dart
│   └── recurring_recipient_selection_page.dart
└── widgets/
    └── task_common_widgets.dart

Бэкенд файлы:
├── loyalty-proxy/api/tasks_api.js
└── loyalty-proxy/api/recurring_tasks_api.js

Зависит от: BaseHttpService, CacheManager
От него зависят: efficiency (категория tasks)
```

### COFFEE_MACHINE (Кофемашины) — 13 файлов

```
Файлы Flutter:
├── models/
│   ├── coffee_machine_report_model.dart
│   ├── coffee_machine_template_model.dart
│   └── pending_coffee_machine_report_model.dart
├── services/
│   ├── coffee_machine_report_service.dart
│   ├── coffee_machine_template_service.dart
│   └── coffee_machine_ocr_service.dart
├── pages/
│   ├── coffee_machine_form_page.dart
│   ├── coffee_machine_reports_list_page.dart
│   ├── coffee_machine_report_view_page.dart
│   ├── coffee_machine_questions_management_page.dart
│   ├── coffee_machine_template_management_page.dart
│   └── coffee_machine_training_photos_page.dart
└── widgets/
    └── counter_region_selector.dart

Бэкенд файлы:
├── loyalty-proxy/api/coffee_machine_api.js
├── loyalty-proxy/api/coffee_machine_automation_scheduler.js (scheduler)
├── loyalty-proxy/modules/counter-ocr.js (OCR модуль)
└── loyalty-proxy/modules/ocr_server.py (EasyOCR сервер, порт 5001)

Зависит от: BaseHttpService, MultitenancyFilterService, EmployeePushService
От него зависят: (изолированный модуль)
```

### DATA_CLEANUP (Очистка данных) — 4 файла

```
Файлы Flutter:
├── models/
│   └── cleanup_category.dart
├── services/
│   └── cleanup_service.dart
├── pages/
│   └── data_cleanup_page.dart
└── widgets/
    └── cleanup_period_dialog.dart

Бэкенд файлы:
└── loyalty-proxy/api/data_cleanup_api.js (включает startAutoCleanupScheduler)

ЕСЛИ ИЗМЕНИТЬ DATA_CLEANUP:
> Может случайно удалить данные других модулей!
```

### JOB_APPLICATION (Заявки на работу) — 6 файлов

```
Файлы Flutter:
├── models/
│   └── job_application_model.dart
├── services/
│   └── job_application_service.dart
└── pages/
    ├── job_application_welcome_page.dart
    ├── job_application_form_page.dart
    ├── job_application_detail_page.dart
    └── job_applications_list_page.dart

Бэкенд файлы:
└── loyalty-proxy/api/job_applications_api.js

Зависит от: BaseHttpService
От него зависят: (изолированный)
```

### SUPPLIERS (Поставщики) — 3 файла

```
Файлы Flutter:
├── models/
│   └── supplier_model.dart
├── services/
│   └── supplier_service.dart
└── pages/
    └── suppliers_management_page.dart

Бэкенд файлы:
└── loyalty-proxy/api/suppliers_api.js

Зависит от: BaseHttpService
От него зависят: (изолированный)
```

### NETWORK_MANAGEMENT (Управление сетью) — 2 файла

```
Файлы Flutter:
├── services/
│   └── network_management_service.dart
└── pages/
    └── network_management_page.dart

Бэкенд файлы: (использует эндпоинты других модулей)

Зависит от: BaseHttpService
От него зависят: (изолированный)
```

### EXECUTION_CHAIN (Цепочка исполнения) — 3 файла

```
Файлы Flutter:
├── models/
│   └── execution_chain_model.dart
├── services/
│   └── execution_chain_service.dart
└── pages/
    └── execution_chain_page.dart

Бэкенд файлы:
└── loyalty-proxy/api/execution_chain_api.js

Зависит от: BaseHttpService
От него зависят: (изолированный)
```

---

## 5. Матрица влияния изменений

### Высший риск (сломает 10+ модулей):
| Файл | Влияние |
|------|---------|
| `base_http_service.dart` | ВСЕ 35 модулей |
| `api_constants.dart` | Все модули использующие изменённый эндпоинт |
| `auth_service.dart` / `auth_api.js` | ВСЕ модули (нет токена = нет доступа) |
| `index.js` (бэкенд роутер) | ВСЕ API эндпоинты |
| `utils/db.js` | ВСЕ 41 модуль с PostgreSQL (при USE_DB=true) |
| `utils/db_schema.sql` | Схема БД — ALTER TABLE требует миграции на сервере |

### Высокий риск (сломает 5-10 модулей):
| Файл | Влияние |
|------|---------|
| `base_report_service.dart` | shifts, shift_handover, recount, envelope, coffee_machine |
| `multitenancy_filter_service.dart` | kpi, efficiency, envelope, recount, shifts, rko, coffee_machine, shift_handover |
| `employee_service.dart` | kpi, efficiency, shifts, rko, clients, tasks |
| `shop_service.dart` / `shop_model.dart` | kpi, efficiency, rko, multitenancy фильтрация |
| `user_role_service.dart` | Все страницы с ролевым доступом |
| `notification_service.dart` | 8+ модулей с push |
| `firebase_service.dart` | orders (навигация по push), clients, + зависит от UserRoleService |
| `employee_push_service.dart` | envelope, recount, shifts, rko, tasks, shift_handover, coffee_machine |

### Средний риск (сломает 2-4 модуля):
| Файл | Влияние |
|------|---------|
| `shift_report_service.dart` | kpi, efficiency, rko |
| `attendance_service.dart` | kpi, efficiency |
| `recount_service.dart` | kpi, efficiency |
| `envelope_report_service.dart` | kpi, efficiency |
| `photo_upload_service.dart` | recount, shift_handover, recipes, reviews, tests, training |
| `media_upload_service.dart` | employee_chat, clients |
| `phone_normalizer.dart` | auth, employees, clients, efficiency |

### Низкий риск (изолированные модули):
| Модуль | Влияние |
|--------|---------|
| recipes | Только рецепты |
| training | Только обучение |
| ai_training | Только ИИ обучение |
| job_application | Только заявки |
| referrals | Только рефералы |
| fortune_wheel | Только колесо |
| coffee_machine | Только кофемашины |
| employee_chat | Только чат |
| suppliers | Только поставщики |
| execution_chain | Только цепочка |
| network_management | Только управление сетью |
| data_cleanup | Только очистка |

---

## 6. Бэкенд API зависимости

### index.js — Главный роутер
```
Подключает 67 API файлов через require() и setup*()
48 вызовов setup*API() для маршрутизации
10 планировщиков запущены автоматически
PUBLIC_ENDPOINTS: /health, /, /api/auth
PUBLIC_WRITE_PATHS: 21+ путь для POST/PUT/DELETE без сессии
Middleware: API Key → Session → Rate Limiting → CORS → Compression
```

### Планировщики (Schedulers) — 10 штук, ВСЕ в api/

| # | Scheduler | Файл | Что делает |
|---|-----------|-------|-----------|
| 1 | shift-automation | `api/shift_automation_scheduler.js` | Напоминания о пересменке |
| 2 | recount-automation | `api/recount_automation_scheduler.js` | Напоминания о пересчёте |
| 3 | rko-automation | `api/rko_automation_scheduler.js` | Автоматические РКО |
| 4 | shift-handover-automation | `api/shift_handover_automation_scheduler.js` | Напоминания о передаче |
| 5 | attendance-automation | `api/attendance_automation_scheduler.js` | Автопосещаемость по GPS |
| 6 | envelope-automation | `api/envelope_automation_scheduler.js` | Напоминания о конвертах |
| 7 | coffee-machine-automation | `api/coffee_machine_automation_scheduler.js` | Напоминания о кофемашинах |
| 8 | product-questions-penalty | `api/product_questions_penalty_scheduler.js` | Штрафы за просроченные вопросы |
| 9 | order-timeout | `api/order_timeout_api.js` | Таймауты заказов |
| 10 | data-cleanup | `api/data_cleanup_api.js` | Автоочистка старых данных |

### Модули бэкенда (modules/) — 7 файлов

| Файл | Назначение |
|------|-----------|
| `modules/counter-ocr.js` | OCR счётчиков кофемашин (вызывает EasyOCR) |
| `modules/ocr_server.py` | EasyOCR Python сервер (порт 5001) |
| `modules/orders.js` | Push-уведомления о заказах |
| `modules/cigarette-vision.js` | CV распознавание сигарет |
| `modules/z-report-ocr.js` | OCR Z-отчётов |
| `modules/z-report-templates.js` | Шаблоны Z-отчётов |
| `modules/z-report-vision.js` | Vision для Z-отчётов |

### Утилиты бэкенда (utils/) — 13 файлов

| Файл | Назначение |
|------|-----------|
| `utils/admin_cache.js` | Кэш админских данных (preload + periodic rebuild) |
| `utils/async_fs.js` | Асинхронные файловые операции (writeJsonFile с atomic write + lock) |
| `utils/base_report_scheduler.js` | Базовый класс для автоматизации отчётов |
| `utils/data_cache.js` | Общий кэш данных (employees, shops) |
| `utils/db.js` | PostgreSQL клиент (findById, findAll, upsert, deleteById, query, transaction) |
| `utils/db_schema.sql` | SQL схема всех ~40 таблиц PostgreSQL |
| `utils/file_helpers.js` | Хелперы файлов (sanitizeId, fileExists, maskPhone) |
| `utils/file_lock.js` | Блокировка файлов при записи (race condition protection) |
| `utils/image_compress.js` | Сжатие изображений через sharp |
| `utils/moscow_time.js` | Московское время UTC+3 (getMoscowTime, getMoscowDate) |
| `utils/pagination.js` | Пагинация ответов API |
| `utils/session_middleware.js` | Session middleware (JWT токены) |
| `utils/test_file_lock.js` | Тест блокировки файлов |

### Сервисы бэкенда (services/) — 1 файл

| Файл | Назначение |
|------|-----------|
| `services/telegram_bot_service.js` | Telegram бот |

### Полный список API файлов (67 штук)

**Auth & Users (4):** auth_api, employees_api, employee_registration_api, shop_managers_api
**Shops (4):** shops_api, shop_settings_api, shop_coordinates_api, shop_products_api
**Shifts (8):** shifts_api, shift_questions_api, shift_handover_questions_api, shift_transfers_api, shift_transfers_notifications, shift_ai_verification_api, shift_automation_scheduler, shift_handover_automation_scheduler
**Attendance (3):** attendance_api, attendance_automation_scheduler, work_schedule_api
**Recount (4):** recount_api, recount_questions_api, recount_points_api, recount_automation_scheduler
**Envelope (2):** envelope_api, envelope_automation_scheduler
**RKO (2):** rko_api, rko_automation_scheduler
**Orders (3):** orders_api, order_timeout_api, menu_api
**Efficiency (5):** efficiency_penalties_api, points_settings_api, task_points_settings_api, manager_efficiency_api, dashboard_batch_api
**Rating (1):** rating_wheel_api
**Training (2):** training_api, tests_api
**AI/Vision (5):** cigarette_vision_api, z_report_api, shift_ai_verification_api, master_catalog_api, master_catalog_notifications
**Chat (3):** employee_chat_api, employee_chat_websocket, media_api
**Clients (1):** clients_api
**Loyalty (3):** loyalty_gamification_api, loyalty_promo_api, bonus_penalties_api
**Other (17):** referrals_api, reviews_api, recipes_api, suppliers_api, product_questions_api, product_questions_notifications, product_questions_penalty_scheduler, tasks_api, recurring_tasks_api, job_applications_api, data_cleanup_api, execution_chain_api, geofence_api, pending_api, report_notifications_api, withdrawals_api, coffee_machine_api + coffee_machine_automation_scheduler

### PostgreSQL (основное хранилище с 2026-02-17)

```
База: arabica_db, пользователь: arabica_app, peer auth
Таблиц: ~40, Записей: 10400+, Размер: 17MB
Утилита: utils/db.js (findById, findAll, upsert, deleteById, query, transaction)
Схема: utils/db_schema.sql

Паттерн dual-write:
  WRITE: JSON first → then DB (try/catch)
  READ:  if (USE_DB_*) { read DB } else { read JSON }
  41 feature flag (USE_DB_*=true) в pm2 env

ЕСЛИ ИЗМЕНИТЬ db.js:
> Все 41 модуль с DB потеряют доступ к данным
> МАКСИМАЛЬНЫЙ РИСК — равен base_http_service.dart

ЕСЛИ ИЗМЕНИТЬ db_schema.sql:
> Нужно применить миграцию на сервере
> Backup перед ALTER TABLE обязателен
```

### Хранилище данных (/var/www/) — 110+ директорий (backup/fallback)

```
/var/www/
│
├── AUTH & SESSIONS
│   ├── auth-otp/
│   ├── auth-pins/
│   └── auth-sessions/
│
├── EMPLOYEES
│   ├── employees/
│   ├── employee-registrations/
│   ├── employee-photos/
│   └── employee-ratings/
│
├── SHOPS
│   ├── shops/
│   ├── shop-settings/
│   ├── shop-settings-photos/
│   ├── shop-coordinates/
│   ├── shop-products/
│   └── shop-managers.json
│
├── SHIFTS
│   ├── shift-reports/
│   ├── shift-questions/
│   ├── shift-question-photos/
│   ├── shift-reference-photos/
│   ├── shift-photos/
│   ├── shift-transfers.json
│   ├── shift-automation-state/
│   ├── pending-shift-reports/
│   ├── shift-ai-annotations/
│   └── shift-ai-settings/
│
├── ATTENDANCE
│   ├── attendance/
│   ├── attendance-automation-state/
│   └── attendance-pending/
│
├── WORK SCHEDULE
│   ├── work-schedules/
│   └── work-schedule-templates/
│
├── SHIFT HANDOVER
│   ├── shift-handover-reports/
│   ├── shift-handover-questions/
│   ├── shift-handover-question-photos/
│   ├── shift-handover-automation-state/
│   ├── shift-handover-pending/
│   └── pending-shift-handover-reports.json
│
├── RECOUNT
│   ├── recount-reports/
│   ├── recount-questions/
│   ├── recount-question-photos/
│   ├── recount-points/
│   ├── recount-settings/
│   ├── recount-automation-state/
│   └── pending-recount-reports/
│
├── ENVELOPE
│   ├── envelope-reports/
│   ├── envelope-questions/
│   ├── envelope-question-photos/
│   ├── envelope-automation-state/
│   └── envelope-pending/
│
├── RKO
│   ├── rko-reports/
│   ├── rko-files/
│   ├── rko-uploads-temp/
│   ├── rko-pending/
│   └── rko-automation-state/
│
├── ORDERS & MENU
│   ├── orders/
│   ├── orders-viewed-rejected.json
│   ├── orders-viewed-unconfirmed.json
│   ├── menu/
│   └── recipes/ + recipe-photos/
│
├── CLIENTS & CHAT
│   ├── clients/
│   ├── client-dialogs/
│   ├── client-messages/
│   ├── client-messages-management/
│   ├── client-messages-network/
│   ├── employee-chats/
│   ├── chat-media/
│   └── network-messages/
│
├── EFFICIENCY & POINTS
│   ├── efficiency/
│   ├── efficiency-penalties/
│   └── points-settings/
│
├── TASKS
│   ├── tasks/
│   ├── task-assignments/
│   ├── task-media/
│   ├── task-points-config.json
│   ├── recurring-tasks/
│   └── recurring-task-instances/
│
├── TRAINING & TESTS
│   ├── training-articles/
│   ├── training-articles-media/
│   ├── test-questions/
│   ├── test-results/
│   └── test-settings.json
│
├── PRODUCT QUESTIONS
│   ├── product-questions/
│   ├── product-question-dialogs/
│   ├── product-question-photos/
│   └── product-question-penalty-state/
│
├── LOYALTY & BONUSES
│   ├── loyalty-gamification/
│   ├── loyalty-promo.json
│   ├── loyalty-transactions/
│   ├── bonus-penalties/
│   ├── fortune-wheel/
│   └── referrals-viewed.json
│
├── REVIEWS
│   └── reviews/
│
├── COFFEE MACHINE
│   ├── coffee-machine-reports/
│   ├── coffee-machine-templates/
│   ├── coffee-machine-shop-configs/
│   ├── coffee-machine-pending/
│   ├── coffee-machine-automation-state/
│   ├── coffee-machine-photos/
│   └── coffee-machine-training/
│
├── MAIN CASH
│   ├── withdrawals/
│   └── main_cash/
│
├── AI / VISION
│   ├── ai-recognition-stats/
│   ├── z-report-samples/
│   └── master-catalog/
│
├── OTHER
│   ├── job-applications/
│   ├── suppliers/
│   ├── execution-chain/
│   ├── geofence-notifications/
│   ├── geofence-settings.json
│   ├── fcm-tokens/
│   ├── report-notifications/
│   └── data/ + dbf-sync-settings/
│
└── SYSTEM
    ├── app-logs/
    ├── app-version.json
    ├── cache/
    └── html/ (статические файлы)
```

---

## 7. Общие модели данных

### Модели используемые несколькими модулями:

| Модель | Файл | Используется в |
|--------|-------|---------------|
| `Shop` | `shops/models/shop_model.dart` | shops, kpi, efficiency, rko, multitenancy |
| `ShopSettings` | `shops/models/shop_settings_model.dart` | shops, rko, recount |
| `EmployeeRegistration` | `employees/models/employee_registration_model.dart` | employees, rko |
| `UserRoleData` | `employees/models/user_role_model.dart` | employees, shops, все страницы с ролями |
| `ShiftReport` | `shifts/models/shift_report_model.dart` | shifts, kpi, efficiency, rko |
| `AttendanceRecord` | `attendance/models/attendance_model.dart` | attendance, kpi, efficiency |
| `RecountReport` | `recount/models/recount_report_model.dart` | recount, kpi, efficiency |
| `EnvelopeReport` | `envelope/models/envelope_report_model.dart` | envelope, kpi, efficiency |
| `UnifiedDialogMessage` | `shared/models/unified_dialog_message_model.dart` | clients, product_questions |

### Телефон как ключ (критически важно!):
Многие модули используют номер телефона как идентификатор.
**Нормализация телефона** — используй `core/utils/phone_normalizer.dart`
```
Вариант 1: phone.replaceAll(RegExp(r'[\s\+]'), '')   ← ПРАВИЛЬНЫЙ (большинство)
Вариант 2: phone.replaceAll(RegExp(r'[\s+]'), '')     ← НЕПРАВИЛЬНЫЙ (без \)
Вариант 3: phone.replace(/[^\d]/g, '')                ← БЭКЕНД (убирает всё кроме цифр)
```
Несовпадение нормализации = телефон не найден = функция не работает

---

## 8. Shared и App слои

### shared/ — Общие виджеты и модели (17 файлов)

```
shared/
├── dialogs/ (8 файлов)
│   ├── abbreviation_selection_dialog.dart
│   ├── auto_fill_schedule_dialog.dart
│   ├── notification_required_dialog.dart
│   ├── schedule_bulk_operations_dialog.dart
│   ├── schedule_errors_dialog.dart
│   ├── schedule_validation_dialog.dart
│   ├── send_message_dialog.dart
│   └── shift_edit_dialog.dart
├── models/ (1 файл)
│   └── unified_dialog_message_model.dart
├── providers/ (2 файла)
│   ├── cart_provider.dart
│   └── order_provider.dart
└── widgets/ (6 файлов)
    ├── app_cached_image.dart
    ├── delete_confirmation_dialog.dart
    ├── media_message_widget.dart
    ├── media_picker_button.dart
    ├── report_list_widgets.dart
    └── shop_selection_scaffold.dart
```

Используется в: work_schedule (dialogs), orders (providers), shifts/recount/envelope/rko (report_list, shop_selection), employee_chat/clients (media widgets)

### app/ — Навигация и общие страницы (10 файлов)

```
app/
├── services/ (3 файла)
│   ├── dashboard_batch_service.dart
│   ├── reports_counter_service.dart
│   └── my_dialogs_counter_service.dart
└── pages/ (7 файлов)
    ├── main_menu_page.dart (главное меню)
    ├── manager_grid_page.dart (сетка менеджера)
    ├── reports_page.dart (все отчёты)
    ├── my_dialogs_page.dart (мои диалоги)
    ├── client_functions_page.dart (клиентские функции)
    ├── data_management_page.dart (управление данными)
    └── role_test_page.dart (тестирование ролей)
```

Используется в: main.dart (точка входа), навигация между модулями

---

> **Как пользоваться этим файлом:**
> 1. Найди модуль который хочешь изменить
> 2. Посмотри раздел "От него зависят"
> 3. Посмотри "ЕСЛИ ИЗМЕНИТЬ"
> 4. Протестируй ВСЕ зависимые модули после изменения

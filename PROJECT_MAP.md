# PROJECT MAP — Карта зависимостей проекта Arabica

> **Цель этого файла**: показать КАК модули связаны друг с другом.
> Перед изменением любого файла — найди его в карте и проверь **"Если изменить"**.
> Дата создания: 2026-02-10

---

## 📋 СОДЕРЖАНИЕ

1. [Обзор архитектуры](#1-обзор-архитектуры)
2. [Ядро системы (Core)](#2-ядро-системы-core)
3. [Модули по категориям](#3-модули-по-категориям)
4. [Карта зависимостей каждого модуля](#4-карта-зависимостей-каждого-модуля)
5. [Матрица влияния изменений](#5-матрица-влияния-изменений)
6. [Бэкенд API зависимости](#6-бэкенд-api-зависимости)
7. [Общие модели данных](#7-общие-модели-данных)

---

## 1. Обзор архитектуры

```
Flutter App (lib/)                    Backend (loyalty-proxy/)
├── core/                             ├── index.js (главный роутер)
│   ├── constants/                    ├── api/ (56+ файлов)
│   ├── services/ (shared)            ├── modules/ (schedulers, OCR)
│   └── utils/                        └── /var/www/ (JSON хранилище)
├── features/ (35 модулей)
│   ├── auth/
│   ├── shifts/, attendance/, ...
│   └── coffee_machine/
├── shared/ (общие виджеты)
└── app/ (навигация, main)
```

**Ключевые числа:**
- 35 Flutter модулей
- 56+ API модулей бэкенда
- 240+ API эндпоинтов
- 8 автоматических планировщиков (schedulers)
- 6 ролей пользователей
- Файловое JSON-хранилище (без БД)

---

## 2. Ядро системы (Core)

### 2.1 BaseHttpService — ЦЕНТРАЛЬНЫЙ СЕРВИС
**Файл:** `lib/core/services/base_http_service.dart`

Все Flutter сервисы вызывают API через него. Это самый критичный файл.

**Методы:** getList, get, post, put, patch, delete, getRaw, postRaw, simplePost
**Добавляет к каждому запросу:** API key + session token

```
⚠️ ЕСЛИ ИЗМЕНИТЬ BaseHttpService:
→ Сломается ВСЁ приложение (все 35 модулей)
→ НИКОГДА не менять без полного тестирования
```

### 2.1b BaseReportService<T> — Базовый сервис отчётов
**Файл:** `lib/core/services/base_report_service.dart`

Generic класс для общих CRUD-операций отчётов. Используется через композицию (static `_base` instance).

**Методы:** getReports, getReportsForCurrentUser, getExpiredReports, getReport, deleteReport, confirmViaEndpoint, rejectViaEndpoint, sendStatusPush, buildQueryParams
**Зависит от:** BaseHttpService, MultitenancyFilterService, EmployeePushService

```
⚠️ ЕСЛИ ИЗМЕНИТЬ BaseReportService:
→ Затронет 5 сервисов: ShiftReport, ShiftHandoverReport, Recount, Envelope, CoffeeMachine
→ Public API этих сервисов НЕ меняется — вызывающие файлы не затронуты
```

### 2.2 ApiConstants — Все эндпоинты
**Файл:** `lib/core/constants/api_constants.dart`

Содержит URL сервера и 40+ констант эндпоинтов.

```
⚠️ ЕСЛИ ИЗМЕНИТЬ ApiConstants:
→ Все модули, использующие изменённый эндпоинт, перестанут работать
→ Проверь "Кто использует" в разделе 4
```

### 2.3 Другие Core сервисы

| Сервис | Файл | Кто использует | Если изменить |
|--------|-------|----------------|---------------|
| **NotificationService** | `core/services/notification_service.dart` | auth, shifts, attendance, recount, envelope, rko, tasks, shift_handover | Push-уведомления перестанут приходить |
| **MultitenancyFilterService** | `core/services/multitenancy_filter_service.dart` | kpi, efficiency, envelope, recount, shifts, rko, coffee_machine, shift_handover | Фильтрация по магазинам сломается — пользователи увидят чужие данные |
| **CacheManager** | `core/utils/cache_manager.dart` | employees, shops, kpi, efficiency, tasks, recurring_tasks | Данные будут грузиться заново каждый раз (медленно) |
| **Logger** | `core/utils/logger.dart` | ВСЕ модули | Только логирование — безопасно менять |
| **PhotoUploadService** | `core/services/photo_upload_service.dart` | recount, shift_handover, recipes, reviews | Загрузка фото в отчётах перестанет работать |
| **MediaUploadService** | `core/services/media_upload_service.dart` | employee_chat, clients | Отправка медиа в чатах сломается |
| **EmployeePushService** | `core/services/employee_push_service.dart` | envelope, recount, shifts, rko, tasks, shift_handover, coffee_machine | Push сотрудникам при подтверждении отчётов |

---

## 3. Модули по категориям

### 🔐 Авторизация и пользователи
| Модуль | Папка | Зависимости Core |
|--------|-------|-----------------|
| **auth** | `features/auth/` | BaseHttpService, ApiConstants, SharedPreferences |
| **employees** | `features/employees/` | BaseHttpService, ApiConstants, CacheManager, PhotoUploadService |
| **job_application** | `features/job_application/` | BaseHttpService, ApiConstants |

### 🏪 Магазины и настройки
| Модуль | Папка | Зависимости Core |
|--------|-------|-----------------|
| **shops** | `features/shops/` | BaseHttpService, ApiConstants, CacheManager, MultitenancyFilterService |

### ⏰ Смены и посещаемость
| Модуль | Папка | Зависимости Core |
|--------|-------|-----------------|
| **shifts** | `features/shifts/` | BaseHttpService, ApiConstants, PhotoUploadService, NotificationService, MultitenancyFilterService |
| **attendance** | `features/attendance/` | BaseHttpService, ApiConstants |
| **work_schedule** | `features/work_schedule/` | BaseHttpService, ApiConstants |
| **shift_handover** | `features/shift_handover/` | BaseHttpService, ApiConstants, PhotoUploadService, MultitenancyFilterService, EmployeePushService |

### 📦 Отчёты и инвентаризация
| Модуль | Папка | Зависимости Core |
|--------|-------|-----------------|
| **recount** | `features/recount/` | BaseHttpService, ApiConstants, PhotoUploadService, MultitenancyFilterService, EmployeePushService |
| **envelope** | `features/envelope/` | BaseHttpService, ApiConstants, MultitenancyFilterService, EmployeePushService |
| **rko** | `features/rko/` | BaseHttpService, ApiConstants, CacheManager, MultitenancyFilterService |

### 🛒 Заказы и меню
| Модуль | Папка | Зависимости Core |
|--------|-------|-----------------|
| **orders** | `features/orders/` | BaseHttpService, ApiConstants |
| **menu** | `features/menu/` | BaseHttpService, ApiConstants |
| **recipes** | `features/recipes/` | BaseHttpService, ApiConstants, PhotoUploadService |

### 📊 Аналитика и эффективность
| Модуль | Папка | Зависимости Core |
|--------|-------|-----------------|
| **kpi** | `features/kpi/` | BaseHttpService, ApiConstants, CacheManager, MultitenancyFilterService |
| **efficiency** | `features/efficiency/` | BaseHttpService, ApiConstants, CacheManager, MultitenancyFilterService |
| **rating** | `features/rating/` | BaseHttpService, ApiConstants |
| **main_cash** | `features/main_cash/` | BaseHttpService, ApiConstants |

### 🎓 Обучение и тесты
| Модуль | Папка | Зависимости Core |
|--------|-------|-----------------|
| **training** | `features/training/` | BaseHttpService, ApiConstants, PhotoUploadService |
| **tests** | `features/tests/` | BaseHttpService, ApiConstants, PhotoUploadService |
| **product_questions** | `features/product_questions/` | BaseHttpService, ApiConstants |
| **ai_training** | `features/ai_training/` | BaseHttpService, ApiConstants |

### 💬 Коммуникации
| Модуль | Папка | Зависимости Core |
|--------|-------|-----------------|
| **employee_chat** | `features/employee_chat/` | BaseHttpService, ApiConstants, MediaUploadService, WebSocket |
| **clients** | `features/clients/` | BaseHttpService, ApiConstants, MediaUploadService |
| **reviews** | `features/reviews/` | BaseHttpService, ApiConstants, PhotoUploadService |

### 🎁 Лояльность и бонусы
| Модуль | Папка | Зависимости Core |
|--------|-------|-----------------|
| **loyalty** | `features/loyalty/` | BaseHttpService, ApiConstants |
| **bonuses** | `features/bonuses/` | BaseHttpService, ApiConstants |
| **fortune_wheel** | `features/fortune_wheel/` | BaseHttpService, ApiConstants |
| **referrals** | `features/referrals/` | BaseHttpService, ApiConstants |

### 🔧 Утилиты и прочее
| Модуль | Папка | Зависимости Core |
|--------|-------|-----------------|
| **tasks** | `features/tasks/` | BaseHttpService, ApiConstants, CacheManager |
| **data_cleanup** | `features/data_cleanup/` | BaseHttpService, ApiConstants |
| **coffee_machine** | `features/coffee_machine/` | BaseHttpService, ApiConstants, MultitenancyFilterService, EmployeePushService |
| **suppliers** | `features/suppliers/` | BaseHttpService, ApiConstants |
| **network_management** | `features/network_management/` | BaseHttpService, ApiConstants |
| **execution_chain** | `features/execution_chain/` | BaseHttpService, ApiConstants |

---

## 4. Карта зависимостей каждого модуля

### 🔐 AUTH (Авторизация)

```
Файлы Flutter:
├── services/auth_service.dart
├── services/biometric_service.dart
├── pages/login_page.dart
├── pages/registration_page.dart
└── pages/pin_page.dart

API эндпоинты:
├── POST /api/auth/login
├── POST /api/auth/register
├── POST /api/auth/register-simple
├── POST /api/auth/verify-otp
├── POST /api/auth/refresh-session ⚠️ НЕ СУЩЕСТВУЕТ НА БЭКЕНДЕ
├── POST /api/auth/change-pin ⚠️ ТОЛЬКО ЛОКАЛЬНО
└── GET  /api/auth/check-session

Бэкенд файлы:
└── loyalty-proxy/api/auth_api.js

Зависит от: BaseHttpService, SharedPreferences, FirebaseMessaging
От него зависят: ВСЕ модули (session token)

⚠️ ЕСЛИ ИЗМЕНИТЬ AUTH:
→ Все пользователи будут разлогинены
→ Невозможен вход в приложение
→ МАКСИМАЛЬНЫЙ РИСК
```

### 👥 EMPLOYEES (Сотрудники)

```
Файлы Flutter:
├── services/employee_service.dart (основной, кэш 30 сек)
├── services/employee_registration_service.dart
├── services/user_role_service.dart (определение роли)
├── models/employee_model.dart
├── models/employee_registration_model.dart
├── models/user_role_model.dart
├── pages/employees_page.dart
└── pages/unverified_employees_page.dart

API эндпоинты:
├── GET    /api/employees
├── GET    /api/employees/:id
├── POST   /api/employees
├── PUT    /api/employees/:id
├── DELETE /api/employees/:id
├── GET    /api/employee-registrations
├── GET    /api/employee-registration/:phone
├── POST   /api/employee-registration
├── POST   /api/employee-registration/:phone/verify
├── POST   /upload-employee-photo
└── GET    /api/shop-managers/role/:phone (кэш 5 мин)

Бэкенд файлы:
├── loyalty-proxy/api/employees_api.js
├── loyalty-proxy/api/employee_registration_api.js
└── loyalty-proxy/api/shop_managers_api.js

Зависит от: BaseHttpService, CacheManager, PhotoUploadService, SharedPreferences
От него зависят: kpi, efficiency, shifts, rko, envelope, recount, clients, tasks, shops

⚠️ ЕСЛИ ИЗМЕНИТЬ EMPLOYEES:
→ KPI перестанет загружать данные сотрудников
→ Efficiency не сможет рассчитать баллы
→ Роли и права доступа сломаются
→ 8+ модулей затронуты
```

### 🏪 SHOPS (Магазины)

```
Файлы Flutter:
├── models/shop_model.dart
├── models/shop_settings_model.dart
├── services/shop_service.dart
├── pages/shops_management_page.dart
└── pages/shops_on_map_page.dart

API эндпоинты:
├── GET    /api/shops
├── GET    /api/shops/:id
├── POST   /api/shops
├── PUT    /api/shops/:id
├── DELETE /api/shops/:id
├── GET    /api/shop-settings/:shopAddress
└── POST   /api/shop-settings

Бэкенд файлы:
├── loyalty-proxy/api/shops_api.js
└── loyalty-proxy/api/shop_settings_api.js

Зависит от: BaseHttpService, CacheManager, UserRoleService
От него зависят: kpi, efficiency, rko, MultitenancyFilterService, все модули с фильтрацией по магазину

⚠️ ЕСЛИ ИЗМЕНИТЬ SHOPS:
→ Фильтрация по магазинам во ВСЕХ модулях сломается
→ Дашборд перестанет показывать данные
→ 10+ модулей затронуты
```

### ⏰ SHIFTS (Пересменки)

```
Файлы Flutter:
├── services/shift_report_service.dart
├── services/shift_question_service.dart
├── models/shift_report_model.dart
├── models/shift_question_model.dart
├── pages/shift_report_page.dart
├── pages/shift_reports_management_page.dart
└── pages/shift_questions_management_page.dart

API эндпоинты:
├── GET    /api/shift-reports
├── GET    /api/shift-reports/:id
├── POST   /api/shift-reports
├── PUT    /api/shift-reports/:id
├── DELETE /api/shift-reports/:id
├── GET    /api/shift-questions
├── POST   /api/shift-questions
├── PUT    /api/shift-questions/:id
└── DELETE /api/shift-questions/:id

Бэкенд файлы:
├── loyalty-proxy/api/shift_reports_api.js
├── loyalty-proxy/api/shift_questions_api.js
└── loyalty-proxy/modules/shift-automation.js (scheduler каждые 5 мин)

Зависит от: BaseHttpService, PhotoUploadService, MultitenancyFilterService, NotificationService
От него зависят: kpi (ShiftReportService), efficiency (shift отчёты), rko (getLastShift)

⚠️ ЕСЛИ ИЗМЕНИТЬ SHIFTS:
→ KPI перестанет считать пересменки
→ Efficiency баллы за смены сломаются
→ RKO не получит данные последней смены
→ Автоматические уведомления о пересменках перестанут приходить
```

### 📅 ATTENDANCE (Посещаемость)

```
Файлы Flutter:
├── services/attendance_service.dart
├── models/attendance_model.dart
└── pages/attendance_page.dart

API эндпоинты:
├── GET    /api/attendance
├── POST   /api/attendance
├── PUT    /api/attendance/:id
└── DELETE /api/attendance/:id

Бэкенд файлы:
├── loyalty-proxy/api/attendance_api.js
└── loyalty-proxy/modules/attendance-automation.js (scheduler каждые 5 мин)

Зависит от: BaseHttpService
От него зависят: kpi, efficiency (посещаемость + опоздания)

⚠️ ЕСЛИ ИЗМЕНИТЬ ATTENDANCE:
→ KPI не покажет посещаемость
→ Efficiency потеряет категорию "Посещаемость"
→ Автоматическая посещаемость перестанет работать
```

### 📆 WORK_SCHEDULE (Рабочий график)

```
Файлы Flutter:
├── services/work_schedule_service.dart
├── models/work_schedule_model.dart
└── pages/my_schedule_page.dart

API эндпоинты:
├── GET    /api/work-schedule
├── POST   /api/work-schedule
├── PUT    /api/work-schedule/:id
└── DELETE /api/work-schedule/:id

Бэкенд файлы:
└── loyalty-proxy/api/work_schedule_api.js

Зависит от: BaseHttpService
От него зависят: kpi (интеграция с графиком для опозданий), attendance (автоматическая проверка)

⚠️ ЕСЛИ ИЗМЕНИТЬ WORK_SCHEDULE:
→ KPI неправильно посчитает опоздания (нужен график для сравнения)
→ Автоматическая посещаемость сломается
```

### 🔄 SHIFT_HANDOVER (Передача смены)

```
Файлы Flutter:
├── services/shift_handover_service.dart
├── services/shift_handover_question_service.dart
├── models/shift_handover_report_model.dart
├── models/shift_handover_question_model.dart
└── pages/shift_handover_page.dart

API эндпоинты:
├── GET    /api/shift-handover-reports
├── GET    /api/shift-handover-reports/:id
├── POST   /api/shift-handover-reports
├── PUT    /api/shift-handover-reports/:id/confirm
├── DELETE /api/shift-handover-reports/:id
├── GET    /api/shift-handover-questions
├── POST   /api/shift-handover-questions
├── PUT    /api/shift-handover-questions/:id
└── DELETE /api/shift-handover-questions/:id

Бэкенд файлы:
├── loyalty-proxy/api/shift_handover_reports_api.js
├── loyalty-proxy/api/shift_handover_questions_api.js
└── loyalty-proxy/modules/shift-handover-automation.js (scheduler)

Зависит от: BaseHttpService, PhotoUploadService, MultitenancyFilterService, EmployeePushService
От него зависят: kpi, efficiency (handover отчёты)

⚠️ ЕСЛИ ИЗМЕНИТЬ SHIFT_HANDOVER:
→ KPI потеряет данные передач смен
→ Efficiency баллы за передачу смены сломаются
```

### 📦 RECOUNT (Пересчёт товаров)

```
Файлы Flutter:
├── services/recount_service.dart (web + mobile)
├── services/recount_question_service.dart
├── services/recount_points_service.dart
├── models/recount_report_model.dart
├── models/recount_answer_model.dart
├── models/recount_pivot_model.dart
├── pages/recount_page.dart
├── pages/recount_management_tabs_page.dart
└── pages/recount_points_settings_page.dart

API эндпоинты:
├── GET    /api/recount-reports
├── GET    /api/recount-reports/:id
├── POST   /api/recount-reports
├── PUT    /api/recount-reports/:id/confirm
├── DELETE /api/recount-reports/:id
├── GET    /api/recount-questions
├── POST   /api/recount-questions
├── PUT    /api/recount-questions/:id
├── DELETE /api/recount-questions/:id
├── GET    /api/recount-points/:phone
└── POST   /api/recount-points/:phone

Бэкенд файлы:
├── loyalty-proxy/api/recount_reports_api.js
├── loyalty-proxy/api/recount_questions_api.js
├── loyalty-proxy/api/recount_points_api.js
└── loyalty-proxy/modules/recount-automation.js (scheduler)

Зависит от: BaseHttpService, PhotoUploadService, MultitenancyFilterService, EmployeePushService
От него зависят: kpi, efficiency (recount отчёты и баллы)

⚠️ ЕСЛИ ИЗМЕНИТЬ RECOUNT:
→ KPI потеряет данные пересчётов
→ Efficiency баллы за пересчёт сломаются
→ Баллы сотрудников не будут начисляться
```

### ✉️ ENVELOPE (Конверты)

```
Файлы Flutter:
├── services/envelope_report_service.dart
├── services/envelope_question_service.dart
├── models/envelope_report_model.dart
├── models/pending_envelope_report_model.dart
├── pages/envelope_page.dart
└── pages/envelope_management_page.dart

API эндпоинты:
├── GET    /api/envelope-reports
├── GET    /api/envelope-reports/:id
├── POST   /api/envelope-reports
├── PUT    /api/envelope-reports/:id
├── DELETE /api/envelope-reports/:id
├── GET    /api/envelope-questions
├── POST   /api/envelope-questions
├── PUT    /api/envelope-questions/:id
└── DELETE /api/envelope-questions/:id

Бэкенд файлы:
├── loyalty-proxy/api/envelope_reports_api.js
├── loyalty-proxy/api/envelope_questions_api.js
└── loyalty-proxy/modules/envelope-automation.js (scheduler)

Зависит от: BaseHttpService, MultitenancyFilterService, EmployeePushService
От него зависят: kpi, efficiency (envelope отчёты)

⚠️ ЕСЛИ ИЗМЕНИТЬ ENVELOPE:
→ KPI потеряет данные конвертов
→ Efficiency баллы за конверты сломаются
```

### 💰 RKO (Расходно-кассовые ордера)

```
Файлы Flutter:
├── services/rko_service.dart
├── services/rko_reports_service.dart
├── models/rko_report_model.dart
├── pages/rko_type_selection_page.dart
├── pages/rko_amount_input_page.dart
└── pages/rko_reports_page.dart

API эндпоинты:
├── GET    /api/rko
├── POST   /api/rko
├── GET    /api/rko/employee/:name
├── GET    /api/rko/shop/:address
└── DELETE /api/rko/:id

Бэкенд файлы:
├── loyalty-proxy/api/rko_api.js
└── loyalty-proxy/modules/rko-automation.js (scheduler)

Зависит от: BaseHttpService, CacheManager, ShopSettings, EmployeeRegistrationService, ShiftReport
От него зависят: kpi, efficiency (RKO данные)

⚠️ ЕСЛИ ИЗМЕНИТЬ RKO:
→ KPI потеряет финансовые данные
→ Efficiency баллы за РКО сломаются
→ Нумерация документов может сбиться
```

### 🛒 ORDERS (Заказы)

```
Файлы Flutter:
├── services/order_service.dart
├── models/order_model.dart
├── pages/orders_page.dart
└── pages/cart_page.dart

API эндпоинты:
├── GET    /api/orders
├── GET    /api/orders/:id
├── POST   /api/orders
├── PUT    /api/orders/:id
├── DELETE /api/orders/:id
└── PUT    /api/orders/:id/status

Бэкенд файлы:
└── loyalty-proxy/api/orders_api.js

Зависит от: BaseHttpService, BonusService (списание бонусов)
От него зависят: efficiency (категория заказы), loyalty (бонусы от заказов)

⚠️ ЕСЛИ ИЗМЕНИТЬ ORDERS:
→ Efficiency потеряет категорию "Заказы"
→ Бонусы при заказе перестанут начисляться
```

### 📋 MENU (Меню)

```
Файлы Flutter:
├── services/menu_service.dart
├── models/menu_item_model.dart
└── pages/menu_page.dart

API эндпоинты:
├── GET    /api/menu
├── POST   /api/menu
├── PUT    /api/menu/:id
└── DELETE /api/menu/:id

Бэкенд файлы:
└── loyalty-proxy/api/menu_api.js

Зависит от: BaseHttpService
От него зависят: orders (список товаров для заказа)

⚠️ ЕСЛИ ИЗМЕНИТЬ MENU:
→ Заказы потеряют список товаров
→ Корзина может не работать
```

### 🍳 RECIPES (Рецепты)

```
Файлы Flutter:
├── services/recipe_service.dart
├── models/recipe_model.dart
├── pages/recipes_page.dart
└── pages/recipe_form_page.dart

API эндпоинты:
├── GET    /api/recipes
├── GET    /api/recipes/:id
├── POST   /api/recipes
├── PUT    /api/recipes/:id
└── DELETE /api/recipes/:id

Бэкенд файлы:
└── loyalty-proxy/api/recipes_api.js

Зависит от: BaseHttpService, PhotoUploadService
От него зависят: (изолированный модуль)

⚠️ ЕСЛИ ИЗМЕНИТЬ RECIPES:
→ Только рецепты перестанут работать (низкий риск)
```

### 📊 KPI (Ключевые показатели)

```
Файлы Flutter:
├── services/kpi_service.dart (агрегирует 6+ источников)
├── services/kpi_aggregation_service.dart
├── services/kpi_cache_service.dart
├── services/kpi_persistence_service.dart (SharedPreferences fallback для offline)
├── services/kpi_schedule_integration_service.dart
├── services/kpi_filters.dart
└── pages/kpi_page.dart

API эндпоинты (вызывает чужие):
├── GET /api/attendance
├── GET /api/shift-reports
├── GET /api/recount-reports
├── GET /api/rko/employee/:name
├── GET /api/rko/shop/:address
├── GET /api/envelope-reports
├── GET /api/shift-handover-reports
├── GET /api/work-schedule
├── GET /api/employees
└── GET /api/shops

Бэкенд файлы: НЕТ (только агрегация на клиенте)

Зависит от: attendance, shifts, recount, rko, envelope, shift_handover, work_schedule, employees, shops
От него зависят: (конечный потребитель)

⚠️ ЕСЛИ ИЗМЕНИТЬ KPI:
→ Только KPI страница сломается (но она критична для менеджеров)
→ ЗАТО если изменить ЛЮБОЙ из 9 модулей выше — KPI тоже сломается!
```

### 📈 EFFICIENCY (Эффективность)

```
Файлы Flutter:
├── services/efficiency_data_service.dart (batch загрузка)
├── services/efficiency_calculation_service.dart
├── services/manager_efficiency_service.dart
├── services/points_settings_service.dart
├── models/efficiency_record_model.dart
├── models/efficiency_penalty_model.dart
└── pages/my_efficiency_page.dart

API эндпоинты:
├── GET  /api/efficiency/reports-batch?month=YYYY-MM (batch)
├── GET  /api/efficiency-penalties
├── POST /api/efficiency-penalties
├── GET  /api/points-settings
├── POST /api/points-settings
├── GET  /api/manager-efficiency?phone=&month=
└── Индивидуальные: /api/shift-reports, /api/recount-reports, /api/attendance и т.д.

Бэкенд файлы:
├── loyalty-proxy/api/efficiency_api.js (batch + penalties)
├── loyalty-proxy/api/points_settings_api.js
└── loyalty-proxy/api/manager_efficiency_api.js

Зависит от: shifts, recount, shift_handover, attendance, tasks, reviews, product_questions, orders, rko, envelope
10 категорий данных! Самый "зависимый" модуль.

От него зависят: (конечный потребитель, но критичный для зарплат)

⚠️ ЕСЛИ ИЗМЕНИТЬ EFFICIENCY:
→ Баллы эффективности перестанут считаться
→ Зарплатные расчёты будут неверными
→ НО: изменение ЛЮБОГО из 10 источников сломает efficiency!
```

### ⭐ RATING (Рейтинг сотрудников)

```
Файлы Flutter:
├── services/rating_service.dart
└── pages/rating_page.dart

API эндпоинты:
├── GET /api/rating
└── GET /api/rating/calculate

Бэкенд файлы:
└── loyalty-proxy/api/rating_wheel_api.js

Зависит от: BaseHttpService
От него зависят: fortune_wheel (рейтинг = кол-во спинов)

⚠️ ЕСЛИ ИЗМЕНИТЬ RATING:
→ Рейтинг и колесо фортуны перестанут работать
```

### 🎡 FORTUNE_WHEEL (Колесо фортуны)

```
Файлы Flutter:
├── services/fortune_wheel_service.dart
└── pages/fortune_wheel_page.dart

API эндпоинты:
├── GET  /api/rating-wheel/spins
├── POST /api/rating-wheel/spin
└── GET  /api/rating-wheel/prizes

Бэкенд файлы:
└── loyalty-proxy/api/rating_wheel_api.js (тот же файл что rating)

Зависит от: BaseHttpService, rating (количество спинов)
От него зависят: (изолированный модуль)
```

### 🎓 TRAINING (Обучение)

```
Файлы Flutter:
├── services/training_article_service.dart
├── models/training_article_model.dart
├── pages/training_articles_management_page.dart
└── pages/training_article_editor_page.dart

API эндпоинты:
├── GET    /api/training-articles
├── GET    /api/training-articles/:id
├── POST   /api/training-articles
├── PUT    /api/training-articles/:id
└── DELETE /api/training-articles/:id

Бэкенд файлы:
└── loyalty-proxy/api/training_articles_api.js

Зависит от: BaseHttpService, PhotoUploadService
От него зависят: (изолированный модуль)
```

### 📝 TESTS (Тесты для сотрудников)

```
Файлы Flutter:
├── services/test_service.dart
├── services/test_question_service.dart
├── models/test_model.dart
├── models/test_question_model.dart
├── pages/test_page.dart
├── pages/test_questions_management_page.dart
└── pages/test_notifications_page.dart

API эндпоинты:
├── GET    /api/tests
├── GET    /api/tests/:id
├── POST   /api/tests
├── GET    /api/test-questions
├── POST   /api/test-questions
├── PUT    /api/test-questions/:id
├── DELETE /api/test-questions/:id
├── POST   /api/test-notifications
└── GET    /api/test-notifications

Бэкенд файлы:
├── loyalty-proxy/api/tests_api.js
└── loyalty-proxy/api/test_questions_api.js

Зависит от: BaseHttpService, PhotoUploadService
От него зависят: (изолированный модуль)
```

### 🔍 PRODUCT_QUESTIONS (Вопросы по товарам)

```
Файлы Flutter:
├── services/product_question_service.dart
├── models/product_question_model.dart
└── pages/product_search_page.dart

API эндпоинты:
├── GET    /api/product-questions
├── POST   /api/product-questions
├── PUT    /api/product-questions/:id
└── DELETE /api/product-questions/:id

Бэкенд файлы:
├── loyalty-proxy/api/product_questions_api.js
└── loyalty-proxy/modules/product-questions-automation.js (scheduler)

Зависит от: BaseHttpService
От него зависят: efficiency (категория product_search)

⚠️ ЕСЛИ ИЗМЕНИТЬ PRODUCT_QUESTIONS:
→ Efficiency потеряет категорию "Поиск товаров"
```

### 💬 EMPLOYEE_CHAT (Чат сотрудников)

```
Файлы Flutter:
├── services/employee_chat_service.dart (HTTP + WebSocket)
├── models/employee_chat_model.dart
├── pages/employee_chat_page.dart
└── pages/create_group_page.dart

API эндпоинты:
├── GET    /api/employee-chat/chats
├── GET    /api/employee-chat/chats/:id
├── POST   /api/employee-chat/chats
├── POST   /api/employee-chat/chats/:id/messages
├── POST   /api/employee-chat/chats/:id/read
├── DELETE /api/employee-chat/chats/:id
└── WS     /ws (WebSocket для реального времени)

Бэкенд файлы:
├── loyalty-proxy/api/employee_chat_api.js
└── loyalty-proxy/modules/websocket.js

Зависит от: BaseHttpService, MediaUploadService, WebSocket
От него зависят: (изолированный модуль)

⚠️ ЕСЛИ ИЗМЕНИТЬ EMPLOYEE_CHAT:
→ WebSocket может разорваться — сообщения не будут приходить в реальном времени
```

### 👥 CLIENTS (Клиенты / CRM)

```
Файлы Flutter:
├── services/client_service.dart
├── services/client_dialog_service.dart
├── models/client_model.dart
├── models/client_message_model.dart
├── pages/clients_management_page.dart
├── pages/client_chat_page.dart
└── pages/management_dialog_page.dart

API эндпоинты:
├── GET    /api/clients
├── GET    /api/clients/:phone/messages
├── POST   /api/clients/:phone/messages
├── POST   /api/clients/messages/broadcast
├── POST   /api/client-dialogs/:phone/network/read-by-admin
├── GET    /api/client-dialogs
└── GET    /api/my-dialogs-counter

Бэкенд файлы:
├── loyalty-proxy/api/clients_api.js
└── loyalty-proxy/api/client_dialogs_api.js

Зависит от: BaseHttpService, MediaUploadService
От него зависят: (изолированный от других модулей)
```

### 🎁 LOYALTY (Лояльность / Геймификация)

```
Файлы Flutter:
├── services/loyalty_gamification_service.dart
└── pages/loyalty_page.dart

API эндпоинты:
├── GET    /api/loyalty-program
├── POST   /api/loyalty-program/action
├── GET    /api/loyalty-program/history
└── GET    /api/loyalty-program/leaderboard

Бэкенд файлы:
└── loyalty-proxy/api/loyalty_gamification_api.js

Зависит от: BaseHttpService
От него зависят: bonuses (бонусная система связана)
```

### 💎 BONUSES (Бонусы)

```
Файлы Flutter:
├── services/bonus_service.dart
└── pages/bonuses_page.dart

API эндпоинты:
├── GET  /api/bonuses/:phone
├── POST /api/bonuses/add
├── POST /api/bonuses/spend
└── GET  /api/bonuses/history/:phone

Бэкенд файлы:
└── loyalty-proxy/api/bonuses_api.js

Зависит от: BaseHttpService
От него зависят: orders (списание бонусов при заказе)
```

### 🔗 REFERRALS (Реферальная система)

```
Файлы Flutter:
├── services/referral_service.dart
└── pages/referral_page.dart

API эндпоинты:
├── GET  /api/referrals/:phone
├── POST /api/referrals
└── GET  /api/referrals/stats

Бэкенд файлы:
└── loyalty-proxy/api/referrals_api.js

Зависит от: BaseHttpService
От него зависят: (изолированный)
```

### ⭐ REVIEWS (Отзывы)

```
Файлы Flutter:
├── services/review_service.dart
├── models/review_model.dart
└── pages/review_shop_selection_page.dart

API эндпоинты:
├── GET    /api/reviews
├── POST   /api/reviews
├── PUT    /api/reviews/:id
└── DELETE /api/reviews/:id

Бэкенд файлы:
└── loyalty-proxy/api/reviews_api.js

Зависит от: BaseHttpService, PhotoUploadService
От него зависят: efficiency (категория reviews)

⚠️ ЕСЛИ ИЗМЕНИТЬ REVIEWS:
→ Efficiency потеряет категорию "Отзывы"
```

### 📌 TASKS (Задачи)

```
Файлы Flutter:
├── services/task_service.dart
├── services/recurring_task_service.dart
├── models/task_model.dart
├── pages/my_tasks_page.dart
└── pages/task_management_page.dart

API эндпоинты:
├── GET    /api/tasks
├── GET    /api/tasks/:id
├── POST   /api/tasks
├── PUT    /api/tasks/:id
├── DELETE /api/tasks/:id
├── GET    /api/task-assignments
├── POST   /api/task-assignments/:id/respond
├── POST   /api/task-assignments/:id/review
├── GET    /api/recurring-tasks
├── POST   /api/recurring-tasks
├── PUT    /api/recurring-tasks/:id
└── DELETE /api/recurring-tasks/:id

Бэкенд файлы:
├── loyalty-proxy/api/tasks_api.js
└── loyalty-proxy/api/recurring_tasks_api.js

Зависит от: BaseHttpService, CacheManager
От него зависят: efficiency (категория tasks)

⚠️ ЕСЛИ ИЗМЕНИТЬ TASKS:
→ Efficiency потеряет категорию "Задачи"
```

### ☕ COFFEE_MACHINE (Кофемашины)

```
Файлы Flutter:
├── services/coffee_machine_report_service.dart
├── services/coffee_machine_template_service.dart
├── services/coffee_machine_config_service.dart
├── models/coffee_machine_report_model.dart
├── models/pending_coffee_machine_report_model.dart
├── pages/coffee_machine_page.dart
└── pages/coffee_machine_management_page.dart

API эндпоинты:
├── GET    /api/coffee-machine/reports
├── GET    /api/coffee-machine/reports/:id
├── POST   /api/coffee-machine/reports
├── PUT    /api/coffee-machine/reports/:id/confirm
├── DELETE /api/coffee-machine/reports/:id
├── GET    /api/coffee-machine/templates
├── POST   /api/coffee-machine/templates
├── GET    /api/coffee-machine/shop-config/:shopAddress
├── POST   /api/coffee-machine/shop-config
├── POST   /api/coffee-machine/ocr (OCR распознавание)
└── GET    /api/coffee-machine/pending

Бэкенд файлы:
├── loyalty-proxy/api/coffee_machine_api.js
├── loyalty-proxy/modules/counter-ocr.js (OCR модуль)
├── loyalty-proxy/modules/ocr_server.py (EasyOCR сервер)
└── loyalty-proxy/modules/coffee-machine-automation.js (scheduler)

Зависит от: BaseHttpService, MultitenancyFilterService, EmployeePushService
От него зависят: (изолированный модуль)
```

### 🤖 AI_TRAINING (ИИ обучение)

```
Файлы Flutter:
├── services/ai_training_service.dart
└── pages/ai_training_page.dart

API эндпоинты:
├── POST /api/ai-training/ask
└── GET  /api/ai-training/history

Бэкенд файлы:
└── loyalty-proxy/api/ai_training_api.js

Зависит от: BaseHttpService
От него зависят: (изолированный)
```

### 💼 JOB_APPLICATION (Заявки на работу)

```
Файлы Flutter:
├── pages/job_application_welcome_page.dart
├── pages/job_application_form_page.dart
└── pages/job_application_detail_page.dart

API эндпоинты:
├── GET  /api/job-applications
├── POST /api/job-applications
└── PUT  /api/job-applications/:id

Бэкенд файлы:
└── loyalty-proxy/api/job_applications_api.js

Зависит от: BaseHttpService
От него зависят: (изолированный)
```

### 🧹 DATA_CLEANUP (Очистка данных)

```
Файлы Flutter:
├── services/data_cleanup_service.dart
└── pages/data_cleanup_page.dart

API эндпоинты:
├── GET    /api/data-cleanup/stats
├── POST   /api/data-cleanup/cleanup
└── DELETE /api/data-cleanup/:type

Бэкенд файлы:
└── loyalty-proxy/api/data_cleanup_api.js

⚠️ ЕСЛИ ИЗМЕНИТЬ DATA_CLEANUP:
→ Может случайно удалить данные других модулей!
→ ВСЕГДА проверять что именно удаляется
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

### Высокий риск (сломает 5-10 модулей):
| Файл | Влияние |
|------|---------|
| `base_report_service.dart` | shifts, shift_handover, recount, envelope, coffee_machine |
| `multitenancy_filter_service.dart` | kpi, efficiency, envelope, recount, shifts, rko, coffee_machine, shift_handover |
| `employee_service.dart` | kpi, efficiency, shifts, rko, clients, tasks |
| `shop_service.dart` / `shop_model.dart` | kpi, efficiency, rko, multitenancy фильтрация |
| `user_role_service.dart` | Все страницы с ролевым доступом |
| `notification_service.dart` | 8+ модулей с push |

### Средний риск (сломает 2-4 модуля):
| Файл | Влияние |
|------|---------|
| `shift_report_service.dart` | kpi, efficiency, rko |
| `attendance_service.dart` | kpi, efficiency |
| `recount_service.dart` | kpi, efficiency |
| `envelope_report_service.dart` | kpi, efficiency |
| `photo_upload_service.dart` | recount, shift_handover, recipes, reviews, tests, training |
| `media_upload_service.dart` | employee_chat, clients |

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

---

## 6. Бэкенд API зависимости

### index.js — Главный роутер
```
Подключает 56+ API модулей через require() и app.use()
⚠️ Если добавить/убрать require — весь сервер может не запуститься
```

### Планировщики (Schedulers) — работают каждые 5 минут
| Scheduler | Файл | Что делает |
|-----------|-------|-----------|
| attendance-automation | `modules/attendance-automation.js` | Автопосещаемость по GPS |
| shift-automation | `modules/shift-automation.js` | Напоминания о пересменке |
| recount-automation | `modules/recount-automation.js` | Напоминания о пересчёте |
| envelope-automation | `modules/envelope-automation.js` | Напоминания о конвертах |
| rko-automation | `modules/rko-automation.js` | Автоматические РКО |
| shift-handover-automation | `modules/shift-handover-automation.js` | Напоминания о передаче |
| coffee-machine-automation | `modules/coffee-machine-automation.js` | Напоминания о кофемашинах |
| product-questions-automation | `modules/product-questions-automation.js` | Автоназначение вопросов |

### Хранилище данных (/var/www/)
```
/var/www/
├── employees/              ← employees_api.js
├── employee-registrations/ ← employee_registration_api.js
├── shops/                  ← shops_api.js
├── shop-settings/          ← shop_settings_api.js
├── shift-reports/          ← shift_reports_api.js
├── shift-questions/        ← shift_questions_api.js
├── attendance/             ← attendance_api.js
├── work-schedule/          ← work_schedule_api.js
├── recount-reports/        ← recount_reports_api.js
├── recount-questions/      ← recount_questions_api.js
├── recount-points/         ← recount_points_api.js
├── envelope-reports/       ← envelope_reports_api.js
├── envelope-questions/     ← envelope_questions_api.js
├── rko/                    ← rko_api.js
├── orders/                 ← orders_api.js
├── menu/                   ← menu_api.js
├── recipes/                ← recipes_api.js
├── reviews/                ← reviews_api.js
├── clients/                ← clients_api.js
├── client-dialogs/         ← client_dialogs_api.js
├── training-articles/      ← training_articles_api.js
├── test-questions/         ← test_questions_api.js
├── tests/                  ← tests_api.js
├── product-questions/      ← product_questions_api.js
├── tasks/                  ← tasks_api.js
├── task-assignments/       ← tasks_api.js
├── recurring-tasks/        ← recurring_tasks_api.js
├── bonuses/                ← bonuses_api.js
├── loyalty-program/        ← loyalty_gamification_api.js
├── referrals/              ← referrals_api.js
├── rating/                 ← rating_wheel_api.js
├── efficiency-penalties/   ← efficiency_api.js
├── points-settings/        ← points_settings_api.js
├── coffee-machine-templates/    ← coffee_machine_api.js
├── coffee-machine-shop-configs/ ← coffee_machine_api.js
├── coffee-machine-reports/      ← coffee_machine_api.js
├── coffee-machine-pending/      ← coffee_machine_api.js
├── coffee-machine-automation-state/ ← coffee-machine-automation.js
├── job-applications/       ← job_applications_api.js
├── shift-handover-reports/ ← shift_handover_reports_api.js
├── shift-handover-questions/ ← shift_handover_questions_api.js
├── shop-managers/          ← shop_managers_api.js
├── data-cleanup/           ← data_cleanup_api.js
└── uploads/                ← фото/медиа файлы
```

---

## 7. Общие модели данных

### Модели используемые несколькими модулями:

| Модель | Файл | Используется в |
|--------|-------|---------------|
| `Shop` | `shops/models/shop_model.dart` | shops, kpi, efficiency, rko, multitenancy |
| `ShopSettings` | `shops/models/shop_settings_model.dart` | shops, rko, recount |
| `Employee` | `employees/models/employee_model.dart` | employees, kpi, efficiency, shifts |
| `EmployeeRegistration` | `employees/models/employee_registration_model.dart` | employees, rko |
| `UserRoleData` | `employees/models/user_role_model.dart` | employees, shops, все страницы с ролями |
| `ShiftReport` | `shifts/models/shift_report_model.dart` | shifts, kpi, efficiency, rko |
| `AttendanceRecord` | `attendance/models/attendance_model.dart` | attendance, kpi, efficiency |
| `RecountReport` | `recount/models/recount_report_model.dart` | recount, kpi, efficiency |
| `EnvelopeReport` | `envelope/models/envelope_report_model.dart` | envelope, kpi, efficiency |

### Телефон как ключ (критически важно!):
Многие модули используют номер телефона как идентификатор.
**Нормализация телефона** происходит в 20+ местах разными регулярками!
```
Вариант 1: phone.replaceAll(RegExp(r'[\s\+]'), '')   ← ПРАВИЛЬНЫЙ (большинство)
Вариант 2: phone.replaceAll(RegExp(r'[\s+]'), '')     ← НЕПРАВИЛЬНЫЙ (без \)
Вариант 3: phone.replace(/[^\d]/g, '')                ← БЭКЕНД (убирает всё кроме цифр)
```
⚠️ Несовпадение нормализации = телефон не найден = функция не работает

---

> **Как пользоваться этим файлом:**
> 1. Найди модуль который хочешь изменить
> 2. Посмотри раздел "От него зависят"
> 3. Посмотри "⚠️ ЕСЛИ ИЗМЕНИТЬ"
> 4. Протестируй ВСЕ зависимые модули после изменения

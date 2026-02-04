# Arabica 2026 - Полная Архитектура Приложения

**Дата создания:** 2026-02-04
**Версия:** 1.0
**Статус:** Полный технический аудит перед внедрением мультитенантности

---

## Содержание

1. [Обзор проекта](#1-обзор-проекта)
2. [Структура каталогов](#2-структура-каталогов)
3. [Flutter модули (lib/features)](#3-flutter-модули-libfeatures)
4. [Серверный код (loyalty-proxy)](#4-серверный-код-loyalty-proxy)
5. [Инфраструктура (lib/core, lib/shared, lib/app)](#5-инфраструктура)
6. [Карта зависимостей](#6-карта-зависимостей)
7. [Потоки данных](#7-потоки-данных)
8. [API Endpoints](#8-api-endpoints)
9. [Хранилище данных](#9-хранилище-данных)

---

## 1. Обзор проекта

### 1.1 Технологический стек

| Компонент | Технология | Версия |
|-----------|------------|--------|
| Мобильное приложение | Flutter/Dart | SDK ^3.5.3 |
| Сервер | Node.js/Express | - |
| База данных | JSON файлы | /var/www/* |
| Push-уведомления | Firebase Cloud Messaging | 15.0.0 |
| Геолокация | Geolocator | 10.1.1 |
| Фоновые задачи | WorkManager | 0.5.2 |

### 1.2 Статистика кодовой базы

| Метрика | Значение |
|---------|----------|
| Flutter модулей | 31 |
| Страниц (pages) | 150+ |
| Сервисов (services) | 60+ |
| Моделей (models) | 80+ |
| Серверных файлов | 50 JS |
| API endpoints | 160+ |
| Тестов | 475 |

### 1.3 Роли пользователей (текущие)

```
┌─────────────────────────────────────────┐
│                 ADMIN                   │
│     (Видит ВСЕ магазины и данные)      │
└─────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
┌───────────────┐       ┌───────────────┐
│   EMPLOYEE    │       │    CLIENT     │
│  (Сотрудник)  │       │   (Клиент)    │
└───────────────┘       └───────────────┘
```

---

## 2. Структура каталогов

```
arabica2026/
├── lib/
│   ├── app/                    # Главные страницы приложения
│   │   ├── pages/
│   │   │   ├── main_menu_page.dart
│   │   │   ├── my_dialogs_page.dart
│   │   │   ├── reports_page.dart
│   │   │   ├── data_management_page.dart
│   │   │   ├── client_functions_page.dart
│   │   │   └── role_test_page.dart
│   │   └── services/
│   │       └── my_dialogs_counter_service.dart
│   │
│   ├── core/                   # Инфраструктура
│   │   ├── constants/
│   │   │   ├── api_constants.dart
│   │   │   └── app_constants.dart
│   │   ├── services/
│   │   │   ├── base_http_service.dart
│   │   │   ├── firebase_service.dart
│   │   │   ├── notification_service.dart
│   │   │   ├── photo_upload_service.dart
│   │   │   ├── media_upload_service.dart
│   │   │   ├── background_gps_service.dart
│   │   │   ├── app_update_service.dart
│   │   │   └── report_notification_service.dart
│   │   ├── utils/
│   │   │   ├── cache_manager.dart
│   │   │   ├── date_formatter.dart
│   │   │   ├── error_handler.dart
│   │   │   ├── logger.dart
│   │   │   └── phone_normalizer.dart
│   │   └── widgets/
│   │       └── shop_icon.dart
│   │
│   ├── shared/                 # Общие компоненты
│   │   ├── providers/
│   │   │   ├── cart_provider.dart
│   │   │   └── order_provider.dart
│   │   ├── models/
│   │   │   └── unified_dialog_message_model.dart
│   │   ├── widgets/
│   │   │   ├── media_picker_button.dart
│   │   │   └── media_message_widget.dart
│   │   └── dialogs/
│   │       └── ... (8 файлов диалогов)
│   │
│   ├── features/               # 31 бизнес-модуль
│   │   ├── ai_training/
│   │   ├── attendance/
│   │   ├── bonuses/
│   │   ├── clients/
│   │   ├── data_cleanup/
│   │   ├── efficiency/
│   │   ├── employee_chat/
│   │   ├── employees/
│   │   ├── envelope/
│   │   ├── fortune_wheel/
│   │   ├── job_application/
│   │   ├── kpi/
│   │   ├── loyalty/
│   │   ├── main_cash/
│   │   ├── menu/
│   │   ├── orders/
│   │   ├── product_questions/
│   │   ├── rating/
│   │   ├── recipes/
│   │   ├── recount/
│   │   ├── referrals/
│   │   ├── reviews/
│   │   ├── rko/
│   │   ├── shift_handover/
│   │   ├── shifts/
│   │   ├── shops/
│   │   ├── suppliers/
│   │   ├── tasks/
│   │   ├── tests/
│   │   ├── training/
│   │   └── work_schedule/
│   │
│   └── main.dart
│
├── loyalty-proxy/              # Серверный код
│   ├── index.js                # Главный сервер (8500+ строк)
│   ├── api/                    # API модули (24 файла)
│   ├── modules/                # Специализированные модули
│   └── utils/                  # Утилиты
│
├── test/                       # Тесты (475 тестов)
│   ├── admin/
│   ├── client/
│   ├── employee/
│   └── integration/
│
└── android/                    # Android конфигурация
```

---

## 3. Flutter модули (lib/features)

### 3.1 AI Training (🔧 В разработке)

**Путь:** `lib/features/ai_training/`

**Назначение:** AI/ML система обучения для распознавания товаров (сигареты), Z-отчётов и верификации пересменок.

**Страницы (11):**
| Файл | Описание |
|------|----------|
| `ai_training_page.dart` | Главный хаб с TabBar |
| `z_report_training_page.dart` | Обучение распознавания Z-отчётов |
| `cigarette_training_page.dart` | Обучение подсчёта сигарет |
| `cigarette_annotation_page.dart` | Разметка bounding boxes |
| `shift_training_page.dart` | Загрузка фото пересменок |
| `shift_ai_verification_page.dart` | AI верификация пересменок |
| `photo_templates_page.dart` | Управление шаблонами |
| `template_camera_page.dart` | Камера с overlay шаблона |
| `template_editor_page.dart` | Редактор шаблонов |
| `training_settings_page.dart` | Настройки AI |
| `pending_codes_page.dart` | Нераспознанные коды товаров |

**Сервисы (5):**
- `z_report_service.dart` - OCR парсинг Z-отчётов
- `z_report_template_service.dart` - Управление шаблонами
- `cigarette_vision_service.dart` - Computer vision сигарет
- `shift_ai_verification_service.dart` - Валидация пересменок
- `master_catalog_service.dart` - Мастер-каталог товаров

**Модели (7):**
- `z_report_template_model.dart`
- `z_report_sample_model.dart`
- `photo_template.dart`
- `cigarette_training_model.dart`
- `master_product_model.dart`
- `pending_code_model.dart`
- `shift_ai_verification_model.dart`

**Виджеты (4):**
- `bounding_box_painter.dart`
- `template_overlay_painter.dart`
- `region_selector_widget.dart`
- `z_report_recognition_dialog.dart`

**Зависимости:** employees, package:image, core services

---

### 3.2 Attendance (Посещаемость)

**Путь:** `lib/features/attendance/`

**Назначение:** Система "Я на работе" с GPS-отслеживанием и 4-вкладочным отчётом.

**Страницы (5):**
| Файл | Описание |
|------|----------|
| `attendance_reports_page.dart` | 4 вкладки: Сотрудники, Магазины, Ожидающие, Не сданы |
| `attendance_month_page.dart` | Календарь посещаемости сотрудника |
| `attendance_shop_selection_page.dart` | Выбор магазина для отметки |
| `attendance_employee_detail_page.dart` | История посещаемости сотрудника |
| `attendance_day_details_dialog.dart` | Детали дня |

**Сервисы (2):**
- `attendance_service.dart` - GPS, геофенсинг, ближайший магазин
- `attendance_report_service.dart` - API: GET/POST /api/attendance

**Модели (3):**
- `attendance_model.dart`
- `pending_attendance_model.dart`
- `shop_attendance_summary.dart`

**API Endpoints:**
- `POST /api/attendance` - Отметка посещаемости
- `GET /api/attendance` - Получение записей
- `GET /api/attendance/pending` - Ожидающие отчёты
- `GET /api/attendance/failed` - Не сданные отчёты

**Зависимости:** shops, employees, geolocator

---

### 3.3 Bonuses (Премии и штрафы)

**Путь:** `lib/features/bonuses/`

**Назначение:** Админ-система назначения премий и штрафов сотрудникам.

**Страницы (2):**
- `bonus_penalty_management_page.dart` - Создание премии/штрафа
- `bonus_penalty_history_page.dart` - История с фильтрами

**Сервисы (1):**
- `bonus_penalty_service.dart` - CRUD операции

**Модели (1):**
- `bonus_penalty_model.dart`

**API Endpoints:**
- `GET /api/bonuses-penalties`
- `POST /api/bonuses-penalties`
- `DELETE /api/bonuses-penalties/:id`

---

### 3.4 Clients (Клиенты)

**Путь:** `lib/features/clients/`

**Назначение:** Управление клиентами и диалогами с ними.

**Страницы (7):**
- `clients_management_page.dart` - Список клиентов
- `client_dialog_page.dart` - Чат с клиентом
- `client_chat_page.dart` - Интерфейс сообщений
- `management_dialog_page.dart` - Управление диалогами
- `management_dialogs_list_page.dart` - Список диалогов
- `registration_page.dart` - Регистрация клиента
- `network_dialog_page.dart` - Сетевые диалоги

**Сервисы (5):**
- `client_service.dart`
- `client_dialog_service.dart`
- `registration_service.dart`
- `network_message_service.dart`
- `management_message_service.dart`

**Модели (5):**
- `client_model.dart`
- `client_message_model.dart`
- `client_dialog_model.dart`
- `network_message_model.dart`
- `management_message_model.dart`

---

### 3.5 Data Cleanup (Очистка данных)

**Путь:** `lib/features/data_cleanup/`

**Назначение:** Админ-утилита для очистки старых данных на сервере.

**Страницы (1):**
- `data_cleanup_page.dart` - Dashboard с использованием диска по категориям

**Сервисы (1):**
- `cleanup_service.dart`

**API Endpoints:**
- `GET /api/admin/disk-info`
- `GET /api/admin/data-stats`
- `POST /api/admin/cleanup/:category`

---

### 3.6 Efficiency (Эффективность)

**Путь:** `lib/features/efficiency/`

**Назначение:** Комплексная система аналитики эффективности по 10 категориям.

**10 категорий эффективности:**
1. shifts - пересменки
2. recount - пересчёты
3. envelope - конверты
4. attendance - посещаемость
5. reviews - отзывы
6. rko - РКО
7. orders - заказы
8. productSearch - поиск товара
9. tests - тестирование
10. tasks - задачи

**Страницы (15):**
- `my_efficiency_page.dart` - "Моя эффективность"
- `points_settings_page.dart` - Настройка баллов (10 вкладок)
- `employees_efficiency_page.dart` - Рейтинг сотрудников
- `efficiency_analytics_page.dart` - Аналитика
- `efficiency_by_shop_page.dart` - По магазинам
- `efficiency_by_employee_page.dart` - По сотрудникам
- `employee_efficiency_detail_page.dart` - Детали сотрудника
- `shop_efficiency_detail_page.dart` - Детали магазина
- + 7 файлов настроек по категориям

**Сервисы (4):**
- `efficiency_calculation_service.dart`
- `efficiency_data_service.dart`
- `points_settings_service.dart`
- `data_loaders/efficiency_record_loaders.dart`

**Модели (14):**
- `efficiency_data_model.dart`
- + 13 моделей настроек по категориям

**Зависимости:** employees, bonuses, referrals, rating, tests

---

### 3.7 Employee Chat (Чат сотрудников)

**Путь:** `lib/features/employee_chat/`

**Назначение:** Внутренняя коммуникация с 4 типами чатов.

**4 типа чатов:**
1. general - общий для всей компании
2. shop - чат магазина
3. private - личные сообщения
4. group - групповые чаты

**Страницы (6):**
- `employee_chats_list_page.dart` - Список чатов
- `employee_chat_page.dart` - Интерфейс чата
- `create_group_page.dart` - Создание группы
- `group_info_page.dart` - Информация о группе
- `shop_chat_members_page.dart` - Участники чата магазина
- `new_chat_page.dart` - Новый приватный чат

**Сервисы (3):**
- `employee_chat_service.dart` - HTTP API
- `chat_websocket_service.dart` - WebSocket real-time
- `client_group_chat_service.dart` - Для клиентов

**Модели (2):**
- `employee_chat_model.dart`
- `employee_chat_message_model.dart`

**Виджеты (2):**
- `chat_message_bubble.dart`
- `chat_input_field.dart`

---

### 3.8 Employees (Сотрудники)

**Путь:** `lib/features/employees/`

**Назначение:** Управление сотрудниками (CRUD, роли, верификация).

**Страницы (7):**
- `employees_page.dart` - Список сотрудников
- `employee_panel_page.dart` - Профиль сотрудника
- `employee_registration_page.dart` - Регистрация
- `employee_registration_view_page.dart` - Заявки на регистрацию
- `employee_registration_select_employee_page.dart` - Выбор сотрудника
- `unverified_employees_page.dart` - Неверифицированные
- `employee_schedule_page.dart` - График сотрудника

**Сервисы (3):**
- `employee_service.dart` - CRUD операции
- `employee_registration_service.dart` - Регистрация
- `user_role_service.dart` - Управление ролями

**Модели (2):**
- `employee_registration_model.dart`
- `user_role_model.dart` - **КРИТИЧЕСКИ ВАЖНО для мультитенантности**

---

### 3.9 Envelope (Конверты)

**Путь:** `lib/features/envelope/`

**Назначение:** Система сдачи наличных с 5 вкладками и автоматизацией.

**5 вкладок:**
1. В очереди (pending)
2. Не сданы (failed)
3. Ожидают проверки (awaiting)
4. Подтверждены (confirmed)
5. Отклонены (rejected)

**Страницы (5):**
- `envelope_reports_list_page.dart` - 5 вкладок
- `envelope_form_page.dart` - Форма сдачи
- `envelope_report_view_page.dart` - Просмотр отчёта
- `envelope_questions_management_page.dart` - Управление вопросами

**Сервисы (2):**
- `envelope_report_service.dart`
- `envelope_question_service.dart`

**Модели (3):**
- `envelope_report_model.dart`
- `pending_envelope_report_model.dart`
- `envelope_question_model.dart`

**Автоматизация:**
- 07:00/19:00 → Автосоздание pending
- 09:00/21:00 → Автоштраф -5 баллов
- 23:59 → Очистка pending/failed

---

### 3.10 Fortune Wheel (Колесо удачи)

**Путь:** `lib/features/fortune_wheel/`

**Назначение:** Геймификация для топ-3 сотрудников с 15-секторным колесом.

**Страницы (3):**
- `fortune_wheel_page.dart` - Колесо с анимацией
- `wheel_settings_page.dart` - Настройка секторов (админ)
- `wheel_reports_page.dart` - История прокруток

**Сервисы (1):**
- `fortune_wheel_service.dart`

**Модели (2):**
- `fortune_wheel_model.dart`
- `FortuneWheelSector`, `WheelSpinResult`, `EmployeeWheelSpins`

**Виджеты (1):**
- `animated_wheel_widget.dart` - Анимация колеса

**Награды:**
- 1 место: 2 прокрутки
- 2-3 место: 1 прокрутка

---

### 3.11 Job Application (Заявки на работу)

**Путь:** `lib/features/job_application/`

**Назначение:** Подача и обработка заявок на трудоустройство.

**Страницы (5):**
- `job_application_welcome_page.dart`
- `job_application_form_page.dart`
- `job_applications_list_page.dart`
- `job_application_detail_page.dart`

**Сервисы (1):**
- `job_application_service.dart`

**Статусы:** new → viewed → contacted → interview → accepted/rejected

---

### 3.12 KPI (Аналитика)

**Путь:** `lib/features/kpi/`

**Назначение:** Дашборд аналитики по сотрудникам и магазинам.

**Страницы (6):**
- `kpi_type_selection_page.dart` - Выбор типа анализа
- `kpi_employees_list_page.dart` - Список сотрудников
- `kpi_employee_detail_page.dart` - Детали сотрудника
- `kpi_employee_day_detail_page.dart` - День сотрудника
- `kpi_shops_list_page.dart` - Список магазинов
- `kpi_shop_calendar_page.dart` - Календарь магазина

**Сервисы (6):**
- `kpi_service.dart` - Главный координатор
- `kpi_aggregation_service.dart`
- `kpi_cache_service.dart`
- `kpi_filters.dart`
- `kpi_normalizers.dart`
- `kpi_schedule_integration_service.dart`

**Зависимости:** attendance, shifts, recount, rko, envelope, shift_handover, work_schedule, shops

---

### 3.13 Loyalty (Карта лояльности)

**Путь:** `lib/features/loyalty/`

**Назначение:** Клиентская программа лояльности (N+M акция).

**Страницы (3):**
- `loyalty_page.dart` - Карта с QR-кодом
- `loyalty_scanner_page.dart` - Сканер QR
- `loyalty_promo_management_page.dart` - Настройка акции (админ)

**Сервисы (2):**
- `loyalty_service.dart`
- `loyalty_storage.dart`

---

### 3.14 Main Cash (Главная касса)

**Путь:** `lib/features/main_cash/`

**Назначение:** Управление кассой всех магазинов (ООО/ИП балансы).

**Страницы (6):**
- `main_cash_page.dart` - Дашборд балансов
- `shop_balance_details_page.dart` - Детали магазина
- `withdrawal_shop_selection_page.dart` - Выбор магазина для выемки
- `withdrawal_employee_selection_page.dart` - Выбор сотрудника
- `withdrawal_form_page.dart` - Форма выемки
- `revenue_analytics_page.dart` - Аналитика выручки

**Сервисы (4):**
- `main_cash_service.dart`
- `withdrawal_service.dart`
- `revenue_analytics_service.dart`
- `turnover_service.dart`

**Модели (4):**
- `shop_cash_balance_model.dart`
- `withdrawal_model.dart`
- `withdrawal_expense_model.dart`
- `shop_revenue_model.dart`

---

### 3.15 Menu (Меню)

**Путь:** `lib/features/menu/`

**Назначение:** Управление меню кофейни.

**Страницы (2):**
- `menu_page.dart` - Отображение меню
- `menu_groups_page.dart` - Управление категориями (админ)

**Сервисы (1):**
- `menu_service.dart` - CRUD операции

---

### 3.16 Orders (Заказы)

**Путь:** `lib/features/orders/`

**Назначение:** Управление заказами (корзина, статусы, отчёты).

**Страницы (5):**
- `cart_page.dart` - Корзина
- `orders_page.dart` - Дашборд заказов
- `employee_order_detail_page.dart` - Детали заказа
- `employee_orders_page.dart` - Заказы сотрудника
- `orders_report_page.dart` - Отчёты

**Сервисы (2):**
- `order_service.dart`
- `order_timeout_settings_service.dart`

**Статусы:** pending → accepted/rejected → completed

---

### 3.17 Product Questions (Поиск товара)

**Путь:** `lib/features/product_questions/`

**Назначение:** Q&A система с бонусами за ответы.

**Страницы (13):**
- `product_search_page.dart` - Поиск
- `product_search_shop_selection_page.dart` - Выбор магазина
- `product_question_input_page.dart` - Ввод вопроса
- `product_question_dialog_page.dart` - Диалог Q&A
- `product_question_client_dialog_page.dart` - Клиентский вид
- `product_question_employee_dialog_page.dart` - Вид сотрудника
- `product_question_personal_dialog_page.dart` - Личный диалог
- `product_question_answer_page.dart` - Ответ на вопрос
- `product_questions_management_page.dart` - Управление
- `product_questions_report_page.dart` - Отчёты
- + ещё 3 страницы

**Сервисы (1):**
- `product_question_service.dart`

**Бонусы:** +0.2 балла за ответ

---

### 3.18 Rating (Рейтинг)

**Путь:** `lib/features/rating/`

**Назначение:** Расчёт нормализованного рейтинга сотрудников.

**Формула:**
```
normalizedRating = (totalPoints / shiftsCount) + referralPoints
```

**Страницы (1):**
- `my_rating_page.dart` - "Мой рейтинг" (3 месяца истории)

**Сервисы (1):**
- `rating_service.dart`

**Модели (1):**
- `employee_rating_model.dart`

**Виджеты (1):**
- `rating_badge_widget.dart` - 🥇🥈🥉

---

### 3.19 Recipes (Рецепты)

**Путь:** `lib/features/recipes/`

**Назначение:** Управление рецептами для обучения.

**Страницы (5):**
- `recipes_list_page.dart` - Список рецептов
- `recipe_view_page.dart` - Просмотр
- `recipe_edit_page.dart` - Редактирование
- `recipe_form_page.dart` - Создание
- `recipe_list_edit_page.dart` - Пакетное управление

**Сервисы (1):**
- `recipe_service.dart`

**Модели (1):**
- `recipe_model.dart`

---

### 3.20 Recount (Пересчёты)

**Путь:** `lib/features/recount/`

**Назначение:** Система инвентаризации с AI интеграцией.

**Страницы (8):**
- `recount_shop_selection_page.dart` - Выбор магазина
- `recount_questions_page.dart` - Прохождение пересчёта
- `recount_report_view_page.dart` - Просмотр отчёта
- `recount_reports_list_page.dart` - Список отчётов
- `recount_management_tabs_page.dart` - 4 вкладки управления
- `recount_questions_management_page.dart` - Управление вопросами
- `recount_points_settings_page.dart` - Настройка баллов
- `recount_summary_report_page.dart` - Сводный отчёт

**Сервисы (4):**
- `recount_service.dart`
- `pending_recount_service.dart`
- `recount_question_service.dart`
- `recount_points_service.dart`

**Модели (8):**
- `recount_report_model.dart`
- `recount_answer_model.dart`
- `pending_recount_model.dart`
- `pending_recount_report_model.dart`
- `recount_question_model.dart`
- `recount_pivot_model.dart`
- `recount_points_model.dart`
- `recount_settings_model.dart`

---

### 3.21 Referrals (Рефералы)

**Путь:** `lib/features/referrals/`

**Назначение:** Реферальная система с милестоунами.

**Страницы (3):**
- `referrals_report_page.dart` - Отчёт по всем сотрудникам
- `employee_referrals_detail_page.dart` - Детали сотрудника
- `referrals_points_settings_page.dart` - Настройка баллов

**Сервисы (1):**
- `referral_service.dart`

**Модели (1):**
- `referral_stats_model.dart`

**Коды:** 1-1000 уникальные коды

---

### 3.22 Reviews (Отзывы)

**Путь:** `lib/features/reviews/`

**Назначение:** Управление отзывами клиентов.

**Страницы (6):**
- `client_reviews_list_page.dart` - Отзывы клиента
- `review_type_selection_page.dart` - Выбор типа
- `review_shop_selection_page.dart` - Выбор магазина
- `review_text_input_page.dart` - Ввод текста
- `review_detail_page.dart` - Диалог отзыва
- `reviews_list_page.dart` - Все отзывы (админ)
- `reviews_shop_detail_page.dart` - По магазину

**Сервисы (1):**
- `review_service.dart`

**Модели (1):**
- `review_model.dart`

---

### 3.23 RKO (Расходные кассовые ордера)

**Путь:** `lib/features/rko/`

**Назначение:** Управление РКО с PDF генерацией.

**Страницы (6):**
- `rko_reports_page.dart` - 4 вкладки
- `rko_employee_reports_page.dart` - По сотруднику
- `rko_shop_reports_page.dart` - По магазину
- `rko_type_selection_page.dart` - Выбор типа
- `rko_amount_input_page.dart` - Ввод суммы
- `rko_pdf_viewer_page.dart` - Просмотр PDF

**Сервисы (3):**
- `rko_service.dart`
- `rko_reports_service.dart`
- `rko_pdf_service.dart`

**Модели (1):**
- `rko_report_model.dart`

---

### 3.24 Shift Handover (Сдача смены)

**Путь:** `lib/features/shift_handover/`

**Назначение:** Система сдачи смены с 5 вкладками.

**Страницы (6):**
- `shift_handover_reports_list_page.dart` - 5 вкладок
- `shift_handover_role_selection_page.dart` - Выбор роли
- `shift_handover_shop_selection_page.dart` - Выбор магазина
- `shift_handover_questions_page.dart` - Анкета
- `shift_handover_questions_management_page.dart` - Управление вопросами
- `shift_handover_report_view_page.dart` - Просмотр отчёта

**Сервисы (3):**
- `shift_handover_report_service.dart`
- `shift_handover_question_service.dart`
- `pending_shift_handover_service.dart`

**Модели (4):**
- `shift_handover_report_model.dart`
- `pending_shift_handover_model.dart`
- `shift_handover_question_model.dart`
- `pending_shift_handover_report_model.dart`

---

### 3.25 Shifts (Пересменки)

**Путь:** `lib/features/shifts/`

**Назначение:** Система пересменок с 6 вкладками.

**6 вкладок:**
1. Ожидают
2. Не сданы
3. На проверке
4. Подтверждены
5. Отклонены
6. Сводный отчёт (30 дней)

**Страницы (8):**
- `shift_reports_list_page.dart` - 6 вкладок
- `shift_shop_selection_page.dart` - Выбор магазина
- `shift_questions_page.dart` - Анкета
- `shift_questions_management_page.dart` - Управление вопросами
- `shift_report_view_page.dart` - Просмотр отчёта
- `shift_summary_report_page.dart` - Сводный отчёт
- `shift_edit_dialog.dart` - Редактирование
- `shift_photo_gallery_page.dart` - Галерея фото

**Сервисы (4):**
- `shift_report_service.dart`
- `shift_question_service.dart`
- `pending_shift_service.dart`
- `shift_sync_service.dart`

**Модели (4):**
- `shift_report_model.dart`
- `shift_question_model.dart`
- `shift_shortage_model.dart`
- `pending_shift_report_model.dart`

---

### 3.26 Shops (Магазины)

**Путь:** `lib/features/shops/`

**Назначение:** Управление магазинами с геолокацией.

**Страницы (2):**
- `shops_management_page.dart` - CRUD магазинов
- `shops_on_map_page.dart` - Карта с геофенсингом

**Сервисы (2):**
- `shop_service.dart`
- `shop_products_service.dart`

**Модели (2):**
- `shop_model.dart` - с валидацией GPS координат
- `shop_settings_model.dart`

---

### 3.27 Suppliers (Поставщики)

**Путь:** `lib/features/suppliers/`

**Назначение:** Управление поставщиками.

**Страницы (1):**
- `suppliers_management_page.dart` - CRUD с графиком поставок

**Сервисы (1):**
- `supplier_service.dart`

**Модели (1):**
- `supplier_model.dart`

---

### 3.28 Tasks (Задачи)

**Путь:** `lib/features/tasks/`

**Назначение:** Разовые и циклические задачи.

**Страницы (11):**
- `task_management_page.dart` - 2 вкладки
- `create_task_page.dart` - Создание задачи
- `create_recurring_task_page.dart` - Создание циклической
- `my_tasks_page.dart` - Мои задачи
- `task_detail_page.dart` - Детали
- `task_response_page.dart` - Ответ на задачу
- `recurring_task_response_page.dart` - Ответ на циклическую
- `task_recipient_selection_page.dart` - Выбор получателей
- `recurring_recipient_selection_page.dart` - Получатели циклических
- `task_analytics_page.dart` - Аналитика
- `task_reports_page.dart` - Отчёты

**Сервисы (2):**
- `task_service.dart`
- `recurring_task_service.dart`

---

### 3.29 Tests (Тестирование)

**Путь:** `lib/features/tests/`

**Назначение:** Система тестирования сотрудников с автобаллами.

**Страницы (4):**
- `test_page.dart` - Прохождение теста (7 мин, 20 вопросов)
- `test_report_page.dart` - Результаты
- `test_notifications_page.dart` - Уведомления
- `test_questions_management_page.dart` - Управление вопросами

**Сервисы (2):**
- `test_result_service.dart`
- `test_question_service.dart`

**Модели (2):**
- `test_model.dart`
- `test_result_model.dart`

---

### 3.30 Training (Обучение)

**Путь:** `lib/features/training/`

**Назначение:** Статьи обучения с фильтрацией по ролям.

**Страницы (4):**
- `training_page.dart` - Список статей
- `training_article_view_page.dart` - Просмотр
- `training_article_editor_page.dart` - Редактор
- `training_articles_management_page.dart` - Управление

**Сервисы (1):**
- `training_article_service.dart`

**Модели (2):**
- `training_model.dart`
- `content_block.dart`

---

### 3.31 Work Schedule (График работы)

**Путь:** `lib/features/work_schedule/`

**Назначение:** Комплексная система планирования смен.

**Страницы (4):**
- `work_schedule_page.dart` - 2 вкладки (график, переводы)
- `my_schedule_page.dart` - Мой график
- `shift_transfer_requests_page.dart` - Заявки на перевод
- `employee_bulk_schedule_dialog.dart` - Массовые операции

**Сервисы (4):**
- `work_schedule_service.dart`
- `shift_transfer_service.dart`
- `schedule_pdf_service.dart`
- `auto_fill_schedule_service.dart`

**Модели (2):**
- `work_schedule_model.dart`
- `shift_transfer_model.dart`

**Утилиты:**
- `work_schedule_validator.dart` - Валидация расписания

---

## 4. Серверный код (loyalty-proxy)

### 4.1 Главный сервер (index.js)

**Строк кода:** 8,500+
**API endpoints:** 150+

**Ключевые возможности:**
- Express.js сервер
- Google Apps Script прокси
- Rate limiting и security middleware
- CORS и Helmet
- Firebase Admin для push-уведомлений
- Multer для загрузки файлов

### 4.2 API модули (api/*.js)

| Файл | Назначение |
|------|------------|
| `attendance_automation_scheduler.js` | Автоматизация посещаемости |
| `clients_api.js` | Управление клиентами |
| `employee_chat_api.js` | Чат сотрудников |
| `employee_chat_websocket.js` | WebSocket для чата |
| `envelope_automation_scheduler.js` | Автоматизация конвертов |
| `geofence_api.js` | Геофенсинг |
| `master_catalog_api.js` | Мастер-каталог товаров |
| `points_settings_api.js` | Настройки баллов |
| `product_questions_api.js` | Q&A система |
| `product_questions_notifications.js` | Уведомления Q&A |
| `shift_transfers_api.js` | Переводы смен |
| `shift_transfers_notifications.js` | Уведомления переводов |
| `shop_products_api.js` | Товары магазина |
| `task_points_settings_api.js` | Баллы за задачи |
| `withdrawals_api.js` | Выемки наличных |
| `z_report_api.js` | Z-отчёты |
| `cigarette_vision_api.js` | AI подсчёт сигарет |
| `shift_ai_verification_api.js` | AI верификация смен |
| `data_cleanup_api.js` | Очистка данных |
| `shift_automation_scheduler.js` | Автоматизация пересменок |
| `recount_automation_scheduler.js` | Автоматизация пересчётов |
| `rko_automation_scheduler.js` | Автоматизация РКО |
| `shift_handover_automation_scheduler.js` | Автоматизация сдачи смен |
| `master_catalog_notifications.js` | Уведомления каталога |

### 4.3 Отдельные API файлы

| Файл | Назначение |
|------|------------|
| `efficiency_calc.js` | Расчёт эффективности (10 категорий) |
| `rating_wheel_api.js` | Рейтинг и колесо удачи |
| `referrals_api.js` | Реферальная система |
| `tasks_api.js` | Разовые задачи |
| `recurring_tasks_api.js` | Циклические задачи |
| `job_applications_api.js` | Заявки на работу |
| `recount_points_api.js` | Баллы за пересчёты |
| `report_notifications_api.js` | Push-уведомления отчётов |
| `order_notifications_api.js` | Уведомления заказов |
| `order_timeout_api.js` | Таймауты заказов |

### 4.4 Модули (modules/*.js)

| Файл | Назначение |
|------|------------|
| `orders.js` | Ядро заказов |
| `z-report-templates.js` | Шаблоны Z-отчётов |
| `z-report-vision.js` | AI распознавание Z-отчётов |
| `cigarette-vision.js` | AI подсчёт сигарет |

---

## 5. Инфраструктура

### 5.1 lib/core/constants/

**api_constants.dart:**
- `serverUrl` - https://arabica26.ru
- Таймауты: short (10s), default (15s), long (30s), upload (120s)
- 30+ endpoint констант

**app_constants.dart:**
- `checkInRadius` - 750м для геофенса
- `eveningBoundaryHour` - 15:00 граница смен
- `cacheDuration` - 5 минут TTL

### 5.2 lib/core/services/

| Сервис | Назначение |
|--------|------------|
| `base_http_service.dart` | HTTP клиент с type-safe сериализацией |
| `firebase_service.dart` | FCM push-уведомления |
| `notification_service.dart` | Локальные уведомления |
| `photo_upload_service.dart` | Загрузка фото смен |
| `media_upload_service.dart` | Загрузка медиа |
| `background_gps_service.dart` | Фоновый GPS (WorkManager) |
| `app_update_service.dart` | In-app обновления |
| `report_notification_service.dart` | Счётчики отчётов |

### 5.3 lib/core/utils/

| Утилита | Назначение |
|---------|------------|
| `cache_manager.dart` | LRU кэш с TTL (max 200 записей) |
| `date_formatter.dart` | Русское форматирование дат |
| `error_handler.dart` | Категоризация ошибок |
| `logger.dart` | Debug логирование |
| `phone_normalizer.dart` | Нормализация телефонов |

### 5.4 lib/shared/

**Providers:**
- `cart_provider.dart` - Состояние корзины
- `order_provider.dart` - Состояние заказов

**Models:**
- `unified_dialog_message_model.dart` - Полиморфные сообщения

**Widgets:**
- `media_picker_button.dart` - Выбор медиа
- `media_message_widget.dart` - Отображение медиа

**Dialogs:**
- 8 файлов диалогов для расписания и сообщений

### 5.5 lib/app/

**Pages:**
- `main_menu_page.dart` - Главное меню
- `my_dialogs_page.dart` - "Мои диалоги" (6 типов + группы)
- `reports_page.dart` - Отчёты
- `data_management_page.dart` - Управление данными
- `client_functions_page.dart` - Функции клиента
- `role_test_page.dart` - Тестирование ролей

**Services:**
- `my_dialogs_counter_service.dart` - Подсчёт непрочитанных

---

## 6. Карта зависимостей

### 6.1 Критические зависимости между модулями

```
┌─────────────────────────────────────────────────────────────────┐
│                      EFFICIENCY (центр)                         │
│                                                                 │
│  Зависит от: attendance, shifts, recount, envelope,            │
│              reviews, rko, orders, product_questions,           │
│              tests, tasks, bonuses, referrals                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         RATING                                  │
│                                                                 │
│  Зависит от: efficiency (10 категорий), referrals (бонусы),    │
│              attendance (подсчёт смен)                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      FORTUNE_WHEEL                              │
│                                                                 │
│  Зависит от: rating (топ-3 для прокруток)                      │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Зависимости KPI

```
                          ┌──────────┐
                          │   KPI    │
                          └────┬─────┘
                               │
     ┌─────────────────────────┼─────────────────────────┐
     ▼                         ▼                         ▼
┌──────────┐            ┌──────────┐            ┌──────────┐
│attendance│            │  shifts  │            │ recount  │
└──────────┘            └──────────┘            └──────────┘
     │                         │                         │
     ▼                         ▼                         ▼
┌──────────┐            ┌──────────┐            ┌──────────┐
│   rko    │            │ envelope │            │  shift   │
│          │            │          │            │ handover │
└──────────┘            └──────────┘            └──────────┘
                               │
                               ▼
                         ┌──────────┐
                         │work_sched│
                         │   ule    │
                         └──────────┘
```

### 6.3 Зависимости главной кассы

```
┌───────────────────────────────────────┐
│              MAIN_CASH                │
│                                       │
│  ← envelope (входящие наличные)       │
│  ← withdrawals (выемки)               │
│  → shops (список магазинов)           │
└───────────────────────────────────────┘
```

---

## 7. Потоки данных

### 7.1 Поток расчёта эффективности

```
┌─────────────────────────────────────────────────────────────────┐
│                     РАСЧЁТ ЭФФЕКТИВНОСТИ                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. Инициализация batch cache (efficiency_calc.js)              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Для каждого сотрудника:                                     │
│    ├── Получить количество смен из attendance                   │
│    ├── Рассчитать эффективность по 10 категориям               │
│    ├── Получить баллы рефералов (с милестоунами)               │
│    ├── Рассчитать normalizedRating = (total / shifts) + refs   │
│    └── Назначить прокрутки Fortune Wheel топ-3                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Кэшировать рейтинги по месяцам                              │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Поток автоматизации конвертов

```
07:00/19:00 ──► Генерация pending для всех магазинов
      │
      ▼
До 09:00/21:00 ──► Сотрудники сдают конверты (pending → awaiting)
      │
      ▼
После дедлайна ──► Автоштраф -5 баллов + push + статус failed
      │
      ▼
Админ проверяет ──► Подтверждает/отклоняет с оценкой
      │
      ▼
23:59 ──► Очистка всех pending/failed файлов
```

### 7.3 Поток push-уведомлений

```
Событие (отчёт создан, подтверждён, штраф и т.д.)
      │
      ▼
Найти телефон сотрудника
      │
      ▼
Получить FCM токен из /var/www/fcm-tokens/{phone}.json
      │
      ▼
Firebase Admin Messaging отправляет уведомление
      │
      ▼
Логирование в /var/www/report-notifications/all.json
```

---

## 8. API Endpoints

### 8.1 Сводка по категориям

| Категория | Количество | Методы |
|-----------|------------|--------|
| Attendance | 6 | GET/POST |
| Recount | 7 | GET/POST/PUT/DELETE |
| Employees | 7 | GET/POST/PUT/DELETE |
| Shops | 5 | GET/POST/PUT/DELETE |
| RKO | 8 | GET/POST |
| Shift Handover | 10 | GET/POST/PUT/DELETE |
| Envelope | 8 | GET/POST/PUT/DELETE |
| Orders | 5 | GET/POST/PATCH/DELETE |
| Training | 7 | GET/POST/PUT/DELETE |
| Tests | 6 | GET/POST/PUT/DELETE |
| Reviews | 5 | GET/POST |
| Menu & Recipes | 9 | GET/POST/PUT/DELETE |
| Clients & Loyalty | 6 | GET/POST |
| Chat | 8 | GET/POST/DELETE |
| Work Schedule | 8 | GET/POST/DELETE |
| Suppliers | 5 | GET/POST/PUT/DELETE |
| Withdrawals | 5 | GET/POST/PATCH/DELETE |
| Bonuses | 4 | GET/POST/DELETE |
| Product Questions | 7 | GET/POST/PUT/DELETE |
| Shift Transfers | 6 | GET/POST/PATCH/DELETE |
| **ВСЕГО** | **~160+** | **Все HTTP методы** |

### 8.2 Ключевые endpoints

**Посещаемость:**
- `POST /api/attendance` - Отметка
- `GET /api/attendance/pending` - Ожидающие
- `GET /api/attendance/failed` - Не сданные

**Эффективность:**
- `GET /api/efficiency/reports-batch` - Пакетные данные
- `GET /api/efficiency-penalties` - Штрафы по месяцам

**Рейтинг:**
- `GET /api/ratings` - Рейтинг за месяц
- `POST /api/ratings/calculate` - Пересчёт
- `DELETE /api/ratings/cache` - Очистка кэша

**Колесо удачи:**
- `GET /api/fortune-wheel/settings` - Настройки секторов
- `POST /api/fortune-wheel/spin` - Прокрутка
- `GET /api/fortune-wheel/spins/:employeeId` - Доступные прокрутки

---

## 9. Хранилище данных

### 9.1 Структура /var/www/

```
/var/www/
├── employees/                  # Профили сотрудников (phone.json)
├── shops/                      # Данные магазинов
├── clients/                    # Профили клиентов
│
├── attendance/                 # Записи посещаемости
├── attendance-pending/         # Автогенерированные pending
│
├── shift-reports/              # Отчёты пересменок
├── shift-photos/               # Фото пересменок
├── recount-reports/            # Отчёты пересчётов
├── shift-handovers/            # Отчёты сдачи смен
├── shift-handover-question-photos/
│
├── envelope-reports/           # Сданные конверты
├── envelope-pending/           # Автогенерированные pending
│
├── rko/                        # РКО файлы
├── orders/                     # Заказы
├── product-questions/          # Q&A вопросы
├── product-question-photos/
├── recipes/                    # Рецепты
│
├── work-schedules/             # Графики (YYYY-MM.json)
├── shift-transfers.json        # Заявки на перевод
├── withdrawals/                # Выемки
├── job-applications/           # Заявки на работу
│
├── tasks/                      # Разовые задачи
├── recurring-tasks/            # Циклические задачи
│
├── fcm-tokens/                 # Firebase токены (phone.json)
├── efficiency-penalties/       # Штрафы (YYYY-MM.json)
├── employee-ratings/           # Кэш рейтингов (YYYY-MM.json)
│
├── fortune-wheel/
│   ├── settings.json           # 15 секторов
│   ├── spins/YYYY-MM.json      # Выданные прокрутки
│   └── history/YYYY-MM.json    # История прокруток
│
├── shift-automation-state/     # Состояние scheduler
├── attendance-automation-state/
├── envelope-automation-state/
│
├── points-settings/            # Настройки баллов
│   ├── test_points_settings.json
│   ├── attendance_points_settings.json
│   ├── shift_points_settings.json
│   ├── recount_points_settings.json
│   ├── rko_points_settings.json
│   ├── shift_handover_points_settings.json
│   ├── reviews_points_settings.json
│   ├── product_search_points_settings.json
│   ├── orders_points_settings.json
│   ├── envelope_points_settings.json
│   ├── task_points_settings.json
│   └── referrals.json
│
├── master-catalog/             # AI обучение
├── geofence-notifications/     # История уведомлений
│
└── cache/                      # Различные кэши
```

---

## Заключение

Данный документ содержит полную карту архитектуры приложения Arabica 2026:
- **31 Flutter модуль** с детальным описанием
- **50 серверных файлов** с API endpoints
- **160+ API endpoints**
- **Карты зависимостей** между модулями
- **Потоки данных** для критических систем

**Защищённые системы (30 из 31):** Все модули кроме `ai_training` полностью работают и защищены от изменений.

**Готовность к мультитенантности:** После анализа выявлены ключевые точки изменений:
1. `lib/features/employees/models/user_role_model.dart` - добавление роли developer и managedShopIds
2. `lib/features/employees/services/user_role_service.dart` - логика определения роли
3. `loyalty-proxy/index.js` - middleware фильтрации по управляющим
4. Новый файл `/var/www/shop-managers.json` - конфигурация управляющих

---

*Документ создан для технического аудита перед внедрением мультитенантной архитектуры.*

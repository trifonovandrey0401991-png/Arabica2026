# Навигация по модулю Пересменки и связанным модулям

> Пути ко всем файлам для быстрого поиска.
> Обновлено: 2026-02-12

---

## Оглавление

1. [Пересменка (Shifts)](#1-пересменка-shifts)
2. [Сдача смены (Shift Handover)](#2-сдача-смены-shift-handover)
3. [Эффективность и баллы (Efficiency)](#3-эффективность-и-баллы-efficiency)
4. [KPI](#4-kpi)
5. [Задачи (Tasks)](#5-задачи-tasks)
6. [Сотрудники (Employees)](#6-сотрудники-employees)
7. [Магазины (Shops)](#7-магазины-shops)
8. [AI обучение и верификация (AI Training)](#8-ai-обучение-и-верификация-ai-training)
9. [Core сервисы](#9-core-сервисы)
10. [Backend API (loyalty-proxy)](#10-backend-api-loyalty-proxy)
11. [Backend Schedulers](#11-backend-schedulers)
12. [Данные на сервере](#12-данные-на-сервере)

---

## 1. Пересменка (Shifts)

### Модели
| Файл | Описание |
|------|----------|
| `lib/features/shifts/models/shift_report_model.dart` | Модель отчёта пересменки (ShiftReport, ShiftAnswer, статусы) |
| `lib/features/shifts/models/shift_question_model.dart` | Модель вопроса пересменки (ShiftQuestion, типы ответов) |
| `lib/features/shifts/models/shift_shortage_model.dart` | Модель недостачи товара (ShiftShortage) |
| `lib/features/shifts/models/pending_shift_report_model.dart` | Модель pending отчёта (локальное хранение) |

### Сервисы
| Файл | Описание |
|------|----------|
| `lib/features/shifts/services/shift_report_service.dart` | CRUD отчётов, отправка, мультитенантность (BaseReportService) |
| `lib/features/shifts/services/shift_question_service.dart` | CRUD вопросов пересменки |
| `lib/features/shifts/services/pending_shift_service.dart` | Работа с pending отчётами (локально) |
| `lib/features/shifts/services/shift_sync_service.dart` | Синхронизация локальных отчётов с сервером |

### Страницы
| Файл | Описание |
|------|----------|
| `lib/features/shifts/pages/shift_shop_selection_page.dart` | Выбор магазина перед пересменкой |
| `lib/features/shifts/pages/shift_questions_page.dart` | Заполнение вопросов пересменки сотрудником |
| `lib/features/shifts/pages/shift_reports_list_page.dart` | Список отчётов пересменки (вкладки: ожидание, проверка, подтверждённые) |
| `lib/features/shifts/pages/shift_report_view_page.dart` | Просмотр и проверка отчёта (оценка 1-10, подтверждение) |
| `lib/features/shifts/pages/shift_questions_management_page.dart` | Управление вопросами (CRUD, drag-and-drop порядок) |
| `lib/features/shifts/pages/shift_photo_gallery_page.dart` | Галерея фото из отчётов |
| `lib/features/shifts/pages/shift_edit_dialog.dart` | Диалог редактирования отчёта |
| `lib/features/shifts/pages/shift_summary_report_page.dart` | Сводный отчёт по пересменкам |

---

## 2. Сдача смены (Shift Handover)

### Модели
| Файл | Описание |
|------|----------|
| `lib/features/shift_handover/models/shift_handover_report_model.dart` | Модель отчёта сдачи смены |
| `lib/features/shift_handover/models/shift_handover_question_model.dart` | Модель вопроса сдачи смены |
| `lib/features/shift_handover/models/pending_shift_handover_model.dart` | Pending модель (локально) |
| `lib/features/shift_handover/models/pending_shift_handover_report_model.dart` | Pending отчёт (локально) |

### Сервисы
| Файл | Описание |
|------|----------|
| `lib/features/shift_handover/services/shift_handover_report_service.dart` | CRUD отчётов сдачи смены (BaseReportService) |
| `lib/features/shift_handover/services/shift_handover_question_service.dart` | CRUD вопросов сдачи смены |
| `lib/features/shift_handover/services/pending_shift_handover_service.dart` | Работа с pending отчётами |

### Страницы
| Файл | Описание |
|------|----------|
| `lib/features/shift_handover/pages/shift_handover_shop_selection_page.dart` | Выбор магазина |
| `lib/features/shift_handover/pages/shift_handover_role_selection_page.dart` | Выбор роли (сдающий/принимающий) |
| `lib/features/shift_handover/pages/shift_handover_questions_page.dart` | Заполнение вопросов |
| `lib/features/shift_handover/pages/shift_handover_reports_list_page.dart` | Список отчётов |
| `lib/features/shift_handover/pages/shift_handover_report_view_page.dart` | Просмотр и проверка отчёта |
| `lib/features/shift_handover/pages/shift_handover_questions_management_page.dart` | Управление вопросами |

---

## 3. Эффективность и баллы (Efficiency)

### Модели — общие
| Файл | Описание |
|------|----------|
| `lib/features/efficiency/models/efficiency_data_model.dart` | Модель данных эффективности сотрудника |
| `lib/features/efficiency/models/manager_efficiency_model.dart` | Модель эффективности управляющего |
| `lib/features/efficiency/models/points_settings_model.dart` | Все модели настроек баллов (экспорт) |

### Модели — настройки баллов
| Файл | Описание |
|------|----------|
| `lib/features/efficiency/models/settings/points_settings_base.dart` | Базовый класс настроек (mixins: TimeWindow, RatingBased) |
| `lib/features/efficiency/models/settings/points_settings.dart` | Экспорт всех настроек |
| `lib/features/efficiency/models/settings/shift_points_settings.dart` | **Настройки баллов за пересменку** (minPoints, zeroThreshold, maxPoints) |
| `lib/features/efficiency/models/settings/shift_handover_points_settings.dart` | Настройки баллов за сдачу смены |
| `lib/features/efficiency/models/settings/attendance_points_settings.dart` | Настройки баллов за посещаемость |
| `lib/features/efficiency/models/settings/coffee_machine_points_settings.dart` | Настройки баллов за кофемашину |
| `lib/features/efficiency/models/settings/envelope_points_settings.dart` | Настройки баллов за конверт |
| `lib/features/efficiency/models/settings/manager_points_settings.dart` | Настройки баллов управляющего |
| `lib/features/efficiency/models/settings/orders_points_settings.dart` | Настройки баллов за заказы |
| `lib/features/efficiency/models/settings/product_search_points_settings.dart` | Настройки баллов за поиск товаров |
| `lib/features/efficiency/models/settings/recount_points_settings.dart` | Настройки баллов за пересчёт |
| `lib/features/efficiency/models/settings/reviews_points_settings.dart` | Настройки баллов за отзывы |
| `lib/features/efficiency/models/settings/rko_points_settings.dart` | Настройки баллов за РКО |
| `lib/features/efficiency/models/settings/task_points_settings.dart` | Настройки баллов за задачи |
| `lib/features/efficiency/models/settings/test_points_settings.dart` | Настройки баллов за тесты |

### Сервисы
| Файл | Описание |
|------|----------|
| `lib/features/efficiency/services/efficiency_calculation_service.dart` | **Расчёт баллов** (calculateShiftPoints, calculateShiftHandoverPoints, ...) |
| `lib/features/efficiency/services/points_settings_service.dart` | Загрузка настроек баллов с сервера |
| `lib/features/efficiency/services/efficiency_data_service.dart` | Загрузка данных эффективности |
| `lib/features/efficiency/services/manager_efficiency_service.dart` | Эффективность управляющего |
| `lib/features/efficiency/services/data_loaders/data_loaders.dart` | Загрузчики данных (экспорт) |
| `lib/features/efficiency/services/data_loaders/efficiency_batch_parsers.dart` | Парсеры batch-данных |
| `lib/features/efficiency/services/data_loaders/efficiency_record_loaders.dart` | Загрузчики записей |

### Страницы — основные
| Файл | Описание |
|------|----------|
| `lib/features/efficiency/pages/my_efficiency_page.dart` | **Моя эффективность** (личная статистика сотрудника) |
| `lib/features/efficiency/pages/efficiency_analytics_page.dart` | Аналитика эффективности |
| `lib/features/efficiency/pages/efficiency_by_employee_page.dart` | Эффективность по сотрудникам |
| `lib/features/efficiency/pages/efficiency_by_shop_page.dart` | Эффективность по магазинам |
| `lib/features/efficiency/pages/employee_efficiency_detail_page.dart` | Детали эффективности сотрудника |
| `lib/features/efficiency/pages/employees_efficiency_page.dart` | Список сотрудников с эффективностью |
| `lib/features/efficiency/pages/shop_efficiency_detail_page.dart` | Детали эффективности магазина |
| `lib/features/efficiency/pages/points_settings_page.dart` | Настройки баллов (все вкладки) |

### Страницы — вкладки настроек баллов
| Файл | Описание |
|------|----------|
| `lib/features/efficiency/pages/settings_tabs/shift_points_settings_page.dart` | **Настройки баллов пересменки** |
| `lib/features/efficiency/pages/settings_tabs/shift_handover_points_settings_page.dart` | Настройки баллов сдачи смены |
| `lib/features/efficiency/pages/settings_tabs/attendance_points_settings_page.dart` | Настройки баллов посещаемости |
| `lib/features/efficiency/pages/settings_tabs/coffee_machine_points_settings_page.dart` | Настройки баллов кофемашины |
| `lib/features/efficiency/pages/settings_tabs/envelope_points_settings_page.dart` | Настройки баллов конверта |
| `lib/features/efficiency/pages/settings_tabs/generic_points_settings_page.dart` | Общие настройки (шаблон) |
| `lib/features/efficiency/pages/settings_tabs/manager_points_settings_page.dart` | Настройки баллов управляющего |
| `lib/features/efficiency/pages/settings_tabs/orders_points_settings_page.dart` | Настройки баллов заказов |
| `lib/features/efficiency/pages/settings_tabs/product_search_points_settings_page.dart` | Настройки баллов поиска товаров |
| `lib/features/efficiency/pages/settings_tabs/recount_efficiency_points_settings_page.dart` | Настройки баллов пересчёта |
| `lib/features/efficiency/pages/settings_tabs/recurring_task_points_settings_page.dart` | Настройки баллов циклических задач |
| `lib/features/efficiency/pages/settings_tabs/regular_task_points_settings_page.dart` | Настройки баллов разовых задач |
| `lib/features/efficiency/pages/settings_tabs/reviews_points_settings_page.dart` | Настройки баллов отзывов |
| `lib/features/efficiency/pages/settings_tabs/rko_points_settings_page.dart` | Настройки баллов РКО |
| `lib/features/efficiency/pages/settings_tabs/test_points_settings_page.dart` | Настройки баллов тестов |

### Виджеты
| Файл | Описание |
|------|----------|
| `lib/features/efficiency/widgets/efficiency_common_widgets.dart` | Общие виджеты эффективности |
| `lib/features/efficiency/widgets/rating_preview_widget.dart` | Предпросмотр рейтинга |
| `lib/features/efficiency/widgets/settings_save_button_widget.dart` | Кнопка сохранения настроек |
| `lib/features/efficiency/widgets/settings_slider_widget.dart` | Слайдер настроек |
| `lib/features/efficiency/widgets/settings_widgets.dart` | Общие виджеты настроек |
| `lib/features/efficiency/widgets/time_window_picker_widget.dart` | Выбор временного окна |

### Утилиты
| Файл | Описание |
|------|----------|
| `lib/features/efficiency/utils/efficiency_utils.dart` | Утилиты расчётов |

---

## 4. KPI

### Модели
| Файл | Описание |
|------|----------|
| `lib/features/kpi/models/kpi_models.dart` | Основные KPI модели (KPIDayData, KPIShopData) |
| `lib/features/kpi/models/kpi_employee_month_stats.dart` | Месячная статистика сотрудника |
| `lib/features/kpi/models/kpi_shop_month_stats.dart` | Месячная статистика магазина |

### Сервисы
| Файл | Описание |
|------|----------|
| `lib/features/kpi/services/kpi_service.dart` | Главный KPI сервис (загрузка данных, включая shift_reports) |
| `lib/features/kpi/services/kpi_aggregation_service.dart` | **Агрегация данных** (_processShifts, _processShiftHandovers) |
| `lib/features/kpi/services/kpi_cache_service.dart` | Кэширование KPI данных |
| `lib/features/kpi/services/kpi_filters.dart` | Фильтры KPI (по магазину, сотруднику, дате) |
| `lib/features/kpi/services/kpi_normalizers.dart` | Нормализация данных (даты, имена) |
| `lib/features/kpi/services/kpi_persistence_service.dart` | Сохранение KPI в SharedPreferences |
| `lib/features/kpi/services/kpi_schedule_integration_service.dart` | Интеграция с графиком работы |

### Страницы
| Файл | Описание |
|------|----------|
| `lib/features/kpi/pages/kpi_type_selection_page.dart` | Выбор типа KPI (по магазинам / по сотрудникам) |
| `lib/features/kpi/pages/kpi_shops_list_page.dart` | Список магазинов с KPI |
| `lib/features/kpi/pages/kpi_shop_calendar_page.dart` | Календарь магазина (дни с пересменками) |
| `lib/features/kpi/pages/kpi_shop_day_detail_dialog.dart` | Детали дня магазина (список пересменок) |
| `lib/features/kpi/pages/kpi_employees_list_page.dart` | Список сотрудников с KPI |
| `lib/features/kpi/pages/kpi_employee_detail_page.dart` | Месячная статистика сотрудника |
| `lib/features/kpi/pages/kpi_employee_day_detail_page.dart` | Детали дня сотрудника |

---

## 5. Задачи (Tasks)

### Модели
| Файл | Описание |
|------|----------|
| `lib/features/tasks/models/task_model.dart` | Модель разовой задачи |
| `lib/features/tasks/models/recurring_task_model.dart` | Модель циклической задачи |

### Сервисы
| Файл | Описание |
|------|----------|
| `lib/features/tasks/services/task_service.dart` | CRUD разовых задач |
| `lib/features/tasks/services/recurring_task_service.dart` | CRUD циклических задач |

### Страницы
| Файл | Описание |
|------|----------|
| `lib/features/tasks/pages/my_tasks_page.dart` | **Мои задачи** (включая отчёты review для управляющей) |
| `lib/features/tasks/pages/task_management_page.dart` | Управление задачами |
| `lib/features/tasks/pages/create_task_page.dart` | Создание разовой задачи |
| `lib/features/tasks/pages/create_recurring_task_page.dart` | Создание циклической задачи |
| `lib/features/tasks/pages/task_detail_page.dart` | Детали задачи |
| `lib/features/tasks/pages/task_response_page.dart` | Ответ на задачу |
| `lib/features/tasks/pages/recurring_task_response_page.dart` | Ответ на циклическую задачу |
| `lib/features/tasks/pages/task_recipient_selection_page.dart` | Выбор получателя задачи |
| `lib/features/tasks/pages/recurring_recipient_selection_page.dart` | Выбор получателя циклической задачи |
| `lib/features/tasks/pages/task_analytics_page.dart` | Аналитика задач |
| `lib/features/tasks/pages/task_reports_page.dart` | Отчёты по задачам |

### Виджеты
| Файл | Описание |
|------|----------|
| `lib/features/tasks/widgets/task_common_widgets.dart` | Общие виджеты задач |

---

## 6. Сотрудники (Employees)

### Модели
| Файл | Описание |
|------|----------|
| `lib/features/employees/models/user_role_model.dart` | **Роли пользователей** (UserRole, UserRoleData, мультитенантные поля) |
| `lib/features/employees/models/employee_registration_model.dart` | Модель регистрации сотрудника |

### Сервисы
| Файл | Описание |
|------|----------|
| `lib/features/employees/services/user_role_service.dart` | **Определение роли** (getUserRole, checkEmployeeViaAPI, getMultitenantRole) |
| `lib/features/employees/services/employee_service.dart` | CRUD сотрудников |
| `lib/features/employees/services/employee_registration_service.dart` | Регистрация и верификация сотрудников |

### Страницы
| Файл | Описание |
|------|----------|
| `lib/features/employees/pages/employees_page.dart` | Список сотрудников |
| `lib/features/employees/pages/employee_panel_page.dart` | Панель сотрудника |
| `lib/features/employees/pages/employee_registration_page.dart` | Регистрация сотрудника |
| `lib/features/employees/pages/employee_registration_select_employee_page.dart` | Выбор сотрудника для регистрации |
| `lib/features/employees/pages/employee_registration_view_page.dart` | Просмотр регистрации |
| `lib/features/employees/pages/employee_schedule_page.dart` | График работы сотрудника |
| `lib/features/employees/pages/employee_preferences_dialog.dart` | Предпочтения сотрудника |
| `lib/features/employees/pages/unverified_employees_page.dart` | Неверифицированные сотрудники |

---

## 7. Магазины (Shops)

### Модели
| Файл | Описание |
|------|----------|
| `lib/features/shops/models/shop_model.dart` | Модель магазина (id, name, address, coordinates) |
| `lib/features/shops/models/shop_settings_model.dart` | Настройки магазина |

### Сервисы
| Файл | Описание |
|------|----------|
| `lib/features/shops/services/shop_service.dart` | **CRUD магазинов** (getShops — используется в MultitenancyFilterService) |
| `lib/features/shops/services/shop_products_service.dart` | Товары магазина (DBF остатки) |

### Страницы
| Файл | Описание |
|------|----------|
| `lib/features/shops/pages/shops_management_page.dart` | Управление магазинами |
| `lib/features/shops/pages/shops_on_map_page.dart` | Магазины на карте |

---

## 8. AI обучение и верификация (AI Training)

### Модели
| Файл | Описание |
|------|----------|
| `lib/features/ai_training/models/shift_ai_verification_model.dart` | **Модель AI верификации пересменки** |
| `lib/features/ai_training/models/photo_template.dart` | Шаблон фото |
| `lib/features/ai_training/models/z_report_template_model.dart` | Шаблон Z-отчёта |
| `lib/features/ai_training/models/z_report_sample_model.dart` | Пример Z-отчёта |
| `lib/features/ai_training/models/cigarette_training_model.dart` | Модель обучения сигарет |
| `lib/features/ai_training/models/master_product_model.dart` | Мастер-продукт |
| `lib/features/ai_training/models/pending_code_model.dart` | Pending коды |

### Сервисы
| Файл | Описание |
|------|----------|
| `lib/features/ai_training/services/shift_ai_verification_service.dart` | **Сервис AI верификации фото пересменки** |
| `lib/features/ai_training/services/z_report_service.dart` | Сервис Z-отчётов |
| `lib/features/ai_training/services/z_report_template_service.dart` | Шаблоны Z-отчётов |
| `lib/features/ai_training/services/cigarette_vision_service.dart` | Распознавание сигарет |
| `lib/features/ai_training/services/master_catalog_service.dart` | Мастер-каталог |

### Страницы
| Файл | Описание |
|------|----------|
| `lib/features/ai_training/pages/shift_ai_verification_page.dart` | **Результаты AI проверки пересменки** |
| `lib/features/ai_training/pages/shift_training_page.dart` | **Обучение AI на фото пересменки** |
| `lib/features/ai_training/pages/ai_training_page.dart` | Главная страница AI обучения |
| `lib/features/ai_training/pages/photo_templates_page.dart` | Шаблоны фото |
| `lib/features/ai_training/pages/template_camera_page.dart` | Камера для шаблонов |
| `lib/features/ai_training/pages/template_editor_page.dart` | Редактор шаблонов |
| `lib/features/ai_training/pages/training_settings_page.dart` | Настройки обучения |
| `lib/features/ai_training/pages/z_report_training_page.dart` | Обучение Z-отчётов |
| `lib/features/ai_training/pages/cigarette_annotation_page.dart` | Аннотация сигарет |
| `lib/features/ai_training/pages/cigarette_training_page.dart` | Обучение сигарет |
| `lib/features/ai_training/pages/pending_codes_page.dart` | Pending коды |

### Виджеты
| Файл | Описание |
|------|----------|
| `lib/features/ai_training/widgets/bounding_box_painter.dart` | Отрисовка bounding box |
| `lib/features/ai_training/widgets/region_selector_widget.dart` | Выбор региона на фото |
| `lib/features/ai_training/widgets/template_overlay_painter.dart` | Оверлей шаблона |
| `lib/features/ai_training/widgets/z_report_recognition_dialog.dart` | Диалог распознавания Z-отчёта |

---

## 9. Core сервисы

| Файл | Описание |
|------|----------|
| `lib/core/services/base_report_service.dart` | **Базовый сервис отчётов** (CRUD + мультитенантность) — используется Shift, ShiftHandover, Envelope, CoffeeMachine, Recount |
| `lib/core/services/multitenancy_filter_service.dart` | **Фильтрация по мультитенантности** (getAllowedShopAddresses, filterByShopAddress) |
| `lib/core/services/base_http_service.dart` | HTTP клиент (GET, POST, PUT, DELETE) |
| `lib/core/services/employee_push_service.dart` | Push-уведомления сотрудникам |
| `lib/core/services/notification_service.dart` | Уведомления (FCM) |
| `lib/core/services/firebase_service.dart` | Firebase инициализация |
| `lib/core/services/app_update_service.dart` | Обновление приложения |
| `lib/core/constants/api_constants.dart` | Константы API (serverUrl, endpoints, timeouts) |
| `lib/core/utils/logger.dart` | Логгер (debug, warning, error, maskPhone) |

---

## 10. Backend API (loyalty-proxy)

### API модуля пересменки
| Файл | Описание |
|------|----------|
| `loyalty-proxy/api/shifts_api.js` | **API отчётов пересменки** (GET/POST/PUT/DELETE /api/shift-reports) |
| `loyalty-proxy/api/shift_questions_api.js` | API вопросов пересменки (GET/POST/PUT/DELETE /api/shift-questions) |
| `loyalty-proxy/api/shift_ai_verification_api.js` | API AI верификации фото |
| `loyalty-proxy/api/shift_transfers_api.js` | API переводов смен |
| `loyalty-proxy/api/shift_transfers_notifications.js` | Уведомления о переводах смен |

### API связанных модулей
| Файл | Описание |
|------|----------|
| `loyalty-proxy/api/shift_handover_questions_api.js` | API вопросов сдачи смены |
| `loyalty-proxy/api/shops_api.js` | API магазинов |
| `loyalty-proxy/api/shop_managers_api.js` | **API ролей и управляющих** (/api/shop-managers/role/:phone) |
| `loyalty-proxy/api/employees_api.js` | API сотрудников |
| `loyalty-proxy/api/employee_registration_api.js` | API регистрации сотрудников |
| `loyalty-proxy/api/points_settings_api.js` | API настроек баллов |
| `loyalty-proxy/api/tasks_api.js` | API задач |
| `loyalty-proxy/api/recurring_tasks_api.js` | API циклических задач |
| `loyalty-proxy/api/report_notifications_api.js` | **API push-уведомлений** о статусе отчётов |
| `loyalty-proxy/api/dashboard_batch_api.js` | Batch-загрузка данных для дашборда |

### Утилиты backend
| Файл | Описание |
|------|----------|
| `loyalty-proxy/utils/file_lock.js` | **Блокировка файлов** (withLock — предотвращение race conditions) |
| `loyalty-proxy/index.js` | Главный файл сервера (Express + маршруты) |
| `loyalty-proxy/efficiency_calc.js` | Серверный расчёт эффективности |

---

## 11. Backend Schedulers

| Файл | Описание |
|------|----------|
| `loyalty-proxy/api/shift_automation_scheduler.js` | **Автоматизация пересменки** (pending, дедлайны, штрафы, каждые 5 мин) |
| `loyalty-proxy/api/shift_handover_automation_scheduler.js` | Автоматизация сдачи смены |
| `loyalty-proxy/api/envelope_automation_scheduler.js` | Автоматизация конвертов |
| `loyalty-proxy/api/coffee_machine_automation_scheduler.js` | Автоматизация кофемашин |
| `loyalty-proxy/api/recount_automation_scheduler.js` | Автоматизация пересчёта |
| `loyalty-proxy/api/attendance_automation_scheduler.js` | Автоматизация посещаемости |
| `loyalty-proxy/api/rko_automation_scheduler.js` | Автоматизация РКО |
| `loyalty-proxy/api/product_questions_penalty_scheduler.js` | Штрафы за вопросы о товарах |

---

## 12. Данные на сервере

| Путь | Содержимое | Связь с модулем |
|------|-----------|-----------------|
| `/var/www/shift-reports/` | `{YYYY-MM-DD}.json` — отчёты по дням | Пересменка |
| `/var/www/shift-questions/` | `questions.json` — вопросы | Вопросы пересменки |
| `/var/www/shift-handover-reports/` | Отчёты сдачи смены по дням | Сдача смены |
| `/var/www/shift-handover-questions/` | Вопросы сдачи смены | Вопросы сдачи смены |
| `/var/www/shift-ai-verification/` | Результаты AI проверки | AI верификация |
| `/var/www/points-settings/` | `shift_points.json` и др. | Баллы |
| `/var/www/automation-state/` | Состояние schedulers | Автоматизация |
| `/var/www/shop-managers.json` | Роли, привязки магазинов | Мультитенантность |
| `/var/www/shops.json` | Список магазинов | Магазины |
| `/var/www/employees.json` | Список сотрудников | Сотрудники |

---

## Быстрый поиск по действию

| Хочу найти... | Ищи в файле |
|---------------|-------------|
| Как создаётся отчёт | `shift_report_service.dart` → `submitReport()` |
| Как проверяется отчёт | `shift_report_view_page.dart` → кнопка подтверждения |
| Как считаются баллы | `efficiency_calculation_service.dart` → `calculateShiftPoints()` |
| Как фильтруются отчёты по магазинам | `multitenancy_filter_service.dart` → `filterByShopAddress()` |
| Как определяется роль | `user_role_service.dart` → `getUserRole()` |
| Как создаётся pending | `shift_automation_scheduler.js` → `createPendingReports()` |
| Как обрабатываются дедлайны | `shift_automation_scheduler.js` → `checkSubmissionDeadlines()` |
| Настройки баллов (UI) | `shift_points_settings_page.dart` |
| Настройки баллов (модель) | `shift_points_settings.dart` |
| Вопросы пересменки | `shift_question_model.dart` + `shift_question_service.dart` |
| Недостачи товаров | `shift_shortage_model.dart` |
| Отчёты на проверке в задачах | `my_tasks_page.dart` → `_shiftReviewReports` |
| KPI агрегация | `kpi_aggregation_service.dart` → `_processShifts()` |
| AI проверка фото | `shift_ai_verification_service.dart` |
| Push-уведомления | `employee_push_service.dart` + `report_notifications_api.js` |
| Блокировка файлов | `file_lock.js` → `withLock()` |

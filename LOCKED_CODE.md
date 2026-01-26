# LOCKED CODE - НЕ ИЗМЕНЯТЬ БЕЗ ЯВНОГО РАЗРЕШЕНИЯ

> Этот файл содержит список протестированных и работающих функций.
> Claude Code НЕ ДОЛЖЕН изменять эти файлы без явного запроса пользователя.

---

## Система заказов (v1.5.0) - Проверено: 03.01.2026

### Защищённые файлы:

#### Провайдеры
| Файл | Функции | Статус |
|------|---------|--------|
| `lib/shared/providers/order_provider.dart` | loadClientOrders, createOrder, acceptOrder, rejectOrder | ✅ Работает |
| `lib/shared/providers/cart_provider.dart` | addItem, removeItem, clear | ✅ Работает |

#### Сервисы
| Файл | Функции | Статус |
|------|---------|--------|
| `lib/features/orders/services/order_service.dart` | createOrder, getClientOrders, getAllOrders, updateOrderStatus | ✅ Работает |

#### Страницы заказов
| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/orders/pages/orders_page.dart` | Мои заказы клиента, фото, сортировка | ✅ Работает |
| `lib/features/orders/pages/employee_orders_page.dart` | 3 вкладки (Ожидают/Выполненные/Отказано), иконки статусов | ✅ Работает |
| `lib/features/orders/pages/employee_order_detail_page.dart` | Детали заказа, принятие/отклонение | ✅ Работает |

---

## Серверная часть (v1.5.0) - Проверено: 03.01.2026

### Защищённые модули на сервере:
| Файл | Функционал | Статус |
|------|------------|--------|
| `/root/arabica_app/loyalty-proxy/modules/orders.js` | createOrder, getOrders, updateOrderStatus, push-уведомления | ✅ Работает |

### API Endpoints:
| Endpoint | Метод | Статус |
|----------|-------|--------|
| `/api/orders` | POST | ✅ Создание заказа |
| `/api/orders?clientPhone=X` | GET | ✅ Заказы клиента |
| `/api/orders?status=pending` | GET | ✅ Заказы по статусу |
| `/api/orders/:id/status` | PATCH | ✅ Обновление статуса |

---

## Правила для Claude Code:

1. **НЕ ИЗМЕНЯТЬ** файлы из этого списка без явного запроса
2. **НЕ РЕФАКТОРИТЬ** защищённый код "для улучшения"
3. **НЕ УДАЛЯТЬ** функции из защищённых файлов
4. **СПРАШИВАТЬ** перед любыми изменениями в защищённых файлах

### Если нужно изменить защищённый код:
1. Сообщить пользователю что файл защищён
2. Получить явное разрешение
3. Создать backup перед изменением
4. Обновить этот файл после изменений

---

## История изменений:

| Дата | Версия | Что добавлено |
|------|--------|---------------|
| 03.01.2026 | v1.5.0 | Система заказов: создание, принятие, отклонение, вкладки |
| 03.01.2026 | v1.5.1 | Управление магазинами: интервалы смен, аббревиатуры |
| 03.01.2026 | v1.5.2 | Сотрудники: регистрация, верификация, загрузка фото |
| 03.01.2026 | v1.5.3 | Пересменки: просроченные отчёты, 4-я вкладка, cron 00:00 |
| 03.01.2026 | v1.5.4 | Пересчёты: вопросы (грейды, фото), прохождение (выбор магазина, ответы), отчёты (4 вкладки, оценки, просроченные) |
| 03.01.2026 | v1.5.5 | Статьи обучения: CRUD, группировка, открытие ссылок, белые заголовки, AndroidManifest queries |
| 26.01.2026 | v1.6.0 | Мои диалоги: сетевые сообщения, связь с руководством, интеграция с отзывами и поиском товара |
| 26.01.2026 | v1.6.1 | Поиск товара: вопросы, персональные диалоги, автоматическое начисление баллов, scheduler штрафов |

---

## Управление магазинами (v1.5.1) - Проверено: 03.01.2026

### Защищённые файлы:

#### Страницы
| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/shops/pages/shops_management_page.dart` | Редактирование магазинов, интервалы смен, аббревиатуры | ✅ Работает |

#### Модели
| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/shops/models/shop_settings_model.dart` | Модель настроек магазина, сериализация времени | ✅ Работает |

### Серверная часть:
| Файл | Функционал | Статус |
|------|------------|--------|
| `/root/arabica_app/loyalty-proxy/index.js` | POST /api/shop-settings - сохранение интервалов и аббревиатур | ✅ Работает |

### API Endpoints:
| Endpoint | Метод | Статус |
|----------|-------|--------|
| `/api/shop-settings` | POST | ✅ Сохранение настроек (интервалы, аббревиатуры) |
| `/api/shop-settings/:shopAddress` | GET | ✅ Получение настроек магазина |

---

## Сотрудники (v1.5.2) - Проверено: 03.01.2026

### Защищённые файлы:

#### Сервисы
| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/employees/services/employee_registration_service.dart` | uploadPhoto, saveRegistration, getRegistration, verifyEmployee, getAllRegistrations | ✅ Работает |

#### Модели
| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/employees/models/employee_registration_model.dart` | Модель регистрации сотрудника, сериализация | ✅ Работает |

### Серверная часть:
| Файл | Функционал | Статус |
|------|------------|--------|
| `/root/arabica_app/loyalty-proxy/index.js` | employee-registration endpoints, upload-employee-photo | ✅ Работает |

### Nginx конфигурация:
| Location | Функционал | Статус |
|----------|------------|--------|
| `/upload-employee-photo` | Загрузка фото сотрудников на сервер | ✅ Работает |
| `/employee-photos/` | Раздача статических файлов фотографий | ✅ Работает |

### API Endpoints:
| Endpoint | Метод | Статус |
|----------|-------|--------|
| `/api/employee-registration` | POST | ✅ Сохранение регистрации |
| `/api/employee-registration/:phone` | GET | ✅ Получение регистрации |
| `/api/employee-registration/:phone/verify` | POST | ✅ Верификация сотрудника |
| `/api/employee-registrations` | GET | ✅ Список всех регистраций |
| `/upload-employee-photo` | POST | ✅ Загрузка фото |

---

## Система пересменок (v1.5.3) - Проверено: 03.01.2026

### Общее описание:
Полная система управления пересменками: создание вопросов, прохождение пересменки сотрудниками, просмотр и подтверждение отчётов администратором.

---

### 1. Вопросы пересменки (Управление)

#### Функционал:
- Создание/редактирование/удаление вопросов пересменки
- Типы вопросов: текст, число, фото
- Эталонные фото для каждого магазина (сравнение с фото сотрудника)
- Привязка вопросов к конкретным магазинам

#### Защищённые файлы:

| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/shifts/pages/shift_questions_management_page.dart` | CRUD вопросов, загрузка эталонных фото, выбор магазина | ✅ Работает |
| `lib/features/shifts/models/shift_question_model.dart` | Модель вопроса: id, question, type, referencePhotos, shopAddresses | ✅ Работает |
| `lib/features/shifts/services/shift_question_service.dart` | getQuestions, createQuestion, updateQuestion, deleteQuestion, uploadReferencePhoto | ✅ Работает |

#### API Endpoints:
| Endpoint | Метод | Статус |
|----------|-------|--------|
| `/api/shift-questions` | GET | ✅ Получение вопросов |
| `/api/shift-questions` | POST | ✅ Создание вопроса |
| `/api/shift-questions/:id` | PUT | ✅ Обновление вопроса |
| `/api/shift-questions/:id` | DELETE | ✅ Удаление вопроса |
| `/upload-photo` | POST | ✅ Загрузка эталонного фото |

---

### 2. Прохождение пересменки (Сотрудник)

#### Функционал:
- Пошаговое прохождение вопросов
- Ввод текста/числа, фотографирование
- Показ эталонного фото перед фотографированием
- Сохранение referencePhotoUrl в ответе для сравнения
- Автоматическая загрузка фото на сервер

#### Защищённые файлы:

| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/shifts/pages/shift_handover_page.dart` | UI прохождения пересменки, вопросы пошагово, фото с эталоном | ✅ Работает |
| `lib/features/shifts/models/shift_report_model.dart` | ShiftReport, ShiftAnswer (question, textAnswer, numberAnswer, photoPath, photoDriveId, referencePhotoUrl) | ✅ Работает |

#### Логика эталонных фото:
```
Вопрос с типом "photo" + referencePhotos[магазин] = URL
    ↓
При фотографировании показывается эталонное фото
    ↓
В ответ сохраняется:
  - photoPath: локальный путь к фото сотрудника
  - photoDriveId: URL загруженного фото сотрудника на сервере
  - referencePhotoUrl: URL эталонного фото для сравнения
```

---

### 3. Отчёты по пересменкам (Администратор)

#### Функционал:
- 4 вкладки: Не пройдены | Ожидают | Подтверждённые | Не подтверждённые
- Фильтрация по магазину
- Просмотр ответов с фото (фото сотрудника + эталонное фото рядом)
- Подтверждение отчёта с оценкой (1-10)
- Автоматическое просрочивание в 00:00

#### Защищённые файлы:

| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/shifts/pages/shift_reports_list_page.dart` | 4 вкладки, фильтр по магазину, списки отчётов, isExpanded в DropdownButtonFormField | ✅ Работает |
| `lib/features/shifts/pages/shift_report_view_page.dart` | Просмотр ответов, сравнение фото (сотрудник vs эталон), подтверждение с оценкой, блок "Отчет просрочен" | ✅ Работает |
| `lib/features/shifts/services/shift_report_service.dart` | saveReport, updateReport, getReports, getExpiredReports | ✅ Работает |
| `lib/features/shifts/services/pending_shift_service.dart` | getPendingReports (магазины без отчётов сегодня) | ✅ Работает |
| `lib/features/shifts/models/pending_shift_report_model.dart` | Модель непройденной пересменки | ✅ Работает |

#### Вкладки отчётов:
| Вкладка | Описание | Действия |
|---------|----------|----------|
| Не пройдены | Магазины без отчётов сегодня | Только просмотр |
| Ожидают | Отчёты < 24ч без подтверждения | Просмотр, Подтверждение с оценкой |
| Подтверждённые | Отчёты с confirmedAt | Просмотр |
| Не подтверждённые | Просроченные (status=expired) | Только просмотр |

#### API Endpoints:
| Endpoint | Метод | Статус |
|----------|-------|--------|
| `/api/shift-reports` | GET | ✅ Получение отчётов (фильтры: employeeName, shopAddress, date) |
| `/api/shift-reports` | POST | ✅ Сохранение отчёта |
| `/api/shift-reports/:id` | PUT | ✅ Обновление отчёта (подтверждение) |
| `/api/shift-reports/expired` | GET | ✅ Получение просроченных отчётов |
| `/api/pending-shift-reports` | GET | ✅ Непройденные пересменки за сегодня |
| `/api/pending-shift-reports/generate` | POST | ✅ Генерация непройденных (ручной вызов) |

---

### Серверная часть (index.js):

| Функция | Описание | Статус |
|---------|----------|--------|
| `checkExpiredShiftReports()` | Помечает отчёты как expired если createdAt < сегодня | ✅ Работает |
| `generateDailyPendingShifts()` | Генерирует список непройденных пересменок на день | ✅ Работает |
| `completePendingShift()` | Закрывает pending при сдаче отчёта | ✅ Работает |
| Cron `0 0 * * *` | В 00:00 по Москве: проверка просроченных | ✅ Работает |
| Cron `0 0 * * *` | В 00:00 по Москве: генерация pending на новый день | ✅ Работает |

### Хранение данных:
| Директория | Содержимое |
|------------|------------|
| `/var/www/shift-reports/` | JSON файлы отчётов пересменки |
| `/var/www/shift-questions/` | JSON файлы вопросов |
| `/var/www/pending-shift-reports/` | JSON файлы непройденных пересменок |
| `/var/www/shift-photos/` | Фото сотрудников и эталонные фото |

### Логика просрочивания:
```
Отчёт создан (createdAt: YYYY-MM-DD)
    ├── Подтверждён до 00:00 следующего дня → confirmedAt: DateTime
    └── НЕ подтверждён → Cron в 00:00 → status: "expired", expiredAt: DateTime
```

### Логика непройденных пересменок:
```
Каждый день в 00:00:
  1. Удаляются файлы за предыдущие дни
  2. Генерируются pending для каждого магазина (утро + вечер)

При сдаче отчёта:
  completePendingShift() помечает соответствующий pending как completed
```

---

## Система пересчётов (v1.5.4) - Проверено: 03.01.2026

### Общее описание:
Полная система управления пересчётами товаров: создание вопросов, прохождение пересчёта сотрудниками, просмотр и оценка отчётов администратором.

---

### 1. Вопросы пересчёта (Управление)

#### Функционал:
- Создание/редактирование/удаление вопросов пересчёта
- Грейды вопросов (1, 2, 3) - определяют приоритет/важность
- Опция "Требуется фото" для каждого вопроса
- Вопросы применяются ко всем магазинам

#### Защищённые файлы:

| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/recount/pages/recount_questions_management_page.dart` | CRUD вопросов, грейды, фото опция | ✅ Работает |
| `lib/features/recount/models/recount_question_model.dart` | Модель вопроса: id, question, grade, photoRequired | ✅ Работает |
| `lib/features/recount/services/recount_question_service.dart` | getQuestions, createQuestion, updateQuestion, deleteQuestion | ✅ Работает |

#### API Endpoints:
| Endpoint | Метод | Статус |
|----------|-------|--------|
| `/api/recount-questions` | GET | ✅ Получение вопросов |
| `/api/recount-questions` | POST | ✅ Создание вопроса |
| `/api/recount-questions/:id` | PUT | ✅ Обновление вопроса |
| `/api/recount-questions/:id` | DELETE | ✅ Удаление вопроса |

---

### 2. Прохождение пересчёта (Сотрудник)

#### Функционал:
- Выбор магазина перед началом пересчёта
- Пошаговое прохождение вопросов с таймером
- Ответы: "Сходится" (количество) или "Не сходится" (остаток программа/факт/разница)
- Фотографирование для вопросов с флагом photoRequired
- Автоматическая загрузка фото на сервер
- Подсчёт времени прохождения пересчёта

#### Защищённые файлы:

| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/recount/pages/recount_shop_selection_page.dart` | Выбор магазина, проверка авторизации | ✅ Работает |
| `lib/features/recount/pages/recount_questions_page.dart` | UI прохождения: вопросы пошагово, ответы, фото, таймер | ✅ Работает |
| `lib/features/recount/models/recount_report_model.dart` | RecountReport, RecountAnswer (question, answer, quantity, programBalance, actualBalance, difference, photoUrl) | ✅ Работает |

#### Логика ответов на вопрос:
```
Вопрос пересчёта
    ├── "Сходится" → вводится quantity
    └── "Не сходится" → вводятся:
        - programBalance (остаток по программе)
        - actualBalance (фактический остаток)
        - difference (авто-расчёт: actualBalance - programBalance)

Если photoRequired = true:
    → Открывается камера
    → Фото загружается на сервер
    → photoUrl сохраняется в ответе
```

---

### 3. Отчёты по пересчётам (Администратор)

#### Функционал:
- 4 вкладки: Не пройдены | Ожидают | Оценённые | Не оценённые
- Фильтрация по магазину
- Просмотр ответов с фото
- Оценка отчёта (1-10)
- Автоматическое просрочивание в 00:00

#### Защищённые файлы:

| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/recount/pages/recount_reports_list_page.dart` | 4 вкладки, фильтр по магазину, реальные магазины из API | ✅ Работает |
| `lib/features/recount/pages/recount_report_view_page.dart` | Просмотр ответов, фото, оценка 1-10, блок "Отчёт просрочен" | ✅ Работает |
| `lib/features/recount/services/recount_service.dart` | getReports, rateReport, getExpiredReports | ✅ Работает |
| `lib/features/recount/models/recount_report_model.dart` | RecountReport: status, expiredAt, isExpired, adminRating, ratedAt | ✅ Работает |

#### Вкладки отчётов:
| Вкладка | Описание | Действия |
|---------|----------|----------|
| Не пройдены | Магазины из API без пересчётов сегодня | Только просмотр |
| Ожидают | Отчёты < 24ч без оценки | Просмотр, Оценка 1-10 |
| Оценённые | Отчёты с ratedAt | Просмотр |
| Не оценённые | Просроченные (status=expired) | Только просмотр, блок "Отчёт просрочен" |

#### Логика вкладки "Не пройдены":
```
1. Загружаются все магазины из Shop.loadShopsFromGoogleSheets()
2. Загружаются все отчёты за сегодня
3. Вычисляются магазины БЕЗ отчётов:
   _pendingShops = _allShops.where((shop) =>
     !shopsWithRecountToday.contains(shop.address)
   ).toList()
```

### API Endpoints:
| Endpoint | Метод | Статус |
|----------|-------|--------|
| `/api/recount-reports` | GET | ✅ Получение отчётов |
| `/api/recount-reports` | POST | ✅ Создание отчёта |
| `/api/recount-reports/:id/rating` | POST | ✅ Оценка отчёта |
| `/api/recount-reports/expired` | GET | ✅ Просроченные отчёты |
| `/api/pending-recount-reports` | GET | ✅ Непройденные за сегодня |
| `/api/pending-recount-reports/generate` | POST | ✅ Генерация (ручной вызов) |

### Серверная часть (index.js):
| Функция | Описание | Статус |
|---------|----------|--------|
| `generateDailyPendingRecounts()` | Генерирует pending для каждого магазина | ✅ Работает |
| `checkExpiredRecountReports()` | Помечает отчёты как expired | ✅ Работает |
| `completePendingRecount()` | Закрывает pending при сдаче отчёта | ✅ Работает |
| Cron `0 0 * * *` | В 00:00 по Москве: генерация + проверка просрочки | ✅ Работает |

### Хранение данных:
| Директория | Содержимое |
|------------|------------|
| `/var/www/recount-reports/` | JSON файлы отчётов пересчёта |
| `/var/www/pending-recount-reports/` | JSON файлы непройденных пересчётов |
| `/var/www/recount-questions/` | JSON файлы вопросов |

### Логика просрочивания:
```
Отчёт создан (completedAt: YYYY-MM-DD)
    ├── Оценён до 00:00 следующего дня → ratedAt: DateTime
    └── НЕ оценён → Cron в 00:00 → status: "expired", expiredAt: DateTime
```

### Логика непройденных пересчётов:
```
Каждый день в 00:00:
  1. Удаляются файлы за предыдущие дни
  2. Генерируются pending для каждого магазина

При сдаче отчёта:
  completePendingRecount() помечает соответствующий pending как completed
```

---

## Статьи обучения (v1.5.5) - Проверено: 03.01.2026

### Общее описание:
Система управления обучающими статьями для сотрудников: добавление, редактирование, удаление статей с группировкой по категориям.

---

### Функционал:
- Добавление статей: наименование, группа, ссылка
- Редактирование и удаление статей
- Группировка статей по категориям
- Открытие ссылок во внешнем браузере
- Белый цвет названий групп на тёмном фоне

### Защищённые файлы:

| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/training/pages/training_articles_management_page.dart` | CRUD статей, группировка, открытие ссылок, белые заголовки групп | ✅ Работает |
| `lib/features/training/pages/training_page.dart` | Отображение статей для сотрудников | ✅ Работает |
| `lib/features/training/models/training_model.dart` | Модель статьи: id, group, title, url | ✅ Работает |
| `lib/features/training/services/training_article_service.dart` | getArticles, createArticle, updateArticle, deleteArticle | ✅ Работает |

### AndroidManifest.xml:
```xml
<queries>
    <!-- Required for url_launcher to open URLs in browser -->
    <intent>
        <action android:name="android.intent.action.VIEW"/>
        <data android:scheme="https"/>
    </intent>
    <intent>
        <action android:name="android.intent.action.VIEW"/>
        <data android:scheme="http"/>
    </intent>
</queries>
```

### API Endpoints:
| Endpoint | Метод | Статус |
|----------|-------|--------|
| `/api/training-articles` | GET | ✅ Получение статей |
| `/api/training-articles` | POST | ✅ Создание статьи |
| `/api/training-articles/:id` | PUT | ✅ Обновление статьи |
| `/api/training-articles/:id` | DELETE | ✅ Удаление статьи |

### Стилизация:
| Элемент | Стиль |
|---------|-------|
| Название группы | fontSize: 20, fontWeight: bold, color: Colors.white |
| Фон страницы | arabica_background.png с opacity 0.6 на Color(0xFF004D40) |
| Карточки статей | Card с elevation: 2, иконка Icons.article |

---

## Мои диалоги (v1.6.0) - Проверено: 26.01.2026

### Общее описание:
Централизованная страница для клиента, объединяющая все типы диалогов: сетевые сообщения, связь с руководством, отзывы, поиск товара (общий и персональные диалоги). Включает единый счётчик непрочитанных сообщений.

---

### Функционал:
- 5 типов диалогов на одной странице
- Единый счётчик непрочитанных (MyDialogsCounterService)
- Сетевые сообщения (broadcast и личные)
- Связь с руководством (клиент↔админ)
- Интеграция с отзывами клиента
- Интеграция с поиском товара (общий диалог + персональные)
- Push-уведомления для всех типов сообщений
- Флаги непрочитанности (isReadByClient, isReadByAdmin, isReadByManager)

---

### Защищённые файлы:

#### Страницы
| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/app/pages/my_dialogs_page.dart` | Главная страница "Мои диалоги", 5 карточек типов диалогов | ✅ Работает |
| `lib/features/clients/pages/network_dialog_page.dart` | Диалог сетевых сообщений (клиент) | ✅ Работает |
| `lib/features/clients/pages/management_dialog_page.dart` | Диалог с руководством (клиент) | ✅ Работает |
| `lib/features/clients/pages/admin_management_dialog_page.dart` | Диалог с клиентом (админ) | ✅ Работает |
| `lib/features/clients/pages/management_dialogs_list_page.dart` | Список диалогов с клиентами (админ) | ✅ Работает |

#### Модели
| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/clients/models/network_message_model.dart` | NetworkMessage, NetworkDialogData | ✅ Работает |
| `lib/features/clients/models/management_message_model.dart` | ManagementMessage, ManagementDialogData | ✅ Работает |

#### Сервисы
| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/app/services/my_dialogs_counter_service.dart` | getTotalUnreadCount() - подсчёт всех непрочитанных | ✅ Работает |
| `lib/features/clients/services/network_message_service.dart` | getNetworkMessages, sendMessage, markAsRead | ✅ Работает |
| `lib/features/clients/services/management_message_service.dart` | getManagementMessages, sendMessage, sendManagerMessage, markAsRead | ✅ Работает |

---

### API Endpoints:

#### Сетевые сообщения
| Endpoint | Метод | Статус |
|----------|-------|--------|
| `/api/client-dialogs/:phone/network` | GET | ✅ Получение сетевых сообщений |
| `/api/client-dialogs/:phone/network/reply` | POST | ✅ Ответ клиента на сетевое сообщение |
| `/api/client-dialogs/:phone/network/read-by-client` | POST | ✅ Отметить как прочитанное |
| `/api/client-dialogs/network/broadcast` | POST | ✅ Broadcast всем клиентам |

#### Связь с руководством
| Endpoint | Метод | Статус |
|----------|-------|--------|
| `/api/client-dialogs/:phone/management` | GET | ✅ Получение диалога с руководством |
| `/api/client-dialogs/:phone/management/reply` | POST | ✅ Сообщение от клиента руководству |
| `/api/client-dialogs/:phone/management/send` | POST | ✅ Ответ от руководства клиенту |
| `/api/client-dialogs/:phone/management/read-by-client` | POST | ✅ Отметить как прочитанное (клиент) |
| `/api/client-dialogs/:phone/management/read-by-manager` | POST | ✅ Отметить как прочитанное (админ) |
| `/api/client-dialogs/management/list` | GET | ✅ Список всех диалогов (админ) |

---

### Серверная часть:

| Файл | Функционал | Статус |
|------|------------|--------|
| `loyalty-proxy/api/clients_api.js` | Все endpoints для network/management диалогов | ✅ Работает |

---

### Хранение данных:
| Директория | Содержимое |
|------------|------------|
| `/var/www/client-messages/network/` | Сетевые сообщения по клиентам |
| `/var/www/client-messages/management/` | Диалоги с руководством по клиентам |

---

### Логика счётчика:
```
MyDialogsCounterService.getTotalUnreadCount()
    ├── NetworkMessageService → unreadCount
    ├── ManagementMessageService → unreadCount
    ├── ReviewService → getUnreadCountForClient()
    ├── ProductQuestionService (общий) → unreadCount
    └── ProductQuestionService (персональные) → hasUnreadFromEmployee

Итого: sum(все непрочитанные) → Бейдж на кнопке "Мои диалоги"
```

---

### Push-уведомления:
| Тип | Получатель | Payload.type |
|-----|------------|--------------|
| Broadcast всем | Все клиенты | `'network_broadcast'` |
| Ответ админа (сетевое) | Клиент | `'network_message'` |
| Ответ клиента (сетевое) | Админы | `'network_message'` |
| Ответ руководства | Клиент | `'management_message'` |
| Сообщение клиента руководству | Админы | `'management_message'` |

---

## Поиск товара (v1.6.1) - Проверено: 26.01.2026

### Общее описание:
Система для клиентов по поиску товаров в сети кофеен с возможностью задать вопрос конкретному магазину, всей сети или продолжить персональный диалог. Включает автоматическое начисление баллов за ответы, штрафы за неответы и scheduler для проверки просроченных вопросов.

---

### Функционал:
- 3 типа вопросов: конкретному магазину, всей сети, персональные диалоги
- Автоматическое начисление баллов за своевременные ответы (+0.2 по умолчанию)
- Автоматические штрафы за неответы (-3 по умолчанию)
- Настраиваемый таймаут ответа (5-60 минут, по умолчанию 30)
- Scheduler проверки просроченных вопросов (каждые 5 минут)
- Broadcast push-уведомлений всем сотрудникам
- Приоритет персональных диалогов над общими вопросами
- Интеграция с модулем Эффективность (баллы)
- Дедупликация начисления баллов через sourceId

---

### Защищённые файлы:

#### Страницы (Клиент)
| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/product_questions/pages/product_search_shop_selection_page.dart` | Выбор магазина или "Вся сеть" | ✅ Работает |
| `lib/features/product_questions/pages/product_question_input_page.dart` | Ввод текста вопроса + фото | ✅ Работает |
| `lib/features/product_questions/pages/product_question_client_dialog_page.dart` | Общий диалог всех вопросов клиента | ✅ Работает |
| `lib/features/product_questions/pages/product_question_personal_dialog_page.dart` | Персональный диалог с магазином | ✅ Работает |

#### Страницы (Сотрудник)
| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/product_questions/pages/product_question_shops_list_page.dart` | Список магазинов с приоритетом персональных диалогов | ✅ Работает |
| `lib/features/product_questions/pages/product_question_dialog_page.dart` | Просмотр и ответ на общий вопрос | ✅ Работает |
| `lib/features/product_questions/pages/product_question_employee_dialog_page.dart` | Диалог сотрудника | ✅ Работает |

#### Страницы (Админ)
| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/product_questions/pages/product_questions_management_page.dart` | Управление вопросами | ✅ Работает |
| `lib/features/product_questions/pages/product_questions_report_page.dart` | Статистика вопросов | ✅ Работает |
| `lib/features/efficiency/pages/settings_tabs/product_search_points_settings_page.dart` | Настройки баллов и таймаута | ✅ Работает |

#### Модели
| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/product_questions/models/product_question_model.dart` | ProductQuestion, PersonalProductDialog, ProductQuestionShopGroup | ✅ Работает |
| `lib/features/product_questions/models/product_question_message_model.dart` | ProductQuestionMessage | ✅ Работает |

#### Сервисы
| Файл | Функционал | Статус |
|------|------------|--------|
| `lib/features/product_questions/services/product_question_service.dart` | CRUD вопросов, персональных диалогов, группировка | ✅ Работает |

---

### API Endpoints:

#### Вопросы
| Endpoint | Метод | Статус |
|----------|-------|--------|
| `/api/product-questions` | GET | ✅ Получить все вопросы |
| `/api/product-questions` | POST | ✅ Создать вопрос |
| `/api/product-questions/client/:phone` | GET | ✅ Вопросы клиента (общий диалог) |
| `/api/product-questions/:id` | GET | ✅ Получить конкретный вопрос |
| `/api/product-questions/:id/messages` | POST | ✅ Ответить на вопрос (с начислением баллов) |
| `/api/product-questions/:id/mark-answered` | POST | ✅ Пометить как отвеченный |

#### Персональные диалоги
| Endpoint | Метод | Статус |
|----------|-------|--------|
| `/api/product-question-dialogs/all` | GET | ✅ Все персональные диалоги |
| `/api/product-question-dialogs/client/:phone` | GET | ✅ Персональные диалоги клиента |
| `/api/product-question-dialogs/:id` | GET | ✅ Получить диалог |
| `/api/product-question-dialogs/:id/messages` | POST | ✅ Отправить сообщение в диалог |
| `/api/product-question-dialogs/:id/read-by-client` | POST | ✅ Отметить как прочитанное (клиент) |
| `/api/product-question-dialogs/:id/read-by-employee` | POST | ✅ Отметить как прочитанное (сотрудник) |

#### Группировка
| Endpoint | Метод | Статус |
|----------|-------|--------|
| `/api/product-questions/grouped-by-shop` | GET | ✅ Вопросы + диалоги, группированные по магазинам |

---

### Серверная часть:

| Файл | Функционал | Статус |
|------|------------|--------|
| `loyalty-proxy/api/product_questions_api.js` | Все endpoints, начисление баллов при ответе (assignAnswerBonus) | ✅ Работает |
| `loyalty-proxy/api/product_questions_notifications.js` | Push-уведомления (broadcast сотрудникам, персональные клиенту) | ✅ Работает |
| `loyalty-proxy/product_questions_penalty_scheduler.js` | Cron каждые 5 минут: проверка просроченных, начисление штрафов | ✅ Работает |

---

### Хранение данных:
| Директория | Содержимое |
|------------|------------|
| `/var/www/product-questions/` | JSON файлы общих вопросов |
| `/var/www/product-question-dialogs/` | JSON файлы персональных диалогов |
| `/var/www/efficiency-penalties/{YYYY-MM}.json` | Баллы и штрафы за месяц |
| `/var/www/points-settings/product_search_points_settings.json` | Настройки баллов и таймаута |

---

### Настройки баллов:
| Параметр | По умолчанию | Описание |
|----------|--------------|----------|
| `answeredPoints` | +0.2 | Баллы за своевременный ответ |
| `notAnsweredPoints` | -3.0 | Штраф за неответ |
| `answerTimeoutMinutes` | 30 | Таймаут в минутах |

---

### Функции начисления баллов:

#### assignAnswerBonus() (в product_questions_api.js)
```javascript
// Вызывается при ответе сотрудника
// Проверяет: questionAge <= answerTimeoutMinutes
// Начисляет: +answeredPoints (например, +0.2)
// Дедупликация: sourceId = "pq_answer_{questionId}"
// Записывает в: /var/www/efficiency-penalties/{YYYY-MM}.json
```

#### assignPenalty() (в product_questions_penalty_scheduler.js)
```javascript
// Вызывается scheduler каждые 5 минут
// Проверяет: !isAnswered && !penalized && ageMinutes >= answerTimeoutMinutes
// Начисляет: notAnsweredPoints (например, -3)
// Дедупликация: sourceId = "pq_timeout_{questionId}"
// Помечает: question.penalized = true
// Записывает в: /var/www/efficiency-penalties/{YYYY-MM}.json
```

---

### Scheduler (Cron каждые 5 минут):
```
Файл: product_questions_penalty_scheduler.js

Логика:
1. Загрузить все вопросы из /var/www/product-questions/
2. Загрузить настройки из product_search_points_settings.json
3. Для каждого вопроса:
   - Если !isAnswered && !penalized
   - Вычислить возраст: (now - timestamp) / 60000 минут
   - Если возраст >= answerTimeoutMinutes:
     → assignPenalty() → штраф магазину
     → question.penalized = true
     → sendPushNotification() → всем сотрудникам
4. Сохранить изменённые вопросы
```

---

### Push-уведомления:
| Событие | Получатель | Payload.type | Функция |
|---------|------------|--------------|---------|
| Новый вопрос | Все сотрудники | `'product_question'` | `notifyEmployeesAboutNewQuestion()` |
| Ответ сотрудника | Клиент | `'product_question_answer'` | `notifyClientAboutAnswer()` |
| Сообщение клиента (персональный) | Все сотрудники | `'personal_dialog_client_message'` | `notifyPersonalDialogClientMessage()` |
| Сообщение сотрудника (персональный) | Клиент | `'personal_dialog_employee_message'` | `notifyPersonalDialogEmployeeMessage()` |
| Штраф за неответ | Все сотрудники | `'product_question_penalty'` | Scheduler → broadcast |

---

### Критические особенности:

1. **Broadcast уведомлений:**
   - Все уведомления сотрудникам отправляются broadcast (всем, независимо от магазина)
   - Любой сотрудник может ответить на вопрос

2. **Приоритет персональных диалогов:**
   - На `ShopsListPage` сотрудник видит список магазинов
   - При клике: сначала проверка персональных диалогов → если есть, открыть → иначе открыть общий вопрос

3. **Автоматическое начисление баллов:**
   - Бонус начисляется сразу при ответе (если в рамках таймаута)
   - Штраф начисляется scheduler'ом каждые 5 минут
   - Дедупликация через `sourceId` предотвращает повторное начисление

4. **Динамический таймаут:**
   - Админ может настроить таймаут в UI (5-60 минут)
   - Scheduler динамически загружает настройки из файла при каждом запуске

---

### Интеграция с модулем Эффективность:
```
Категории баллов:
  - product_question_bonus (+0.2 по умолчанию)
  - product_question_penalty (-3 по умолчанию)

Запись в файл:
  /var/www/efficiency-penalties/{YYYY-MM}.json

Структура записи:
  {
    "id": "bonus_pq_123",
    "type": "employee",
    "entityId": "79054443224",
    "entityName": "Мария",
    "shopAddress": "ул. Ленина, 1",
    "category": "product_question_bonus",
    "categoryName": "Ответ на вопрос о товаре",
    "points": 0.2,
    "reason": "Ответил на вопрос за 15 минут",
    "sourceId": "pq_answer_pq_123",
    "sourceType": "question_answer",
    "date": "2026-01-26",
    "createdAt": "2026-01-26T12:00:00Z"
  }
```

---

**Git тег для отката:** `v1.5.0`

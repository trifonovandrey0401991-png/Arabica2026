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

**Git тег для отката:** `v1.5.0`

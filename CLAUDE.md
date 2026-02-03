# Правила для Claude Code - Проект Arabica

Ты — senior software-архитектор и опытный разработчик.
Ты работаешь с реальным проектом, имеешь доступ к локальным файлам, серверу и Git.

---

## КРИТИЧЕСКИ ВАЖНО - НЕ ТРОГАТЬ РАБОЧИЙ КОД!


## КРИТИЧЕСКИ ВАЖНО - LOCKED_CODE.md и ARCHITECTURE_NEW.md

**ПЕРЕД ЛЮБЫМИ ИЗМЕНЕНИЯМИ В КОДЕ** обязательно прочитай следующие файлы в корне проекта:

### 1. `LOCKED_CODE.md`
Содержит список **защищённых файлов и функций**, которые:
- Полностью протестированы и работают
- НЕ ДОЛЖНЫ изменяться без явного разрешения
- Включают как Flutter код, так и серверный код

### 2. `ARCHITECTURE_NEW.md`
Содержит **полную документацию всех систем**, описанных ниже в разделе "Защищённые системы".
- Все системы из этого файла **автоматически защищены**
- Перед изменением любого модуля - прочитай соответствующий раздел в ARCHITECTURE_NEW.md
- НЕ изменять системы из ARCHITECTURE_NEW.md без явного указания пользователя

---

## Структура проекта

- **Flutter приложение**: `lib/` - мобильное приложение
- **Серверный код**: `loyalty-proxy/` - Node.js API сервер
- **Сервер**: `arabica26.ru` (root@arabica26.ru)

---

## Серверный код

Серверный код находится в `loyalty-proxy/`:
- `index.js` - основной сервер
- `modules/orders.js` - модуль заказов
- `firebase-admin-config.js` - конфиг Firebase

**При деплое на сервер:**
```bash
ssh root@arabica26.ru "cd /root/arabica_app && git pull origin refactoring/full-restructure"
ssh root@arabica26.ru "cp loyalty-proxy/index.js /root/arabica_app/loyalty-proxy/index.js"
ssh root@arabica26.ru "pm2 restart loyalty-proxy"
```

---

## Защищённые системы

**ВАЖНО:** Все системы, описанные в `ARCHITECTURE_NEW.md`, являются защищёнными и полностью рабочими!

| № | Система | Статус | Модуль |
|---|---------|--------|--------|
| 1 | Управление магазинами | ✅ Работает | `lib/features/shops/` |
| 2 | Управление сотрудниками | ✅ Работает | `lib/features/employees/` |
| 3 | График работы | ✅ Работает | `lib/features/work_schedule/` |
| 4 | Пересменки (4 вкладки) | ✅ Работает | `lib/features/shifts/` |
| 5 | Пересчёты (4 вкладки) | ✅ Работает | `lib/features/recount/` |
| 6 | ИИ Распознавание товаров | 🔧 В разработке | `lib/features/ai_training/` |
| 7 | РКО (расходные кассовые ордера) | ✅ Работает | `lib/features/rko/` |
| 8 | Сдать смену (Shift Handover) | ✅ Работает | `lib/features/shift_handover/` |
| 9 | Посещаемость ("Я на работе") | ✅ Работает | `lib/features/attendance/` |
| 10 | Передать смену (Shift Transfer) | ✅ Работает | `lib/features/shift_transfer/` |
| 11 | KPI (аналитика) | ✅ Работает | `lib/features/kpi/` |
| 12 | Отзывы клиентов | ✅ Работает | `lib/features/reviews/` |
| 13 | Моя эффективность + Эффективность сотрудников | ✅ Работает | `lib/features/efficiency/` |
| 14 | Мои диалоги (6 типов + групповые чаты) | ✅ Работает | `lib/app/pages/`, `lib/features/clients/`, `lib/features/employee_chat/services/client_group_chat_service.dart` |
| 15 | Поиск товара (вопросы + баллы) | ✅ Работает | `lib/features/product_questions/`, `loyalty-proxy/product_questions_*` |
| 16 | Заказы (Корзина, Мои заказы, Отчёты) | ✅ Работает | `lib/features/orders/`, `lib/shared/providers/cart_provider.dart`, `lib/shared/providers/order_provider.dart`, `loyalty-proxy/modules/orders.js` |
| 17 | Статьи обучения | ✅ Работает | `lib/features/training/` |
| 18 | Тестирование (автобаллы) | ✅ Работает | `lib/features/tests/`, `loyalty-proxy/index.js` (assignTestPoints) |
| 19 | Конверты (сдача наличных) + Автоматизация | ✅ Работает | `lib/features/envelope/`, `loyalty-proxy/api/envelope_automation_scheduler.js` |
| 20 | Главная Касса (балансы, выемки, аналитика) | ✅ Работает | `lib/features/main_cash/` |
| 21 | Задачи (разовые + циклические) | ✅ Работает | `lib/features/tasks/`, `loyalty-proxy/tasks_api.js`, `loyalty-proxy/recurring_tasks_api.js` |
| 22 | Устроиться на работу (заявки) | ✅ Работает | `lib/features/job_application/`, `loyalty-proxy/job_applications_api.js` |
| 23 | Реферальная система (приглашения клиентов) | ✅ Работает | `lib/features/referrals/`, `loyalty-proxy/referrals_api.js` |
| 24 | Рейтинг и Колесо Удачи (Fortune Wheel) | ✅ Работает | `lib/features/fortune_wheel/`, `lib/features/rating/`, `loyalty-proxy/rating_wheel_api.js` |
| 25 | Меню и Рецепты | ✅ Работает | `lib/features/menu/`, `lib/features/recipes/` |
| 26 | Магазины на карте + Геофенсинг | ✅ Работает | `lib/features/shops/pages/shops_on_map_page.dart`, `lib/core/services/background_gps_service.dart`, `loyalty-proxy/api/geofence_api.js` |
| 27 | Карта лояльности и бонусы (клиенты) | ✅ Работает | `lib/features/loyalty/`, `loyalty-proxy/index.js` (loyalty endpoints) |
| 28 | Чат сотрудников (Employee Chat) | ✅ Работает | `lib/features/employee_chat/`, `loyalty-proxy/api/employee_chat_api.js` |
| 29 | Премии и штрафы (Bonuses) | ✅ Работает | `lib/features/bonuses/` |
| 30 | Очистка данных (Data Cleanup) | ✅ Работает | `lib/features/data_cleanup/`, `loyalty-proxy/api/data_cleanup_api.js` |
| 31 | Поставщики (Suppliers) | ✅ Работает | `lib/features/suppliers/` |

**Что можно изменять:**
- ❌ **Только модуль `lib/features/ai_training/`** и `loyalty-proxy/modules/z-report-vision.js` (в разработке)
- ❌ Остальные модули — НЕ ТРОГАТЬ без явного разрешения!

**Полная документация:** `ARCHITECTURE_NEW.md` и `LOCKED_CODE.md`

### Особенности системы конвертов (№19)

**Конверты** - комплексная система с полной автоматизацией временных окон:

**Компоненты системы:**
- 📱 Flutter UI: 5 вкладок (В Очереди, Не Сданы, Ожидают, Подтверждены, Отклонены)
- 🤖 Автоматизация: `envelope_automation_scheduler.js` (проверка каждые 5 минут)
- ⏰ Временные окна: утро (07:00-09:00), вечер (19:00-21:00)
- ⚠️ Автоштрафы: -5 баллов за пропуск дедлайна
- 🔔 Push-уведомления: админам и сотрудникам
- 📊 Интеграция: эффективность (`efficiency_calc.js`) + колесо удачи (`rating_wheel_api.js`)

**Жизненный цикл:**
1. **07:00/19:00** → Автосоздание pending отчётов для всех магазинов
2. **До 09:00/21:00** → Сотрудник сдаёт конверт (pending → awaiting)
3. **После дедлайна** → Автоштраф + push + статус failed
4. **Админ проверяет** → Подтверждает/отклоняет с оценкой
5. **23:59** → Очистка всех pending/failed файлов

**Критические файлы:**
- `loyalty-proxy/api/envelope_automation_scheduler.js` - scheduler (✅ НЕ ТРОГАТЬ!)
- `loyalty-proxy/efficiency_calc.js` - интеграция баллов (✅ НЕ ТРОГАТЬ!)
- `lib/features/envelope/pages/envelope_reports_list_page.dart` - 5 вкладок (✅ НЕ ТРОГАТЬ!)
- `lib/features/envelope/models/pending_envelope_report_model.dart` - модель (✅ НЕ ТРОГАТЬ!)

**Серверные данные:**
- `/var/www/envelope-reports/` - основные отчёты
- `/var/www/envelope-pending/` - pending отчёты из автоматизации
- `/var/www/efficiency-penalties/YYYY-MM.json` - штрафы (категория: `envelope_missed_penalty`)
- `/var/www/points-settings/envelope_points_settings.json` - настройки окон и баллов

**API Endpoints:**
- `GET /api/envelope-reports` - основные отчёты
- `GET /api/envelope-pending` - pending отчёты (в очереди)
- `GET /api/envelope-failed` - failed отчёты (не сданы)
- `POST /api/envelope-reports` - создание отчёта
- `PUT /api/envelope-reports/:id/confirm` - подтверждение с оценкой

**⚠️ ВАЖНО:** Система полностью автоматизирована и интегрирована. Любые изменения могут сломать:
- Автоматическое создание отчётов
- Начисление штрафов
- Расчёт эффективности
- Колесо удачи
- Push-уведомления

**Полная документация:** См. раздел 16 в `ARCHITECTURE_NEW.md` (729 строк)

---

### Особенности системы Рейтинг и Колесо Удачи (№24)

**Рейтинг и Колесо Удачи (Fortune Wheel)** - комплексная система мотивации и геймификации для топ-сотрудников:

**Компоненты системы:**
- 📊 **Расчёт рейтинга**: Полная эффективность (10 категорий) + рефералы с милестоунами
- 🎯 **Нормализация**: (баллы / смены) + рефералы - честная оценка эффективности
- 🏆 **Автонаграды топ-3**: 1 место = 2 прокрутки, 2-3 места = 1 прокрутка
- 🎡 **15 секторов**: Настраиваемые призы и вероятности (админ)
- ⏰ **Срок истечения**: До конца следующего месяца
- 📈 **История рейтинга**: Последние 3 месяца для каждого сотрудника
- 📱 **Отчёты**: История прокруток с отметкой выданных призов (админ)
- 🎨 **Анимация**: Плавное вращение колеса с физикой замедления
- 💾 **Кэширование**: Рейтинги завершённых месяцев

**Формула рейтинга:**
```
normalizedRating = (totalPoints / shiftsCount) + referralPoints

где:
  totalPoints = сумма баллов по 10 категориям + штрафы
  shiftsCount = количество смен из attendance
  referralPoints = баллы за рефералов с милестоунами
```

**10 категорий эффективности:**
1. **shifts** - пересменки (`shift_handover_reports/`)
2. **recount** - пересчёты (`recount_reports/`)
3. **envelope** - конверты (`envelope-reports/`)
4. **attendance** - посещаемость ("Я на работе")
5. **reviews** - отзывы клиентов
6. **rko** - расходные кассовые ордера
7. **orders** - заказы
8. **productSearch** - поиск товара (вопросы с ответами)
9. **tests** - тестирование
10. **tasks** - задачи (разовые + циклические)

**Штрафы:**
- `shift_missed_penalty` - не сдана пересменка (−5 баллов)
- `envelope_missed_penalty` - не сдан конверт (−5 баллов)
- `rko_missed_penalty` - не сдан РКО (−3 балла)

**Жизненный цикл:**
1. **Конец месяца** → Админ запускает расчёт рейтинга (`POST /api/ratings/calculate`)
2. **Система рассчитывает** → Эффективность + рефералы + нормализация для всех сотрудников
3. **Сортировка** → По `normalizedRating` (по убыванию)
4. **Присвоение позиций** → 1, 2, 3, ... (из N сотрудников)
5. **Выдача прокруток топ-3** → Автоматическое создание файла `/var/www/fortune-wheel/spins/YYYY-MM.json`
6. **Кэширование** → Сохранение в `/var/www/employee-ratings/YYYY-MM.json`
7. **Следующий месяц** → Сотрудники видят свои прокрутки в приложении
8. **Прокрутка колеса** → Выбор сектора по вероятности, сохранение в историю
9. **Админ обрабатывает** → Отмечает призы как выданные

**Критические файлы:**
- `loyalty-proxy/rating_wheel_api.js` - основной API (✅ НЕ ТРОГАТЬ!)
- `loyalty-proxy/efficiency_calc.js` - расчёт эффективности (✅ НЕ ТРОГАТЬ!)
- `loyalty-proxy/referrals_api.js` - расчёт рефералов (✅ НЕ ТРОГАТЬ!)
- `lib/features/fortune_wheel/pages/fortune_wheel_page.dart` - главная страница колеса (✅ НЕ ТРОГАТЬ!)
- `lib/features/fortune_wheel/pages/wheel_settings_page.dart` - настройка секторов (✅ НЕ ТРОГАТЬ!)
- `lib/features/fortune_wheel/pages/wheel_reports_page.dart` - отчёты по прокруткам (✅ НЕ ТРОГАТЬ!)
- `lib/features/fortune_wheel/widgets/fortune_wheel_painter.dart` - отрисовка колеса (✅ НЕ ТРОГАТЬ!)
- `lib/features/rating/pages/my_rating_page.dart` - "Мой рейтинг" (✅ НЕ ТРОГАТЬ!)
- `lib/features/fortune_wheel/models/fortune_wheel_model.dart` - модели (✅ НЕ ТРОГАТЬ!)
- `lib/features/rating/models/employee_rating_model.dart` - модели рейтинга (✅ НЕ ТРОГАТЬ!)

**Серверные данные:**
- `/var/www/employee-ratings/YYYY-MM.json` - кэш рейтингов за месяц
- `/var/www/fortune-wheel/settings.json` - настройки 15 секторов (тексты, вероятности, цвета)
- `/var/www/fortune-wheel/spins/YYYY-MM.json` - выданные прокрутки топ-3
- `/var/www/fortune-wheel/history/YYYY-MM.json` - история прокруток за месяц
- `/var/www/attendance/` - смены для нормализации
- `/var/www/efficiency-penalties/YYYY-MM.json` - штрафы (все категории)
- `/var/www/referral-clients/` - рефералы для подсчёта
- `/var/www/points-settings/referrals.json` - настройки милестоунов

**API Endpoints (Рейтинг):**
- `GET /api/ratings` - получить рейтинг всех сотрудников за месяц
- `GET /api/ratings/:employeeId` - получить рейтинг сотрудника за N месяцев
- `POST /api/ratings/calculate` - пересчитать рейтинг и выдать прокрутки топ-3
- `DELETE /api/ratings/cache` - очистить кэш рейтингов

**API Endpoints (Колесо):**
- `GET /api/fortune-wheel/settings` - получить настройки секторов
- `POST /api/fortune-wheel/settings` - обновить настройки секторов (админ)
- `GET /api/fortune-wheel/spins/:employeeId` - получить доступные прокрутки
- `POST /api/fortune-wheel/spin` - прокрутить колесо
- `GET /api/fortune-wheel/history` - история прокруток за месяц
- `PATCH /api/fortune-wheel/history/:id/process` - отметить приз обработанным

**Пример расчёта рейтинга:**
```
Иван (20 смен):
  Эффективность: 70.5 баллов (10 категорий + штрафы)
  Рефералы: 11 баллов (7 клиентов с милестоунами)
  Рейтинг: (70.5 / 20) + 11 = 14.525 → 🥇 1 место (2 прокрутки)

Мария (15 смен):
  Эффективность: 75.0 баллов
  Рефералы: 8 баллов (5 клиентов)
  Рейтинг: (75.0 / 15) + 8 = 13.0 → 🥈 2 место (1 прокрутка)

Пётр (18 смен):
  Эффективность: 68.0 баллов
  Рефералы: 5 баллов (3 клиента)
  Рейтинг: (68.0 / 18) + 5 = 8.78 → 🥉 3 место (1 прокрутка)
```

**Зачем нужна нормализация?**

Без нормализации сотрудники с большим количеством смен всегда будут выше:

```
БЕЗ НОРМАЛИЗАЦИИ:
  Иван: 20 смен × 5 баллов/смену = 100 баллов (1 место)
  Мария: 10 смен × 8 баллов/смену = 80 баллов (2 место)

С НОРМАЛИЗАЦИЕЙ:
  Иван: 100 / 20 = 5.0 баллов/смену (2 место)
  Мария: 80 / 10 = 8.0 баллов/смену (1 место)
```

Мария работает **эффективнее** Ивана, хотя у неё меньше смен! Это честная система.

**Дефолтные секторы (15 штук):**
1. Выходной день (6.67%)
2. +500 к премии (6.67%)
3. Бесплатный обед (6.67%)
4. +300 к премии (6.67%)
5. Сертификат на кофе (6.67%)
6. +200 к премии (6.67%)
7. Раньше уйти (6.67%)
8. +100 к премии (6.67%)
9. Десерт в подарок (6.67%)
10. Скидка 20% на меню (6.67%)
11. +150 к премии (6.67%)
12. Кофе бесплатно неделю (6.67%)
13. +250 к премии (6.67%)
14. Подарок от шефа (6.67%)
15. Позже прийти (6.67%)

**⚠️ ВАЖНО:** Система полностью интегрирована со ВСЕМИ модулями! Любые изменения могут сломать:
- Расчёт рейтинга (10 категорий эффективности)
- Нормализацию по сменам
- Интеграцию с рефералами (милестоуны)
- Выдачу прокруток топ-3
- Срок истечения прокруток
- Анимацию колеса
- Вероятностный выбор сектора
- Кэширование рейтингов
- Историю прокруток
- Страницу "Мой рейтинг"
- Настройку секторов (админ)

**🚫 Что НЕ делать:**
- ❌ Не изменять формулу `normalizedRating` без понимания последствий
- ❌ Не менять количество секторов (всегда 15)
- ❌ Не удалять кэш рейтингов без причины
- ❌ Не изменять структуру файлов `spins/` и `history/`
- ❌ Не игнорировать проверку срока истечения прокруток
- ❌ Не изменять алгоритм выбора сектора по вероятности
- ❌ Не менять количество прокруток (1 место = 2, остальные = 1)

**✅ Безопасные изменения:**
- ✅ Изменение текстов призов (через WheelSettingsPage)
- ✅ Изменение вероятностей секторов (сумма должна быть 100%)
- ✅ Изменение цветов секторов
- ✅ Очистка кэша через `DELETE /api/ratings/cache`
- ✅ Пересчёт рейтинга через `POST /api/ratings/calculate`
- ✅ Отметка призов как обработанных
- ✅ Изменение настроек баллов в любой из 10 категорий эффективности
- ✅ Изменение настроек рефералов (basePoints, milestoneThreshold, milestonePoints)

**Полная документация:** См. раздел 23 в `ARCHITECTURE_NEW.md` (более 1200 строк с диаграммами, примерами кода, алгоритмами, API endpoints, моделями данных, жизненными циклами, интеграциями и критическими предупреждениями)

---

### Особенности системы Магазины на карте + Геофенсинг (№26)

**Магазины на карте с геофенсингом** - система интерактивной карты магазинов с push-уведомлениями для клиентов при входе в радиус кофейни.

**Компоненты системы:**
- 🗺️ **Google Maps** - интерактивная карта с маркерами всех магазинов
- 📍 **Геолокация** - определение позиции с проверкой сервисов и таймаутом
- 🔔 **Push-уведомления** - автоматическая отправка при входе в радиус
- ⏰ **Фоновая проверка** - WorkManager каждые 15 минут
- ⚙️ **Настройки** - радиус, тексты, cooldown (только админ)

**Ключевые особенности:**
- TabBar с 2 вкладками (Магазины / Настройки для админа)
- Формула Haversine для расчёта расстояния (±1м точность)
- Cooldown 24 часа для предотвращения спама
- Валидация координат (-90..90, -180..180)
- Анимация с clamp для предотвращения overflow

**Критические файлы:**
- `lib/features/shops/pages/shops_on_map_page.dart` - главная страница (✅ НЕ ТРОГАТЬ!)
- `lib/features/shops/models/shop_model.dart` - модель с валидацией координат (✅ НЕ ТРОГАТЬ!)
- `lib/core/services/background_gps_service.dart` - фоновый сервис (✅ НЕ ТРОГАТЬ!)
- `loyalty-proxy/api/geofence_api.js` - серверный API (✅ НЕ ТРОГАТЬ!)

**Серверные данные:**
- `/var/www/geofence-settings.json` - настройки геозоны
- `/var/www/geofence-notifications/` - история уведомлений (7 дней)
- `/var/www/shops/shop_*.json` - магазины с координатами

**API Endpoints:**
- `GET /api/geofence-settings` - получить настройки
- `POST /api/geofence-settings` - обновить настройки (админ)
- `POST /api/geofence/client-check` - проверить вход в геозону
- `GET /api/geofence/stats` - статистика уведомлений

**🚫 Что НЕ делать:**
- ❌ Не изменять формулу Haversine (calculateGpsDistance)
- ❌ Не изменять логику cooldown
- ❌ Не убирать .clamp() в анимации
- ❌ Не изменять валидацию координат

**✅ Безопасные изменения:**
- ✅ Изменение текстов уведомлений (через UI настроек)
- ✅ Изменение радиуса срабатывания (через UI)
- ✅ Изменение периода cooldown (через UI)
- ✅ Включение/выключение геофенсинга

**Полная документация:** См. раздел 25 в `ARCHITECTURE_NEW.md`

---

### Особенности системы Карта лояльности и бонусы (№27)

**Карта лояльности и бонусы** - клиентская система накопления баллов и получения бесплатных напитков (акция типа "10+1").

**Компоненты системы:**
- 🎫 **QR-код клиента** - уникальный идентификатор для сканирования
- 📊 **Прогресс-бар** - визуализация накопленных баллов
- ☕ **Начисление баллов** - +1 балл за каждый напиток
- 🎁 **Выдача бонуса** - при достижении порога (напр. 10 баллов → 1 бесплатный напиток)
- ⚙️ **Управление акцией** - настройка формулы N+M (только админ)
- 📝 **Текст условий** - кастомизируемый текст акции
- 🔄 **Синхронизация** - freeDrinksGiven синхронизируется с внешним API

**Ключевые особенности:**
- Интеграция с внешним Loyalty API (action=register, getClient, addPoint, redeem)
- Кэширование настроек акции (5 минут) для снижения нагрузки
- Формула акции настраивается админом (pointsRequired + drinksToGive)
- Валидация: 1-100 баллов, 1-10 напитков
- Счётчик freeDrinksGiven для статистики выданных бесплатных напитков

**Критические файлы:**
- `lib/features/loyalty/pages/loyalty_card_page.dart` - карта лояльности клиента (✅ НЕ ТРОГАТЬ!)
- `lib/features/loyalty/pages/loyalty_scanner_page.dart` - сканер QR (✅ НЕ ТРОГАТЬ!)
- `lib/features/loyalty/pages/loyalty_promo_management_page.dart` - управление акцией (✅ НЕ ТРОГАТЬ!)
- `lib/features/loyalty/services/loyalty_service.dart` - сервис API (✅ НЕ ТРОГАТЬ!)
- `loyalty-proxy/index.js` - серверные endpoints (✅ НЕ ТРОГАТЬ!)

**Серверные данные:**
- `/var/www/loyalty-promo.json` - настройки акции (promoText, pointsRequired, drinksToGive)
- `/var/www/clients/{phone}.json` - данные клиентов (freeDrinksGiven)
- Внешний API: addPoint, redeem через BaseHttpService

**API Endpoints:**
- `GET /api/loyalty-promo` - получить настройки акции
- `POST /api/loyalty-promo` - сохранить настройки (только админ!)
- `POST /api/clients/:phone/free-drink` - инкремент freeDrinksGiven
- `POST /api/clients/:phone/sync-free-drinks` - синхронизация freeDrinksGiven

**🚫 Что НЕ делать:**
- ❌ Не изменять логику начисления баллов (addPoint)
- ❌ Не изменять логику redeem без синхронизации
- ❌ Не убирать проверку isAdmin на POST /api/loyalty-promo
- ❌ Не изменять кэширование настроек

**✅ Безопасные изменения:**
- ✅ Изменение текста условий акции (через UI)
- ✅ Изменение формулы N+M (через UI, в пределах валидации)
- ✅ Изменение стилей UI без логики

**Полная документация:** См. раздел 26 в `ARCHITECTURE_NEW.md`

---

### Особенности системы Чат сотрудников (№28)

**Чат сотрудников (Employee Chat)** - внутренняя система коммуникаций с 4 типами чатов, WebSocket для реального времени и интеграцией с "Мои диалоги" для клиентов.

**Компоненты системы:**
- 💬 **4 типа чатов**: general, shop, private, group
- 🌐 **Общий чат** - для всех сотрудников компании
- 🏪 **Чат магазина** - для сотрудников конкретного магазина
- 👤 **Приватные сообщения** - личная переписка между двумя пользователями
- 👥 **Групповые чаты** - создаваемые группы с участниками
- 📷 **Отправка фото** - поддержка изображений в сообщениях
- ⚡ **WebSocket** - реальное время обновлений
- 🔔 **Push-уведомления** - FCM для новых сообщений

**Ключевые особенности:**
- Сервер фильтрует группы по `participants[]` - клиенты видят только группы где они участники
- Нормализация телефонов: `replace(/[\s+]/g, '')` для корректного сравнения
- `ClientGroupChatService` для интеграции с "Мои диалоги"
- Сортировка диалогов: непрочитанные вверху, затем по времени

**Критические файлы:**
- `lib/features/employee_chat/pages/employee_chat_list_page.dart` - список чатов (✅ НЕ ТРОГАТЬ!)
- `lib/features/employee_chat/pages/employee_chat_page.dart` - страница чата (✅ НЕ ТРОГАТЬ!)
- `lib/features/employee_chat/pages/create_group_chat_page.dart` - создание групп (✅ НЕ ТРОГАТЬ!)
- `lib/features/employee_chat/services/employee_chat_service.dart` - HTTP API (✅ НЕ ТРОГАТЬ!)
- `lib/features/employee_chat/services/chat_websocket_service.dart` - WebSocket (✅ НЕ ТРОГАТЬ!)
- `lib/features/employee_chat/services/client_group_chat_service.dart` - для клиентов (✅ НЕ ТРОГАТЬ!)
- `lib/features/employee_chat/models/employee_chat_model.dart` - модели (✅ НЕ ТРОГАТЬ!)
- `loyalty-proxy/api/employee_chat_api.js` - серверный API (✅ НЕ ТРОГАТЬ!)

**Серверные данные:**
- `/var/www/employee-chats/` - сообщения чатов (general.json, shop_*.json, private_*.json)
- `/var/www/employee-chat-groups/` - групповые чаты (group_*.json)
- `/var/www/chat-images/` - изображения из сообщений

**API Endpoints:**
- `GET /api/employee-chats` - список чатов пользователя
- `GET /api/employee-chats/:chatId/messages` - сообщения чата
- `POST /api/employee-chats/messages` - отправить сообщение
- `POST /api/employee-chats/messages/read` - пометить как прочитанные
- `POST /api/employee-chat-groups` - создать групповой чат
- `PUT /api/employee-chat-groups/:id` - обновить группу
- `DELETE /api/employee-chat-groups/:id` - удалить группу

**Интеграция с "Мои диалоги":**
- `ClientGroupChatService.getClientGroupChats(phone)` - получить группы клиента
- `ClientGroupChatService.getUnreadCount(phone)` - счётчик непрочитанных
- Фильтрация: `chat.type == EmployeeChatType.group` (только группы)
- Клиенты НЕ видят general/shop/private чаты

**🚫 Что НЕ делать:**
- ❌ Не изменять фильтрацию групп по `participants` - это безопасность
- ❌ Не давать клиентам доступ к general/shop чатам
- ❌ Не изменять нормализацию телефонов
- ❌ Не убирать проверку `isAdmin` на сервере
- ❌ Не изменять WebSocket протокол

**✅ Безопасные изменения:**
- ✅ Изменение UI стилей без логики
- ✅ Добавление новых типов сообщений (через extension)
- ✅ Изменение текстов уведомлений

**Полная документация:** См. раздел 27 в `ARCHITECTURE_NEW.md`

---

## Общие правила разработки

1. Всегда придерживайся модульной архитектуры.
2. Разделяй ответственность: state, logic, services, UI, utils.
3. Не смешивай бизнес-логику и интерфейс.
4. Вынеси конфигурации и состояние в отдельные модули.
5. Избегай дублирования (DRY).
6. Используй понятные, семантические имена.
7. Пиши читаемый, поддерживаемый код.
8. Каждый новый функционал должен быть изолирован.
9. Не выполняй глобальный рефакторинг без запроса.
10. Никогда не ломай существующую архитектуру без причины.
11. Все изменения должны быть минимально достаточными.

---

## Контроль качества

12. Перед изменениями объясняй архитектурное решение.
13. После изменений кратко опиши:
    - что было изменено
    - почему
    - как это влияет на систему
14. Указывай возможные риски или ограничения.

---

## Правила работы с Git

15. Делай логичные, атомарные коммиты.
16. Комментарий к коммиту должен отражать суть изменений.
17. Не коммить автогенерированный или временный код.

---

## ПРАВИЛА ДЕПЛОЯ (КРИТИЧЕСКИ ВАЖНО!)

### Перед выгрузкой в Git:

1. **НЕ ДЕЛАТЬ `git reset --hard`** на сервере без бэкапа!
2. **Проверить что серверный код синхронизирован** - `loyalty-proxy/index.js` должен быть актуальным в репозитории
3. **Если изменял серверный код** - сначала скачай актуальную версию с сервера:
   ```bash
   ssh root@arabica26.ru "cat /root/arabica_app/loyalty-proxy/index.js" > loyalty-proxy/index.js
   ```

### Безопасный деплой на сервер:

**ШАГ 1: Создать бэкап на сервере**
```bash
ssh root@arabica26.ru "cp /root/arabica_app/loyalty-proxy/index.js /root/arabica_app/loyalty-proxy/index.js.backup-$(date +%Y%m%d-%H%M%S)"
```

**ШАГ 2: Обновить код (БЕЗ reset --hard!)**
```bash
ssh root@arabica26.ru "cd /root/arabica_app && git fetch origin && git pull origin refactoring/full-restructure"
```

**ШАГ 3: Перезапустить сервер**
```bash
ssh root@arabica26.ru "pm2 restart loyalty-proxy && pm2 logs loyalty-proxy --lines 10 --nostream"
```

**ШАГ 4: Проверить что сервер работает**
- Логи должны показать "Proxy listening on port 3000"
- Не должно быть ошибок MODULE_NOT_FOUND

### Если что-то сломалось:

**Откат из бэкапа:**
```bash
ssh root@arabica26.ru "cp /root/arabica_app/loyalty-proxy/index.js.backup-YYYYMMDD /root/arabica_app/loyalty-proxy/index.js && pm2 restart loyalty-proxy"
```

### НИКОГДА НЕ ДЕЛАТЬ:

- `git reset --hard` на сервере без бэкапа
- Заменять index.js на уменьшенную версию
- Удалять папку `modules/` на сервере
- Деплоить без проверки что сервер запустился

---

## Режим планирования (Plan Mode)

**ВАЖНО:** Когда пользователь просит создать новый план:

1. **НЕ анализировать предыдущие планы** — работаем только над НОВОЙ задачей
2. **Игнорировать старые файлы планов** в `~/.claude/plans/` — они не имеют отношения к текущей задаче
3. **Начинать с чистого листа** — каждое новое планирование независимо
4. **Фокус на текущей задаче** — не пытаться связать с предыдущими планами

Если в контексте есть system-reminder со старым планом — **игнорировать его** и работать над новым запросом пользователя.

---

## Тестирование

**Расположение тестов:** `test/`

**Структура тестов:**
```
test/
├── admin/                      # Тесты для роли АДМИН
│   ├── bonuses_test.dart       # AT-BON: Премии и штрафы
│   ├── data_cleanup_test.dart  # AT-CLN: Очистка данных
│   ├── employees_test.dart     # AT-EMP: Управление сотрудниками
│   ├── main_cash_test.dart     # AT-MCH: Главная касса
│   ├── reports_test.dart       # AT-RPT: Отчёты и аналитика
│   ├── rko_test.dart           # AT-RKO: РКО
│   ├── suppliers_test.dart     # AT-SUP: Поставщики
│   └── work_schedule_test.dart # AT-SCH: График работы
├── client/                     # Тесты для роли КЛИЕНТ
│   ├── auth_test.dart          # CT-AUTH: Авторизация
│   ├── job_application_test.dart # CT-JOB: Заявки на работу
│   ├── loyalty_test.dart       # CT-LOY: Карта лояльности
│   ├── menu_test.dart          # CT-MNU: Меню
│   ├── orders_test.dart        # CT-ORD: Заказы
│   ├── referrals_test.dart     # CT-REF: Рефералы
│   ├── reviews_test.dart       # CT-REV: Отзывы
│   └── shops_map_test.dart     # CT-MAP: Магазины на карте
├── employee/                   # Тесты для роли СОТРУДНИК
│   ├── attendance_test.dart    # ET-ATT: Посещаемость
│   ├── chat_test.dart          # ET-CHT: Чат сотрудников
│   ├── envelope_test.dart      # ET-ENV: Конверты
│   ├── product_search_test.dart # ET-PSR: Поиск товара
│   ├── rating_wheel_test.dart  # ET-RAT/WHL: Рейтинг и Колесо
│   ├── recount_test.dart       # ET-REC: Пересчёты
│   ├── recipes_test.dart       # ET-RCP: Рецепты
│   ├── shift_test.dart         # ET-SH: Пересменки
│   ├── tasks_test.dart         # ET-TSK: Задачи
│   └── training_test.dart      # ET-TRN: Обучение
├── integration/                # Интеграционные тесты
│   └── efficiency_cycle_test.dart  # INT: Полный цикл эффективности
├── mocks/
│   └── mock_services.dart      # Общие mock-классы
└── widget_test.dart            # Widget тест (skipped)
```

**Запуск тестов:**
```bash
# Все тесты
flutter test

# Конкретный файл
flutter test test/employee/envelope_test.dart

# С подробным выводом
flutter test --reporter=expanded
```

**Статистика:** 475 тестов, 1 пропущен (widget_test.dart)

**Покрытие модулей:**

| № | Модуль | Тест-файл | Статус |
|---|--------|-----------|--------|
| 1 | Магазины | shops_map_test.dart | ✅ |
| 2 | Сотрудники | employees_test.dart | ✅ |
| 3 | График работы | work_schedule_test.dart | ✅ |
| 4 | Пересменки | shift_test.dart | ✅ |
| 5 | Пересчёты | recount_test.dart | ✅ |
| 6 | ИИ Распознавание | - | 🔧 В разработке |
| 7 | РКО | rko_test.dart | ✅ |
| 8 | Сдать смену | shift_test.dart | ✅ |
| 9 | Посещаемость | attendance_test.dart | ✅ |
| 10 | Передать смену | shift_test.dart | ✅ |
| 11 | KPI | reports_test.dart | ✅ |
| 12 | Отзывы | reviews_test.dart | ✅ |
| 13 | Эффективность | efficiency_cycle_test.dart | ✅ |
| 14 | Мои диалоги | chat_test.dart | ✅ |
| 15 | Поиск товара | product_search_test.dart | ✅ |
| 16 | Заказы | orders_test.dart | ✅ |
| 17 | Обучение | training_test.dart | ✅ |
| 18 | Тестирование | training_test.dart | ✅ |
| 19 | Конверты | envelope_test.dart | ✅ |
| 20 | Главная Касса | main_cash_test.dart | ✅ |
| 21 | Задачи | tasks_test.dart | ✅ |
| 22 | Заявки на работу | job_application_test.dart | ✅ |
| 23 | Рефералы | referrals_test.dart | ✅ |
| 24 | Рейтинг и Колесо | rating_wheel_test.dart | ✅ |
| 25 | Меню и Рецепты | menu_test.dart, recipes_test.dart | ✅ |
| 26 | Геофенсинг | shops_map_test.dart | ✅ |
| 27 | Лояльность | loyalty_test.dart | ✅ |
| 28 | Чат сотрудников | chat_test.dart | ✅ |
| 29 | Премии/штрафы | bonuses_test.dart | ✅ |
| 30 | Очистка данных | data_cleanup_test.dart | ✅ |
| 31 | Поставщики | suppliers_test.dart | ✅ |

**Покрытие:** 30/31 модулей (97%) - только ИИ Распознавание в разработке

---

## Управление памятью диалога

**ВАЖНО:** При заполнении контекста диалога необходимо сохранять суть разговора.

**Правила конспектирования:**

1. **Что сохранять:**
   - Ключевые решения и почему они были приняты
   - Изменённые файлы и что именно было изменено
   - Обнаруженные проблемы и как они были решены
   - Невыполненные задачи (TODO)
   - Важные договорённости с пользователем

2. **Формат конспекта:**
   ```
   ## Сессия [дата]

   ### Выполнено:
   - [задача] → [результат]

   ### Изменённые файлы:
   - path/to/file.dart: [что изменено]

   ### Решения:
   - [проблема] → [решение]

   ### TODO:
   - [ ] Незавершённая задача
   ```

3. **Когда конспектировать:**
   - При приближении к лимиту контекста
   - После завершения крупной задачи
   - Перед переключением на новую тему

4. **Где хранить:**
   - В памяти диалога (автоматическое сжатие)
   - Важные решения дублировать в `ARCHITECTURE_NEW.md`

---

## Напоминание

При долгом диалоге контекст может теряться. Если сомневаешься:
- **Перечитай LOCKED_CODE.md** для проверки защищённых файлов
- **Перечитай ARCHITECTURE_NEW.md** для понимания архитектуры модуля

**Если задача неясна — задай уточняющие вопросы.**

**Если есть несколько вариантов реализации — предложи их с плюсами и минусами.**

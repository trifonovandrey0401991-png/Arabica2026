# АРХИТЕКТУРА КЛИЕНТСКОГО МОДУЛЯ — ARABICA 2026

> **Полная документация всего, что доступно клиенту приложения**
> Дата: 2026-02-12 | Ветка: refactoring/full-restructure

---

## СОДЕРЖАНИЕ

1. [Общая схема архитектуры](#1-общая-схема-архитектуры)
2. [Навигация клиента (визуальная карта)](#2-навигация-клиента)
3. [Регистрация и аутентификация](#3-регистрация-и-аутентификация)
4. [Модуль «Меню и заказы»](#4-модуль-меню-и-заказы)
5. [Модуль «Лояльность и геймификация»](#5-модуль-лояльность-и-геймификация)
6. [Модуль «Отзывы»](#6-модуль-отзывы)
7. [Модуль «Поиск товара»](#7-модуль-поиск-товара)
8. [Модуль «Диалоги» (3-уровневая система)](#8-модуль-диалоги)
9. [Модуль «Колесо фортуны»](#9-модуль-колесо-фортуны)
10. [Модуль «Заявка на работу»](#10-модуль-заявка-на-работу)
11. [Модуль «Кофейни на карте»](#11-модуль-кофейни-на-карте)
12. [Все API эндпоинты (бэкенд)](#12-все-api-эндпоинты)
13. [Все модели данных (Flutter)](#13-все-модели-данных)
14. [Все сервисы (Flutter)](#14-все-сервисы)
15. [Виджеты](#15-виджеты)
16. [Хранилище данных (сервер)](#16-хранилище-данных)
17. [Push-уведомления](#17-push-уведомления)
18. [Безопасность и авторизация](#18-безопасность-и-авторизация)
19. [Карта зависимостей](#19-карта-зависимостей)
20. [Диаграмма потоков данных](#20-диаграмма-потоков-данных)

---

## 1. ОБЩАЯ СХЕМА АРХИТЕКТУРЫ

```
┌─────────────────────────────────────────────────────────────────┐
│                     КЛИЕНТСКОЕ ПРИЛОЖЕНИЕ                        │
│                        (Flutter / Dart)                          │
│                                                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │  Меню &  │ │Лояльность│ │  Отзывы  │ │  Поиск   │           │
│  │  Заказы  │ │& Колесо  │ │          │ │  товара  │           │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘           │
│       │             │            │             │                  │
│  ┌────┴─────┐ ┌────┴─────┐ ┌────┴─────┐ ┌────┴─────┐           │
│  │ Диалоги  │ │ Кофейни  │ │  Работа  │ │ Корзина  │           │
│  │(3 уровня)│ │ на карте │ │  (заявка)│ │          │           │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘           │
│       │             │            │             │                  │
│  ┌────┴─────────────┴────────────┴─────────────┴─────┐          │
│  │              СЕРВИСНЫЙ СЛОЙ (Services)              │          │
│  │  ClientService, LoyaltyService, ReviewService,      │          │
│  │  OrderService, ProductQuestionService, ...          │          │
│  └──────────────────────┬────────────────────────────┘          │
│                         │                                        │
│  ┌──────────────────────┴────────────────────────────┐          │
│  │              BaseHttpService + ApiConstants         │          │
│  └──────────────────────┬────────────────────────────┘          │
│                         │                                        │
│  ┌──────────────────────┴────────────────────────────┐          │
│  │   SharedPreferences / LoyaltyStorage / Providers   │          │
│  └───────────────────────────────────────────────────┘          │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTP (REST API)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                     БЭКЕНД СЕРВЕР                                │
│                  arabica26.ru:3000 (Node.js)                     │
│                                                                  │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐   │
│  │clients_api │ │loyalty_gam │ │ reviews_api│ │product_q_  │   │
│  │    .js     │ │ ification  │ │    .js     │ │  api.js    │   │
│  │            │ │  _api.js   │ │            │ │            │   │
│  └─────┬──────┘ └─────┬──────┘ └─────┬──────┘ └─────┬──────┘   │
│        │               │              │               │          │
│  ┌─────┴───────────────┴──────────────┴───────────────┴──────┐  │
│  │                  orders_api.js                              │  │
│  │              job_applications_api.js                        │  │
│  │           loyalty_promo_api.js                              │  │
│  └──────────────────────┬────────────────────────────────────┘  │
│                         │                                        │
│  ┌──────────────────────┴────────────────────────────────────┐  │
│  │             Файловая система /var/www/                      │  │
│  │    clients/ client-dialogs/ reviews/ orders/ ...           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Firebase Cloud Messaging (FCM)                │  │
│  │           Push-уведомления клиентам                         │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. НАВИГАЦИЯ КЛИЕНТА

### 2.1 Полное дерево навигации

```
🏠 ГЛАВНОЕ МЕНЮ (MainMenuPage) — 9 пунктов для клиента
│
├── ☕ Меню ─────────────────── Выбор кофейни → MenuGroupsPage → MenuPage
│                                                                    │
│                                                              [Добавить в корзину]
│
├── 🛒 Корзина ─────────────── CartPage ─── [Оформить заказ]
│                                                    │
│                                              OrdersPage (статус)
│
├── 📋 Заказы ──────────────── OrdersPage (история и статусы)
│
├── 📍 Кофейни ─────────────── ShopsOnMapPage (карта с точками)
│
├── 💳 Лояльность ──────────── [Проверка уведомлений]
│   │                               │
│   │                          LoyaltyPage
│   │                           ├── QR-код клиента
│   │                           ├── Баллы и бесплатные напитки
│   │                           ├── Текущий уровень + бейджи
│   │                           ├── Прогресс до следующего уровня
│   │                           ├── Ожидающий приз (если есть)
│   │                           └── ClientWheelPage (колесо фортуны)
│   │                                └── Анимированное колесо
│   │                                └── Результат вращения
│   │                                └── Получение приза
│
├── ⭐ Отзывы ──────────────── ReviewTypeSelectionPage
│                                ├── 👍 Положительный
│                                └── 👎 Отрицательный
│                                     │
│                                ReviewShopSelectionPage (выбор кофейни)
│                                     │
│                                ReviewTextInputPage (написать отзыв)
│
├── 💬 Диалоги ─────────────── MyDialogsPage (все диалоги клиента)
│   [бейдж: кол-во непрочитанных]
│   │
│   ├── 🌐 Сетевые сообщения ──── NetworkDialogPage
│   ├── 👔 Руководство ─────────── ManagementDialogPage
│   ├── 📢 Рассылки ────────────── BroadcastMessagesPage
│   ├── 🔍 Поиск товара (ответы) ─ ProductQuestionShopsListPage
│   │                                  └── ProductQuestionPersonalDialogPage
│   ├── ⭐ Ответы на отзывы ────── ClientReviewsListPage
│   │                                  └── ReviewDetailPage
│   └── 👥 Групповые чаты ──────── EmployeeChatPage
│
├── 🔍 Поиск товара ────────── ProductSearchShopSelectionPage
│                                ├── «Вся сеть» (network-wide)
│                                └── Конкретная кофейня
│                                     │
│                                ProductQuestionInputPage
│                                     └── Написать вопрос + фото
│
└── 💼 Работа ──────────────── JobApplicationWelcomePage
                                     │
                                JobApplicationFormPage
                                     ├── ФИО
                                     ├── Телефон
                                     ├── Смена (день/ночь)
                                     └── Выбор кофеен
```

### 2.2 Роль «Клиент» в системе ролей

```
Роли приложения:
┌──────────────────────────────────────────────┐
│  developer  →  Все меню + тестирование       │
│  admin      →  Все меню + управление         │
│  manager    →  Меню сотрудника + управление  │
│  employee   →  Меню сотрудника               │
│  client     →  Клиентское меню (8 пунктов)   │ ← ЭТО
└──────────────────────────────────────────────┘

Определение роли:
  1. UserRoleService.getUserRole(phone) → запрос к API
  2. UserRoleService.checkEmployeeViaAPI() → проверка в БД сотрудников
  3. По умолчанию → UserRole.client
```

---

## 3. РЕГИСТРАЦИЯ И АУТЕНТИФИКАЦИЯ

### 3.1 Поток регистрации

```
Запуск приложения
    │
    ▼
_CheckRegistrationPage
    │
    ├─── Не зарегистрирован ───► RegistrationPage
    │                                │
    │                          ┌─────┴──────────────────────────┐
    │                          │ 1. Ввод телефона (+7...)       │
    │                          │ 2. Ввод имени                  │
    │                          │ 3. PIN-код (4 цифры)           │
    │                          │ 4. Подтверждение PIN           │
    │                          │ 5. Реферальный код (опционально)│
    │                          └─────┬──────────────────────────┘
    │                                │
    │                          ┌─────┴──────────────────────────┐
    │                          │ Проверка в системе лояльности:  │
    │                          │                                 │
    │                          │ ЕСТЬ → загрузить данные         │
    │                          │ НЕТ  → создать новый профиль   │
    │                          │        (UUID → QR-код)          │
    │                          └─────┬──────────────────────────┘
    │                                │
    │                          ┌─────┴──────────────────────────┐
    │                          │ Проверка роли:                  │
    │                          │ Сотрудник? → не сохранять клиента│
    │                          │ Клиент?    → saveClientToServer()│
    │                          └─────┬──────────────────────────┘
    │                                │
    │                          ┌─────┴──────────────────────────┐
    │                          │ Сохранение:                     │
    │                          │ • SharedPreferences (локально)  │
    │                          │ • AuthService (PIN)             │
    │                          │ • FCM Token (push-уведомления)  │
    │                          │ • LoyaltyStorage (баллы)        │
    │                          └─────┬──────────────────────────┘
    │                                │
    │                                ▼
    ├─── Зарегистрирован, нет PIN ──► PinSetupPage ──► MainMenuPage
    │
    └─── Зарегистрирован, есть PIN ─► PinEntryPage ──► MainMenuPage
```

### 3.2 Файлы регистрации

| Файл | Назначение |
|------|------------|
| `lib/features/auth/pages/phone_entry_page.dart` | Ввод телефона |
| `lib/features/auth/pages/pin_setup_page.dart` | Установка PIN |
| `lib/features/auth/pages/pin_entry_page.dart` | Ввод PIN при входе |
| `lib/features/auth/pages/otp_verification_page.dart` | OTP верификация |
| `lib/features/auth/pages/forgot_pin_page.dart` | Восстановление PIN |
| `lib/features/auth/widgets/pin_input_widget.dart` | Виджет ввода PIN |
| `lib/features/auth/widgets/otp_input_widget.dart` | Виджет ввода OTP |
| `lib/features/clients/pages/registration_page.dart` | Форма регистрации клиента |
| `lib/features/clients/services/registration_service.dart` | Сервис регистрации |

### 3.3 Что хранится после регистрации

```
SharedPreferences:
  ├── user_phone          → "79001234567"
  ├── user_name           → "Имя"
  ├── loyalty_qr          → "uuid-xxxx-xxxx"
  ├── loyalty_points      → 15
  ├── loyalty_free_drinks → 2
  ├── loyalty_promo       → "Текст акции"
  ├── loyalty_points_required → 10
  └── loyalty_drinks_to_give  → 1

Firebase:
  └── FCM Token → сохраняется для push-уведомлений
```

---

## 4. МОДУЛЬ «МЕНЮ И ЗАКАЗЫ»

### 4.1 Визуальная схема

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Выбор кофейни  │────►│ Категории меню  │────►│  Позиции меню   │
│  (Диалог)       │     │ MenuGroupsPage  │     │   MenuPage      │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                          │
                                                    [Добавить]
                                                          │
                                                          ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ История заказов │◄────│ Оформить заказ  │◄────│    Корзина      │
│  OrdersPage     │     │ (подтверждение) │     │   CartPage      │
└────────┬────────┘     └─────────────────┘     └─────────────────┘
         │
    Статусы:
    ├── ⏳ pending (ожидает)
    ├── 🔄 preparing (готовится)
    ├── ✅ ready (готов)
    ├── ✔️ completed (выдан)
    └── ❌ rejected (отклонён)
```

### 4.2 Файлы модуля

| Файл | Класс | Назначение |
|------|-------|------------|
| `lib/features/menu/pages/menu_groups_page.dart` | `MenuGroupsPage` | Категории меню (кофе, чай, десерты) |
| `lib/features/menu/pages/menu_page.dart` | `MenuPage` | Позиции в категории + добавление в корзину |
| `lib/features/orders/pages/cart_page.dart` | `CartPage` | Корзина: список, количество, итого, оформление |
| `lib/features/orders/pages/orders_page.dart` | `OrdersPage` | История заказов клиента |
| `lib/shared/providers/cart_provider.dart` | `CartProvider` | Состояние корзины (items, shop, total) |
| `lib/shared/providers/order_provider.dart` | `OrderProvider` | Состояние заказов (список, CRUD) |

### 4.3 Модели

**CartItem** (в `cart_provider.dart`):
```
├── id (String)         — ID позиции
├── name (String)       — Название
├── price (double)      — Цена
├── quantity (int)      — Количество
├── imageUrl (String?)  — Фото
└── photoId (String)    — ID фото из assets
```

**Order** (в `order_provider.dart`):
```
├── id (String)              — ID заказа
├── orderNumber (int)        — Глобальный номер заказа
├── clientPhone (String)     — Телефон клиента
├── clientName (String)      — Имя клиента
├── shopAddress (String)     — Адрес кофейни
├── items (List)             — Список позиций
├── totalPrice (double)      — Итого
├── comment (String?)        — Комментарий
├── status (String)          — Статус: pending/preparing/ready/completed/rejected
├── acceptedBy (String?)     — Кто принял
├── rejectedBy (String?)     — Кто отклонил
├── rejectionReason (String?)— Причина отказа
└── createdAt (DateTime)     — Дата создания
```

### 4.4 API эндпоинты заказов

| Метод | Путь | Назначение |
|-------|------|------------|
| `POST` | `/api/orders` | Создать заказ |
| `GET` | `/api/orders?clientPhone=X` | Получить заказы клиента |
| `GET` | `/api/orders/:id` | Детали заказа |
| `PATCH` | `/api/orders/:id` | Обновить статус (для сотрудника) |
| `DELETE` | `/api/orders/:id` | Удалить заказ |
| `GET` | `/api/orders/unviewed-count` | Кол-во непросмотренных |
| `POST` | `/api/orders/mark-viewed/:type` | Отметить как просмотренные |

---

## 5. МОДУЛЬ «ЛОЯЛЬНОСТЬ И ГЕЙМИФИКАЦИЯ»

### 5.1 Визуальная схема

```
┌───────────────────────────────────────────────────────────────┐
│                       LoyaltyPage                              │
│                                                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐ │
│  │  QR-код      │  │  Баллы       │  │  Бесплатные напитки  │ │
│  │  (для скана) │  │  loyalty_pts │  │  free_drinks         │ │
│  └──────────────┘  └──────────────┘  └──────────────────────┘ │
│                                                                │
│  ┌────────────────────────────────────────────────────────────┐│
│  │                  УРОВЕНЬ КЛИЕНТА                           ││
│  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐               ││
│  │  │ 🌱  │ │ ⭐  │ │ 💎  │ │ 👑  │ │ 🏆  │  ← Бейджи    ││
│  │  │Нович│ │Сереб│ │Золот│ │Плати│ │Леген│               ││
│  │  └─────┘ └─────┘ └─────┘ └─────┘ └─────┘               ││
│  │  ████████████░░░░░░░░  Прогресс до след. уровня          ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                │
│  ┌────────────────────────────────────────────────────────────┐│
│  │               КОЛЕСО ФОРТУНЫ                               ││
│  │  Доступно вращений: 2                                      ││
│  │  Напитков до след. вращения: 3 из 5                        ││
│  │  [████████░░░░░░░]                                         ││
│  │                                                            ││
│  │  ┌──────────────────┐                                      ││
│  │  │ 🎡 КРУТИТЬ КОЛЕСО│ ← Кнопка (если есть вращения)       ││
│  │  └──────────────────┘                                      ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  🎁 У вас есть ожидающий приз!                             ││
│  │  «Бесплатный латте» — Покажите QR на кассе                 ││
│  └────────────────────────────────────────────────────────────┘│
└───────────────────────────────────────────────────────────────┘
```

### 5.2 Система уровней

```
Уровень определяется по количеству бесплатных напитков:

freeDrinksGiven:  0──►5──►15──►30──►50──►100
                  │    │    │    │    │     │
Уровень:         🌱   ⭐   💎   👑   🏆    🔥
                Новичок Silver Gold Plat Legend Master

Каждый уровень имеет:
├── id (int)           — ID уровня
├── name (String)      — Название
├── minFreeDrinks (int)— Мин. напитков для достижения
├── badge (LevelBadge) — Иконка (icon или image)
└── colorHex (String)  — Цвет уровня
```

### 5.3 Колесо фортуны (клиентское)

```
Механика:
  1. Клиент получает N бесплатных напитков
  2. За каждые freeDrinksPerSpin напитков = 1 вращение
  3. Клиент нажимает «Крутить колесо»
  4. Анимация вращения (5 секунд + easeOutCubic)
  5. Колесо останавливается на секторе-призе
  6. Приз сохраняется как ClientPrize со статусом pending
  7. Клиент показывает QR-код на кассе → сотрудник выдаёт приз

Сектора колеса (WheelSector):
├── text (String)        — "Латте бесплатно"
├── probability (double) — 0.15 (сумма всех = 1.0)
├── prizeType (String)   — bonus_points / discount / free_drink / merch
├── prizeValue (int)     — Числовое значение приза
└── colorHex (String)    — Цвет сектора
```

### 5.4 Файлы модуля лояльности

| Файл | Класс | Назначение |
|------|-------|------------|
| `lib/features/loyalty/pages/loyalty_page.dart` | `LoyaltyPage` | Главная страница лояльности |
| `lib/features/loyalty/pages/client_wheel_page.dart` | `ClientWheelPage` | Колесо фортуны с анимацией |
| `lib/features/loyalty/pages/loyalty_scanner_page.dart` | `LoyaltyScannerPage` | Сканер QR (для сотрудников) |
| `lib/features/loyalty/pages/pending_prize_page.dart` | `PendingPrizePage` | Ожидающий приз |
| `lib/features/loyalty/pages/prize_scanner_page.dart` | `PrizeScannerPage` | Сканер приза (для сотрудников) |
| `lib/features/loyalty/pages/loyalty_promo_management_page.dart` | `LoyaltyPromoManagementPage` | Управление акциями (админ) |
| `lib/features/loyalty/pages/loyalty_gamification_settings_page.dart` | `LoyaltyGamificationSettingsPage` | Настройки геймификации (админ) |
| `lib/features/loyalty/pages/client_wheel_prizes_report_page.dart` | `ClientWheelPrizesReportPage` | Отчёт по призам |
| `lib/features/loyalty/services/loyalty_service.dart` | `LoyaltyService` | Работа с баллами, регистрация |
| `lib/features/loyalty/services/loyalty_gamification_service.dart` | `LoyaltyGamificationService` | Уровни, колесо, призы |
| `lib/features/loyalty/services/loyalty_storage.dart` | `LoyaltyStorage` | Локальное хранение данных |
| `lib/features/loyalty/widgets/qr_badges_widget.dart` | `QrBadgesWidget` | QR-код с бейджами вокруг |
| `lib/features/loyalty/widgets/wheel_progress_widget.dart` | `WheelProgressWidget` | Прогресс до вращения |

### 5.5 Модели лояльности

**LoyaltyInfo** (в `loyalty_service.dart`):
```
├── name (String)        — Имя клиента
├── phone (String)       — Телефон
├── qr (String)          — QR-код (UUID)
├── points (int)         — Баллы лояльности
├── freeDrinks (int)     — Бесплатные напитки
├── promoText (String)   — Текст акции
├── pointsRequired (int) — Баллов для напитка
└── drinksToGive (int)   — Напитков за баллы
```

**ClientGamificationData**:
```
├── phone, name            — Идентификация
├── freeDrinksGiven (int)  — Всего бесплатных напитков
├── currentLevel           — Текущий LoyaltyLevel
├── earnedBadges (List)    — Заработанные бейджи
├── wheelSpinsAvailable    — Доступные вращения
├── wheelSpinsUsed         — Использованные вращения
├── drinksToNextSpin       — Напитков до вращения
├── nextLevel              — Следующий уровень
└── drinksToNextLevel      — Напитков до уровня
```

**ClientPrize**:
```
├── id (String)            — ID приза
├── clientPhone, clientName — Кто выиграл
├── prize (String)         — Описание приза
├── prizeType (String)     — Тип: bonus_points/discount/free_drink/merch
├── prizeValue (int)       — Значение
├── spinDate (DateTime)    — Дата вращения
├── status (enum)          — pending / issued
├── qrToken (String)       — QR-токен для получения
├── qrUsed (bool)          — QR использован
├── issuedBy (String?)     — Кто выдал
├── issuedByName (String?) — Имя выдавшего
└── issuedAt (DateTime?)   — Когда выдан
```

### 5.6 API эндпоинты лояльности

| Метод | Путь | Назначение |
|-------|------|------------|
| `GET` | `/api/loyalty-promo` | Настройки акции |
| `POST` | `/api/loyalty-promo` | Сохранить настройки (админ) |
| `GET` | `/api/loyalty-gamification/settings` | Настройки геймификации |
| `POST` | `/api/loyalty-gamification/settings` | Сохранить настройки (админ) |
| `GET` | `/api/loyalty-gamification/client/:phone` | Данные клиента (уровень, вращения) |
| `POST` | `/api/loyalty-gamification/spin` | Вращение колеса |
| `GET` | `/api/loyalty-gamification/wheel-history` | История вращений |
| `GET` | `/api/loyalty-gamification/client/:phone/pending-prize` | Ожидающий приз |
| `POST` | `/api/loyalty-gamification/generate-qr` | Генерация QR для приза |
| `POST` | `/api/loyalty-gamification/scan-prize` | Сканирование QR приза |
| `POST` | `/api/loyalty-gamification/issue-prize` | Выдача приза |
| `POST` | `/api/loyalty-gamification/postpone-prize` | Отложить приз |
| `GET` | `/api/loyalty-gamification/client-prizes-report` | Отчёт по призам |
| `POST` | `/api/loyalty-gamification/upload-badge` | Загрузка бейджа (админ) |
| `POST` | `/api/clients/:phone/free-drink` | Увеличить счётчик напитков |
| `POST` | `/api/clients/:phone/sync-free-drinks` | Синхронизация напитков |

---

## 6. МОДУЛЬ «ОТЗЫВЫ»

### 6.1 Визуальная схема

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Тип отзыва     │────►│ Выбор кофейни    │────►│ Текст отзыва     │
│ ReviewTypeSelect │     │ ReviewShopSelect │     │ ReviewTextInput   │
│                  │     │                  │     │                   │
│  👍 Положительный│     │  📍 Кофейня 1    │     │  [Текст...]       │
│  👎 Отрицательный│     │  📍 Кофейня 2    │     │  [Отправить]      │
└─────────────────┘     └──────────────────┘     └──────────────────┘

После отправки: отзыв появляется в «Мои диалоги» → Отзывы
Администратор может ответить → клиент видит ответ
```

### 6.2 Файлы

| Файл | Класс | Назначение |
|------|-------|------------|
| `lib/features/reviews/pages/review_type_selection_page.dart` | `ReviewTypeSelectionPage` | Выбор типа: положительный/отрицательный |
| `lib/features/reviews/pages/review_shop_selection_page.dart` | `ReviewShopSelectionPage` | Выбор кофейни |
| `lib/features/reviews/pages/review_text_input_page.dart` | `ReviewTextInputPage` | Ввод текста отзыва |
| `lib/features/reviews/pages/client_reviews_list_page.dart` | `ClientReviewsListPage` | Список отзывов клиента |
| `lib/features/reviews/pages/review_detail_page.dart` | `ReviewDetailPage` | Детали отзыва + диалог |
| `lib/features/reviews/pages/reviews_list_page.dart` | `ReviewsListPage` | Все отзывы (для админа) |
| `lib/features/reviews/pages/reviews_shop_detail_page.dart` | `ReviewsShopDetailPage` | Отзывы по кофейне (админ) |
| `lib/features/reviews/services/review_service.dart` | `ReviewService` | CRUD операции с отзывами |

### 6.3 Модели

**Review**:
```
├── id (String)                    — ID отзыва
├── clientPhone (String)           — Телефон клиента
├── clientName (String)            — Имя клиента
├── shopAddress (String)           — Адрес кофейни
├── reviewType (String)            — "positive" / "negative"
├── reviewText (String)            — Текст отзыва
├── createdAt (DateTime)           — Дата создания
├── messages (List<ReviewMessage>) — Переписка
├── hasUnreadFromClient (bool)     — Непрочитанные от клиента
└── hasUnreadFromAdmin (bool)      — Непрочитанные от админа
```

**ReviewMessage**:
```
├── id (String)          — ID сообщения
├── sender (String)      — "client" / "admin"
├── senderName (String)  — Имя отправителя
├── text (String)        — Текст
├── createdAt (DateTime) — Дата
└── isRead (bool)        — Прочитано
```

### 6.4 API эндпоинты отзывов

| Метод | Путь | Назначение |
|-------|------|------------|
| `POST` | `/api/reviews` | Создать отзыв |
| `GET` | `/api/reviews` | Получить отзывы (фильтр по phone) |
| `GET` | `/api/reviews/:id` | Детали отзыва |
| `POST` | `/api/reviews/:id/messages` | Добавить сообщение в диалог |
| `POST` | `/api/reviews/:id/mark-read` | Отметить как прочитанное |

---

## 7. МОДУЛЬ «ПОИСК ТОВАРА»

### 7.1 Визуальная схема

```
┌─────────────────────┐     ┌──────────────────┐
│  Выбор кофейни      │────►│ Ввод вопроса     │
│ ProductSearchShop   │     │ ProductQuestion   │
│ SelectionPage       │     │ InputPage         │
│                     │     │                   │
│  🌐 Вся сеть        │     │  [Текст вопроса]  │
│  📍 Кофейня 1       │     │  📷 [Фото]        │
│  📍 Кофейня 2       │     │  [Отправить]      │
└─────────────────────┘     └──────────────────┘
         │
         │ Ответ приходит от сотрудника кофейни
         ▼
┌────────────────────────────────────────────────┐
│          Мои диалоги → Поиск товара             │
│                                                 │
│  ProductQuestionShopsListPage                   │
│  ├── 📍 Кофейня 1 (3 непрочитанных)            │
│  │   └── ProductQuestionPersonalDialogPage      │
│  │       ├── Вопрос клиента                     │
│  │       ├── Ответ сотрудника                   │
│  │       └── [Ответить]                         │
│  └── 🌐 Вся сеть (1 непрочитанное)             │
│      └── Ответы от разных кофеен                │
└────────────────────────────────────────────────┘
```

### 7.2 Файлы

| Файл | Класс | Назначение |
|------|-------|------------|
| `lib/features/product_questions/pages/product_search_shop_selection_page.dart` | `ProductSearchShopSelectionPage` | Выбор кофейни для вопроса |
| `lib/features/product_questions/pages/product_question_input_page.dart` | `ProductQuestionInputPage` | Ввод вопроса + фото |
| `lib/features/product_questions/pages/product_question_shops_list_page.dart` | `ProductQuestionShopsListPage` | Список кофеен с диалогами |
| `lib/features/product_questions/pages/product_question_personal_dialog_page.dart` | `ProductQuestionPersonalDialogPage` | Персональный диалог клиент↔сотрудник |
| `lib/features/product_questions/pages/product_question_client_dialog_page.dart` | `ProductQuestionClientDialogPage` | Диалог клиента |
| `lib/features/product_questions/pages/product_question_employee_dialog_page.dart` | `ProductQuestionEmployeeDialogPage` | Диалог сотрудника |
| `lib/features/product_questions/pages/product_question_dialog_page.dart` | `ProductQuestionDialogPage` | Общий диалог |
| `lib/features/product_questions/pages/product_question_answer_page.dart` | `ProductQuestionAnswerPage` | Ответ на вопрос (сотрудник) |
| `lib/features/product_questions/pages/product_search_page.dart` | `ProductSearchPage` | Поиск товара |
| `lib/features/product_questions/pages/product_questions_management_page.dart` | `ProductQuestionsManagementPage` | Управление (админ) |
| `lib/features/product_questions/pages/product_questions_report_page.dart` | `ProductQuestionsReportPage` | Отчёт (админ) |
| `lib/features/product_questions/services/product_question_service.dart` | `ProductQuestionService` | Все операции с вопросами |

### 7.3 Модели

**ProductQuestion**:
```
├── id (String)                    — ID вопроса
├── clientPhone (String)           — Телефон клиента
├── clientName (String)            — Имя клиента
├── shopAddress (String?)          — Адрес (null = вся сеть)
├── questionText (String)          — Текст вопроса
├── questionImageUrl (String?)     — Фото товара
├── timestamp (String)             — Дата
├── isAnswered (bool)              — Отвечен ли
├── isNetworkWide (bool)           — На всю сеть
├── hasUnreadFromClient (bool)     — Непрочитанные от клиента
├── messages (List<PQMessage>)     — Переписка
└── rawShops (List<Map>)           — Мульти-магазин данные
```

**ProductQuestionMessage**:
```
├── id (String)              — ID сообщения
├── senderType (String)      — "client" / "employee"
├── senderPhone (String?)    — Телефон отправителя
├── senderName (String?)     — Имя отправителя
├── shopAddress (String?)    — Из какой кофейни ответ
├── text (String)            — Текст
├── imageUrl (String?)       — Фото
├── timestamp (String)       — Дата
├── questionId (String?)     — Ссылка на вопрос
└── isNetworkWide (bool?)    — На всю сеть
```

**PersonalProductDialog**:
```
├── id (String)                    — ID диалога
├── clientPhone (String)           — Телефон
├── clientName (String)            — Имя
├── shopAddress (String)           — Кофейня
├── originalQuestionId (String?)   — Исходный вопрос
├── createdAt (String)             — Дата создания
├── hasUnreadFromClient (bool)     — Непрочитанные от клиента
├── hasUnreadFromEmployee (bool)   — Непрочитанные от сотрудника
├── lastMessageTime (String?)      — Время последнего сообщения
└── messages (List<PQMessage>)     — Переписка
```

**ProductQuestionGroupedData**:
```
├── totalUnread (int)              — Всего непрочитанных
├── networkWideQuestions (List)     — Вопросы на всю сеть
├── networkWideUnreadCount (int)   — Непрочитанных по сети
└── byShop (Map<String, ShopGroup>) — Группировка по кофейням
    └── ProductQuestionShopGroup
        ├── shopAddress (String)
        ├── questions (List<PQ>)
        ├── dialogs (List<PPD>)
        └── unreadCount (int)
```

### 7.4 API эндпоинты поиска товара

| Метод | Путь | Назначение |
|-------|------|------------|
| `POST` | `/api/product-questions` | Создать вопрос |
| `GET` | `/api/product-questions` | Список вопросов |
| `GET` | `/api/product-questions/:id` | Конкретный вопрос |
| `POST` | `/api/product-questions/:id/messages` | Ответить на вопрос |
| `POST` | `/api/product-questions/:id/mark-read` | Отметить прочитанным |
| `GET` | `/api/product-questions/client/:phone` | Вопросы клиента |
| `POST` | `/api/product-questions/client/:phone/reply` | Ответ клиента |
| `GET` | `/api/product-questions/client/:phone/grouped` | Группировка по кофейням |
| `POST` | `/api/product-questions/client/:phone/mark-all-read` | Отметить все прочитанными |
| `GET` | `/api/product-questions/unanswered-count` | Кол-во без ответа |
| `POST` | `/api/product-questions/upload-photo` | Загрузить фото |
| `POST` | `/api/product-question-dialogs` | Создать персональный диалог |
| `GET` | `/api/product-question-dialogs/client/:phone` | Диалоги клиента |
| `GET` | `/api/product-question-dialogs/:id` | Конкретный диалог |
| `POST` | `/api/product-question-dialogs/:id/messages` | Сообщение в диалог |
| `POST` | `/api/product-question-dialogs/:id/mark-read` | Отметить прочитанным |

---

## 8. МОДУЛЬ «ДИАЛОГИ» (3-УРОВНЕВАЯ СИСТЕМА)

### 8.1 Общая схема

```
┌───────────────────────────────────────────────────────────────────┐
│                    MyDialogsPage                                   │
│              (Все диалоги клиента)                                 │
│                                                                    │
│  Сортировка: непрочитанные первые → по дате последнего сообщения  │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ 🌐 Сетевые сообщения           ● 3 непрочитанных           │  │
│  │    Последнее: "Новая акция..."  14:30                       │  │
│  └───────────────────────────────────────────────────────────┬─┘  │
│                                                               │    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ 👔 Руководство                  ● 1 непрочитанное          │  │
│  │    Последнее: "Ответ на ваш..." 12:15                       │  │
│  └───────────────────────────────────────────────────────────┬─┘  │
│                                                               │    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ 📢 Рассылки                                                │  │
│  │    Последнее: "Уважаемые клиенты..." вчера                  │  │
│  └───────────────────────────────────────────────────────────┬─┘  │
│                                                               │    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ 🔍 Поиск товара — Кофейня на Площади  ● 2 непрочитанных   │  │
│  │    Последнее: "Да, есть в наличии" 11:00                    │  │
│  └───────────────────────────────────────────────────────────┬─┘  │
│                                                               │    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ ⭐ Отзыв — Кофейня на Ленина        ● 1 непрочитанное      │  │
│  │    Последнее: "Спасибо за отзыв!" позавчера                 │  │
│  └───────────────────────────────────────────────────────────┬─┘  │
│                                                               │    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ 👥 Групповой чат «Любители кофе»                           │  │
│  │    Последнее: "Привет всем!" 10:00                          │  │
│  └─────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
```

### 8.2 Три уровня сообщений

```
УРОВЕНЬ 1: СЕТЕВЫЕ СООБЩЕНИЯ (Network)
├── Отправитель: Администратор сети
├── Получатели: ВСЕ клиенты
├── Клиент может: Читать + Отвечать
├── Сервис: NetworkMessageService
├── Страница: NetworkDialogPage
└── API: /api/client-dialogs/:phone/network

УРОВЕНЬ 2: РУКОВОДСТВО (Management)
├── Два подтипа:
│   ├── broadcast (рассылка) — от руководства всем клиентам
│   └── personal (персональные) — 1:1 клиент ↔ менеджер
├── Клиент может: Читать + Отвечать + Создавать
├── Сервис: ManagementMessageService
├── Страницы:
│   ├── ManagementDialogPage (клиент видит персональные)
│   └── BroadcastMessagesPage (клиент видит рассылки)
└── API: /api/client-dialogs/:phone/management

УРОВЕНЬ 3: ПРЯМЫЕ СООБЩЕНИЯ (Shop Dialogs)
├── Отправитель: Клиент → конкретная кофейня
├── Через: Отзывы, Поиск товара, Заказы
├── Клиент может: Читать диалог с кофейней
├── Сервис: ClientDialogService
├── Страница: ClientDialogPage
└── API: /api/client-dialogs/:phone/shop/:shopAddress
```

### 8.3 Модели диалогов

**NetworkMessage**:
```
├── id (String)             — ID сообщения
├── text (String)           — Текст
├── imageUrl (String?)      — Изображение
├── timestamp (String)      — Время
├── senderType (String)     — "admin" / "client"
├── senderName (String)     — Имя
├── senderPhone (String?)   — Телефон
├── isReadByClient (bool)   — Клиент прочитал
├── isReadByAdmin (bool)    — Админ прочитал
└── isBroadcast (bool)      — Рассылка
```

**ManagementMessage**:
```
├── id (String)             — ID сообщения
├── text (String)           — Текст
├── imageUrl (String?)      — Изображение
├── timestamp (String)      — Время
├── senderType (String)     — "manager" / "client"
├── senderName (String)     — Имя
├── senderPhone (String?)   — Телефон
├── isReadByClient (bool)   — Клиент прочитал
├── isReadByManager (bool)  — Менеджер прочитал
└── isBroadcast (bool)      — Рассылка (broadcast) или персональное (personal)
```

**ManagementDialogData** (контейнер):
```
├── messages (List<ManagementMessage>)
├── unreadCount (int)
├── broadcastMessages → фильтр по isBroadcast == true
├── personalMessages → фильтр по isBroadcast == false
├── broadcastUnreadCount → непрочитанные рассылки
└── personalUnreadCount → непрочитанные персональные
```

**ClientDialog**:
```
├── shopAddress (String)    — Адрес кофейни
├── messages (List<UnifiedDialogMessage>)
├── lastMessageTime (String?)
└── unreadCount (int)
```

**UnifiedDialogMessage**:
```
├── type (String)           — "review" / "product_question" / "order" / "employee_response"
├── data (Map)              — Данные по типу
├── timestamp (String)      — Время
├── getDisplayText()        → Текст для отображения
├── getImageUrl()           → URL изображения
└── isUnread()              → Непрочитанное
```

### 8.4 Файлы модуля диалогов

| Файл | Класс | Назначение |
|------|-------|------------|
| `lib/app/pages/my_dialogs_page.dart` | `MyDialogsPage` | Хаб всех диалогов клиента |
| `lib/features/clients/pages/network_dialog_page.dart` | `NetworkDialogPage` | Сетевые сообщения |
| `lib/features/clients/pages/management_dialog_page.dart` | `ManagementDialogPage` | Руководство (персональные) |
| `lib/features/clients/pages/broadcast_messages_page.dart` | `BroadcastMessagesPage` | Рассылки |
| `lib/features/clients/pages/client_dialog_page.dart` | `ClientDialogPage` | Диалог с кофейней |
| `lib/features/clients/pages/client_chat_page.dart` | `ClientChatPage` | Чат (для админа/сотрудника) |
| `lib/features/clients/pages/admin_management_dialog_page.dart` | `AdminManagementDialogPage` | Управление диалогом (админ) |
| `lib/features/clients/pages/clients_management_page.dart` | `ClientsManagementPage` | Управление клиентами (админ) |
| `lib/features/clients/pages/management_dialogs_list_page.dart` | `ManagementDialogsListPage` | Список всех диалогов (админ) |

### 8.5 API эндпоинты диалогов

| Метод | Путь | Назначение |
|-------|------|------------|
| `GET` | `/api/client-dialogs/:phone` | Все диалоги клиента по кофейням |
| `GET` | `/api/client-dialogs/:phone/shop/:shopAddress` | Диалог с конкретной кофейней |
| `GET` | `/api/client-dialogs/:phone/network` | Сетевые сообщения |
| `POST` | `/api/client-dialogs/:phone/network/reply` | Ответ клиента на сетевое |
| `POST` | `/api/client-dialogs/:phone/network/read-by-client` | Отметить прочитанными |
| `GET` | `/api/client-dialogs/:phone/management` | Сообщения руководства |
| `POST` | `/api/client-dialogs/:phone/management/reply` | Ответ клиента руководству |
| `POST` | `/api/client-dialogs/:phone/management/send` | Менеджер отправляет клиенту |
| `POST` | `/api/client-dialogs/:phone/management/read-by-client` | Клиент прочитал (с фильтром type) |
| `POST` | `/api/client-dialogs/:phone/management/read-by-manager` | Менеджер прочитал |
| `GET` | `/api/clients` | Список всех клиентов |
| `POST` | `/api/clients` | Создать/обновить клиента |
| `GET` | `/api/clients/:phone/messages` | Сообщения клиента (legacy) |
| `POST` | `/api/clients/:phone/messages` | Отправить клиенту |
| `POST` | `/api/clients/messages/broadcast` | Рассылка всем клиентам |
| `GET` | `/api/management-dialogs` | Все диалоги руководства (админ) |

---

## 9. МОДУЛЬ «КОЛЕСО ФОРТУНЫ»

### 9.1 Визуальная схема

```
┌─────────────────────────────────────────────────────────────────┐
│                     ClientWheelPage                              │
│                                                                  │
│              ┌───────────────────────────┐                       │
│              │      🔺 Указатель         │                       │
│              │                           │                       │
│              │    ╭─────────────────╮    │                       │
│              │   ╱  Латте  │ Скидка ╲   │                       │
│              │  │  бесплатно│  10%    │  │                       │
│              │  │───────────┼─────────│  │                       │
│              │  │  Бонус   │ Десерт  │  │                       │
│              │  │  50 баллов│бесплатно│  │                       │
│              │   ╲─────────┼─────────╱   │                       │
│              │    ╰─────────────────╯    │                       │
│              │         ★ ★ ★            │                       │
│              └───────────────────────────┘                       │
│                                                                  │
│  Доступно вращений: 2          Анимация: 5 сек + easeOutCubic   │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │              🎡 КРУТИТЬ КОЛЕСО                              │  │
│  │         (пульсирующая анимация кнопки)                      │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Результат → Диалог «Поздравляем! Вы выиграли...»               │
│  Приз → ClientPrize (pending) → QR-код → Выдача на кассе        │
└─────────────────────────────────────────────────────────────────┘
```

### 9.2 Три анимации

```
1. _spinController (AnimationController)
   └── Вращение колеса: 5 секунд, Curves.easeOutCubic
   └── Минимум 6 полных оборотов + остановка на секторе

2. _glowController (AnimationController)
   └── Свечение вокруг колеса: 2 секунды, повтор
   └── Применяется: BoxShadow с opacity

3. _pulseController (AnimationController)
   └── Пульсация кнопки «Крутить»: 1.5 секунды, повтор
   └── Применяется: Transform.scale
```

### 9.3 Виджет AnimatedWheelWidget

```
Визуальные слои (Stack):
├── Внешнее кольцо (PremiumWheelPainter)
│   ├── Sweep gradient (градиент по кругу)
│   ├── Анимированные «лампочки» (пульсируют)
│   └── Внутреннее кольцо со звёздами
├── Секторы колеса
│   ├── Радиальный градиент на каждый сектор
│   ├── Текст призов (по радиусу)
│   └── Внутренние тени
├── Указатель (PremiumPointerPainter)
│   ├── Стрелка с градиентом
│   ├── Эффект тени
│   └── Точка крепления
└── Центральная кнопка
    ├── Золотой градиент
    └── Иконка звезды
```

---

## 10. МОДУЛЬ «ЗАЯВКА НА РАБОТУ»

### 10.1 Визуальная схема

```
┌──────────────────┐     ┌──────────────────┐
│  Добро пожаловать │────►│  Форма заявки    │
│ JobApplication    │     │ JobApplication   │
│ WelcomePage       │     │ FormPage         │
│                   │     │                  │
│ "Хочешь работать │     │ ФИО              │
│  в Arabica?"     │     │ Телефон          │
│                   │     │ Смена: День/Ночь │
│ [Подать заявку]  │     │ Кофейни: [✓][✓]  │
└──────────────────┘     │ [Отправить]      │
                          └──────────────────┘

Статусы заявки:
  📩 new        → "Новая"
  👀 viewed     → "Просмотрена"
  📞 contacted  → "Связались"
  🗣️ interview  → "Собеседование"
  ✅ accepted   → "Принят"
  ❌ rejected   → "Отказ"
```

### 10.2 Файлы

| Файл | Класс | Назначение |
|------|-------|------------|
| `lib/features/job_application/pages/job_application_welcome_page.dart` | `JobApplicationWelcomePage` | Приветственная страница |
| `lib/features/job_application/pages/job_application_form_page.dart` | `JobApplicationFormPage` | Форма подачи |
| `lib/features/job_application/pages/job_applications_list_page.dart` | `JobApplicationsListPage` | Список заявок (админ) |
| `lib/features/job_application/pages/job_application_detail_page.dart` | `JobApplicationDetailPage` | Детали заявки (админ) |
| `lib/features/job_application/services/job_application_service.dart` | `JobApplicationService` | CRUD для заявок |

### 10.3 Модель

**JobApplication**:
```
├── id (String)                  — ID заявки
├── fullName (String)            — ФИО
├── phone (String)               — Телефон
├── preferredShift (String)      — "day" / "night"
├── shopAddresses (List<String>) — Желаемые кофейни
├── createdAt (DateTime)         — Дата подачи
├── isViewed (bool)              — Просмотрена
├── viewedAt (DateTime?)         — Когда просмотрена
├── viewedBy (String?)           — Кем просмотрена
├── status (ApplicationStatus)   — Текущий статус
└── adminNotes (String?)         — Заметки админа
```

### 10.4 API эндпоинты

| Метод | Путь | Назначение |
|-------|------|------------|
| `POST` | `/api/job-applications` | Подать заявку |
| `GET` | `/api/job-applications` | Все заявки (админ) |
| `GET` | `/api/job-applications/unviewed-count` | Кол-во непросмотренных |
| `PATCH` | `/api/job-applications/:id/view` | Отметить просмотренной |
| `PATCH` | `/api/job-applications/:id/status` | Обновить статус |
| `PATCH` | `/api/job-applications/:id/notes` | Обновить заметки |

---

## 11. МОДУЛЬ «КОФЕЙНИ НА КАРТЕ»

### 11.1 Описание

```
ShopsOnMapPage
├── Карта с маркерами всех кофеен
├── При нажатии на маркер → информация о кофейне
│   ├── Название
│   ├── Адрес
│   ├── Время работы
│   └── Контакты
└── Использует: Yandex Maps / Google Maps виджет
```

### 11.2 Файлы

| Файл | Класс | Назначение |
|------|-------|------------|
| `lib/features/shops/pages/shops_on_map_page.dart` | `ShopsOnMapPage` | Карта с точками |
| `lib/features/shops/pages/shops_management_page.dart` | `ShopsManagementPage` | Управление (админ) |
| `lib/features/shops/models/shop_model.dart` | `Shop` | Модель кофейни |

---

## 12. ВСЕ API ЭНДПОИНТЫ (СВОДНАЯ ТАБЛИЦА)

### 12.1 Клиенты и диалоги (`clients_api.js`)

| # | Метод | Путь | Назначение |
|---|-------|------|------------|
| 1 | `GET` | `/api/clients` | Все клиенты (поиск, пагинация) |
| 2 | `POST` | `/api/clients` | Создать/обновить клиента |
| 3 | `GET` | `/api/clients/:phone/messages` | Сообщения клиента |
| 4 | `POST` | `/api/clients/:phone/messages` | Отправить клиенту |
| 5 | `POST` | `/api/clients/messages/broadcast` | Рассылка всем |
| 6 | `POST` | `/api/clients/:phone/free-drink` | +1 бесплатный напиток |
| 7 | `POST` | `/api/clients/:phone/sync-free-drinks` | Синхронизация напитков |
| 8 | `GET` | `/api/client-dialogs/:phone` | Диалоги по кофейням |
| 9 | `GET` | `/api/client-dialogs/:phone/shop/:addr` | Диалог с кофейней |
| 10 | `POST` | `/api/client-dialogs/:phone/shop/:addr/messages` | Сообщение в кофейню |
| 11 | `GET` | `/api/client-dialogs/:phone/network` | Сетевые сообщения |
| 12 | `POST` | `/api/client-dialogs/:phone/network/reply` | Ответ на сетевое |
| 13 | `POST` | `/api/client-dialogs/:phone/network/read-by-client` | Прочитано клиентом |
| 14 | `POST` | `/api/client-dialogs/:phone/network/read-by-admin` | Прочитано админом |
| 15 | `GET` | `/api/client-dialogs/:phone/management` | Сообщения руководства |
| 16 | `POST` | `/api/client-dialogs/:phone/management/reply` | Ответ руководству |
| 17 | `POST` | `/api/client-dialogs/:phone/management/send` | Менеджер → клиенту |
| 18 | `POST` | `/api/client-dialogs/:phone/management/read-by-client` | Прочитано клиентом |
| 19 | `POST` | `/api/client-dialogs/:phone/management/read-by-manager` | Прочитано менеджером |
| 20 | `GET` | `/api/management-dialogs` | Все диалоги руководства |

### 12.2 Лояльность (`loyalty_promo_api.js` + `loyalty_gamification_api.js`)

| # | Метод | Путь | Назначение |
|---|-------|------|------------|
| 21 | `GET` | `/api/loyalty-promo` | Настройки акции |
| 22 | `POST` | `/api/loyalty-promo` | Сохранить настройки |
| 23 | `GET` | `/api/loyalty-gamification/settings` | Настройки геймификации |
| 24 | `POST` | `/api/loyalty-gamification/settings` | Сохранить настройки |
| 25 | `POST` | `/api/loyalty-gamification/upload-badge` | Загрузить бейдж |
| 26 | `GET` | `/api/loyalty-gamification/client/:phone` | Данные клиента |
| 27 | `POST` | `/api/loyalty-gamification/spin` | Вращение колеса |
| 28 | `GET` | `/api/loyalty-gamification/wheel-history` | История вращений |
| 29 | `PATCH` | `/api/loyalty-gamification/wheel-history/:id/process` | Обработать вращение |
| 30 | `GET` | `/api/loyalty-gamification/client/:phone/pending-prize` | Ожидающий приз |
| 31 | `POST` | `/api/loyalty-gamification/generate-qr` | Генерация QR приза |
| 32 | `POST` | `/api/loyalty-gamification/scan-prize` | Сканирование QR |
| 33 | `POST` | `/api/loyalty-gamification/issue-prize` | Выдача приза |
| 34 | `POST` | `/api/loyalty-gamification/postpone-prize` | Отложить приз |
| 35 | `GET` | `/api/loyalty-gamification/client-prizes-report` | Отчёт по призам |

### 12.3 Отзывы (`reviews_api.js`)

| # | Метод | Путь | Назначение |
|---|-------|------|------------|
| 36 | `POST` | `/api/reviews` | Создать отзыв |
| 37 | `GET` | `/api/reviews` | Список отзывов |
| 38 | `GET` | `/api/reviews/:id` | Детали отзыва |
| 39 | `POST` | `/api/reviews/:id/messages` | Сообщение в отзыв |
| 40 | `POST` | `/api/reviews/:id/mark-read` | Отметить прочитанным |

### 12.4 Поиск товара (`product_questions_api.js`)

| # | Метод | Путь | Назначение |
|---|-------|------|------------|
| 41 | `POST` | `/api/product-questions` | Создать вопрос |
| 42 | `GET` | `/api/product-questions` | Список вопросов |
| 43 | `GET` | `/api/product-questions/:id` | Конкретный вопрос |
| 44 | `PUT` | `/api/product-questions/:id` | Обновить вопрос |
| 45 | `DELETE` | `/api/product-questions/:id` | Удалить вопрос |
| 46 | `POST` | `/api/product-questions/:id/messages` | Ответить на вопрос |
| 47 | `POST` | `/api/product-questions/:id/mark-read` | Прочитано |
| 48 | `GET` | `/api/product-questions/unanswered-count` | Без ответа |
| 49 | `GET` | `/api/product-questions/client/:phone` | Вопросы клиента |
| 50 | `POST` | `/api/product-questions/client/:phone/reply` | Ответ клиента |
| 51 | `GET` | `/api/product-questions/client/:phone/grouped` | Группировка |
| 52 | `POST` | `/api/product-questions/client/:phone/mark-all-read` | Всё прочитано |
| 53 | `POST` | `/api/product-questions/upload-photo` | Загрузить фото |
| 54 | `POST` | `/api/product-question-dialogs` | Создать диалог |
| 55 | `GET` | `/api/product-question-dialogs/client/:phone` | Диалоги клиента |
| 56 | `GET` | `/api/product-question-dialogs/all` | Все диалоги |
| 57 | `GET` | `/api/product-question-dialogs/shop/:addr` | Диалоги кофейни |
| 58 | `GET` | `/api/product-question-dialogs/unviewed-counts` | Непросмотренные |
| 59 | `GET` | `/api/product-question-dialogs/:id` | Конкретный диалог |
| 60 | `POST` | `/api/product-question-dialogs/:id/messages` | Сообщение |
| 61 | `POST` | `/api/product-question-dialogs/:id/mark-read` | Прочитано |
| 62 | `POST` | `/api/product-question-dialogs/:id/mark-viewed-by-admin` | Просмотрено админом |
| 63 | `POST` | `/api/product-question-dialogs/mark-shop-viewed-by-admin` | Просмотрено (кофейня) |

### 12.5 Заказы (`orders_api.js`)

| # | Метод | Путь | Назначение |
|---|-------|------|------------|
| 64 | `POST` | `/api/orders` | Создать заказ |
| 65 | `GET` | `/api/orders` | Список заказов |
| 66 | `GET` | `/api/orders/unviewed-count` | Непросмотренные |
| 67 | `POST` | `/api/orders/mark-viewed/:type` | Просмотрено |
| 68 | `GET` | `/api/orders/:id` | Детали заказа |
| 69 | `PATCH` | `/api/orders/:id` | Обновить статус |
| 70 | `DELETE` | `/api/orders/:id` | Удалить заказ |

### 12.6 Заявки на работу (`job_applications_api.js`)

| # | Метод | Путь | Назначение |
|---|-------|------|------------|
| 71 | `POST` | `/api/job-applications` | Подать заявку |
| 72 | `GET` | `/api/job-applications` | Все заявки |
| 73 | `GET` | `/api/job-applications/unviewed-count` | Непросмотренные |
| 74 | `PATCH` | `/api/job-applications/:id/view` | Просмотрена |
| 75 | `PATCH` | `/api/job-applications/:id/status` | Обновить статус |
| 76 | `PATCH` | `/api/job-applications/:id/notes` | Обновить заметки |

**ИТОГО: 76 API эндпоинтов для клиентского модуля**

---

## 13. ВСЕ МОДЕЛИ ДАННЫХ (СВОДКА)

| # | Модель | Файл | Модуль |
|---|--------|------|--------|
| 1 | `Client` | `clients/models/client_model.dart` | Клиенты |
| 2 | `ClientDialog` | `clients/models/client_dialog_model.dart` | Клиенты |
| 3 | `ClientMessage` | `clients/models/client_message_model.dart` | Клиенты |
| 4 | `NetworkMessage` | `clients/models/network_message_model.dart` | Клиенты |
| 5 | `NetworkDialogData` | `clients/models/network_message_model.dart` | Клиенты |
| 6 | `ManagementMessage` | `clients/models/management_message_model.dart` | Клиенты |
| 7 | `ManagementDialogData` | `clients/models/management_message_model.dart` | Клиенты |
| 8 | `UnifiedDialogMessage` | `shared/models/unified_dialog_message_model.dart` | Общие |
| 9 | `LoyaltyInfo` | `loyalty/services/loyalty_service.dart` | Лояльность |
| 10 | `LoyaltyPromoSettings` | `loyalty/services/loyalty_service.dart` | Лояльность |
| 11 | `LevelBadge` | `loyalty/models/loyalty_gamification_model.dart` | Лояльность |
| 12 | `LoyaltyLevel` | `loyalty/models/loyalty_gamification_model.dart` | Лояльность |
| 13 | `WheelSector` | `loyalty/models/loyalty_gamification_model.dart` | Лояльность |
| 14 | `WheelSettings` | `loyalty/models/loyalty_gamification_model.dart` | Лояльность |
| 15 | `GamificationSettings` | `loyalty/models/loyalty_gamification_model.dart` | Лояльность |
| 16 | `ClientGamificationData` | `loyalty/models/loyalty_gamification_model.dart` | Лояльность |
| 17 | `WheelSpinResult` | `loyalty/models/loyalty_gamification_model.dart` | Лояльность |
| 18 | `ClientPrize` | `loyalty/models/loyalty_gamification_model.dart` | Лояльность |
| 19 | `ClientPrizeStatus` | `loyalty/models/loyalty_gamification_model.dart` | Лояльность |
| 20 | `Review` | `reviews/models/review_model.dart` | Отзывы |
| 21 | `ReviewMessage` | `reviews/models/review_model.dart` | Отзывы |
| 22 | `ProductQuestion` | `product_questions/models/product_question_model.dart` | Поиск товара |
| 23 | `ProductQuestionMessage` | `product_questions/models/product_question_message_model.dart` | Поиск товара |
| 24 | `ProductQuestionDialog` | `product_questions/models/product_question_model.dart` | Поиск товара |
| 25 | `ProductQuestionClientDialogData` | `product_questions/models/product_question_model.dart` | Поиск товара |
| 26 | `ProductQuestionLastMessage` | `product_questions/models/product_question_model.dart` | Поиск товара |
| 27 | `PersonalProductDialog` | `product_questions/models/product_question_model.dart` | Поиск товара |
| 28 | `ProductQuestionShopGroup` | `product_questions/models/product_question_model.dart` | Поиск товара |
| 29 | `ProductQuestionGroupedData` | `product_questions/models/product_question_model.dart` | Поиск товара |
| 30 | `Order` | `shared/providers/order_provider.dart` | Заказы |
| 31 | `CartItem` | `shared/providers/cart_provider.dart` | Заказы |
| 32 | `JobApplication` | `job_application/models/job_application_model.dart` | Работа |
| 33 | `ApplicationStatus` | `job_application/models/job_application_model.dart` | Работа |

**ИТОГО: 33 модели данных**

---

## 14. ВСЕ СЕРВИСЫ (СВОДКА)

| # | Сервис | Файл | Методов | Назначение |
|---|--------|------|---------|------------|
| 1 | `ClientService` | `clients/services/client_service.dart` | 6 | Клиенты, сообщения |
| 2 | `ClientDialogService` | `clients/services/client_dialog_service.dart` | 2 | Диалоги по кофейням |
| 3 | `NetworkMessageService` | `clients/services/network_message_service.dart` | 3 | Сетевые сообщения |
| 4 | `ManagementMessageService` | `clients/services/management_message_service.dart` | 5 | Руководство |
| 5 | `RegistrationService` | `clients/services/registration_service.dart` | 2 | Регистрация |
| 6 | `LoyaltyService` | `loyalty/services/loyalty_service.dart` | 8 | Баллы, регистрация |
| 7 | `LoyaltyGamificationService` | `loyalty/services/loyalty_gamification_service.dart` | 12 | Уровни, колесо, призы |
| 8 | `LoyaltyStorage` | `loyalty/services/loyalty_storage.dart` | 3 | Локальное хранение |
| 9 | `ReviewService` | `reviews/services/review_service.dart` | 7 | CRUD отзывов |
| 10 | `ProductQuestionService` | `product_questions/services/product_question_service.dart` | 25+ | Вопросы, диалоги |
| 11 | `OrderService` | `orders/services/order_service.dart` | 6 | Заказы |
| 12 | `JobApplicationService` | `job_application/services/job_application_service.dart` | 5 | Заявки |

**ИТОГО: 12 сервисов, ~85 методов**

### Ключевые методы сервисов (используемые клиентом)

```
RegistrationService:
  ├── registerUser(name, phone, qr)
  └── saveClientToServer(phone, name, clientName, referredBy?)

LoyaltyService:
  ├── fetchPromoSettings()        — кэш 5 минут
  ├── registerClient(name, phone, qr)
  ├── fetchByPhone(phone)
  └── redeemPoints(phone, points)

LoyaltyGamificationService:
  ├── fetchSettings()             — кэш 5 минут
  ├── fetchClientData(phone)
  ├── spinWheel(phone)
  ├── fetchPendingPrize(phone)
  └── getPrizeQR(prizeId, phone)

ReviewService:
  ├── createReview(clientPhone, clientName, shopAddress, type, text)
  ├── getClientReviews(phone)
  └── sendReplyToReview(reviewId, text, senderPhone, senderName)

ProductQuestionService:
  ├── createQuestion(clientPhone, clientName, shopAddress, text, imageUrl?)
  ├── getClientGroupedDialogs(phone)
  ├── sendClientReply(clientPhone, text, imageUrl?, questionId?)
  └── markQuestionAsRead(questionId, readerType)

OrderService:
  ├── createOrder(clientPhone, clientName, shopAddress, items, totalPrice)
  └── getClientOrders(clientPhone)

ManagementMessageService:
  ├── getManagementMessages(clientPhone)
  ├── sendMessage(clientPhone, text, imageUrl?, clientName?)
  └── markAsReadByClient(clientPhone, type?)

NetworkMessageService:
  ├── getNetworkMessages(clientPhone)
  ├── sendReply(clientPhone, text, imageUrl?, clientName?)
  └── markAsReadByClient(clientPhone)
```

---

## 15. ВИДЖЕТЫ

### 15.1 QrBadgesWidget

```
Назначение: Отображение QR-кода с бейджами уровней вокруг

Параметры:
  ├── qrWidget (Widget)              — Центральный QR-код
  └── earnedLevels (List<LoyaltyLevel>) — Заработанные бейджи

Визуал:
  ┌──────────────────────────┐
  │    🌱          ⭐         │
  │         ┌──────────┐     │
  │    💎   │ QR-КОД   │ 👑  │
  │         │          │     │
  │    🏆   └──────────┘     │
  │              🔥           │
  └──────────────────────────┘

  До 8 бейджей: top(1,5), bottom(2,6), right(3,7), left(4,8)
  Размер бейджа: 80x80dp
  Анимация: elasticOut при первом рендере
  Форма: зубчатый/серрейтный край (StickerClipper)
```

### 15.2 WheelProgressWidget

```
Назначение: Прогресс до следующего вращения колеса

Параметры:
  ├── currentDrinks (int)      — Текущие напитки
  ├── drinksPerSpin (int)      — Напитков на вращение
  ├── spinsAvailable (int)     — Доступные вращения
  ├── wheelEnabled (bool)      — Активно/неактивно
  └── onSpinPressed (callback) — Нажатие «Крутить»

Визуал:
  ┌────────────────────────────────────────┐
  │  🎡 Колесо фортуны    [2 вращения]    │
  │                                        │
  │  Напитков до вращения: 3 из 5          │
  │  [●●●○○]                               │
  │                                        │
  │  ┌──────────────────────────────────┐  │
  │  │      🎡 КРУТИТЬ КОЛЕСО          │  │
  │  └──────────────────────────────────┘  │
  └────────────────────────────────────────┘
```

### 15.3 AnimatedWheelWidget

```
Назначение: Анимированное колесо фортуны с премиум-эффектами

Параметры:
  ├── sectors (List<FortuneWheelSector>)
  ├── targetSectorIndex (int?)
  ├── onSpinComplete (callback)
  └── isSpinning (bool)

Ключевые методы:
  └── spinToSector(int sectorIndex) — анимация к сектору (мин. 6 оборотов)

Внутренние классы:
  ├── PremiumWheelPainter — рисует секторы, кольцо, лампочки, звёзды
  └── PremiumPointerPainter — рисует указатель-стрелку
```

### 15.4 Общие виджеты (shared)

| Виджет | Файл | Назначение |
|--------|------|------------|
| `MediaMessageWidget` | `shared/widgets/media_message_widget.dart` | Медиа в сообщениях |
| `MediaPickerButton` | `shared/widgets/media_picker_button.dart` | Кнопка выбора фото/видео |
| `AppCachedImage` | `shared/widgets/app_cached_image.dart` | Кэшированные изображения |
| `NotificationRequiredDialog` | `shared/dialogs/notification_required_dialog.dart` | Диалог включения уведомлений |

---

## 16. ХРАНИЛИЩЕ ДАННЫХ (СЕРВЕР)

### 16.1 Файловая структура

```
/var/www/
├── clients/                              # Профили клиентов
│   └── 79001234567.json                  # По телефону
│       ├── phone, name
│       ├── fcmToken
│       ├── hasUnreadFromClient
│       ├── hasUnreadManagement
│       ├── lastClientMessageTime
│       ├── lastManagementMessageTime
│       └── freeDrinksGiven
│
├── client-dialogs/                       # Диалоги по кофейням
│   └── 79001234567/                      # Папка клиента
│       └── Кофейня_на_Площади.json       # Диалог с кофейней
│
├── client-messages/                      # Legacy сообщения
│   └── 79001234567.json
│
├── client-messages-network/              # Сетевые сообщения
│   └── 79001234567.json
│
├── client-messages-management/           # Сообщения руководства
│   └── 79001234567.json
│
├── reviews/                              # Отзывы клиентов
│   └── review-uuid-xxxx.json
│       ├── clientPhone, clientName
│       ├── shopAddress, reviewType, reviewText
│       └── messages[]
│
├── product-questions/                    # Вопросы о товарах
│   └── question-uuid-xxxx.json
│       ├── clientPhone, clientName
│       ├── shopAddress, questionText
│       └── messages[]
│
├── product-question-dialogs/             # Персональные диалоги
│   └── dialog-uuid-xxxx.json
│
├── orders/                               # Заказы
│   └── order-uuid-xxxx.json
│       ├── orderNumber, clientPhone
│       ├── items[], totalPrice
│       └── status, acceptedBy
│
├── job-applications/                     # Заявки на работу
│   └── application-uuid-xxxx.json
│
├── loyalty-gamification/                 # Геймификация
│   ├── settings.json                     # Настройки (уровни, колесо)
│   ├── badges/                           # Изображения бейджей
│   ├── client-prizes/                    # Призы клиентов
│   │   └── prize-uuid-xxxx.json
│   └── wheel-history/                    # История вращений
│       └── 2026-02/                      # По месяцам
│           └── spin-uuid-xxxx.json
│
└── fcm-tokens/                           # Push-токены
    └── 79001234567.json                  # FCM token по телефону
```

---

## 17. PUSH-УВЕДОМЛЕНИЯ

### 17.1 Уведомления, которые получает клиент

| Событие | Заголовок | Тип (data.type) | Когда отправляется |
|---------|-----------|-----------------|-------------------|
| Ответ от руководства | "Ответ от руководства" | `management_message` | Менеджер отвечает клиенту |
| Рассылка | "Рассылка" | `management_message` + `isBroadcast` | Массовая рассылка |
| Заказ принят | "Заказ #N принят" | `order_status` | Сотрудник принимает заказ |
| Заказ отклонён | "Заказ #N не принят" | `order_status` | Сотрудник отклоняет заказ |
| Ответ на вопрос | "Ответ на ваш вопрос" | `product_question_answered` | Сотрудник отвечает на вопрос |
| Ответ на отзыв | "Ответ на ваш отзыв" | `review_message` | Админ отвечает на отзыв |

### 17.2 Механизм доставки

```
Сервер (Node.js)
    │
    ├── Читает FCM-токен из /var/www/fcm-tokens/{phone}.json
    │
    ├── Отправляет через Firebase Admin SDK:
    │   {
    │     token: clientFcmToken,
    │     notification: { title, body },
    │     data: { type, orderId/questionId/... }
    │   }
    │
    └── Flutter обрабатывает через NotificationService:
        ├── Foreground → показать SnackBar/уведомление
        ├── Background → системное уведомление
        └── Tap → навигация к нужной странице
```

---

## 18. БЕЗОПАСНОСТЬ И АВТОРИЗАЦИЯ

### 18.1 Аутентификация клиента

```
Механизм: Phone-based (без сессий)
├── Клиент идентифицируется по номеру телефона
├── Телефон передаётся в:
│   ├── URL параметрах (:phone)
│   ├── Query параметрах (?clientPhone=)
│   ├── Body запроса (clientPhone)
│   └── Заголовке X-Client-Phone
└── PIN-код проверяется ЛОКАЛЬНО на устройстве

Защита API:
├── sanitizePhone() — очистка телефона от спецсимволов
├── sanitizeId() — защита от path traversal
├── fileExists() — проверка существования файла
└── Проверка роли для admin-only эндпоинтов
```

### 18.2 Защита данных

```
├── Logger.maskPhone() — маскирование телефона в логах
│   79001234567 → 7900***4567
├── PII не логируется (имена клиентов скрыты в production)
├── FCM-токены хранятся отдельно от профилей
└── Broadcast не требует списка клиентов (отправка всем)
```

### 18.3 Ограничения доступа

```
Только для админа/разработчика:
├── POST /api/loyalty-promo (сохранение настроек)
├── POST /api/loyalty-gamification/settings
├── POST /api/loyalty-gamification/upload-badge
├── POST /api/client-dialogs/:phone/management/send
├── PATCH /api/job-applications/:id/*
└── Настройки уровней и колеса

Для всех ролей:
├── GET /api/loyalty-promo
├── GET /api/loyalty-gamification/settings
├── GET /api/loyalty-gamification/client/:phone
└── Чтение публичных данных

Дедупликация:
├── Job applications — проверка 24 часа
└── Product questions — проверка дублей
```

---

## 19. КАРТА ЗАВИСИМОСТЕЙ

### 19.1 Flutter модули и их связи

```
┌─────────────────────────────────────────────────────────────────────┐
│                     КЛИЕНТСКИЕ МОДУЛИ                                │
│                                                                      │
│  ┌────────────┐     ┌────────────┐     ┌────────────┐              │
│  │  clients/   │────►│  loyalty/   │────►│ fortune_   │              │
│  │  (ядро)     │     │  (баллы)   │     │ wheel/     │              │
│  └─────┬───────┘     └─────┬──────┘     └────────────┘              │
│        │                   │                                         │
│        │    ┌──────────────┘                                         │
│        │    │                                                        │
│        ▼    ▼                                                        │
│  ┌────────────┐     ┌────────────┐     ┌────────────┐              │
│  │  reviews/   │     │ product_   │     │   orders/  │              │
│  │  (отзывы)  │     │ questions/ │     │  (заказы)  │              │
│  └─────┬───────┘     └─────┬──────┘     └─────┬──────┘              │
│        │                   │                   │                     │
│        └───────────┬───────┘                   │                     │
│                    │                           │                     │
│                    ▼                           ▼                     │
│  ┌────────────────────────┐     ┌────────────────────────┐         │
│  │    app/pages/           │     │    shared/providers/    │         │
│  │  MyDialogsPage          │     │  CartProvider           │         │
│  │  ClientFunctionsPage    │     │  OrderProvider          │         │
│  │  MainMenuPage           │     │                         │         │
│  └────────────┬────────────┘     └────────────────────────┘         │
│               │                                                      │
│               ▼                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                  ОБЩИЕ ЗАВИСИМОСТИ                           │    │
│  │                                                              │    │
│  │  BaseHttpService ← ApiConstants                              │    │
│  │  SharedPreferences ← LoyaltyStorage                          │    │
│  │  FirebaseService ← NotificationService                       │    │
│  │  MediaUploadService ← ImagePicker                            │    │
│  │  Logger (маскирование PII)                                   │    │
│  │  flutter_screenutil (адаптивный UI)                          │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### 19.2 Что от чего зависит

```
MyDialogsPage зависит от:
  ├── NetworkMessageService
  ├── ManagementMessageService
  ├── ProductQuestionService
  ├── ReviewService
  ├── ClientGroupChatService
  └── SharedPreferences (phone, name)

LoyaltyPage зависит от:
  ├── LoyaltyService
  ├── LoyaltyGamificationService
  ├── LoyaltyStorage
  ├── FirebaseService (проверка уведомлений)
  └── UserRoleService (показ админ-настроек)

CartPage зависит от:
  ├── CartProvider
  ├── OrderProvider
  └── NotificationService

ClientWheelPage зависит от:
  ├── LoyaltyGamificationService
  └── 3 AnimationController'а

RegistrationPage зависит от:
  ├── RegistrationService
  ├── LoyaltyService
  ├── AuthService
  ├── UserRoleService
  ├── ReferralService
  ├── FirebaseService
  └── SharedPreferences
```

---

## 20. ДИАГРАММА ПОТОКОВ ДАННЫХ

### 20.1 Регистрация нового клиента

```
Клиент                        Flutter                         Сервер
  │                              │                              │
  │  Ввод данных                 │                              │
  ├─────────────────────────────►│                              │
  │                              │  POST /api/loyalty/register  │
  │                              ├─────────────────────────────►│
  │                              │                     создать  │
  │                              │◄─────────────────────────────┤
  │                              │  POST /api/clients           │
  │                              ├─────────────────────────────►│
  │                              │                   сохранить  │
  │                              │◄─────────────────────────────┤
  │                              │  SharedPreferences.save()    │
  │                              │  LoyaltyStorage.save()       │
  │                              │  FCM Token → сервер          │
  │  Переход в MainMenuPage      │                              │
  │◄─────────────────────────────┤                              │
```

### 20.2 Создание заказа

```
Клиент                        Flutter                         Сервер
  │                              │                              │
  │  Меню → Добавить в корзину   │                              │
  ├─────────────────────────────►│                              │
  │                              │  CartProvider.addItem()      │
  │                              │  (локальное состояние)       │
  │                              │                              │
  │  Корзина → Оформить          │                              │
  ├─────────────────────────────►│                              │
  │                              │  POST /api/orders            │
  │                              ├─────────────────────────────►│
  │                              │              { orderNumber } │
  │                              │◄─────────────────────────────┤
  │                              │                              │
  │  [Ожидание...]               │                              │
  │                              │     Push: "Заказ принят"     │
  │  Уведомление ◄───────────────┤◄─────────────────────────────┤
  │                              │                              │
  │  Заказы → Статус             │                              │
  ├─────────────────────────────►│  GET /api/orders?clientPhone │
  │                              ├─────────────────────────────►│
  │  [completed] ◄───────────────┤◄─────────────────────────────┤
```

### 20.3 Вращение колеса

```
Клиент                        Flutter                         Сервер
  │                              │                              │
  │  Лояльность → Колесо         │                              │
  ├─────────────────────────────►│                              │
  │                              │  GET /api/loyalty-gam/client │
  │                              ├─────────────────────────────►│
  │                              │        { spinsAvailable: 2 } │
  │                              │◄─────────────────────────────┤
  │                              │                              │
  │  Нажать «Крутить»            │                              │
  ├─────────────────────────────►│                              │
  │                              │  POST /api/loyalty-gam/spin  │
  │                              ├─────────────────────────────►│
  │                              │     { sectorIndex: 3,        │
  │                              │       prize: "Латте" }       │
  │                              │◄─────────────────────────────┤
  │                              │                              │
  │  Анимация вращения (5 сек)   │                              │
  │  ████████████████████ 100%   │                              │
  │                              │                              │
  │  🎉 «Поздравляем!            │                              │
  │      Вы выиграли Латте!»     │                              │
  │                              │                              │
  │  Показать QR → Кассиру       │                              │
  ├─────────────────────────────►│  POST /issue-prize           │
  │                              ├─────────────────────────────►│
  │  ✅ Приз выдан               │◄─────────────────────────────┤
```

### 20.4 Поиск товара (полный цикл)

```
Клиент                        Flutter                         Сервер        Сотрудник
  │                              │                              │               │
  │  Поиск → Кофейня → Вопрос   │                              │               │
  ├─────────────────────────────►│  POST /api/product-questions │               │
  │                              ├─────────────────────────────►│               │
  │                              │                   { id }     │  Push         │
  │                              │◄─────────────────────────────┤──────────────►│
  │                              │                              │               │
  │  [Ожидание ответа]           │                              │  Ответ        │
  │                              │                              │◄──────────────┤
  │                              │     Push: "Ответ на вопрос"  │               │
  │  Уведомление ◄───────────────┤◄─────────────────────────────┤               │
  │                              │                              │               │
  │  Диалоги → Поиск товара      │                              │               │
  ├─────────────────────────────►│  GET /client/:phone/grouped  │               │
  │                              ├─────────────────────────────►│               │
  │  Ответ: "Да, есть!" ◄───────┤◄─────────────────────────────┤               │
```

---

## ИТОГОВАЯ СТАТИСТИКА

```
┌─────────────────────────────────────────┐
│        КЛИЕНТСКИЙ МОДУЛЬ В ЦИФРАХ       │
├─────────────────────────────────────────┤
│                                         │
│  📄 Страницы (Pages):           32      │
│  📦 Модели данных (Models):     33      │
│  ⚙️ Сервисы (Services):         12      │
│  🎨 Виджеты (Widgets):           4      │
│  🔗 API эндпоинты:              76      │
│  📁 Директории на сервере:      12      │
│  🔔 Типы Push-уведомлений:       6      │
│  🎯 Пунктов меню клиента:        9      │
│  🎮 Уровней геймификации:       5+      │
│  📊 Провайдеров состояния:       3      │
│                                         │
│  Модули:                                │
│  ├── Клиенты и диалоги (3 уровня)      │
│  ├── Лояльность и геймификация          │
│  ├── Колесо фортуны                     │
│  ├── Отзывы                             │
│  ├── Поиск товара                       │
│  ├── Меню и заказы                      │
│  ├── Заявки на работу                   │
│  └── Кофейни на карте                   │
│                                         │
│  Тема: Dark Emerald                     │
│  ├── Primary:  #1A4D4D                  │
│  ├── Dark:     #0D2E2E                  │
│  ├── Night:    #051515                  │
│  └── Gold:     #D4AF37                  │
│                                         │
└─────────────────────────────────────────┘
```

---

> **Этот документ охватывает 100% функциональности, доступной клиенту приложения Arabica.**
> Каждый файл, модель, сервис, API-эндпоинт и поток данных задокументирован.

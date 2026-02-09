# Arabica - Полная архитектурная документация

**Версия:** 2.4.0
**Дата обновления:** 2026-02-09
**Автор:** Claude Code (полный архитектурный анализ + аудит безопасности + полный аудит 09.02.2026)
**Назначение:** Исчерпывающая документация для любого IT-специалиста

---

## ОГЛАВЛЕНИЕ

1. [Общая архитектура системы](#1-общая-архитектура-системы)
2. [Запуск приложения (App Flow)](#2-запуск-приложения)
3. [Система авторизации](#3-система-авторизации)
4. [Flutter модули (35 штук)](#4-flutter-модули)
5. [Сервер (loyalty-proxy)](#5-сервер-loyalty-proxy)
6. [Потоки данных](#6-потоки-данных)
7. [Автоматизация (Schedulers)](#7-автоматизация-schedulers)
8. [Система баллов и эффективности](#8-система-баллов-и-эффективности)
9. [Роли и матрица доступа](#9-роли-и-матрица-доступа)
10. [Структура данных (/var/www/)](#10-структура-данных)
11. [Слабые места и рекомендации](#11-слабые-места-и-рекомендации)
12. [Карта связей модулей](#12-карта-связей-модулей)
13. [Результаты аудита 09.02.2026](#13-результаты-аудита)
14. [Глоссарий](#14-глоссарий)

---

# 1. ОБЩАЯ АРХИТЕКТУРА СИСТЕМЫ

## 1.1 Обзор системы

**Arabica** — комплексная система управления сетью кофеен, включающая:
- Мобильное приложение (Flutter) для клиентов, сотрудников и администраторов
- Backend сервер (Node.js + Express) для API и автоматизации
- Файловое хранилище (JSON) для всех данных
- Push-уведомления через Firebase Cloud Messaging
- Telegram-бот для OTP авторизации

## 1.2 Технологический стек

| Компонент | Технология | Версия |
|-----------|------------|--------|
| Mobile App | Flutter (Dart) | 3.x |
| Backend | Node.js + Express | 18+ |
| Database | File-based JSON | - |
| Push Notifications | Firebase Cloud Messaging | - |
| Hosting | nginx + PM2 | - |
| Domain | arabica26.ru | - |
| Auth Bot | Telegram Bot API | - |
| AI (в разработке) | Python + TensorFlow | - |

## 1.3 Высокоуровневая архитектура

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         MOBILE APP (Flutter 3.x)                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌───────────┐  │  │
│  │   │ Клиент  │  │Сотрудник│  │Менеджер │  │  Админ  │  │ Developer │  │  │
│  │   │  (30%)  │  │  (50%)  │  │  (10%)  │  │  (9%)   │  │   (1%)    │  │  │
│  │   └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘  └─────┬─────┘  │  │
│  │        │            │            │            │              │        │  │
│  │        └────────────┴────────────┴────────────┴──────────────┘        │  │
│  │                                  │                                     │  │
│  │                    ┌─────────────┴─────────────┐                      │  │
│  │                    │     BaseHttpService       │                      │  │
│  │                    │     (lib/core/services)   │                      │  │
│  │                    └─────────────┬─────────────┘                      │  │
│  └──────────────────────────────────┼────────────────────────────────────┘  │
└─────────────────────────────────────┼───────────────────────────────────────┘
                                      │ HTTPS (port 443)
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SERVER (arabica26.ru)                           │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         nginx (reverse proxy)                          │  │
│  │                    SSL: Let's Encrypt (auto-renew)                     │  │
│  └───────────────────────────────┬───────────────────────────────────────┘  │
│                                  │ port 3000                                 │
│  ┌───────────────────────────────▼───────────────────────────────────────┐  │
│  │                    Node.js + Express (PM2)                             │  │
│  │                      loyalty-proxy/index.js                            │  │
│  │  ┌─────────────┬─────────────┬─────────────┬─────────────────────┐    │  │
│  │  │  56 API     │ 8 Schedulers│  WebSocket  │  Static Files       │    │  │
│  │  │  modules    │ (cron jobs) │  (chat)     │  (photos, media)    │    │  │
│  │  └─────────────┴─────────────┴─────────────┴─────────────────────┘    │  │
│  └───────────────────────────────┬───────────────────────────────────────┘  │
│                                  │                                           │
│       ┌──────────────────────────┼──────────────────────────┐               │
│       │                          │                          │               │
│  ┌────▼─────┐           ┌────────▼────────┐         ┌───────▼───────┐       │
│  │ /var/www │           │  Firebase FCM   │         │  Telegram Bot │       │
│  │  (JSON)  │           │  (push notify)  │         │  (OTP auth)   │       │
│  │ 70+ dirs │           │                 │         │               │       │
│  └──────────┘           └─────────────────┘         └───────────────┘       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## 1.4 Структура проекта

```
arabica2026/
├── android/                        # Android конфигурация (Gradle, manifest)
├── ios/                            # iOS конфигурация (Xcode project)
├── lib/                            # Flutter исходный код
│   ├── main.dart                   # Точка входа приложения
│   ├── app/                        # Главные страницы и сервисы
│   │   ├── pages/
│   │   │   ├── main_menu_page.dart
│   │   │   ├── my_dialogs_page.dart
│   │   │   └── reports_page.dart
│   │   └── services/
│   ├── core/                       # Базовые сервисы и утилиты
│   │   ├── constants/
│   │   │   └── api_constants.dart  # URL сервера, таймауты
│   │   ├── services/
│   │   │   ├── base_http_service.dart
│   │   │   ├── firebase_service.dart
│   │   │   ├── notification_service.dart
│   │   │   └── background_gps_service.dart
│   │   └── utils/
│   │       ├── logger.dart
│   │       ├── cache_manager.dart
│   │       └── date_formatter.dart
│   ├── features/                   # 33 функциональных модуля
│   │   ├── auth/                   # Авторизация
│   │   ├── attendance/             # Посещаемость
│   │   ├── shifts/                 # Пересменки
│   │   ├── ... (ещё 30 модулей)
│   │   └── ai_training/            # ИИ распознавание (Z-отчёты, сигареты)
│   └── shared/                     # Общие компоненты
│       ├── dialogs/
│       ├── widgets/
│       └── providers/
├── loyalty-proxy/                  # Node.js сервер
│   ├── index.js                    # Точка входа (middleware, schedulers, routes)
│   ├── api/                        # 49 API модулей
│   ├── modules/                    # Вспомогательные модули
│   ├── services/                   # Сервисы (Telegram bot)
│   ├── utils/                      # Утилиты (cache, pagination)
│   └── efficiency_calc.js          # Расчёт эффективности
├── test/                           # 475 тестов (97% покрытие)
├── assets/                         # Ресурсы (изображения, шрифты)
├── pubspec.yaml                    # Flutter зависимости
├── ARCHITECTURE_COMPLETE.md        # Этот файл
├── CLAUDE.md                       # Правила для Claude Code
└── RELEASE_CHECKLIST.md            # Чеклист релиза
```

## 1.5 Сетевая конфигурация

| Параметр | Значение |
|----------|----------|
| Домен | arabica26.ru |
| SSL | Let's Encrypt (auto-renew) |
| nginx порт | 443 (HTTPS), 80 (redirect) |
| Node.js порт | 3000 |
| WebSocket | wss://arabica26.ru/ws |
| API базовый URL | https://arabica26.ru/api |
| Статика (nginx) | shift-photos/, shift-question-photos/, shift-handover-question-photos/, shift-reference-photos/, training-articles-media/, product-question-photos/, task-media/, chat-media/ |

## 1.6 Безопасность сервера

```javascript
// Middleware стек (порядок применения)
1. bodyParser.json({ limit: "50mb" })     // Парсинг JSON
2. helmet()                                // Security headers (XSS, clickjacking)
3. cors(corsOptions)                       // CORS (только разрешённые домены)
4. compression({ level: 6 })               // GZIP сжатие (10MB → ~1MB)
5. trust proxy                             // Для работы за nginx
6. apiKeyMiddleware                        // API ключ (опционально)
7. rateLimiter                             // 500 req/min общий, 50 req/min финансы
```

**Rate Limiting:**
- Общий лимит: 500 запросов/минуту с одного IP
- Финансовые операции: 50 запросов/минуту (withdrawals, bonuses, rko)

---

# 2. ЗАПУСК ПРИЛОЖЕНИЯ

## 2.1 Точка входа (main.dart)

```dart
// Файл: lib/main.dart
// Последовательность инициализации:

void main() async {
  // 1. Инициализация Flutter binding
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Firebase Core + Messaging
  await FirebaseWrapper.initializeApp();        // ~200ms
  await FirebaseService.initialize();           // ~100ms

  // 3. Локальные уведомления
  await NotificationService.initialize();       // ~50ms

  // 4. Геофенсинг (для уведомлений "Я на работе")
  await BackgroundGpsService.initialize();      // ~100ms
  await BackgroundGpsService.start();

  // 5. Фоновая синхронизация (НЕ блокирует UI)
  Future.microtask(() {
    ShiftSyncService.syncAllReports();
  });

  // 6. Запуск приложения
  runApp(const ArabicaApp());
}
```

## 2.2 Обёртки провайдеров

```dart
// ArabicaApp оборачивает всё в провайдеры состояния:

CartProviderScope(                    // Состояние корзины заказов
  child: OrderProviderScope(          // Состояние текущего заказа
    child: MaterialApp(
      home: _CheckRegistrationPage(), // Проверка регистрации
    ),
  ),
)
```

## 2.3 Дерево решений при запуске

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        _CheckRegistrationPage                                │
│                        (lib/main.dart:134)                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Шаг 1: Читаем SharedPreferences                                           │
│   ─────────────────────────────────                                         │
│   • user_phone     - номер телефона                                         │
│   • user_name      - имя пользователя                                       │
│   • is_registered  - флаг регистрации                                       │
│                                                                              │
│                              ▼                                               │
│   ┌────────────────────────────────────────────────────────────────────┐    │
│   │                    phone == null?                                   │    │
│   └─────────────┬──────────────────────────────────────┬───────────────┘    │
│                 │ Да                                   │ Нет                 │
│                 ▼                                      ▼                     │
│   ┌─────────────────────┐              ┌───────────────────────────────┐    │
│   │   RegistrationPage  │              │   phone + is_registered?      │    │
│   │   (регистрация)     │              └────────────┬──────────────────┘    │
│   └─────────────────────┘                           │                        │
│                                          ┌──────────┴──────────┐             │
│                                          │ Да                  │ Нет         │
│                                          ▼                     ▼             │
│                           ┌──────────────────────┐  ┌──────────────────────┐│
│                           │ AuthService          │  │ LoyaltyService       ││
│                           │ .getAuthStatus()     │  │ .fetchByPhone()      ││
│                           └──────────┬───────────┘  │ (проверка в базе)    ││
│                                      │              └──────────────────────┘│
│                                      ▼                                       │
│                           ┌──────────────────────┐                          │
│                           │    hasPin == true?   │                          │
│                           └─────────┬────────────┘                          │
│                        ┌────────────┴────────────┐                          │
│                        │ Да                      │ Нет                      │
│                        ▼                         ▼                          │
│           ┌─────────────────────┐   ┌─────────────────────┐                │
│           │    PinEntryPage     │   │    PinSetupPage     │                │
│           │  (ввод PIN-кода)    │   │  (создание PIN)     │                │
│           └─────────┬───────────┘   └─────────┬───────────┘                │
│                     │                         │                             │
│                     └────────────┬────────────┘                             │
│                                  ▼                                          │
│                     ┌─────────────────────┐                                 │
│                     │    MainMenuPage     │                                 │
│                     │   (главное меню)    │                                 │
│                     └─────────────────────┘                                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 2.4 Сервисы инициализируемые при запуске

| Сервис | Файл | Назначение | Блокирующий? |
|--------|------|------------|--------------|
| FirebaseWrapper | `core/services/firebase_wrapper.dart` | Firebase Core init | Да |
| FirebaseService | `core/services/firebase_service.dart` | FCM токены, push | Да |
| NotificationService | `core/services/notification_service.dart` | Локальные уведомления | Да |
| BackgroundGpsService | `core/services/background_gps_service.dart` | Геофенсинг | Да |
| ShiftSyncService | `features/shifts/services/shift_sync_service.dart` | Синхронизация отчётов | Нет (async) |

---

# 3. СИСТЕМА АВТОРИЗАЦИИ

## 3.1 Архитектура авторизации

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      FLUTTER (lib/features/auth/)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  pages/                                   services/                          │
│  ├── pin_entry_page.dart                  ├── auth_service.dart (singleton)  │
│  ├── pin_setup_page.dart                  ├── secure_storage_service.dart    │
│  └── forgot_pin_page.dart                 ├── device_service.dart            │
│                                           └── biometric_service.dart         │
│  models/                                                                     │
│  ├── auth_session.dart                    widgets/                           │
│  └── auth_credentials.dart                ├── pin_input_widget.dart          │
│                                           └── otp_input_widget.dart          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTPS
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      SERVER (loyalty-proxy/api/auth_api.js)                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Endpoints:                              Данные:                             │
│  POST /api/auth/register                 /var/www/auth-sessions/{phone}.json │
│  POST /api/auth/login                    /var/www/auth-pins/{phone}.json     │
│  POST /api/auth/request-otp              /var/www/auth-otp/{phone}.json      │
│  POST /api/auth/verify-otp                                                   │
│  POST /api/auth/reset-pin                                                    │
│  POST /api/auth/validate-session                                             │
│  POST /api/auth/logout                                                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Telegram API
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      TELEGRAM BOT (@ArabicaAuthBot26_bot)                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Файл: loyalty-proxy/services/telegram_bot_service.js                        │
│                                                                              │
│  Команды:                                                                    │
│  • /start           → Показать кнопку "Поделиться номером"                  │
│  • /code {phone}    → Получить код вручную                                  │
│                                                                              │
│  OTP параметры:                                                              │
│  • Длина кода: 6 цифр                                                       │
│  • TTL: 5 минут                                                             │
│  • Макс. попыток: 3                                                         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 3.2 Flow: Первичная регистрация

```
┌────────┐         ┌────────────────┐         ┌────────────┐
│  User  │         │   Flutter App  │         │   Server   │
└────┬───┘         └───────┬────────┘         └─────┬──────┘
     │                     │                        │
     │ 1. Ввод телефона    │                        │
     │     + имя           │                        │
     │────────────────────>│                        │
     │                     │                        │
     │ 2. Создание PIN     │                        │
     │    (4-6 цифр)       │                        │
     │────────────────────>│                        │
     │                     │                        │
     │                     │ 3. POST /api/auth/register
     │                     │    {phone, name, pin}  │
     │                     │───────────────────────>│
     │                     │                        │
     │                     │                        │ 4. Сервер:
     │                     │                        │    salt = random(16 bytes)
     │                     │                        │    pinHash = SHA256(pin + salt)
     │                     │                        │    session = random token
     │                     │                        │    save to auth-pins/
     │                     │                        │    save to auth-sessions/
     │                     │                        │
     │                     │  {session, pinHash, salt}
     │                     │<───────────────────────│
     │                     │                        │
     │                     │ 5. Сохранить локально: │
     │                     │    SecureStorage       │
     │                     │    SharedPreferences   │
     │                     │                        │
     │  MainMenuPage       │                        │
     │<────────────────────│                        │
     │                     │                        │
```

**Пример запроса:**
```json
POST /api/auth/register
Content-Type: application/json

{
  "phone": "79001234567",
  "name": "Иван Иванов",
  "pin": "1234",
  "deviceId": "abc123def456",
  "deviceName": "Samsung Galaxy S21"
}
```

**Пример ответа:**
```json
{
  "success": true,
  "session": {
    "sessionToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "phone": "79001234567",
    "name": "Иван Иванов",
    "deviceId": "abc123def456",
    "createdAt": "2026-02-05T10:00:00.000Z",
    "expiresAt": "2026-03-07T10:00:00.000Z",
    "isVerified": true
  },
  "pinHash": "a1b2c3d4e5f6...",
  "salt": "1234567890abcdef"
}
```

## 3.3 Flow: Повторный вход (PIN)

```
┌────────┐         ┌────────────────┐
│  User  │         │   Flutter App  │
└────┬───┘         └───────┬────────┘
     │                     │
     │ 1. Ввод PIN         │
     │────────────────────>│
     │                     │
     │                     │ 2. ЛОКАЛЬНАЯ проверка:
     │                     │    credentials = SecureStorage.get()
     │                     │    computedHash = SHA256(pin + salt)
     │                     │    if (computedHash == pinHash) → OK
     │                     │
     │                     │ 3. Если 5 ошибок подряд:
     │                     │    → Блокировка 15 минут
     │                     │
     │  MainMenuPage       │
     │<────────────────────│ (без обращения к серверу!)
     │                     │
```

**Важно:** Повторный вход происходит ЛОКАЛЬНО без обращения к серверу. Это позволяет работать офлайн.

## 3.4 Flow: Сброс PIN через Telegram

```
┌────────┐      ┌──────────┐      ┌────────┐      ┌──────────┐
│  User  │      │  Flutter │      │ Server │      │ Telegram │
└────┬───┘      └────┬─────┘      └────┬───┘      └────┬─────┘
     │               │                 │               │
     │ "Забыли PIN?" │                 │               │
     │──────────────>│                 │               │
     │               │                 │               │
     │               │ POST /api/auth/request-otp     │
     │               │ {phone}         │               │
     │               │────────────────>│               │
     │               │                 │               │
     │               │                 │ Generate OTP  │
     │               │                 │ (6 digits)    │
     │               │                 │ Save to       │
     │               │                 │ auth-otp/     │
     │               │                 │               │
     │               │                 │──────────────>│ Отправить код
     │               │                 │               │ пользователю
     │               │ {telegramBotLink}               │
     │               │<────────────────│               │
     │               │                 │               │
     │ Открыть Telegram                │               │
     │<──────────────│                 │               │
     │               │                 │               │
     │ Нажать "Поделиться номером"     │               │
     │─────────────────────────────────────────────────>│
     │               │                 │               │
     │<─────────────────────────────────────────────────│ Получить OTP
     │               │                 │               │
     │ Ввести OTP    │                 │               │
     │──────────────>│                 │               │
     │               │                 │               │
     │               │ POST /api/auth/verify-otp      │
     │               │ {phone, code}   │               │
     │               │────────────────>│               │
     │               │                 │               │
     │               │ {registrationToken}             │
     │               │<────────────────│               │
     │               │                 │               │
     │ Создать новый PIN               │               │
     │──────────────>│                 │               │
     │               │                 │               │
     │               │ POST /api/auth/reset-pin       │
     │               │ {phone, pin, registrationToken}│
     │               │────────────────>│               │
     │               │                 │               │
     │               │ {session}       │               │
     │               │<────────────────│               │
     │               │                 │               │
     │ MainMenuPage  │                 │               │
     │<──────────────│                 │               │
```

## 3.5 Параметры безопасности

| Параметр | Значение | Где настраивается |
|----------|----------|-------------------|
| PIN длина | 4-6 цифр | auth_api.js |
| Hash алгоритм | SHA-256 + salt | auth_api.js |
| Salt длина | 16 bytes (hex) | auth_api.js |
| Сессия TTL | 30 дней | auth_api.js |
| Макс. попыток PIN | 5 | auth_service.dart |
| Блокировка | 15 минут | auth_service.dart |
| OTP длина | 6 цифр | telegram_bot_service.js |
| OTP TTL | 5 минут | telegram_bot_service.js |
| OTP макс. попыток | 3 | telegram_bot_service.js |

## 3.6 Модели данных

### AuthSession (auth_session.dart)
```dart
class AuthSession {
  final String sessionToken;    // JWT токен
  final String phone;           // Телефон пользователя
  final String? name;           // Имя пользователя
  final String deviceId;        // ID устройства
  final String? deviceName;     // Название устройства
  final DateTime createdAt;     // Дата создания
  final DateTime expiresAt;     // Дата истечения (30 дней)
  final bool isVerified;        // Верифицирован ли

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
```

### AuthCredentials (auth_credentials.dart)
```dart
class AuthCredentials {
  final String pinHash;         // SHA256(pin + salt)
  final String salt;            // 16 bytes hex
  final DateTime createdAt;     // Дата создания
  final int failedAttempts;     // Счётчик ошибок (0-5)
  final DateTime? lockedUntil;  // Дата разблокировки

  static const maxFailedAttempts = 5;
  static const lockDuration = Duration(minutes: 15);

  bool get isLocked => lockedUntil != null &&
                       DateTime.now().isBefore(lockedUntil!);
}
```

---

# 4. FLUTTER МОДУЛИ

## 4.1 Обзор модулей (35 штук)

| # | Модуль | Директория | Роли | Статус | Описание |
|---|--------|------------|------|--------|----------|
| 1 | Авторизация | `auth/` | Все | Работает | PIN, OTP, биометрия |
| 2 | Посещаемость | `attendance/` | Сотрудник, Админ | Работает | "Я на работе" |
| 3 | Пересменки | `shifts/` | Сотрудник, Админ | Работает | Отчёты с фото |
| 4 | Сдача смены | `shift_handover/` | Сотрудник, Админ | Работает | Закрытие дня |
| 5 | Пересчёты | `recount/` | Сотрудник, Админ | Работает | Инвентаризация |
| 6 | Конверты | `envelope/` | Сотрудник, Админ | Работает | Сдача наличных |
| 7 | РКО | `rko/` | Сотрудник, Админ | Работает | Касс. ордера |
| 8 | Заказы | `orders/` | Клиент, Сотрудник, Админ | Работает | Корзина, заказы |
| 9 | Меню | `menu/` | Клиент, Админ | Работает | Каталог товаров |
| 10 | Рецепты | `recipes/` | Сотрудник, Админ | Работает | Приготовление |
| 11 | Сотрудники | `employees/` | Админ | Работает | Управление |
| 12 | Магазины | `shops/` | Клиент (карта), Админ | Работает | Локации |
| 13 | График работы | `work_schedule/` | Сотрудник, Админ | Работает | Расписание |
| 14 | Эффективность | `efficiency/` | Сотрудник, Админ | Работает | 12 категорий |
| 15 | Рейтинг | `rating/` | Сотрудник | Работает | Топ сотрудников |
| 16 | Колесо удачи | `fortune_wheel/` | Сотрудник, Админ | Работает | Призы |
| 17 | Задачи | `tasks/` | Сотрудник, Админ | Работает | Задания |
| 18 | Обучение | `training/` | Сотрудник, Админ | Работает | Статьи |
| 19 | Тестирование | `tests/` | Сотрудник, Админ | Работает | Квизы |
| 20 | Отзывы | `reviews/` | Клиент, Админ | Работает | Feedback |
| 21 | Поиск товара | `product_questions/` | Клиент, Сотрудник, Админ | Работает | Диалоги |
| 22 | Лояльность | `loyalty/` | Клиент, Админ | Работает | Баллы, геймификация, колесо удачи, значки |
| 23 | Рефералы | `referrals/` | Сотрудник, Админ | Работает | Привлечение |
| 24 | Заявки на работу | `job_application/` | Клиент, Админ | Работает | HR |
| 25 | Чат сотрудников | `employee_chat/` | Сотрудник | Работает | Мессенджер |
| 26 | Клиенты | `clients/` | Клиент, Админ | Работает | Диалоги |
| 27 | Премии/штрафы | `bonuses/` | Админ | Работает | Начисления |
| 28 | Главная касса | `main_cash/` | Админ | Работает | Финансы |
| 29 | Поставщики | `suppliers/` | Админ | Работает | Закупки |
| 30 | Очистка данных | `data_cleanup/` | Админ | Работает | Maintenance |
| 31 | KPI | `kpi/` | Админ | Работает | Аналитика |
| 32 | ИИ распознавание | `ai_training/` | Админ | В разработке | Z-отчёты, сигареты, шаблоны фото |
| 33 | Управление сетью | `network_management/` | Developer | Работает | Настройки |
| 34 | Кофемашины | `coffee_machine/` | Сотрудник, Админ | Работает | OCR счётчиков, шаблоны, автоматизация |
| 35 | Передача смен | `shift_transfers/` | Сотрудник, Админ | Работает | Обмен сменами между сотрудниками |

---

## 4.2 Детальное описание модулей

### МОДУЛЬ: attendance (Посещаемость)

**Директория:** `lib/features/attendance/`

```
attendance/
├── models/
│   ├── attendance_model.dart           # Модель отметки
│   ├── pending_attendance_model.dart   # Pending отметка
│   └── shop_attendance_summary.dart    # Сводка по магазину
├── services/
│   ├── attendance_service.dart         # CRUD операции
│   └── attendance_report_service.dart  # Отчёты
└── pages/
    ├── attendance_page.dart            # Кнопка "Я на работе"
    ├── attendance_shop_selection_page.dart
    ├── attendance_month_page.dart      # Календарь
    ├── attendance_employee_detail_page.dart
    └── attendance_reports_page.dart    # Отчёты (админ)
```

**Роли:** Сотрудник, Админ

**API Endpoints:**

| Method | Path | Описание |
|--------|------|----------|
| GET | `/api/attendance` | Список отметок |
| POST | `/api/attendance` | Создать отметку "Я на работе" |
| GET | `/api/attendance/pending` | Pending отметки (автоматизация) |
| PUT | `/api/attendance/:id/confirm` | Подтвердить (админ) |
| GET | `/api/attendance/check` | Проверить отметку сегодня |

**Пример запроса POST /api/attendance:**
```json
{
  "employeePhone": "79001234567",
  "employeeName": "Иван Иванов",
  "shopAddress": "ул. Ленина, 1",
  "timestamp": "2026-02-05T08:55:00.000Z",
  "isOnTime": true,
  "shiftType": "morning",
  "latitude": 55.7558,
  "longitude": 37.6173
}
```

**Пример ответа:**
```json
{
  "success": true,
  "id": "att_1707123456789",
  "message": "Отметка сохранена",
  "isOnTime": true
}
```

**Серверные данные:**
- `/var/www/attendance/{id}.json` - подтверждённые отметки
- `/var/www/attendance-pending/{id}.json` - ожидающие подтверждения

**Автоматизация:** `attendance_automation_scheduler.js`
- Интервал: каждые 5 минут
- Дедлайн: 10:00 (утренняя смена), 14:00 (вечерняя смена)
- Штраф за опоздание: -5 баллов

---

### МОДУЛЬ: shifts (Пересменки)

**Директория:** `lib/features/shifts/`

```
shifts/
├── models/
│   ├── shift_report_model.dart        # Полный отчёт
│   ├── pending_shift_report_model.dart
│   ├── shift_question_model.dart      # Вопрос анкеты
│   └── shift_shortage_model.dart      # Недостача
├── services/
│   ├── shift_report_service.dart      # CRUD отчётов
│   ├── shift_question_service.dart    # Управление вопросами
│   ├── pending_shift_service.dart     # Pending отчёты
│   └── shift_sync_service.dart        # Фоновая синхронизация
└── pages/
    ├── shift_shop_selection_page.dart
    ├── shift_questions_page.dart       # Анкета
    ├── shift_report_view_page.dart     # Просмотр отчёта
    ├── shift_reports_list_page.dart    # Список (админ)
    ├── shift_summary_report_page.dart  # Сводный отчёт
    └── shift_photo_gallery_page.dart   # Фото
```

**Роли:** Сотрудник, Админ

**API Endpoints:**

| Method | Path | Описание |
|--------|------|----------|
| GET | `/api/shift-reports` | Все отчёты |
| POST | `/api/shift-reports` | Создать отчёт |
| GET | `/api/shift-reports/:id` | Один отчёт |
| PUT | `/api/shift-reports/:id/confirm` | Подтвердить с оценкой |
| GET | `/api/shift-questions` | Вопросы анкеты |
| POST | `/api/shift-questions` | Создать вопрос |
| GET | `/api/pending-shift-reports` | Pending отчёты |
| POST | `/upload-photo` | Загрузить фото |

**Пример запроса POST /api/shift-reports:**
```json
{
  "id": "shift_report_2026-02-05_79001234567",
  "employeeName": "Иван Иванов",
  "employeePhone": "79001234567",
  "shopAddress": "ул. Ленина, 1",
  "handoverDate": "2026-02-05",
  "shiftType": "morning",
  "status": "review",
  "questions": [
    {
      "questionId": "q1",
      "question": "Витрина чистая?",
      "answer": "Да",
      "photoUrl": "https://arabica26.ru/shift-photos/photo1.jpg"
    }
  ],
  "photos": [
    "https://arabica26.ru/shift-photos/photo1.jpg",
    "https://arabica26.ru/shift-photos/photo2.jpg"
  ]
}
```

**Пример ответа подтверждения:**
```json
{
  "success": true,
  "message": "Оценка сохранена",
  "efficiencyPoints": 1.5
}
```

**Серверные данные:**
- `/var/www/shift-reports/{id}.json` - отчёты
- `/var/www/shift-questions/questions.json` - вопросы анкеты
- `/var/www/shift-photos/` - загруженные фото

---

### МОДУЛЬ: efficiency (Эффективность)

**Директория:** `lib/features/efficiency/`

```
efficiency/
├── models/
│   ├── efficiency_data_model.dart       # Данные эффективности
│   ├── manager_efficiency_model.dart    # Эффективность менеджера
│   ├── points_settings_model.dart       # Настройки баллов
│   └── settings/                        # 14 типов настроек
│       ├── attendance_points_settings.dart
│       ├── envelope_points_settings.dart
│       ├── shift_points_settings.dart
│       ├── recount_points_settings.dart
│       └── ... (ещё 10 файлов)
├── services/
│   ├── efficiency_data_service.dart     # Загрузка данных
│   ├── efficiency_calculation_service.dart
│   ├── manager_efficiency_service.dart
│   └── points_settings_service.dart
├── pages/
│   ├── my_efficiency_page.dart          # Моя эффективность
│   ├── employees_efficiency_page.dart   # Список сотрудников
│   ├── employee_efficiency_detail_page.dart
│   ├── efficiency_by_shop_page.dart
│   ├── efficiency_analytics_page.dart   # Аналитика
│   └── points_settings_page.dart        # Настройки (админ)
│       └── settings_tabs/               # 16 вкладок настроек
└── widgets/
    ├── efficiency_common_widgets.dart
    ├── settings_slider_widget.dart
    └── time_window_picker_widget.dart
```

**Роли:** Сотрудник (своя), Админ (всех)

**12 категорий эффективности:**

| # | Категория | Источник | Тип | Баллы |
|---|-----------|----------|-----|-------|
| 1 | shifts | shift-reports | Rating 1-10 | -3 ... +2 |
| 2 | recount | recount-reports | Rating 1-10 | -3 ... +2 |
| 3 | handover | shift-handovers | Rating 1-10 | -3 ... +1 |
| 4 | attendance | attendance | Boolean | +0.5 ... +1 |
| 5 | test | test-results | Score 0-20 | -2.5 ... +3.5 |
| 6 | reviews | client-reviews | Rating >= 4 | -1.5 ... +1.5 |
| 7 | productSearch | product-questions | Boolean | 0 ... +1 |
| 8 | orders | orders | Boolean | 0 ... +1 |
| 9 | rko | rko | Boolean | -3 ... +1 |
| 10 | tasks | tasks | Boolean | +1 за выполнение |
| 11 | penalties | efficiency-penalties | Sum | Сумма штрафов |
| 12 | envelope | envelope-reports | Boolean | -5 ... 0 |

**API Endpoints:**

| Method | Path | Описание |
|--------|------|----------|
| GET | `/api/efficiency/reports-batch` | Batch данные за месяц |
| GET | `/api/efficiency-penalties` | Штрафы за месяц |
| POST | `/api/efficiency-penalties` | Создать штраф |
| GET | `/api/manager-efficiency` | Эффективность менеджеров |
| GET | `/api/points-settings/:type` | Настройки баллов |
| POST | `/api/points-settings/:type` | Обновить настройки |

**Серверные данные:**
- `/var/www/efficiency-penalties/{YYYY-MM}.json` - штрафы по месяцам
- `/var/www/points-settings/*.json` - настройки баллов

---

### МОДУЛЬ: employee_chat (Чат сотрудников)

**Директория:** `lib/features/employee_chat/`

```
employee_chat/
├── models/
│   ├── employee_chat_model.dart         # Модель чата
│   └── employee_chat_message_model.dart # Сообщение
├── services/
│   ├── employee_chat_service.dart       # REST API
│   ├── chat_websocket_service.dart      # WebSocket real-time
│   └── client_group_chat_service.dart   # Группы
└── pages/
    ├── employee_chats_list_page.dart    # Список чатов
    ├── employee_chat_page.dart          # Экран чата
    ├── new_chat_page.dart               # Новый личный чат
    ├── create_group_page.dart           # Создание группы
    ├── group_info_page.dart             # Инфо о группе
    └── shop_chat_members_page.dart      # Участники
```

**Роли:** Сотрудник

**4 типа чатов:**
- `general` - Общий чат всех сотрудников
- `shop` - Чат магазина
- `private` - Личный чат 1-на-1
- `group` - Групповой чат

**API Endpoints:**

| Method | Path | Описание |
|--------|------|----------|
| GET | `/api/employee-chats` | Список чатов |
| GET | `/api/employee-chats/:chatId/messages` | Сообщения чата |
| POST | `/api/employee-chats/:chatId/messages` | Отправить сообщение |
| POST | `/api/employee-chats/group` | Создать группу |
| PUT | `/api/employee-chats/group/:id` | Обновить группу |
| POST | `/api/employee-chats/media` | Загрузить медиа |

**WebSocket Events:**
```javascript
// Подключение
ws.connect('wss://arabica26.ru/ws?phone=79001234567');

// События
'new_message'     // Новое сообщение
'message_read'    // Сообщение прочитано
'typing'          // Пользователь печатает
'online_status'   // Статус онлайн
```

**Серверные данные:**
- `/var/www/employee-chats/` - чаты
- `/var/www/employee-chat-groups/` - группы
- `/var/www/chat-media/` - медиафайлы

---

### МОДУЛЬ: training (Обучение)

**Директория:** `lib/features/training/`

```
training/
├── models/
│   ├── training_model.dart              # Модель статьи (TrainingArticle)
│   └── content_block.dart               # Блок контента (ContentBlock: text/image)
├── services/
│   └── training_article_service.dart    # REST API сервис
└── pages/
    ├── training_page.dart               # Главная страница обучения (список статей + поиск)
    ├── training_article_view_page.dart  # Просмотр статьи (текст + изображения)
    ├── training_article_editor_page.dart     # Редактор статей (админ)
    └── training_articles_management_page.dart # Управление статьями (админ)
```

**Роли:** Сотрудник (чтение), Админ (CRUD)

**Дизайн:** Тёмная изумрудная тема (`_emerald=#1A4D4D`, `_emeraldDark=#0D2E2E`, `_night=#051515`, `_gold=#D4AF37`)

**Ключевые особенности:**
- **Статьи с блочным контентом** — каждая статья содержит массив `contentBlocks` с типами `text` и `image`
- **12 статей** с перенесённым контентом (текст + 150 изображений) с внешних источников (teletype.in, telegra.ph)
- **Умный поиск** — строка поиска с нечётким поиском (алгоритм Левенштейна), ищет по заголовкам, группам и содержимому статей
- **Кэширование изображений** — `cached_network_image` для оффлайн-доступа и быстрой загрузки
- **Сжатые изображения** — 162 фото оптимизированы sharp на сервере (91MB → 14MB, экономия 84%)
- **Видимость** — поле `visibility: "managers"` скрывает статьи от обычных сотрудников
- **Группировка** — статьи сгруппированы по категориям с золотыми заголовками групп
- **Полноэкранный просмотр** — нажатие на изображение открывает его в полный экран с InteractiveViewer (зум)

**Структура данных статьи (JSON):**
```json
{
  "id": "training_article_1765708247730",
  "title": "Название статьи",
  "group": "Категория",
  "content": "Текстовый контент (для обратной совместимости)",
  "url": "https://... (внешняя ссылка, опционально)",
  "visibility": "all | managers",
  "contentBlocks": [
    { "id": "block_1", "type": "text", "content": "Текст блока..." },
    { "id": "block_2", "type": "image", "content": "https://arabica26.ru/training-articles-media/img.jpg", "caption": "Подпись" }
  ],
  "createdAt": "2025-12-11T...",
  "updatedAt": "2026-02-06T..."
}
```

**Серверные данные:**
- `/var/www/training-articles/` — JSON-файлы статей (по одному на статью)
- `/var/www/training-articles-media/` — изображения статей (162 файла, ~14MB)
- `/var/www/training-articles-media/originals-backup/` — оригинальные несжатые изображения

**API Endpoints:**

| Method | Path | Описание |
|--------|------|----------|
| GET | `/api/training-articles` | Все статьи |
| GET | `/api/training-articles/:id` | Одна статья |
| POST | `/api/training-articles` | Создать статью |
| PUT | `/api/training-articles/:id` | Обновить статью |
| DELETE | `/api/training-articles/:id` | Удалить статью |

---

### МОДУЛЬ: tests (Тестирование)

**Директория:** `lib/features/tests/`

```
tests/
├── models/
│   ├── test_model.dart                  # Модель вопроса (TestQuestion)
│   └── test_result_model.dart           # Результат теста (TestResult)
├── services/
│   ├── test_question_service.dart       # REST API вопросов
│   └── test_result_service.dart         # REST API результатов + начисление баллов
└── pages/
    ├── test_page.dart                   # Прохождение теста (20 вопросов, 7 мин)
    ├── test_report_page.dart            # Отчёт по тестированию (статистика + все результаты)
    ├── test_questions_management_page.dart # Управление вопросами (админ)
    └── test_notifications_page.dart     # Уведомления о новых тестах
```

**Роли:** Сотрудник (прохождение), Админ (управление вопросами, просмотр отчётов)

**Дизайн:** Тёмная изумрудная тема (единая палитра приложения)

**Ключевые особенности:**
- **20 случайных вопросов** из общего банка вопросов
- **Таймер 7 минут** — золотой индикатор, при <1 мин становится красным
- **Автопереход** — после выбора ответа автоматически переходит к следующему вопросу (1.5с правильный, 2с неправильный)
- **Подсветка ответов** — правильный = зелёный, неправильный = красный + подсветка правильного
- **Анимации** — fade-переход между вопросами, elastic-анимация баллов в результатах
- **Начисление баллов** — автоматическое начисление/списание баллов на основе результата
- **Отчёт** — две вкладки: "По сотрудникам" (средний балл за месяц/всего) и "Все результаты"
- **Bottom Sheet детали** — нажатие на сотрудника показывает статистику по месяцам и последний тест
- **Прогресс-бар** — золотой, показывает текущий вопрос из 20

**Структура данных вопроса (JSON):**
```json
{
  "id": "q_1234567890",
  "question": "Текст вопроса?",
  "options": ["Вариант A", "Вариант B", "Вариант C", "Вариант D"],
  "correctAnswer": "Вариант B"
}
```

**Структура данных результата (JSON):**
```json
{
  "employeeName": "Имя сотрудника",
  "employeePhone": "79001234567",
  "score": 16,
  "totalQuestions": 20,
  "percentage": 80,
  "timeSpent": 245,
  "formattedTime": "4:05",
  "shopAddress": "ул. Пример, 1",
  "points": 2.5,
  "completedAt": "2026-02-06T21:18:00.000Z"
}
```

**Серверные данные:**
- `/var/www/test-questions/` — банк вопросов (questions.json)
- `/var/www/test-results/` — результаты по месяцам (YYYY-MM.json)

**API Endpoints:**

| Method | Path | Описание |
|--------|------|----------|
| GET | `/api/test-questions` | Все вопросы |
| POST | `/api/test-questions` | Создать вопрос |
| PUT | `/api/test-questions/:id` | Обновить вопрос |
| DELETE | `/api/test-questions/:id` | Удалить вопрос |
| GET | `/api/test-results` | Результаты тестов |
| POST | `/api/test-results` | Записать результат |

---

# 5. СЕРВЕР (loyalty-proxy)

## 5.1 Структура сервера

```
loyalty-proxy/
├── index.js                              # Точка входа (middleware, schedulers, routes)
│
├── api/                                  # 49 API модулей
│   ├── auth_api.js                       # Авторизация (600 строк)
│   ├── attendance_api.js                 # Посещаемость (380 строк)
│   ├── shifts_api.js                     # Пересменки (520 строк)
│   ├── recount_api.js                    # Пересчёты (450 строк)
│   ├── envelope_api.js                   # Конверты (420 строк)
│   ├── rko_api.js                        # РКО (480 строк)
│   ├── orders_api.js                     # Заказы (450 строк)
│   ├── employees_api.js                  # Сотрудники (450 строк)
│   ├── shops_api.js                      # Магазины (450 строк)
│   ├── tasks_api.js                      # Задачи (520 строк)
│   ├── employee_chat_api.js              # Чат (1386 строк)
│   ├── employee_chat_websocket.js        # WebSocket (450 строк)
│   ├── geofence_api.js                   # Геофенсинг (520 строк)
│   ├── loyalty_api.js                    # Лояльность (480 строк)
│   ├── loyalty_promo_api.js              # Промо-акции (450 строк)
│   ├── master_catalog_api.js             # Мастер-каталог (1306 строк)
│   ├── cigarette_vision_api.js           # ИИ распознавание (880 строк)
│   ├── shift_ai_verification_api.js      # ИИ верификация (871 строк)
│   ├── data_cleanup_api.js               # Очистка данных (576 строк)
│   ├── media_api.js                      # Загрузка медиа (520 строк)
│   ├── points_settings_api.js            # Настройки баллов (1442 строк)
│   ├── efficiency_penalties_api.js       # Штрафы (520 строк)
│   ├── manager_efficiency_api.js         # Эффективность менеджеров (610 строк)
│   ├── product_questions_api.js          # Поиск товара (1290 строк)
│   ├── reviews_api.js                    # Отзывы (400 строк)
│   ├── tests_api.js                      # Тесты (450 строк)
│   ├── training_api.js                   # Обучение (480 строк)
│   ├── work_schedule_api.js              # График работы (420 строк)
│   ├── shift_transfers_api.js            # Передача смен (670 строк)
│   ├── withdrawals_api.js                # Выемки (500 строк)
│   ├── suppliers_api.js                  # Поставщики (480 строк)
│   ├── shop_settings_api.js              # Настройки магазинов (480 строк)
│   ├── shop_coordinates_api.js           # Координаты (450 строк)
│   ├── shop_managers_api.js              # Менеджеры магазинов (520 строк)
│   ├── shop_products_api.js              # Товары магазинов (520 строк)
│   ├── pending_api.js                    # Pending отчёты (770 строк)
│   ├── z_report_api.js                   # Z-отчёты (500 строк)
│   ├── recurring_tasks_api.js            # Циклические задачи (594 строк)
│   ├── task_points_settings_api.js       # Настройки баллов задач (480 строк)
│   ├── clients_api.js                    # Клиенты (661 строк)
│   │
│   │── AUTOMATION SCHEDULERS ──────────────────────────────────────
│   ├── attendance_automation_scheduler.js   # Посещаемость (822 строк)
│   ├── envelope_automation_scheduler.js     # Конверты (650 строк)
│   ├── shift_automation_scheduler.js        # Пересменки (690 строк)
│   ├── shift_handover_automation_scheduler.js # Сдача смены (853 строк)
│   ├── rko_automation_scheduler.js          # РКО (719 строк)
│   ├── recount_automation_scheduler.js      # Пересчёты (788 строк)
│   │
│   │── NOTIFICATIONS ──────────────────────────────────────────────
│   ├── master_catalog_notifications.js
│   ├── product_questions_notifications.js
│   └── shift_transfers_notifications.js
│
├── modules/
│   ├── orders.js                         # Логика заказов
│   └── cigarette-vision.js               # ИИ модуль
│
├── services/
│   └── telegram_bot_service.js           # Telegram бот для OTP
│
├── utils/
│   ├── admin_cache.js                    # Кэш для админ-запросов
│   ├── pagination.js                     # Пагинация
│   ├── async_fs.js                       # Async файловые операции с locking
│   ├── file_lock.js                      # File locking (защита от race conditions)
│   └── test_file_lock.js                 # Тесты для file locking
│
├── efficiency_calc.js                    # Расчёт эффективности (1078 строк)
├── rating_wheel_api.js                   # Рейтинг + колесо
├── referrals_api.js                      # Рефералы
├── job_applications_api.js               # Заявки на работу
├── order_notifications_api.js            # Push заказов
├── order_timeout_api.js                  # Таймауты заказов
├── report_notifications_api.js           # Push отчётов
├── product_questions_penalty_scheduler.js # Штрафы поиска товара
├── recount_points_api.js                 # Баллы за пересчёт
│
├── firebase-admin-config.js              # Firebase конфиг
└── package.json                          # Зависимости
```

**Общая статистика:**
- ~37000 строк JavaScript кода
- 56 API файлов (49 в api/ + 7 в корне loyalty-proxy/)
- 8 Scheduler'ов
- 503+ endpoints

## 5.2 ПОЛНАЯ ТАБЛИЦА API ENDPOINTS (240+)

### AUTH API (Авторизация)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| POST | `/api/auth/send-code` | Отправить OTP код | ❌ |
| POST | `/api/auth/verify-code` | Верифицировать OTP | ❌ |
| POST | `/api/auth/register` | Регистрация с PIN | ❌ |
| POST | `/api/auth/login` | Вход с PIN | ❌ |
| POST | `/api/auth/login-biometric` | Вход по биометрии | ❌ |
| GET | `/api/auth/status/:phone` | Проверить статус авторизации | ❌ |
| POST | `/api/auth/logout` | Выход | ✅ |
| POST | `/api/auth/reset-pin` | Сброс PIN через OTP | ❌ |
| POST | `/api/auth/sessions/invalidate` | Закрыть все сессии | ✅ |

**Пример запроса:**
```bash
curl -X POST http://arabica26.ru:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "79991234567",
    "name": "Иван Петров",
    "pin": "1234",
    "deviceId": "device_123"
  }'
```

**Ответ:**
```json
{
  "success": true,
  "pinHash": "abc123def456...",
  "salt": "salt_xyz789...",
  "session": {
    "sessionToken": "token_xxxxx...",
    "phone": "79991234567",
    "expiresAt": 1709481600000
  }
}
```

### ATTENDANCE API (Посещаемость)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/attendance` | Получить все отметки | ✅ |
| GET | `/api/attendance/:date` | Отметки за день | ✅ |
| POST | `/api/attendance` | Создать отметку | ✅ |
| GET | `/api/attendance/pending` | Pending отметки | ✅ |
| GET | `/api/attendance/failed` | Failed отметки | ✅ |
| POST | `/api/attendance/mark-complete` | Завершить pending | ✅ |
| GET | `/api/attendance/settings` | Настройки | ✅ |
| POST | `/api/attendance/settings` | Сохранить настройки | ✅ |

### SHIFTS API (Пересменки)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/shift-reports` | Все отчёты | ✅ |
| GET | `/api/shift-reports/:date` | Отчёты за день | ✅ |
| POST | `/api/shift-reports` | Создать отчёт | ✅ |
| PUT | `/api/shift-reports/:id` | Обновить отчёт | ✅ |
| POST | `/api/shift-reports/:id/answer` | Ответить на вопрос | ✅ |
| POST | `/api/shift-reports/:id/confirm` | Подтвердить (админ) | ✅ |
| GET | `/api/shift-reports/pending` | Pending отчёты | ✅ |
| GET | `/api/shift-reports/settings` | Настройки | ✅ |

### RECOUNT API (Пересчёты)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/recount-reports` | Все отчёты | ✅ |
| GET | `/api/recount-reports/:date` | Отчёты за день | ✅ |
| POST | `/api/recount-reports` | Создать отчёт | ✅ |
| PUT | `/api/recount-reports/:id` | Обновить | ✅ |
| POST | `/api/recount-reports/:id/confirm` | Подтвердить | ✅ |
| GET | `/api/recount-reports/pending` | Pending | ✅ |

### SHIFT HANDOVER API (Сдача смены)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/shift-handover-reports` | Все отчёты | ✅ |
| GET | `/api/shift-handover-reports/:id` | Один отчёт | ✅ |
| POST | `/api/shift-handover-reports` | Создать отчёт | ✅ |
| PUT | `/api/shift-handover-reports/:id` | Обновить | ✅ |
| POST | `/api/shift-handover-reports/:id/confirm` | Подтвердить | ✅ |
| POST | `/api/shift-handover-reports/:id/reject` | Отклонить | ✅ |
| GET | `/api/shift-handover-reports/pending` | Pending | ✅ |
| GET | `/api/shift-handover-questions` | Вопросы сдачи смены | ✅ |
| POST | `/api/shift-handover-questions` | Создать вопрос | ✅ |
| PUT | `/api/shift-handover-questions/:id` | Обновить вопрос | ✅ |
| DELETE | `/api/shift-handover-questions/:id` | Удалить вопрос | ✅ |

**Типы ответов для вопросов сдачи смены:**

| Тип | answerFormatB | answerFormatC | Описание | Источник фото |
|-----|---------------|---------------|----------|---------------|
| Да/Нет | null/пусто | null/пусто | Выбор Да или Нет | - |
| Фото | `photo` или `free` | null | Требуется фото | Только камера |
| **Скриншот** | `screenshot` | null | Требуется фото | Камера ИЛИ галерея |
| Число | null | `число` | Числовой ввод | - |
| Текст | `text` | null | Текстовый ввод | - |

> **Новое (2026-02-06):** Тип "Скриншот" позволяет сотруднику выбрать фото из галереи или сделать новое на камеру. Используется для вопросов где нужен скриншот приложения или существующее фото.

### ENVELOPE API (Конверты)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/envelope-reports` | Все отчёты | ✅ |
| GET | `/api/envelope-reports/:date` | За день | ✅ |
| POST | `/api/envelope-reports` | Создать | ✅ |
| PUT | `/api/envelope-reports/:id` | Обновить | ✅ |
| POST | `/api/envelope-reports/:id/confirm` | Подтвердить | ✅ |
| GET | `/api/envelope-reports/pending` | Pending | ✅ |
| GET | `/api/envelope-reports/settings` | Настройки | ✅ |

### RKO API

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/rko` | Все РКО | ✅ |
| GET | `/api/rko/:shopAddress/:date` | РКО магазина | ✅ |
| POST | `/api/rko` | Создать РКО | ✅ |
| PUT | `/api/rko/:id` | Обновить | ✅ |
| DELETE | `/api/rko/:id` | Удалить | ✅ |
| GET | `/api/rko/pending` | Pending | ✅ |
| POST | `/api/rko/upload-photo` | Загрузить фото | ✅ |

### ORDERS API (Заказы)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/orders` | Все заказы | ✅ |
| GET | `/api/orders/:orderId` | Один заказ | ✅ |
| POST | `/api/orders` | Создать заказ | ✅ |
| PUT | `/api/orders/:orderId` | Обновить | ✅ |
| POST | `/api/orders/:orderId/accept` | Принять | ✅ |
| POST | `/api/orders/:orderId/reject` | Отклонить | ✅ |
| POST | `/api/orders/:orderId/complete` | Завершить | ✅ |
| GET | `/api/orders/shop/:shopAddress` | Заказы магазина | ✅ |
| GET | `/api/orders/client/:phone` | Заказы клиента | ✅ |

### MENU API (Меню)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/menu` | Всё меню | ❌ |
| GET | `/api/menu/:itemId` | Один пункт | ❌ |
| POST | `/api/menu` | Создать пункт | ✅ |
| PUT | `/api/menu/:itemId` | Обновить | ✅ |
| DELETE | `/api/menu/:itemId` | Удалить | ✅ |
| GET | `/api/menu/categories` | Категории | ❌ |
| POST | `/api/menu/categories` | Создать категорию | ✅ |

### RECIPES API (Рецепты)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/recipes` | Все рецепты | ✅ |
| GET | `/api/recipes/:recipeId` | Один рецепт | ✅ |
| POST | `/api/recipes` | Создать | ✅ |
| PUT | `/api/recipes/:recipeId` | Обновить | ✅ |
| DELETE | `/api/recipes/:recipeId` | Удалить | ✅ |

### EMPLOYEES API (Сотрудники)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/employees` | Все сотрудники | ✅ |
| GET | `/api/employees/:id` | Один сотрудник | ✅ |
| POST | `/api/employees` | Создать | ✅ |
| PUT | `/api/employees/:id` | Обновить | ✅ |
| DELETE | `/api/employees/:id` | Удалить | ✅ |
| GET | `/api/employees/shop/:shopAddress` | По магазину | ✅ |
| GET | `/api/employees/search` | Поиск | ✅ |

### SHOPS API (Магазины)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/shops` | Все магазины | ✅ |
| GET | `/api/shops/:shopAddress` | Один магазин | ✅ |
| POST | `/api/shops` | Создать | ✅ |
| PUT | `/api/shops/:shopAddress` | Обновить | ✅ |
| DELETE | `/api/shops/:shopAddress` | Удалить | ✅ |

### LOYALTY API (Лояльность)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/loyalty/:phone` | Баллы клиента | ✅ |
| POST | `/api/loyalty/add-points` | Начислить баллы | ✅ |
| POST | `/api/loyalty/spend-points` | Списать баллы | ✅ |
| GET | `/api/loyalty/transactions/:phone` | История | ✅ |
| GET | `/api/loyalty/leaderboard` | Топ клиентов | ✅ |

### LOYALTY GAMIFICATION API (Геймификация лояльности)

**Файл:** `loyalty-proxy/api/loyalty_gamification_api.js`

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/loyalty-gamification/settings` | Настройки уровней и колеса | ✅ |
| POST | `/api/loyalty-gamification/settings` | Сохранить настройки (админ) | ✅ |
| POST | `/api/loyalty-gamification/upload-badge` | Загрузить картинку значка | ✅ |
| GET | `/api/loyalty-gamification/client/:phone` | Данные клиента (уровень, значки, спины) | ✅ |
| GET | `/api/loyalty-gamification/client/:phone/pending-prize` | Pending приз клиента | ✅ |
| POST | `/api/loyalty-gamification/spin` | Крутить колесо удачи | ✅ |
| POST | `/api/loyalty-gamification/deliver-prize` | Выдать приз клиенту (push-уведомление) | ✅ |
| GET | `/api/loyalty-gamification/wheel-history` | История прокруток | ✅ |

**Структура настроек:**
- 10 VIP уровней (настраиваемые названия, пороги, значки)
- Значки: Material Icons ИЛИ загруженные изображения (зубчатая форма «наклейки»)
- Колесо удачи: N напитков = 1 прокрутка (настраивается)
- Секторы колеса: текст, вероятность, цвет, тип приза
- Система призов: pending → deliver (push-уведомление клиенту)

**Оптимизации:**
- Параллельная загрузка данных (fetchByPhone, fetchSettings, fetchClientData, fetchPendingPrize одновременно)
- 5-минутный кэш для настроек геймификации и промо-настроек

**Flutter файлы:**
- `lib/features/loyalty/models/loyalty_gamification_model.dart` — модели
- `lib/features/loyalty/services/loyalty_gamification_service.dart` — API сервис
- `lib/features/loyalty/pages/loyalty_page.dart` — главная страница лояльности (QR, баллы, уровень, колесо)
- `lib/features/loyalty/pages/loyalty_gamification_settings_page.dart` — настройки (админ)
- `lib/features/loyalty/pages/client_wheel_page.dart` — страница колеса (клиент)
- `lib/features/loyalty/pages/pending_prize_page.dart` — страница получения приза (клиент)
- `lib/features/loyalty/widgets/qr_badges_widget.dart` — значки-рамка вокруг QR (Stack layout, 80px, по 4 сторонам)
- `lib/features/loyalty/widgets/wheel_progress_widget.dart` — прогресс колеса

### TASKS API (Задачи)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/tasks` | Все задачи | ✅ |
| GET | `/api/tasks/:taskId` | Одна задача | ✅ |
| POST | `/api/tasks` | Создать | ✅ |
| PUT | `/api/tasks/:taskId` | Обновить | ✅ |
| DELETE | `/api/tasks/:taskId` | Удалить | ✅ |
| POST | `/api/tasks/:taskId/complete` | Выполнить | ✅ |
| GET | `/api/tasks/employee/:employeeId` | Задачи сотрудника | ✅ |

### RECURRING TASKS API (Циклические задачи)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/recurring-tasks` | Все шаблоны | ✅ |
| POST | `/api/recurring-tasks` | Создать шаблон | ✅ |
| PUT | `/api/recurring-tasks/:id` | Обновить | ✅ |
| DELETE | `/api/recurring-tasks/:id` | Удалить | ✅ |
| PUT | `/api/recurring-tasks/:id/toggle-pause` | Пауза | ✅ |
| POST | `/api/recurring-tasks/generate-daily` | Сгенерировать | ✅ |
| GET | `/api/recurring-tasks/instances/list` | Экземпляры | ✅ |
| POST | `/api/recurring-tasks/instances/:id/complete` | Выполнить | ✅ |

### TRAINING API (Обучение)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/training-articles` | Все статьи | ✅ |
| GET | `/api/training-articles/:id` | Одна статья | ✅ |
| POST | `/api/training-articles` | Создать | ✅ |
| PUT | `/api/training-articles/:id` | Обновить | ✅ |
| DELETE | `/api/training-articles/:id` | Удалить | ✅ |

### TESTS API (Тестирование)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/test-questions` | Все вопросы | ✅ |
| POST | `/api/test-questions` | Создать вопрос | ✅ |
| PUT | `/api/test-questions/:id` | Обновить | ✅ |
| DELETE | `/api/test-questions/:id` | Удалить | ✅ |
| GET | `/api/test-results` | Результаты | ✅ |
| POST | `/api/test-results` | Записать результат | ✅ |

### REVIEWS API (Отзывы)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/reviews` | Все отзывы | ✅ |
| GET | `/api/reviews/:reviewId` | Один отзыв | ✅ |
| POST | `/api/reviews` | Создать | ❌ |
| POST | `/api/reviews/:reviewId/reply` | Ответить | ✅ |
| DELETE | `/api/reviews/:reviewId` | Удалить | ✅ |
| GET | `/api/reviews/shop/:shopAddress` | По магазину | ✅ |

### PRODUCT QUESTIONS API (Поиск товара)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/product-questions` | Все вопросы | ✅ |
| GET | `/api/product-questions/:id` | Один вопрос | ✅ |
| POST | `/api/product-questions` | Создать вопрос | ❌ |
| POST | `/api/product-questions/:id/messages` | Ответить на вопрос | ✅ |
| POST | `/api/product-questions/upload-photo` | Загрузить фото (multipart) | ❌ |
| GET | `/api/product-questions/unanswered-count` | Кол-во неотвеченных | ✅ |
| GET | `/api/product-questions/client/:phone` | Вопросы клиента | ❌ |
| GET | `/api/product-questions/client/:phone/grouped` | Группировка по магазинам | ❌ |
| POST | `/api/product-questions/:id/mark-read` | Пометить прочитанным | ✅ |
| POST | `/api/product-questions/client/:phone/mark-all-read` | Все прочитаны | ❌ |
| POST | `/api/product-question-dialogs` | Создать персональный диалог | ❌ |
| GET | `/api/product-question-dialogs/:id` | Персональный диалог | ✅ |
| GET | `/api/product-question-dialogs/client/:phone` | Диалоги клиента | ❌ |
| GET | `/api/product-question-dialogs/shop/:addr` | Диалоги магазина | ✅ |
| GET | `/api/product-question-dialogs/all` | Все диалоги (админ) | ✅ |
| GET | `/api/product-question-dialogs/unviewed-counts` | Непросмотренные (админ) | ✅ |
| POST | `/api/product-question-dialogs/:id/messages` | Сообщение в диалог | ✅ |
| POST | `/api/product-question-dialogs/:id/mark-read` | Пометить прочитанным | ✅ |
| POST | `/api/product-question-dialogs/:id/mark-viewed-by-admin` | Просмотрено админом | ✅ |
| POST | `/api/product-question-dialogs/mark-shop-viewed-by-admin` | Просм. магазин (админ) | ✅ |

### EMPLOYEE CHAT API (Чат сотрудников)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/employee-chat/messages` | Сообщения | ✅ |
| POST | `/api/employee-chat/messages` | Отправить | ✅ |
| GET | `/api/employee-chat/groups` | Группы | ✅ |
| POST | `/api/employee-chat/groups` | Создать группу | ✅ |
| PUT | `/api/employee-chat/groups/:id` | Обновить | ✅ |
| DELETE | `/api/employee-chat/groups/:id` | Удалить | ✅ |
| POST | `/api/employee-chat/groups/:id/members` | Добавить участника | ✅ |
| WS | `/ws/chat` | WebSocket подключение | ✅ |

### WORK SCHEDULE API (График работы)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/work-schedule/:shopAddress` | График магазина | ✅ |
| POST | `/api/work-schedule` | Создать график | ✅ |
| GET | `/api/work-schedule-templates` | Шаблоны | ✅ |
| POST | `/api/work-schedule-templates` | Создать шаблон | ✅ |
| DELETE | `/api/work-schedule-templates/:id` | Удалить шаблон | ✅ |

### EFFICIENCY API (Эффективность)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/efficiency/:employeeId/:month` | Эффективность сотрудника | ✅ |
| GET | `/api/efficiency/all/:month` | Всех сотрудников | ✅ |
| GET | `/api/efficiency/shop/:shopAddress/:month` | По магазину | ✅ |
| GET | `/api/efficiency-penalties` | Штрафы | ✅ |
| POST | `/api/efficiency-penalties` | Создать штраф | ✅ |
| DELETE | `/api/efficiency-penalties/:id` | Удалить штраф | ✅ |

### POINTS SETTINGS API (Настройки баллов)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/points-settings/shift` | Настройки пересменок | ✅ |
| POST | `/api/points-settings/shift` | Сохранить | ✅ |
| GET | `/api/points-settings/recount` | Настройки пересчётов | ✅ |
| POST | `/api/points-settings/recount` | Сохранить | ✅ |
| GET | `/api/points-settings/attendance` | Посещаемость | ✅ |
| POST | `/api/points-settings/attendance` | Сохранить | ✅ |
| GET | `/api/points-settings/test` | Тестирование | ✅ |
| POST | `/api/points-settings/test` | Сохранить | ✅ |
| GET | `/api/points-settings/rko` | РКО | ✅ |
| POST | `/api/points-settings/rko` | Сохранить | ✅ |
| GET | `/api/points-settings/envelope` | Конверты | ✅ |
| POST | `/api/points-settings/envelope` | Сохранить | ✅ |

### FORTUNE WHEEL API (Колесо удачи)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/fortune-wheel/settings` | Настройки | ✅ |
| POST | `/api/fortune-wheel/settings` | Сохранить | ✅ |
| GET | `/api/fortune-wheel/spins/:employeeId` | Доступные прокрутки | ✅ |
| POST | `/api/fortune-wheel/spin` | Прокрутить | ✅ |
| GET | `/api/fortune-wheel/history/:employeeId` | История | ✅ |

### REFERRALS API (Рефералы)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| POST | `/api/referrals/register-client` | Регистрация по рефералу | ❌ |
| GET | `/api/referrals/stats/:employeeId` | Статистика | ✅ |
| GET | `/api/referrals/viewing-log/:phone` | Лог просмотров | ✅ |
| POST | `/api/referrals/mark-viewed/:phone` | Пометить просмотренным | ✅ |

### JOB APPLICATIONS API (Заявки на работу)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/job-applications` | Все заявки | ✅ |
| POST | `/api/job-applications` | Создать заявку | ❌ |
| POST | `/api/job-applications/:id/view` | Просмотрено | ✅ |
| POST | `/api/job-applications/:id/accept` | Принять | ✅ |
| POST | `/api/job-applications/:id/reject` | Отклонить | ✅ |

### SUPPLIERS API (Поставщики)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/suppliers` | Все поставщики | ✅ |
| GET | `/api/suppliers/:id` | Один поставщик | ✅ |
| POST | `/api/suppliers` | Создать | ✅ |
| PUT | `/api/suppliers/:id` | Обновить | ✅ |
| DELETE | `/api/suppliers/:id` | Удалить | ✅ |

### WITHDRAWALS API (Выемки)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/withdrawals` | Все выемки | ✅ |
| POST | `/api/withdrawals` | Создать | ✅ |
| PATCH | `/api/withdrawals/:id/confirm` | Подтвердить | ✅ |
| DELETE | `/api/withdrawals/:id` | Удалить | ✅ |

### SHOP MANAGERS API (Менеджеры магазинов)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/shop-managers` | Все менеджеры | ✅ |
| GET | `/api/shop-managers/role/:phone` | Роль пользователя | ✅ |
| POST | `/api/shop-managers/developers` | Добавить разработчика | ✅ |
| DELETE | `/api/shop-managers/developers/:phone` | Удалить | ✅ |
| POST | `/api/shop-managers/managers` | Добавить менеджера | ✅ |
| DELETE | `/api/shop-managers/managers/:phone` | Удалить | ✅ |
| PUT | `/api/shop-managers/managers/:phone/shops` | Обновить магазины | ✅ |

### GEOFENCE API (Геозоны)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/geofence-settings` | Настройки | ✅ |
| POST | `/api/geofence-settings` | Сохранить | ✅ |
| POST | `/api/geofence/client-check` | Проверить клиента | ✅ |
| GET | `/api/geofence/stats` | Статистика | ✅ |

### CIGARETTE VISION API (ИИ распознавание)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/cigarette-vision/settings` | Настройки | ✅ |
| PUT | `/api/cigarette-vision/settings` | Сохранить | ✅ |
| GET | `/api/cigarette-vision/model-status` | Статус модели | ✅ |
| POST | `/api/cigarette-vision/detect` | Распознать товар | ✅ |
| POST | `/api/cigarette-vision/train` | Обучить модель | ✅ |
| GET | `/api/cigarette-vision/samples` | Образцы | ✅ |
| POST | `/api/cigarette-vision/samples` | Загрузить образец | ✅ |
| DELETE | `/api/cigarette-vision/samples/:id` | Удалить | ✅ |

### SHIFT AI VERIFICATION API (ИИ верификация отчётов)

**Файл:** `loyalty-proxy/api/shift_ai_verification_api.js`

AI верификация проверяет фото товаров на соответствие ожидаемому ассортименту.

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| POST | `/api/shift-ai-verification/verify` | Запустить верификацию | ✅ |
| GET | `/api/shift-ai-verification/status/:reportId` | Статус верификации | ✅ |
| GET | `/api/shift-ai-verification/results/:reportId` | Результаты | ✅ |

**Где используется AI верификация:**
- ✅ **Пересменка (Shift Transfer)** — проверка фото при передаче смены
- ✅ **Пересчёт (Recount)** — верификация инвентаризации
- ✅ **Конверты (Envelope)** — проверка фото при инкассации

**Где НЕ используется:**
- ❌ **Сдача смены (Shift Handover)** — только ручная проверка админом

### DATA CLEANUP API (Очистка данных)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/admin/disk-info` | Информация о диске | ✅ |
| GET | `/api/admin/data-stats` | Статистика данных | ✅ |
| GET | `/api/admin/cleanup-preview` | Предпросмотр | ✅ |
| POST | `/api/admin/cleanup` | Очистить данные | ✅ |

### MEDIA API (Медиа файлы)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| POST | `/upload-media` | Загрузить медиа | ✅ |
| POST | `/upload-chat-media` | Загрузить в чат | ✅ |
| POST | `/api/app-logs` | Записать логи | ✅ |
| GET | `/api/app-logs` | Получить логи | ✅ |

### CLIENTS API (Клиенты)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/clients` | Все клиенты | ✅ |
| GET | `/api/clients/list` | Список клиентов | ✅ |
| POST | `/api/clients` | Создать | ✅ |
| GET | `/api/clients/:phone/messages` | Сообщения | ✅ |
| POST | `/api/clients/:phone/messages` | Отправить | ✅ |
| POST | `/api/clients/messages/broadcast` | Рассылка | ✅ |

### FCM TOKENS API (Push токены)

| Method | Path | Описание | Auth |
|--------|------|----------|------|
| GET | `/api/fcm-tokens` | Все токены | ✅ |
| POST | `/api/fcm-tokens` | Сохранить токен | ❌ |
| DELETE | `/api/fcm-tokens/:phone` | Удалить | ✅ |
| POST | `/api/send-push` | Отправить push | ✅ |
| POST | `/api/send-push/broadcast` | Рассылка push | ✅ |

---

# 6. ПОТОКИ ДАННЫХ

## 6.1 Отметка посещаемости (Attendance)

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Сотрудник     │     │    Flutter      │     │     Server      │
│   (Employee)    │     │   App           │     │  (Node.js)      │
└───────┬─────────┘     └───────┬─────────┘     └───────┬─────────┘
        │                       │                       │
        │ 1. Нажимает           │                       │
        │    "Я на работе"      │                       │
        │──────────────────────>│                       │
        │                       │                       │
        │                       │ 2. GPS + проверка     │
        │                       │    геозоны            │
        │                       │───────────────────────>
        │                       │                       │
        │                       │ POST /api/attendance  │
        │                       │ {employeeName,        │
        │                       │  shopAddress,         │
        │                       │  latitude, longitude, │
        │                       │  timestamp, action}   │
        │                       │───────────────────────>
        │                       │                       │
        │                       │                       │ 3. Проверить:
        │                       │                       │    - Координаты в радиусе
        │                       │                       │    - Время в окне 07:00-09:00
        │                       │                       │    - Сотрудник в графике
        │                       │                       │
        │                       │                       │ 4. Сохранить:
        │                       │                       │    /var/www/attendance/
        │                       │                       │    YYYY-MM-DD.json
        │                       │                       │
        │                       │                       │ 5. Удалить pending
        │                       │                       │    (если был)
        │                       │                       │
        │                       │ 200 {success: true,   │
        │                       │      isOnTime: true}  │
        │                       │<───────────────────────
        │                       │                       │
        │ Показать результат    │                       │
        │<──────────────────────│                       │
```

## 6.2 Создание заказа (Order)

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  Клиент  │     │ Flutter  │     │  Server  │     │ Магазин  │
│          │     │   App    │     │          │     │(Employee)│
└────┬─────┘     └────┬─────┘     └────┬─────┘     └────┬─────┘
     │                │                │                │
     │ 1. Выбрать     │                │                │
     │    товары      │                │                │
     │───────────────>│                │                │
     │                │                │                │
     │                │ POST /api/orders               │
     │                │ {shopAddress,   │                │
     │                │  clientPhone,   │                │
     │                │  items[],       │                │
     │                │  total,         │                │
     │                │  paymentMethod} │                │
     │                │───────────────->│                │
     │                │                │                │
     │                │                │ 2. Сохранить   │
     │                │                │    order.json  │
     │                │                │                │
     │                │                │ 3. Firebase    │
     │                │                │    Push        │
     │                │                │───────────────>│
     │                │                │                │
     │                │                │  "Новый заказ" │
     │                │                │───────────────>│
     │                │                │                │
     │                │ 200 {orderId}  │                │
     │                │<───────────────│                │
     │ "Заказ создан" │                │                │
     │<───────────────│                │                │
     │                │                │                │
     │                │                │ 4. Сотрудник   │
     │                │                │    принимает   │
     │                │                │<───────────────│
     │                │                │                │
     │ Push: "Заказ   │                │                │
     │       принят"  │                │                │
     │<───────────────│<───────────────│                │
```

## 6.3 Пересменка (Shift Report)

```
┌──────────────────────────────────────────────────────────────────┐
│                    ПРОЦЕСС ПЕРЕСМЕНКИ                            │
└──────────────────────────────────────────────────────────────────┘

07:00 ─────────────────────────────────────────────────────> 13:00
  │                                                             │
  │ Scheduler генерирует                                        │ Deadline
  │ pending reports                                             │
  │                                                             │
  ▼                                                             ▼
┌─────────────┐                                         ┌─────────────┐
│   PENDING   │                                         │   FAILED    │
│             │                                         │  (штраф -3) │
└──────┬──────┘                                         └─────────────┘
       │                                                       ▲
       │ Сотрудник отвечает                                    │
       │ на вопросы                                            │
       ▼                                                       │
┌─────────────┐      Дедлайн прошел,                           │
│   REVIEW    │      админ не проверил ──────────────────────>─┤
│             │      (2 часа timeout)                          │
└──────┬──────┘                                                │
       │                                                       │
       │ Админ оценивает                                       │
       │ (рейтинг 1-10)                                        │
       ▼                                                       │
┌─────────────┐      Админ не успел ─────────────────────────>─┘
│  CONFIRMED  │
│  (баллы по  │
│  формуле)   │
└─────────────┘

Формула баллов:
- Rating 1-6: от -3 до 0 (линейно)
- Rating 6-10: от 0 до +2 (линейно)
```

## 6.4 Сдача смены (Shift Handover)

> **Примечание:** AI верификация в сдаче смены НЕ используется.
> Проверка выполняется вручную администратором.
> AI верификация работает только в: Пересменка, Пересчёт, Конверты.

```
Сотрудник           Приложение              Сервер              Админ
    │                   │                     │                   │
    │ 1. Нажать         │                     │                   │
    │    "Сдать смену"  │                     │                   │
    │──────────────────>│                     │                   │
    │                   │                     │                   │
    │                   │ 2. Камера для       │                   │
    │                   │    фото витрины     │                   │
    │<──────────────────│                     │                   │
    │                   │                     │                   │
    │ 3. Фото + Z-отчет │                     │                   │
    │──────────────────>│                     │                   │
    │                   │                     │                   │
    │                   │ POST /upload-media  │                   │
    │                   │ (multipart/form)    │                   │
    │                   │────────────────────>│                   │
    │                   │                     │                   │
    │                   │ POST /api/shift-    │                   │
    │                   │   handover-reports  │                   │
    │                   │────────────────────>│                   │
    │                   │                     │                   │
    │                   │                     │ 4. Сохранить в    │
    │                   │                     │    shift-handover-│
    │                   │                     │    reports/       │
    │                   │                     │                   │
    │                   │                     │ 5. Push админу    │
    │                   │                     │────────────────────>
    │                   │                     │                   │
    │                   │ 200 OK              │                   │
    │                   │<────────────────────│                   │
    │                   │                     │                   │
    │ "Отчёт отправлен" │                     │                   │
    │<──────────────────│                     │                   │
    │                   │                     │                   │
    │                   │                     │ 6. Админ          │
    │                   │                     │    проверяет      │
    │                   │                     │<───────────────────
    │                   │                     │                   │
    │                   │                     │ PUT /api/shift-   │
    │                   │                     │   handover-reports│
    │                   │                     │   /:id/confirm    │
    │                   │                     │<───────────────────
    │                   │                     │                   │
    │ Push: "Смена      │                     │                   │
    │        подтверждена│                    │                   │
    │        (рейтинг 8)"│                    │                   │
    │<──────────────────│<────────────────────│                   │
```

## 6.5 Начисление штрафа (Penalty Flow)

```
┌─────────────────────────────────────────────────────────────────┐
│                 АВТОМАТИЧЕСКОЕ НАЧИСЛЕНИЕ ШТРАФА                │
└─────────────────────────────────────────────────────────────────┘

Scheduler (каждые 5 минут)
        │
        ▼
┌───────────────────────┐
│ Проверить все pending │
│ отчёты на дедлайн     │
└───────────┬───────────┘
            │
            ▼
    ┌───────────────┐     Нет
    │ Дедлайн       │─────────────> Продолжить
    │ прошел?       │               мониторинг
    └───────┬───────┘
            │ Да
            ▼
┌───────────────────────┐
│ Найти сотрудника      │
│ в work-schedules      │
│ по (shop, date, shift)│
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│ Создать penalty:      │
│ {                     │
│   employeeName,       │
│   category,           │
│   points: -3,         │
│   reason,             │
│   sourceId (для       │
│   предотвращения      │
│   дубликатов)         │
│ }                     │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│ Сохранить в           │
│ efficiency-penalties/ │
│ YYYY-MM.json          │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│ Отправить Push        │
│ сотруднику:           │
│ "Штраф за [причина]"  │
└───────────────────────┘
```

---

# 7. АВТОМАТИЗАЦИЯ (SCHEDULERS)

## 7.1 Обзор всех Scheduler'ов

| Scheduler | Интервал | Утреннее окно | Вечернее окно | Штраф |
|-----------|----------|---------------|---------------|-------|
| Attendance | 5 мин | 07:00-09:00 | 19:00-21:00 | -2 |
| Envelope | 5 мин | 07:00-09:00 | 19:00-21:00 | -5 |
| Shift | 5 мин | 07:00-13:00 | 14:00-23:00 | -3 |
| Shift Handover | 5 мин | 07:00-14:00 | 14:00-23:00 | -3 |
| RKO | 5 мин | 07:00-14:00 | 14:00-23:00 | -3 |
| Recount | 5 мин | 08:00-14:00 | 14:00-23:00 | -3 |
| Product Questions | 5 мин | N/A | N/A | -1 |

## 7.2 ATTENDANCE AUTOMATION SCHEDULER

**Файл:** `loyalty-proxy/api/attendance_automation_scheduler.js`
**Строк кода:** 822

### Блок-схема работы:

```
START (каждые 5 минут)
  │
  ├─→ Загрузить state
  │
  ├─→ Проверить утреннее окно (07:00-09:00)
  │   └─→ Если активно И первый раз сегодня
  │       └─→ Для каждого магазина:
  │           ├─→ Есть ли pending? (пропустить)
  │           ├─→ Отметка уже есть? (пропустить)
  │           └─→ Создать pending отчёт (deadline = 09:00)
  │
  ├─→ Проверить вечернее окно (19:00-21:00)
  │   └─→ Если активно И первый раз сегодня
  │       └─→ Создать pending отчёты (deadline = 21:00)
  │
  ├─→ Проверить дедлайны всех pending
  │   └─→ Для каждого pending:
  │       ├─→ Найти отметку (если есть → удалить pending)
  │       ├─→ Если NOW > deadline
  │       │   ├─→ Статус = FAILED
  │       │   ├─→ Найти сотрудника в графике
  │       │   └─→ Создать штраф (-2 баллов)
  │       └─→ Отправить push админу (если есть failed)
  │
  ├─→ В 23:59: cleanup
  │   ├─→ Удалить все pending файлы
  │   └─→ Сбросить state
  │
  └─→ Сохранить state

END
```

### Экспортируемые функции:

```javascript
startAttendanceAutomationScheduler()   // Запуск scheduler'а
generatePendingReports(shiftType)      // Генерация pending
checkPendingDeadlines()                // Проверка дедлайнов
cleanupFailedReports()                 // Очистка failed
loadTodayPendingReports()              // Загрузка pending за день
getPendingReports()                    // Получить все pending
getFailedReports()                     // Получить все failed
canMarkAttendance(shopAddress)         // Можно ли отметиться
markPendingAsCompleted(shop, shift)    // Пометить выполненным
getAttendanceSettings()                // Получить настройки
getMoscowTime()                        // Московское время
getMoscowDateString()                  // Дата в формате YYYY-MM-DD
```

## 7.3 ENVELOPE AUTOMATION SCHEDULER

**Файл:** `loyalty-proxy/api/envelope_automation_scheduler.js`
**Строк кода:** 650

### Оптимизация (Batch Loading):

```javascript
// Загружает ВСЕ pending + submitted за день в начале
// Затем O(1) поиск вместо O(N) чтения файлов

const cache = await initBatchCache(date);
// cache.pending = Map<string, Report>
// cache.submitted = Set<string>

// Проверка за O(1):
if (cache.pending.has(key)) { /* есть pending */ }
if (cache.submitted.has(key)) { /* уже сдан */ }
```

### Блок-схема:

```
START (каждые 5 минут)
  │
  ├─→ Проверить время: 07:00-07:05
  │   └─→ Если первый раз сегодня
  │       └─→ Загрузить ALL pending + submitted в Map/Set
  │       └─→ Для каждого магазина:
  │           ├─→ Есть pending? (O(1) поиск в Map)
  │           ├─→ Есть submitted? (O(1) поиск в Set)
  │           └─→ Создать pending (deadline = "09:00")
  │
  ├─→ Проверить время: 19:00-19:05
  │   └─→ Аналогично для вечера
  │
  ├─→ Проверить все pending дедлайны
  │   └─→ Для каждого pending:
  │       ├─→ Проверить: может конверт уже сдан? (O(1))
  │       │   └─→ Если да → удалить pending
  │       ├─→ Parse deadline (09:00 → 540 минут)
  │       ├─→ Если current >= deadline
  │       │   ├─→ Статус = FAILED
  │       │   ├─→ Найти сотрудника в графике
  │       │   └─→ Создать штраф (-5 баллов)
  │       └─→ Отправить push админу
  │
  ├─→ В 23:59: Удалить все pending файлы
  │
  └─→ Сохранить state

END
```

## 7.4 SHIFT AUTOMATION SCHEDULER

**Файл:** `loyalty-proxy/api/shift_automation_scheduler.js`
**Строк кода:** 690

### Состояния отчёта:

```
pending → (deadline прошел) → failed
pending → (сотрудник ответил) → review → (админ оценил) → confirmed
                                      → (админ не проверил за 2ч) → rejected
```

### Admin Review Timeout:

```javascript
// Если админ не проверил за 2 часа:
const reviewDeadline = new Date(submittedAt.getTime() + 2 * 60 * 60 * 1000);
if (now > reviewDeadline && status === 'review') {
  status = 'rejected';
  // Штраф остаётся у сотрудника
}
```

### API Helper функции:

```javascript
// Сотрудник ответил на вопросы пересменки
setReportToReview(reportId, employeeId, employeeName)

// Админ оценил отчёт
confirmReport(reportId, rating, adminName)
```

## 7.5 SHIFT HANDOVER AUTOMATION SCHEDULER

**Файл:** `loyalty-proxy/api/shift_handover_automation_scheduler.js`
**Строк кода:** 853

### Особенности:

- Проверяет isWithinTimeWindow() для ночных интервалов
- Admin review timeout: 4 часа (больше чем у shift)
- Отправляет push админу при submit: "Новая сдача смены"

### Блок-схема:

```
START (каждые 5 минут)
  │
  ├─→ ГЕНЕРАЦИЯ PENDING (если в окне)
  │   ├─→ Утро (07:00-14:00): создать pending
  │   └─→ Вечер (14:00-23:00): создать pending
  │
  ├─→ ПРОВЕРКА 1: pending дедлайны
  │   └─→ Для каждого pending:
  │       ├─→ Проверить: submitted ли уже?
  │       │   └─→ Если да → удалить pending
  │       ├─→ Если NOW >= deadline (время в HH:MM формате)
  │       │   ├─→ Статус = FAILED
  │       │   ├─→ Найти сотрудника в графике
  │       │   └─→ Создать штраф
  │       └─→ Отправить push админу
  │
  ├─→ ПРОВЕРКА 2: admin review timeout (4 часа)
  │   └─→ Для КАЖДОГО ФАЙЛА в shift-handover-reports/
  │       ├─→ Если status = 'pending'
  │       ├─→ Если (NOW - createdAt) >= 4 часов
  │       │   ├─→ Статус = REJECTED
  │       │   └─→ Отправить push админу
  │
  └─→ В 23:59: cleanup

END
```

## 7.6 RKO AUTOMATION SCHEDULER

**Файл:** `loyalty-proxy/api/rko_automation_scheduler.js`
**Строк кода:** 719

### Особенность cleanup:

```javascript
// Cleanup происходит в 00:00-06:00 (ночью), не в 23:59
// Это связано с тем, что вечерняя смена может сдавать РКО до 23:00

if (moscowHour >= 0 && moscowHour < 6) {
  if (state.lastCleanup !== todayMoscow) {
    await cleanupFailedReports();
    state.lastCleanup = todayMoscow;
  }
}
```

## 7.7 RECOUNT AUTOMATION SCHEDULER

**Файл:** `loyalty-proxy/api/recount_automation_scheduler.js`
**Строк кода:** 788

### Состояния (аналогично Shift):

```
pending → (deadline) → failed
pending → (сотрудник) → review → (админ) → confirmed
                              → (timeout 2ч) → rejected
```

## 7.8 PRODUCT QUESTIONS PENALTY SCHEDULER

**Файл:** `loyalty-proxy/product_questions_penalty_scheduler.js`

### Особенности:

- Динамический timeout (из настроек, по умолчанию 30 минут)
- Может штрафовать НЕСКОЛЬКИХ сотрудников (если смены пересекаются)
- State хранит обработанные ID (limit 1000 для предотвращения утечки памяти)

### Определение смены по времени:

```javascript
function getShiftTypeByTime(date) {
  const hour = date.getUTCHours() + 3; // Moscow timezone
  if (hour >= 0 && hour < 8) return ['evening'];
  if (hour >= 8 && hour < 12) return ['morning'];
  if (hour >= 12 && hour < 16) return ['morning', 'day']; // overlap
  if (hour >= 16 && hour < 20) return ['day', 'evening']; // overlap
  return ['evening'];
}
```

### Блок-схема:

```
START (каждые 5 минут)
  │
  ├─→ Загрузить state + timeout (динамический)
  │
  ├─→ ПРОВЕРКА 1: Unread questions
  │   └─→ Для каждого файла в product-questions/:
  │       ├─→ Пропустить если уже processed
  │       ├─→ Если elapsed > timeoutMinutes:
  │       │   └─→ Для каждого unanswered shop:
  │       │       ├─→ Найти сотрудников на смене (может быть overlap!)
  │       │       └─→ Создать штраф: -1 балл для КАЖДОГО
  │       └─→ Добавить в processedQuestions
  │
  ├─→ ПРОВЕРКА 2: Unread dialogs
  │   └─→ Для каждого файла в product-question-dialogs/:
  │       ├─→ Пропустить если уже processed
  │       ├─→ Пропустить если hasUnreadFromClient = false
  │       ├─→ Если elapsed > timeoutMinutes:
  │       │   ├─→ Найти сотрудников в shopAddress
  │       │   └─→ Создать штраф: -1 балл для КАЖДОГО
  │       └─→ Добавить в processedDialogs
  │
  └─→ Обновить state (limit 1000 ID)

END
```

---

# 8. СИСТЕМА БАЛЛОВ И ЭФФЕКТИВНОСТИ

## 8.1 Обзор 12 категорий эффективности

| № | Категория | Тип | Источник данных | Min | Max |
|---|-----------|-----|-----------------|-----|-----|
| 1 | Shift (Пересменка) | Rating 1-10 | shift-reports/ | -3 | +2 |
| 2 | Recount (Пересчёт) | Rating 1-10 | recount-reports/ | -3 | +1 |
| 3 | ShiftHandover (Сдача смены) | Rating 1-10 | shift-handovers/ | -3 | +1 |
| 4 | Attendance (Посещаемость) | Boolean | attendance/ | -1 | +0.5 |
| 5 | Test (Тестирование) | Score 0-20 | test-results/ | -2.5 | +3.5 |
| 6 | Reviews (Отзывы) | Boolean | client-reviews/ | -1.5 | +1.5 |
| 7 | ProductSearch (Поиск товара) | Boolean | product-questions/ | 0 | +1.0 |
| 8 | RKO | Boolean | rko/ | -3 | +1.0 |
| 9 | Orders (Заказы) | Boolean | Lichi CRM | 0 | +1.0 |
| 10 | Penalties (Штрафы) | Custom | efficiency-penalties/ | Variable | Variable |
| 11 | Tasks (Задачи) | Count | tasks/ + recurring-tasks/ | 0 | Variable |
| 12 | Envelope (Конверты) | Boolean | envelope-reports/ | -5 | 0 |

## 8.2 Формула линейной интерполяции (Rating)

**Используется для:** Shift, Recount, ShiftHandover

```javascript
// efficiency_calc.js, строки 169-184
function interpolateRatingPoints(rating, minRating, maxRating, minPoints, zeroThreshold, maxPoints) {
  // Если рейтинг <= минимального (1), возвращаем минимальные баллы
  if (rating <= minRating) return minPoints;

  // Если рейтинг >= максимального (10), возвращаем максимальные баллы
  if (rating >= maxRating) return maxPoints;

  // Зона от minRating до zeroThreshold: линейно от minPoints до 0
  if (rating <= zeroThreshold) {
    const range = zeroThreshold - minRating;
    if (range === 0) return 0;
    return minPoints + (0 - minPoints) * ((rating - minRating) / range);
  }
  // Зона от zeroThreshold до maxRating: линейно от 0 до maxPoints
  else {
    const range = maxRating - zeroThreshold;
    if (range === 0) return maxPoints;
    return 0 + (maxPoints - 0) * ((rating - zeroThreshold) / range);
  }
}
```

### Визуализация формулы (Shift: min=-3, zero=6, max=+2):

```
Баллы
  +2 ─┤                                           ╱
     │                                         ╱
  +1 ─┤                                      ╱
     │                                    ╱
   0 ─┼────────────────────────────────┬─
     │                              ╱  │
  -1 ─┤                           ╱    │
     │                        ╱       │
  -2 ─┤                     ╱          │
     │                  ╱             │
  -3 ─┼────────────────┴───────────────┴──────────
     │  1   2   3   4   5   6   7   8   9   10
                     Рейтинг
                         ▲
                    zeroThreshold
```

### Таблица примеров для Shift:

| Рейтинг | Формула | Результат |
|---------|---------|-----------|
| 1 | ≤ minRating | -3.0 |
| 2 | -3 + (0-(-3)) × (2-1)/(6-1) | -2.4 |
| 3 | -3 + (0-(-3)) × (3-1)/(6-1) | -1.8 |
| 4 | -3 + (0-(-3)) × (4-1)/(6-1) | -1.2 |
| 5 | -3 + (0-(-3)) × (5-1)/(6-1) | -0.6 |
| 6 | zeroThreshold | 0.0 |
| 7 | 0 + (2-0) × (7-6)/(10-6) | 0.5 |
| 8 | 0 + (2-0) × (8-6)/(10-6) | 1.0 |
| 9 | 0 + (2-0) × (9-6)/(10-6) | 1.5 |
| 10 | ≥ maxRating | 2.0 |

## 8.3 Формула для тестирования (Score)

```javascript
// efficiency_calc.js, строки 189-201
function interpolateTestPoints(score, totalQuestions, minPoints, zeroThreshold, maxPoints) {
  if (score <= 0) return minPoints;
  if (score >= totalQuestions) return maxPoints;

  if (score <= zeroThreshold) {
    return minPoints + (0 - minPoints) * (score / zeroThreshold);
  } else {
    const range = totalQuestions - zeroThreshold;
    return 0 + (maxPoints - 0) * ((score - zeroThreshold) / range);
  }
}
```

### Таблица примеров для Test (min=-2.5, zero=15, max=+3.5, total=20):

| Score | Формула | Результат |
|-------|---------|-----------|
| 0 | ≤ 0 | -2.5 |
| 5 | -2.5 + (0-(-2.5)) × 5/15 | -1.67 |
| 10 | -2.5 + (0-(-2.5)) × 10/15 | -0.83 |
| 15 | zeroThreshold | 0.0 |
| 17 | 0 + (3.5-0) × (17-15)/(20-15) | 1.4 |
| 20 | ≥ totalQuestions | 3.5 |

## 8.4 Простые бинарные формулы

### Посещаемость (Attendance):
```javascript
if (isOnTime) {
  points = onTimePoints;  // +0.5
} else {
  points = latePoints;    // -1.0
}
```

### РКО:
```javascript
if (hasRko) {
  points = hasRkoPoints;   // +1.0
} else {
  points = noRkoPoints;    // -3.0
}
```

### Отзывы (Reviews):
```javascript
if (review.rating >= 4) {
  points = positivePoints;  // +1.5
} else {
  points = negativePoints;  // -1.5
}
```

### Конверты (Envelope):
```javascript
if (status === 'confirmed') {
  points = submittedPoints;     // 0
} else {
  points = notSubmittedPoints;  // -5
}
```

## 8.5 Расчёт итогового рейтинга

```javascript
// efficiency_calc.js, строки 788-818
async function calculateFullEfficiency(employeeId, employeeName, shopAddress, month) {
  const breakdown = {
    shift:               await calculateShiftPoints(...),
    recount:             await calculateRecountPoints(...),
    handover:            await calculateHandoverPoints(...),
    attendance:          await calculateAttendancePoints(...),
    attendancePenalties: await calculateAttendancePenalties(...),
    test:                await calculateTestPoints(...),
    reviews:             await calculateReviewsPoints(...),
    productSearch:       await calculateProductSearchPoints(...),
    rko:                 await calculateRkoPoints(...),
    tasks:               await calculateTasksPoints(...),
    orders:              await calculateOrdersPoints(...),
    envelope:            await calculateEnvelopePoints(...),
  };

  // Простое суммирование всех баллов
  const total = Object.values(breakdown).reduce((sum, v) => sum + v, 0);

  return { total, breakdown };
}
```

### Формула итогового балла:

```
totalPoints = shift + recount + shiftHandover + attendance +
              attendancePenalties + test + reviews + productSearch +
              rko + tasks + orders + envelope
```

## 8.6 Пример расчёта для сотрудника

**Сотрудник:** Иван Петров
**Месяц:** 2026-02

| Категория | Данные | Расчёт | Результат |
|-----------|--------|--------|-----------|
| Shift | 4 пересменки: ratings 7,8,6,9 | (0.5+1.0+0+1.5)/4 | +0.75 |
| Recount | 4 пересчёта: ratings 6,7,8,7 | (0+0.33+0.67+0.33)/4 | +0.33 |
| Handover | 2 сдачи: ratings 8,9 | (1.0+1.5)/2 | +1.25 |
| Attendance | 20 вовремя, 2 опоздания | 20×0.5 + 2×(-1) | +8.0 |
| Penalties | 1 штраф за опоздание | из файла | -2.0 |
| Test | 1 тест: 17/20 | interpolate(17,20,-2.5,15,3.5) | +1.4 |
| Reviews | 1 положительный | 1×1.5 | +1.5 |
| ProductSearch | 15 ответов | 15×0.2 | +3.0 |
| RKO | 20 дней есть, 2 нет | 20×1 + 2×(-3) | +14.0 |
| Tasks | 8 выполненных | 8×1.0 | +8.0 |
| Orders | N/A | - | 0 |
| Envelope | 10 confirmed, 12 pending | 10×0 + 12×(-5) | -60.0 |
| | | **ИТОГО** | **-23.77** |

## 8.7 Batch-оптимизация расчётов

```javascript
// efficiency_calc.js, строки 1029-1056
async function calculateBatchEfficiency(employees, month) {
  // ШАГ 1: Загрузить ВСЕ данные один раз
  const cache = await initBatchCache(month);

  // ШАГ 2: Для каждого сотрудника используем кэш
  const results = new Map();
  for (const emp of employees) {
    const efficiency = await calculateFullEfficiencyCached(
      emp.id, emp.name, emp.shopAddress, month, cache
    );
    results.set(emp.id, efficiency);
  }

  // ШАГ 3: Очистить кэш
  clearBatchCache();

  return results;
}
```

**Оптимизация:**
- Без batch: 1000 сотрудников × 12 категорий = 12000 I/O операций
- С batch: 1 загрузка всех файлов + 12000 операций в памяти
- **Ускорение:** ~50-100x

## 8.8 Связь с Колесом Удачи

```
Расчёт эффективности (12 категорий)
           ↓
   Сортировка по totalPoints
           ↓
    Топ-3 сотрудника месяца
           ↓
    ┌──────────────────┐
    │  Fortune Wheel   │
    │  (Колесо удачи)  │
    └──────────────────┘
           ↓
   15 секторов с призами
```

**Условия доступа к колесу:**
- Топ-1: 2 прокрутки
- Топ-2: 1 прокрутка
- Топ-3: 1 прокрутка

## 8.9 Файлы настроек баллов

**Директория:** `/var/www/points-settings/`

| Файл | Содержимое |
|------|------------|
| shift_points_settings.json | minPoints, zeroThreshold, maxPoints, timeWindows |
| recount_points_settings.json | minPoints, zeroThreshold, maxPoints, timeWindows |
| shift_handover_points_settings.json | minPoints, zeroThreshold, maxPoints, adminTimeout |
| attendance_points_settings.json | onTimePoints, latePoints, timeWindows |
| test_points_settings.json | minPoints, zeroThreshold, maxPoints, totalQuestions |
| rko_points_settings.json | hasRkoPoints, noRkoPoints, timeWindows |
| reviews_points_settings.json | positivePoints, negativePoints |
| product_search_points_settings.json | answeredPoints, notAnsweredPoints, timeout |
| orders_points_settings.json | acceptedPoints, rejectedPoints |
| envelope_points_settings.json | submittedPoints, notSubmittedPoints |
| manager_points_settings.json | confirmedPoints, rejectedPenalty |

### Пример файла настроек:

```json
// shift_points_settings.json
{
  "id": "shift_points",
  "category": "shift",
  "minPoints": -3,
  "zeroThreshold": 7,
  "maxPoints": 2,
  "minRating": 1,
  "maxRating": 10,
  "morningStartTime": "07:00",
  "morningEndTime": "13:00",
  "eveningStartTime": "14:00",
  "eveningEndTime": "23:00",
  "missedPenalty": -3,
  "adminReviewTimeout": 2,
  "createdAt": "2026-01-15T10:00:00Z",
  "updatedAt": "2026-02-05T15:30:00Z"
}
```

---

# 9. РОЛИ И МАТРИЦА ДОСТУПА

## 9.1 Иерархия ролей

```
                    ┌───────────────┐
                    │   Developer   │  (полный доступ)
                    └───────┬───────┘
                            │
                    ┌───────▼───────┐
                    │     Admin     │  (управление сетью)
                    └───────┬───────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
   ┌──────▼──────┐  ┌───────▼───────┐  ┌──────▼──────┐
   │   Manager   │  │ Store Manager │  │   Manager   │
   │  (Группа A) │  │   (Точка X)   │  │  (Группа B) │
   └──────┬──────┘  └───────┬───────┘  └──────┬──────┘
          │                 │                 │
   ┌──────▼──────┐  ┌───────▼───────┐  ┌──────▼──────┐
   │  Employee   │  │   Employee    │  │  Employee   │
   │ (Магазин 1) │  │  (Магазин X)  │  │ (Магазин 2) │
   └─────────────┘  └───────────────┘  └─────────────┘
                            │
                    ┌───────▼───────┐
                    │    Client     │  (клиент)
                    └───────────────┘
```

## 9.2 Определение роли пользователя

**Файл:** `lib/features/employees/services/user_role_service.dart`

```dart
// Приоритет проверки:
// 1. developers (телефон в списке разработчиков)
// 2. managers (телефон в списке менеджеров)
// 3. store-managers (телефон в списке старших менеджеров)
// 4. employees (телефон в списке сотрудников)
// 5. client (по умолчанию)

static Future<UserRoleData> getUserRole(String phone) async {
  // 1. Проверить developers
  final devResponse = await http.get('/api/shop-managers/developers');
  if (devResponse.developers.contains(phone)) {
    return UserRoleData(role: UserRole.developer, ...);
  }

  // 2. Проверить managers
  final mgrResponse = await http.get('/api/shop-managers/managers');
  for (final manager in mgrResponse.managers) {
    if (manager.phone == phone) {
      return UserRoleData(role: UserRole.admin, shops: manager.shops);
    }
  }

  // 3. Проверить store-managers
  final storeMgrResponse = await http.get('/api/shop-managers/store-managers');
  for (final sm in storeMgrResponse.storeManagers) {
    if (sm.phone == phone) {
      return UserRoleData(role: UserRole.manager, shops: sm.shops);
    }
  }

  // 4. Проверить employees
  final empResponse = await http.get('/api/employees');
  for (final emp in empResponse.employees) {
    if (emp.phone == phone) {
      return UserRoleData(role: UserRole.employee, shop: emp.shopAddress);
    }
  }

  // 5. По умолчанию - клиент
  return UserRoleData(role: UserRole.client);
}
```

## 9.3 Матрица доступа: Модули × Роли

| Модуль | Client | Employee | Manager | Admin | Developer |
|--------|--------|----------|---------|-------|-----------|
| **Лояльность** | ✅ Свои баллы | ✅ Просмотр | ✅ Начисление | ✅ Полный | ✅ Полный |
| **Заказы** | ✅ Создание | ✅ Обработка | ✅ Отмена | ✅ Полный | ✅ Полный |
| **Меню** | ✅ Просмотр | ✅ Просмотр | ✅ Редактирование | ✅ Полный | ✅ Полный |
| **Отзывы** | ✅ Написание | ✅ Просмотр | ✅ Ответы | ✅ Полный | ✅ Полный |
| **Рефералы** | ✅ Свой код | ❌ | ❌ | ✅ Статистика | ✅ Полный |
| **Посещаемость** | ❌ | ✅ Отметка | ✅ Просмотр всех | ✅ Штрафы | ✅ Полный |
| **Пересменки** | ❌ | ✅ Ответы | ✅ Просмотр | ✅ Оценка | ✅ Полный |
| **Пересчёты** | ❌ | ✅ Ответы | ✅ Просмотр | ✅ Оценка | ✅ Полный |
| **Сдача смены** | ❌ | ✅ Сдача | ✅ Просмотр | ✅ Подтверждение | ✅ Полный |
| **РКО** | ❌ | ✅ Сдача | ✅ Просмотр | ✅ Подтверждение | ✅ Полный |
| **Конверты** | ❌ | ✅ Сдача | ✅ Просмотр | ✅ Подтверждение | ✅ Полный |
| **Задачи** | ❌ | ✅ Выполнение | ✅ Создание | ✅ Полный | ✅ Полный |
| **Тестирование** | ❌ | ✅ Прохождение | ✅ Просмотр | ✅ Редактирование | ✅ Полный |
| **Обучение** | ❌ | ✅ Чтение | ✅ Просмотр | ✅ Редактирование | ✅ Полный |
| **Эффективность** | ❌ | ✅ Своя | ✅ Своих сотрудников | ✅ Всех | ✅ Полный |
| **Рейтинг** | ❌ | ✅ Свой | ✅ Просмотр | ✅ Полный | ✅ Полный |
| **Колесо удачи** | ❌ | ✅ Если в топ-3 | ✅ Просмотр | ✅ Настройки | ✅ Полный |
| **Чат сотрудников** | ❌ | ✅ Участие | ✅ Участие | ✅ Модерация | ✅ Полный |
| **График работы** | ❌ | ✅ Свой | ✅ Своих точек | ✅ Полный | ✅ Полный |
| **Сотрудники** | ❌ | ❌ | ✅ Своих точек | ✅ Полный | ✅ Полный |
| **Магазины** | ❌ | ❌ | ✅ Своих | ✅ Полный | ✅ Полный |
| **Поставщики** | ❌ | ❌ | ❌ | ✅ Полный | ✅ Полный |
| **Главная касса** | ❌ | ❌ | ❌ | ✅ Полный | ✅ Полный |
| **Очистка данных** | ❌ | ❌ | ❌ | ✅ Полный | ✅ Полный |
| **Настройки баллов** | ❌ | ❌ | ❌ | ✅ Полный | ✅ Полный |
| **KPI** | ❌ | ❌ | ✅ Просмотр | ✅ Полный | ✅ Полный |
| **ИИ Распознавание** | ❌ | ❌ | ❌ | ✅ Настройки | ✅ Полный |

## 9.4 Проверка прав в коде

### Flutter (клиентская сторона):

```dart
// lib/features/employees/services/user_role_service.dart
class UserRoleService {
  static UserRole? _currentRole;
  static List<String>? _currentShops;

  // Проверка роли
  static bool isAdmin() => _currentRole == UserRole.admin || isDeveloper();
  static bool isManager() => _currentRole == UserRole.manager || isAdmin();
  static bool isEmployee() => _currentRole == UserRole.employee || isManager();
  static bool isDeveloper() => _currentRole == UserRole.developer;

  // Проверка доступа к магазину
  static bool hasAccessToShop(String shopAddress) {
    if (isAdmin()) return true;
    return _currentShops?.contains(shopAddress) ?? false;
  }
}
```

### Node.js (серверная сторона):

```javascript
// loyalty-proxy/api/shop_managers_api.js
async function checkManagerAccess(phone, shopAddress) {
  const managers = await loadManagers();
  const manager = managers.find(m => m.phone === phone);

  if (!manager) return false;
  if (manager.role === 'developer') return true;
  if (manager.role === 'admin') return true;

  return manager.shops?.includes(shopAddress) ?? false;
}
```

---

# 10. СТРУКТУРА ДАННЫХ (/var/www/)

## 10.1 Дерево директорий

```
/var/www/
├── attendance/                    # Отметки посещаемости
│   └── YYYY-MM-DD.json           # Отметки за день
│
├── attendance-pending/            # Pending отметки
│   └── pending_att_*.json        # Ожидающие отметки
│
├── shift-reports/                 # Отчёты пересменок
│   └── YYYY-MM-DD.json           # Отчёты за день
│
├── shift-pending/                 # Pending пересменки
│   └── pending_shift_*.json
│
├── recount-reports/               # Отчёты пересчётов
│   └── YYYY-MM-DD.json
│
├── recount-pending/               # Pending пересчёты
│   └── pending_recount_*.json
│
├── shift-handover-reports/        # Сдача смены
│   └── report_*.json             # Каждый отчёт отдельным файлом
│
├── shift-handover-pending/        # Pending сдачи смены
│   └── pending_handover_*.json
│
├── rko/                           # РКО документы
│   ├── YYYY-MM/
│   │   └── rko_shopName_date.json
│   └── rko_metadata.json         # Метаданные всех РКО
│
├── rko-pending/                   # Pending РКО
│   └── pending_rko_*.json
│
├── envelope-reports/              # Конверты
│   └── env_YYYYMMDD_shop_shift.json
│
├── envelope-pending/              # Pending конверты
│   └── pending_env_*.json
│
├── work-schedules/                # Графики работы
│   └── YYYY-MM.json              # График на месяц
│
├── employees/                     # Сотрудники
│   └── employees.json            # Все сотрудники
│
├── shops/                         # Магазины
│   └── shops.json                # Все магазины
│
├── shop-managers/                 # Менеджеры
│   ├── developers.json
│   ├── managers.json
│   └── store-managers.json
│
├── shop-coordinates/              # Координаты магазинов
│   └── coordinates.json
│
├── shop-settings/                 # Настройки магазинов
│   └── {shopAddress}.json
│
├── clients/                       # Клиенты
│   └── clients.json
│
├── client-reviews/                # Отзывы клиентов
│   └── YYYY-MM.json
│
├── loyalty/                       # Лояльность
│   ├── {phone}.json              # Баллы клиента
│   └── transactions/
│       └── YYYY-MM.json          # История транзакций
│
├── loyalty-gamification-settings.json  # Настройки геймификации (в разработке)
│   # { levels: [...], wheel: { enabled, freeDrinksPerSpin, sectors: [...] } }
│
├── wheel-history/                 # История прокруток колеса (в разработке)
│   └── {phone}.json              # Прокрутки клиента
│
├── orders/                        # Заказы
│   └── YYYY-MM-DD/
│       └── order_*.json
│
├── tasks/                         # Задачи
│   └── YYYY-MM.json
│
├── recurring-tasks/               # Циклические задачи
│   ├── templates.json            # Шаблоны
│   └── instances/
│       └── YYYY-MM-DD.json
│
├── test-questions/                # Вопросы для тестов
│   └── questions.json
│
├── test-results/                  # Результаты тестов
│   └── YYYY-MM.json
│
├── training-articles/             # Статьи для обучения
│   └── articles.json
│
├── product-questions/             # Поиск товара
│   └── question_*.json
│
├── product-question-dialogs/      # Диалоги поиска
│   └── dialog_*.json
│
├── product-question-photos/      # Фото к вопросам о товарах (nginx static)
│   └── product_question_*.jpg
│
├── employee-chat/                 # Чат сотрудников
│   ├── messages/
│   │   └── YYYY-MM-DD.json
│   └── groups.json
│
├── efficiency-penalties/          # Штрафы
│   └── YYYY-MM.json
│
├── points-settings/               # Настройки баллов
│   ├── shift_points_settings.json
│   ├── recount_points_settings.json
│   ├── attendance_points_settings.json
│   └── ...
│
├── fcm-tokens/                    # Firebase токены
│   └── tokens.json
│
├── suppliers/                     # Поставщики
│   └── suppliers.json
│
├── job-applications/              # Заявки на работу
│   └── applications.json
│
├── referrals/                     # Рефералы
│   └── referrals.json
│
├── withdrawals/                   # Выемки
│   └── YYYY-MM.json
│
├── media/                         # Загруженные медиа
│   ├── shift-handover/
│   ├── chat/
│   └── products/
│
├── cigarette-vision/              # ИИ распознавание
│   ├── samples/
│   ├── models/
│   └── settings.json
│
├── z-report-templates/            # Шаблоны Z-отчётов
│   └── templates.json
│
├── automation-state/              # Состояние schedulers
│   ├── attendance_state.json
│   ├── envelope_state.json
│   ├── shift_state.json
│   ├── handover_state.json
│   ├── rko_state.json
│   ├── recount_state.json
│   └── product_questions_state.json
│
└── app-logs/                      # Логи приложения
    └── YYYY-MM-DD.json
```

## 10.2 JSON Schemas основных сущностей

### Employee (Сотрудник):

```json
{
  "id": "emp_12345",
  "phone": "79991234567",
  "name": "Иван Петров",
  "shopAddress": "ул. Пушкина, 10",
  "position": "Бариста",
  "hireDate": "2025-01-15",
  "status": "active",
  "createdAt": "2025-01-15T10:00:00Z",
  "updatedAt": "2026-02-05T15:30:00Z"
}
```

### Client (Клиент):

```json
{
  "id": "client_67890",
  "phone": "79998887766",
  "name": "Мария Сидорова",
  "email": "maria@example.com",
  "registeredAt": "2025-03-20T14:00:00Z",
  "referralCode": "REF123",
  "referredBy": "emp_12345",
  "loyaltyPoints": 150,
  "totalOrders": 25,
  "lastOrderAt": "2026-02-04T18:30:00Z"
}
```

### Shift Report (Пересменка):

```json
{
  "id": "shift_report_001",
  "shopAddress": "ул. Пушкина, 10",
  "date": "2026-02-05",
  "shiftType": "morning",
  "status": "confirmed",
  "employeePhone": "79991234567",
  "employeeName": "Иван Петров",
  "questions": [
    {
      "id": "q1",
      "question": "Сколько молока осталось?",
      "answer": "5 литров",
      "answeredAt": "2026-02-05T08:30:00Z"
    }
  ],
  "adminRating": 8,
  "adminName": "Админ",
  "ratedAt": "2026-02-05T10:00:00Z",
  "createdAt": "2026-02-05T07:00:00Z",
  "deadline": "2026-02-05T13:00:00Z"
}
```

### Order (Заказ):

```json
{
  "id": "order_20260205_001",
  "clientPhone": "79998887766",
  "clientName": "Мария Сидорова",
  "shopAddress": "ул. Пушкина, 10",
  "items": [
    {
      "barcode": "4606816000001",
      "name": "Капучино",
      "quantity": 2,
      "price": 150
    }
  ],
  "total": 300,
  "loyaltyPointsUsed": 50,
  "finalTotal": 250,
  "status": "completed",
  "paymentMethod": "card",
  "employeeName": "Иван Петров",
  "createdAt": "2026-02-05T14:30:00Z",
  "acceptedAt": "2026-02-05T14:32:00Z",
  "completedAt": "2026-02-05T14:45:00Z"
}
```

### Efficiency Penalty (Штраф):

```json
{
  "id": "penalty_12345",
  "type": "employee",
  "entityId": "79991234567",
  "entityName": "Иван Петров",
  "shopAddress": "ул. Пушкина, 10",
  "category": "attendance_missed_penalty",
  "categoryName": "Пропущена отметка посещаемости",
  "date": "2026-02-05",
  "shiftType": "morning",
  "points": -2,
  "reason": "Не отмечен на работе до 09:00",
  "sourceId": "pending_att_shop1_morning",
  "createdAt": "2026-02-05T09:05:00Z"
}
```

### Work Schedule (График работы):

```json
{
  "month": "2026-02",
  "shopAddress": "ул. Пушкина, 10",
  "schedule": [
    {
      "date": "2026-02-05",
      "shifts": [
        {
          "type": "morning",
          "employees": ["Иван Петров", "Анна Смирнова"]
        },
        {
          "type": "evening",
          "employees": ["Петр Иванов"]
        }
      ]
    }
  ],
  "updatedAt": "2026-02-01T10:00:00Z"
}
```

### Attendance (Посещаемость):

```json
{
  "date": "2026-02-05",
  "records": [
    {
      "identifier": "Иван Петров",
      "shopAddress": "ул. Пушкина, 10",
      "shiftType": "morning",
      "action": "check-in",
      "timestamp": "2026-02-05T07:45:00Z",
      "latitude": 55.7558,
      "longitude": 37.6173,
      "isOnTime": true,
      "deviceId": "device_123"
    }
  ]
}
```

---

# 11. СЛАБЫЕ МЕСТА И РЕКОМЕНДАЦИИ

> **Дата аудита:** 2026-02-08 (первичный) + 2026-02-09 (полный аудит)
> **Дата исправлений:** 2026-02-08 (Category 1 + Category 2 + Phase 3 fixes applied)
> **Методология:** Полный статический анализ всего кода (449 Dart файлов, ~37000 строк JS, 56 API модулей)

### Компоненты безопасности (добавлены 2026-02-08):

| Компонент | Файл | Описание |
|-----------|------|----------|
| Session Middleware | `loyalty-proxy/utils/session_middleware.js` | Неблокирующий Express middleware. In-memory token index (Map), O(1) lookup, перестройка каждые 5 мин. Заполняет `req.user = {phone, name, isAdmin}` |
| API Key в Flutter | `lib/core/constants/api_constants.dart` | `jsonHeaders` getter автоматически добавляет `X-API-Key` и `Authorization: Bearer` ко всем запросам |
| Session Token Flow | `lib/features/auth/services/auth_service.dart` | При логине `ApiConstants.sessionToken = token`, при логауте `= null`. Инициализация в `main.dart` |
| WebSocket Auth | `loyalty-proxy/api/employee_chat_websocket.js` | Опциональная проверка `token` query param через `verifyToken()`. Код 4003 при невалидном токене |
| Bcrypt PIN | `loyalty-proxy/api/auth_api.js` | `bcryptjs` для хеширования PIN. Авто-миграция с SHA-256 при успешном логине. `hashType` поле в данных |
| RKO File Validation | `loyalty-proxy/index.js` | Отдельный `uploadRKO` multer с `docFileFilter` (DOCX/DOC/PDF). `safeFileName` + `isPathSafe()` |
| File Helpers | `loyalty-proxy/utils/file_helpers.js` | Общие утилиты: `fileExists`, `ensureDir`, `loadJsonFile`, `saveJsonFile`, `sanitizeId`, `isPathSafe`, `sanitizePhone` |
| Path Traversal Protection | 10 API модулей | `sanitizeId()` в index.js (25 эндпоинтов), `sanitizePhone()` в clients/loyalty/orders/gamification, `sanitizeFileName()` в rko/cigarette, `sanitizeDate()` в media |
| API Smoke Test | `loyalty-proxy/tests/smoke-test.js` | Автоматический тест 73 GET + 13 POST эндпоинтов. Baseline + post-deploy сравнение |
| Load Test | `loyalty-proxy/tests/load-test.js` | Нагрузочное тестирование: 5 сценариев, p95 метрики, WebSocket нагрузка |

## 11.1 Критические проблемы (из аудита 08-09.02.2026)

**Статус: 7 из 8 блокеров от 08.02 РЕШЕНЫ. Новых 12 критических + 24 важных от аудита 09.02.**

| № | Проблема | Статус | Описание | Приоритет |
|---|----------|--------|----------|-----------|
| 1 | API аутентификация отключена | ✅ **РЕШЕНО** | API Key включён (`API_KEY_ENABLED=true`), Flutter отправляет `X-API-Key` | ✅ |
| 2 | Нет серверной проверки ролей | ✅ **РЕШЕНО** | `session_middleware.js` заполняет `req.user = {phone, name, isAdmin}` | ✅ |
| 3 | Hardcoded Telegram Bot Token | ✅ **РЕШЕНО** | Только `process.env.TELEGRAM_BOT_TOKEN` | ✅ |
| 4 | WebSocket без аутентификации | ✅ **РЕШЕНО** | `verifyToken()` в handshake, close(4003) | ✅ |
| 5 | Публичная загрузка файлов | ✅ **РЕШЕНО** | `uploadRKO` с `docFileFilter`, `safeFileName` | ✅ |
| 6 | PIN — однократный SHA-256 | ✅ **РЕШЕНО** | bcryptjs + авто-миграция | ✅ |
| 7 | File locking не используется | ⚠️ Частично | `file_lock.js` существует, 197 `writeFile` без блокировки | P1 |
| 8 | Бэкапы | ✅ **РЕШЕНО** | `backup-script.sh` для cron | ✅ |

### Новые проблемы (аудит 09.02.2026):

| № | Файл | Описание | Уровень |
|---|------|----------|---------|
| N1 | `api_constants.dart:7` | API ключ захардкожен в исходниках — извлекается из APK | 🔴 |
| N2 | `index.js:148` | `API_KEY_ENABLED=false` по умолчанию — если env не задан, API публичен | 🔴 |
| N3 | Все API файлы | Нет проверки `req.user.isAdmin` на write-операциях | 🔴 |
| N4 | `auth_api.js:282` | Регистрация возвращает `pinHash` и `salt` в ответе | 🔴 |
| N5 | `auth_api.js:657` | GET `/api/auth/session/:phone` без аутентификации | 🔴 |
| N6 | `product_questions_penalty_scheduler.js` | `getHours()` = LOCAL time, не Moscow — неправильные штрафы | 🔴 |
| N7 | `clients_api.js` | Broadcast body mismatch: Flutter → `{text, imageUrl}`, сервер ← `{message, phones}` | 🔴 |
| N8 | `auth_service.dart` | Вызывает `/api/auth/refresh-session` — endpoint НЕ существует на сервере | 🔴 |
| N9 | `admin_cache.js:80` | Синхронные `readdirSync`/`readFileSync` блокируют event loop | 🔴 |
| N10 | `efficiency_calc.js:301` | ~6500 файловых чтений на single-employee запрос | 🔴 |
| N11 | 15+ API файлов | Нет пагинации — эндпоинты возвращают ВСЕ записи | 🔴 |
| N12 | `efficiency_calc.js` | 5 из 10 категорий не работают (envelope, reviews, orders, productSearch, tasks) | 🔴 |

## 11.2 Безопасность

| № | Уязвимость | Риск | Статус |
|---|------------|------|--------|
| 1 | API Key по умолчанию выключен | **КРИТИЧЕСКИЙ** | ✅ РЕШЕНО (но N2: env fallback!) |
| 2 | CORS допускает HTTP origin | Средний | ✅ РЕШЕНО |
| 3 | Нет CSRF защиты | Средний | НЕ РЕШЕНО |
| 4 | PIN — SHA-256 без итераций | **КРИТИЧЕСКИЙ** | ✅ РЕШЕНО (bcryptjs) |
| 5 | User enumeration через /api/auth | Средний | НЕ РЕШЕНО |
| 6 | bodyParser limit 50MB | Средний | ✅ РЕШЕНО (10MB) |
| 7 | Регистрация возвращает pinHash/salt | **КРИТИЧЕСКИЙ** | ⚠️ НЕ РЕШЕНО (N4) |
| 8 | OTP в plaintext JSON файлах | Низкий | НЕ РЕШЕНО |
| 9 | WebSocket auth опциональна | **ВАЖНО** | ⚠️ Обратно совместимо (без token всё ещё работает) |
| 10 | Biometric enable/disable без auth | Средний | НЕ РЕШЕНО |
| 11 | Upload-photo в publicPaths | **ВАЖНО** | НЕ РЕШЕНО |
| 12 | application/octet-stream в upload | Средний | НЕ РЕШЕНО |
| 13 | Слабый salt из DateTime.now() | Средний | НЕ РЕШЕНО |
| 14 | Нет certificate pinning в Flutter | Средний | НЕ РЕШЕНО |
| 15 | sanitizeId/isPathSafe | ✅ Во всех модулях | ✅ РЕШЕНО |

## 11.3 Архитектурные проблемы

| № | Проблема | Влияние |
|---|----------|---------|
| 1 | ~~index.js — 7611 строк~~ | ✅ Рефакторинг: 26 модулей вынесены в api/, мёртвый код удалён |
| 2 | Файловое хранилище JSON без транзакций | Race conditions, O(n) чтение. 197 writeFile без lock |
| 3 | 200+ setState перестраивают целые страницы | Медленный UI, нет state management |
| 4 | Нет lazy loading ни на клиенте, ни на сервере | Все данные грузятся сразу |
| 5 | Страницы >3000 строк | cigarette_training_page.dart: 3992 строк |
| 6 | Silent error handling в Flutter | Пользователь не видит ошибок |
| 7 | 30+ Image.network без кэширования | Каждый скролл = повторная загрузка |
| 8 | MainMenuPage — 10+ API вызовов при открытии | Медленный старт |
| 9 | Sort/filter в build() | Пересчёт на каждом rebuild |
| 10 | Нет сжатия фото при загрузке (3-10MB) | Трафик, место на диске |

## 11.4 Dead Code

| Элемент | Файл |
|---------|------|
| ~~`_verifyRegistrationInBackground()`~~ | ✅ Удалено |
| ~~`_checkUserRoleInBackground()`~~ | ✅ Удалено |
| ~~5 backup-файлов в git~~ | ✅ Удалены + .gitignore |
| `ApiConstants.kpiEndpoint` | `api_constants.dart` — не используется |
| `MenuService` | `menu/services/` — мёртвый код |
| Deprecated `ReferralSettings` | `referrals/` — можно удалить |
| 9 `_settings` полей в pages | Неиспользуемые поля |
| TODO: "Обновить PIN на сервере" | auth_service.dart |

## 11.5 Рекомендации по приоритету

### Неделя 1 — 🔴 Критические (блокеры):
| # | Задача | Файл(ы) | Оценка |
|---|--------|---------|--------|
| 1 | Добавить `isAdmin` проверку на все write-эндпоинты | Все api/ файлы | 3-4 часа |
| 2 | Удалить pinHash/salt из ответа регистрации | `auth_api.js` | 15 мин |
| 3 | Вынести API ключ из Flutter кода в build config | `api_constants.dart` | 1 час |
| 4 | Сделать `API_KEY_ENABLED=true` по умолчанию | `index.js` | 15 мин |
| 5 | Исправить product_questions scheduler — Moscow time | `product_questions_penalty_scheduler.js` | 30 мин |
| 6 | Подключить file_lock.js ко всем API | Все api/ файлы | 2-3 часа |
| 7 | Исправить clients broadcast body mismatch | `client_service.dart` / `clients_api.js` | 30 мин |
| 8 | Добавить `/api/auth/refresh-session` endpoint | `auth_api.js` | 30 мин |

### Неделя 2 — 🟠 Важные:
| # | Задача | Файл(ы) | Оценка |
|---|--------|---------|--------|
| 9 | Пагинация на 15+ list endpoints | Все api/ файлы | 2-3 часа |
| 10 | Исправить 5 сломанных категорий efficiency_calc | `efficiency_calc.js` | 2 часа |
| 11 | Заменить Image.network → CachedNetworkImage (30+ мест) | Flutter pages | 1 час |
| 12 | Сжатие фото в PhotoUploadService | `photo_upload_service.dart` | 30 мин |
| 13 | Расширить окно генерации envelope/coffee_machine schedulers | 2 файла | 1 час |
| 14 | Сделать admin_cache.js async | `admin_cache.js` | 1 час |
| 15 | Сделать WebSocket auth обязательной | `employee_chat_websocket.js` | 30 мин |
| 16 | Убрать /upload-photo из publicPaths | `index.js` | 5 мин |
| 17 | Добавить кэш employees/shops на сервере | Новый модуль | 2 часа |

### Неделя 3+ — 🟡 Рекомендации:
| # | Задача |
|---|--------|
| 18 | Certificate pinning в Flutter |
| 19 | `--obfuscate` для Flutter build |
| 20 | Автоматическая ротация/очистка данных |
| 21 | Rate limit на auth endpoints (10/мин) |
| 22 | Batch API для MainMenuPage |
| 23 | Batch API для MyEfficiencyPage |
| 24 | Кэширование settings в efficiency_calc.js batch |
| 25 | Стандартизация формата pending/failed endpoints |
| 26 | Очистка onlineStatus Map в WebSocket |
| 27 | Прекомпиляция sort/filter вне build() |
| 28 | Удалить мёртвый код (MenuService, ReferralSettings) |
| 29 | Исправить 45 warnings из flutter analyze |
| 30 | Добавить get-by-ID endpoints для отчётов |
| 31 | Стабилизировать penalty file format |

### Долгосрочно (P3 — 3-6 месяцев):
32. Миграция на SQLite/PostgreSQL
33. State management (Riverpod/Bloc)
34. Router (go_router)
35. Рефакторинг страниц >1000 строк
36. CI/CD pipeline

---

# 12. КАРТА СВЯЗЕЙ МОДУЛЕЙ

## 12.1 Flutter модуль → API → Файлы → Scheduler → Push

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  Flutter модуль         → API endpoints           → /var/www/ файлы        │
│  (+ Scheduler)          (метод, путь)              (хранение)              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  auth/                  POST /api/auth/register   → auth-sessions/          │
│                         POST /api/auth/login        auth-pins/              │
│                         POST /api/auth/request-otp  auth-otp/              │
│                         POST /api/auth/verify-otp                           │
│                         POST /api/auth/reset-pin                            │
│                         POST /api/auth/logout                               │
│                         ⚠️ refresh-session (не существует!)                │
│                                                                              │
│  attendance/            GET/POST /api/attendance   → attendance/             │
│  📅 attendance_sched    GET /api/attendance/pending  attendance-pending/     │
│  → push сотруднику      GET /api/attendance/check                           │
│                                                                              │
│  shifts/                GET/POST /api/shift-reports → shift-reports/        │
│  📅 shift_sched         PUT /api/shift-reports/:id   shift-pending/         │
│  → push сотруднику      POST /api/shift-questions    shift-questions/       │
│  → push админу          GET /api/pending-shift-reports shift-photos/        │
│                                                                              │
│  shift_handover/        GET/POST /api/shift-handover-reports                │
│  📅 handover_sched      → shift-handover-reports/ + shift-handover-pending/ │
│  → push сотруднику      GET/POST/PUT/DELETE /api/shift-handover-questions   │
│  → push админу                                                              │
│                                                                              │
│  recount/               GET/POST /api/recount-reports → recount-reports/    │
│  📅 recount_sched       → recount-pending/                                  │
│  → push сотруднику                                                          │
│                                                                              │
│  envelope/              GET/POST /api/envelope-reports → envelope-reports/  │
│  📅 envelope_sched      → envelope-pending/                                 │
│  → push сотруднику                                                          │
│                                                                              │
│  rko/                   GET/POST /api/rko          → rko/ + rko-pending/   │
│  📅 rko_sched           rko_metadata.json                                   │
│  → push сотруднику                                                          │
│                                                                              │
│  coffee_machine/        GET/POST /api/coffee-machine-reports                │
│  📅 coffee_sched        → coffee-machine-reports/ + coffee-machine-pending/ │
│  → push сотруднику       coffee-machine-templates/ + shop-configs/          │
│                                                                              │
│  employees/             GET/POST/PUT/DELETE /api/employees → employees/     │
│  work_schedule/         GET/POST /api/work-schedule → work-schedules/      │
│  shops/                 GET/POST/PUT/DELETE /api/shops → shops/             │
│                                                                              │
│  efficiency/            GET /api/efficiency/reports-batch                    │
│                         GET/POST /api/efficiency-penalties                   │
│                         → efficiency-penalties/ + points-settings/           │
│                                                                              │
│  fortune_wheel/         GET/POST /api/fortune-wheel/* → fortune-wheel/     │
│  rating/                GET /api/rating-wheel/* → (вычисляется)             │
│                                                                              │
│  tasks/                 GET/POST/PUT/DELETE /api/tasks → tasks/             │
│  product_questions/     GET/POST /api/product-questions                      │
│  📅 pq_penalty_sched    → product-questions/ + product-question-dialogs/    │
│  → push сотруднику                                                          │
│                                                                              │
│  employee_chat/         REST + WebSocket /ws → employee-chats/ + groups/   │
│  training/              GET/POST /api/training-articles → training-articles/│
│  tests/                 GET/POST /api/test-* → test-questions/ + results/  │
│  reviews/               GET/POST /api/reviews → client-reviews/            │
│                                                                              │
│  clients/               GET/POST /api/clients → clients/                   │
│  loyalty/               GET/POST /api/loyalty/* → loyalty/                 │
│  loyalty_gamification/  GET/POST /api/loyalty-gamification/* → settings     │
│  orders/                GET/POST /api/orders → orders/                     │
│  referrals/             GET/POST /api/referrals → referrals/               │
│  recipes/               GET/POST/PUT/DELETE /api/recipes → recipes/        │
│  suppliers/             GET/POST/PUT/DELETE /api/suppliers → suppliers/     │
│  job_application/       GET/POST /api/job-applications → job-applications/ │
│  bonuses/               GET/POST /api/bonuses → bonuses/                   │
│  main_cash/             GET/POST /api/withdrawals → withdrawals/           │
│  data_cleanup/          GET/POST /api/admin/* → (очистка файлов)           │
│  kpi/                   (только Flutter, вычисляется из efficiency)         │
│  ai_training/           POST /api/z-report-* + /api/cigarette-vision/*     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## 12.2 Потоки push-уведомлений

```
8 Schedulers (каждые 5 мин) ──┐
                               ├──→ Firebase FCM ──→ Сотрудник (штраф/напоминание)
API endpoints (POST confirm) ──┤                 ──→ Админ (новый отчёт на проверку)
                               ├──→ WebSocket ────→ Чат real-time
Client broadcast ──────────────┘
```

---

# 13. РЕЗУЛЬТАТЫ АУДИТА 09.02.2026

## 13.1 Сводка

| Метрика | Значение |
|---------|----------|
| 🔴 Критических проблем | 12 |
| 🟠 Важных проблем | 24 |
| 🟡 Рекомендаций | 31 |
| ✅ Модулей без проблем | 22 / 35 |
| flutter analyze | 0 ошибок, 45 warnings, 135 infos |

## 13.2 Цепочки данных (35 модулей)

| Модуль | URL | Модель | Сохранение | Push | Проблемы |
|--------|-----|--------|------------|------|----------|
| auth | ⚠️ 7/8 | ⚠️ | ✅ | N/A | 🔴 refresh-session не существует |
| employees | ✅ | ✅ | ⚠️ | N/A | Flutter не отправляет position/department/email |
| shops | ✅ | ⚠️ | ✅ | N/A | Flutter игнорирует поле icon |
| attendance | ✅ | ✅ | ✅ | ✅ | ✅ |
| work_schedule | ✅ | ✅ | ✅ | ✅ | ✅ |
| shifts | ✅ | ✅ | ✅ | ✅ | ✅ |
| shift_handover | ✅ | ✅ | ✅ | ✅ | ✅ |
| recount | ✅ | ✅ | ✅ | ✅ | Сервер маскирует ошибки (пустой массив вместо 500) |
| envelope | ✅ | ✅ | ✅ | ✅ | 🟠 pending/failed bare JSON array |
| rko | ✅ | ✅ | ✅ | N/A | ✅ |
| coffee_machine | ✅ | ✅ | ✅ | ✅ | 🟠 pending/failed bare JSON array |
| main_cash | ✅ | ✅ | ✅ | ✅ | ✅ |
| bonuses | ✅ | ✅ | ✅ | N/A | ✅ |
| efficiency | ✅ | ✅ | ✅ | N/A | ✅ |
| kpi | N/A | ✅ | N/A | N/A | мёртвый kpiEndpoint |
| clients | ✅ | ⚠️ | ✅ | ✅ | 🔴 broadcast body mismatch |
| loyalty | ✅ | ✅ | ✅ | N/A | ✅ |
| loyalty_gamification | ✅ | ✅ | ✅ | ✅ | ✅ |
| fortune_wheel | ✅ | ✅ | ✅ | N/A | ✅ |
| referrals | ✅ | ✅ | ✅ | N/A | deprecated ReferralSettings |
| reviews | ✅ | ✅ | ✅ | ✅ | 🟠 markMessageAsRead → 404 |
| orders | ⚠️ | ⚠️ | ✅ | ⚠️ | raw Map, нет push |
| training | ⚠️ | ✅ | ✅ | N/A | Нет admin check на сервере |
| tests | ✅ | ✅ | ✅ | N/A | ✅ |
| tasks | ⚠️ | ✅ | ✅ | ✅ | getEmployeePhoneById сканирует всех |
| product_questions | ⚠️ | ✅ | ✅ | ✅ | calculateProductSearchPoints ошибка полей |
| recipes | ✅ | ✅ | ✅ | N/A | ✅ |
| ai_training | — | — | — | N/A | В разработке |
| employee_chat | ⚠️ | ✅ | ✅ | WS | Нет auth на сервере |
| menu | ✅ | ✅ | ✅ | N/A | MenuService мёртвый код |
| suppliers | ⚠️ | ✅ | ✅ | N/A | getNextReferralCode → 500 |
| job_application | ⚠️ | ✅ | ✅ | N/A | Нет auth на PATCH |
| data_cleanup | ⚠️ | ✅ | ✅ | N/A | execSync, нет auth |
| coffee_machine | ✅ | ✅ | ✅ | ✅ | ✅ (backend ОК) |
| shift_transfers | ✅ | ✅ | ✅ | ✅ | ✅ |

## 13.3 Schedulers

| # | Scheduler | Время | Штраф | Надёжность | Проблема |
|---|-----------|-------|-------|------------|----------|
| 1 | shift | UTC+3 ✅ | -3 | Robust | 🟡 Зависимость от TZ сервера |
| 2 | recount | UTC+3 ✅ | -3 | Robust | 🟡 Читает ВСЕ файлы отчётов |
| 3 | rko | UTC+3 ✅ | -3 | Robust | 🟡 metadata читается N раз |
| 4 | shift_handover | UTC+3 ✅ | -3 | Robust | 🟠 `getHours()` вместо Moscow |
| 5 | attendance | UTC+3 ✅ | -2 | Robust | 🟡 Hour overflow (23+3=26) |
| 6 | envelope | UTC+3 ✅ | -5 | Moderate | 🟠 5-мин окно генерации |
| 7 | coffee_machine | UTC+3 ✅ | -3 | Moderate | 🟠 5-мин окно генерации |
| 8 | product_questions | ❌ LOCAL | -1 | Robust | 🔴 `getHours()` = LOCAL time! |

## 13.4 Влияние на Fortune Wheel

| Категория | Статус | Учитывается |
|-----------|--------|-------------|
| shifts | ✅ Работает | Да |
| recount | ✅ Работает | Да |
| envelope | ❌ Не загружается | Нет |
| attendance | ✅ Работает | Да |
| reviews | ❌ Неправильное поле | Нет |
| rko | ✅ Работает | Да |
| orders | ❌ Неправильная структура | Нет |
| productSearch | ❌ Неправильные поля | Нет |
| tests | ✅ Работает | Да |
| tasks | ❌ Баллы не записываются | Нет |

**Результат:** Рейтинг считается по 5 из 10 категорий — несправедливо для сотрудников.

## 13.5 Масштабируемость

| # | Проблема | Уровень | При 100 магазинах |
|---|----------|---------|-------------------|
| 1 | Файловая система как БД | 🔴 | ~5 сек на список, блокировка event loop |
| 2 | Нет кэширования employees/shops | 🟠 | Тысячи лишних чтений/мин |
| 3 | 197 writeFile без блокировки | 🔴 | Гарантированная порча данных |
| 4 | Нет автоматической очистки | 🟠 | 500K+ файлов через 12 месяцев |
| 5 | 2GB RAM + 2GB swap | 🟠 | OOM при batch efficiency |
| 6 | 8 schedulers × 5 мин одновременно | 🟡 | ~800 файл.операций/5мин |
| 7 | WebSocket broadcast O(N) | 🟡 | O(N²) distribution |
| 8 | Upload 10-20MB без проверки | 🟡 | Диск заполнится |

## 13.6 Производительность (Backend)

| # | Уровень | Файл | Описание |
|---|---------|------|----------|
| B-1 | 🔴 | `admin_cache.js:80-103` | Sync I/O при cache miss блокирует event loop |
| B-6 | 🔴 | `efficiency_calc.js:301-826` | ~6500 файловых чтений на single-employee |
| B-7 | 🟠 | `efficiency_calc.js:1077` | Batch cache не покрывает 4 категории |
| B-9 | 🟠 | `tasks_api.js:54-77` | getEmployeePhoneById сканирует ВСЕХ |
| B-10 | 🟠 | `clients_api.js:571` | Broadcast пишет по 1 файлу (100 = 10 сек) |
| B-11 | 🔴 | 15+ API файлов | Нет пагинации — ВСЕ записи |
| B-12 | 🟠 | `pending_api.js:511` | generateDailyPendingShifts на КАЖДОМ GET |
| B-13 | 🟠 | `shifts_api.js:298` | PUT сканирует ВСЕ daily файлы |

## 13.7 Производительность (Flutter)

| # | Уровень | Описание |
|---|---------|----------|
| F-1 | 🟠 | 200+ setState перестраивают целые страницы |
| F-3 | 🟠 | Sort/filter в build() — пересчёт на каждом rebuild |
| F-4 | 🔴 | Нет lazy loading — грузит ВСЕ данные сразу |
| F-5 | 🟠 | 30+ Image.network без кэширования |
| F-6 | 🟠 | Нет сжатия фото при загрузке (3-10MB) |
| F-7 | 🟠 | MainMenuPage — 10+ API вызовов одновременно |
| F-8 | 🟠 | MyEfficiencyPage — 5-7 последовательных вызовов |

## 13.8 Критические потоки

| Поток | Статус | Проблемы |
|-------|--------|----------|
| 1. Регистрация → PIN → Вход | ⚠️ | refresh-session не существует |
| 2. Пересменка → Фото → Отправить | ✅ | Работает |
| 3. Пересчёт → Заполнить → Штраф | ✅ | Работает |
| 4. Клиент → Бонусы → QR | ✅ | Работает |
| 5. Задача → Выполнить → Баллы | ⚠️ | Баллы не записываются при approve |
| 6. Расписание → Авто → Публикация | ✅ | Работает |
| 7. Кофемашина → OCR → Отчёт | ✅ | Работает |
| 8. Эффективность → KPI → Рейтинг | ⚠️ | 5 из 10 категорий не работают |

## 13.9 Нагрузочные тесты

Созданы в `loyalty-proxy/tests/`:
- **`load-test.js`** — 5 сценариев: 50 параллельных GET employees, 50 GET shift-reports, 20 POST attendance, 10 GET efficiency batch, 30 WebSocket connections. Метрики: min/avg/max/p95, throughput, errors. Запуск: `SESSION_TOKEN=xxx node tests/load-test.js`
- **`smoke-test.js`** — 73 GET + 13 POST endpoints. Классификация: OK/BROKEN/ERROR. Сохранение в JSON. Запуск: `SESSION_TOKEN=xxx node tests/smoke-test.js`

---

# 14. ГЛОССАРИЙ

## Термины приложения

| Термин | Определение |
|--------|-------------|
| **Пересменка (Shift)** | Ежедневная проверка знаний сотрудника в начале смены |
| **Пересчёт (Recount)** | Инвентаризация товара (утренняя и вечерняя) |
| **Сдача смены (Shift Handover)** | Передача смены следующему сотруднику с фото-отчётом |
| **РКО** | Расходный кассовый ордер - документ о движении денег |
| **Конверт (Envelope)** | Инкассация наличных в конце смены |
| **Эффективность** | Числовой показатель работы сотрудника (сумма 12 категорий) |
| **Pending** | Ожидающий отчёт, требующий действия сотрудника |
| **Failed** | Просроченный отчёт (штраф начислен автоматически) |
| **Review** | Отчёт на проверке у админа |
| **Confirmed** | Подтверждённый отчёт с рейтингом |
| **Колесо удачи** | Геймификация: топ-3 сотрудника могут крутить колесо с призами |

## Технические термины

| Термин | Определение |
|--------|-------------|
| **Scheduler** | Автоматическая задача, выполняемая по расписанию |
| **Pending report** | Файл, ожидающий действия (отметки, отчёта) |
| **Deadline** | Крайний срок выполнения действия |
| **Interpolation** | Линейная интерполяция для расчёта баллов по рейтингу |
| **zeroThreshold** | Порог рейтинга, при котором баллы = 0 |
| **FCM Token** | Токен Firebase для push-уведомлений |
| **Geofencing** | Определение нахождения в радиусе магазина по GPS |
| **Batch processing** | Обработка данных пакетами (оптимизация) |

## Роли пользователей

| Роль | Описание |
|------|----------|
| **Client** | Клиент кофейни (заказы, лояльность, отзывы) |
| **Employee** | Сотрудник (бариста) - отметки, отчёты, задачи |
| **Manager** | Менеджер группы магазинов - контроль сотрудников |
| **Store Manager** | Старший менеджер точки - расширенный контроль |
| **Admin** | Администратор сети - полный контроль |
| **Developer** | Разработчик - технический доступ ко всему |

## Сокращения

| Сокращение | Расшифровка |
|------------|-------------|
| API | Application Programming Interface |
| FCM | Firebase Cloud Messaging |
| OTP | One-Time Password (одноразовый пароль) |
| PIN | Personal Identification Number |
| CRUD | Create, Read, Update, Delete |
| JSON | JavaScript Object Notation |
| JWT | JSON Web Token |
| GPS | Global Positioning System |
| UI/UX | User Interface / User Experience |
| CI/CD | Continuous Integration / Continuous Deployment |

---

**Конец документации**

*Последнее обновление: 2026-02-09*
*Автор: Claude Code*
*Версия: 2.4.0 (после полного аудита 09.02.2026: безопасность + цепочки данных + schedulers + масштабируемость + производительность + flutter analyze)*


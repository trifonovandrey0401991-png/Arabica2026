# Arabica 2026 - Architecture Documentation

## Overview

Flutter мобильное приложение для управления сетью кофеен с Node.js бэкендом.

- **Frontend:** Flutter (Dart)
- **Backend:** Node.js + Express
- **Database:** Firebase Realtime Database
- **Notifications:** Firebase Cloud Messaging
- **AI/ML:** Google Cloud Vision API

---

## Project Structure

```
arabica2026/
├── lib/                          # Flutter приложение
│   ├── main.dart                 # Точка входа
│   ├── app/pages/                # Главные страницы (меню, отчёты)
│   ├── core/                     # Ядро приложения
│   │   ├── constants/            # API endpoints, константы
│   │   ├── services/             # BaseHttpService, Firebase, Notifications
│   │   ├── utils/                # Logger, DateFormatter, ErrorHandler
│   │   └── widgets/              # Общие виджеты
│   ├── shared/                   # Общие компоненты
│   │   ├── dialogs/              # Переиспользуемые диалоги
│   │   ├── models/               # Общие модели
│   │   ├── providers/            # CartProvider, OrderProvider
│   │   └── widgets/              # Переиспользуемые виджеты
│   └── features/                 # 30 feature-модулей
└── loyalty-proxy/                # Node.js сервер
    ├── index.js                  # Главный сервер (~6.7K строк)
    ├── modules/                  # Специализированные модули
    │   ├── orders.js
    │   ├── z-report-vision.js    # AI распознавание
    │   └── cigarette-vision.js   # AI распознавание
    └── api/                      # Отдельные API модули
```

---

## Feature Module Architecture

Каждый feature следует единой структуре:

```
feature/
├── models/           # Data classes с fromJson/toJson
├── services/         # Бизнес-логика, API запросы
├── pages/            # UI страницы и диалоги
├── widgets/          # (опционально) Кастомные виджеты
└── utils/            # (опционально) Утилиты
```

### Принципы разделения:

| Слой | Ответственность |
|------|-----------------|
| **models/** | Только структуры данных, сериализация JSON |
| **services/** | Вся бизнес-логика, API через BaseHttpService |
| **pages/** | Только UI, получает данные от services |

---

## Core Services

### BaseHttpService
Центральный сервис для всех API запросов:

```dart
// Получить список
BaseHttpService.getList<T>(endpoint, fromJson, listKey)

// Получить один элемент
BaseHttpService.get<T>(endpoint, fromJson)

// Создать
BaseHttpService.post<T>(endpoint, body, fromJson)

// Обновить
BaseHttpService.put<T>(endpoint, body, fromJson)

// Удалить
BaseHttpService.delete(endpoint)
```

### ApiConstants
Все API endpoints и таймауты:
- Base URL: `https://arabica26.ru`
- Таймауты: 10s (short), 15s (default), 30s (long), 120s (upload)
- 90+ endpoints для всех features

---

## Features List (30 модулей)

### Core Features
| Feature | Описание | API Endpoint |
|---------|----------|--------------|
| **orders** | Заказы, корзина | `/api/orders` |
| **menu** | Меню продуктов | `/api/menu` |
| **shops** | Управление магазинами | `/api/shops` |
| **employees** | Сотрудники, регистрация | `/api/employees` |
| **work_schedule** | График работы | `/api/work-schedule` |
| **loyalty** | Программа лояльности | `/api/loyalty-promo` |

### Report Features (Системы отчётности)
| Feature | Описание | API Endpoint |
|---------|----------|--------------|
| **shifts** | Пересменки (4 вкладки) | `/api/shift-reports` |
| **recount** | Пересчёты (4 вкладки) | `/api/recount-reports` |
| **envelope** | Конверты (денежные отчёты) | `/api/envelope-reports` |
| **shift_handover** | Передача смены | `/api/shift-handover-reports` |
| **rko** | Кассовые отчёты | `/api/rko` |
| **attendance** | Посещаемость | `/api/attendance` |

### Quality & Analytics
| Feature | Описание | API Endpoint |
|---------|----------|--------------|
| **kpi** | KPI по магазинам/сотрудникам | `/api/kpi` |
| **efficiency** | Баллы эффективности (14 источников) | `/api/efficiency` |
| **rating** | Рейтинг сотрудников | `/api/ratings` |

### Education
| Feature | Описание | API Endpoint |
|---------|----------|--------------|
| **training** | Статьи обучения | `/api/training-articles` |
| **ai_training** | Машинное зрение (IN DEV) | `/api/z-report-vision` |
| **tests** | Тесты для сотрудников | `/api/test-questions` |

### Communication
| Feature | Описание | API Endpoint |
|---------|----------|--------------|
| **reviews** | Отзывы клиентов | `/api/reviews` |
| **product_questions** | Вопросы о продуктах | `/api/product-questions` |
| **employee_chat** | Чат между сотрудниками | `/api/employee-chats` |
| **clients** | Клиентская база, диалоги | `/api/clients` |

### Management & Gamification
| Feature | Описание | API Endpoint |
|---------|----------|--------------|
| **tasks** | Задачи (обычные и повторяющиеся) | `/api/tasks` |
| **fortune_wheel** | Колесо фортуны | `/api/fortune-wheel` |
| **bonuses** | Бонусы и штрафы | `/api/bonus-penalties` |
| **referrals** | Реферальная система | `/api/referrals` |

### Additional
| Feature | Описание |
|---------|----------|
| **main_cash** | Главная касса (выемки) |
| **recipes** | Рецепты |
| **job_application** | Заявки на работу |
| **suppliers** | Поставщики |
| **data_cleanup** | Очистка данных |

---

## Data Flow

### Создание отчёта:
```
User → Page.onSubmit() → Service.save() → BaseHttpService.post()
→ Server (index.js) → Firebase RTDB → FCM Notification → Response
→ Local Cache → UI Refresh
```

### Получение списка:
```
Page.initState() → Service.getList() → BaseHttpService.getList()
→ GET /api/endpoint → Server → Firebase Query → Response
→ JSON → List<Model> → UI Build
```

---

## Efficiency System Integration

Система Efficiency агрегирует данные из 14 features:

```
┌─────────────────────────────────────────────────┐
│              Efficiency Service                  │
├─────────────────────────────────────────────────┤
│ Источники:                                       │
│ • Attendance    • Shifts      • Recount         │
│ • RKO           • Envelope    • Shift Handover  │
│ • Tests         • Reviews     • Product Search  │
│ • Orders        • Tasks       • Rating          │
│ • Referrals     • Fortune Wheel                 │
├─────────────────────────────────────────────────┤
│ Результат:                                       │
│ • Баллы сотрудника                              │
│ • Рейтинг магазина                              │
│ • Отчёты эффективности                          │
└─────────────────────────────────────────────────┘
```

---

## Server Architecture (loyalty-proxy/)

### index.js (~6.7K строк)
- Express с CORS, helmet, rate limiting
- Firebase Admin SDK
- Основные CRUD endpoints

### modules/
- `orders.js` - логика заказов
- `z-report-vision.js` - AI распознавание Z-отчётов
- `cigarette-vision.js` - AI распознавание сигарет

### api/
Отдельные модули для сложных features:
- `clients_api.js`, `tasks_api.js`, `points_settings_api.js`
- `recurring_tasks_api.js`, `referrals_api.js`
- `report_notifications_api.js`

### Python Scripts
- `rko_docx_processor.py` - обработка DOCX
- `rko_pdf_generator.py` - генерация PDF

---

## Protected Code

**НЕ ИЗМЕНЯТЬ без разрешения** (см. LOCKED_CODE.md):
- Все features кроме `ai_training`
- Серверный код кроме `modules/z-report-vision.js`

**Можно изменять:**
- `lib/features/ai_training/` - машинное зрение
- `loyalty-proxy/modules/z-report-vision.js`

---

## Deployment

### Сервер: arabica26.ru

```bash
# Деплой
ssh root@arabica26.ru "cd /root/arabica_app && git pull origin refactoring/full-restructure"
ssh root@arabica26.ru "pm2 restart loyalty-proxy"

# Логи
ssh root@arabica26.ru "pm2 logs loyalty-proxy --lines 50"
```

### Flutter Build

```bash
flutter clean
flutter pub get
flutter build apk --debug
flutter install --debug
```

---

## Key Files for Context

При работе с Claude рекомендуется предоставить:

```
# Обязательно
CLAUDE.md
ARCHITECTURE.md

# Core
lib/core/constants/api_constants.dart
lib/core/services/base_http_service.dart

# Для конкретного feature - его models/, services/, pages/
```

---

## Statistics

| Метрика | Значение |
|---------|----------|
| Dart файлов | 346 |
| Features | 30 |
| API endpoints | 90+ |
| Серверный код | ~14.5K строк |
| index.js | ~6.7K строк |

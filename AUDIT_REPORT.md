# ПОЛНЫЙ АУДИТ СИСТЕМЫ ARABICA
## Дата: 06.01.2026
## Аналитик: Claude AI (30-летний опыт IT)

---

# КРИТИЧЕСКИЕ ПРОБЛЕМЫ

## 1. ОТСУТСТВУЮЩИЕ API ENDPOINTS НА СЕРВЕРЕ

Приложение Flutter ожидает следующие API endpoints, которые **НЕ СУЩЕСТВУЮТ** на сервере:

| Endpoint в приложении | Статус на сервере | Данные на сервере |
|----------------------|-------------------|-------------------|
| `/api/envelope-reports` | **ОТСУТСТВУЕТ** | Есть: `/var/www/envelope-reports/` (9 файлов) |
| `/api/suppliers` | **ОТСУТСТВУЕТ** | Есть: `/var/www/suppliers/` (6 файлов) |
| `/api/shift-reports` | **ОТСУТСТВУЕТ** | Есть: `/var/www/shift-reports/` (файлы есть) |
| `/api/shift-handover-reports` | **ОТСУТСТВУЕТ** | Есть: `/var/www/shift-handover-reports/` (5 файлов) |
| `/api/orders` | **НЕ ПРОВЕРЕНО** | Есть: `/var/www/orders/` |
| `/api/shift-transfers` | **НЕ ПРОВЕРЕНО** | Есть: `/var/www/shift-transfers.json` |
| `/api/pending-recount-reports` | **НЕ ПРОВЕРЕНО** | Есть: `/var/www/pending-recount-reports/` |
| `/api/pending-shift-reports` | **НЕ ПРОВЕРЕНО** | Есть: `/var/www/pending-shift-reports/` |
| `/api/pending-shift-handover-reports` | **НЕ ПРОВЕРЕНО** | Есть: файл |
| `/api/training-articles` | **НЕ ПРОВЕРЕНО** | Есть: `/var/www/training-articles/` |
| `/api/product-questions` | **НЕ ПРОВЕРЕНО** | Есть: `/var/www/product-questions/` |
| `/api/client-dialogs` | **НЕ ПРОВЕРЕНО** | Есть: `/var/www/client-dialogs/` |

### ПОСЛЕДСТВИЯ:
- **Поставщики**: Кнопка есть в приложении, но данные не загружаются (сервер возвращает 404)
- **Конверты**: Данные сохраняются на сервере, но не читаются обратно
- **Отчеты пересменки/сдачи смены**: Данные есть, но приложение не может их загрузить

---

## 2. API ENDPOINTS КОТОРЫЕ ЕСТЬ НА СЕРВЕРЕ

```
/api/attendance (GET, POST)
/api/attendance/check (GET)
/api/employee-registration (POST)
/api/employee-registration/:phone (GET)
/api/employee-registration/:phone/verify (POST)
/api/employee-registrations (GET)
/api/recount-questions (GET, POST, PUT, DELETE)
/api/recount-reports (GET, POST)
/api/recount-reports/:reportId/rating (POST)
/api/recount-reports/:reportId/notify (POST)
/api/rko/* (несколько endpoints)
/api/shift-handover-questions (GET, POST, PUT, DELETE)
/api/shift-questions (GET, POST, PUT, DELETE)
/api/shop-settings (GET, POST)
/api/test-questions (GET, POST, PUT, DELETE)
/api/test-results (GET, POST)
/api/withdrawals (GET, POST, DELETE) - из withdrawals_api.js
/api/work-schedule/* (несколько endpoints)
```

---

## 3. ДУБЛИРОВАНИЕ И МУСОР НА СЕРВЕРЕ

### Backup файлы в корне проекта:
```
/root/loyalty-proxy/index.js.backup-20251229-150738 (255KB)
/root/loyalty-proxy/index.js.backup_20251228_203858 (251KB)
/root/loyalty-proxy/index.js.backup_20251229_030630 (252KB)
/root/loyalty-proxy/index.js.backup_shift_handover_20251229_220925 (260KB)
```

### Неиспользуемые .md файлы (более 70 файлов):
- ALGORITHM_IMPROVEMENTS.md
- ALGORITHM_VERIFICATION.md
- APPLICATION_LOGIC.md
- BUGFIXES.md
- И множество других...

**Рекомендация:** Очистить или переместить в архив

---

## 4. СТРУКТУРА ПАПОК ДАННЫХ НА СЕРВЕРЕ

```
/var/www/
├── app-logs/
├── attendance/               # Используется
├── chat-media/
├── client-dialogs/           # API не проверен
├── client-messages/
├── client-messages-management/
├── client-messages-network/
├── clients/
├── employee-photos/          # Используется
├── employee-registrations/   # Используется
├── employees/
├── envelope-questions/       # API есть
├── envelope-reports/         # API ОТСУТСТВУЕТ!
├── fcm-tokens/
├── menu/
├── orders/                   # API не проверен
├── pending-recount-reports/
├── pending-shift-handover-reports.json
├── pending-shift-reports/
├── product-question-dialogs/
├── product-question-photos/
├── product-questions/
├── recipe-photos/
├── recipes/
├── recount-questions/        # API есть
├── recount-reports/          # API есть
├── reviews/
├── rko-reports/             # API есть
├── shift-handover-question-photos/
├── shift-handover-questions/ # API есть
├── shift-handover-reports/   # API ОТСУТСТВУЕТ!
├── shift-photos/
├── shift-question-photos/
├── shift-questions/          # API есть
├── shift-reference-photos/
├── shift-reports/            # API ОТСУТСТВУЕТ!
├── shift-transfers.json
├── shop-coordinates/
├── shop-settings/            # API есть
├── shop-settings-photos/
├── shops/
├── suppliers/                # API ОТСУТСТВУЕТ!
├── suppliers.json            # Дубликат?
├── test-questions/           # API есть
├── test-results/             # API есть
├── training-articles/        # API не проверен
├── withdrawals/              # API есть
├── work-schedule-templates/
└── work-schedules/           # API есть
```

---

## 5. ДУБЛИРОВАНИЕ В ПРИЛОЖЕНИИ FLUTTER

### Похожие сервисы:
- `shift_report_service.dart` (Пересменка)
- `shift_handover_report_service.dart` (Сдача смены)
- Оба имеют практически идентичную структуру

### Pending сервисы:
- `pending_shift_service.dart`
- `pending_shift_report_model.dart`
- `pending_recount_service.dart`
- `pending_recount_report_model.dart`

**Вопрос:** Нужны ли отдельные pending модели или можно использовать основные?

---

## 6. СЕРВЕРНЫЙ ФАЙЛ index.js

- **Размер:** 2802 строки (104KB)
- **Количество endpoints:** 67
- **Модульность:** Только `withdrawals_api.js` вынесен отдельно

### Проблемы:
1. Слишком большой файл - сложно поддерживать
2. Нет разделения на модули (кроме withdrawals)
3. Много повторяющегося кода для CRUD операций

---

## 7. ПОТЕНЦИАЛЬНЫЕ БАГИ

### 7.1 Санитизация имен файлов
```javascript
const sanitizedId = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
```
Используется повсеместно, но может привести к коллизиям если два разных ID преобразуются в одинаковый sanitized ID.

### 7.2 Отсутствие транзакций
Все операции с файлами не атомарны. При сбое в середине операции данные могут быть повреждены.

### 7.3 Отсутствие валидации
Многие endpoints не проверяют входные данные полностью.

### 7.4 Hardcoded пути
```javascript
const uploadDir = '/var/www/shift-photos';
```
Пути захардкожены, нет конфигурации.

---

## 8. ТОЧКИ УЛУЧШЕНИЯ

### Высокий приоритет:
1. **Добавить недостающие API endpoints:**
   - `/api/envelope-reports` (CRUD)
   - `/api/suppliers` (CRUD)
   - `/api/shift-reports` (CRUD)
   - `/api/shift-handover-reports` (CRUD)

2. **Модуляризация сервера:**
   - Вынести каждую группу endpoints в отдельный файл
   - Создать общий CRUD-генератор

### Средний приоритет:
3. **Очистка:**
   - Удалить неиспользуемые backup файлы
   - Удалить или переместить .md файлы

4. **Конфигурация:**
   - Вынести пути в переменные окружения
   - Создать config.js

### Низкий приоритет:
5. **Логирование:**
   - Добавить структурированное логирование
   - Ротация логов

6. **Тестирование:**
   - Добавить unit-тесты для API

---

## 9. ПРОЦЕССЫ PM2

```
┌────┬──────────────────┬─────────┬────────┬──────┬───────────┐
│ id │ name             │ mode    │ uptime │ ↺    │ status    │
├────┼──────────────────┼─────────┼────────┼──────┼───────────┤
│ 0  │ loyalty-proxy    │ fork    │ 6h     │ 20   │ online    │
└────┴──────────────────┴─────────┴────────┴──────┴───────────┘
```

- Сервер работает стабильно
- 20 рестартов - возможно были ошибки ранее

---

## 10. РЕКОМЕНДАЦИИ ПО ПОРЯДКУ ИСПРАВЛЕНИЯ

### Фаза 1: Критические исправления (сделать первыми)
1. Добавить `/api/suppliers` endpoints на сервер
2. Добавить `/api/envelope-reports` endpoints на сервер
3. Добавить `/api/shift-reports` endpoints на сервер
4. Добавить `/api/shift-handover-reports` endpoints на сервер

### Фаза 2: Стабилизация
5. Проверить и добавить остальные отсутствующие endpoints
6. Протестировать все функции приложения

### Фаза 3: Оптимизация
7. Модуляризация серверного кода
8. Очистка мусора
9. Добавление конфигурации

---

## ЗАКЛЮЧЕНИЕ

Основная проблема системы - **рассинхронизация между Flutter приложением и сервером**.
Приложение ожидает множество API endpoints, которые не существуют на сервере.
Данные сохраняются на сервере (файлы создаются), но не могут быть прочитаны обратно из-за отсутствия GET endpoints.

**Критичность:** ВЫСОКАЯ
**Оценка времени на исправление:** 4-8 часов для базовых endpoints

---

*Отчет сформирован: 06.01.2026*

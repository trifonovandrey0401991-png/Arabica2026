# 🚀 АУДИТ ПЕРЕД РЕЛИЗОМ - ARABICA 2026

**Дата аудита:** 31 января 2026
**Версия:** v2.0.0-major-update
**Аудитор:** Claude Opus 4.5

---

## 📊 ОБЩАЯ ОЦЕНКА

| Категория | Оценка | Статус |
|-----------|--------|--------|
| Архитектура | 8/10 | ✅ Хорошо |
| Безопасность | 2/10 | 🔴 КРИТИЧНО |
| Стабильность кода | 6/10 | 🟡 Средне |
| Оптимизация | 7/10 | ✅ Хорошо |
| Production Readiness | 5/10 | 🟡 Частично |

---

## ⚠️ КРИТИЧНЫЕ ПРОБЛЕМЫ (BLOCKER - исправить ДО релиза)

### 🔴 SECURITY-001: Захардкоженные секреты в коде

**Файлы:**
- `loyalty-proxy/index.js:264` - Google Apps Script URL
- `android/app/google-services.json:18` - Firebase API Key
- `ios/GoogleService-Info.plist:6` - Firebase API Key
- `dbf-sync-agent/config.json:6` - Sync API Key

**Риск:** Полный доступ к backend API, Firebase, синхронизации данных

**Решение:**
```bash
# 1. Ротировать все ключи
# 2. Использовать переменные окружения
SCRIPT_URL=xxx node index.js

# 3. Добавить в .gitignore:
google-services.json
GoogleService-Info.plist
*service-account*.json
config.json
```

---

### 🔴 SECURITY-002: Нет аутентификации на API

**Проблема:** ВСЕ 100+ endpoints доступны без авторизации

**Затронуто:**
- `GET /api/employees` - список всех сотрудников с паролями
- `POST /api/employees` - создание сотрудника с isAdmin=true
- `GET /api/clients` - все данные клиентов
- `DELETE /api/*` - удаление любых данных

**Риск:** Любой может получить/изменить/удалить все данные

**Решение (минимум):**
```javascript
// Добавить в index.js
const authMiddleware = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  if (!apiKey || !validApiKeys.includes(apiKey)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
};

app.use('/api', authMiddleware);
```

---

### 🔴 SECURITY-003: Path Traversal уязвимости (11 endpoints)

**Файл:** `loyalty-proxy/index.js`

**Уязвимые endpoints:**
| Endpoint | Строка | Риск |
|----------|--------|------|
| `PUT /api/training-articles/:id` | 6249 | Запись любых файлов |
| `DELETE /api/training-articles/:id` | 6274 | Удаление любых файлов |
| `PUT /api/test-questions/:id` | 6411 | Запись любых файлов |
| `DELETE /api/test-questions/:id` | 6432 | Удаление любых файлов |
| `GET /api/reviews/:id` | 6684 | Чтение любых файлов |
| `GET /api/recipes/:id` | 6842 | Чтение любых файлов |
| И ещё 5 endpoints... | | |

**Пример атаки:**
```bash
curl "https://arabica26.ru/api/reviews/../../../../etc/passwd"
```

**Решение:**
```javascript
// Добавить санитизацию ВСЕХ параметров
const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
const filePath = path.join(DIR, `${sanitizedId}.json`);

// Проверка что путь в пределах директории
const realPath = fs.realpathSync(filePath);
if (!realPath.startsWith(DIR)) {
  throw new Error('Path traversal detected');
}
```

---

### 🔴 SECURITY-004: CORS разрешает ВСЕ origins

**Файл:** `loyalty-proxy/index.js:122`

```javascript
// ТЕКУЩИЙ КОД (ОПАСНО!)
if (!allowedOrigins.includes(origin)) {
  console.warn(`⚠️ CORS blocked origin: ${origin}`);
  callback(null, true); // ❌ ВСЕГДА РАЗРЕШАЕТ!
}
```

**Риск:** Любой сайт может делать запросы от имени пользователей

**Решение:**
```javascript
// Заменить на:
callback(new Error('Not allowed by CORS'), false);
```

---

### 🔴 SECURITY-005: Загрузка файлов без валидации типа

**Файл:** `loyalty-proxy/index.js:175-194`

**Проблема:** 8 из 9 endpoints загрузки разрешают ЛЮБЫЕ файлы (.exe, .php, .sh)

**Затронутые endpoints:**
- `POST /upload-photo`
- `POST /upload-employee-photo`
- `POST /api/rko/upload`
- И другие...

**Решение:**
```javascript
const upload = multer({
  storage: storage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowedTypes = ['image/jpeg', 'image/png', 'image/gif'];
    if (!allowedTypes.includes(file.mimetype)) {
      return cb(new Error('Invalid file type'));
    }
    cb(null, true);
  }
});
```

---

### 🔴 INFRA-001: Нет graceful shutdown

**Риск:** При перезапуске сервера:
- Scheduler'ы не завершают текущие операции
- Файлы могут записаться частично
- WebSocket соединения обрываются без уведомления

**Решение:**
```javascript
// Добавить в конец index.js
process.on('SIGTERM', async () => {
  console.log('Graceful shutdown started...');
  server.close();
  // Остановить все scheduler'ы
  process.exit(0);
});
```

---

### 🔴 INFRA-002: Нет автоматических бэкапов

**Данные под риском:**
- `/var/www/envelope-reports/` - Финансовые отчёты
- `/var/www/employees/` - Данные сотрудников
- `/var/www/efficiency-penalties/` - Баллы и штрафы
- `/var/www/shift-reports/` - Отчёты о сменах

**Решение:**
```bash
# Добавить в crontab
0 2 * * * tar -czf /backups/arabica_$(date +\%Y\%m\%d).tar.gz /var/www/
```

---

## 🔴 ВЫСОКИЙ ПРИОРИТЕТ (исправить в течение недели после релиза)

### SECURITY-006: Broken Authorization
- Пользователи могут видеть данные других пользователей
- `GET /api/client-dialogs/:phone` - любой телефон
- `GET /api/shift-reports?employeeName=X` - любой сотрудник

### BUG-001: Empty List Crash
**Файл:** `lib/core/services/notification_service.dart:52-55`
```dart
// ПАДАЕТ если orders пустой!
final order = orderProvider.orders.firstWhere(
  (o) => o.id == orderId,
  orElse: () => orderProvider.orders.first, // ❌ CRASH
);
```

### BUG-002: TextEditingController Memory Leak
**Файл:** `lib/core/services/notification_service.dart:235`
- Controller создаётся но не удаляется при закрытии диалога

### BUG-003: WebSocket Connection Loop
**Файл:** `lib/features/employee_chat/services/chat_websocket_service.dart`
- При ошибке подключения бесконечный цикл переподключений
- Ошибка в логах: `WebSocketException: Connection was not upgraded`

### DEP-001: Syncfusion PDF Viewer
- Коммерческая библиотека (+5-10MB к APK)
- Рекомендация: заменить на `pdfx`

---

## 🟡 СРЕДНИЙ ПРИОРИТЕТ (включить в следующий спринт)

### OPT-001: 40+ Debug Print Statements
**Файлы:**
- `lib/features/work_schedule/pages/work_schedule_page.dart` - 30+ print()
- `lib/features/clients/pages/*_dialog_page.dart` - 10+ print()

### OPT-002: Дублированный код _formatDateTime()
- 6 идентичных реализаций в разных файлах
- Рекомендация: создать `lib/core/utils/date_formatter.dart`

### OPT-003: 4 TODO с незавершённой функциональностью
- Push-уведомления клиентам при ответе админа
- Удаление шаблонов расписания
- Навигация по уведомлениям для админов

### INFRA-003: Нет Health Check Endpoint
```javascript
// Добавить:
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date() });
});
```

### INFRA-004: Нет структурированного логирования
- Все логи через console.log()
- Нет ротации логов
- Нет уровней логирования

---

## 🟢 НИЗКИЙ ПРИОРИТЕТ / ТЕХНИЧЕСКИЙ ДОЛГ

### TD-001: Camera package устарел
- Текущий: ^0.10.5+9
- Рекомендуется: ^0.11.0+

### TD-002: iOS icon generation отключён
- `flutter_launcher_icons: ios: false`
- Включить если планируется App Store

### TD-003: Workmanager без обновлений
- Последнее обновление 2023
- Мониторить совместимость с Android 14+

### TD-004: 7 пустых строк в конце файлов
- `lib/core/utils/logger.dart`
- `lib/features/reviews/pages/review_detail_page.dart`

---

## 📊 МЕТРИКИ КАЧЕСТВА

| Метрика | Значение |
|---------|----------|
| Всего Dart файлов | 393 |
| Всего строк кода (Flutter) | 172,373 |
| Всего JS файлов (Server) | 47 |
| Всего строк кода (Server) | 32,499 |
| Количество фич/модулей | 31 |
| Защищённых систем | 28 |
| Критических уязвимостей | 6 |
| Высоких уязвимостей | 4 |
| Debug print() statements | 40+ |
| Дублированного кода | ~200 строк |
| TODO/FIXME комментариев | 4 |

---

## ✅ PRODUCTION READY?

# ❌ НЕТ

**Причины:**

1. **6 КРИТИЧЕСКИХ уязвимостей безопасности** - API полностью открыт, секреты в коде
2. **Нет аутентификации** - любой может удалить все данные
3. **Нет бэкапов** - потеря данных невосстановима
4. **Нет graceful shutdown** - риск потери данных при перезапуске

**Минимум для релиза:**
- [ ] Ротировать все API ключи
- [ ] Добавить базовую API key аутентификацию
- [ ] Исправить Path Traversal (11 endpoints)
- [ ] Исправить CORS конфигурацию
- [ ] Добавить fileFilter для загрузок
- [ ] Настроить ежедневные бэкапы
- [ ] Добавить graceful shutdown
- [ ] Добавить health check endpoint

**Оценочное время:** 2-3 дня интенсивной работы

---

## 🎯 ТОП-10 ТОЧЕК РОСТА (После релиза)

| # | Фича | Impact | Effort | Приоритет |
|---|------|--------|--------|-----------|
| 1 | JWT аутентификация | HIGH | HIGH | P0 |
| 2 | Role-based access control | HIGH | HIGH | P0 |
| 3 | Sentry для error tracking | HIGH | LOW | P1 |
| 4 | Winston/Pino для логирования | MEDIUM | MEDIUM | P1 |
| 5 | Миграция на PostgreSQL | HIGH | VERY HIGH | P2 |
| 6 | Push уведомления клиентам | MEDIUM | MEDIUM | P2 |
| 7 | Offline режим в приложении | MEDIUM | HIGH | P2 |
| 8 | API versioning (/api/v1/) | MEDIUM | LOW | P3 |
| 9 | Rate limiting per user | MEDIUM | MEDIUM | P3 |
| 10 | Автоматические тесты | HIGH | VERY HIGH | P3 |

---

## 📋 CHECKLIST ДЛЯ РЕЛИЗА

### Безопасность
- [ ] Ротировать Google Apps Script URL
- [ ] Ротировать Firebase API keys
- [ ] Ротировать DBF Sync API key
- [ ] Добавить .gitignore для секретов
- [ ] Добавить API key аутентификацию
- [ ] Исправить CORS (line 122)
- [ ] Исправить Path Traversal (11 endpoints)
- [ ] Добавить file type validation

### Инфраструктура
- [ ] Настроить cron для бэкапов
- [ ] Добавить graceful shutdown
- [ ] Добавить health check endpoint
- [ ] Создать PM2 ecosystem.config.js

### Код
- [ ] Исправить Empty List crash (notification_service.dart)
- [ ] Исправить TextEditingController leak
- [ ] Удалить debug print() statements

### Тестирование
- [ ] Проверить все критические flows
- [ ] Тест загрузки файлов
- [ ] Тест работы scheduler'ов
- [ ] Тест WebSocket чата

---

**Отчёт создан:** 31.01.2026
**Рекомендация:** ОТЛОЖИТЬ РЕЛИЗ до исправления критических проблем безопасности

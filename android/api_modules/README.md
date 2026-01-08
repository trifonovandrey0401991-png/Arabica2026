# Arabica API - Modular Architecture v2.0

## Структура файлов

```
api_modules/
├── index.js              # Главный файл сервера (158 строк)
├── api/                  # Папка с модулями API
│   ├── recount_api.js    # Пересчеты и вопросы пересчета
│   ├── attendance_api.js # Посещаемость
│   ├── employees_api.js  # Сотрудники и регистрация
│   ├── shops_api.js      # Магазины и настройки
│   ├── shifts_api.js     # Отчеты смен и вопросы
│   ├── clients_api.js    # Клиенты и диалоги
│   ├── work_schedule_api.js # График работы
│   ├── rko_api.js        # РКО отчеты
│   ├── training_api.js   # Обучающие статьи
│   ├── tests_api.js      # Тесты и результаты
│   ├── recipes_api.js    # Рецепты
│   ├── menu_api.js       # Меню
│   ├── orders_api.js     # Заказы и FCM токены
│   ├── product_questions_api.js # Вопросы о продуктах
│   ├── reviews_api.js    # Отзывы
│   ├── media_api.js      # Медиафайлы и логи
│   ├── loyalty_api.js    # Система лояльности
│   ├── suppliers_api.js  # Поставщики
│   ├── envelope_api.js   # Сдача смены (конверты)
│   └── withdrawals_api.js # Выемки
└── README.md
```

## Развертывание на сервере

### 1. Подключение к серверу
```bash
ssh root@167.86.89.229
```

### 2. Создание backup
```bash
cd /root/arabica_app/loyalty-proxy
cp index.js index.js.backup_$(date +%Y%m%d_%H%M%S)
```

### 3. Создание папки api
```bash
mkdir -p /root/arabica_app/loyalty-proxy/api
```

### 4. Загрузка файлов (с локальной машины)
```bash
# Загрузка главного файла
scp c:/Users/Admin/arabica2026/android/api_modules/index.js root@167.86.89.229:/root/arabica_app/loyalty-proxy/index_new.js

# Загрузка модулей
scp c:/Users/Admin/arabica2026/android/api_modules/api/*.js root@167.86.89.229:/root/arabica_app/loyalty-proxy/api/
```

### 5. Проверка синтаксиса
```bash
ssh root@167.86.89.229 "cd /root/arabica_app/loyalty-proxy && node -c index_new.js"
```

### 6. Замена и перезапуск
```bash
ssh root@167.86.89.229 "cd /root/arabica_app/loyalty-proxy && mv index_new.js index.js && pm2 restart loyalty-proxy && pm2 logs --lines 20"
```

## Преимущества модульной архитектуры

1. **Читаемость** - Каждый модуль отвечает за свою область
2. **Поддержка** - Легко найти и исправить код
3. **Тестирование** - Можно тестировать модули отдельно
4. **Масштабируемость** - Просто добавить новые модули

## Сравнение

| Параметр | Старая версия | Новая версия |
|----------|---------------|--------------|
| Размер index.js | 5800+ строк | 158 строк |
| Количество файлов | 1 | 21 |
| Модульность | Нет | Да |
| Версия | 1.x | 2.0.0 |

## API Endpoints по модулям

### recount_api.js
- GET/POST `/api/recount-reports`
- POST `/api/recount-reports/:id/rating`
- POST `/api/recount-reports/:id/notify`
- GET/POST/PUT/DELETE `/api/recount-questions`

### attendance_api.js
- GET/POST `/api/attendance`
- GET `/api/attendance/check`

### employees_api.js
- POST/GET `/api/employee-registration`
- GET `/api/employee-registrations`
- GET/POST/PUT/DELETE `/api/employees`

### shifts_api.js
- GET/POST/PUT `/api/shift-reports`
- GET/POST/PUT/DELETE `/api/shift-questions`
- GET/POST/DELETE `/api/shift-handover-reports`
- GET/POST/PUT/DELETE `/api/shift-handover-questions`

### clients_api.js
- GET/POST `/api/clients`
- GET `/api/client-dialogs/:phone`
- Сетевые и управленческие сообщения

### И другие...

## Откат

Если что-то пошло не так:
```bash
ssh root@167.86.89.229 "cd /root/arabica_app/loyalty-proxy && cp index.js.backup_YYYYMMDD_HHMMSS index.js && pm2 restart loyalty-proxy"
```

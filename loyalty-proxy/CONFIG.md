# Конфигурация Backend Сервера

## Переменные Окружения

Все настройки сервера настраиваются через переменные окружения. Создайте файл `.env` на основе `.env.example`:

```bash
cp .env.example .env
```

### Основные Параметры

#### DATA_DIR
**Описание**: Базовая директория для хранения всех данных приложения
**По умолчанию**: `/var/www`
**Пример**: `DATA_DIR=/opt/arabica/data`

Все поддиректории создаются автоматически внутри `DATA_DIR`:
- `html/` - статические HTML файлы и шаблоны
- `shift-photos/` - фотографии с пересменок
- `recount-reports/` - отчеты пересчета
- `attendance/` - данные о посещаемости
- `employee-photos/` - фотографии сотрудников
- `employee-registrations/` - регистрации сотрудников
- `shop-settings/` - настройки магазинов
- `rko-reports/` - РКО отчеты
- `work-schedules/` - графики работы
- `work-schedule-templates/` - шаблоны графиков
- `suppliers/` - данные поставщиков
- `clients/` - данные клиентов

#### ALLOWED_ORIGINS
**Описание**: Список разрешенных доменов для CSRF защиты (через запятую)
**По умолчанию**: `https://arabica26.ru,http://localhost:3000`
**Пример**: `ALLOWED_ORIGINS=https://arabica26.ru,https://app.arabica26.ru,http://localhost:3000`

**ВАЖНО**: Все POST/PUT/DELETE запросы проверяются на CSRF атаки. Только запросы с указанными доменами в Origin/Referer будут обработаны.

## Безопасность

### CSRF Защита
Сервер автоматически защищен от CSRF атак:
- Проверяются все POST, PUT, DELETE, PATCH запросы
- Требуется заголовок Origin или Referer
- Origin должен быть в списке ALLOWED_ORIGINS
- При нарушении возвращается HTTP 403 Forbidden

### Конфигурируемые Пути
Все пути к директориям настраиваются через переменные окружения, что позволяет:
- Легко изменить расположение данных
- Запускать в контейнерах (Docker)
- Использовать разные окружения (dev/prod)

## Примеры Использования

### Разработка (Development)
```bash
DATA_DIR=/home/user/arabica-dev
ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
```

### Продакшн (Production)
```bash
DATA_DIR=/var/www
ALLOWED_ORIGINS=https://arabica26.ru
```

### Docker
```bash
DATA_DIR=/app/data
ALLOWED_ORIGINS=https://arabica26.ru
```

## Запуск Сервера

```bash
# Установить зависимости
npm install

# Создать .env файл
cp .env.example .env
# Отредактировать .env по необходимости

# Запустить сервер
npm start

# Или с явным указанием переменных
DATA_DIR=/opt/data ALLOWED_ORIGINS=https://example.com npm start
```

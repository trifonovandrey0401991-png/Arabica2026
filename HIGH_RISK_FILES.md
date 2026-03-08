# Файлы высокого риска — НЕ ТРОГАТЬ БЕЗ РАЗРЕШЕНИЯ АНДРЕЯ

## КРИТИЧЕСКИЙ РИСК (ломает ВСЁ)

| Файл | Последствия поломки |
|------|---------------------|
| `lib/core/services/base_http_service.dart` | Приложение полностью не работает |
| `lib/core/constants/api_constants.dart` | Приложение не может связаться с сервером |
| `lib/features/auth/services/auth_service.dart` | Никто не может войти |
| `loyalty-proxy/index.js` | Сервер полностью не работает |
| `loyalty-proxy/utils/db.js` | Все данные недоступны |
| `loyalty-proxy/utils/db_schema.sql` | Структура базы данных |
| `loyalty-proxy/utils/session_middleware.js` | Все вышли из системы |

## ВЫСОКИЙ РИСК (ломается 5-10 частей)

| Файл | Что затронет |
|------|-------------|
| `base_report_service.dart` | Все отчеты: пересменки, пересчеты, конверты, кофемашины |
| `multitenancy_filter_service.dart` | Фильтрация «по моим магазинам» — 8+ экранов |
| `employee_service.dart` | Списки сотрудников в 8+ разделах |
| `shop_model.dart` | Информация о магазинах — 10+ мест |
| `user_role_service.dart` | Все права доступа |
| `employee_push_service.dart` | Push-уведомления — 7 модулей |

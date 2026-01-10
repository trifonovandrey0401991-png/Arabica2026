# Архитектура сервисов Arabica

## Обзор

Проект использует **сервисную архитектуру** для работы с данными. Все HTTP-запросы к серверу проходят через унифицированный `BaseHttpService`.

## Структура

```
lib/
├── core/
│   ├── services/           # Базовые сервисы
│   │   ├── base_http_service.dart    # HTTP-абстракция
│   │   ├── firebase_service.dart     # Push-уведомления
│   │   ├── notification_service.dart # Локальные уведомления
│   │   └── photo_upload_service.dart # Загрузка фото
│   ├── constants/
│   │   └── api_constants.dart        # Все API endpoints
│   └── utils/
│       └── logger.dart               # Логирование
│
└── features/
    └── {feature}/
        └── services/
            └── {feature}_service.dart  # Feature-специфичный сервис
```

## Базовый HTTP-сервис

`BaseHttpService` - единая точка для всех API-запросов.

### Методы

| Метод | Описание | Возврат |
|-------|----------|---------|
| `getList<T>()` | Получить список | `List<T>` |
| `get<T>()` | Получить один элемент | `T?` |
| `post<T>()` | Создать элемент | `T?` |
| `put<T>()` | Обновить элемент | `T?` |
| `patch<T>()` | Частичное обновление | `T?` |
| `delete()` | Удалить элемент | `bool` |
| `getRaw()` | GET с сырым ответом | `Map?` |
| `postRaw()` | POST с сырым ответом | `Map?` |
| `simplePost()` | POST без парсинга | `bool` |
| `simplePatch()` | PATCH без парсинга | `bool` |

### Пример использования

```dart
// В feature-сервисе
class TaskService {
  static Future<List<Task>> getTasks() async {
    return await BaseHttpService.getList<Task>(
      endpoint: ApiConstants.tasksEndpoint,
      fromJson: Task.fromJson,
      listKey: 'tasks',
    );
  }

  static Future<Task?> createTask(Map<String, dynamic> data) async {
    return await BaseHttpService.post<Task>(
      endpoint: ApiConstants.tasksEndpoint,
      body: data,
      fromJson: Task.fromJson,
      itemKey: 'task',
    );
  }
}
```

## API Constants

Все endpoints определены в `ApiConstants`:

```dart
class ApiConstants {
  static const String serverUrl = 'https://arabica26.ru';

  // Core
  static const String employeesEndpoint = '/api/employees';
  static const String clientsEndpoint = '/api/clients';
  static const String shopsEndpoint = '/api/shops';

  // Tasks
  static const String tasksEndpoint = '/api/tasks';
  static const String taskAssignmentsEndpoint = '/api/task-assignments';

  // ... и другие
}
```

## Feature-сервисы

Каждая фича имеет свой сервис в `lib/features/{name}/services/`.

### Список сервисов по категориям

#### Сотрудники и роли
- `employee_service.dart` - CRUD сотрудников
- `user_role_service.dart` - определение роли пользователя
- `employee_registration_service.dart` - регистрация сотрудников

#### Клиенты
- `client_service.dart` - CRUD клиентов
- `registration_service.dart` - регистрация клиентов
- `client_dialog_service.dart` - диалоги с клиентами

#### Отчёты и смены
- `shift_report_service.dart` - отчёты пересменки
- `shift_handover_report_service.dart` - сдача смены
- `recount_service.dart` - отчёты пересчёта
- `envelope_report_service.dart` - отчёты по конвертам

#### Задачи
- `task_service.dart` - разовые задачи
- `recurring_task_service.dart` - периодические задачи

#### Эффективность
- `efficiency_data_service.dart` - данные эффективности
- `efficiency_calculation_service.dart` - расчёт баллов
- `points_settings_service.dart` - настройки баллов
- `bonus_penalty_service.dart` - премии/штрафы

#### Рейтинг и награды
- `rating_service.dart` - рейтинг сотрудников
- `fortune_wheel_service.dart` - колесо удачи
- `referral_service.dart` - реферальная система

#### Прочее
- `loyalty_service.dart` - карта лояльности
- `attendance_service.dart` - "Я на работе"
- `rko_service.dart` - РКО документы
- `review_service.dart` - отзывы
- `job_application_service.dart` - заявки на работу

## Соглашения

### 1. Статические методы
Все методы сервисов - **статические**. Не нужно создавать экземпляры.

```dart
// Правильно
final tasks = await TaskService.getTasks();

// Неправильно
final service = TaskService();
final tasks = await service.getTasks();
```

### 2. Обработка ошибок
Сервисы **не бросают исключения** наружу. При ошибке возвращают:
- `[]` для списков
- `null` для одиночных элементов
- `false` для операций

```dart
final task = await TaskService.getTask(id);
if (task == null) {
  // Ошибка или не найдено
}
```

### 3. Логирование
Все запросы автоматически логируются через `Logger`:
- `Logger.debug()` - отладочная информация
- `Logger.error()` - ошибки
- `Logger.success()` - успешные операции

### 4. Таймауты
По умолчанию 15 секунд. Можно переопределить:

```dart
await BaseHttpService.getList<Task>(
  endpoint: '/api/tasks',
  timeout: Duration(seconds: 30),
  // ...
);
```

## Серверный код

Серверный API находится в `loyalty-proxy/index.js` на сервере `arabica26.ru`.

### Формат ответов

```json
// Успех - список
{
  "success": true,
  "tasks": [...]
}

// Успех - один элемент
{
  "success": true,
  "task": {...}
}

// Ошибка
{
  "success": false,
  "error": "Описание ошибки"
}
```

## Добавление нового сервиса

1. Создать файл `lib/features/{name}/services/{name}_service.dart`
2. Добавить endpoint в `ApiConstants`
3. Использовать `BaseHttpService` для запросов
4. Добавить документацию (/// комментарии)

```dart
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../models/{name}_model.dart';

/// Сервис для работы с {описание}.
class MyService {
  /// Получить все элементы.
  static Future<List<MyModel>> getAll() async {
    return await BaseHttpService.getList<MyModel>(
      endpoint: ApiConstants.myEndpoint,
      fromJson: MyModel.fromJson,
      listKey: 'items',
    );
  }
}
```

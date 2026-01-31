# Arabica 2026 - Test Suite

## Структура тестов

```
test/
├── client/                        # Тесты для роли КЛИЕНТ
│   ├── auth_test.dart            # Авторизация клиента (P0)
│   ├── orders_test.dart          # Заказы и корзина (P1)
│   ├── menu_test.dart            # Меню и избранное (P2)
│   ├── loyalty_test.dart         # Карта лояльности (P2)
│   ├── reviews_test.dart         # Отзывы (P2)
│   └── shops_map_test.dart       # Карта магазинов + геофенсинг (P3)
├── employee/                      # Тесты для роли СОТРУДНИК
│   ├── attendance_test.dart      # Посещаемость (P0)
│   ├── shift_test.dart           # Пересменки (P0)
│   ├── envelope_test.dart        # Конверты (P1)
│   ├── rating_wheel_test.dart    # Рейтинг и колесо удачи (P1)
│   ├── chat_test.dart            # Чат сотрудников (P1)
│   ├── tasks_test.dart           # Задачи (P1)
│   ├── product_search_test.dart  # Поиск товара (P2)
│   ├── training_test.dart        # Обучение и тестирование (P2)
│   └── recipes_test.dart         # Рецепты (P3)
├── admin/                         # Тесты для роли АДМИНИСТРАТОР
│   ├── reports_test.dart         # Отчёты (P0)
│   ├── suppliers_test.dart       # Поставщики (P3)
│   └── data_cleanup_test.dart    # Очистка данных (P3)
├── integration/                   # Интеграционные тесты
│   └── efficiency_cycle_test.dart  # Расчёт эффективности (P0)
├── api/                           # API тесты (Node.js)
│   └── efficiency_api_test.js
├── mocks/                         # Mock данные и сервисы
│   └── mock_services.dart
└── README.md                      # Этот файл
```

## Приоритеты тестов

### P0 - Критический (обязательно)
- ✅ Авторизация и определение роли → `client/auth_test.dart`
- ✅ Расчёт эффективности (12 категорий) → `integration/efficiency_cycle_test.dart`
- ✅ Автоматизация штрафов → `integration/efficiency_cycle_test.dart`
- ✅ Пересменка (полный цикл) → `employee/shift_test.dart`
- ✅ Посещаемость с геолокацией → `employee/attendance_test.dart`

### P1 - Высокий приоритет
- ✅ Заказы (клиент + сотрудник) → `client/orders_test.dart`
- ✅ Рейтинг и колесо удачи → `employee/rating_wheel_test.dart`
- ✅ Конверты (автоматизация) → `employee/envelope_test.dart`
- ✅ Чат сотрудников → `employee/chat_test.dart`
- ✅ Задачи (разовые + циклические) → `employee/tasks_test.dart`

### P2 - Средний приоритет
- ✅ Меню и корзина → `client/menu_test.dart`
- ✅ Карта лояльности → `client/loyalty_test.dart`
- ✅ Отзывы → `client/reviews_test.dart`
- ✅ Поиск товара → `employee/product_search_test.dart`
- ✅ Обучение и тестирование → `employee/training_test.dart`

### P3 - Низкий приоритет
- ✅ Рецепты → `employee/recipes_test.dart`
- ✅ Поставщики → `admin/suppliers_test.dart`
- ✅ Очистка данных → `admin/data_cleanup_test.dart`
- ✅ Магазины на карте + геофенсинг → `client/shops_map_test.dart`

## Статистика тестов

| Категория | Файлов | Тестов |
|-----------|--------|--------|
| P0 (критические) | 5 | ~50 |
| P1 (высокий приоритет) | 5 | ~130 |
| P2 (средний приоритет) | 5 | ~90 |
| P3 (низкий приоритет) | 4 | ~45 |
| **Итого** | **19** | **~315** |

## Запуск тестов

### Flutter тесты

```bash
# Все тесты
flutter test

# Конкретная директория
flutter test test/client/
flutter test test/employee/
flutter test test/admin/
flutter test test/integration/

# Конкретный файл
flutter test test/employee/attendance_test.dart

# С покрытием
flutter test --coverage

# Только P0 тесты
flutter test test/client/auth_test.dart test/employee/attendance_test.dart test/employee/shift_test.dart test/admin/reports_test.dart test/integration/
```

### API тесты (Node.js)

```bash
cd loyalty-proxy

# Установка зависимостей для тестов
npm install --save-dev mocha chai

# Запуск
npm test test/api/efficiency_api_test.js
```

## Создание новых тестов

### Шаблон Flutter теста

```dart
import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

void main() {
  group('Feature Name Tests', () {

    setUp(() async {
      // Инициализация перед каждым тестом
    });

    tearDown(() async {
      // Очистка после каждого теста
    });

    test('TEST-001: Описание теста', () async {
      // Arrange
      final testData = MockEmployeeData.validEmployee;

      // Act
      final result = await someFunction(testData);

      // Assert
      expect(result.success, true);
      expect(result.data, isNotNull);
    });
  });
}
```

### Шаблон API теста

```javascript
describe('API Endpoint', () => {

  beforeEach(() => {
    // Setup
  });

  afterEach(() => {
    // Cleanup
  });

  it('TEST-001: should return expected result', async () => {
    // Arrange
    const input = { ... };

    // Act
    const response = await fetch(`${API_URL}/endpoint`, {
      method: 'POST',
      body: JSON.stringify(input)
    });
    const data = await response.json();

    // Assert
    assert.equal(data.success, true);
  });
});
```

## Naming Convention

| Роль | Префикс | Пример |
|------|---------|--------|
| Client | CT- | CT-AUTH-001 |
| Employee | ET- | ET-ATT-001 |
| Admin | AT- | AT-REP-001 |
| Integration | INT- | INT-EFF-001 |
| API | XXX-API- | EFF-API-001 |

## Покрытие модулей

### Покрытые модули (31 из 31)
1. ✅ Управление магазинами (shops_map_test)
2. ✅ Управление сотрудниками (auth_test, reports_test)
3. ✅ График работы (attendance_test)
4. ✅ Пересменки (shift_test)
5. ✅ Пересчёты (efficiency_cycle_test)
6. ✅ ИИ Распознавание (интеграция в efficiency)
7. ✅ РКО (efficiency_cycle_test)
8. ✅ Сдать смену (shift_test)
9. ✅ Посещаемость (attendance_test)
10. ✅ Передать смену (shift_test)
11. ✅ KPI/Аналитика (reports_test)
12. ✅ Отзывы (reviews_test)
13. ✅ Эффективность (efficiency_cycle_test, rating_wheel_test)
14. ✅ Мои диалоги (chat_test)
15. ✅ Поиск товара (product_search_test)
16. ✅ Заказы (orders_test)
17. ✅ Статьи обучения (training_test)
18. ✅ Тестирование (training_test)
19. ✅ Конверты (envelope_test)
20. ✅ Главная Касса (reports_test)
21. ✅ Задачи (tasks_test)
22. ✅ Устроиться на работу (auth_test)
23. ✅ Реферальная система (rating_wheel_test)
24. ✅ Рейтинг и Колесо Удачи (rating_wheel_test)
25. ✅ Меню и Рецепты (menu_test, recipes_test)
26. ✅ Магазины на карте (shops_map_test)
27. ✅ Карта лояльности (loyalty_test)
28. ✅ Чат сотрудников (chat_test)
29. ✅ Премии и штрафы (efficiency_cycle_test)
30. ✅ Очистка данных (data_cleanup_test)
31. ✅ Поставщики (suppliers_test)

## Критерии успеха

- [x] Все P0 тесты проходят (100%)
- [x] P1 тесты покрыты (100%)
- [x] P2 тесты покрыты (100%)
- [x] P3 тесты покрыты (100%)
- [x] Все 31 модуль покрыты тестами
- [ ] Время выполнения < 10 минут
- [ ] Code coverage > 60%

## Полезные команды

```bash
# Проверка синтаксиса без запуска
flutter analyze

# Форматирование кода
dart format test/

# Генерация покрытия
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html

# Открыть отчёт покрытия
open coverage/html/index.html

# Запуск конкретной группы тестов
flutter test --name "Rating"
```

## Документация

- [TEST_PLAN_ANALYSIS.md](../TEST_PLAN_ANALYSIS.md) - Полный план тестирования
- [ARCHITECTURE_NEW.md](../ARCHITECTURE_NEW.md) - Архитектура системы
- [CLAUDE.md](../CLAUDE.md) - Правила разработки

---

> **Автор:** Claude Code Analysis
> **Версия:** 2.0
> **Дата:** 2026-02-01

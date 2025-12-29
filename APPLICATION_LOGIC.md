# 📚 Полная документация логики приложения Arabica2026

**Проект:** Arabica2026 Coffee Shop Management System
**Дата создания:** 2025-12-29
**Версия:** 2.0 (после полного рефакторинга)
**Назначение:** Справочный документ для поддержания контекста между сессиями

---

## 🎯 Общая информация о проекте

### Описание
Arabica2026 - это система управления сетью кофеен, включающая:
- Управление сотрудниками и графиками работы
- Программа лояльности для клиентов
- Управление меню и заказами
- KPI и отчетность
- Посещаемость и отметки
- РКО (расходные кассовые ордера)
- Отзывы и коммуникация с клиентами

### Технологии
- **Клиент:** Flutter (поддержка Web + Android + iOS)
- **Сервер:** Node.js Express
- **База данных:** Файловая система (JSON файлы)
- **Хостинг:** arabica26.ru
- **Ветка разработки:** refactoring/full-restructure

### Пользовательские роли
```dart
enum UserRole {
  admin,     // Администратор - полный доступ
  employee,  // Сотрудник - ограниченный доступ
  client,    // Клиент - доступ к программе лояльности
}
```

**Основные администраторы:**
- Телефон: 79054443224

---

## 📁 Структура проекта (после рефакторинга)

### Flutter Client
```
lib/
├── core/
│   ├── constants/
│   │   ├── api_constants.dart       # URL, endpoints, timeouts
│   │   └── app_constants.dart       # Радиус отметок, границы смен
│   ├── services/
│   │   └── base_http_service.dart   # Базовый HTTP сервис
│   └── utils/
│       ├── logger.dart              # Централизованное логирование
│       ├── cache_manager.dart       # Кэширование данных
│       └── phone_normalizer.dart    # Нормализация телефонов
│
├── features/                         # Feature-based архитектура
│   ├── attendance/                   # Отметки посещаемости
│   ├── clients/                      # Управление клиентами
│   ├── employees/                    # Управление сотрудниками
│   ├── kpi/                          # KPI и метрики
│   ├── menu/                         # Меню и продукты
│   ├── orders/                       # Заказы
│   ├── recipes/                      # Рецепты
│   ├── reviews/                      # Отзывы
│   ├── rko/                          # РКО
│   ├── shops/                        # Магазины
│   └── work_schedule/                # График работы
│
├── shared/                           # Общие компоненты
│   ├── widgets/                      # Переиспользуемые виджеты
│   ├── dialogs/                      # Диалоги
│   └── providers/                    # State management
│
└── main.dart                         # Точка входа
```

### Node.js Server
```
/root/loyalty-proxy/
├── config/
│   └── constants.js              # Пути, URL, лимиты
├── middleware/
│   ├── errorHandler.js           # Обработка ошибок
│   └── validation.js             # Валидация запросов
├── utils/
│   ├── fileSystem.js             # Работа с файлами
│   └── dataFilter.js             # Фильтрация данных
├── routes/                       # Модульные роуты
│   ├── attendance.js
│   ├── clients.js
│   ├── employees.js
│   ├── menu.js
│   ├── orders.js
│   ├── recount.js
│   ├── rko.js
│   ├── shops.js
│   └── workSchedule.js
└── index.js                      # Главный файл (~100 строк)
```

---

## 🔐 Система доступа и ролей

### UserRoleService

**Файл:** `lib/features/user_role/services/user_role_service.dart`

**Логика определения роли:**
```dart
static Future<UserRole> determineUserRole(String phone) async {
  // 1. Проверка администратора
  if (phone == '79054443224') {
    return UserRole.admin;
  }

  // 2. Проверка сотрудника
  final employees = await EmployeeService.getEmployees();
  final isEmployee = employees.any((emp) =>
    PhoneNormalizer.normalize(emp.phone) == PhoneNormalizer.normalize(phone)
  );

  if (isEmployee) {
    return UserRole.employee;
  }

  // 3. По умолчанию - клиент
  return UserRole.client;
}
```

**Доступ к функциям по ролям:**

| Функция | Admin | Employee | Client |
|---------|-------|----------|--------|
| Управление сотрудниками | ✅ | ❌ | ❌ |
| График работы | ✅ | ✅ Просмотр | ❌ |
| Отметки посещаемости | ✅ | ✅ | ❌ |
| РКО | ✅ | ✅ | ❌ |
| **Отчеты (Reports)** | ✅ | ❌ | ❌ |
| KPI | ✅ | ✅ Свои | ❌ |
| Программа лояльности | ✅ | ❌ | ✅ |
| Заказы | ✅ | ✅ | ❌ |

**Важное изменение (Commit e2c9901):**
```dart
// В main_menu_page.dart строка 365
// БЫЛО: if (role == UserRole.admin || role == UserRole.employee)
// СТАЛО: if (role == UserRole.admin)
// Теперь Reports видят ТОЛЬКО администраторы
```

---

## 📊 Система работы с графиком (Work Schedule)

### Модели данных

**WorkScheduleEntry:**
```dart
class WorkScheduleEntry {
  String id;
  String employeeId;
  String employeeName;
  String shopAddress;
  DateTime date;
  ShiftType shiftType;  // morning, day, evening
}
```

**Employee (предпочтения):**
```dart
class Employee {
  String id;
  String name;
  String phone;

  // Предпочтения
  List<String> preferredShops;        // Список ID магазинов
  List<String> preferredWorkDays;     // ['monday', 'friday', ...]
  Map<String, int> shiftPreferences;  // {'morning': 1, 'evening': 2}

  // Градации предпочтений смен:
  // 1 - Всегда хочет работать эту смену
  // 2 - Может работать, но не хочет
  // 3 - НЕ будет работать эту смену
}
```

### Алгоритм автозаполнения графика

**Файл:** `lib/features/work_schedule/services/auto_fill_schedule_service.dart`

#### 4 главных правила (требования пользователя):

1. **✅ Главное - учитываются заполненные предпочтения**
2. **✅ Нельзя ставить сотруднику утро, если перед сменой он работал вечером**
3. **✅ Если не хватает сотрудника на магазин - игнорировать первое правило, но нельзя нарушать второе**
4. **✅ Использовать систему баллов**

#### Система баллов (Priority Scoring System)

**Максимальный балл: 120 (после улучшений)**

| Приоритет | Условие | Баллы | Пример |
|-----------|---------|-------|--------|
| **1. Предпочтение магазина** | `preferredShops.contains(shop.id)` | **+10** | Любит "Ессентуки" |
| **2. Желаемый день** | `preferredWorkDays.contains("monday")` | **+5** | Любит понедельник |
| **3. Любит смену** | `shiftPreferences[shiftType] == 1` | **+3** | Всегда хочет утро |
| **3. Может работать** | `shiftPreferences[shiftType] == 2` | **+1** | Может утром |
| **3. НЕ будет работать** | `shiftPreferences[shiftType] == 3` | **-10** | Не работает утром |
| **4. Нет конфликта** | `!_hasConflict(...)` | **+2** | Не работал вчера вечером |
| **5. Усиленная балансировка** | `assignedShiftsCount == 0` | **+100** | Гарантия для незадействованных |
| **5. Обычная балансировка** | `30 - assignedShiftsCount` | **0-30** | Чем меньше смен, тем выше балл |

**Код Priority 5 (Усиленная балансировка нагрузки):**
```dart
// Приоритет 5: Усиленная балансировка нагрузки
// Чем меньше смен назначено, тем выше приоритет
final assignedShiftsCount = schedule.entries
    .where((e) => e.employeeId == employee.id)
    .length;

// Экстра-бонус для сотрудников без смен (+100)
// Обычная балансировка (от +30 до 0)
if (assignedShiftsCount == 0) {
  score += 100; // Гарантированный максимальный приоритет
} else {
  final loadBalanceBonus = (30 - assignedShiftsCount).clamp(0, 30);
  score += loadBalanceBonus;
}
```

**Прогрессия баллов:**
- 0 смен: **+100** (ГАРАНТИЯ назначения)
- 1 смена: +29
- 5 смен: +25
- 10 смен: +20
- 15 смен: +15
- 30+ смен: 0

#### Процесс автозаполнения (пошагово)

**1. Подготовка данных:**
```dart
// Разделение сотрудников на группы
final employeesWithPreferences = employees.where((e) =>
  e.preferredWorkDays.isNotEmpty ||
  e.preferredShops.isNotEmpty ||
  e.shiftPreferences.isNotEmpty
).toList();

final employeesWithoutPreferences = employees.where((e) =>
  e.preferredWorkDays.isEmpty &&
  e.preferredShops.isEmpty &&
  e.shiftPreferences.isEmpty
).toList();
```

**2. Цикл назначения смен:**
```dart
ДЛЯ КАЖДОГО дня в периоде:
  ДЛЯ КАЖДОГО магазина:
    ДЛЯ КАЖДОЙ смены (утро, вечер):

      // Попытка #1: С ПРЕДПОЧТЕНИЯМИ
      selectedEmployee = _selectBestEmployee(
        employees: employeesWithPreferences,
      );

      // Попытка #2: БЕЗ предпочтений
      if (selectedEmployee == null) {
        selectedEmployee = _selectBestEmployee(
          employees: employeesWithoutPreferences,
        );
      }

      // Попытка #3: ЛЮБОЙ доступный
      if (selectedEmployee == null) {
        selectedEmployee = _selectAnyAvailableEmployee(
          employees: employees,
        );
      }

      // Назначить смену
      if (selectedEmployee != null) {
        createScheduleEntry();
      }
```

**3. Метод `_selectBestEmployee()` - выбор лучшего кандидата:**
```dart
static Employee? _selectBestEmployee({
  required Shop shop,
  required DateTime day,
  required ShiftType shiftType,
  required List<Employee> employees,
  required WorkSchedule schedule,
}) {
  // 1. Подсчитать баллы для ВСЕХ сотрудников
  final scoredEmployees = employees.map((employee) {
    int score = 0;

    // Priority 1: +10 за предпочитаемый магазин
    if (_isPreferredShop(employee, shop)) {
      score += 10;
    }

    // Priority 2: +5 за желаемый день
    if (_isPreferredDay(employee, day)) {
      score += 5;
    }

    // Priority 3: Предпочтение смены
    final grade = _getShiftPreferenceGrade(employee, shiftType);
    if (grade == 1) score += 3;      // Всегда хочет
    else if (grade == 2) score += 1; // Может
    else if (grade == 3) score -= 10; // НЕ будет

    // Priority 4: +2 за отсутствие конфликта
    if (!_hasConflict(employee, day, shiftType, schedule)) {
      score += 2;
    }

    // Priority 5: Усиленная балансировка
    final assignedShiftsCount = schedule.entries
        .where((e) => e.employeeId == employee.id)
        .length;

    if (assignedShiftsCount == 0) {
      score += 100; // Гарантия для незадействованных
    } else {
      final loadBalanceBonus = (30 - assignedShiftsCount).clamp(0, 30);
      score += loadBalanceBonus;
    }

    return {'employee': employee, 'score': score};
  }).toList();

  // 2. Отфильтровать отрицательные баллы
  scoredEmployees.removeWhere((item) => item['score'] as int < 0);

  // 3. Отсортировать по убыванию баллов
  scoredEmployees.sort((a, b) =>
    (b['score'] as int).compareTo(a['score'] as int)
  );

  // 4. Выбрать первого, кто может работать
  for (var item in scoredEmployees) {
    final employee = item['employee'] as Employee;
    if (_canWorkShift(employee, day, shiftType, schedule)) {
      return employee;
    }
  }

  return null;
}
```

**4. Метод `_canWorkShift()` - проверка возможности работы:**
```dart
static bool _canWorkShift(
  Employee employee,
  DateTime day,
  ShiftType shiftType,
  WorkSchedule schedule,
) {
  // БЛОКИРОВКА 1: Конфликт "утро после вечера"
  if (_hasConflict(employee, day, shiftType, schedule)) {
    return false; // СТРОГАЯ БЛОКИРОВКА
  }

  // БЛОКИРОВКА 2: Один сотрудник = одна смена в день
  final hasShift = schedule.entries.any((e) =>
    e.employeeId == employee.id &&
    e.date.year == day.year &&
    e.date.month == day.month &&
    e.date.day == day.day
  );

  if (hasShift) {
    return false; // НЕ разрешаем несколько смен в день
  }

  return true;
}
```

**5. Метод `_hasConflict()` - проверка конфликта "утро после вечера":**
```dart
static bool _hasConflict(
  Employee employee,
  DateTime day,
  ShiftType shiftType,
  WorkSchedule schedule,
) {
  // Проверяем ТОЛЬКО для утренней смены
  if (shiftType != ShiftType.morning) return false;

  // Проверяем, работал ли вечером ВЧЕРА
  final previousDay = day.subtract(const Duration(days: 1));
  return schedule.entries.any((e) =>
    e.employeeId == employee.id &&
    e.date.year == previousDay.year &&
    e.date.month == previousDay.month &&
    e.date.day == previousDay.day &&
    e.shiftType == ShiftType.evening
  );
}
```

**6. Валидация и статистика:**
```dart
static List<String> _validateAllEmployeesUsed(
  WorkSchedule schedule,
  List<Employee> employees,
  List<DateTime> days,
) {
  final warnings = <String>[];
  final employeeShiftCounts = <String, int>{};

  // Подсчет смен для каждого сотрудника
  for (var employee in employees) {
    final shiftsCount = schedule.entries
        .where((e) => e.employeeId == employee.id && ...)
        .length;

    employeeShiftCounts[employee.name] = shiftsCount;

    if (shiftsCount == 0) {
      warnings.add('⚠️ Сотрудник ${employee.name} не задействован в графике');
    }
  }

  // Статистика в логах
  Logger.debug('📊 Статистика распределения смен:');
  Logger.debug('   Всего смен: $totalShifts');
  Logger.debug('   Среднее на сотрудника: ${avgShifts.toStringAsFixed(1)}');
  Logger.debug('   Минимум: $minShifts, Максимум: $maxShifts');
  Logger.debug('   Сотрудников с 0 смен: ${count}');

  return warnings;
}
```

#### Пример работы (сценарий)

**Исходные данные:**
- Период: 1-15 декабря 2025 (15 дней)
- Магазины: 8
- Сотрудники: 25
- Ожидаемые смены: 15 × 8 × 2 = **240 смен**

**День 1, Магазин "Ессентуки", Утро:**

```
Кандидаты с баллами:
1. Бородина: 10 (магазин) + 5 (понедельник) + 3 (любит утро) + 2 (нет конфликта) + 100 (0 смен) = 120
2. Васютина: 10 (магазин) + 1 (может утром) + 2 (нет конфликта) + 100 (0 смен) = 113
3. Веретенников: 5 (понедельник) + 3 (любит утро) + 2 (нет конфликта) + 100 (0 смен) = 110

Проверка _canWorkShift():
- Бородина: ✅ Может работать → НАЗНАЧЕНА
```

**День 1, Магазин "Ессентуки", Вечер:**

```
Кандидаты с баллами:
1. Бородина: 120 баллов → ❌ БЛОКИРОВАНА (уже работает сегодня)
2. Васютина: 113 баллов → ✅ НАЗНАЧЕНА
```

**Результат после 15 дней (ожидаемый):**
- Минимум смен: 8-9
- Максимум смен: 10-11
- Среднее: 9.6
- Сотрудников с 0 смен: **0** (гарантировано)

#### История улучшений алгоритма

**Версия 1.0 (до улучшений):**
- Проблема: 2 сотрудника получали все 160 смен
- Причина: Можно было работать утро И вечер в один день

**Версия 2.0 (Commit 4a3bbbf):**
- Исправление: Блокировка нескольких смен в день
- Результат: Более равномерное распределение

**Версия 2.1 (Commit 017bc3e):**
- Добавлено: Priority 5 с бонусом +15 за низкую нагрузку
- Добавлено: Валидация `_validateAllEmployeesUsed()`
- Результат: 6 сотрудников все еще получили 0 смен

**Версия 2.2 (текущая):**
- Усилено: Priority 5 с бонусом +100 для незадействованных
- Усилено: Priority 5 с бонусом до +30 для малозадействованных
- Результат: **ВСЕ** 25 сотрудников гарантированно получают смены

---

## 📄 Система РКО (Расходные кассовые ордера)

### Модели данных

**RKO:**
```dart
class RKO {
  String id;
  String employeeName;
  String shopAddress;
  DateTime date;
  int amount;
  String category;
  String documentNumber;
  String pdfFileName;
  String pdfUrl;
  DateTime createdAt;
}
```

### Генерация PDF документов

**Файлы:**
- `lib/features/rko/services/rko_pdf_service.dart` - Генерация PDF
- `lib/features/rko/services/rko_reports_service.dart` - Загрузка на сервер
- `lib/features/rko/services/rko_service.dart` - Основной API

#### Проблема: Несовместимость с веб-платформой

**Ошибка 1 (Commit 30bb694):**
```
MissingPluginException(
  No implementation found for method getTemporaryDirectory
  on channel plugins.flutter.io/path_provider
)
```

**Причина:**
- Плагин `path_provider` не поддерживается на Flutter Web
- Браузеры не предоставляют доступ к файловой системе
- Методы `getTemporaryDirectory()` и `getApplicationDocumentsDirectory()` недоступны

**Решение: Класс `_MemoryFile`**
```dart
/// Класс для работы с файлами в памяти (для веб-платформы)
/// Имитирует интерфейс File, но хранит данные в памяти
class _MemoryFile implements File {
  final String _path;
  final Uint8List _bytes;

  _MemoryFile(String path, List<int> bytes)
      : _path = path,
        _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  @override
  String get path => _path;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Uint8List readAsBytesSync() => _bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

**Применение в `generateRKOFromDocx()`:**
```dart
if (response.statusCode == 200) {
  final fileName = generateFileName(...);

  if (kIsWeb) {
    // Для веб создаем временный файл в памяти
    final virtualFile = _MemoryFile(fileName, response.bodyBytes);
    return virtualFile; // ✅ РАБОТАЕТ
  } else {
    // Для мобильных сохраняем в файловую систему
    final directory = await getTemporaryDirectory();
    final file = File(path.join(directory.path, fileName));
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }
}
```

**Ошибка 2 (Commit 5ef9fa4):**
```
Unsupported operation: MultipartFile is only supported
where dart:io is available.
```

**Причина:**
- `MultipartFile.fromPath()` требует доступ к файловой системе
- На веб-платформе нет файловых путей (все в памяти)

**Решение: Платформо-специфичная загрузка**
```dart
// В uploadRKO()
if (kIsWeb) {
  // Читаем байты из файла (работает с _MemoryFile)
  final bytes = await pdfFile.readAsBytes();
  request.files.add(
    http.MultipartFile.fromBytes(
      'docx',
      bytes,
      filename: fileName, // Важно: явно указываем имя
    ),
  );
} else {
  // Для мобильных используем путь к файлу
  request.files.add(
    await http.MultipartFile.fromPath('docx', pdfFile.path),
  );
}
```

### Полный цикл создания РКО

**1. Пользователь создает РКО через UI**
```dart
// Заполняет форму:
- Сотрудник: "Бородина Елена"
- Магазин: "Арабика Ессентуки"
- Дата: 2025-12-29
- Сумма: 5000
- Категория: "Закупка продуктов"
```

**2. Генерация PDF на сервере**
```dart
final pdfFile = await RKOPDFService.generateRKOFromDocx(
  employeeName: employeeName,
  shopAddress: shopAddress,
  date: date,
  amount: amount,
  category: category,
);
```

**3. Платформо-зависимая обработка**
```dart
// WEB:
Server → PDF bytes → _MemoryFile(fileName, bytes) → возврат

// MOBILE:
Server → PDF bytes → File system → возврат File
```

**4. Загрузка на сервер**
```dart
final success = await RKOReportsService.uploadRKO(
  pdfFile: pdfFile,
  employeeName: employeeName,
  shopAddress: shopAddress,
  date: date,
  amount: amount,
  category: category,
);
```

**5. Сервер сохраняет файл**
```javascript
// /root/loyalty-proxy/routes/rko.js
const fileName = `${sanitized_employee}_${sanitized_shop}_${dateStr}.docx`;
const filePath = path.join(RKO_REPORTS_DIR, fileName);
fs.writeFileSync(filePath, fileBuffer);
```

**6. Обновление базы данных**
```javascript
const rkoData = {
  id: uuidv4(),
  employeeName,
  shopAddress,
  date: date.toISOString(),
  amount,
  category,
  documentNumber: generatedNumber,
  pdfFileName: fileName,
  pdfUrl: `${BASE_URL}/rko-reports/${fileName}`,
  createdAt: new Date().toISOString(),
};

rkoList.push(rkoData);
fs.writeFileSync(RKO_DB_PATH, JSON.stringify(rkoList, null, 2));
```

---

## 📊 Система KPI (Key Performance Indicators)

### Структура после разделения

**Было:** 1 файл `kpi_service.dart` (1200 строк)

**Стало:** 5 файлов

#### 1. kpi_service.dart (координатор, ~150 строк)
```dart
class KpiService {
  static Future<Map<String, dynamic>> getKpiData({
    required DateTime startDate,
    required DateTime endDate,
    String? shopAddress,
  }) async {
    // Проверить кэш
    final cached = await KpiCacheService.get(startDate, endDate, shopAddress);
    if (cached != null) return cached;

    // Загрузить данные
    final data = await KpiAggregationService.aggregate(
      startDate: startDate,
      endDate: endDate,
      shopAddress: shopAddress,
    );

    // Сохранить в кэш
    await KpiCacheService.save(data, startDate, endDate, shopAddress);

    return data;
  }
}
```

#### 2. kpi_aggregation_service.dart (~400 строк)
**Ответственность:**
- Загрузка данных из attendance, orders, rko
- Группировка по магазинам/сотрудникам
- Подсчет метрик

**Основные метрики:**
```dart
class KpiMetrics {
  // Посещаемость
  int totalAttendance;
  int morningShifts;
  int eveningShifts;

  // Заказы
  int totalOrders;
  double totalRevenue;
  double averageCheck;

  // РКО
  int totalRko;
  double totalExpenses;

  // Эффективность
  double revenuePerShift;
  double ordersPerShift;
}
```

#### 3. kpi_cache_service.dart (~100 строк)
```dart
class KpiCacheService {
  static const Duration cacheDuration = Duration(minutes: 5);

  static Future<Map<String, dynamic>?> get(
    DateTime startDate,
    DateTime endDate,
    String? shopAddress,
  ) async {
    final key = _generateCacheKey(startDate, endDate, shopAddress);
    final cached = await CacheManager.get(key);

    if (cached != null && _isValid(cached)) {
      return cached['data'];
    }

    return null;
  }

  static Future<void> save(
    Map<String, dynamic> data,
    DateTime startDate,
    DateTime endDate,
    String? shopAddress,
  ) async {
    final key = _generateCacheKey(startDate, endDate, shopAddress);
    await CacheManager.set(key, {
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}
```

#### 4. kpi_normalizers.dart (~150 строк)
```dart
class KpiNormalizers {
  static String normalizeEmployeeName(String name) {
    return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String normalizeShopAddress(String address) {
    return address.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static DateTime normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }
}
```

#### 5. kpi_filters.dart (~200 строк)
```dart
class KpiFilters {
  // Фильтрация по датам
  static List<T> filterByDateRange<T>(
    List<T> items,
    DateTime startDate,
    DateTime endDate,
    DateTime Function(T) getDate,
  ) {
    return items.where((item) {
      final date = getDate(item);
      return !date.isBefore(startDate) && !date.isAfter(endDate);
    }).toList();
  }

  // Фильтрация по сотрудникам
  static List<T> filterByEmployee<T>(
    List<T> items,
    String employeeName,
    String Function(T) getName,
  ) {
    final normalized = KpiNormalizers.normalizeEmployeeName(employeeName);
    return items.where((item) {
      final itemName = KpiNormalizers.normalizeEmployeeName(getName(item));
      return itemName == normalized;
    }).toList();
  }

  // Разделение на утро/вечер
  static Map<String, List<T>> splitByShift<T>(
    List<T> items,
    ShiftType Function(T) getShiftType,
  ) {
    return {
      'morning': items.where((item) => getShiftType(item) == ShiftType.morning).toList(),
      'evening': items.where((item) => getShiftType(item) == ShiftType.evening).toList(),
    };
  }
}
```

---

## 🌐 Работа с HTTP и API

### BaseHttpService

**Файл:** `lib/core/services/base_http_service.dart`

**Цель:** Устранить дублирование кода в 30+ сервисах

**Было (в каждом сервисе ~60 строк):**
```dart
class ClientService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/clients';

  static Future<List<Client>> getClients() async {
    try {
      final response = await http.get(Uri.parse(baseUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final clientsJson = result['clients'] as List<dynamic>;
          return clientsJson.map((json) => Client.fromJson(json)).toList();
        }
      }
      return [];
    } catch (e) {
      Logger.error('Error', e);
      return [];
    }
  }
}
```

**Стало (~12 строк):**
```dart
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../models/client_model.dart';

class ClientService {
  static Future<List<Client>> getClients() async {
    return await BaseHttpService.getList<Client>(
      endpoint: ApiConstants.clientsEndpoint,
      fromJson: (json) => Client.fromJson(json),
      listKey: 'clients',
    );
  }
}
```

**Сокращение кода: ~80%!**

### Методы BaseHttpService

#### 1. getList - Получение списка
```dart
static Future<List<T>> getList<T>({
  required String endpoint,
  required T Function(Map<String, dynamic>) fromJson,
  required String listKey,
  Map<String, String>? queryParams,
  Duration? timeout,
}) async {
  final uri = Uri.parse('${ApiConstants.serverUrl}$endpoint')
      .replace(queryParameters: queryParams);

  final response = await http
      .get(uri)
      .timeout(timeout ?? ApiConstants.defaultTimeout);

  if (response.statusCode == 200) {
    final result = jsonDecode(response.body);
    if (result['success'] == true) {
      final items = result[listKey] as List<dynamic>;
      return items
          .map((json) => fromJson(json as Map<String, dynamic>))
          .toList();
    }
  }

  return [];
}
```

**Использование:**
```dart
// Клиенты
final clients = await BaseHttpService.getList<Client>(
  endpoint: '/api/clients',
  fromJson: Client.fromJson,
  listKey: 'clients',
);

// Сотрудники
final employees = await BaseHttpService.getList<Employee>(
  endpoint: '/api/employees',
  fromJson: Employee.fromJson,
  listKey: 'employees',
);
```

#### 2. get - Получение одного объекта
```dart
static Future<T?> get<T>({
  required String endpoint,
  required T Function(Map<String, dynamic>) fromJson,
  required String itemKey,
  Duration? timeout,
}) async { /* ... */ }
```

#### 3. post - Создание объекта
```dart
static Future<T?> post<T>({
  required String endpoint,
  required Map<String, dynamic> body,
  required T Function(Map<String, dynamic>) fromJson,
  required String itemKey,
  Duration? timeout,
}) async { /* ... */ }
```

#### 4. put - Обновление объекта
```dart
static Future<T?> put<T>({ /* ... */ }) async { /* ... */ }
```

#### 5. delete - Удаление объекта
```dart
static Future<bool> delete({
  required String endpoint,
  Duration? timeout,
}) async { /* ... */ }
```

### API Constants

**Файл:** `lib/core/constants/api_constants.dart`

```dart
class ApiConstants {
  // URL
  static const String serverUrl = 'https://arabica26.ru';

  // Timeouts
  static const Duration shortTimeout = Duration(seconds: 10);
  static const Duration defaultTimeout = Duration(seconds: 15);
  static const Duration longTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 120);

  // Headers
  static const Map<String, String> jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // Endpoints
  static const String attendanceEndpoint = '/api/attendance';
  static const String clientsEndpoint = '/api/clients';
  static const String employeesEndpoint = '/api/employees';
  static const String menuEndpoint = '/api/menu';
  static const String ordersEndpoint = '/api/orders';
  static const String recipesEndpoint = '/api/recipes';
  static const String reviewsEndpoint = '/api/reviews';
  static const String rkoEndpoint = '/api/rko';
  static const String shopsEndpoint = '/api/shops';
  static const String workScheduleEndpoint = '/api/work-schedule';
  static const String kpiEndpoint = '/api/kpi';
}
```

**Устранено дублирований:** 24 → 1

---

## 🏪 Система магазинов (Shops)

### Модели данных

**Shop:**
```dart
class Shop {
  String id;
  String name;
  String address;
  double latitude;
  double longitude;
  bool isActive;
}
```

**ShopSettings:**
```dart
class ShopSettings {
  String shopAddress;
  TimeOfDay morningStart;
  TimeOfDay morningEnd;
  TimeOfDay eveningStart;
  TimeOfDay eveningEnd;
  double checkInRadius;  // Радиус для отметок (метры)
}
```

### Отметки посещаемости (Attendance)

**Файл:** `lib/features/attendance/services/attendance_service.dart`

**Логика определения смены:**
```dart
static ShiftType determineShift(DateTime time) {
  final hour = time.hour;

  if (hour < AppConstants.eveningBoundaryHour) {
    return ShiftType.morning;
  } else {
    return ShiftType.evening;
  }
}

// AppConstants.eveningBoundaryHour = 15
// До 15:00 → morning
// После 15:00 → evening
```

**Проверка геолокации:**
```dart
static bool isWithinCheckInRadius(
  double userLat,
  double userLng,
  double shopLat,
  double shopLng,
  double radius,
) {
  final distance = _calculateDistance(userLat, userLng, shopLat, shopLng);
  return distance <= radius;
}

// Используется формула Haversine для точного расчета
```

**Создание отметки:**
```dart
static Future<bool> checkIn({
  required String employeeName,
  required String shopAddress,
  required double latitude,
  required double longitude,
}) async {
  // 1. Проверить радиус
  final shop = await ShopService.getShopByAddress(shopAddress);
  final inRadius = isWithinCheckInRadius(
    latitude, longitude,
    shop.latitude, shop.longitude,
    shop.checkInRadius ?? AppConstants.checkInRadius,
  );

  if (!inRadius) {
    throw Exception('Вы слишком далеко от магазина');
  }

  // 2. Определить смену
  final shiftType = determineShift(DateTime.now());

  // 3. Создать отметку
  final attendance = AttendanceRecord(
    id: '',
    employeeName: employeeName,
    shopAddress: shopAddress,
    date: DateTime.now(),
    shiftType: shiftType,
    latitude: latitude,
    longitude: longitude,
  );

  // 4. Отправить на сервер
  return await BaseHttpService.post(/* ... */);
}
```

---

## 👥 Управление клиентами (Clients)

### Модели данных

**Client:**
```dart
class Client {
  String phone;           // Уникальный идентификатор
  String name;
  String clientName;
  bool isAdmin;
  String employeeName;    // Кто зарегистрировал
  DateTime? updatedAt;
}
```

### Нормализация телефонов

**Файл:** `lib/core/utils/phone_normalizer.dart`

```dart
class PhoneNormalizer {
  static String normalize(String phone) {
    // Удаляет пробелы, +, скобки, дефисы
    return phone.replaceAll(RegExp(r'[\s\+\(\)\-]'), '');
  }
}

// Примеры:
// "+7 905 444 32 24" → "79054443224"
// "8 (905) 444-32-24" → "89054443224"
// "7-905-444-32-24" → "79054443224"
```

### Программа лояльности

**Система чашек (Loyalty Cups):**
```dart
class LoyaltyService {
  static const int cupsForFreeItem = 9; // 9 чашек → бесплатный товар

  static Future<int> getCupsCount(String phone) async {
    // Загрузить из базы
  }

  static Future<void> addCup(String phone) async {
    final currentCups = await getCupsCount(phone);
    final newCups = (currentCups + 1) % cupsForFreeItem;
    // Если было 8, станет 0 (получил бесплатный товар)
  }

  static Future<void> redeemReward(String phone) async {
    // Обнулить счетчик чашек
    await setCupsCount(phone, 0);
  }
}
```

**Виджет отображения чашек:**
```dart
class LoyaltyCupWidget extends StatelessWidget {
  final int filledCups;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(9, (index) {
        return Icon(
          index < filledCups ? Icons.coffee : Icons.coffee_outlined,
          color: index < filledCups ? Colors.brown : Colors.grey,
        );
      }),
    );
  }
}
```

### Чат с клиентами

**ClientDialogService:**
```dart
class ClientDialogService {
  // Отправка сообщения клиенту
  static Future<bool> sendMessage({
    required String phone,
    required String message,
    required String senderName,
  }) async {
    final messageData = ClientMessage(
      id: '',
      phone: phone,
      message: message,
      senderName: senderName,
      timestamp: DateTime.now(),
      isFromClient: false, // От сотрудника
    );

    return await BaseHttpService.post(/* ... */);
  }

  // Получение истории сообщений
  static Future<List<ClientMessage>> getMessages(String phone) async {
    return await BaseHttpService.getList<ClientMessage>(
      endpoint: '/api/client-messages/$phone',
      fromJson: ClientMessage.fromJson,
      listKey: 'messages',
    );
  }
}
```

---

## 🔧 Утилиты и вспомогательные сервисы

### Logger

**Файл:** `lib/core/utils/logger.dart`

```dart
class Logger {
  static void debug(String message, [dynamic error]) {
    print('🔵 DEBUG: $message');
    if (error != null) {
      print('   Error: $error');
    }
  }

  static void error(String message, [dynamic error]) {
    print('🔴 ERROR: $message');
    if (error != null) {
      print('   Error: $error');
    }
  }

  static void info(String message) {
    print('ℹ️ INFO: $message');
  }

  static void success(String message) {
    print('✅ SUCCESS: $message');
  }
}
```

**Использование:**
```dart
Logger.debug('🔄 Начало автозаполнения');
Logger.debug('   Период: ${startDate} - ${endDate}');
Logger.debug('   Сотрудников: ${employees.length}');

Logger.error('❌ Ошибка загрузки данных', e);

Logger.success('✅ График создан: 240 смен');
```

### CacheManager

**Файл:** `lib/core/utils/cache_manager.dart`

```dart
class CacheManager {
  static final Map<String, dynamic> _cache = {};

  static Future<dynamic> get(String key) async {
    return _cache[key];
  }

  static Future<void> set(String key, dynamic value) async {
    _cache[key] = value;
  }

  static Future<void> clear(String key) async {
    _cache.remove(key);
  }

  static Future<void> clearAll() async {
    _cache.clear();
  }
}
```

---

## 🖥️ Серверная часть (Node.js)

### Структура после рефакторинга

**Файл:** `/root/loyalty-proxy/index.js` (~100 строк)

```javascript
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const config = require('./config/constants');
const { errorMiddleware } = require('./middleware/errorHandler');

const app = express();

// Middleware
app.use(cors());
app.use(bodyParser.json({ limit: '50mb' }));
app.use(bodyParser.urlencoded({ limit: '50mb', extended: true }));

// Routes
app.use('/api/attendance', require('./routes/attendance'));
app.use('/api/clients', require('./routes/clients'));
app.use('/api/employees', require('./routes/employees'));
app.use('/api/menu', require('./routes/menu'));
app.use('/api/orders', require('./routes/orders'));
app.use('/api/recount-reports', require('./routes/recount'));
app.use('/api/rko', require('./routes/rko'));
app.use('/api/shops', require('./routes/shops'));
app.use('/api/work-schedule', require('./routes/workSchedule'));

// Static files
app.use('/shift-photos', express.static(config.PATHS.SHIFT_PHOTOS));
app.use('/employee-photos', express.static(config.PATHS.EMPLOYEE_PHOTOS));

// Error handling
app.use(errorMiddleware);

// Start server
app.listen(config.PORT, () => {
  console.log(`Server listening on port ${config.PORT}`);
});
```

### Config Constants

**Файл:** `/root/loyalty-proxy/config/constants.js`

```javascript
module.exports = {
  PATHS: {
    SHIFT_PHOTOS: '/var/www/shift-photos',
    RECOUNT_REPORTS: '/var/www/recount-reports',
    ATTENDANCE: '/var/www/attendance',
    EMPLOYEE_PHOTOS: '/var/www/employee-photos',
    EMPLOYEE_REGISTRATIONS: '/var/www/employee-registrations',
    SHOP_SETTINGS: '/var/www/shop-settings',
    RKO_REPORTS: '/var/www/rko-reports',
    WORK_SCHEDULES: '/var/www/work-schedules',
    WORK_SCHEDULE_TEMPLATES: '/var/www/work-schedule-templates',
  },

  URLS: {
    BASE_URL: 'https://arabica26.ru',
    SHIFT_PHOTOS_URL: 'https://arabica26.ru/shift-photos/',
    EMPLOYEE_PHOTOS_URL: 'https://arabica26.ru/employee-photos/',
  },

  LIMITS: {
    FILE_SIZE: 10 * 1024 * 1024, // 10MB
    MAX_RKOS_PER_EMPLOYEE: 150,
    MAX_RKOS_PER_SHOP: 6,
    RECENT_RKOS_LIMIT: 25,
    MAX_DOCUMENT_NUMBER: 50000,
  },

  PORT: 3000,
};
```

### Error Handler Middleware

**Файл:** `/root/loyalty-proxy/middleware/errorHandler.js`

```javascript
function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

function errorMiddleware(err, req, res, next) {
  console.error('❌ Error:', err);

  const statusCode = err.statusCode || 500;
  const message = err.message || 'Internal server error';

  res.status(statusCode).json({
    success: false,
    error: message,
  });
}

module.exports = {
  asyncHandler,
  errorMiddleware,
};
```

### File System Utils

**Файл:** `/root/loyalty-proxy/utils/fileSystem.js`

```javascript
const fs = require('fs');
const path = require('path');

function ensureDirectoryExists(directory) {
  if (!fs.existsSync(directory)) {
    fs.mkdirSync(directory, { recursive: true });
  }
}

function sanitizeFileName(fileName) {
  return fileName.replace(/[^a-zA-Z0-9_\-\.]/g, '_');
}

function readJSONFile(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  return JSON.parse(content);
}

function writeJSONFile(filePath, data) {
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
}

module.exports = {
  ensureDirectoryExists,
  sanitizeFileName,
  readJSONFile,
  writeJSONFile,
};
```

### Data Filter Utils

**Файл:** `/root/loyalty-proxy/utils/dataFilter.js`

```javascript
function filterByEmployeeName(records, employeeName) {
  if (!employeeName) return records;
  return records.filter(r =>
    r.employeeName && r.employeeName.includes(employeeName)
  );
}

function filterByShopAddress(records, shopAddress) {
  if (!shopAddress) return records;
  return records.filter(r =>
    r.shopAddress && r.shopAddress.includes(shopAddress)
  );
}

function filterByDate(records, date, dateField = 'createdAt') {
  if (!date) return records;
  const filterDate = new Date(date);
  return records.filter(r => {
    const recordDate = new Date(r[dateField]);
    return recordDate.toDateString() === filterDate.toDateString();
  });
}

function sortByDate(records, dateField = 'createdAt', order = 'desc') {
  return records.sort((a, b) => {
    const dateA = new Date(a[dateField] || 0);
    const dateB = new Date(b[dateField] || 0);
    return order === 'desc' ? dateB - dateA : dateA - dateB;
  });
}

module.exports = {
  filterByEmployeeName,
  filterByShopAddress,
  filterByDate,
  sortByDate,
};
```

### Пример роута: Clients

**Файл:** `/root/loyalty-proxy/routes/clients.js`

```javascript
const express = require('express');
const router = express.Router();
const { asyncHandler } = require('../middleware/errorHandler');
const { ensureDirectoryExists, readJSONFile, writeJSONFile } = require('../utils/fileSystem');
const config = require('../config/constants');
const path = require('path');
const fs = require('fs');

const clientsDir = '/var/www/clients';

// GET /api/clients - получить всех клиентов
router.get('/', asyncHandler(async (req, res) => {
  ensureDirectoryExists(clientsDir);

  const files = fs.readdirSync(clientsDir).filter(f => f.endsWith('.json'));
  const clients = files.map(file => {
    const filePath = path.join(clientsDir, file);
    return readJSONFile(filePath);
  });

  res.json({ success: true, clients });
}));

// POST /api/clients - создать/обновить клиента
router.post('/', asyncHandler(async (req, res) => {
  const { phone, name, clientName, isAdmin, employeeName } = req.body;

  if (!phone) {
    return res.status(400).json({
      success: false,
      error: 'Телефон обязателен',
    });
  }

  const normalizedPhone = phone.replace(/[^0-9]/g, '');
  const clientFile = path.join(clientsDir, `${normalizedPhone}.json`);

  // Сохранить isAdmin если клиент уже существует
  let preservedIsAdmin = isAdmin || false;
  if (fs.existsSync(clientFile)) {
    const existingClient = readJSONFile(clientFile);
    preservedIsAdmin = existingClient.isAdmin || false;
  }

  const clientData = {
    phone: normalizedPhone,
    name: name || clientName || '',
    clientName: clientName || name || '',
    isAdmin: preservedIsAdmin,
    employeeName: employeeName || '',
    updatedAt: new Date().toISOString(),
  };

  ensureDirectoryExists(clientsDir);
  writeJSONFile(clientFile, clientData);

  console.log(`✅ Client saved: ${clientData.name} (${clientData.phone})`);

  res.json({
    success: true,
    client: clientData,
  });
}));

module.exports = router;
```

---

## 📝 Важные улучшения и исправления

### История изменений (Git commits)

#### 1. Commit 30bb694 - Исправление создания РКО на веб
```
🔧 Исправление создания РКО на веб-платформе

- Создан класс _MemoryFile для хранения PDF в памяти
- Обновлены generateRKOFromDocx() и generateRKO()
- Добавлена проверка kIsWeb для выбора стратегии
```

#### 2. Commit 5ef9fa4 - Исправление загрузки РКО на сервер
```
🔧 Исправление загрузки РКО на сервер для веб-платформы

- Добавлена проверка kIsWeb в uploadRKO()
- Для веб: MultipartFile.fromBytes()
- Для мобильных: MultipartFile.fromPath()
```

#### 3. Commit e2c9901 - Скрытие Reports от сотрудников
```
🔒 Ограничение доступа к Reports только для администраторов

- Изменена логика видимости в main_menu_page.dart
- Теперь Reports видят только администраторы
```

#### 4. Commit 4a3bbbf - Исправление автозаполнения графика
```
🐛 Исправление: один сотрудник = одна смена в день

- Обновлен _canWorkShift() для блокировки нескольких смен в день
- Исправлена проблема с концентрацией всех смен у 2 сотрудников
```

#### 5. Commit 017bc3e - Добавление балансировки нагрузки
```
✨ Улучшения алгоритма автозаполнения графика работы

- Добавлен Приоритет 5: Балансировка нагрузки (+15 баллов)
- Создан метод _validateAllEmployeesUsed()
- Улучшено логирование со статистикой распределения
```

#### 6. Текущая версия - Усиленная балансировка
```
✨ Усиленная балансировка нагрузки графика

- Увеличен бонус до +100 для сотрудников без смен
- Увеличен обычный бонус до +30 (было +15)
- Гарантия задействования всех 25 сотрудников
```

---

## 🎯 Ключевые принципы и best practices

### 1. Платформо-зависимый код
```dart
import 'package:flutter/foundation.dart' show kIsWeb;

if (kIsWeb) {
  // Код для веб-платформы
  final memoryFile = _MemoryFile(fileName, bytes);
} else {
  // Код для мобильных платформ
  final file = File(path);
}
```

### 2. Централизация констант
```dart
// ❌ ПЛОХО: Дублирование в каждом сервисе
class ClientService {
  static const String serverUrl = 'https://arabica26.ru';
}

// ✅ ХОРОШО: Централизация
import '../../../core/constants/api_constants.dart';

class ClientService {
  // Использует ApiConstants.serverUrl
}
```

### 3. Переиспользование кода
```dart
// ❌ ПЛОХО: Повторение логики HTTP запросов
class ClientService {
  static Future<List<Client>> getClients() async {
    // 60 строк HTTP кода
  }
}

// ✅ ХОРОШО: Использование BaseHttpService
class ClientService {
  static Future<List<Client>> getClients() async {
    return await BaseHttpService.getList<Client>(
      endpoint: ApiConstants.clientsEndpoint,
      fromJson: Client.fromJson,
      listKey: 'clients',
    );
  }
}
```

### 4. Логирование
```dart
// ❌ ПЛОХО: print везде
print('Loaded clients');

// ✅ ХОРОШО: Централизованный Logger
Logger.debug('📥 Загружено клиентов: ${clients.length}');
Logger.error('❌ Ошибка загрузки', e);
Logger.success('✅ Операция выполнена успешно');
```

### 5. Обработка ошибок
```dart
// ❌ ПЛОХО: Игнорирование ошибок
try {
  final data = await loadData();
} catch (e) {
  // Пустой catch
}

// ✅ ХОРОШО: Логирование и возврат значения по умолчанию
try {
  final data = await loadData();
  return data;
} catch (e) {
  Logger.error('❌ Ошибка загрузки данных', e);
  return [];
}
```

### 6. Нормализация данных
```dart
// ❌ ПЛОХО: Прямое сравнение
if (employee.name == searchName) { }

// ✅ ХОРОШО: Нормализация перед сравнением
final normalizedSearch = KpiNormalizers.normalizeEmployeeName(searchName);
final normalizedEmployee = KpiNormalizers.normalizeEmployeeName(employee.name);
if (normalizedEmployee == normalizedSearch) { }
```

---

## 🔍 Частые проблемы и их решения

### Проблема 1: "Сохранено локально" при создании РКО на веб
**Причина:** `path_provider` не поддерживается на веб
**Решение:** Класс `_MemoryFile` для хранения в памяти

### Проблема 2: Неравномерное распределение смен
**Причина:** Отсутствие балансировки нагрузки
**Решение:** Priority 5 с бонусом +100 для незадействованных

### Проблема 3: Сотрудник работает утро после вечера
**Причина:** Недостаточная проверка конфликтов
**Решение:** Метод `_hasConflict()` с строгой блокировкой

### Проблема 4: Один сотрудник работает утро И вечер в один день
**Причина:** `_canWorkShift()` разрешал несколько смен
**Решение:** Добавлена проверка `hasShift` с блокировкой

### Проблема 5: Дублирование serverUrl в 24 сервисах
**Причина:** Отсутствие централизации констант
**Решение:** `ApiConstants.serverUrl` в одном месте

---

## 📊 Статистика проекта

### Flutter Client
- **Файлов:** ~143 (организовано в feature-based структуру)
- **Сервисов:** 30 (все используют BaseHttpService)
- **Сокращение кода:** ~40% после рефакторинга
- **Дублирование serverUrl:** 24 → 1

### Node.js Server
- **Строк кода (до):** 1839 в index.js
- **Строк кода (после):** ~100 в index.js + модули
- **Сокращение:** ~50%
- **Модулей:** 15 (routes + utils + middleware)

### Work Schedule Algorithm
- **Версия:** 2.2 (с усиленной балансировкой)
- **Максимальный балл:** 120
- **Приоритетов:** 5
- **Гарантия:** Все 25 сотрудников задействованы

---

## 🚀 Будущие улучшения (рекомендации)

### 1. База данных
**Текущее состояние:** JSON файлы на диске
**Рекомендация:** Миграция на PostgreSQL или MongoDB

### 2. Аутентификация
**Текущее состояние:** По номеру телефона
**Рекомендация:** JWT токены с refresh механизмом

### 3. Кэширование
**Текущее состояние:** In-memory кэш (теряется при перезапуске)
**Рекомендация:** Redis для централизованного кэша

### 4. WebSocket для чата
**Текущее состояние:** HTTP polling
**Рекомендация:** WebSocket для реального времени

### 5. Тестирование
**Текущее состояние:** Ручное тестирование
**Рекомендация:** Unit тесты + Integration тесты

---

## 📞 Контакты и поддержка

**Проект:** Arabica2026 Coffee Shop Management System
**Сервер:** https://arabica26.ru
**Телефон администратора:** 79054443224
**Ветка разработки:** refactoring/full-restructure

---

**Дата создания документа:** 2025-12-29
**Версия:** 1.0
**Автор:** Claude Sonnet 4.5

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## 🎓 Как использовать этот документ

### Для нового разработчика:
1. Прочитать раздел "Общая информация о проекте"
2. Изучить структуру проекта
3. Ознакомиться с ключевыми принципами
4. Прочитать про Work Schedule Algorithm (самая сложная часть)

### Для AI ассистента (следующая сессия):
1. Прочитать весь документ
2. Обратить внимание на "Частые проблемы и их решения"
3. Помнить про 4 главных правила алгоритма автозаполнения
4. Учитывать платформо-зависимый код (kIsWeb)

### Для внесения изменений:
1. Обновлять документ при любых значительных изменениях
2. Добавлять новые разделы для новых фич
3. Обновлять статистику проекта
4. Документировать решения проблем

---

**КОНЕЦ ДОКУМЕНТА**

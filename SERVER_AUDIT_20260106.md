# АУДИТ СЕРВЕРА ARABICA
## Дата: 06.01.2026 (после модуляризации)

---

# ТЕКУЩЕЕ СОСТОЯНИЕ

## Структура сервера
```
/root/arabica_app/loyalty-proxy/
├── index.js                 (158 строк) - АКТУАЛЬНЫЙ
├── api/                     (20 модулей) - АКТУАЛЬНЫЕ
│   ├── recount_api.js       (8.9 KB)
│   ├── attendance_api.js    (4.0 KB)
│   ├── employees_api.js     (7.9 KB)
│   ├── shops_api.js         (4.6 KB)
│   ├── shifts_api.js        (14.9 KB)
│   ├── clients_api.js       (14.1 KB)
│   ├── work_schedule_api.js (4.4 KB)
│   ├── rko_api.js           (4.1 KB)
│   ├── training_api.js      (3.4 KB)
│   ├── tests_api.js         (5.8 KB)
│   ├── recipes_api.js       (3.9 KB)
│   ├── menu_api.js          (4.2 KB)
│   ├── orders_api.js        (10.7 KB) + Firebase
│   ├── product_questions_api.js (6.9 KB)
│   ├── reviews_api.js       (5.7 KB)
│   ├── media_api.js         (3.5 KB)
│   ├── loyalty_api.js       (6.7 KB)
│   ├── suppliers_api.js     (6.2 KB)
│   ├── envelope_api.js      (9.6 KB)
│   └── withdrawals_api.js   (5.0 KB)
├── firebase-service-account.json - НАСТРОЕН ✅
├── firebase-admin-config.js - НЕ ИСПОЛЬЗУЕТСЯ (дубль)
├── modules/orders.js        - СТАРЫЙ, НЕ ИСПОЛЬЗУЕТСЯ
├── product_questions_api.js - СТАРЫЙ, НЕ ИСПОЛЬЗУЕТСЯ (27.9 KB)
├── shift-transfers-api.js   - СТАРЫЙ, НЕ ИСПОЛЬЗУЕТСЯ (14.7 KB)
├── withdrawals_api.js       - СТАРЫЙ, НЕ ИСПОЛЬЗУЕТСЯ (6.6 KB)
└── index.js.backup_*        - 4 файла (836 KB)
```

---

# КРИТИЧЕСКИЕ ПРОБЛЕМЫ

## 1. ОТСУТСТВУЮЩИЕ API ENDPOINTS

Найдены данные в `/var/www/`, но API для них **НЕ СУЩЕСТВУЕТ** в новых модулях:

| Директория/Файл | Размер | Статус API |
|----------------|--------|------------|
| `/var/www/pending-recount-reports/` | 48 KB | **НЕТ API** |
| `/var/www/pending-shift-reports/` | 92 KB | **НЕТ API** |
| `/var/www/pending-shift-handover-reports.json` | 19 bytes | **НЕТ API** |
| `/var/www/shift-transfers.json` | 2.7 KB | **НЕТ API** |
| `/var/www/shop-coordinates/` | 8 KB | **НЕТ API** |
| `/var/www/loyalty-promo.json` | 173 bytes | **НЕТ API** |

### Рекомендация:
Добавить endpoints или проверить используются ли эти данные в приложении.

---

## 2. НЕИСПОЛЬЗУЕМЫЕ ФАЙЛЫ (МУСОР)

### Корневая папка сервера:
| Файл | Размер | Причина |
|------|--------|---------|
| `modules/orders.js` | 8.8 KB | Заменен на api/orders_api.js |
| `product_questions_api.js` | 27.9 KB | Заменен на api/product_questions_api.js |
| `shift-transfers-api.js` | 14.7 KB | НЕ ПОДКЛЮЧЕН к index.js |
| `withdrawals_api.js` | 6.6 KB | Заменен на api/withdrawals_api.js |
| `firebase-admin-config.js` | 748 bytes | Firebase теперь в orders_api.js |
| `debug.log` | 29 bytes | Старый лог |

### Backup файлы (836 KB):
- `index.js.backup_20260106_113611_before_envelope` (200 KB)
- `index.js.backup_20260106_224354_before_modular` (216 KB)
- `index.js.backup_20260106_WORKING` (208 KB)
- `index.js.backup_before_test_results` (212 KB)

**Итого мусора: ~900 KB**

---

## 3. ДУБЛИРОВАНИЕ КОДА

### Firebase инициализация:
- `firebase-admin-config.js` - старая версия
- `api/orders_api.js` - новая версия (актуальная)

### Product Questions:
- `product_questions_api.js` (корень) - 27.9 KB, старая
- `api/product_questions_api.js` - 6.9 KB, новая

### Withdrawals:
- `withdrawals_api.js` (корень) - 6.6 KB, старая
- `api/withdrawals_api.js` - 5.0 KB, новая

---

# ТОЧКИ УЛУЧШЕНИЯ

## Высокий приоритет:

### 1. Добавить недостающие API endpoints:

**a) Pending Reports API** (для отложенных отчетов):
```javascript
// Endpoints нужны:
GET/POST /api/pending-recount-reports
GET/POST /api/pending-shift-reports
GET/POST /api/pending-shift-handover-reports
```

**b) Shift Transfers API** (передача смен):
```javascript
// shift-transfers-api.js существует, но НЕ подключен
GET/POST /api/shift-transfers
PUT /api/shift-transfers/:id
DELETE /api/shift-transfers/:id
```

**c) Shop Coordinates API**:
```javascript
GET/POST /api/shop-coordinates/:shopAddress
```

**d) Loyalty Promo API**:
```javascript
GET/PUT /api/loyalty-promo
```

### 2. Очистить мусор:
```bash
# Удалить старые файлы
rm /root/arabica_app/loyalty-proxy/modules/orders.js
rm /root/arabica_app/loyalty-proxy/product_questions_api.js
rm /root/arabica_app/loyalty-proxy/withdrawals_api.js
rm /root/arabica_app/loyalty-proxy/firebase-admin-config.js
rm /root/arabica_app/loyalty-proxy/debug.log

# Оставить 1 backup, удалить остальные
rm /root/arabica_app/loyalty-proxy/index.js.backup_20260106_113611_before_envelope
rm /root/arabica_app/loyalty-proxy/index.js.backup_before_test_results
rm /root/arabica_app/loyalty-proxy/index.js.backup_20260106_WORKING
# Оставить: index.js.backup_20260106_224354_before_modular
```

## Средний приоритет:

### 3. Подключить shift-transfers-api.js
Файл существует и содержит полноценный API, но не подключен к index.js.

### 4. Проверить использование данных:
- `/var/www/pending-*` - используются ли pending отчеты?
- `/var/www/shop-coordinates/` - нужны ли координаты магазинов?

## Низкий приоритет:

### 5. Оптимизация хранения:
- `work-schedules/` хранит большие JSON файлы (240KB за месяц)
- Рассмотреть архивацию старых графиков

### 6. Очистка старых данных:
- `app-logs/` - 3.4 MB логов
- `test-questions/` - 296 файлов (1.2 MB)

---

# СТАТИСТИКА

## Размеры данных /var/www/:
| Категория | Размер |
|-----------|--------|
| chat-media | 5.0 MB |
| menu | 4.2 MB |
| recipe-photos | 3.9 MB |
| app-logs | 3.4 MB |
| shift-photos | 3.2 MB |
| employee-photos | 1.7 MB |
| test-questions | 1.2 MB |
| **Итого** | **~27 MB** |

## PM2 статус:
- Процесс: `loyalty-proxy`
- Статус: online
- Рестартов: 3
- Память: ~60 MB

---

# КОМАНДЫ ДЛЯ ОЧИСТКИ

```bash
# 1. Удалить старые файлы
ssh root@arabica26.ru "cd /root/arabica_app/loyalty-proxy && \
  rm -rf modules/ && \
  rm product_questions_api.js withdrawals_api.js firebase-admin-config.js debug.log && \
  rm index.js.backup_20260106_113611_before_envelope \
     index.js.backup_before_test_results \
     index.js.backup_20260106_WORKING"

# 2. Проверить результат
ssh root@arabica26.ru "ls -la /root/arabica_app/loyalty-proxy/"
```

---

# ЗАКЛЮЧЕНИЕ

**Что работает хорошо:**
- ✅ Модульная архитектура (20 модулей)
- ✅ Firebase настроен и работает
- ✅ Основные API endpoints функционируют
- ✅ index.js компактный (158 строк вместо 5800+)

**Что требует внимания:**
- ❌ 4-6 API endpoints отсутствуют (pending, shift-transfers, coordinates, promo)
- ❌ ~900 KB мусорных файлов
- ❌ Дублирование кода (firebase-admin-config, старые API файлы)

**Приоритет исправления:**
1. Добавить недостающие API endpoints (если используются в приложении)
2. Очистить мусорные файлы
3. Подключить shift-transfers-api.js

---

*Отчет сформирован: 06.01.2026*

# ПОЛНЫЙ АУДИТ СИСТЕМЫ ARABICA v2 (ИСПРАВЛЕННЫЙ)
## Дата: 06.01.2026
## Аналитик: Claude AI

---

# КРИТИЧЕСКАЯ НАХОДКА

## ПРЕДЫДУЩИЙ АУДИТ БЫЛ ОШИБОЧНЫМ!

Я анализировал **НЕПРАВИЛЬНЫЙ** серверный файл:
- `/root/loyalty-proxy/loyalty-proxy/index.js` (2802 строки) - **СТАРЫЙ, НЕАКТИВНЫЙ**

PM2 на самом деле запускает:
- `/root/arabica_app/loyalty-proxy/index.js` (5733 строки) - **АКТУАЛЬНЫЙ, РАБОЧИЙ**

---

# РЕАЛЬНОЕ СОСТОЯНИЕ СИСТЕМЫ

## 1. ВСЕ API ENDPOINTS СУЩЕСТВУЮТ И РАБОТАЮТ

После проверки ПРАВИЛЬНОГО сервера (`/root/arabica_app/loyalty-proxy/index.js`):

| Endpoint | Статус | Строки в коде | Тест |
|----------|--------|---------------|------|
| `/api/suppliers` | **РАБОТАЕТ** | 2192-2378 | Возвращает 6 поставщиков |
| `/api/envelope-reports` | **РАБОТАЕТ** | 5407-5573 | Возвращает 10+ отчетов |
| `/api/envelope-questions` | **РАБОТАЕТ** | 5628-5716 | OK |
| `/api/shift-reports` | **РАБОТАЕТ** | 3816-3868 | Возвращает 20+ отчетов |
| `/api/shift-handover-reports` | **РАБОТАЕТ** | 4197-4327 | OK |
| `/api/orders` | **РАБОТАЕТ** | 4476-4549 | OK |
| `/api/training-articles` | **РАБОТАЕТ** | 3868-3946 | OK |
| `/api/product-questions` | **РАБОТАЕТ** | 4584-4977 | OK |

**Всего на сервере: 129 API endpoints**

---

## 2. ДУБЛИРОВАНИЕ ПАПОК НА СЕРВЕРЕ (КРИТИЧЕСКАЯ ПРОБЛЕМА)

### Найдены ДВЕ разные директории:

| Папка | Размер | Статус |
|-------|--------|--------|
| `/root/arabica_app/` | **169 MB** | АКТИВНАЯ (PM2 запускает отсюда) |
| `/root/loyalty-proxy/` | **41 MB** | СТАРАЯ КОПИЯ (не используется!) |

### Содержимое старой папки `/root/loyalty-proxy/`:
- `loyalty-proxy/index.js` - 2802 строки (устаревший код)
- 65 файлов .md (документация)
- `node_modules/`
- Backup файлы

### Рекомендация:
**УДАЛИТЬ `/root/loyalty-proxy/`** - это старая копия, которая только запутывает.

---

## 3. BACKUP ФАЙЛЫ (МУСОР)

### В `/root/arabica_app/loyalty-proxy/` найдено 14 backup файлов:

```
index.js.backup                             (204 KB)
index.js.backup-20260102-212109             (145 KB)
index.js.backup-20260103-184515             (145 KB)
index.js.backup-20260103-190624             (154 KB)
index.js.backup-shop-settings               (145 KB)
index.js.backup_20260104_113902             (174 KB)
index.js.backup_20260104_125801             (190 KB)
index.js.backup_20260104_225143             (202 KB)
index.js.backup_20260106_113611_before_envelope (202 KB)
index.js.backup_20260106_WORKING            (209 KB)
index.js.backup_loyalty                     (183 KB)
index.js.backup_msg_20260103_223151         (160 KB)
index.js.backup_network_20260103_221002     (154 KB)
index.js.bak                                (183 KB)
```

**Суммарно: ~2.5 MB мусора**

### Рекомендация:
Оставить 1-2 последних backup, удалить остальные.

---

## 4. НЕИСПОЛЬЗУЕМЫЕ .md ФАЙЛЫ

Найдено **3664** файла .md на сервере!

В `/root/loyalty-proxy/` - 65 файлов .md
В `/root/arabica_app/` - 65 файлов .md (дубликаты)

Примеры:
- ALGORITHM_IMPROVEMENTS.md
- ALGORITHM_VERIFICATION.md
- APPLICATION_LOGIC.md
- BUGFIXES.md
- API_DOCUMENTATION.md
- и многие другие...

**Рекомендация:** Переместить в отдельную папку `/docs/` или удалить.

---

## 5. FLUTTER ПРИЛОЖЕНИЕ

### Найден 1 backup файл:
- `lib/features/employees/pages/employee_panel_page.dart.bak`

### Pending сервисы (возможно избыточны):
- `pending_shift_service.dart`
- `pending_shift_report_model.dart`
- `pending_recount_service.dart`
- `pending_recount_report_model.dart`

---

## 6. СТРУКТУРА ДАННЫХ /var/www/ (27 MB)

Самые большие папки:
```
5.0M  chat-media/       - Медиафайлы чатов
4.2M  menu/             - Меню (много файлов)
3.9M  recipe-photos/    - Фото рецептов
3.4M  app-logs/         - Логи приложения
3.2M  shift-photos/     - Фото смен
1.7M  employee-photos/  - Фото сотрудников
1.2M  test-questions/   - Тестовые вопросы
```

---

## 7. СЕРВЕРНЫЙ ФАЙЛ index.js (АКТУАЛЬНЫЙ)

- **Путь:** `/root/arabica_app/loyalty-proxy/index.js`
- **Размер:** 5733 строки (216 KB)
- **Endpoints:** 129
- **Модули:** `withdrawals_api.js` вынесен отдельно

### Проблемы:
1. Слишком большой файл - сложно поддерживать
2. Нет разделения на модули (кроме withdrawals)
3. Много повторяющегося кода для CRUD операций
4. Hardcoded пути (`/var/www/...`)

---

## 8. PM2 СТАТУС

```
┌────┬──────────────────┬─────────┬────────┬──────┬───────────┐
│ id │ name             │ mode    │ uptime │ ↺    │ status    │
├────┼──────────────────┼─────────┼────────┼──────┼───────────┤
│ 0  │ loyalty-proxy    │ fork    │ 6h+    │ 20   │ online    │
└────┴──────────────────┴─────────┴────────┴──────┴───────────┘

script path: /root/arabica_app/loyalty-proxy/index.js
exec cwd: /root/arabica_app/loyalty-proxy
node.js version: 20.19.5
```

---

# РЕКОМЕНДАЦИИ ПО ОЧИСТКЕ

## Высокий приоритет:

1. **Удалить старую папку:**
   ```bash
   rm -rf /root/loyalty-proxy/
   ```
   Это освободит 41 MB и уберет путаницу.

2. **Очистить backup файлы:**
   ```bash
   cd /root/arabica_app/loyalty-proxy/
   rm index.js.backup-20260102* index.js.backup-20260103* index.js.backup_20260104_113902 index.js.backup_20260104_125801
   ```
   Оставить только последние 2-3 backup.

## Средний приоритет:

3. **Удалить .md файлы или переместить:**
   ```bash
   mkdir /root/arabica_app/docs
   mv /root/arabica_app/*.md /root/arabica_app/docs/
   ```

4. **Удалить backup в Flutter:**
   ```bash
   rm lib/features/employees/pages/employee_panel_page.dart.bak
   ```

## Низкий приоритет:

5. **Модуляризация сервера** - разбить index.js на отдельные файлы

---

# ЗАКЛЮЧЕНИЕ

## Главные находки:

1. **API работает корректно** - все endpoints существуют на ПРАВИЛЬНОМ сервере
2. **Критическая путаница** - две папки `/root/loyalty-proxy/` и `/root/arabica_app/` вызывают ошибки при деплое
3. **Много мусора** - 14 backup файлов, 65+ .md файлов, старая папка

## Если функции не работают в приложении:

Проблема НЕ в API сервера (все endpoints есть), а скорее:
- В Flutter коде (неправильные пути или компоненты)
- В навигации между страницами
- В отсутствующих кнопках в UI

---

*Отчет сформирован: 06.01.2026 (версия 2 - исправленная)*

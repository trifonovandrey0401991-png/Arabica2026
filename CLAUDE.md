# Правила для Claude Code - Проект Arabica

## КРИТИЧЕСКИ ВАЖНО - LOCKED_CODE.md

**ПЕРЕД ЛЮБЫМИ ИЗМЕНЕНИЯМИ В КОДЕ** обязательно прочитай файл `LOCKED_CODE.md` в корне проекта!

Этот файл содержит список **защищённых файлов и функций**, которые:
- Полностью протестированы и работают
- НЕ ДОЛЖНЫ изменяться без явного разрешения пользователя
- Включают как Flutter код, так и серверный код

### Что делать перед изменениями:

1. **Прочитай LOCKED_CODE.md** - узнай какие файлы защищены
2. **Если файл в списке** - спроси разрешения у пользователя
3. **Создай бэкап** перед изменением защищённого кода
4. **Обнови LOCKED_CODE.md** после изменений

---

## Структура проекта

- **Flutter приложение**: `lib/` - мобильное приложение
- **Серверный код**: `loyalty-proxy/` - Node.js API сервер
- **Сервер**: `arabica26.ru` (root@arabica26.ru)

---

## Серверный код

Серверный код находится в `loyalty-proxy/`:
- `index.js` - основной сервер (3800+ строк)
- `modules/orders.js` - модуль заказов
- `firebase-admin-config.js` - конфиг Firebase

**При деплое на сервер:**
```bash
ssh root@arabica26.ru "cd /root/arabica_app && git pull origin refactoring/full-restructure"
ssh root@arabica26.ru "cp loyalty-proxy/index.js /root/arabica_app/loyalty-proxy/index.js"
ssh root@arabica26.ru "pm2 restart loyalty-proxy"
```

---

## Защищённые системы (краткий список)

| Версия | Система | Статус |
|--------|---------|--------|
| v1.5.0 | Заказы | Работает |
| v1.5.1 | Управление магазинами | Работает |
| v1.5.2 | Регистрация сотрудников | Работает |
| v1.5.3 | Пересменки (4 вкладки) | Работает |
| v1.5.4 | Пересчёты (4 вкладки) | Работает |
| v1.5.5 | Статьи обучения | Работает |

**Полный список в LOCKED_CODE.md**

---

## ПРАВИЛА ДЕПЛОЯ (КРИТИЧЕСКИ ВАЖНО!)

### Перед выгрузкой в Git:

1. **НЕ ДЕЛАТЬ `git reset --hard`** на сервере без бэкапа!
2. **Проверить что серверный код синхронизирован** - `loyalty-proxy/index.js` должен быть актуальным в репозитории
3. **Если изменял серверный код** - сначала скачай актуальную версию с сервера:
   ```bash
   ssh root@arabica26.ru "cat /root/arabica_app/loyalty-proxy/index.js" > loyalty-proxy/index.js
   ```

### Безопасный деплой на сервер:

**ШАГ 1: Создать бэкап на сервере**
```bash
ssh root@arabica26.ru "cp /root/arabica_app/loyalty-proxy/index.js /root/arabica_app/loyalty-proxy/index.js.backup-$(date +%Y%m%d-%H%M%S)"
```

**ШАГ 2: Обновить код (БЕЗ reset --hard!)**
```bash
ssh root@arabica26.ru "cd /root/arabica_app && git fetch origin && git pull origin refactoring/full-restructure"
```

**ШАГ 3: Перезапустить сервер**
```bash
ssh root@arabica26.ru "pm2 restart loyalty-proxy && pm2 logs loyalty-proxy --lines 10 --nostream"
```

**ШАГ 4: Проверить что сервер работает**
- Логи должны показать "Proxy listening on port 3000"
- Не должно быть ошибок MODULE_NOT_FOUND

### Если что-то сломалось:

**Откат из бэкапа:**
```bash
ssh root@arabica26.ru "cp /root/arabica_app/loyalty-proxy/index.js.backup-YYYYMMDD /root/arabica_app/loyalty-proxy/index.js && pm2 restart loyalty-proxy"
```

### НИКОГДА НЕ ДЕЛАТЬ:

- `git reset --hard` на сервере без бэкапа
- Заменять index.js на уменьшенную версию
- Удалять папку `modules/` на сервере
- Деплоить без проверки что сервер запустился

---

## Напоминание

При долгом диалоге контекст может теряться. Если сомневаешься - **перечитай LOCKED_CODE.md**!

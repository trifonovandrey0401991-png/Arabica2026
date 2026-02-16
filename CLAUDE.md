# Правила для Claude Code - Проект Arabica

Ты — опытный разработчик, помогающий человеку БЕЗ опыта в программировании.
Объясняй всё простым языком. Если используешь термин — сразу поясни что он значит.

---

## 🔴 ГЛАВНОЕ ПРАВИЛО

```
ЕСЛИ КОД РАБОТАЕТ — НЕ ТРОГАЙ ЕГО БЕЗ МОЕГО РАЗРЕШЕНИЯ
```

---

## 📚 ОБЯЗАТЕЛЬНО ЧИТАЙ ПЕРЕД РАБОТОЙ

| Файл | Что содержит | Когда читать |
|------|--------------|--------------|
| `ARCHITECTURE_COMPLETE.md` | ВСЯ архитектура: 35 модулей, 240+ API, 8 schedulers | **Перед ЛЮБЫМ изменением** |
| `PROJECT_MAP.md` | Карта зависимостей: что от чего зависит, что сломается | **Перед изменением любого файла** |

---



---

## 🎯 ПРИОРИТЕТЫ

```
1. 🔴 НЕ СЛОМАТЬ
2. 🟠 Сделать что просят
3. 🟡 Сделать правильно
4. 🟢 Сделать красиво (если просят)
```

---

## 🚀 ДЕПЛОЙ (только с разрешения!)

```bash
ssh root@arabica26.ru "cp /root/arabica_app/loyalty-proxy/index.js /root/arabica_app/loyalty-proxy/index.js.backup-$(date +%Y%m%d-%H%M%S)"
ssh root@arabica26.ru "cd /root/arabica_app && git pull origin refactoring/full-restructure"
ssh root@arabica26.ru "pm2 restart loyalty-proxy"
ssh root@arabica26.ru "pm2 logs loyalty-proxy --lines 20 --nostream"
# После деплоя — обязательно:
node tests/api-test.js   # Все 55 эндпоинтов должны быть OK
```

---

## 🧪 ТЕСТИРОВАНИЕ

```
Запуск всех тестов: tests/run-all-tests.bat

Уровень 1 — Smoke:     HTTP 200 от всех эндпоинтов
Уровень 2 — Structure:  Правильный формат ответа (поля, тип)
Уровень 3 — Analyze:    flutter analyze без ошибок

Тесты: tests/api-test.js (55 эндпоинтов)
Раннер: tests/run-all-tests.bat (все 3 уровня)

⚠️ ЕСЛИ ТЕСТЫ НЕ ПРОХОДЯТ — НЕ ГОВОРИ "ГОТОВО"!
```

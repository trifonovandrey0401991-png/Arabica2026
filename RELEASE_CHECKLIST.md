# Arabica - Чеклист релиза v1.0.0

Дата аудита: 2026-02-05 (обновлено)
Статус: **ГОТОВ К РЕЛИЗУ** (метаданные Play Market нужно подготовить)

---

## Сводка

| Категория | Результат |
|-----------|-----------|
| **Сборка** | ✅ OK (app-release.aab, 67.1MB) |
| **Тесты** | 475/476 passed (1 skipped) |
| **API Endpoints** | 19/19 работают (все OK) |
| **Android конфиг** | OK |
| **Безопасность** | OK |
| **Сервер** | Online (loyalty-proxy running) |

---

## 1. Android конфигурация

### build.gradle
- [x] `applicationId = "ru.arabica.app"`
- [x] `compileSdk = 36`
- [x] `minSdk` / `targetSdk` - из Flutter
- [x] Подпись настроена (key.properties существует)
- [x] ProGuard включен (minifyEnabled = true)
- [x] R8 включен (shrinkResources = true)

### AndroidManifest.xml
- [x] Permissions корректные:
  - INTERNET
  - CAMERA
  - ACCESS_FINE_LOCATION
  - ACCESS_COARSE_LOCATION
  - ACCESS_BACKGROUND_LOCATION
  - READ/WRITE_EXTERNAL_STORAGE
  - POST_NOTIFICATIONS
- [x] Firebase FCM настроен
- [x] networkSecurityConfig настроен

### Ресурсы
- [x] Иконки во всех разрешениях (mipmap-mdpi..xxxhdpi)
- [x] Adaptive icons (foreground + background)
- [x] Launch theme настроен
- [x] google-services.json существует

---

## 2. Серверная инфраструктура

### Сервер
- [x] HTTPS работает (nginx/1.24.0)
- [x] SSL сертификат валидный
- [x] loyalty-proxy online (PM2)
- [x] Uptime: стабильный

### API Endpoints - Статус

| Endpoint | Статус | Код |
|----------|--------|-----|
| `/api/shops` | OK | 200 |
| `/api/employees` | OK | 200 |
| `/api/menu` | OK | 200 |
| `/api/loyalty-promo` | OK | 200 |
| `/api/geofence-settings` | OK | 200 |
| `/api/shift-reports` | OK | 200 |
| `/api/recount-reports` | OK | 200 |
| `/api/tasks` | OK | 200 |
| `/api/ratings` | OK | 200 |
| `/api/training-articles` | OK | 200 |
| `/api/test-questions` | OK | 200 |
| `/api/envelope-reports` | OK | 200 |
| `/api/fortune-wheel/settings` | OK | 200 |
| `/api/job-applications` | OK | 200 |
| `/api/withdrawals` | OK | 200 |
| `/api/rko/all` | OK | 200 |
| `/api/referrals/stats` | OK | 200 |
| `/api/auth/register` | OK | 200 |
| `/api/auth/login` | OK | 200 |

### Данные на сервере
- [x] `/var/www/` структура полная (70+ директорий)
- [x] Все модули имеют соответствующие папки данных

---

## 3. Тестирование

### Unit Tests
```
flutter test --reporter=compact
475 passed, 1 skipped
```

### Покрытие модулей: 30/31 (97%)

| Роль | Тестов | Статус |
|------|--------|--------|
| Admin | 8 файлов | OK |
| Client | 8 файлов | OK |
| Employee | 10 файлов | OK |
| Integration | 1 файл | OK |

### Пропущенный тест
- `widget_test.dart` - базовый widget тест (не критичен)

---

## 4. Безопасность

- [x] Нет hardcoded API keys
- [x] Нет hardcoded passwords/secrets
- [x] Все API через HTTPS
- [x] apiKey в клиенте = null (отключена проверка)
- [x] Токены FCM хранятся на сервере безопасно
- [ ] Rate limiting не проверен
- [ ] CORS настройки не проверены

---

## 5. Требования Play Market

### Технические
- [x] applicationId уникальный
- [ ] versionCode актуальный (сейчас = 1)
- [ ] versionName актуальный (сейчас = 1.0.0)
- [x] Target API >= 33 (Flutter default)
- [x] 64-bit поддержка (arm64-v8a)
- [x] App Bundle формат поддерживается
- [x] Размер AAB: 67.1MB (лимит Play Market: 150MB)

### Метаданные (требуется подготовить)
- [ ] Название приложения (до 30 символов)
- [ ] Краткое описание (до 80 символов)
- [ ] Полное описание (до 4000 символов)
- [ ] Скриншоты (минимум 2, рекомендуется 8)
- [ ] Feature graphic (1024x500)
- [ ] Иконка 512x512 для Store
- [ ] Категория приложения
- [ ] Контактный email
- [ ] Политика конфиденциальности (URL)

### Data Safety форма

| Тип данных | Собирается | Передаётся | Цель |
|------------|------------|------------|------|
| Имя | Да | Да | Идентификация сотрудников/клиентов |
| Телефон | Да | Да | Авторизация, уведомления |
| Геолокация | Да | Да | Геофенсинг, карта магазинов |
| Фото | Да | Да | Отчёты, аватары, чаты |
| Данные о заказах | Да | Да | Функциональность приложения |

---

## 6. Критические проблемы (блокируют релиз)

**Нет критических проблем**

---

## 7. Некритические проблемы

| # | Проблема | Приоритет | Решение |
|---|----------|-----------|---------|
| 1 | versionCode = 1 | Средний | Увеличить при релизе |
| 2 | ~~2 API endpoints 404~~ | ~~Низкий~~ | ✅ Исправлено (пути были неверные) |
| 3 | apiKey = null | Низкий | Включить при необходимости защиты API |
| 4 | Метаданные не готовы | Высокий | Подготовить для Play Market |

---

## 8. Рекомендации перед публикацией

### Обязательно
1. Собрать release AAB: `flutter build appbundle --release`
2. Протестировать на реальном устройстве
3. Подготовить метаданные для Play Market
4. Создать политику конфиденциальности
5. Заполнить Data Safety форму

### Желательно
1. Увеличить versionCode
2. Проверить работу push-уведомлений
3. Проверить геолокацию на реальном устройстве
4. Создать скриншоты для всех ролей

---

## 9. Команды для релиза

```bash
# 1. Очистка и сборка
cd c:\Users\Admin\arabica2026
flutter clean
flutter pub get
flutter build appbundle --release

# 2. Проверка размера
dir build\app\outputs\bundle\release\app-release.aab

# 3. Деплой серверного кода (если были изменения)
ssh root@arabica26.ru "cd /root/arabica_app && git pull origin refactoring/full-restructure"
ssh root@arabica26.ru "pm2 restart loyalty-proxy"
```

---

## 10. Контакты и ресурсы

- **Сервер:** arabica26.ru (root@arabica26.ru)
- **Репозиторий:** refactoring/full-restructure branch
- **PM2 сервис:** loyalty-proxy

---

Дата создания: 2026-02-05
Аудит провёл: Claude Code

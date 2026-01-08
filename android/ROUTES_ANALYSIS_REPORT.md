# ОТЧЁТ: Анализ потерянных маршрутов и неиспользуемых данных

**Дата:** 2026-01-08
**Автор:** Claude Code (анализ)

---

## РЕЗЮМЕ

| Источник | Количество маршрутов |
|----------|---------------------|
| Текущий index.js (на сервере) | 107 |
| Backup index.js | 119 |
| API модули (/api/ папка) | 221 |
| **Потенциально потеряно** | **114** |

---

## 1. МАРШРУТЫ, ПОТЕРЯННЫЕ ПО СРАВНЕНИЮ С BACKUP

Эти 12 маршрутов есть в backup, но **ОТСУТСТВУЮТ** в текущем index.js:

### 1.1 Envelope Questions (Вопросы конвертов)
| Метод | Маршрут | Статус |
|-------|---------|--------|
| GET | `/api/envelope-questions` | ❌ ПОТЕРЯН |
| GET | `/api/envelope-questions/:id` | ❌ ПОТЕРЯН |
| POST | `/api/envelope-questions` | ❌ ПОТЕРЯН |
| PUT | `/api/envelope-questions/:id` | ❌ ПОТЕРЯН |
| DELETE | `/api/envelope-questions/:id` | ❌ ПОТЕРЯН |

**Влияние:** Невозможно управлять вопросами для формирования конвертов.

### 1.2 Product Questions (Поиск товара)
| Метод | Маршрут | Статус |
|-------|---------|--------|
| GET | `/api/product-questions` | ❌ ПОТЕРЯН |
| GET | `/api/product-questions/:id` | ❌ ПОТЕРЯН |
| GET | `/api/product-questions/client/:phone` | ❌ ПОТЕРЯН |
| POST | `/api/product-questions` | ❌ ПОТЕРЯН |
| POST | `/api/product-questions/:id/messages` | ❌ ПОТЕРЯН |
| POST | `/api/product-questions/client/:phone/reply` | ❌ ПОТЕРЯН |
| POST | `/api/product-questions/upload-photo` | ❌ ПОТЕРЯН |

**Влияние:** Функционал "Поиск товара" (запросы от клиентов) полностью не работает.

### 1.3 Test Results (Результаты тестов)
| Метод | Маршрут | Статус |
|-------|---------|--------|
| GET | `/api/test-results` | ❌ ПОТЕРЯН |
| POST | `/api/test-results` | ❌ ПОТЕРЯН |

**Влияние:** Невозможно сохранять и получать результаты тестирования сотрудников.

### 1.4 Clients
| Метод | Маршрут | Статус |
|-------|---------|--------|
| GET | `/api/clients` | ❌ ПОТЕРЯН (в текущем есть POST но нет GET) |

**Влияние:** Невозможно получить список клиентов.

---

## 2. МАРШРУТЫ ИЗ API МОДУЛЕЙ, НЕ ПОДКЛЮЧЁННЫЕ К СЕРВЕРУ

Папка `/root/arabica_app/loyalty-proxy/api/` содержит **221 маршрут**, но index.js **НЕ ИМПОРТИРУЕТ** эти модули. Это значит, что весь функционал API модулей недоступен.

### 2.1 Критически важные недоступные маршруты:

#### Loyalty (Программа лояльности)
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/loyalty/balance/:phone` | Баланс баллов клиента |
| GET | `/api/loyalty/transactions/:phone` | История транзакций |
| POST | `/api/loyalty/add-points` | Начислить баллы |
| POST | `/api/loyalty/spend-points` | Списать баллы |

#### FCM Tokens
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/fcm-tokens` | Получить токены |
| DELETE | `/api/fcm-tokens/:phone` | Удалить токен |

#### Pending Reports (Непройденные отчёты)
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/pending-recount-reports` | Непройденные пересчёты |
| GET | `/api/pending-recount-reports/:reportId` | Конкретный пересчёт |
| POST | `/api/pending-recount-reports` | Создать запись |
| PUT | `/api/pending-recount-reports/:reportId` | Обновить |
| DELETE | `/api/pending-recount-reports/:reportId` | Удалить |
| GET | `/api/pending-shift-handover-reports` | Непройденные сдачи смен |
| POST | `/api/pending-shift-handover-reports` | Создать запись |
| DELETE | `/api/pending-shift-handover-reports/:reportId` | Удалить |
| GET | `/api/pending-shift-reports` | Непройденные пересменки |
| GET | `/api/pending-shift-reports/:reportId` | Конкретная пересменка |
| POST | `/api/pending-shift-reports` | Создать запись |
| POST | `/api/pending-shift-reports/:reportId/complete` | Завершить |
| POST | `/api/pending-shift-reports/generate` | Сгенерировать |
| PUT | `/api/pending-shift-reports/:reportId` | Обновить |
| DELETE | `/api/pending-shift-reports/:reportId` | Удалить |

#### Points Settings (Настройки баллов)
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET/POST | `/api/points-settings/attendance` | Баллы за посещаемость |
| GET/POST | `/api/points-settings/orders` | Баллы за заказы |
| GET/POST | `/api/points-settings/product-search` | Баллы за поиск товара |
| GET/POST | `/api/points-settings/recount` | Баллы за пересчёт |
| GET/POST | `/api/points-settings/reviews` | Баллы за отзывы |
| GET/POST | `/api/points-settings/rko` | Баллы за РКО |
| GET/POST | `/api/points-settings/shift` | Баллы за пересменку |
| GET/POST | `/api/points-settings/shift-handover` | Баллы за сдачу смены |
| GET/POST | `/api/points-settings/test` | Баллы за тестирование |
| GET | `/api/points-settings/*/calculate` | Расчёт баллов |

#### Shop Coordinates (Геолокация магазинов)
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/shop-coordinates` | Все координаты |
| GET | `/api/shop-coordinates/:shopAddress` | Координаты магазина |
| POST | `/api/shop-coordinates` | Добавить |
| POST | `/api/shop-coordinates/check-proximity` | Проверка близости |
| PUT | `/api/shop-coordinates/:shopAddress` | Обновить |
| DELETE | `/api/shop-coordinates/:shopAddress` | Удалить |

#### Shift Reports (Пересменки)
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/shift-reports/:reportId` | Конкретный отчёт |
| PUT | `/api/shift-reports/:reportId` | Обновить отчёт |
| DELETE | `/api/shift-reports/:reportId` | Удалить отчёт |

#### Shift Transfers (Переносы смен)
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/shift-transfers` | Все переносы |
| GET | `/api/shift-transfers/:transferId` | Конкретный перенос |
| POST | `/api/shift-transfers` | Создать перенос |
| POST | `/api/shift-transfers/:transferId/approve` | Одобрить |
| POST | `/api/shift-transfers/:transferId/reject` | Отклонить |
| PUT | `/api/shift-transfers/:transferId` | Обновить |
| DELETE | `/api/shift-transfers/:transferId` | Удалить |

#### RKO Reports (Отчёты РКО)
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/rko-reports` | Все отчёты |
| GET | `/api/rko-reports/:reportId` | Конкретный отчёт |
| POST | `/api/rko-reports` | Создать |
| PUT | `/api/rko-reports/:reportId` | Обновить |
| DELETE | `/api/rko-reports/:reportId` | Удалить |

#### Withdrawals (Изъятия из кассы)
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/withdrawals` | Все изъятия |
| GET | `/api/withdrawals/:withdrawalId` | Конкретное изъятие |
| POST | `/api/withdrawals` | Создать |
| DELETE | `/api/withdrawals/:withdrawalId` | Удалить |

#### Work Schedule Templates
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/work-schedule-templates` | Все шаблоны |
| POST | `/api/work-schedule-templates` | Создать |
| DELETE | `/api/work-schedule-templates/:templateId` | Удалить |

#### Client Dialogs (Расширенные)
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/client-dialogs/:phone` | Диалоги клиента |
| GET | `/api/client-dialogs/:phone/management` | Управленческие диалоги |
| GET | `/api/client-dialogs/:phone/network` | Сетевые диалоги |
| GET | `/api/client-dialogs/:phone/shop/:shopAddress` | Диалоги по магазину |
| POST | `/api/client-dialogs/:phone/management/read-by-client` | Прочитано клиентом |
| POST | `/api/client-dialogs/:phone/management/read-by-manager` | Прочитано менеджером |
| POST | `/api/client-dialogs/:phone/management/reply` | Ответ |
| POST | `/api/client-dialogs/:phone/management/send` | Отправка |
| POST | `/api/client-dialogs/:phone/network/read-by-admin` | Прочитано админом |
| POST | `/api/client-dialogs/:phone/network/read-by-client` | Прочитано клиентом |
| POST | `/api/client-dialogs/:phone/network/reply` | Ответ |
| POST | `/api/client-dialogs/:phone/shop/:shopAddress/messages` | Сообщения |

#### Employee Chats
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/employee-chats` | Все чаты |
| GET | `/api/employee-chats/:chatId/messages` | Сообщения чата |
| POST | `/api/employee-chats/:chatId/messages` | Отправить сообщение |
| POST | `/api/employee-chats/:chatId/read` | Прочитать |
| POST | `/api/employee-chats/private` | Создать приватный чат |
| POST | `/api/employee-chats/shop` | Создать чат магазина |
| DELETE | `/api/employee-chats/:chatId/messages/:messageId` | Удалить сообщение |

#### Clients Messages
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/clients/:phone/messages` | Сообщения клиента |
| POST | `/api/clients/:phone/messages` | Отправить сообщение |
| POST | `/api/clients/messages/broadcast` | Массовая рассылка |

#### Recount Reports (Расширенные)
| Метод | Маршрут | Описание |
|-------|---------|----------|
| POST | `/api/recount-reports/:reportId/notify` | Уведомить |
| POST | `/api/recount-reports/:reportId/rating` | Оценить |

#### Reviews (Расширенные)
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/reviews/stats/:shopAddress` | Статистика отзывов |
| PUT | `/api/reviews/:reviewId` | Обновить |
| DELETE | `/api/reviews/:reviewId` | Удалить |

#### QR Scan
| Метод | Маршрут | Описание |
|-------|---------|----------|
| POST | `/api/qr-scan` | Сканирование QR |

#### Push Notifications
| Метод | Маршрут | Описание |
|-------|---------|----------|
| POST | `/api/send-push` | Отправить уведомление |
| POST | `/api/send-push/broadcast` | Массовая отправка |

#### Menu Categories
| Метод | Маршрут | Описание |
|-------|---------|----------|
| GET | `/api/menu-categories` | Категории меню |

---

## 3. ДАННЫЕ НА СЕРВЕРЕ БЕЗ API МАРШРУТОВ

### 3.1 Директории с данными в /var/www/

| Директория | Есть API? | Проблема |
|------------|-----------|----------|
| `app-logs` | ✅ Частично | Только POST для записи |
| `attendance` | ✅ | Работает |
| `chat-media` | ❌ | Нет API для управления |
| `client-dialogs` | ⚠️ | API есть в модулях, но не подключён |
| `client-messages` | ⚠️ | API есть в модулях, но не подключён |
| `client-messages-management` | ⚠️ | API есть в модулях, но не подключён |
| `client-messages-network` | ⚠️ | API есть в модулях, но не подключён |
| `clients` | ⚠️ | POST есть, GET отсутствует |
| `employee-chats` | ⚠️ | API есть в модулях, но не подключён |
| `employee-photos` | ✅ | upload-employee-photo работает |
| `employee-registrations` | ✅ | Работает |
| `employees` | ✅ | Работает |
| `envelope-question-photos` | ❌ | API удалён |
| `envelope-questions` | ❌ | API удалён |
| `envelope-reports` | ✅ | Восстановлено |
| `fcm-tokens` | ⚠️ | Только POST, нет GET/DELETE |
| `loyalty-promo.json` | ⚠️ | API есть в модулях, но не подключён |
| `loyalty-transactions` | ⚠️ | API есть в модулях, но не подключён |
| `menu` | ✅ | Работает |
| `orders` | ✅ | Работает |
| `pending-recount-reports` | ⚠️ | API есть в модулях, но не подключён |
| `pending-shift-handover-reports.json` | ⚠️ | API есть в модулях, но не подключён |
| `pending-shift-reports` | ⚠️ | API есть в модулях, но не подключён |
| `points-settings` | ⚠️ | API есть в модулях, но не подключён |
| `product-question-dialogs` | ❌ | API удалён |
| `product-question-photos` | ❌ | API удалён |
| `product-questions` | ❌ | API удалён |
| `recipe-photos` | ✅ | Работает |
| `recipes` | ✅ | Работает |
| `recount-question-photos` | ✅ | Работает |
| `recount-questions` | ✅ | Работает |
| `recount-reports` | ✅ | Работает |
| `reviews` | ✅ | Работает |
| `rko-files` | ✅ | Работает |
| `rko-reports` | ⚠️ | API есть в модулях, но не подключён |
| `shift-handover-question-photos` | ✅ | Работает |
| `shift-handover-questions` | ✅ | Работает |
| `shift-handover-reports` | ✅ | Восстановлено (PUT добавлен) |
| `shift-photos` | ✅ | upload-photo работает |
| `shift-question-photos` | ✅ | Работает |
| `shift-questions` | ✅ | Работает |
| `shift-reference-photos` | ⚠️ | Неясно, используется ли |
| `shift-reports` | ✅ | Работает |
| `shift-transfers.json` | ⚠️ | API есть в модулях, но не подключён |
| `shop-coordinates` | ⚠️ | API есть в модулях, но не подключён |
| `shop-settings` | ✅ | Работает |
| `shop-settings-photos` | ⚠️ | Нет отдельного API |
| `shops` | ✅ | Работает |
| `suppliers` | ✅ | Работает |
| `test-questions` | ✅ | Работает |
| `test-results` | ❌ | API удалён |
| `training-articles` | ✅ | Работает |
| `withdrawals` | ⚠️ | API есть в модулях, но не подключён |
| `work-schedule-templates` | ⚠️ | API есть в модулях, но не подключён |
| `work-schedules` | ✅ | Работает |

---

## 4. FLUTTER СЕРВИСЫ БЕЗ СЕРВЕРНЫХ ENDPOINTS

Сервисы в приложении, которые вызывают API endpoints, отсутствующие на сервере:

| Flutter сервис | Endpoint | Статус |
|----------------|----------|--------|
| `pending_shift_service.dart` | `/api/pending-shift-reports` | ❌ НЕ РАБОТАЕТ |
| `pending_recount_service.dart` | `/api/pending-recount-reports` | ❌ НЕ РАБОТАЕТ |
| `pending_shift_handover_service.dart` | `/api/pending-shift-handover-reports` | ❌ НЕ РАБОТАЕТ |
| `shift_transfer_service.dart` | `/api/shift-transfers` | ❌ НЕ РАБОТАЕТ |
| `points_settings_service.dart` | `/api/points-settings/*` | ❌ НЕ РАБОТАЕТ |
| `withdrawal_service.dart` | `/api/withdrawals` | ❌ НЕ РАБОТАЕТ |
| `test_result_service.dart` | `/api/test-results` | ❌ НЕ РАБОТАЕТ |
| `product_question_service.dart` | `/api/product-questions` | ❌ НЕ РАБОТАЕТ |
| `envelope_question_service.dart` | `/api/envelope-questions` | ❌ НЕ РАБОТАЕТ |
| `employee_chat_service.dart` | `/api/employee-chats` | ❌ НЕ РАБОТАЕТ |
| `loyalty_service.dart` | `/api/loyalty-promo`, `/api/loyalty/*` | ⚠️ ЧАСТИЧНО |
| `network_message_service.dart` | `/api/client-dialogs/*/network/*` | ❌ НЕ РАБОТАЕТ |
| `management_message_service.dart` | `/api/client-dialogs/*/management/*` | ❌ НЕ РАБОТАЕТ |
| `client_dialog_service.dart` | `/api/client-dialogs/*` | ❌ НЕ РАБОТАЕТ |
| `client_service.dart` | `/api/client-dialogs/*/network/read-by-admin` | ❌ НЕ РАБОТАЕТ |

---

## 5. ПРИЧИНА ПРОБЛЕМЫ

### Архитектура сервера:

```
/root/arabica_app/loyalty-proxy/
├── index.js           # АКТИВНЫЙ файл (107 маршрутов)
├── index.js.backup_*  # Бэкапы (119 маршрутов)
└── api/               # НЕ ИСПОЛЬЗУЕТСЯ (221 маршрут)
    ├── shifts_api.js
    ├── envelope_api.js
    ├── loyalty_api.js
    ├── pending_api.js
    ├── points_api.js
    └── ... и другие
```

**Проблема:** Файл `index.js` НЕ импортирует модули из папки `/api/`. Все эти модули были созданы для модульной архитектуры, но переход на неё не был завершён.

---

## 6. РЕКОМЕНДАЦИИ (НЕ ИСПРАВЛЕНИЯ)

### Вариант 1: Добавить import модулей в index.js
Добавить в начало index.js:
```javascript
// Импорт API модулей
require('./api/shifts_api')(app);
require('./api/envelope_api')(app);
// ... и так далее
```

### Вариант 2: Добавить маршруты напрямую
Скопировать код маршрутов из папки /api/ в index.js.

### Вариант 3: Восстановить из backup
Использовать backup как основу и добавить недостающий функционал.

---

## 7. ПРИОРИТЕТ ВОССТАНОВЛЕНИЯ

### Критический (блокирует основной функционал):
1. `/api/pending-shift-reports` - "Не пройдены" для пересменок
2. `/api/pending-recount-reports` - "Не пройдены" для пересчётов
3. `/api/pending-shift-handover-reports` - "Не пройдены" для сдачи смен
4. `/api/test-results` - Сохранение результатов тестов
5. `/api/points-settings/*` - Настройки баллов эффективности
6. `/api/envelope-questions` - Вопросы для конвертов

### Высокий (важный функционал):
7. `/api/product-questions` - Поиск товара
8. `/api/employee-chats` - Чаты сотрудников
9. `/api/shift-transfers` - Переносы смен
10. `/api/withdrawals` - Изъятия из кассы
11. `/api/client-dialogs/*` - Диалоги с клиентами

### Средний:
12. `/api/loyalty/*` - Расширенная лояльность
13. `/api/shop-coordinates` - Геолокация магазинов
14. `/api/rko-reports` - Отчёты РКО

---

## СТАТИСТИКА

- **Текущих маршрутов:** 107
- **Потеряно из backup:** 12
- **Не подключено из /api/:** 114
- **Всего недоступных маршрутов:** ~126
- **Директорий с данными:** 55
- **Директорий без API:** ~20
- **Flutter сервисов с проблемами:** 15

---

*Отчёт сгенерирован автоматически. Исправления НЕ вносились.*

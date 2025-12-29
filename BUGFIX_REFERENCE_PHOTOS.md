# Исправление ошибок с эталонными фото и фоновым изображением

## Дата: 30 декабря 2024

## Обнаруженные проблемы

### 1. Отсутствие фонового изображения
**Симптом:**
```
Error: Unable to load asset: "assets/images/arabica_background.png"
HTTP status 404
```

**Причина:** Файл `arabica_background.png` отсутствовал в assets/images/

**Решение:**
- Создан Python скрипт `android/create_background.py` для генерации фонового изображения
- Сгенерирован градиентный фон (1920x1080px) с цветами #004D40 → #00695C
- Файл успешно создан: `assets/images/arabica_background.png` (8.5KB)

### 2. Отсутствие поля `referencePhotos` в API
**Симптом:**
```
❌ referencePhotos пуст или null
! Нет эталонного фото в вопросе для магазина
```

**Причина:** API endpoints для shift-questions и recount-questions не были реализованы

**Решение:** Добавлены полноценные CRUD API в `loyalty-proxy/index.js`

## Реализованные API

### API для вопросов пересчета (Recount Questions)
- `GET /api/recount-questions` - получить все вопросы
- `POST /api/recount-questions` - создать вопрос
- `PUT /api/recount-questions/:id` - обновить вопрос
- `POST /api/recount-questions/:id/reference-photo` - загрузить эталонное фото
- `DELETE /api/recount-questions/:id` - удалить вопрос

### API для вопросов пересменки (Shift Questions)
- `GET /api/shift-questions` - получить все вопросы (с фильтром по магазину)
- `GET /api/shift-questions/:id` - получить один вопрос
- `POST /api/shift-questions` - создать вопрос
- `PUT /api/shift-questions/:id` - обновить вопрос
- `POST /api/shift-questions/:id/reference-photo` - загрузить эталонное фото
- `DELETE /api/shift-questions/:id` - удалить вопрос

## Особенности реализации

### Хранение данных
- **Формат:** JSON файлы
- **Расположение:**
  - Recount questions: `/var/www/recount-questions/*.json`
  - Shift questions: `/var/www/shift-questions/*.json`
  - Фотографии: `/var/www/shift-photos/*.jpg`

### Структура referencePhotos
```json
{
  "referencePhotos": {
    "Ессентуки, ул Пятигорская 149/1": "https://arabica26.ru/shift-photos/photo1.jpg",
    "Другой адрес магазина": "https://arabica26.ru/shift-photos/photo2.jpg"
  }
}
```

Ключ - полный адрес магазина, значение - URL эталонного фото для этого магазина.

### Нормализация адресов
Клиентский код уже содержит функцию `_normalizeShopAddress()` для корректного сопоставления адресов:
- Приведение к нижнему регистру
- Удаление лишних пробелов
- Нормализация для поиска совпадений

## Что изменено

### Серверная часть (loyalty-proxy/index.js)
- **Добавлено:** 259 строк кода
- **Новые endpoints:** 10 API endpoints
- **Новые директории:** 2 (recount-questions, shift-questions)

### Клиентская часть
- **Исправлено:** Отсутствие фонового изображения
- **Готово к работе:** Код для работы с referencePhotos уже реализован

### Документация
- Создан файл `API_DOCUMENTATION.md` с описанием всех endpoints
- Создан файл `android/create_background.py` для генерации фона

## Следующие шаги

### Для запуска на сервере:
1. Скопировать обновленный `loyalty-proxy/index.js` на сервер
2. Перезапустить Node.js сервер
3. Создать тестовые вопросы через API
4. Загрузить эталонные фото для тестирования

### Для миграции существующих данных:
Если вопросы уже существуют в Google Sheets, нужно:
1. Экспортировать данные из Google Sheets
2. Создать JSON файлы через POST API
3. Загрузить эталонные фото через API

## Проверка работоспособности

### Тест 1: Создание вопроса
```bash
curl -X POST https://arabica26.ru/api/shift-questions \
  -H "Content-Type: application/json" \
  -d '{
    "question": "Тестовый вопрос",
    "answerFormatB": "photo",
    "shops": ["Ессентуки, ул Пятигорская 149/1"]
  }'
```

### Тест 2: Загрузка эталонного фото
```bash
curl -X POST https://arabica26.ru/api/shift-questions/QUESTION_ID/reference-photo \
  -F "photo=@/path/to/photo.jpg" \
  -F "shopAddress=Ессентуки, ул Пятигорская 149/1"
```

### Тест 3: Получение вопросов
```bash
curl https://arabica26.ru/api/shift-questions
```

## Файлы изменены
1. `loyalty-proxy/index.js` (+259 строк)
2. `assets/images/arabica_background.png` (новый файл)
3. `android/create_background.py` (новый файл)
4. `API_DOCUMENTATION.md` (новый файл)

## Ошибки устранены
✅ Фоновое изображение создано
✅ API для shift-questions реализован
✅ API для recount-questions реализован
✅ Поддержка referencePhotos добавлена
✅ Загрузка эталонных фото реализована

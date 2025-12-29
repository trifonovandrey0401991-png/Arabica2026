# API Documentation - Arabica 2026

## Вопросы пересчета (Recount Questions)

### GET `/api/recount-questions`
Получить список всех вопросов пересчета

**Ответ:**
```json
{
  "success": true,
  "questions": [
    {
      "id": "recount_question_123",
      "question": "Проверить срок годности молока",
      "grade": 1,
      "referencePhotos": {
        "Ессентуки, ул Пятигорская 149/1": "https://arabica26.ru/shift-photos/example.jpg"
      },
      "createdAt": "2025-12-30T00:00:00.000Z",
      "updatedAt": "2025-12-30T00:00:00.000Z"
    }
  ]
}
```

### POST `/api/recount-questions`
Создать новый вопрос пересчета

**Тело запроса:**
```json
{
  "question": "Проверить срок годности молока",
  "grade": 1,
  "referencePhotos": {}
}
```

**Ответ:**
```json
{
  "success": true,
  "message": "Вопрос успешно создан",
  "question": { ... }
}
```

### PUT `/api/recount-questions/:questionId`
Обновить существующий вопрос

**Тело запроса:**
```json
{
  "question": "Новый текст вопроса",
  "grade": 2,
  "referencePhotos": { ... }
}
```

### POST `/api/recount-questions/:questionId/reference-photo`
Загрузить эталонное фото для вопроса

**Параметры:**
- `photo` (file) - файл изображения
- `shopAddress` (string) - адрес магазина

**Ответ:**
```json
{
  "success": true,
  "photoUrl": "https://arabica26.ru/shift-photos/filename.jpg",
  "shopAddress": "Ессентуки, ул Пятигорская 149/1"
}
```

### DELETE `/api/recount-questions/:questionId`
Удалить вопрос

---

## Вопросы пересменки (Shift Questions)

### GET `/api/shift-questions`
Получить список вопросов пересменки

**Query параметры:**
- `shopAddress` (optional) - фильтр по адресу магазина

**Ответ:**
```json
{
  "success": true,
  "questions": [
    {
      "id": "shift_question_456",
      "question": "Проверить кассу",
      "answerFormatB": "free",
      "answerFormatC": null,
      "shops": ["Ессентуки, ул Пятигорская 149/1"],
      "referencePhotos": {
        "Ессентуки, ул Пятигорская 149/1": "https://arabica26.ru/shift-photos/example.jpg"
      },
      "createdAt": "2025-12-30T00:00:00.000Z",
      "updatedAt": "2025-12-30T00:00:00.000Z"
    }
  ]
}
```

### GET `/api/shift-questions/:questionId`
Получить один вопрос по ID

### POST `/api/shift-questions`
Создать новый вопрос пересменки

**Тело запроса:**
```json
{
  "question": "Проверить кассу",
  "answerFormatB": "free",
  "answerFormatC": null,
  "shops": ["Ессентуки, ул Пятигорская 149/1"],
  "referencePhotos": {}
}
```

### PUT `/api/shift-questions/:questionId`
Обновить вопрос

### POST `/api/shift-questions/:questionId/reference-photo`
Загрузить эталонное фото для вопроса

**Параметры:**
- `photo` (file) - файл изображения
- `shopAddress` (string) - адрес магазина

### DELETE `/api/shift-questions/:questionId`
Удалить вопрос

---

## Структура данных

### RecountQuestion
```typescript
{
  id: string;
  question: string;
  grade: number; // 1, 2, или 3
  referencePhotos: { [shopAddress: string]: string }; // URL фото для каждого магазина
  createdAt: string;
  updatedAt: string;
}
```

### ShiftQuestion
```typescript
{
  id: string;
  question: string;
  answerFormatB: string | null; // "free", "photo", etc.
  answerFormatC: string | null; // "число", etc.
  shops: string[] | null; // null = для всех магазинов
  referencePhotos: { [shopAddress: string]: string }; // URL фото для каждого магазина
  createdAt: string;
  updatedAt: string;
}
```

## Хранение данных

- Вопросы пересчета: `/var/www/recount-questions/*.json`
- Вопросы пересменки: `/var/www/shift-questions/*.json`
- Фотографии: `/var/www/shift-photos/*.jpg`

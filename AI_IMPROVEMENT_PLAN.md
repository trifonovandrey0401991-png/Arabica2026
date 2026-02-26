# ПЛАН УЛУЧШЕНИЯ AI-СИСТЕМ ДО 9-10/10

> Дата создания: 2026-02-20
> Текущие оценки: Z-Report OCR 7/10, Coffee Machine OCR 8/10, Cigarette Vision 2/10, Shift AI 1/10
> Цель: каждая система минимум 9/10

---

## ОГЛАВЛЕНИЕ

- [Система 1: Z-Report OCR (7→10)](#система-1-z-report-ocr-710)
- [Система 2: Coffee Machine OCR (8→10)](#система-2-coffee-machine-ocr-810)
- [Система 3: Cigarette Vision YOLO (2→9)](#система-3-cigarette-vision-yolo-29)
- [Система 4: Shift AI Verification (1→9)](#система-4-shift-ai-verification-19)
- [Порядок выполнения](#порядок-выполнения)
- [Чеклист деплоя](#чеклист-деплоя)

---

## Система 1: Z-Report OCR (7→10)

### Что уже исправлено (предыдущая сессия):
- [x] ofdNotSent fallback 0 → null
- [x] Intelligence value→data в DB (jsonb)
- [x] O(n) → O(1) upserts для training samples
- [x] EMA формула для successRate
- [x] Инвалидация кэша learned patterns
- [x] OCR-модули объединены в ocr-engine.js

### Задача Z-1: Сохранять training sample при ПЕРВОМ провале OCR в конверте
**Серьёзность:** HIGH
**Проблема:** Когда OCR полностью провалился при первой попытке в `envelope_form_page.dart` (строки 333-347), сотрудник вводит данные вручную, но training sample НЕ сохраняется. Система не учится на своих провалах.
**Файлы:**
- `lib/features/envelope/pages/envelope_form_page.dart` (строки 333-347)
**Решение:**
После того как сотрудник ввёл данные вручную в ZReportRecognitionDialog, вызвать `ZReportTemplateService.saveTrainingSample()` с `correctData` = введённые данные, `recognizedData` = null (или пустые поля). Это позволит системе обучаться на полных провалах.
```dart
// После получения результата из ZReportRecognitionDialog:
if (manualResult != null && manualResult.hasData) {
  // Сохраняем sample для обучения (OCR провалился полностью)
  ZReportTemplateService.saveTrainingSample(
    imageBase64: _currentImageBase64,
    correctData: manualResult.data,
    recognizedData: {}, // OCR не распознал ничего
    shopAddress: _selectedShopAddress,
  );
}
```

### Задача Z-2: Сохранять training sample при УСПЕШНОМ распознавании в конверте
**Серьёзность:** HIGH
**Проблема:** Когда OCR распознал правильно и сотрудник подтвердил (строки 349-365), training sample тоже НЕ сохраняется. Система не получает позитивного подкрепления — обучается только на ошибках.
**Файлы:**
- `lib/features/envelope/pages/envelope_form_page.dart` (строки 349-365)
**Решение:**
При подтверждении результата сохранять sample с `correctData == recognizedData` (пустой `correctedFields`). Это усиливает статистику accuracy и помогает intelligence строить более точные ожидаемые диапазоны.
```dart
// После подтверждения "Верно":
ZReportTemplateService.saveTrainingSample(
  imageBase64: _currentImageBase64,
  correctData: recognizedData,
  recognizedData: recognizedData, // Совпадают = "всё верно"
  shopAddress: _selectedShopAddress,
);
```
**Важно:** Не сохранять фото (imageBase64: null), только данные — чтобы не раздувать диск. Фото нужно только для pattern learning, а при успешном распознавании паттерны уже работают.

### Задача Z-3: Исправить связку USE_DB env var в intelligence
**Серьёзность:** MEDIUM
**Проблема:** `z-report-intelligence.js:18` читает `USE_DB_ENVELOPE` вместо `USE_DB_Z_REPORT`. Если ENVELOPE=false но Z_REPORT=true, intelligence не пишет в DB.
**Файлы:**
- `loyalty-proxy/modules/z-report-intelligence.js` (строка 18)
**Решение:**
```javascript
// Было:
const USE_DB = process.env.USE_DB_ENVELOPE === 'true';
// Стало:
const USE_DB = process.env.USE_DB_Z_REPORT === 'true' || process.env.USE_DB_ENVELOPE === 'true';
```
Читаем оба флага — если хотя бы один включен, пишем в DB. Это безопаснее чем жёстко привязываться к одному.

### Задача Z-4: Улучшить resourceKeys trend prediction
**Серьёзность:** LOW
**Проблема:** `buildResourceKeysStats()` (строки 127-169) считает тренд только по первой и последней точке. Один аномальный отчёт (сброс ключей) ломает все предсказания.
**Файлы:**
- `loyalty-proxy/modules/z-report-intelligence.js` (строки 127-169)
**Решение:**
Использовать медианный тренд (median of pairwise slopes) вместо first-to-last:
```javascript
// Вычисляем все попарные наклоны
const slopes = [];
for (let i = 1; i < sorted.length; i++) {
  const daysDiff = (new Date(sorted[i].date) - new Date(sorted[i-1].date)) / 86400000;
  if (daysDiff > 0) {
    slopes.push((sorted[i].value - sorted[i-1].value) / daysDiff);
  }
}
// Медиана устойчива к выбросам
slopes.sort((a, b) => a - b);
const medianSlope = slopes[Math.floor(slopes.length / 2)];
```

---

## Система 2: Coffee Machine OCR (8→10)

### Что уже исправлено:
- [x] fsp.writeFile → writeJsonFile для intelligence
- [x] Dual-write intelligence в DB
- [x] DB fallback в loadMachineIntelligence

### Задача CM-1: Intelligence — читать отчёты из DB, не только из файлов
**Серьёзность:** MEDIUM
**Проблема:** `buildMachineIntelligence()` (строка 1041) читает отчёты ТОЛЬКО из JSON-файлов через `fsp.readdir(REPORTS_DIR)`. Если файлы удалят (очистка диска), intelligence потеряет все данные.
**Файлы:**
- `loyalty-proxy/api/coffee_machine_api.js` (строки 1036-1050)
**Решение:**
Добавить DB-путь для чтения отчётов (аналогично другим модулям):
```javascript
async function loadAllReports() {
  if (process.env.USE_DB_COFFEE_MACHINE === 'true') {
    try {
      const rows = await db.query(
        'SELECT data FROM coffee_machine_reports ORDER BY created_at DESC LIMIT 500'
      );
      if (rows.length > 0) return rows.map(r => r.data);
    } catch (e) { console.error('[CoffeeMachine] DB reports read error:', e.message); }
  }
  // JSON fallback
  const files = await fsp.readdir(REPORTS_DIR);
  // ... existing file reading code
}
```

### Задача CM-2: Улучшить avgDailyGrowth — линейная регрессия вместо 2 точек
**Серьёзность:** MEDIUM
**Проблема:** `avgDailyGrowth` (строка 1104) использует только первое и последнее значение. Один сброс счётчика (замена машины) или аномальное чтение ломает все предсказания.
**Файлы:**
- `loyalty-proxy/api/coffee_machine_api.js` (строки 1100-1120)
**Решение:**
Least-squares линейная регрессия по всем точкам:
```javascript
function linearRegression(points) {
  const n = points.length;
  if (n < 2) return { slope: 0, intercept: 0 };
  let sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
  const baseDate = new Date(points[0].date).getTime();
  for (const p of points) {
    const x = (new Date(p.date).getTime() - baseDate) / 86400000; // дни
    sumX += x; sumY += p.value; sumXY += x * p.value; sumX2 += x * x;
  }
  const slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
  const intercept = (sumY - slope * sumX) / n;
  return { slope: isFinite(slope) ? slope : 0, intercept };
}
// slope = avgDailyGrowth
```

### Задача CM-3: Передавать правильный preset при обучении
**Серьёзность:** MEDIUM
**Проблема:** Flutter `coffee_machine_form_page.dart` строка 376 отправляет `preset: ''` при обучении. Сервер получает пустую строку и записывает в training sample, ломая per-preset region learning.
**Файлы:**
- `lib/features/coffee_machine/pages/coffee_machine_report_view_page.dart` (строка 376)
**Решение:**
Передавать актуальный preset из шаблона машины:
```dart
// Было:
'preset': '', // будет определён по шаблону на сервере
// Стало:
'preset': reading.preset ?? 'standard',
```
Также нужно добавить поле `preset` в модель `CoffeeMachineReading` если его нет.

### Задача CM-4: Парсить intelligence из OCR-ответа во Flutter
**Серьёзность:** LOW
**Проблема:** Сервер возвращает `intelligence: { expectedRange, suggestedPreset, successRate, lastKnownValue }` в ответе OCR, но `OcrResult` модель во Flutter не имеет этого поля — данные молча теряются.
**Файлы:**
- `lib/features/coffee_machine/services/coffee_machine_ocr_service.dart` (OcrResult модель)
**Решение:**
Добавить поля в OcrResult:
```dart
class OcrResult {
  // ... existing fields
  final Map<String, dynamic>? intelligence;

  OcrResult({..., this.intelligence});

  factory OcrResult.fromJson(Map<String, dynamic> json) {
    return OcrResult(
      ...,
      intelligence: json['intelligence'] as Map<String, dynamic>?,
    );
  }
}
```
Показывать в UI подсказку: "Ожидаемое значение: X-Y" на основе intelligence.

### Задача CM-5: Добавить random suffix к report ID
**Серьёзность:** LOW
**Проблема:** `cm_report_${Date.now()}` (строка 432) без random suffix. При одновременной отправке двух отчётов в одну миллисекунду — коллизия ID.
**Файлы:**
- `loyalty-proxy/api/coffee_machine_api.js` (строка 432)
**Решение:**
```javascript
// Было:
const reportId = `cm_report_${Date.now()}`;
// Стало:
const reportId = `cm_report_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
```

### Задача CM-6: writeJsonFile для training samples
**Серьёзность:** LOW
**Проблема:** `saveTrainingSamples()` (строка 794) использует raw `fsp.writeFile` вместо `writeJsonFile`. Под конкурентной нагрузкой может повредить файл.
**Файлы:**
- `loyalty-proxy/api/coffee_machine_api.js` (строка ~794)
**Решение:**
```javascript
// Было:
await fsp.writeFile(SAMPLES_FILE, JSON.stringify(samples, null, 2), 'utf8');
// Стало:
await writeJsonFile(SAMPLES_FILE, samples);
```
Добавить import `writeJsonFile` если его нет.

---

## Система 3: Cigarette Vision YOLO (2→9)

### Задача CIG-1: Исправить export — использовать новые dataset директории
**Серьёзность:** CRITICAL
**Проблема:** `yolo_inference.py` (строки 322-324) экспортирует из `data/cigarette-training-images/` и `data/cigarette-training-labels/` — старые единые директории. Новые типизированные данные из `display-training/` и `counting-training/` НИКОГДА не попадают в обучение.
**Файлы:**
- `loyalty-proxy/ml/yolo_inference.py` (строки 310-360)
**Решение:**
Обновить `export_training_data()` чтобы читал из ОБОИХ новых директорий:
```python
def export_training_data():
    datasets = [
        'data/display-training',
        'data/counting-training',
        'data/cigarette-training-images',  # legacy fallback
    ]
    all_images = []
    all_labels = []
    for ds in datasets:
        img_dir = os.path.join(ds, 'images')
        lbl_dir = os.path.join(ds, 'labels')
        if os.path.exists(img_dir):
            for f in os.listdir(img_dir):
                if f.endswith(('.jpg', '.png')):
                    all_images.append(os.path.join(img_dir, f))
                    lbl = os.path.join(lbl_dir, f.rsplit('.', 1)[0] + '.txt')
                    if os.path.exists(lbl):
                        all_labels.append(lbl)
```

### Задача CIG-2: Добавить train/val split
**Серьёзность:** CRITICAL
**Проблема:** `data.yaml` (строка 355) указывает одну и ту же директорию для train и val. YOLO переобучается и показывает ложно высокую точность.
**Файлы:**
- `loyalty-proxy/ml/yolo_inference.py` (строки 340-360)
**Решение:**
При экспорте разделять 80% train / 20% val:
```python
import random
random.shuffle(all_images)
split = int(len(all_images) * 0.8)
train_images = all_images[:split]
val_images = all_images[split:]

# Копировать в train/images, train/labels и val/images, val/labels
# data.yaml: train: train/images, val: val/images
```

### Задача CIG-3: verify-bbox — реально кропать изображение по bbox
**Серьёзность:** HIGH
**Проблема:** `shift_ai_verification_api.js` (строки 680-684) получает bbox координаты но отправляет ПОЛНОЕ изображение в YOLO. Bbox только сохраняется в аннотацию. Комментарий "YOLO будет искать товар в указанной области" — ложь.
**Файлы:**
- `loyalty-proxy/api/shift_ai_verification_api.js` (строки 652-779)
- `loyalty-proxy/modules/cigarette-vision.js` (checkDisplay)
**Решение:**
Перед вызовом YOLO кропнуть изображение по bbox:
```javascript
// В verify-bbox endpoint, после получения boundingBox:
const sharp = require('sharp');
const imgBuffer = Buffer.from(imageBase64, 'base64');
const metadata = await sharp(imgBuffer).metadata();
const { x, y, width, height } = boundingBox;
const left = Math.round(x * metadata.width);
const top = Math.round(y * metadata.height);
const cropW = Math.round(width * metadata.width);
const cropH = Math.round(height * metadata.height);

const croppedBuffer = await sharp(imgBuffer)
  .extract({ left, top, width: cropW, height: cropH })
  .toBuffer();
const croppedBase64 = croppedBuffer.toString('base64');

// Теперь отправляем КРОПНУТОЕ изображение в YOLO
const displayResult = await cigaretteVision.checkDisplay(croppedBase64, [productId], 0.25);
```

### Задача CIG-4: Синхронизировать threshold auto-disable (сервер↔Flutter)
**Серьёзность:** MEDIUM
**Проблема:** Сервер `AI_ERROR_THRESHOLD = 20` (cigarette-vision.js:1590), Flutter `threshold = 5` (cigarette_vision_service.dart:827,843). UI показывает неправильный порог.
**Файлы:**
- `lib/features/ai_training/services/cigarette_vision_service.dart` (строки 825-846)
**Решение:**
Flutter уже получает `threshold` из ответа сервера в `fromJson`. Проблема в дефолтном значении:
```dart
// Было:
threshold: json['threshold'] ?? 5,
// Нужно убедиться что сервер ВСЕГДА отправляет threshold в ответе
```
На сервере в `reportAiError` и `reportAdminAiDecision` добавить `threshold: AI_ERROR_THRESHOLD` в ответ:
```javascript
res.json({ success: true, ..., threshold: AI_ERROR_THRESHOLD });
```

### Задача CIG-5: Исправить temp file collision в yolo-wrapper
**Серьёзность:** MEDIUM
**Проблема:** `yolo-wrapper.js` строка 173 использует `detect_${Date.now()}.jpg` без random suffix.
**Файлы:**
- `loyalty-proxy/ml/yolo-wrapper.js` (строка 173)
**Решение:**
```javascript
// Было:
const tempPath = path.join(TEMP_DIR, `detect_${Date.now()}.jpg`);
// Стало:
const tempPath = path.join(TEMP_DIR, `detect_${Date.now()}_${Math.random().toString(36).slice(2,6)}.jpg`);
```

### Задача CIG-6: Settings cache с TTL
**Серьёзность:** MEDIUM
**Проблема:** `settingsCache` (cigarette-vision.js:120) и `recognitionStatsCache` (строка 2023) кэшируются навечно. Изменение настроек через API не применяется до рестарта pm2.
**Файлы:**
- `loyalty-proxy/modules/cigarette-vision.js` (строки 120-121, 2023)
**Решение:**
Добавить TTL 5 минут:
```javascript
let settingsCache = null;
let settingsCacheTime = 0;
const SETTINGS_CACHE_TTL = 5 * 60 * 1000; // 5 минут

async function loadSettings() {
  if (settingsCache && Date.now() - settingsCacheTime < SETTINGS_CACHE_TTL) {
    return settingsCache;
  }
  // ... загрузка с диска/DB
  settingsCacheTime = Date.now();
  settingsCache = data;
  return data;
}
```
Также добавить инвалидацию при записи:
```javascript
async function saveSettings(settings) {
  // ... сохранение
  settingsCache = settings;
  settingsCacheTime = Date.now();
}
```

### Задача CIG-7: Добавить await для getProductsWithTrainingInfo
**Серьёзность:** MEDIUM
**Проблема:** `cigarette_vision_api.js` (строки 86-89) вызывает async функцию без await. Работает случайно (Express обрабатывает Promise), но хрупко.
**Файлы:**
- `loyalty-proxy/api/cigarette_vision_api.js` (строки 86-89)
**Решение:**
```javascript
// Было:
const products = cigaretteVision.getProductsWithTrainingInfo(...);
res.json(products);
// Стало:
const products = await cigaretteVision.getProductsWithTrainingInfo(...);
res.json(products);
```

### Задача CIG-8: Persistent YOLO inference server (как OCR server)
**Серьёзность:** HIGH
**Проблема:** Каждый вызов YOLO спавнит новый Python-процесс, загружает модель с диска, выполняет inference, завершается. На 2GB RAM сервере это 5-10 секунд на запрос. OCR система использует persistent server на порту 5001 — работает быстро.
**Файлы:**
- `loyalty-proxy/ml/yolo-wrapper.js` (весь файл)
- `loyalty-proxy/ml/yolo_inference.py` (весь файл)
**Решение:**
Создать `loyalty-proxy/ml/yolo_server.py` по аналогии с `ocr_server.py`:
```python
# HTTP server на порту 5002
# Загружает модель один раз при старте
# Endpoints:
#   GET /health — проверка доступности
#   POST /detect — detectAndCount
#   POST /display — checkDisplay
#   POST /train — запуск обучения (async)
```
Обновить `yolo-wrapper.js` чтобы вызывал HTTP вместо spawn:
```javascript
// Вместо spawn('python3', ['yolo_inference.py', ...])
// HTTP POST к http://127.0.0.1:5002/detect
```
Добавить pm2 процесс `yolo-server` аналогично `ocr-server`.

### Задача CIG-9: Убрать неиспользуемые DISPLAY_MODEL/COUNTING_MODEL
**Серьёзность:** LOW
**Проблема:** `cigarette-vision.js` (строки 102-104) определяет `DISPLAY_MODEL` и `COUNTING_MODEL` пути, но inference ВСЕГДА использует единый `cigarette_detector.pt`. Сбивает с толку.
**Файлы:**
- `loyalty-proxy/modules/cigarette-vision.js` (строки 102-104)
**Решение:**
Удалить `DISPLAY_MODEL`, `COUNTING_MODEL`. Оставить только `DEFAULT_MODEL` в yolo-wrapper.
В `getTypedTrainingStats()` проверять `isModelReady()` вместо `fs.existsSync(DISPLAY_MODEL)`.

---

## Система 4: Shift AI Verification (1→9)

> Shift AI Verification использует ТОТ ЖЕ YOLO-модуль что и Cigarette Vision.
> Задачи CIG-1..CIG-9 автоматически улучшают и эту систему.
> Ниже — только специфичные задачи для Shift AI.

### Задача SHIFT-1: Фильтровать фото по isAiCheck флагу
**Серьёзность:** HIGH
**Проблема:** `_collectPhotosForAiVerification()` в `shift_questions_page.dart` (строки 417-443) собирает ВСЕ фото из ВСЕХ ответов. Фото кассы, чеков, оборудования отправляются в YOLO для поиска сигарет — бессмысленно.
**Файлы:**
- `lib/features/shifts/pages/shift_questions_page.dart` (строки 417-443)
- `lib/features/shift_handover/pages/shift_handover_questions_page.dart` (строки 474-538)
**Решение:**
```dart
Future<List<Uint8List>> _collectPhotosForAiVerification() async {
  final photos = <Uint8List>[];
  for (int i = 0; i < _questions.length; i++) {
    // ТОЛЬКО фото от вопросов с isAiCheck == true
    if (!_questions[i].isAiCheck) continue;

    final answer = _answers[_questions[i].id];
    if (answer?.photoPath != null) {
      final bytes = await File(answer!.photoPath!).readAsBytes();
      photos.add(bytes);
    }
  }
  return photos;
}
```
То же самое для `shift_handover_questions_page.dart`.

### Задача SHIFT-2: BBox координаты — нормализовать к размеру изображения
**Серьёзность:** HIGH
**Проблема:** `shift_ai_verification_page.dart` (строки 1250-1255) нормализует bbox к размеру виджета на экране. На разных телефонах (разное разрешение экрана) одна и та же область даёт разные координаты → training data несогласованный.
**Файлы:**
- `lib/features/ai_training/pages/shift_ai_verification_page.dart` (строки 1250-1255)
**Решение:**
Нужно знать реальные размеры изображения, а не виджета:
```dart
// Загрузить реальные размеры изображения
final image = await decodeImageFromList(imageBytes);
final imgWidth = image.width.toDouble();
final imgHeight = image.height.toDouble();

// Нормализовать bbox к размеру ИЗОБРАЖЕНИЯ (не виджета)
final normalizedBox = {
  'x': drawnRect.left / displayWidth * (displayWidth / imgWidth),
  'y': drawnRect.top / displayHeight * (displayHeight / imgHeight),
  'width': drawnRect.width / displayWidth * (displayWidth / imgWidth),
  'height': drawnRect.height / displayHeight * (displayHeight / imgHeight),
};
```
Или проще — передавать ratio между display и image размерами.

### Задача SHIFT-3: Показывать productName вместо productId в admin review
**Серьёзность:** LOW
**Проблема:** `shift_handover_report_view_page.dart` (строка 411) показывает `productId` (barcode) вместо имени товара. Админ не понимает что за товар.
**Файлы:**
- `lib/features/shift_handover/pages/shift_handover_report_view_page.dart` (строка ~411)
**Решение:**
Передавать `productName` вместе с `productId` в `aiBboxAnnotations` map. На стороне `shift_ai_verification_page.dart` при сохранении BBox включать name:
```dart
// Вместо Map<String, String> productId→annotationId
// Использовать Map<String, Map<String, String>> productId→{annotationId, productName}
```

### Задача SHIFT-4: Атомарная запись аннотаций (image + JSON)
**Серьёзность:** LOW
**Проблема:** `shift_ai_verification_api.js` (строки 609, 614) пишет image и JSON отдельно. Краш между записями = JSON без картинки.
**Файлы:**
- `loyalty-proxy/api/shift_ai_verification_api.js` (строки 600-620)
**Решение:**
Писать в обратном порядке (сначала image, потом JSON) и оборачивать в try/catch с cleanup:
```javascript
try {
  await fsp.writeFile(imagePath, imageBuffer); // image первым
  await writeJsonFile(annotationJsonPath, annotationData); // JSON вторым
} catch (e) {
  // Cleanup: удалить image если JSON не записался
  try { await fsp.unlink(imagePath); } catch {}
  throw e;
}
```

---

## Порядок выполнения

### Волна 1: Критические баги (бэкенд) — без деплоя Flutter
Исправления которые можно деплоить ТОЛЬКО на сервере:

| # | Задача | Файлы | Время |
|---|--------|-------|-------|
| 1 | CM-1 | coffee_machine_api.js | 15 мин |
| 2 | CM-2 | coffee_machine_api.js | 20 мин |
| 3 | CM-5 | coffee_machine_api.js | 2 мин |
| 4 | CM-6 | coffee_machine_api.js | 5 мин |
| 5 | Z-3 | z-report-intelligence.js | 5 мин |
| 6 | Z-4 | z-report-intelligence.js | 15 мин |
| 7 | CIG-4 | cigarette_vision_service.dart + cigarette-vision.js | 10 мин |
| 8 | CIG-5 | yolo-wrapper.js | 2 мин |
| 9 | CIG-6 | cigarette-vision.js | 15 мин |
| 10 | CIG-7 | cigarette_vision_api.js | 2 мин |
| 11 | CIG-9 | cigarette-vision.js | 5 мин |

**Деплой** → проверка → коммит

### Волна 2: Flutter-зависимые исправления
Требуют обновления Flutter-приложения:

| # | Задача | Файлы | Время |
|---|--------|-------|-------|
| 1 | Z-1 | envelope_form_page.dart | 20 мин |
| 2 | Z-2 | envelope_form_page.dart | 15 мин |
| 3 | CM-3 | coffee_machine_report_view_page.dart | 10 мин |
| 4 | CM-4 | coffee_machine_ocr_service.dart | 15 мин |
| 5 | SHIFT-1 | shift_questions_page.dart + shift_handover_questions_page.dart | 20 мин |
| 6 | SHIFT-2 | shift_ai_verification_page.dart | 25 мин |
| 7 | SHIFT-3 | shift_handover_report_view_page.dart + shift_ai_verification_page.dart | 15 мин |
| 8 | SHIFT-4 | shift_ai_verification_api.js | 10 мин |

**flutter build** → деплой бэкенда → проверка

### Волна 3: YOLO pipeline (критическая для Cigarette + Shift)
Без этой волны системы 3 и 4 останутся на 2/10 и 1/10:

| # | Задача | Файлы | Время |
|---|--------|-------|-------|
| 1 | CIG-1 | yolo_inference.py | 30 мин |
| 2 | CIG-2 | yolo_inference.py | 20 мин |
| 3 | CIG-3 | shift_ai_verification_api.js | 25 мин |
| 4 | CIG-8 | yolo_server.py (новый) + yolo-wrapper.js | 60 мин |

**Деплой** → проверка

### Волна 4: Обучение модели
После волн 1-3 инфраструктура готова. Нужно:

1. **Собрать данные:** минимум 100 аннотированных фото через Cigarette Training Page
2. **Экспортировать:** `POST /api/cigarette-vision/export-training`
3. **Обучить:** `POST /api/cigarette-vision/train` (YOLOv8n, 100 epochs)
4. **Проверить:** `GET /api/cigarette-vision/model-status` → `isTrained: true`
5. **Тестировать:** несколько фото через UI → проверить accuracy

---

## Ожидаемые оценки после выполнения

| Система | Было | После волн 1-2 | После волн 3-4 |
|---------|------|----------------|----------------|
| Z-Report OCR | 7/10 | **10/10** | 10/10 |
| Coffee Machine OCR | 8/10 | **10/10** | 10/10 |
| Cigarette Vision | 2/10 | 3/10 | **9/10** |
| Shift AI Verification | 1/10 | 2/10 | **9/10** |

> Системы 3 и 4 не могут получить 10/10 потому что YOLO требует достаточного объёма training data. 9/10 = вся инфраструктура идеальна + модель обучена + feedback loop работает. Для 10/10 нужна реальная эксплуатация и fine-tuning.

---

## Чеклист деплоя (для каждой волны)

```bash
# 1. Синтаксическая проверка (на Windows)
node -c loyalty-proxy/modules/z-report-intelligence.js
node -c loyalty-proxy/api/coffee_machine_api.js
node -c loyalty-proxy/modules/cigarette-vision.js
# ... все изменённые .js файлы

# 2. Flutter analyze (если менялся Flutter)
flutter analyze --no-fatal-infos

# 3. Коммит
git add <files>
git commit -m "описание"

# 4. Бэкап на сервере
ssh root@arabica26.ru "cp /root/arabica_app/loyalty-proxy/index.js /root/arabica_app/loyalty-proxy/index.js.backup-$(date +%Y%m%d-%H%M%S)"

# 5. Деплой
ssh root@arabica26.ru "cd /root/arabica_app && git pull origin refactoring/full-restructure"
ssh root@arabica26.ru "pm2 restart loyalty-proxy"

# 6. Проверка
ssh root@arabica26.ru "pm2 logs loyalty-proxy --lines 30 --nostream"  # нет ошибок
curl https://arabica26.ru/health                                       # 200 OK
node tests/api-test.js                                                 # 55/55 pass

# 7. Flutter build (если менялся Flutter)
flutter build apk --release
# Загрузить APK на телефоны для тестирования
```

---

## Файлы затронутые планом (полный список)

### Бэкенд (loyalty-proxy/):
| Файл | Задачи |
|------|--------|
| `modules/z-report-intelligence.js` | Z-3, Z-4 |
| `api/coffee_machine_api.js` | CM-1, CM-2, CM-5, CM-6 |
| `modules/cigarette-vision.js` | CIG-4, CIG-6, CIG-9 |
| `api/cigarette_vision_api.js` | CIG-7 |
| `api/shift_ai_verification_api.js` | CIG-3, SHIFT-4 |
| `ml/yolo-wrapper.js` | CIG-5, CIG-8 |
| `ml/yolo_inference.py` | CIG-1, CIG-2 |
| `ml/yolo_server.py` | CIG-8 **(НОВЫЙ)** |

### Flutter (lib/):
| Файл | Задачи |
|------|--------|
| `features/envelope/pages/envelope_form_page.dart` | Z-1, Z-2 |
| `features/coffee_machine/pages/coffee_machine_report_view_page.dart` | CM-3 |
| `features/coffee_machine/services/coffee_machine_ocr_service.dart` | CM-4 |
| `features/ai_training/services/cigarette_vision_service.dart` | CIG-4 |
| `features/shifts/pages/shift_questions_page.dart` | SHIFT-1 |
| `features/shift_handover/pages/shift_handover_questions_page.dart` | SHIFT-1 |
| `features/ai_training/pages/shift_ai_verification_page.dart` | SHIFT-2 |
| `features/shift_handover/pages/shift_handover_report_view_page.dart` | SHIFT-3 |

### Итого: 22 задачи, 16 файлов (1 новый)

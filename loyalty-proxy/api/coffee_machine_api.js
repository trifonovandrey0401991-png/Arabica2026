/**
 * Coffee Machine Counter API
 *
 * Управление шаблонами кофемашин, привязками к магазинам,
 * отчётами по счётчикам и OCR распознаванием.
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

// Директории данных
const TEMPLATES_DIR = `${DATA_DIR}/coffee-machine-templates`;
const SHOP_CONFIGS_DIR = `${DATA_DIR}/coffee-machine-shop-configs`;
const REPORTS_DIR = `${DATA_DIR}/coffee-machine-reports`;
const PHOTOS_DIR = `${DATA_DIR}/coffee-machine-photos`;
const TRAINING_DIR = `${DATA_DIR}/coffee-machine-training`;
const TRAINING_IMAGES_DIR = `${TRAINING_DIR}/images`;
const TRAINING_SAMPLES_FILE = `${TRAINING_DIR}/samples.json`;
const MAX_TRAINING_SAMPLES = 200;

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Ensure directories exist
(async () => {
  for (const dir of [TEMPLATES_DIR, SHOP_CONFIGS_DIR, REPORTS_DIR, PHOTOS_DIR, TRAINING_DIR, TRAINING_IMAGES_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

// Sanitize ID for filename
function sanitizeId(str) {
  return str.replace(/[^a-zA-Z0-9_\-]/g, '_');
}

function setupCoffeeMachineAPI(app) {

  // ============================================
  // ШАБЛОНЫ КОФЕМАШИН (developer only)
  // ============================================

  // GET /api/coffee-machine/templates — список всех шаблонов
  app.get('/api/coffee-machine/templates', async (req, res) => {
    try {
      const templates = [];
      if (await fileExists(TEMPLATES_DIR)) {
        const files = (await fsp.readdir(TEMPLATES_DIR)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(TEMPLATES_DIR, file), 'utf8');
            templates.push(JSON.parse(content));
          } catch (e) {
            console.error(`[CoffeeMachine] Ошибка чтения ${file}:`, e.message);
          }
        }
      }
      templates.sort((a, b) => (a.name || '').localeCompare(b.name || ''));
      res.json({ success: true, templates });
    } catch (error) {
      console.error('[CoffeeMachine] Ошибка получения шаблонов:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/coffee-machine/templates/:id — один шаблон
  app.get('/api/coffee-machine/templates/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const filePath = path.join(TEMPLATES_DIR, `${sanitizeId(id)}.json`);
      if (await fileExists(filePath)) {
        const template = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        res.json({ success: true, template });
      } else {
        res.status(404).json({ success: false, error: 'Шаблон не найден' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/coffee-machine/templates — создать/обновить шаблон
  app.post('/api/coffee-machine/templates', async (req, res) => {
    try {
      const { template, referenceImage } = req.body;
      if (!template || !template.name) {
        return res.status(400).json({ success: false, error: 'Нужно указать имя шаблона' });
      }

      // Генерация ID если нет
      if (!template.id) {
        template.id = `tmpl_${Date.now()}`;
      }
      template.createdAt = template.createdAt || new Date().toISOString();
      template.updatedAt = new Date().toISOString();

      // Сохранение эталонного фото
      if (referenceImage) {
        const photoFileName = `ref_${sanitizeId(template.id)}.jpg`;
        const photoPath = path.join(PHOTOS_DIR, photoFileName);
        await fsp.writeFile(photoPath, Buffer.from(referenceImage, 'base64'));
        template.referencePhotoUrl = `/coffee-machine-photos/${photoFileName}`;
      }

      const filePath = path.join(TEMPLATES_DIR, `${sanitizeId(template.id)}.json`);
      await fsp.writeFile(filePath, JSON.stringify(template, null, 2), 'utf8');

      console.log(`[CoffeeMachine] ✅ Шаблон сохранён: ${template.name} (${template.id})`);
      res.json({ success: true, template });
    } catch (error) {
      console.error('[CoffeeMachine] Ошибка сохранения шаблона:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/coffee-machine/templates/:id — обновить шаблон
  app.put('/api/coffee-machine/templates/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const { template, referenceImage } = req.body;
      const filePath = path.join(TEMPLATES_DIR, `${sanitizeId(id)}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Шаблон не найден' });
      }

      const existing = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      const updated = { ...existing, ...template, id, updatedAt: new Date().toISOString() };

      // Обновление эталонного фото
      if (referenceImage) {
        const photoFileName = `ref_${sanitizeId(id)}.jpg`;
        const photoPath = path.join(PHOTOS_DIR, photoFileName);
        await fsp.writeFile(photoPath, Buffer.from(referenceImage, 'base64'));
        updated.referencePhotoUrl = `/coffee-machine-photos/${photoFileName}`;
      }

      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2), 'utf8');
      console.log(`[CoffeeMachine] ✅ Шаблон обновлён: ${updated.name} (${id})`);
      res.json({ success: true, template: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/coffee-machine/templates/:id — удалить шаблон
  app.delete('/api/coffee-machine/templates/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const filePath = path.join(TEMPLATES_DIR, `${sanitizeId(id)}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Шаблон не найден' });
      }

      await fsp.unlink(filePath);
      console.log(`[CoffeeMachine] ❌ Шаблон удалён: ${id}`);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/coffee-machine/templates/:id/image — получить эталонное фото
  app.get('/api/coffee-machine/templates/:id/image', async (req, res) => {
    try {
      const { id } = req.params;
      const photoPath = path.join(PHOTOS_DIR, `ref_${sanitizeId(id)}.jpg`);

      if (await fileExists(photoPath)) {
        const imageBuffer = await fsp.readFile(photoPath);
        res.set('Content-Type', 'image/jpeg');
        res.send(imageBuffer);
      } else {
        res.status(404).json({ success: false, error: 'Фото не найдено' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // ПРИВЯЗКИ К МАГАЗИНАМ (developer only)
  // ============================================

  // GET /api/coffee-machine/shop-config — все привязки
  app.get('/api/coffee-machine/shop-config', async (req, res) => {
    try {
      const configs = [];
      if (await fileExists(SHOP_CONFIGS_DIR)) {
        const files = (await fsp.readdir(SHOP_CONFIGS_DIR)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(SHOP_CONFIGS_DIR, file), 'utf8');
            configs.push(JSON.parse(content));
          } catch (e) {
            console.error(`[CoffeeMachine] Ошибка чтения конфига ${file}:`, e.message);
          }
        }
      }
      res.json({ success: true, configs });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/coffee-machine/shop-config/:shopAddress — конфиг одного магазина
  app.get('/api/coffee-machine/shop-config/:shopAddress', async (req, res) => {
    try {
      const shopAddress = decodeURIComponent(req.params.shopAddress);
      const fileName = sanitizeId(shopAddress) + '.json';
      const filePath = path.join(SHOP_CONFIGS_DIR, fileName);

      if (await fileExists(filePath)) {
        const config = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        res.json({ success: true, config });
      } else {
        // Нет конфига — возвращаем пустой
        res.json({
          success: true,
          config: {
            shopAddress,
            machineTemplateIds: [],
            hasComputerVerification: true,
          },
        });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/coffee-machine/shop-config/:shopAddress — обновить привязку
  app.put('/api/coffee-machine/shop-config/:shopAddress', async (req, res) => {
    try {
      const shopAddress = decodeURIComponent(req.params.shopAddress);
      const config = req.body;
      config.shopAddress = shopAddress;
      config.updatedAt = new Date().toISOString();
      if (!config.createdAt) {
        config.createdAt = new Date().toISOString();
      }

      const fileName = sanitizeId(shopAddress) + '.json';
      const filePath = path.join(SHOP_CONFIGS_DIR, fileName);
      await fsp.writeFile(filePath, JSON.stringify(config, null, 2), 'utf8');

      console.log(`[CoffeeMachine] ✅ Конфиг магазина обновлён: ${shopAddress}`);
      res.json({ success: true, config });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // ОТЧЁТЫ ПО СЧЁТЧИКАМ
  // ============================================

  // GET /api/coffee-machine/reports — список отчётов
  app.get('/api/coffee-machine/reports', async (req, res) => {
    try {
      const reports = [];
      if (await fileExists(REPORTS_DIR)) {
        const files = (await fsp.readdir(REPORTS_DIR)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(REPORTS_DIR, file), 'utf8');
            const report = JSON.parse(content);

            // Фильтры
            if (req.query.shopAddress && report.shopAddress !== req.query.shopAddress) continue;
            if (req.query.status && report.status !== req.query.status) continue;
            if (req.query.employeeName && report.employeeName !== req.query.employeeName) continue;
            if (req.query.fromDate) {
              const fromDate = new Date(req.query.fromDate);
              if (new Date(report.createdAt) < fromDate) continue;
            }
            if (req.query.toDate) {
              const toDate = new Date(req.query.toDate);
              if (new Date(report.createdAt) > toDate) continue;
            }

            reports.push(report);
          } catch (e) {
            console.error(`[CoffeeMachine] Ошибка чтения отчёта ${file}:`, e.message);
          }
        }
      }
      reports.sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
      res.json({ success: true, reports });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/coffee-machine/reports/:id — один отчёт
  app.get('/api/coffee-machine/reports/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const filePath = path.join(REPORTS_DIR, `${sanitizeId(id)}.json`);

      if (await fileExists(filePath)) {
        const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        res.json({ success: true, report });
      } else {
        res.status(404).json({ success: false, error: 'Отчёт не найден' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/coffee-machine/reports — создать отчёт
  app.post('/api/coffee-machine/reports', async (req, res) => {
    try {
      const report = req.body;

      if (!report.employeeName || !report.shopAddress) {
        return res.status(400).json({ success: false, error: 'Нужно указать сотрудника и магазин' });
      }

      // Генерация ID
      if (!report.id) {
        report.id = `cm_report_${Date.now()}`;
      }
      report.createdAt = new Date().toISOString();
      report.status = report.status || 'pending';

      // Вычисление суммы и расхождения
      // Логика: компьютер (отрицательный) + сумма машин (положительная) = 0 → сходится
      if (report.readings && Array.isArray(report.readings)) {
        report.sumOfMachines = report.readings.reduce((sum, r) => sum + (r.confirmedNumber || 0), 0);
        if (report.computerNumber !== undefined) {
          const computerNum = parseFloat(report.computerNumber) || 0;
          report.discrepancyAmount = Math.abs(computerNum + report.sumOfMachines);
          report.hasDiscrepancy = report.discrepancyAmount > 0.5;
        }
      }

      // Сохранение фото счётчиков из base64
      if (report.readings) {
        for (let i = 0; i < report.readings.length; i++) {
          const reading = report.readings[i];
          if (reading.photoBase64) {
            const photoFileName = `counter_${sanitizeId(report.id)}_${i}_${Date.now()}.jpg`;
            const photoPath = path.join(PHOTOS_DIR, photoFileName);
            await fsp.writeFile(photoPath, Buffer.from(reading.photoBase64, 'base64'));
            reading.photoUrl = `/coffee-machine-photos/${photoFileName}`;
            delete reading.photoBase64;
          }
        }
      }

      // Сохранение фото компьютера из base64
      if (report.computerPhotoBase64) {
        const photoFileName = `computer_${sanitizeId(report.id)}_${Date.now()}.jpg`;
        const photoPath = path.join(PHOTOS_DIR, photoFileName);
        await fsp.writeFile(photoPath, Buffer.from(report.computerPhotoBase64, 'base64'));
        report.computerPhotoUrl = `/coffee-machine-photos/${photoFileName}`;
        delete report.computerPhotoBase64;
      }

      const filePath = path.join(REPORTS_DIR, `${sanitizeId(report.id)}.json`);
      await fsp.writeFile(filePath, JSON.stringify(report, null, 2), 'utf8');

      console.log(`[CoffeeMachine] ✅ Отчёт создан: ${report.employeeName} - ${report.shopAddress} (${report.shiftType})`);

      // Удалить pending если был
      await markPendingAsCompleted(report.shopAddress, report.shiftType, report.date);

      res.json({ success: true, report });
    } catch (error) {
      console.error('[CoffeeMachine] Ошибка создания отчёта:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/coffee-machine/reports/:id/confirm — подтвердить отчёт
  app.put('/api/coffee-machine/reports/:id/confirm', async (req, res) => {
    try {
      const { id } = req.params;
      const { confirmedByAdmin, rating } = req.body;
      const filePath = path.join(REPORTS_DIR, `${sanitizeId(id)}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Отчёт не найден' });
      }

      const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      report.status = 'confirmed';
      report.confirmedAt = new Date().toISOString();
      report.confirmedByAdmin = confirmedByAdmin;
      report.rating = rating;

      await fsp.writeFile(filePath, JSON.stringify(report, null, 2), 'utf8');
      console.log(`[CoffeeMachine] ✅ Отчёт подтверждён: ${id} (оценка: ${rating})`);
      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/coffee-machine/reports/:id/reject — отклонить отчёт
  app.put('/api/coffee-machine/reports/:id/reject', async (req, res) => {
    try {
      const { id } = req.params;
      const { rejectedByAdmin, rejectReason } = req.body;
      const filePath = path.join(REPORTS_DIR, `${sanitizeId(id)}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Отчёт не найден' });
      }

      const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      report.status = 'rejected';
      report.rejectedAt = new Date().toISOString();
      report.rejectedByAdmin = rejectedByAdmin;
      report.rejectReason = rejectReason;

      await fsp.writeFile(filePath, JSON.stringify(report, null, 2), 'utf8');
      console.log(`[CoffeeMachine] ❌ Отчёт отклонён: ${id}`);
      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/coffee-machine/reports/:id — удалить отчёт
  app.delete('/api/coffee-machine/reports/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const filePath = path.join(REPORTS_DIR, `${sanitizeId(id)}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Отчёт не найден' });
      }

      await fsp.unlink(filePath);
      console.log(`[CoffeeMachine] ❌ Отчёт удалён: ${id}`);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // OCR — распознавание чисел
  // ============================================

  // POST /api/coffee-machine/ocr — распознать число с фото
  app.post('/api/coffee-machine/ocr', async (req, res) => {
    try {
      const { imageBase64, region, preset, machineName } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Нужно передать imageBase64' });
      }

      // Загружаем OCR модуль
      let ocrModule;
      try {
        ocrModule = require('../modules/counter-ocr');
      } catch (e) {
        console.error('[CoffeeMachine] OCR модуль недоступен:', e.message);
        return res.json({
          success: false,
          number: null,
          confidence: 0,
          rawText: '',
          error: 'OCR модуль недоступен. Проверьте установку tesseract.',
        });
      }

      // Если region не передан — попробовать взять из training data
      let effectiveRegion = region || null;
      if (!effectiveRegion) {
        try {
          const samples = await loadTrainingSamples();
          // Ищем samples для этого preset + machineName (с selectedRegion)
          const matching = samples.filter(s =>
            s.selectedRegion &&
            s.preset === (preset || 'standard') &&
            (!machineName || s.machineName === machineName)
          );
          if (matching.length > 0) {
            // Усредняем region по всем подходящим samples
            const avg = { x: 0, y: 0, width: 0, height: 0 };
            for (const s of matching) {
              avg.x += s.selectedRegion.x || 0;
              avg.y += s.selectedRegion.y || 0;
              avg.width += s.selectedRegion.width || 0;
              avg.height += s.selectedRegion.height || 0;
            }
            avg.x /= matching.length;
            avg.y /= matching.length;
            avg.width /= matching.length;
            avg.height /= matching.length;
            effectiveRegion = avg;
            console.log(`[CoffeeMachine] 🎓 Используем обученный region (${matching.length} samples): x=${avg.x.toFixed(2)}, y=${avg.y.toFixed(2)}, w=${avg.width.toFixed(2)}, h=${avg.height.toFixed(2)}`);
          }
        } catch (e) {
          // Training data недоступна — продолжаем без region
        }
      }

      const result = await ocrModule.readCounterNumber(imageBase64, effectiveRegion, preset);
      // Добавляем флаг: использовался ли обученный region
      if (effectiveRegion && !region) {
        result.usedTrainingRegion = true;
      }
      res.json(result);
    } catch (error) {
      console.error('[CoffeeMachine] Ошибка OCR:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // PENDING & FAILED (для автоматизации)
  // ============================================

  // GET /api/coffee-machine/pending — pending отчёты
  app.get('/api/coffee-machine/pending', async (req, res) => {
    try {
      const pendingDir = `${DATA_DIR}/coffee-machine-pending`;
      const results = [];

      if (await fileExists(pendingDir)) {
        const files = (await fsp.readdir(pendingDir)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(pendingDir, file), 'utf8');
            const data = JSON.parse(content);
            if (data.status === 'pending') {
              results.push(data);
            }
          } catch (e) {
            console.error(`[CoffeeMachine] Ошибка чтения pending ${file}:`, e.message);
          }
        }
      }

      results.sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
      res.json(results);
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/coffee-machine/failed — failed отчёты
  app.get('/api/coffee-machine/failed', async (req, res) => {
    try {
      const pendingDir = `${DATA_DIR}/coffee-machine-pending`;
      const results = [];

      if (await fileExists(pendingDir)) {
        const files = (await fsp.readdir(pendingDir)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(pendingDir, file), 'utf8');
            const data = JSON.parse(content);
            if (data.status === 'failed') {
              results.push(data);
            }
          } catch (e) {
            console.error(`[CoffeeMachine] Ошибка чтения failed ${file}:`, e.message);
          }
        }
      }

      results.sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
      res.json(results);
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // ОБУЧЕНИЕ OCR (training)
  // ============================================

  // Загрузить samples.json
  async function loadTrainingSamples() {
    try {
      if (await fileExists(TRAINING_SAMPLES_FILE)) {
        return JSON.parse(await fsp.readFile(TRAINING_SAMPLES_FILE, 'utf8'));
      }
    } catch (e) {
      console.error('[CoffeeMachine] Ошибка чтения training samples:', e.message);
    }
    return [];
  }

  // Сохранить samples.json
  async function saveTrainingSamples(samples) {
    await fsp.writeFile(TRAINING_SAMPLES_FILE, JSON.stringify(samples, null, 2), 'utf8');
  }

  // POST /api/coffee-machine/training — сохранить обучающее фото
  app.post('/api/coffee-machine/training', async (req, res) => {
    try {
      const { photoUrl, correctNumber, selectedRegion, preset, machineName, shopAddress, trainedBy } = req.body;

      if (!photoUrl || correctNumber === undefined) {
        return res.status(400).json({ success: false, error: 'Нужно указать photoUrl и correctNumber' });
      }

      let samples = await loadTrainingSamples();

      const sample = {
        id: `train_${Date.now()}`,
        photoUrl,
        correctNumber,
        selectedRegion: selectedRegion || null,
        preset: preset || 'standard',
        machineName: machineName || '',
        shopAddress: shopAddress || '',
        trainedBy: trainedBy || '',
        createdAt: new Date().toISOString(),
      };

      // Скачать фото в локальное хранилище (если URL)
      if (photoUrl.startsWith('http') || photoUrl.startsWith('/uploads/')) {
        try {
          const https = require('https');
          const http = require('http');
          let fullUrl = photoUrl;
          if (photoUrl.startsWith('/uploads/')) {
            // Локальный файл на сервере
            const srcPath = `/var/www${photoUrl.replace('/uploads', '')}`;
            if (await fileExists(srcPath)) {
              const imgFileName = `train_${Date.now()}.jpg`;
              const destPath = path.join(TRAINING_IMAGES_DIR, imgFileName);
              await fsp.copyFile(srcPath, destPath);
              sample.localPhotoPath = `/coffee-machine-training/images/${imgFileName}`;
            }
          } else {
            // Внешний URL — скачиваем
            const imgFileName = `train_${Date.now()}.jpg`;
            const destPath = path.join(TRAINING_IMAGES_DIR, imgFileName);
            const proto = fullUrl.startsWith('https') ? https : http;
            await new Promise((resolve, reject) => {
              proto.get(fullUrl, (response) => {
                const chunks = [];
                response.on('data', chunk => chunks.push(chunk));
                response.on('end', async () => {
                  await fsp.writeFile(destPath, Buffer.concat(chunks));
                  resolve();
                });
                response.on('error', reject);
              }).on('error', reject);
            });
            sample.localPhotoPath = `/coffee-machine-training/images/${imgFileName}`;
          }
        } catch (e) {
          console.error('[CoffeeMachine] Ошибка сохранения training фото:', e.message);
          // Продолжаем без локальной копии
        }
      }

      samples.push(sample);

      // Ротация: удалить самые старые если > лимита
      if (samples.length > MAX_TRAINING_SAMPLES) {
        const toRemove = samples.splice(0, samples.length - MAX_TRAINING_SAMPLES);
        // Удалить фото старых samples
        for (const old of toRemove) {
          if (old.localPhotoPath) {
            try {
              const oldPath = path.join(DATA_DIR, old.localPhotoPath);
              if (await fileExists(oldPath)) {
                await fsp.unlink(oldPath);
              }
            } catch (e) { /* ignore */ }
          }
        }
      }

      await saveTrainingSamples(samples);
      console.log(`[CoffeeMachine] ✅ Training sample сохранён: ${sample.id} (${machineName}, число: ${correctNumber})`);
      res.json({ success: true, sample });
    } catch (error) {
      console.error('[CoffeeMachine] Ошибка сохранения training:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/coffee-machine/training — список обучающих фото (фильтр по machineName)
  app.get('/api/coffee-machine/training', async (req, res) => {
    try {
      let samples = await loadTrainingSamples();
      // Фильтрация по machineName (если передан)
      const { machineName } = req.query;
      if (machineName) {
        samples = samples.filter(s => s.machineName === machineName);
      }
      // Сортировка: новые первые
      samples.sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
      res.json({ success: true, samples, total: samples.length, limit: MAX_TRAINING_SAMPLES });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/coffee-machine/training/stats — статистика
  app.get('/api/coffee-machine/training/stats', async (req, res) => {
    try {
      const samples = await loadTrainingSamples();
      const byPreset = {};
      const byMachine = {};
      for (const s of samples) {
        const p = s.preset || 'unknown';
        byPreset[p] = (byPreset[p] || 0) + 1;
        const m = s.machineName || 'unknown';
        byMachine[m] = (byMachine[m] || 0) + 1;
      }
      res.json({
        success: true,
        total: samples.length,
        limit: MAX_TRAINING_SAMPLES,
        byPreset,
        byMachine,
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/coffee-machine/training/:id — удалить обучающее фото
  app.delete('/api/coffee-machine/training/:id', async (req, res) => {
    try {
      const { id } = req.params;
      let samples = await loadTrainingSamples();
      const idx = samples.findIndex(s => s.id === id);

      if (idx === -1) {
        return res.status(404).json({ success: false, error: 'Training sample не найден' });
      }

      const removed = samples.splice(idx, 1)[0];

      // Удалить локальное фото
      if (removed.localPhotoPath) {
        try {
          const photoPath = path.join(DATA_DIR, removed.localPhotoPath);
          if (await fileExists(photoPath)) {
            await fsp.unlink(photoPath);
          }
        } catch (e) { /* ignore */ }
      }

      await saveTrainingSamples(samples);
      console.log(`[CoffeeMachine] ❌ Training sample удалён: ${id}`);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Coffee Machine API initialized');
}

/**
 * Пометить pending как выполненный (после создания отчёта)
 */
async function markPendingAsCompleted(shopAddress, shiftType, date) {
  try {
    const pendingDir = `${DATA_DIR}/coffee-machine-pending`;
    if (!(await fileExists(pendingDir))) return;

    const files = (await fsp.readdir(pendingDir)).filter(f => f.endsWith('.json'));
    for (const file of files) {
      try {
        const filePath = path.join(pendingDir, file);
        const data = JSON.parse(await fsp.readFile(filePath, 'utf8'));

        if (data.shopAddress === shopAddress &&
            data.shiftType === shiftType &&
            data.date === date &&
            data.status === 'pending') {
          // Удаляем pending запись — отчёт сдан
          await fsp.unlink(filePath);
          console.log(`[CoffeeMachine] Pending удалён: ${shopAddress} ${shiftType} ${date}`);
          return;
        }
      } catch (e) {
        // Пропускаем файлы с ошибками
      }
    }
  } catch (error) {
    console.error('[CoffeeMachine] Ошибка удаления pending:', error.message);
  }
}

module.exports = { setupCoffeeMachineAPI, markPendingAsCompleted };

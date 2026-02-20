/**
 * Coffee Machine Counter API
 *
 * Управление шаблонами кофемашин, привязками к магазинам,
 * отчётами по счётчикам и OCR распознаванием.
 *
 * REFACTORED: Added PostgreSQL support for coffee_machine_reports (2026-02-17)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, sanitizeId } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireAuth } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_COFFEE_MACHINE === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';

// Директории данных
const TEMPLATES_DIR = `${DATA_DIR}/coffee-machine-templates`;
const SHOP_CONFIGS_DIR = `${DATA_DIR}/coffee-machine-shop-configs`;
const REPORTS_DIR = `${DATA_DIR}/coffee-machine-reports`;
const PHOTOS_DIR = `${DATA_DIR}/coffee-machine-photos`;
const TRAINING_DIR = `${DATA_DIR}/coffee-machine-training`;
const TRAINING_IMAGES_DIR = `${TRAINING_DIR}/images`;
const TRAINING_SAMPLES_FILE = `${TRAINING_DIR}/samples.json`;
const INTELLIGENCE_FILE = `${TRAINING_DIR}/machine-intelligence.json`;
const MAX_TRAINING_SAMPLES = 200;

// Ensure directories exist
(async () => {
  for (const dir of [TEMPLATES_DIR, SHOP_CONFIGS_DIR, REPORTS_DIR, PHOTOS_DIR, TRAINING_DIR, TRAINING_IMAGES_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

// ==================== DB CONVERSION (coffee_machine_reports) ====================

function dbCmReportToCamel(row) {
  return {
    id: row.id,
    employeeName: row.employee_name,
    employeePhone: row.employee_phone,
    shopAddress: row.shop_address,
    shiftType: row.shift_type,
    date: row.date,
    readings: typeof row.readings === 'string' ? JSON.parse(row.readings) : (row.readings || []),
    computerNumber: row.computer_number,
    computerPhotoUrl: row.computer_photo_url,
    sumOfMachines: row.sum_of_machines,
    hasDiscrepancy: row.has_discrepancy,
    discrepancyAmount: row.discrepancy_amount,
    status: row.status,
    rating: row.rating,
    createdAt: row.created_at,
    confirmedAt: row.confirmed_at,
    confirmedByAdmin: row.confirmed_by_admin,
    rejectedAt: row.rejected_at,
    rejectedByAdmin: row.rejected_by_admin,
    rejectReason: row.reject_reason,
    failedAt: row.failed_at,
    completedBy: row.completed_by,
    updatedAt: row.updated_at,
  };
}

function camelToDbCm(body) {
  const data = {};
  if (body.id !== undefined) data.id = body.id;
  if (body.employeeName !== undefined) data.employee_name = body.employeeName;
  if (body.employeePhone !== undefined) data.employee_phone = body.employeePhone;
  if (body.shopAddress !== undefined) data.shop_address = body.shopAddress;
  if (body.shiftType !== undefined) data.shift_type = body.shiftType;
  if (body.date !== undefined) data.date = body.date;
  if (body.readings !== undefined) data.readings = JSON.stringify(body.readings);
  if (body.computerNumber !== undefined) data.computer_number = body.computerNumber;
  if (body.computerPhotoUrl !== undefined) data.computer_photo_url = body.computerPhotoUrl;
  if (body.sumOfMachines !== undefined) data.sum_of_machines = body.sumOfMachines;
  if (body.hasDiscrepancy !== undefined) data.has_discrepancy = body.hasDiscrepancy;
  if (body.discrepancyAmount !== undefined) data.discrepancy_amount = body.discrepancyAmount;
  if (body.status !== undefined) data.status = body.status;
  if (body.rating != null) data.rating = body.rating;
  if (body.createdAt !== undefined) data.created_at = body.createdAt;
  if (body.confirmedAt !== undefined) data.confirmed_at = body.confirmedAt;
  if (body.confirmedByAdmin !== undefined) data.confirmed_by_admin = body.confirmedByAdmin;
  if (body.rejectedAt !== undefined) data.rejected_at = body.rejectedAt;
  if (body.rejectedByAdmin !== undefined) data.rejected_by_admin = body.rejectedByAdmin;
  if (body.rejectReason !== undefined) data.reject_reason = body.rejectReason;
  if (body.failedAt !== undefined) data.failed_at = body.failedAt;
  if (body.completedBy !== undefined) data.completed_by = body.completedBy;
  return data;
}

// ====================================================================================

function setupCoffeeMachineAPI(app) {

  // ============================================
  // ШАБЛОНЫ КОФЕМАШИН (developer only)
  // ============================================

  // GET /api/coffee-machine/templates — список всех шаблонов
  app.get('/api/coffee-machine/templates', requireAuth, async (req, res) => {
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
  app.get('/api/coffee-machine/templates/:id', requireAuth, async (req, res) => {
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
  app.post('/api/coffee-machine/templates', requireAuth, async (req, res) => {
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
  app.put('/api/coffee-machine/templates/:id', requireAuth, async (req, res) => {
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
  app.delete('/api/coffee-machine/templates/:id', requireAuth, async (req, res) => {
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
  app.get('/api/coffee-machine/templates/:id/image', requireAuth, async (req, res) => {
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
  app.get('/api/coffee-machine/shop-config', requireAuth, async (req, res) => {
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
  app.get('/api/coffee-machine/shop-config/:shopAddress', requireAuth, async (req, res) => {
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
  app.put('/api/coffee-machine/shop-config/:shopAddress', requireAuth, async (req, res) => {
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
  app.get('/api/coffee-machine/reports', requireAuth, async (req, res) => {
    try {
      let reports;

      if (USE_DB) {
        let query = 'SELECT * FROM coffee_machine_reports WHERE 1=1';
        const params = [];
        let idx = 1;

        if (req.query.shopAddress) {
          query += ` AND shop_address = $${idx++}`;
          params.push(req.query.shopAddress);
        }
        if (req.query.status) {
          query += ` AND status = $${idx++}`;
          params.push(req.query.status);
        }
        if (req.query.employeeName) {
          query += ` AND employee_name = $${idx++}`;
          params.push(req.query.employeeName);
        }
        if (req.query.fromDate) {
          query += ` AND created_at >= $${idx++}`;
          params.push(req.query.fromDate);
        }
        if (req.query.toDate) {
          query += ` AND created_at <= $${idx++}`;
          params.push(req.query.toDate);
        }

        query += ' ORDER BY created_at DESC';

        const result = await db.query(query, params);
        reports = result.rows.map(dbCmReportToCamel);
      } else {
        reports = [];
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
      }

      res.json({ success: true, reports });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/coffee-machine/reports/:id — один отчёт
  app.get('/api/coffee-machine/reports/:id', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);

      let report;
      if (USE_DB) {
        const row = await db.findById('coffee_machine_reports', id);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Отчёт не найден' });
        }
        report = dbCmReportToCamel(row);
      } else {
        const filePath = path.join(REPORTS_DIR, `${id}.json`);
        if (await fileExists(filePath)) {
          report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        } else {
          return res.status(404).json({ success: false, error: 'Отчёт не найден' });
        }
      }

      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/coffee-machine/reports — создать отчёт
  app.post('/api/coffee-machine/reports', requireAuth, async (req, res) => {
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

      if (USE_DB) {
        const dbData = camelToDbCm(report);
        dbData.id = report.id;
        dbData.date = report.date || (report.createdAt ? report.createdAt.split('T')[0] : null);
        dbData.updated_at = new Date().toISOString();
        await db.upsert('coffee_machine_reports', dbData);
      }

      // Dual-write: файл нужен для efficiency_calc.js и execution_chain_api.js
      const filePath = path.join(REPORTS_DIR, `${sanitizeId(report.id)}.json`);
      await writeJsonFile(filePath, report);

      console.log(`[CoffeeMachine] ✅ Отчёт создан: ${report.employeeName} - ${report.shopAddress} (${report.shiftType})`);

      // Удалить pending если был
      await markPendingAsCompleted(report.shopAddress, report.shiftType, report.date);

      res.json({ success: true, report });

      // Фоновое обновление intelligence (не блокирует ответ)
      buildMachineIntelligence().catch(e =>
        console.error('[CoffeeMachine] Intelligence update error:', e.message)
      );
    } catch (error) {
      console.error('[CoffeeMachine] Ошибка создания отчёта:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/coffee-machine/reports/:id/confirm — подтвердить отчёт
  app.put('/api/coffee-machine/reports/:id/confirm', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const { confirmedByAdmin, rating } = req.body;

      let report;
      if (USE_DB) {
        const row = await db.findById('coffee_machine_reports', id);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Отчёт не найден' });
        }
        report = dbCmReportToCamel(row);
      } else {
        const filePath = path.join(REPORTS_DIR, `${id}.json`);
        if (!(await fileExists(filePath))) {
          return res.status(404).json({ success: false, error: 'Отчёт не найден' });
        }
        report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      }

      report.status = 'confirmed';
      report.confirmedAt = new Date().toISOString();
      report.confirmedByAdmin = confirmedByAdmin;
      report.rating = rating;

      if (USE_DB) {
        await db.updateById('coffee_machine_reports', id, {
          status: 'confirmed',
          confirmed_at: report.confirmedAt,
          confirmed_by_admin: confirmedByAdmin,
          rating: rating,
          updated_at: new Date().toISOString()
        });
      }

      // Dual-write: файл
      const filePath = path.join(REPORTS_DIR, `${id}.json`);
      await writeJsonFile(filePath, report);

      console.log(`[CoffeeMachine] ✅ Отчёт подтверждён: ${id} (оценка: ${rating})`);
      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/coffee-machine/reports/:id/reject — отклонить отчёт
  app.put('/api/coffee-machine/reports/:id/reject', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const { rejectedByAdmin, rejectReason } = req.body;

      let report;
      if (USE_DB) {
        const row = await db.findById('coffee_machine_reports', id);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Отчёт не найден' });
        }
        report = dbCmReportToCamel(row);
      } else {
        const filePath = path.join(REPORTS_DIR, `${id}.json`);
        if (!(await fileExists(filePath))) {
          return res.status(404).json({ success: false, error: 'Отчёт не найден' });
        }
        report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      }

      report.status = 'rejected';
      report.rejectedAt = new Date().toISOString();
      report.rejectedByAdmin = rejectedByAdmin;
      report.rejectReason = rejectReason;

      if (USE_DB) {
        await db.updateById('coffee_machine_reports', id, {
          status: 'rejected',
          rejected_at: report.rejectedAt,
          rejected_by_admin: rejectedByAdmin,
          reject_reason: rejectReason,
          updated_at: new Date().toISOString()
        });
      }

      // Dual-write: файл
      const filePath = path.join(REPORTS_DIR, `${id}.json`);
      await writeJsonFile(filePath, report);

      console.log(`[CoffeeMachine] ❌ Отчёт отклонён: ${id}`);
      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/coffee-machine/reports/:id — удалить отчёт
  app.delete('/api/coffee-machine/reports/:id', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);

      if (USE_DB) {
        const row = await db.findById('coffee_machine_reports', id);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Отчёт не найден' });
        }
        await db.deleteById('coffee_machine_reports', id);
      }

      // Dual-write: удаляем файл тоже
      const filePath = path.join(REPORTS_DIR, `${id}.json`);
      if (await fileExists(filePath)) {
        await fsp.unlink(filePath);
      } else if (!USE_DB) {
        return res.status(404).json({ success: false, error: 'Отчёт не найден' });
      }

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
  app.post('/api/coffee-machine/ocr', requireAuth, async (req, res) => {
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

      // Загружаем intelligence для этой машины (если есть)
      let expectedRange = null;
      let machineIntel = null;
      if (machineName) {
        try {
          machineIntel = await loadMachineIntelligence(machineName);
          if (machineIntel && machineIntel.expectedNext) {
            expectedRange = machineIntel.expectedNext;
            console.log(`[CoffeeMachine] 🧠 Intelligence: ${machineName} → ожидаем ${expectedRange.min}-${expectedRange.max}`);
          }
        } catch (e) { /* intelligence недоступна — продолжаем без неё */ }
      }

      const result = await ocrModule.readCounterNumber(imageBase64, effectiveRegion, preset, expectedRange);
      // Добавляем флаг: использовался ли обученный region
      if (effectiveRegion && !region) {
        result.usedTrainingRegion = true;
      }
      // Добавляем intelligence данные в ответ
      if (machineIntel) {
        result.intelligence = {
          expectedRange: machineIntel.expectedNext,
          suggestedPreset: machineIntel.bestPreset,
          successRate: machineIntel.successRate,
          lastKnownValue: machineIntel.lastKnownValue,
        };
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
  app.get('/api/coffee-machine/pending', requireAuth, async (req, res) => {
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
  app.get('/api/coffee-machine/failed', requireAuth, async (req, res) => {
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
  app.post('/api/coffee-machine/training', requireAuth, async (req, res) => {
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
  app.get('/api/coffee-machine/training', requireAuth, async (req, res) => {
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
  app.get('/api/coffee-machine/training/stats', requireAuth, async (req, res) => {
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
  app.delete('/api/coffee-machine/training/:id', requireAuth, async (req, res) => {
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

  // ============================================
  // MACHINE INTELLIGENCE
  // ============================================

  // GET /api/coffee-machine/intelligence — вся intelligence (все машины)
  app.get('/api/coffee-machine/intelligence', requireAuth, async (req, res) => {
    try {
      const data = await loadMachineIntelligence(null);
      res.json({ success: true, intelligence: data || {}, machineCount: data ? Object.keys(data).length : 0 });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/coffee-machine/intelligence/:machineName — одна машина
  app.get('/api/coffee-machine/intelligence/:machineName', requireAuth, async (req, res) => {
    try {
      const { machineName } = req.params;
      const data = await loadMachineIntelligence(decodeURIComponent(machineName));
      if (data) {
        res.json({ success: true, machineName: decodeURIComponent(machineName), intelligence: data });
      } else {
        res.json({ success: true, machineName: decodeURIComponent(machineName), intelligence: null, message: 'Нет данных для этой машины (нужно минимум 2 отчёта)' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/coffee-machine/intelligence/rebuild — принудительная перестройка
  app.post('/api/coffee-machine/intelligence/rebuild', requireAuth, async (req, res) => {
    try {
      const intelligence = await buildMachineIntelligence();
      res.json({ success: true, machineCount: Object.keys(intelligence).length, intelligence });
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

/**
 * Построить intelligence-профили всех кофемашин из истории отчётов
 * Сканирует все отчёты, группирует по machineName, вычисляет статистику
 */
async function buildMachineIntelligence() {
  try {
    const intelligence = {};

    // Читаем все отчёты
    if (!(await fileExists(REPORTS_DIR))) return intelligence;
    const files = (await fsp.readdir(REPORTS_DIR)).filter(f => f.endsWith('.json'));

    const reportsByMachine = {}; // machineName -> [{confirmedNumber, aiReadNumber, wasManuallyEdited, date}]

    for (const file of files) {
      try {
        const report = JSON.parse(await fsp.readFile(path.join(REPORTS_DIR, file), 'utf8'));
        if (!report.readings || !Array.isArray(report.readings)) continue;

        const reportDate = report.date || (report.createdAt ? report.createdAt.slice(0, 10) : null);

        for (const reading of report.readings) {
          const name = reading.machineName;
          if (!name || !reading.confirmedNumber) continue;

          if (!reportsByMachine[name]) reportsByMachine[name] = [];
          reportsByMachine[name].push({
            confirmedNumber: reading.confirmedNumber,
            aiReadNumber: reading.aiReadNumber || null,
            wasManuallyEdited: reading.wasManuallyEdited || false,
            templateId: reading.templateId || '',
            date: reportDate,
          });
        }
      } catch (e) { /* skip broken files */ }
    }

    // Загружаем шаблоны для определения пресетов
    const templatePresets = {};
    try {
      if (await fileExists(TEMPLATES_DIR)) {
        const tFiles = (await fsp.readdir(TEMPLATES_DIR)).filter(f => f.endsWith('.json'));
        for (const tf of tFiles) {
          try {
            const tmpl = JSON.parse(await fsp.readFile(path.join(TEMPLATES_DIR, tf), 'utf8'));
            if (tmpl.id && tmpl.preset) templatePresets[tmpl.id] = tmpl.preset;
          } catch (e) { /* skip */ }
        }
      }
    } catch (e) { /* no templates */ }

    // Вычисляем intelligence для каждой машины
    for (const [machineName, readings] of Object.entries(reportsByMachine)) {
      if (readings.length < 2) continue; // нужно минимум 2 отчёта

      // Сортировка по дате
      readings.sort((a, b) => (a.date || '').localeCompare(b.date || ''));

      const values = readings.map(r => r.confirmedNumber).filter(v => v > 0);
      if (values.length === 0) continue;

      const lastKnownValue = values[values.length - 1];
      const minValue = Math.min(...values);
      const maxValue = Math.max(...values);

      // Средний дневной прирост
      let avgDailyGrowth = 0;
      const datedReadings = readings.filter(r => r.date && r.confirmedNumber > 0);
      if (datedReadings.length >= 2) {
        const first = datedReadings[0];
        const last = datedReadings[datedReadings.length - 1];
        const daysDiff = Math.max(1, (new Date(last.date) - new Date(first.date)) / (1000 * 60 * 60 * 24));
        avgDailyGrowth = Math.round((last.confirmedNumber - first.confirmedNumber) / daysDiff);
      }

      // Ожидаемый диапазон следующего значения
      const lastDate = datedReadings.length > 0 ? datedReadings[datedReadings.length - 1].date : null;
      let expectedNext = null;
      if (lastDate && avgDailyGrowth > 0) {
        const daysSinceLast = Math.max(0, (Date.now() - new Date(lastDate).getTime()) / (1000 * 60 * 60 * 24));
        const expectedValue = lastKnownValue + Math.round(avgDailyGrowth * daysSinceLast);
        // Диапазон: -10% ... +30% от среднего прироста (допуск на выходные/пики)
        const margin = Math.max(500, Math.round(avgDailyGrowth * 3));
        expectedNext = {
          min: Math.max(lastKnownValue, expectedValue - margin),
          max: expectedValue + margin,
        };
      }

      // Статистика успешности ИИ
      const withAI = readings.filter(r => r.aiReadNumber !== null && r.aiReadNumber !== undefined);
      const aiCorrect = withAI.filter(r => !r.wasManuallyEdited).length;
      const manualEdits = withAI.filter(r => r.wasManuallyEdited).length;
      const successRate = withAI.length > 0 ? Math.round((aiCorrect / withAI.length) * 1000) / 1000 : 0;

      // Лучший пресет (по templateId → preset mapping)
      const presetCounts = {};
      for (const r of readings) {
        const preset = templatePresets[r.templateId] || 'standard';
        if (!presetCounts[preset]) presetCounts[preset] = { total: 0, correct: 0 };
        presetCounts[preset].total++;
        if (r.aiReadNumber && !r.wasManuallyEdited) presetCounts[preset].correct++;
      }
      let bestPreset = 'standard';
      let bestPresetRate = 0;
      for (const [preset, stats] of Object.entries(presetCounts)) {
        const rate = stats.total > 0 ? stats.correct / stats.total : 0;
        if (rate > bestPresetRate || (rate === bestPresetRate && stats.total > (presetCounts[bestPreset]?.total || 0))) {
          bestPreset = preset;
          bestPresetRate = rate;
        }
      }

      intelligence[machineName] = {
        lastKnownValue,
        minValue,
        maxValue,
        avgDailyGrowth,
        expectedNext,
        totalReadings: readings.length,
        aiCorrect,
        manualEdits,
        successRate,
        bestPreset,
        updatedAt: new Date().toISOString(),
      };
    }

    // Dual-write: JSON + DB
    await writeJsonFile(INTELLIGENCE_FILE, intelligence);

    if (USE_DB) {
      try {
        await db.upsert('app_settings', {
          key: 'coffee_machine_intelligence',
          data: intelligence,
          updated_at: new Date().toISOString(),
        }, 'key');
      } catch (e) {
        console.error('[CoffeeMachine] DB intelligence save error:', e.message);
      }
    }

    console.log(`[CoffeeMachine] 🧠 Intelligence обновлён: ${Object.keys(intelligence).length} машин`);
    return intelligence;
  } catch (error) {
    console.error('[CoffeeMachine] Ошибка buildMachineIntelligence:', error.message);
    return {};
  }
}

/**
 * Загрузить intelligence для конкретной машины
 */
async function loadMachineIntelligence(machineName) {
  try {
    // JSON primary
    if (await fileExists(INTELLIGENCE_FILE)) {
      const data = JSON.parse(await fsp.readFile(INTELLIGENCE_FILE, 'utf8'));
      return machineName ? (data[machineName] || null) : data;
    }

    // DB fallback
    if (USE_DB) {
      const row = await db.findById('app_settings', 'coffee_machine_intelligence', 'key');
      if (row?.data) {
        return machineName ? (row.data[machineName] || null) : row.data;
      }
    }

    return null;
  } catch (e) {
    return null;
  }
}

module.exports = { setupCoffeeMachineAPI, markPendingAsCompleted, buildMachineIntelligence, loadMachineIntelligence };

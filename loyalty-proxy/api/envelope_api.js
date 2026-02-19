/**
 * Envelope API
 * Вопросы конверта + Отчёты конвертов + Pending/Failed
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 * REFACTORED: Added PostgreSQL support with USE_DB_ENVELOPE flag (2026-02-17)
 */

const fs = require('fs');
const fsp = require('fs').promises;
const path = require('path');
const { sanitizeId, fileExists } = require('../utils/file_helpers');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireAuth } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_ENVELOPE === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';

// ==================== DB CONVERSION ====================

function dbEnvelopeReportToCamel(row) {
  return {
    id: row.id,
    employeeName: row.employee_name,
    employeePhone: row.employee_phone,
    shopAddress: row.shop_address,
    shiftType: row.shift_type,
    status: row.status,
    createdAt: row.created_at,
    oooZReportPhotoUrl: row.ooo_z_report_photo_url,
    oooRevenue: row.ooo_revenue != null ? Number(row.ooo_revenue) : null,
    oooCash: row.ooo_cash != null ? Number(row.ooo_cash) : null,
    oooExpenses: typeof row.ooo_expenses === 'string' ? JSON.parse(row.ooo_expenses) : (row.ooo_expenses || []),
    oooEnvelopePhotoUrl: row.ooo_envelope_photo_url,
    oooOfdNotSent: row.ooo_ofd_not_sent,
    ipZReportPhotoUrl: row.ip_z_report_photo_url,
    ipRevenue: row.ip_revenue != null ? Number(row.ip_revenue) : null,
    ipCash: row.ip_cash != null ? Number(row.ip_cash) : null,
    expenses: typeof row.expenses === 'string' ? JSON.parse(row.expenses) : (row.expenses || []),
    ipEnvelopePhotoUrl: row.ip_envelope_photo_url,
    ipOfdNotSent: row.ip_ofd_not_sent,
    rating: row.rating,
    confirmedAt: row.confirmed_at,
    confirmedByAdmin: row.confirmed_by_admin,
    failedAt: row.failed_at,
  };
}

/**
 * Конвертация camelCase body в snake_case для DB INSERT/UPDATE
 */
function camelToDbEnvelope(body) {
  const data = {};
  if (body.id !== undefined) data.id = body.id;
  if (body.employeeName !== undefined) data.employee_name = body.employeeName;
  if (body.employeePhone !== undefined) data.employee_phone = body.employeePhone;
  if (body.shopAddress !== undefined) data.shop_address = body.shopAddress;
  if (body.shiftType !== undefined) data.shift_type = body.shiftType;
  if (body.status !== undefined) data.status = body.status;
  if (body.oooZReportPhotoUrl !== undefined) data.ooo_z_report_photo_url = body.oooZReportPhotoUrl;
  if (body.oooRevenue !== undefined) data.ooo_revenue = body.oooRevenue;
  if (body.oooCash !== undefined) data.ooo_cash = body.oooCash;
  if (body.oooExpenses !== undefined) data.ooo_expenses = JSON.stringify(body.oooExpenses || []);
  if (body.oooEnvelopePhotoUrl !== undefined) data.ooo_envelope_photo_url = body.oooEnvelopePhotoUrl;
  if (body.oooOfdNotSent !== undefined) data.ooo_ofd_not_sent = body.oooOfdNotSent;
  if (body.ipZReportPhotoUrl !== undefined) data.ip_z_report_photo_url = body.ipZReportPhotoUrl;
  if (body.ipRevenue !== undefined) data.ip_revenue = body.ipRevenue;
  if (body.ipCash !== undefined) data.ip_cash = body.ipCash;
  if (body.expenses !== undefined) data.expenses = JSON.stringify(body.expenses || []);
  if (body.ipEnvelopePhotoUrl !== undefined) data.ip_envelope_photo_url = body.ipEnvelopePhotoUrl;
  if (body.ipOfdNotSent !== undefined) data.ip_ofd_not_sent = body.ipOfdNotSent;
  if (body.rating !== undefined) data.rating = body.rating;
  if (body.confirmedAt !== undefined) data.confirmed_at = body.confirmedAt;
  if (body.confirmedByAdmin !== undefined) data.confirmed_by_admin = body.confirmedByAdmin;
  return data;
}

const ENVELOPE_QUESTIONS_DIR = `${DATA_DIR}/envelope-questions`;
const ENVELOPE_REPORTS_DIR = `${DATA_DIR}/envelope-reports`;

/**
 * Найти файл отчёта конверта по ID.
 * Пробует sanitized имя (новые файлы), затем оригинальное (старые с кириллицей).
 * Возвращает путь к файлу или null.
 */
async function findEnvelopeReportFile(rawId) {
  // 1. Sanitized путь (новые файлы)
  const sanitized = rawId.replace(/[^a-zA-Z0-9_\-]/g, '_');
  const sanitizedPath = path.join(ENVELOPE_REPORTS_DIR, `${sanitized}.json`);
  if (await fileExists(sanitizedPath)) return sanitizedPath;

  // 2. Оригинальное имя с защитой от path traversal (старые файлы с кириллицей)
  const safeId = rawId.replace(/[\/\\]/g, '').replace(/\.\./g, '');
  const originalPath = path.join(ENVELOPE_REPORTS_DIR, `${safeId}.json`);
  // Проверяем что путь не выходит за пределы директории
  if (path.resolve(originalPath).startsWith(path.resolve(ENVELOPE_REPORTS_DIR)) && await fileExists(originalPath)) {
    return originalPath;
  }

  return null;
}

// Создаем директории, если их нет
(async () => {
  if (!await fileExists(ENVELOPE_QUESTIONS_DIR)) {
    await fsp.mkdir(ENVELOPE_QUESTIONS_DIR, { recursive: true });
  }
  if (!await fileExists(ENVELOPE_REPORTS_DIR)) {
    await fsp.mkdir(ENVELOPE_REPORTS_DIR, { recursive: true });
  }
})();

// Дефолтные вопросы конверта для инициализации
const defaultEnvelopeQuestions = [
  { id: 'envelope_q_1', title: 'Выбор смены', description: 'Выберите тип смены', type: 'shift_select', section: 'general', order: 1, isRequired: true, isActive: true },
  { id: 'envelope_q_2', title: 'ООО: Z-отчет', description: 'Сфотографируйте Z-отчет ООО', type: 'photo', section: 'ooo', order: 2, isRequired: true, isActive: true },
  { id: 'envelope_q_3', title: 'ООО: Выручка и наличные', description: 'Введите данные ООО', type: 'numbers', section: 'ooo', order: 3, isRequired: true, isActive: true },
  { id: 'envelope_q_4', title: 'ООО: Фото конверта', description: 'Сфотографируйте сформированный конверт ООО', type: 'photo', section: 'ooo', order: 4, isRequired: true, isActive: true },
  { id: 'envelope_q_5', title: 'ИП: Z-отчет', description: 'Сфотографируйте Z-отчет ИП', type: 'photo', section: 'ip', order: 5, isRequired: true, isActive: true },
  { id: 'envelope_q_6', title: 'ИП: Выручка и наличные', description: 'Введите данные ИП', type: 'numbers', section: 'ip', order: 6, isRequired: true, isActive: true },
  { id: 'envelope_q_7', title: 'ИП: Расходы', description: 'Добавьте расходы', type: 'expenses', section: 'ip', order: 7, isRequired: true, isActive: true },
  { id: 'envelope_q_8', title: 'ИП: Фото конверта', description: 'Сфотографируйте сформированный конверт ИП', type: 'photo', section: 'ip', order: 8, isRequired: true, isActive: true },
  { id: 'envelope_q_9', title: 'Итог', description: 'Проверьте данные и отправьте отчет', type: 'summary', section: 'general', order: 9, isRequired: true, isActive: true },
];

// Инициализация дефолтных вопросов при старте
(async function initEnvelopeQuestions() {
  try {
    const files = await fsp.readdir(ENVELOPE_QUESTIONS_DIR);
    if (files.filter(f => f.endsWith('.json')).length === 0) {
      console.log('Инициализация дефолтных вопросов конверта...');
      for (const q of defaultEnvelopeQuestions) {
        const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${q.id}.json`);
        await fsp.writeFile(filePath, JSON.stringify({ ...q, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() }, null, 2));
      }
      console.log('✅ Дефолтные вопросы конверта созданы');
    }
  } catch (e) {
    console.error('Ошибка инициализации вопросов конверта:', e);
  }
})();

function setupEnvelopeAPI(app) {
  // ========== ENVELOPE QUESTIONS ==========

  // GET /api/envelope-questions - получить все вопросы
  app.get('/api/envelope-questions', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/envelope-questions');
      const files = await fsp.readdir(ENVELOPE_QUESTIONS_DIR);
      const questions = [];

      for (const file of files) {
        if (file.endsWith('.json')) {
          const filePath = path.join(ENVELOPE_QUESTIONS_DIR, file);
          const data = await fsp.readFile(filePath, 'utf8');
          const question = JSON.parse(data);
          questions.push(question);
        }
      }

      // Сортировка по order
      questions.sort((a, b) => (a.order || 0) - (b.order || 0));

      res.json({ success: true, questions });
    } catch (error) {
      console.error('Ошибка получения вопросов конверта:', error);
      res.status(500).json({ success: false, error: error.message, questions: [] });
    }
  });

  // GET /api/envelope-questions/:id - получить один вопрос
  app.get('/api/envelope-questions/:id', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const sanitizedId2 = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${sanitizedId2}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({ success: false, error: 'Вопрос не найден' });
      }

      const data = await fsp.readFile(filePath, 'utf8');
      const question = JSON.parse(data);

      res.json({ success: true, question });
    } catch (error) {
      console.error('Ошибка получения вопроса конверта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/envelope-questions - создать вопрос
  app.post('/api/envelope-questions', requireAuth, async (req, res) => {
    try {
      console.log('POST /api/envelope-questions:', JSON.stringify(req.body).substring(0, 200));

      const questionId = req.body.id || `envelope_q_${Date.now()}`;
      const sanitizedId2 = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${sanitizedId2}.json`);

      const question = {
        id: questionId,
        title: req.body.title || '',
        description: req.body.description || '',
        type: req.body.type || 'photo',
        section: req.body.section || 'general',
        order: req.body.order || 1,
        isRequired: req.body.isRequired !== false,
        isActive: req.body.isActive !== false,
        referencePhotoUrl: req.body.referencePhotoUrl || null,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };

      await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
      console.log('Вопрос конверта создан:', filePath);

      res.json({ success: true, question });
    } catch (error) {
      console.error('Ошибка создания вопроса конверта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/envelope-questions/:id - обновить вопрос
  app.put('/api/envelope-questions/:id', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('PUT /api/envelope-questions:', id);

      const sanitizedId2 = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${sanitizedId2}.json`);

      // Если файл не существует, создаем новый
      let question = {};
      if (await fileExists(filePath)) {
        const existingData = await fsp.readFile(filePath, 'utf8');
        question = JSON.parse(existingData);
      }

      // Обновляем поля
      if (req.body.title !== undefined) question.title = req.body.title;
      if (req.body.description !== undefined) question.description = req.body.description;
      if (req.body.type !== undefined) question.type = req.body.type;
      if (req.body.section !== undefined) question.section = req.body.section;
      if (req.body.order !== undefined) question.order = req.body.order;
      if (req.body.isRequired !== undefined) question.isRequired = req.body.isRequired;
      if (req.body.isActive !== undefined) question.isActive = req.body.isActive;
      if (req.body.referencePhotoUrl !== undefined) question.referencePhotoUrl = req.body.referencePhotoUrl;

      question.id = id;
      question.updatedAt = new Date().toISOString();
      if (!question.createdAt) question.createdAt = new Date().toISOString();

      await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
      console.log('Вопрос конверта обновлен:', filePath);

      res.json({ success: true, question });
    } catch (error) {
      console.error('Ошибка обновления вопроса конверта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/envelope-questions/:id - удалить вопрос
  app.delete('/api/envelope-questions/:id', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('DELETE /api/envelope-questions:', id);

      const sanitizedId2 = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${sanitizedId2}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({ success: false, error: 'Вопрос не найден' });
      }

      await fsp.unlink(filePath);
      console.log('Вопрос конверта удален:', filePath);

      res.json({ success: true, message: 'Вопрос успешно удален' });
    } catch (error) {
      console.error('Ошибка удаления вопроса конверта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ========== ENVELOPE REPORTS ==========

  // GET /api/envelope-reports - получить все отчеты
  app.get('/api/envelope-reports', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/envelope-reports:', req.query);
      let { shopAddress, status, fromDate, toDate } = req.query;

      // Декодируем shop address если он URL-encoded
      if (shopAddress && shopAddress.includes('%')) {
        try {
          shopAddress = decodeURIComponent(shopAddress);
        } catch (e) {
          console.error('  ⚠️ Ошибка декодирования shopAddress:', e);
        }
      }

      const normalizedShopAddress = shopAddress ? shopAddress.trim() : null;

      let reports;

      if (USE_DB) {
        let query = 'SELECT * FROM envelope_reports WHERE 1=1';
        const params = [];
        let paramIdx = 1;

        if (normalizedShopAddress) {
          query += ` AND TRIM(shop_address) = $${paramIdx++}`;
          params.push(normalizedShopAddress);
        }
        if (status) {
          query += ` AND status = $${paramIdx++}`;
          params.push(status);
        }
        if (fromDate) {
          query += ` AND created_at >= $${paramIdx++}`;
          params.push(fromDate);
        }
        if (toDate) {
          query += ` AND created_at <= $${paramIdx++}`;
          params.push(toDate);
        }

        query += ' ORDER BY created_at DESC';

        const result = await db.query(query, params);
        reports = result.rows.map(dbEnvelopeReportToCamel);
      } else {
        reports = [];
        if (await fileExists(ENVELOPE_REPORTS_DIR)) {
          const files = await fsp.readdir(ENVELOPE_REPORTS_DIR);
          const jsonFiles = files.filter(f => f.endsWith('.json'));

          for (const file of jsonFiles) {
            try {
              const content = await fsp.readFile(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8');
              const report = JSON.parse(content);

              if (normalizedShopAddress) {
                if (report.shopAddress.trim() !== normalizedShopAddress) continue;
              }
              if (status && report.status !== status) continue;
              if (fromDate && new Date(report.createdAt) < new Date(fromDate)) continue;
              if (toDate && new Date(report.createdAt) > new Date(toDate)) continue;

              reports.push(report);
            } catch (e) {
              console.error(`Ошибка чтения ${file}:`, e);
            }
          }
        }
        reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      }

      if (isPaginationRequested(req.query)) {
        res.json(createPaginatedResponse(reports, req.query, 'reports'));
      } else {
        res.json({ success: true, reports });
      }
    } catch (error) {
      console.error('Ошибка получения отчетов конвертов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/envelope-reports/expired - получить просроченные отчеты
  app.get('/api/envelope-reports/expired', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/envelope-reports/expired');

      let reports;

      if (USE_DB) {
        const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
        const result = await db.query(
          "SELECT * FROM envelope_reports WHERE status = 'pending' AND created_at < $1 ORDER BY created_at ASC",
          [cutoff]
        );
        reports = result.rows.map(dbEnvelopeReportToCamel);
      } else {
        reports = [];
        if (await fileExists(ENVELOPE_REPORTS_DIR)) {
          const files = await fsp.readdir(ENVELOPE_REPORTS_DIR);
          const jsonFiles = files.filter(f => f.endsWith('.json'));

          for (const file of jsonFiles) {
            try {
              const content = await fsp.readFile(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8');
              const report = JSON.parse(content);

              if (report.status === 'pending') {
                const createdAt = new Date(report.createdAt);
                const now = new Date();
                const diffHours = (now - createdAt) / (1000 * 60 * 60);

                if (diffHours >= 24) {
                  reports.push(report);
                }
              }
            } catch (e) {
              console.error(`Ошибка чтения ${file}:`, e);
            }
          }
        }
        reports.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
      }

      res.json({ success: true, reports });
    } catch (error) {
      console.error('Ошибка получения просроченных отчетов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/envelope-reports/:id - получить один отчет
  app.get('/api/envelope-reports/:id', requireAuth, async (req, res) => {
    try {
      const rawId = decodeURIComponent(req.params.id);
      console.log('GET /api/envelope-reports/:id', rawId);

      let report;

      if (USE_DB) {
        const row = await db.findById('envelope_reports', rawId);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Отчет не найден' });
        }
        report = dbEnvelopeReportToCamel(row);
      } else {
        const filePath = await findEnvelopeReportFile(rawId);
        if (!filePath) {
          return res.status(404).json({ success: false, error: 'Отчет не найден' });
        }
        const content = await fsp.readFile(filePath, 'utf8');
        report = JSON.parse(content);
      }

      // IDOR: проверка владельца или админ
      const ownerPhone = report.employeePhone || report.phone;
      if (ownerPhone && req.user && req.user.phone !== ownerPhone && !req.user.isAdmin) {
        return res.status(403).json({ success: false, error: 'Доступ запрещён' });
      }

      res.json({ success: true, report });
    } catch (error) {
      console.error('Ошибка получения отчета:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/envelope-reports - создать новый отчет
  app.post('/api/envelope-reports', requireAuth, async (req, res) => {
    try {
      console.log('POST /api/envelope-reports:', JSON.stringify(req.body).substring(0, 300));

      const reportId = req.body.id || `envelope_report_${Date.now()}`;
      const now = new Date().toISOString();
      const report = {
        ...req.body,
        id: reportId,
        createdAt: now,
        status: req.body.status || 'pending',
      };

      if (USE_DB) {
        const dbData = camelToDbEnvelope(report);
        dbData.id = reportId;
        dbData.created_at = now;
        dbData.date = now.split('T')[0];
        dbData.updated_at = now;
        await db.insert('envelope_reports', dbData);
      }

      // Dual-write: всегда сохраняем в файл (для efficiency_calc, dashboard_batch)
      const sanitizedId2 = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_REPORTS_DIR, `${sanitizedId2}.json`);
      // Boy Scout: fs.promises.writeFile → writeJsonFile
      await writeJsonFile(filePath, report);
      console.log('Отчет конверта создан:', filePath);

      res.json({ success: true, report });
    } catch (error) {
      console.error('Ошибка создания отчета конверта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/envelope-reports/:id - обновить отчет
  app.put('/api/envelope-reports/:id', requireAuth, async (req, res) => {
    try {
      const rawId = decodeURIComponent(req.params.id);
      console.log('PUT /api/envelope-reports/:id', rawId);

      let existingReport;

      if (USE_DB) {
        const row = await db.findById('envelope_reports', rawId);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Отчет не найден' });
        }
        existingReport = dbEnvelopeReportToCamel(row);
      } else {
        const filePath = await findEnvelopeReportFile(rawId);
        if (!filePath) {
          return res.status(404).json({ success: false, error: 'Отчет не найден' });
        }
        const content = await fsp.readFile(filePath, 'utf8');
        existingReport = JSON.parse(content);
      }

      // IDOR: проверка владельца или админ
      const ownerPhone = existingReport.employeePhone || existingReport.phone;
      if (ownerPhone && req.user && req.user.phone !== ownerPhone && !req.user.isAdmin) {
        return res.status(403).json({ success: false, error: 'Доступ запрещён' });
      }

      const updatedReport = {
        ...existingReport,
        ...req.body,
        id: existingReport.id,
        createdAt: existingReport.createdAt,
      };

      if (USE_DB) {
        const dbUpdates = camelToDbEnvelope(req.body);
        // Не перезаписываем id и created_at
        delete dbUpdates.id;
        delete dbUpdates.created_at;
        dbUpdates.updated_at = new Date().toISOString();
        await db.updateById('envelope_reports', rawId, dbUpdates);
      }

      // Dual-write: всегда обновляем файл
      const filePath = await findEnvelopeReportFile(rawId);
      if (filePath) {
        // Boy Scout: fs.promises.writeFile → writeJsonFile
        await writeJsonFile(filePath, updatedReport);
      } else {
        // Файла нет — создаём с sanitized именем
        const sanitizedId = rawId.replace(/[^a-zA-Z0-9_\-]/g, '_');
        await writeJsonFile(path.join(ENVELOPE_REPORTS_DIR, `${sanitizedId}.json`), updatedReport);
      }
      console.log('Отчет конверта обновлён:', rawId);

      res.json({ success: true, report: updatedReport });
    } catch (error) {
      console.error('Ошибка обновления отчета:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/envelope-reports/:id/confirm - подтвердить отчет с оценкой (только админ)
  app.put('/api/envelope-reports/:id/confirm', requireAuth, async (req, res) => {
    try {
      // Подтверждение отчёта — только админ
      if (!req.user || !req.user.isAdmin) {
        return res.status(403).json({ success: false, error: 'Только администратор может подтвердить отчёт' });
      }

      const rawId = decodeURIComponent(req.params.id);
      const { confirmedByAdmin, rating } = req.body;
      console.log('PUT /api/envelope-reports/:id/confirm', rawId, confirmedByAdmin, rating);

      const now = new Date().toISOString();
      let report;

      if (USE_DB) {
        const row = await db.findById('envelope_reports', rawId);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Отчет не найден' });
        }
        await db.updateById('envelope_reports', rawId, {
          status: 'confirmed',
          confirmed_at: now,
          confirmed_by_admin: confirmedByAdmin,
          rating: rating,
          updated_at: now
        });
        report = dbEnvelopeReportToCamel(row);
        report.status = 'confirmed';
        report.confirmedAt = now;
        report.confirmedByAdmin = confirmedByAdmin;
        report.rating = rating;
      } else {
        const filePath = await findEnvelopeReportFile(rawId);
        if (!filePath) {
          return res.status(404).json({ success: false, error: 'Отчет не найден' });
        }
        const content = await fsp.readFile(filePath, 'utf8');
        report = JSON.parse(content);
        report.status = 'confirmed';
        report.confirmedAt = now;
        report.confirmedByAdmin = confirmedByAdmin;
        report.rating = rating;
      }

      // Dual-write: всегда обновляем файл
      const filePath = await findEnvelopeReportFile(rawId);
      if (filePath) {
        // Boy Scout: fs.promises.writeFile → writeJsonFile
        await writeJsonFile(filePath, report);
      }
      console.log('Отчет конверта подтверждён:', rawId);

      res.json({ success: true, report });
    } catch (error) {
      console.error('Ошибка подтверждения отчета:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/envelope-reports/:id - удалить отчет (только админ)
  app.delete('/api/envelope-reports/:id', requireAuth, async (req, res) => {
    try {
      // Удаление отчёта — только админ
      if (!req.user || !req.user.isAdmin) {
        return res.status(403).json({ success: false, error: 'Только администратор может удалить отчёт' });
      }

      const rawId = decodeURIComponent(req.params.id);
      console.log('DELETE /api/envelope-reports/:id', rawId);

      if (USE_DB) {
        const deleted = await db.deleteById('envelope_reports', rawId);
        if (!deleted) {
          return res.status(404).json({ success: false, error: 'Отчет не найден' });
        }
      }

      // Dual-write: удаляем файл тоже
      const filePath = await findEnvelopeReportFile(rawId);
      if (filePath) {
        await fsp.unlink(filePath);
      } else if (!USE_DB) {
        // Только если не DB — файл обязателен
        return res.status(404).json({ success: false, error: 'Отчет не найден' });
      }
      console.log('Отчет конверта удалён:', rawId);

      res.json({ success: true, message: 'Отчет успешно удален' });
    } catch (error) {
      console.error('Ошибка удаления отчета:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ========== ENVELOPE PENDING/FAILED ==========

  // GET /api/envelope-pending - получить pending отчеты
  app.get('/api/envelope-pending', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/envelope-pending');
      const pendingDir = `${DATA_DIR}/envelope-pending`;
      const reports = [];

      if (await fileExists(pendingDir)) {
        const files = await fs.promises.readdir(pendingDir);

        for (const file of files) {
          if (file.startsWith('pending_env_')) {
            try {
              const content = await fs.promises.readFile(path.join(pendingDir, file), 'utf8');
              const data = JSON.parse(content);
              if (data.status === 'pending') {
                reports.push(data);
              }
            } catch (e) {
              console.error(`Ошибка чтения ${file}:`, e);
            }
          }
        }
      }

      // Сортируем по дате создания (новые первыми)
      reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      res.json(reports);
    } catch (error) {
      console.error('Ошибка получения pending отчетов:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // GET /api/envelope-failed - получить failed отчеты
  app.get('/api/envelope-failed', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/envelope-failed');
      const pendingDir = `${DATA_DIR}/envelope-pending`;
      const reports = [];

      if (await fileExists(pendingDir)) {
        const files = await fs.promises.readdir(pendingDir);

        for (const file of files) {
          if (file.startsWith('pending_env_')) {
            try {
              const content = await fs.promises.readFile(path.join(pendingDir, file), 'utf8');
              const data = JSON.parse(content);
              if (data.status === 'failed') {
                reports.push(data);
              }
            } catch (e) {
              console.error(`Ошибка чтения ${file}:`, e);
            }
          }
        }
      }

      // Сортируем по дате создания (новые первыми)
      reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      res.json(reports);
    } catch (error) {
      console.error('Ошибка получения failed отчетов:', error);
      res.status(500).json({ error: error.message });
    }
  });

  console.log(`✅ Envelope API initialized (reports storage: ${USE_DB ? 'PostgreSQL + dual-write' : 'JSON files'})`);
}

module.exports = { setupEnvelopeAPI };

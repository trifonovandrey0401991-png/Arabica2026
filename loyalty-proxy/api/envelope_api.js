/**
 * Envelope API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const ENVELOPE_REPORTS_DIR = `${DATA_DIR}/envelope-reports`;
const ENVELOPE_QUESTIONS_DIR = `${DATA_DIR}/envelope-questions`;

// Sanitize ID to prevent path traversal
function sanitizeId(id) {
  if (!id || typeof id !== 'string') return '';
  return id.replace(/[^a-zA-Z0-9_\-\.]/g, '_');
}

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Ensure directories exist (async IIFE)
(async () => {
  for (const dir of [ENVELOPE_REPORTS_DIR, ENVELOPE_QUESTIONS_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

// Дефолтные вопросы
const defaultEnvelopeQuestions = [
  { id: 'envelope_q_1', title: 'Выбор смены', type: 'shift_select', section: 'general', order: 1, isRequired: true, isActive: true },
  { id: 'envelope_q_2', title: 'ООО: Z-отчет', type: 'photo', section: 'ooo', order: 2, isRequired: true, isActive: true },
  { id: 'envelope_q_3', title: 'ООО: Выручка и наличные', type: 'numbers', section: 'ooo', order: 3, isRequired: true, isActive: true },
  { id: 'envelope_q_4', title: 'ООО: Фото конверта', type: 'photo', section: 'ooo', order: 4, isRequired: true, isActive: true },
  { id: 'envelope_q_5', title: 'ИП: Z-отчет', type: 'photo', section: 'ip', order: 5, isRequired: true, isActive: true },
  { id: 'envelope_q_6', title: 'ИП: Выручка и наличные', type: 'numbers', section: 'ip', order: 6, isRequired: true, isActive: true },
  { id: 'envelope_q_7', title: 'ИП: Расходы', type: 'expenses', section: 'ip', order: 7, isRequired: true, isActive: true },
  { id: 'envelope_q_8', title: 'ИП: Фото конверта', type: 'photo', section: 'ip', order: 8, isRequired: true, isActive: true },
  { id: 'envelope_q_9', title: 'Итог', type: 'summary', section: 'general', order: 9, isRequired: true, isActive: true },
];

async function initEnvelopeQuestions() {
  try {
    if (!(await fileExists(ENVELOPE_QUESTIONS_DIR))) {
      await fsp.mkdir(ENVELOPE_QUESTIONS_DIR, { recursive: true });
    }
    const files = await fsp.readdir(ENVELOPE_QUESTIONS_DIR);
    if (files.filter(f => f.endsWith('.json')).length === 0) {
      console.log('Инициализация дефолтных вопросов конверта...');
      for (const q of defaultEnvelopeQuestions) {
        await fsp.writeFile(path.join(ENVELOPE_QUESTIONS_DIR, q.id + '.json'), JSON.stringify(q, null, 2));
      }
    }
  } catch (error) {
    console.error('Error initializing envelope questions:', error);
  }
}

function setupEnvelopeAPI(app) {
  // Initialize questions asynchronously
  initEnvelopeQuestions();

  // ===== ENVELOPE REPORTS =====

  app.get('/api/envelope-reports', async (req, res) => {
    try {
      console.log('GET /api/envelope-reports');
      const files = await fsp.readdir(ENVELOPE_REPORTS_DIR);
      const reports = [];

      for (const file of files) {
        if (file.endsWith('.json')) {
          try {
            const data = JSON.parse(await fsp.readFile(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8'));
            if (req.query.shopAddress && data.shopAddress !== req.query.shopAddress) continue;
            if (req.query.status && data.status !== req.query.status) continue;
            if (req.query.fromDate && new Date(data.createdAt) < new Date(req.query.fromDate)) continue;
            if (req.query.toDate && new Date(data.createdAt) > new Date(req.query.toDate)) continue;
            reports.push(data);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }
      reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, reports });
    } catch (error) {
      console.error('Error getting envelope reports:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/envelope-reports/expired', async (req, res) => {
    try {
      const files = await fsp.readdir(ENVELOPE_REPORTS_DIR);
      const reports = [];
      const now = new Date();

      for (const file of files) {
        if (file.endsWith('.json')) {
          try {
            const data = JSON.parse(await fsp.readFile(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8'));
            if (data.status !== 'confirmed') {
              const hoursDiff = (now - new Date(data.createdAt)) / (1000 * 60 * 60);
              if (hoursDiff >= 24) reports.push(data);
            }
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }
      reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, reports });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/envelope-reports/:id', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_REPORTS_DIR, sanitizeId(req.params.id) + '.json');
      if (await fileExists(filePath)) {
        res.json({ success: true, report: JSON.parse(await fsp.readFile(filePath, 'utf8')) });
      } else {
        res.json({ success: false, error: 'Report not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/envelope-reports', async (req, res) => {
    try {
      const report = req.body;
      if (!report.id) report.id = 'envelope_' + Date.now();
      report.createdAt = report.createdAt || new Date().toISOString();
      report.status = report.status || 'pending';
      await fsp.writeFile(path.join(ENVELOPE_REPORTS_DIR, sanitizeId(report.id) + '.json'), JSON.stringify(report, null, 2));
      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/envelope-reports/:id', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_REPORTS_DIR, sanitizeId(req.params.id) + '.json');
      if (!(await fileExists(filePath))) return res.json({ success: false, error: 'Report not found' });
      const updated = { ...JSON.parse(await fsp.readFile(filePath, 'utf8')), ...req.body };
      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2));
      res.json({ success: true, report: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/envelope-reports/:id/confirm', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_REPORTS_DIR, sanitizeId(req.params.id) + '.json');
      if (!(await fileExists(filePath))) return res.json({ success: false, error: 'Report not found' });
      const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      report.status = 'confirmed';
      report.confirmedAt = new Date().toISOString();
      report.confirmedByAdmin = req.body.confirmedByAdmin;
      report.rating = req.body.rating;
      await fsp.writeFile(filePath, JSON.stringify(report, null, 2));
      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Отклонить отчет конверта
  app.put('/api/envelope-reports/:id/reject', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_REPORTS_DIR, sanitizeId(req.params.id) + '.json');
      if (!(await fileExists(filePath))) return res.json({ success: false, error: 'Report not found' });
      const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      report.status = 'rejected';
      report.rejectedAt = new Date().toISOString();
      report.rejectedByAdmin = req.body.rejectedByAdmin;
      report.rejectReason = req.body.rejectReason || '';
      await fsp.writeFile(filePath, JSON.stringify(report, null, 2));
      console.log(`✅ Envelope report rejected: ${req.params.id}`);
      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/envelope-reports/:id', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_REPORTS_DIR, sanitizeId(req.params.id) + '.json');
      if (!(await fileExists(filePath))) return res.json({ success: false, error: 'Report not found' });
      await fsp.unlink(filePath);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ENVELOPE QUESTIONS =====

  app.get('/api/envelope-questions', async (req, res) => {
    try {
      const files = await fsp.readdir(ENVELOPE_QUESTIONS_DIR);
      const questions = [];
      for (const f of files) {
        if (f.endsWith('.json')) {
          try {
            const q = JSON.parse(await fsp.readFile(path.join(ENVELOPE_QUESTIONS_DIR, f), 'utf8'));
            questions.push(q);
          } catch (e) {
            console.error(`Error reading ${f}:`, e);
          }
        }
      }
      questions.sort((a, b) => (a.order || 0) - (b.order || 0));
      res.json({ success: true, questions });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/envelope-questions/:id', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, sanitizeId(req.params.id) + '.json');
      if (await fileExists(filePath)) {
        res.json({ success: true, question: JSON.parse(await fsp.readFile(filePath, 'utf8')) });
      } else {
        res.json({ success: false, error: 'Question not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/envelope-questions', async (req, res) => {
    try {
      const question = req.body;
      if (!question.id) question.id = 'envelope_q_' + Date.now();
      await fsp.writeFile(path.join(ENVELOPE_QUESTIONS_DIR, sanitizeId(question.id) + '.json'), JSON.stringify(question, null, 2));
      res.json({ success: true, question });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/envelope-questions/:id', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, sanitizeId(req.params.id) + '.json');
      if (!(await fileExists(filePath))) return res.json({ success: false, error: 'Question not found' });
      const updated = { ...JSON.parse(await fsp.readFile(filePath, 'utf8')), ...req.body, id: req.params.id };
      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2));
      res.json({ success: true, question: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/envelope-questions/:id', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, sanitizeId(req.params.id) + '.json');
      if (!(await fileExists(filePath))) return res.json({ success: false, error: 'Question not found' });
      await fsp.unlink(filePath);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Envelope API initialized');
}

module.exports = { setupEnvelopeAPI };

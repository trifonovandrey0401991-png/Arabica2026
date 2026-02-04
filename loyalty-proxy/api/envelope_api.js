const fs = require('fs');
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || DATA_DIR;

const ENVELOPE_REPORTS_DIR = `${DATA_DIR}/envelope-reports`;
const ENVELOPE_QUESTIONS_DIR = `${DATA_DIR}/envelope-questions`;

// Создаем директории
[ENVELOPE_REPORTS_DIR, ENVELOPE_QUESTIONS_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

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

function initEnvelopeQuestions() {
  const files = fs.readdirSync(ENVELOPE_QUESTIONS_DIR);
  if (files.filter(f => f.endsWith('.json')).length === 0) {
    console.log('Инициализация дефолтных вопросов конверта...');
    for (const q of defaultEnvelopeQuestions) {
      fs.writeFileSync(path.join(ENVELOPE_QUESTIONS_DIR, q.id + '.json'), JSON.stringify(q, null, 2));
    }
  }
}

function setupEnvelopeAPI(app) {
  initEnvelopeQuestions();

  // ===== ENVELOPE REPORTS =====

  app.get('/api/envelope-reports', async (req, res) => {
    try {
      console.log('GET /api/envelope-reports');
      const files = fs.readdirSync(ENVELOPE_REPORTS_DIR);
      const reports = [];

      for (const file of files) {
        if (file.endsWith('.json')) {
          const data = JSON.parse(fs.readFileSync(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8'));
          if (req.query.shopAddress && data.shopAddress !== req.query.shopAddress) continue;
          if (req.query.status && data.status !== req.query.status) continue;
          if (req.query.fromDate && new Date(data.createdAt) < new Date(req.query.fromDate)) continue;
          if (req.query.toDate && new Date(data.createdAt) > new Date(req.query.toDate)) continue;
          reports.push(data);
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
      const files = fs.readdirSync(ENVELOPE_REPORTS_DIR);
      const reports = [];
      const now = new Date();

      for (const file of files) {
        if (file.endsWith('.json')) {
          const data = JSON.parse(fs.readFileSync(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8'));
          if (data.status !== 'confirmed') {
            const hoursDiff = (now - new Date(data.createdAt)) / (1000 * 60 * 60);
            if (hoursDiff >= 24) reports.push(data);
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
      const filePath = path.join(ENVELOPE_REPORTS_DIR, req.params.id + '.json');
      if (fs.existsSync(filePath)) {
        res.json({ success: true, report: JSON.parse(fs.readFileSync(filePath, 'utf8')) });
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
      fs.writeFileSync(path.join(ENVELOPE_REPORTS_DIR, report.id + '.json'), JSON.stringify(report, null, 2));
      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/envelope-reports/:id', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_REPORTS_DIR, req.params.id + '.json');
      if (!fs.existsSync(filePath)) return res.json({ success: false, error: 'Report not found' });
      const updated = { ...JSON.parse(fs.readFileSync(filePath, 'utf8')), ...req.body };
      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2));
      res.json({ success: true, report: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/envelope-reports/:id/confirm', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_REPORTS_DIR, req.params.id + '.json');
      if (!fs.existsSync(filePath)) return res.json({ success: false, error: 'Report not found' });
      const report = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      report.status = 'confirmed';
      report.confirmedAt = new Date().toISOString();
      report.confirmedByAdmin = req.body.confirmedByAdmin;
      report.rating = req.body.rating;
      fs.writeFileSync(filePath, JSON.stringify(report, null, 2));
      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/envelope-reports/:id', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_REPORTS_DIR, req.params.id + '.json');
      if (!fs.existsSync(filePath)) return res.json({ success: false, error: 'Report not found' });
      fs.unlinkSync(filePath);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ENVELOPE QUESTIONS =====

  app.get('/api/envelope-questions', async (req, res) => {
    try {
      const files = fs.readdirSync(ENVELOPE_QUESTIONS_DIR);
      const questions = files.filter(f => f.endsWith('.json'))
        .map(f => JSON.parse(fs.readFileSync(path.join(ENVELOPE_QUESTIONS_DIR, f), 'utf8')))
        .sort((a, b) => (a.order || 0) - (b.order || 0));
      res.json({ success: true, questions });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/envelope-questions/:id', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, req.params.id + '.json');
      if (fs.existsSync(filePath)) {
        res.json({ success: true, question: JSON.parse(fs.readFileSync(filePath, 'utf8')) });
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
      fs.writeFileSync(path.join(ENVELOPE_QUESTIONS_DIR, question.id + '.json'), JSON.stringify(question, null, 2));
      res.json({ success: true, question });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/envelope-questions/:id', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, req.params.id + '.json');
      if (!fs.existsSync(filePath)) return res.json({ success: false, error: 'Question not found' });
      const updated = { ...JSON.parse(fs.readFileSync(filePath, 'utf8')), ...req.body, id: req.params.id };
      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2));
      res.json({ success: true, question: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/envelope-questions/:id', async (req, res) => {
    try {
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, req.params.id + '.json');
      if (!fs.existsSync(filePath)) return res.json({ success: false, error: 'Question not found' });
      fs.unlinkSync(filePath);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Envelope API initialized');
}

module.exports = { setupEnvelopeAPI };

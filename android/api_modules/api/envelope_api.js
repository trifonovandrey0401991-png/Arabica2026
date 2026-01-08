const fs = require('fs');
const path = require('path');

const ENVELOPE_REPORTS_DIR = '/var/www/envelope-reports';
const ENVELOPE_QUESTIONS_DIR = '/var/www/envelope-questions';
const ENVELOPE_QUESTION_PHOTOS_DIR = '/var/www/envelope-question-photos';

[ENVELOPE_REPORTS_DIR, ENVELOPE_QUESTIONS_DIR, ENVELOPE_QUESTION_PHOTOS_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

function setupEnvelopeAPI(app, uploadEnvelopePhoto) {
  // ===== ENVELOPE REPORTS (Сдача смены) =====

  app.get('/api/envelope-reports', async (req, res) => {
    try {
      console.log('GET /api/envelope-reports');
      const { shopAddress, date, employeeName } = req.query;
      const reports = [];

      if (fs.existsSync(ENVELOPE_REPORTS_DIR)) {
        const files = fs.readdirSync(ENVELOPE_REPORTS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8');
            const report = JSON.parse(content);

            if (shopAddress && report.shopAddress !== shopAddress) continue;
            if (date && !report.createdAt?.startsWith(date)) continue;
            if (employeeName && report.employeeName !== employeeName) continue;

            reports.push(report);
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

  app.post('/api/envelope-reports', async (req, res) => {
    try {
      const report = req.body;
      console.log('POST /api/envelope-reports:', report.shopAddress);

      if (!report.id) {
        report.id = `envelope_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      report.createdAt = report.createdAt || new Date().toISOString();

      const filePath = path.join(ENVELOPE_REPORTS_DIR, `${report.id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(report, null, 2), 'utf8');

      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/envelope-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      console.log('GET /api/envelope-reports/:reportId', reportId);

      const filePath = path.join(ENVELOPE_REPORTS_DIR, `${reportId}.json`);

      if (fs.existsSync(filePath)) {
        const report = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        res.json({ success: true, report });
      } else {
        res.status(404).json({ success: false, error: 'Report not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/envelope-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const updates = req.body;
      console.log('PUT /api/envelope-reports/:reportId', reportId);

      const filePath = path.join(ENVELOPE_REPORTS_DIR, `${reportId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Report not found' });
      }

      const report = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const updated = { ...report, ...updates, updatedAt: new Date().toISOString() };

      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, report: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/envelope-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      console.log('DELETE /api/envelope-reports/:reportId', reportId);

      const filePath = path.join(ENVELOPE_REPORTS_DIR, `${reportId}.json`);

      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Report not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ENVELOPE QUESTIONS =====

  app.get('/api/envelope-questions', async (req, res) => {
    try {
      console.log('GET /api/envelope-questions');
      const questions = [];

      if (fs.existsSync(ENVELOPE_QUESTIONS_DIR)) {
        const files = fs.readdirSync(ENVELOPE_QUESTIONS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(ENVELOPE_QUESTIONS_DIR, file), 'utf8');
            questions.push(JSON.parse(content));
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      questions.sort((a, b) => (a.order || 0) - (b.order || 0));
      res.json({ success: true, questions });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/envelope-questions', async (req, res) => {
    try {
      const question = req.body;
      console.log('POST /api/envelope-questions:', question.text?.substring(0, 50));

      if (!question.id) {
        question.id = `envq_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      question.createdAt = question.createdAt || new Date().toISOString();
      question.updatedAt = new Date().toISOString();

      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${question.id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(question, null, 2), 'utf8');

      res.json({ success: true, question });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/envelope-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const updates = req.body;
      console.log('PUT /api/envelope-questions:', questionId);

      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${questionId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      const question = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const updated = { ...question, ...updates, updatedAt: new Date().toISOString() };

      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, question: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/envelope-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      console.log('DELETE /api/envelope-questions:', questionId);

      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${questionId}.json`);

      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Question not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ENVELOPE QUESTION PHOTOS =====

  if (uploadEnvelopePhoto) {
    app.post('/api/envelope-questions/:questionId/reference-photo', uploadEnvelopePhoto.single('photo'), async (req, res) => {
      try {
        const { questionId } = req.params;
        console.log('POST /api/envelope-questions/:questionId/reference-photo', questionId);

        if (!req.file) {
          return res.status(400).json({ success: false, error: 'No file uploaded' });
        }

        const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${questionId}.json`);

        if (!fs.existsSync(filePath)) {
          return res.status(404).json({ success: false, error: 'Question not found' });
        }

        const question = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        question.referencePhotoUrl = `/envelope-question-photos/${req.file.filename}`;
        question.updatedAt = new Date().toISOString();

        fs.writeFileSync(filePath, JSON.stringify(question, null, 2), 'utf8');
        res.json({ success: true, question });
      } catch (error) {
        res.status(500).json({ success: false, error: error.message });
      }
    });
  }

  console.log('✅ Envelope API initialized');
}

module.exports = { setupEnvelopeAPI };

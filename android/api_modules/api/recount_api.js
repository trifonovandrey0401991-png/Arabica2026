const fs = require('fs');
const path = require('path');

const RECOUNT_REPORTS_DIR = '/var/www/recount-reports';
const RECOUNT_QUESTIONS_DIR = '/var/www/recount-questions';

[RECOUNT_REPORTS_DIR, RECOUNT_QUESTIONS_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

function setupRecountAPI(app, upload) {
  // ===== RECOUNT REPORTS =====

  app.post('/api/recount-reports', async (req, res) => {
    try {
      const report = req.body;
      console.log('POST /api/recount-reports');

      if (!report.id) {
        report.id = `recount_${Date.now()}`;
      }

      const sanitizedId = report.id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(RECOUNT_REPORTS_DIR, `${sanitizedId}.json`);

      report.savedAt = new Date().toISOString();
      fs.writeFileSync(filePath, JSON.stringify(report, null, 2), 'utf8');

      console.log('Recount report saved:', filePath);
      res.json({ success: true, report });
    } catch (error) {
      console.error('Error saving recount report:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/recount-reports', async (req, res) => {
    try {
      console.log('GET /api/recount-reports');
      const reports = [];

      if (fs.existsSync(RECOUNT_REPORTS_DIR)) {
        const files = fs.readdirSync(RECOUNT_REPORTS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(RECOUNT_REPORTS_DIR, file), 'utf8');
            const report = JSON.parse(content);

            // Фильтрация
            if (req.query.employeeName && report.employeeName !== req.query.employeeName) continue;
            if (req.query.shopAddress && report.shopAddress !== req.query.shopAddress) continue;
            if (req.query.date) {
              const queryDate = req.query.date.split('T')[0];
              const reportDate = (report.createdAt || report.savedAt || '').split('T')[0];
              if (reportDate !== queryDate) continue;
            }

            reports.push(report);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      reports.sort((a, b) => new Date(b.createdAt || b.savedAt || 0) - new Date(a.createdAt || a.savedAt || 0));
      res.json({ success: true, reports });
    } catch (error) {
      console.error('Error getting recount reports:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/recount-reports/:reportId/rating', async (req, res) => {
    try {
      const { reportId } = req.params;
      const { rating, confirmedByAdmin } = req.body;

      console.log(`POST /api/recount-reports/${reportId}/rating`, rating);

      const sanitizedId = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(RECOUNT_REPORTS_DIR, `${sanitizedId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Report not found' });
      }

      const report = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      report.rating = rating;
      report.confirmedByAdmin = confirmedByAdmin;
      report.confirmedAt = new Date().toISOString();

      fs.writeFileSync(filePath, JSON.stringify(report, null, 2), 'utf8');

      res.json({ success: true, report });
    } catch (error) {
      console.error('Error rating recount report:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/recount-reports/:reportId/notify', async (req, res) => {
    try {
      const { reportId } = req.params;
      console.log(`POST /api/recount-reports/${reportId}/notify`);
      res.json({ success: true, message: 'Notification sent' });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== RECOUNT QUESTIONS =====

  app.get('/api/recount-questions', async (req, res) => {
    try {
      console.log('GET /api/recount-questions');
      const questions = [];

      if (fs.existsSync(RECOUNT_QUESTIONS_DIR)) {
        const files = fs.readdirSync(RECOUNT_QUESTIONS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(RECOUNT_QUESTIONS_DIR, file), 'utf8');
            const question = JSON.parse(content);

            // Фильтрация по shopAddress
            if (req.query.shopAddress) {
              if (question.shopAddresses && Array.isArray(question.shopAddresses)) {
                if (!question.shopAddresses.includes(req.query.shopAddress)) continue;
              }
            }

            questions.push(question);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      questions.sort((a, b) => (a.order || 0) - (b.order || 0));
      res.json({ success: true, questions });
    } catch (error) {
      console.error('Error getting recount questions:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/recount-questions', async (req, res) => {
    try {
      const question = req.body;
      console.log('POST /api/recount-questions');

      if (!question.id) {
        question.id = `recount_question_${Date.now()}`;
      }

      const sanitizedId = question.id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

      question.createdAt = question.createdAt || new Date().toISOString();
      fs.writeFileSync(filePath, JSON.stringify(question, null, 2), 'utf8');

      res.json({ success: true, question });
    } catch (error) {
      console.error('Error creating recount question:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/recount-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const updateData = req.body;

      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      const existing = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const updated = { ...existing, ...updateData, id: questionId };
      updated.updatedAt = new Date().toISOString();

      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, question: updated });
    } catch (error) {
      console.error('Error updating recount question:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/recount-questions/:questionId/reference-photo', upload.single('photo'), async (req, res) => {
    try {
      const { questionId } = req.params;
      const { shopAddress } = req.body;

      if (!req.file) {
        return res.status(400).json({ success: false, error: 'No photo provided' });
      }

      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const sanitizedShop = (shopAddress || 'default').replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ]/g, '_');

      const photoFileName = `ref_${sanitizedId}_${sanitizedShop}_${Date.now()}.jpg`;
      const photoDir = '/var/www/shift-photos';
      const photoPath = path.join(photoDir, photoFileName);

      fs.renameSync(req.file.path, photoPath);

      const photoUrl = `https://arabica26.ru/shift-photos/${photoFileName}`;
      res.json({ success: true, photoUrl });
    } catch (error) {
      console.error('Error uploading reference photo:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/recount-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;

      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      fs.unlinkSync(filePath);
      res.json({ success: true });
    } catch (error) {
      console.error('Error deleting recount question:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Recount API initialized');
}

module.exports = { setupRecountAPI };

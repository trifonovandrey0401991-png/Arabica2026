const fs = require('fs');
const path = require('path');

const SHIFT_REPORTS_DIR = '/var/www/shift-reports';
const SHIFT_QUESTIONS_DIR = '/var/www/shift-questions';
const SHIFT_HANDOVER_REPORTS_DIR = '/var/www/shift-handover-reports';
const SHIFT_HANDOVER_QUESTIONS_DIR = '/var/www/shift-handover-questions';

[SHIFT_REPORTS_DIR, SHIFT_QUESTIONS_DIR, SHIFT_HANDOVER_REPORTS_DIR, SHIFT_HANDOVER_QUESTIONS_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

function setupShiftsAPI(app, upload, uploadShiftHandoverPhoto) {
  // ===== SHIFT REPORTS (Пересменка) =====

  app.get('/api/shift-reports', async (req, res) => {
    try {
      console.log('GET /api/shift-reports');
      const reports = [];

      if (fs.existsSync(SHIFT_REPORTS_DIR)) {
        const files = fs.readdirSync(SHIFT_REPORTS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(SHIFT_REPORTS_DIR, file), 'utf8');
            const report = JSON.parse(content);

            if (req.query.employeeName && report.employeeName !== req.query.employeeName) continue;
            if (req.query.shopAddress && report.shopAddress !== req.query.shopAddress) continue;

            reports.push(report);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      reports.sort((a, b) => new Date(b.createdAt || b.timestamp || 0) - new Date(a.createdAt || a.timestamp || 0));
      res.json({ success: true, reports });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/shift-reports', async (req, res) => {
    try {
      const report = req.body;
      console.log('POST /api/shift-reports');

      if (!report.id) {
        report.id = `shift_${Date.now()}`;
      }

      const sanitizedId = report.id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_REPORTS_DIR, `${sanitizedId}.json`);

      report.savedAt = new Date().toISOString();
      fs.writeFileSync(filePath, JSON.stringify(report, null, 2), 'utf8');

      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== SHIFT QUESTIONS =====

  app.get('/api/shift-questions', async (req, res) => {
    try {
      console.log('GET /api/shift-questions');
      const questions = [];

      if (fs.existsSync(SHIFT_QUESTIONS_DIR)) {
        const files = fs.readdirSync(SHIFT_QUESTIONS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(SHIFT_QUESTIONS_DIR, file), 'utf8');
            const question = JSON.parse(content);

            if (req.query.shopAddress && question.shopAddresses) {
              if (!question.shopAddresses.includes(req.query.shopAddress)) continue;
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
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/shift-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (fs.existsSync(filePath)) {
        const question = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        res.json({ success: true, question });
      } else {
        res.status(404).json({ success: false, error: 'Question not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/shift-questions', async (req, res) => {
    try {
      const question = req.body;

      if (!question.id) {
        question.id = `shift_question_${Date.now()}`;
      }

      const sanitizedId = question.id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

      question.createdAt = new Date().toISOString();
      fs.writeFileSync(filePath, JSON.stringify(question, null, 2), 'utf8');

      res.json({ success: true, question });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/shift-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const updateData = req.body;

      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      const existing = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const updated = { ...existing, ...updateData, id: questionId };
      updated.updatedAt = new Date().toISOString();

      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, question: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/shift-questions/:questionId/reference-photo', upload.single('photo'), async (req, res) => {
    try {
      const { questionId } = req.params;
      const { shopAddress } = req.body;

      if (!req.file) {
        return res.status(400).json({ success: false, error: 'No photo provided' });
      }

      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const photoFileName = `shift_ref_${sanitizedId}_${Date.now()}.jpg`;
      const photoPath = path.join('/var/www/shift-photos', photoFileName);

      fs.renameSync(req.file.path, photoPath);

      const photoUrl = `https://arabica26.ru/shift-photos/${photoFileName}`;
      res.json({ success: true, photoUrl });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/shift-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      fs.unlinkSync(filePath);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== SHIFT HANDOVER REPORTS (Сдача смены) =====

  app.get('/api/shift-handover-reports', async (req, res) => {
    try {
      console.log('GET /api/shift-handover-reports');
      const reports = [];

      if (fs.existsSync(SHIFT_HANDOVER_REPORTS_DIR)) {
        const files = fs.readdirSync(SHIFT_HANDOVER_REPORTS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(SHIFT_HANDOVER_REPORTS_DIR, file), 'utf8');
            const report = JSON.parse(content);

            if (req.query.employeeName && report.employeeName !== req.query.employeeName) continue;
            if (req.query.shopAddress && report.shopAddress !== req.query.shopAddress) continue;

            reports.push(report);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      reports.sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
      res.json({ success: true, reports });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/shift-handover-reports/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_HANDOVER_REPORTS_DIR, `${sanitizedId}.json`);

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

  app.post('/api/shift-handover-reports', async (req, res) => {
    try {
      const report = req.body;

      if (!report.id) {
        report.id = `shift_handover_${Date.now()}`;
      }

      const sanitizedId = report.id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_HANDOVER_REPORTS_DIR, `${sanitizedId}.json`);

      report.createdAt = report.createdAt || new Date().toISOString();
      fs.writeFileSync(filePath, JSON.stringify(report, null, 2), 'utf8');

      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/shift-handover-reports/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_HANDOVER_REPORTS_DIR, `${sanitizedId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Report not found' });
      }

      fs.unlinkSync(filePath);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== SHIFT HANDOVER QUESTIONS =====

  app.get('/api/shift-handover-questions', async (req, res) => {
    try {
      console.log('GET /api/shift-handover-questions');
      const questions = [];

      if (fs.existsSync(SHIFT_HANDOVER_QUESTIONS_DIR)) {
        const files = fs.readdirSync(SHIFT_HANDOVER_QUESTIONS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(SHIFT_HANDOVER_QUESTIONS_DIR, file), 'utf8');
            const question = JSON.parse(content);

            if (req.query.shopAddress && question.shopAddresses) {
              if (!question.shopAddresses.includes(req.query.shopAddress)) continue;
            }
            if (req.query.targetRole && question.targetRole !== req.query.targetRole) continue;

            questions.push(question);
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

  app.get('/api/shift-handover-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (fs.existsSync(filePath)) {
        const question = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        res.json({ success: true, question });
      } else {
        res.status(404).json({ success: false, error: 'Question not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/shift-handover-questions', async (req, res) => {
    try {
      const question = req.body;

      if (!question.id) {
        question.id = `shift_handover_question_${Date.now()}`;
      }

      const sanitizedId = question.id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

      question.createdAt = new Date().toISOString();
      fs.writeFileSync(filePath, JSON.stringify(question, null, 2), 'utf8');

      res.json({ success: true, question });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/shift-handover-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const updateData = req.body;

      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      const existing = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const updated = { ...existing, ...updateData, id: questionId };
      updated.updatedAt = new Date().toISOString();

      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, question: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/shift-handover-questions/:questionId/reference-photo', uploadShiftHandoverPhoto.single('photo'), async (req, res) => {
    try {
      const { questionId } = req.params;

      if (!req.file) {
        return res.status(400).json({ success: false, error: 'No photo provided' });
      }

      const photoUrl = `https://arabica26.ru/shift-handover-question-photos/${req.file.filename}`;
      res.json({ success: true, photoUrl });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/shift-handover-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      fs.unlinkSync(filePath);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Shifts API initialized');
}

module.exports = { setupShiftsAPI };

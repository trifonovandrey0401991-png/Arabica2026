/**
 * Shifts API - Shift Reports and Shift Handover
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const SHIFT_REPORTS_DIR = `${DATA_DIR}/shift-reports`;
const SHIFT_QUESTIONS_DIR = `${DATA_DIR}/shift-questions`;
const SHIFT_HANDOVER_REPORTS_DIR = `${DATA_DIR}/shift-handover-reports`;
const SHIFT_HANDOVER_QUESTIONS_DIR = `${DATA_DIR}/shift-handover-questions`;
const PENDING_SHIFT_DIR = `${DATA_DIR}/pending-shift-reports`;

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
  for (const dir of [SHIFT_REPORTS_DIR, SHIFT_QUESTIONS_DIR, SHIFT_HANDOVER_REPORTS_DIR, SHIFT_HANDOVER_QUESTIONS_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

// Helper to sanitize string for file ID
function sanitizeForId(str) {
  return str.replace(/[^a-zA-Zа-яА-ЯёЁ0-9]/g, '_');
}

// Mark pending shift as completed when shift report is created
async function markPendingShiftCompleted(shopAddress, employeeName) {
  try {
    const now = new Date();
    const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
    const currentHour = now.getHours();

    // Determine shift type based on current hour
    const shiftType = currentHour < 14 ? 'morning' : 'evening';

    const shopKey = sanitizeForId(shopAddress);
    const pendingId = `pending_${shopKey}_${todayStr}_${shiftType}`;
    const pendingFile = path.join(PENDING_SHIFT_DIR, `${pendingId}.json`);

    console.log(`🔍 Looking for pending file: ${pendingFile}`);

    if (await fileExists(pendingFile)) {
      const pending = JSON.parse(await fsp.readFile(pendingFile, 'utf8'));
      pending.status = 'completed';
      pending.completedBy = employeeName;
      pending.completedAt = now.toISOString();

      await fsp.writeFile(pendingFile, JSON.stringify(pending, null, 2), 'utf8');
      console.log(`✅ Marked pending shift as completed: ${pendingId}`);
      return true;
    } else {
      console.log(`⚠️ Pending file not found: ${pendingFile}`);
      return false;
    }
  } catch (error) {
    console.error('❌ Error marking pending shift completed:', error);
    return false;
  }
}

function setupShiftsAPI(app, upload, uploadShiftHandoverPhoto) {
  // ===== SHIFT REPORTS (Пересменка) =====

  app.get('/api/shift-reports', async (req, res) => {
    try {
      console.log('GET /api/shift-reports');
      const reports = [];

      if (await fileExists(SHIFT_REPORTS_DIR)) {
        const files = (await fsp.readdir(SHIFT_REPORTS_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(SHIFT_REPORTS_DIR, file), 'utf8');
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
      console.log('POST /api/shift-reports', report.shopAddress, report.employeeName);

      if (!report.id) {
        report.id = `shift_${Date.now()}`;
      }

      const sanitizedId = report.id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_REPORTS_DIR, `${sanitizedId}.json`);

      report.savedAt = new Date().toISOString();
      await fsp.writeFile(filePath, JSON.stringify(report, null, 2), 'utf8');

      // ✅ AUTO-MARK PENDING SHIFT AS COMPLETED
      if (report.shopAddress && report.employeeName) {
        await markPendingShiftCompleted(report.shopAddress, report.employeeName);
      }

      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Get single shift report
  app.get('/api/shift-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const sanitizedId = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_REPORTS_DIR, `${sanitizedId}.json`);

      if (await fileExists(filePath)) {
        const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        res.json({ success: true, report });
      } else {
        res.status(404).json({ success: false, error: 'Report not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Update shift report (for confirmation/rating)
  app.put('/api/shift-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const updates = req.body;
      console.log('PUT /api/shift-reports', reportId);

      const sanitizedId = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_REPORTS_DIR, `${sanitizedId}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Report not found' });
      }

      const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      const updated = { ...report, ...updates, updatedAt: new Date().toISOString() };

      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2), 'utf8');
      console.log('✅ Shift report updated:', reportId);
      res.json({ success: true, report: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Delete shift report
  app.delete('/api/shift-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const sanitizedId = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_REPORTS_DIR, `${sanitizedId}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Report not found' });
      }

      await fsp.unlink(filePath);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== SHIFT QUESTIONS =====

  app.get('/api/shift-questions', async (req, res) => {
    try {
      console.log('GET /api/shift-questions');
      const questions = [];

      if (await fileExists(SHIFT_QUESTIONS_DIR)) {
        const files = (await fsp.readdir(SHIFT_QUESTIONS_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(SHIFT_QUESTIONS_DIR, file), 'utf8');
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

      if (await fileExists(filePath)) {
        const question = JSON.parse(await fsp.readFile(filePath, 'utf8'));
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
      await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');

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

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      const existing = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      const updated = { ...existing, ...updateData, id: questionId };
      updated.updatedAt = new Date().toISOString();

      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2), 'utf8');
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
      const photoPath = path.join(`${DATA_DIR}/shift-photos`, photoFileName);

      await fsp.rename(req.file.path, photoPath);

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

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      await fsp.unlink(filePath);
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

      if (await fileExists(SHIFT_HANDOVER_REPORTS_DIR)) {
        const files = (await fsp.readdir(SHIFT_HANDOVER_REPORTS_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(SHIFT_HANDOVER_REPORTS_DIR, file), 'utf8');
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

      if (await fileExists(filePath)) {
        const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
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
      await fsp.writeFile(filePath, JSON.stringify(report, null, 2), 'utf8');

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

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Report not found' });
      }

      await fsp.unlink(filePath);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Update shift handover report (for confirmation/rating)
  app.put('/api/shift-handover-reports/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const updates = req.body;
      console.log('PUT /api/shift-handover-reports', id);

      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_HANDOVER_REPORTS_DIR, `${sanitizedId}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Report not found' });
      }

      const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      const updated = { ...report, ...updates, updatedAt: new Date().toISOString() };

      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2), 'utf8');
      console.log('✅ Shift handover report updated:', id);
      res.json({ success: true, report: updated });
    } catch (error) {
      console.error('Error updating shift handover report:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== SHIFT HANDOVER QUESTIONS =====

  app.get('/api/shift-handover-questions', async (req, res) => {
    try {
      console.log('GET /api/shift-handover-questions');
      const questions = [];

      if (await fileExists(SHIFT_HANDOVER_QUESTIONS_DIR)) {
        const files = (await fsp.readdir(SHIFT_HANDOVER_QUESTIONS_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(SHIFT_HANDOVER_QUESTIONS_DIR, file), 'utf8');
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

      if (await fileExists(filePath)) {
        const question = JSON.parse(await fsp.readFile(filePath, 'utf8'));
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
      await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');

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

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      const existing = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      const updated = { ...existing, ...updateData, id: questionId };
      updated.updatedAt = new Date().toISOString();

      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2), 'utf8');
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

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      await fsp.unlink(filePath);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Shifts API initialized');
}

module.exports = { setupShiftsAPI };

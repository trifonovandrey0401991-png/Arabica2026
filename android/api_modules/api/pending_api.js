const fs = require('fs');
const path = require('path');

const PENDING_RECOUNT_DIR = '/var/www/pending-recount-reports';
const PENDING_SHIFT_DIR = '/var/www/pending-shift-reports';
const PENDING_SHIFT_HANDOVER_FILE = '/var/www/pending-shift-handover-reports.json';

[PENDING_RECOUNT_DIR, PENDING_SHIFT_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

function setupPendingAPI(app) {
  // ===== PENDING RECOUNT REPORTS =====

  app.get('/api/pending-recount-reports', async (req, res) => {
    try {
      console.log('GET /api/pending-recount-reports');
      const { shopAddress, employeeName } = req.query;
      const reports = [];

      if (fs.existsSync(PENDING_RECOUNT_DIR)) {
        const files = fs.readdirSync(PENDING_RECOUNT_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(PENDING_RECOUNT_DIR, file), 'utf8');
            const report = JSON.parse(content);

            if (shopAddress && report.shopAddress !== shopAddress) continue;
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

  app.post('/api/pending-recount-reports', async (req, res) => {
    try {
      const report = req.body;
      console.log('POST /api/pending-recount-reports:', report.shopAddress);

      if (!report.id) {
        report.id = `pending_recount_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      report.createdAt = report.createdAt || new Date().toISOString();
      report.status = report.status || 'pending';

      const filePath = path.join(PENDING_RECOUNT_DIR, `${report.id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(report, null, 2), 'utf8');

      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/pending-recount-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const filePath = path.join(PENDING_RECOUNT_DIR, `${reportId}.json`);

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

  app.put('/api/pending-recount-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const updates = req.body;
      const filePath = path.join(PENDING_RECOUNT_DIR, `${reportId}.json`);

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

  app.delete('/api/pending-recount-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const filePath = path.join(PENDING_RECOUNT_DIR, `${reportId}.json`);

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

  // ===== PENDING SHIFT REPORTS =====

  app.get('/api/pending-shift-reports', async (req, res) => {
    try {
      console.log('GET /api/pending-shift-reports');
      const { shopAddress, employeeName } = req.query;
      const reports = [];

      if (fs.existsSync(PENDING_SHIFT_DIR)) {
        const files = fs.readdirSync(PENDING_SHIFT_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(PENDING_SHIFT_DIR, file), 'utf8');
            const report = JSON.parse(content);

            if (shopAddress && report.shopAddress !== shopAddress) continue;
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

  app.post('/api/pending-shift-reports', async (req, res) => {
    try {
      const report = req.body;
      console.log('POST /api/pending-shift-reports:', report.shopAddress);

      if (!report.id) {
        report.id = `pending_shift_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      report.createdAt = report.createdAt || new Date().toISOString();
      report.status = report.status || 'pending';

      const filePath = path.join(PENDING_SHIFT_DIR, `${report.id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(report, null, 2), 'utf8');

      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/pending-shift-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const filePath = path.join(PENDING_SHIFT_DIR, `${reportId}.json`);

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

  app.put('/api/pending-shift-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const updates = req.body;
      const filePath = path.join(PENDING_SHIFT_DIR, `${reportId}.json`);

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

  app.delete('/api/pending-shift-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const filePath = path.join(PENDING_SHIFT_DIR, `${reportId}.json`);

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

  // ===== PENDING SHIFT HANDOVER REPORTS =====

  app.get('/api/pending-shift-handover-reports', async (req, res) => {
    try {
      console.log('GET /api/pending-shift-handover-reports');

      let data = { reports: [] };
      if (fs.existsSync(PENDING_SHIFT_HANDOVER_FILE)) {
        data = JSON.parse(fs.readFileSync(PENDING_SHIFT_HANDOVER_FILE, 'utf8'));
      }

      res.json({ success: true, reports: data.reports || [] });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/pending-shift-handover-reports', async (req, res) => {
    try {
      const report = req.body;
      console.log('POST /api/pending-shift-handover-reports');

      let data = { reports: [] };
      if (fs.existsSync(PENDING_SHIFT_HANDOVER_FILE)) {
        data = JSON.parse(fs.readFileSync(PENDING_SHIFT_HANDOVER_FILE, 'utf8'));
      }

      if (!report.id) {
        report.id = `pending_handover_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }
      report.createdAt = report.createdAt || new Date().toISOString();

      data.reports.push(report);
      fs.writeFileSync(PENDING_SHIFT_HANDOVER_FILE, JSON.stringify(data, null, 2), 'utf8');

      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/pending-shift-handover-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      console.log('DELETE /api/pending-shift-handover-reports:', reportId);

      let data = { reports: [] };
      if (fs.existsSync(PENDING_SHIFT_HANDOVER_FILE)) {
        data = JSON.parse(fs.readFileSync(PENDING_SHIFT_HANDOVER_FILE, 'utf8'));
      }

      const index = data.reports.findIndex(r => r.id === reportId);
      if (index !== -1) {
        data.reports.splice(index, 1);
        fs.writeFileSync(PENDING_SHIFT_HANDOVER_FILE, JSON.stringify(data, null, 2), 'utf8');
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Report not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Pending Reports API initialized');
}

module.exports = { setupPendingAPI };

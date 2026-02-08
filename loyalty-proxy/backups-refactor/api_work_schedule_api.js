const fs = require('fs');
const path = require('path');

const WORK_SCHEDULES_DIR = '/var/www/work-schedules';
const WORK_SCHEDULE_TEMPLATES_DIR = '/var/www/work-schedule-templates';

[WORK_SCHEDULES_DIR, WORK_SCHEDULE_TEMPLATES_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

function setupWorkScheduleAPI(app) {
  // ===== WORK SCHEDULES =====

  app.get('/api/work-schedule/:shopAddress', async (req, res) => {
    try {
      const { shopAddress } = req.params;
      const { year, month } = req.query;
      console.log('GET /api/work-schedule:', shopAddress, year, month);

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const filePath = path.join(WORK_SCHEDULES_DIR, `${sanitizedAddress}_${year}_${month}.json`);

      if (fs.existsSync(filePath)) {
        const schedule = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        res.json({ success: true, schedule });
      } else {
        res.json({ success: true, schedule: { shopAddress, year: parseInt(year), month: parseInt(month), days: {} } });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/work-schedule', async (req, res) => {
    try {
      const schedule = req.body;
      console.log('POST /api/work-schedule:', schedule.shopAddress, schedule.year, schedule.month);

      if (!schedule.shopAddress || !schedule.year || !schedule.month) {
        return res.status(400).json({ success: false, error: 'Shop address, year, and month are required' });
      }

      const sanitizedAddress = schedule.shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const filePath = path.join(WORK_SCHEDULES_DIR, `${sanitizedAddress}_${schedule.year}_${schedule.month}.json`);

      schedule.updatedAt = new Date().toISOString();
      fs.writeFileSync(filePath, JSON.stringify(schedule, null, 2), 'utf8');

      res.json({ success: true, schedule });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== WORK SCHEDULE TEMPLATES =====

  app.get('/api/work-schedule-templates', async (req, res) => {
    try {
      console.log('GET /api/work-schedule-templates');
      const templates = [];

      if (fs.existsSync(WORK_SCHEDULE_TEMPLATES_DIR)) {
        const files = fs.readdirSync(WORK_SCHEDULE_TEMPLATES_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(WORK_SCHEDULE_TEMPLATES_DIR, file), 'utf8');
            templates.push(JSON.parse(content));
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      res.json({ success: true, templates });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/work-schedule-templates', async (req, res) => {
    try {
      const template = req.body;
      console.log('POST /api/work-schedule-templates:', template.name);

      if (!template.id) {
        template.id = `template_${Date.now()}`;
      }

      const filePath = path.join(WORK_SCHEDULE_TEMPLATES_DIR, `${template.id}.json`);
      template.updatedAt = new Date().toISOString();

      fs.writeFileSync(filePath, JSON.stringify(template, null, 2), 'utf8');
      res.json({ success: true, template });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/work-schedule-templates/:templateId', async (req, res) => {
    try {
      const { templateId } = req.params;
      console.log('DELETE /api/work-schedule-templates:', templateId);

      const filePath = path.join(WORK_SCHEDULE_TEMPLATES_DIR, `${templateId}.json`);

      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Template not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Work Schedule API initialized');
}

module.exports = { setupWorkScheduleAPI };

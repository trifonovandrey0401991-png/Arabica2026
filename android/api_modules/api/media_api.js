const fs = require('fs');
const path = require('path');

const CHAT_MEDIA_DIR = '/var/www/chat-media';
const APP_LOGS_DIR = '/var/www/app-logs';

[CHAT_MEDIA_DIR, APP_LOGS_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

function setupMediaAPI(app, uploadChatMedia) {
  // ===== CHAT MEDIA =====

  if (uploadChatMedia) {
    app.post('/upload-media', uploadChatMedia.single('file'), async (req, res) => {
      try {
        console.log('POST /upload-media');

        if (!req.file) {
          return res.status(400).json({ success: false, error: 'No file uploaded' });
        }

        const mediaUrl = `/chat-media/${req.file.filename}`;
        res.json({ success: true, mediaUrl, filename: req.file.filename });
      } catch (error) {
        res.status(500).json({ success: false, error: error.message });
      }
    });

    app.post('/upload-chat-media', uploadChatMedia.single('file'), async (req, res) => {
      try {
        console.log('POST /upload-chat-media');

        if (!req.file) {
          return res.status(400).json({ success: false, error: 'No file uploaded' });
        }

        const mediaUrl = `/chat-media/${req.file.filename}`;
        res.json({ success: true, mediaUrl, filename: req.file.filename });
      } catch (error) {
        res.status(500).json({ success: false, error: error.message });
      }
    });
  }

  // ===== APP LOGS =====

  app.post('/api/app-logs', async (req, res) => {
    try {
      const logData = req.body;
      console.log('POST /api/app-logs');

      const date = new Date().toISOString().split('T')[0];
      const logId = `log_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

      const dateDir = path.join(APP_LOGS_DIR, date);
      if (!fs.existsSync(dateDir)) {
        fs.mkdirSync(dateDir, { recursive: true });
      }

      logData.id = logId;
      logData.timestamp = new Date().toISOString();

      const filePath = path.join(dateDir, `${logId}.json`);
      fs.writeFileSync(filePath, JSON.stringify(logData, null, 2), 'utf8');

      res.json({ success: true, logId });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/app-logs', async (req, res) => {
    try {
      console.log('GET /api/app-logs');
      const { date, phone, level } = req.query;
      const logs = [];

      const searchDate = date || new Date().toISOString().split('T')[0];
      const dateDir = path.join(APP_LOGS_DIR, searchDate);

      if (fs.existsSync(dateDir)) {
        const files = fs.readdirSync(dateDir).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(dateDir, file), 'utf8');
            const log = JSON.parse(content);

            if (phone && log.phone !== phone) continue;
            if (level && log.level !== level) continue;

            logs.push(log);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      logs.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
      res.json({ success: true, logs });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Media & Logs API initialized');
}

module.exports = { setupMediaAPI };

/**
 * Media & App Logs API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');
const { compressUpload } = require('../utils/image_compress');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const CHAT_MEDIA_DIR = `${DATA_DIR}/chat-media`;
const TASK_MEDIA_DIR = `${DATA_DIR}/task-media`;
const APP_LOGS_DIR = `${DATA_DIR}/app-logs`;

/**
 * Sanitize date string — только формат YYYY-MM-DD
 */
function sanitizeDate(date) {
  if (!date) return null;
  const match = date.match(/^(\d{4}-\d{2}-\d{2})$/);
  return match ? match[1] : null;
}


// Ensure directories exist
async function ensureDirs() {
  for (const dir of [CHAT_MEDIA_DIR, TASK_MEDIA_DIR, APP_LOGS_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
}

// Initialize directories at module load
(async () => {
  try {
    await ensureDirs();
  } catch (e) {
    console.error('Error creating media directories:', e.message);
  }
})();

function setupMediaAPI(app, uploadChatMedia) {
  // ===== CHAT MEDIA =====

  if (uploadChatMedia) {
    app.post('/upload-media', uploadChatMedia.single('file'), compressUpload, async (req, res) => {
      try {
        console.log('POST /upload-media');
        console.log('  mediaType:', req.body.mediaType || 'image');
        console.log('  fileName:', req.body.fileName || 'unknown');

        if (!req.file) {
          return res.status(400).json({ success: false, error: 'No file uploaded' });
        }

        // Если это для задач - используем task-media, иначе chat-media
        const mediaType = req.body.mediaType || 'image';
        const isTaskMedia = req.body.fileName && req.body.fileName.startsWith('photo_');

        let targetDir = CHAT_MEDIA_DIR;
        let targetPath = 'chat-media';

        if (isTaskMedia) {
          targetDir = TASK_MEDIA_DIR;
          targetPath = 'task-media';

          // Перемещаем файл из chat-media в task-media
          const srcPath = path.join(CHAT_MEDIA_DIR, req.file.filename);
          const dstPath = path.join(TASK_MEDIA_DIR, req.file.filename);

          if (await fileExists(srcPath)) {
            await fsp.rename(srcPath, dstPath);
            console.log('  Moved to task-media:', req.file.filename);
          }
        }

        const mediaUrl = `https://arabica26.ru/${targetPath}/${req.file.filename}`;
        console.log('  Full URL:', mediaUrl);

        res.json({
          success: true,
          url: mediaUrl,           // Для совместимости с Flutter
          filePath: mediaUrl,      // Альтернативное поле
          mediaUrl: mediaUrl,      // Старое поле для обратной совместимости
          filename: req.file.filename
        });
      } catch (error) {
        console.error('Error in /upload-media:', error);
        res.status(500).json({ success: false, error: error.message });
      }
    });

    app.post('/upload-chat-media', uploadChatMedia.single('file'), compressUpload, async (req, res) => {
      try {
        console.log('POST /upload-chat-media');

        if (!req.file) {
          return res.status(400).json({ success: false, error: 'No file uploaded' });
        }

        const mediaUrl = `https://arabica26.ru/chat-media/${req.file.filename}`;
        res.json({
          success: true,
          url: mediaUrl,
          filePath: mediaUrl,
          mediaUrl: mediaUrl,
          filename: req.file.filename
        });
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
      if (!(await fileExists(dateDir))) {
        await fsp.mkdir(dateDir, { recursive: true });
      }

      logData.id = logId;
      logData.timestamp = new Date().toISOString();

      const filePath = path.join(dateDir, `${logId}.json`);
      await fsp.writeFile(filePath, JSON.stringify(logData, null, 2), 'utf8');

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

      const searchDate = sanitizeDate(date) || new Date().toISOString().split('T')[0];
      const dateDir = path.join(APP_LOGS_DIR, searchDate);

      if (await fileExists(dateDir)) {
        const files = (await fsp.readdir(dateDir)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(dateDir, file), 'utf8');
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

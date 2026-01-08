const fs = require('fs');
const path = require('path');
const multer = require('multer');

const RKO_REPORTS_DIR = '/var/www/rko-reports';
const RKO_FILES_DIR = '/var/www/rko-files';
const RKO_METADATA_FILE = '/var/www/rko-reports/rko_metadata.json';

if (!fs.existsSync(RKO_REPORTS_DIR)) {
  fs.mkdirSync(RKO_REPORTS_DIR, { recursive: true });
}
if (!fs.existsSync(RKO_FILES_DIR)) {
  fs.mkdirSync(RKO_FILES_DIR, { recursive: true });
}

// Вспомогательная функция для чтения всех RKO из обоих источников
function getAllRKOReports() {
  const reports = [];

  // 1. Читаем из rko_metadata.json (основной источник - старый формат)
  if (fs.existsSync(RKO_METADATA_FILE)) {
    try {
      const content = fs.readFileSync(RKO_METADATA_FILE, 'utf8');
      const metadata = JSON.parse(content);
      if (metadata.items && Array.isArray(metadata.items)) {
        for (const item of metadata.items) {
          reports.push({
            id: item.fileName || `rko_${Date.now()}`,
            fileName: item.fileName,
            originalName: item.fileName,
            employeeName: item.employeeName,
            shopAddress: item.shopAddress,
            date: item.date,
            amount: item.amount,
            rkoType: item.rkoType,
            createdAt: item.createdAt
          });
        }
      }
    } catch (e) {
      console.error('Error reading rko_metadata.json:', e);
    }
  }

  // 2. Читаем отдельные .json файлы (новый формат)
  if (fs.existsSync(RKO_REPORTS_DIR)) {
    const files = fs.readdirSync(RKO_REPORTS_DIR).filter(f => f.endsWith('.json') && f !== 'rko_metadata.json');
    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(RKO_REPORTS_DIR, file), 'utf8');
        const report = JSON.parse(content);
        // Проверяем что это отчет, а не другие данные
        if (report.shopAddress && report.employeeName) {
          reports.push(report);
        }
      } catch (e) {
        console.error(`Error reading ${file}:`, e);
      }
    }
  }

  return reports;
}

// Настройка multer для загрузки файлов
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, RKO_FILES_DIR),
  filename: (req, file, cb) => {
    const uniqueName = `rko_${Date.now()}_${file.originalname}`;
    cb(null, uniqueName);
  }
});
const upload = multer({ storage });

function setupRkoAPI(app) {
  // ===== RKO UPLOAD (Flutter endpoint) =====
  app.post('/api/rko/upload', upload.single('docx'), async (req, res) => {
    try {
      console.log('POST /api/rko/upload');
      const { fileName, employeeName, shopAddress, date, amount, rkoType } = req.body;
      const file = req.file;

      if (!file) {
        return res.status(400).json({ success: false, error: 'Файл не загружен' });
      }

      const report = {
        id: `rko_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        fileName: file.filename,
        originalName: fileName || file.originalname,
        employeeName,
        shopAddress,
        date,
        amount: parseFloat(amount) || 0,
        rkoType,
        filePath: file.path,
        createdAt: new Date().toISOString()
      };

      const reportPath = path.join(RKO_REPORTS_DIR, `${report.id}.json`);
      fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), 'utf8');

      console.log(`✅ RKO uploaded: ${report.id}, shop: ${shopAddress}`);
      res.json({ success: true, report });
    } catch (error) {
      console.error('Error uploading RKO:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== RKO LIST BY SHOP (Flutter endpoint) =====
  app.get('/api/rko/list/shop/:shopAddress', async (req, res) => {
    try {
      const shopAddress = decodeURIComponent(req.params.shopAddress);
      console.log('GET /api/rko/list/shop:', shopAddress);

      // Получаем все RKO из всех источников
      const allReports = getAllRKOReports();

      // Фильтруем по магазину
      const reports = allReports.filter(r => r.shopAddress === shopAddress);

      console.log(`  Found ${reports.length} RKOs for shop (from ${allReports.length} total)`);

      const now = new Date();
      const currentMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

      // Группируем по месяцам
      const months = {};
      const currentMonthReports = [];

      for (const report of reports) {
        const reportDate = report.date ? report.date.substring(0, 7) : currentMonth;

        if (reportDate === currentMonth) {
          currentMonthReports.push(report);
        }

        if (!months[reportDate]) {
          months[reportDate] = [];
        }
        months[reportDate].push(report);
      }

      // Сортировка
      currentMonthReports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      res.json({
        success: true,
        currentMonth: currentMonthReports,
        months: Object.keys(months).sort().reverse()
      });
    } catch (error) {
      console.error('Error getting shop RKOs:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== RKO LIST BY EMPLOYEE (Flutter endpoint) =====
  app.get('/api/rko/list/employee/:employeeName', async (req, res) => {
    try {
      const employeeName = decodeURIComponent(req.params.employeeName);
      console.log('GET /api/rko/list/employee:', employeeName);

      // Получаем все RKO из всех источников
      const allReports = getAllRKOReports();

      // Фильтруем по сотруднику (регистронезависимо)
      const reports = allReports.filter(r =>
        r.employeeName && r.employeeName.toLowerCase() === employeeName.toLowerCase()
      );

      console.log(`  Found ${reports.length} RKOs for employee (from ${allReports.length} total)`);

      reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, reports });
    } catch (error) {
      console.error('Error getting employee RKOs:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== RKO FILE DOWNLOAD (Flutter endpoint) =====
  app.get('/api/rko/file/:fileName', async (req, res) => {
    try {
      const fileName = decodeURIComponent(req.params.fileName);
      console.log('GET /api/rko/file:', fileName);

      // 1. Ищем файл в папке RKO_FILES_DIR (новый формат)
      const filePath = path.join(RKO_FILES_DIR, fileName);
      if (fs.existsSync(filePath)) {
        return res.sendFile(filePath);
      }

      // 2. Ищем в employee структуре (старый формат)
      // Структура: /var/www/rko-reports/employee/{employeeName}/{year-month}/{filename}
      const employeeDir = path.join(RKO_REPORTS_DIR, 'employee');
      if (fs.existsSync(employeeDir)) {
        const employeeFolders = fs.readdirSync(employeeDir);
        for (const empFolder of employeeFolders) {
          const empPath = path.join(employeeDir, empFolder);
          if (fs.statSync(empPath).isDirectory()) {
            const monthFolders = fs.readdirSync(empPath);
            for (const monthFolder of monthFolders) {
              const monthPath = path.join(empPath, monthFolder);
              if (fs.statSync(monthPath).isDirectory()) {
                const targetPath = path.join(monthPath, fileName);
                if (fs.existsSync(targetPath)) {
                  console.log(`  Found file at: ${targetPath}`);
                  return res.sendFile(targetPath);
                }
              }
            }
          }
        }
      }

      // 3. Ищем по originalName в метаданных
      const allReports = getAllRKOReports();
      for (const report of allReports) {
        if (report.originalName === fileName || report.fileName === fileName) {
          if (report.filePath && fs.existsSync(report.filePath)) {
            return res.sendFile(report.filePath);
          }
        }
      }

      res.status(404).json({ success: false, error: 'File not found' });
    } catch (error) {
      console.error('Error getting RKO file:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== LEGACY RKO REPORTS (старый формат) =====
  app.get('/api/rko-reports', async (req, res) => {
    try {
      console.log('GET /api/rko-reports');
      const { shopAddress, date } = req.query;
      const reports = [];

      if (fs.existsSync(RKO_REPORTS_DIR)) {
        const files = fs.readdirSync(RKO_REPORTS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(RKO_REPORTS_DIR, file), 'utf8');
            const report = JSON.parse(content);

            if (shopAddress && report.shopAddress !== shopAddress) continue;
            if (date && report.date !== date) continue;

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

  app.post('/api/rko-reports', async (req, res) => {
    try {
      const report = req.body;
      console.log('POST /api/rko-reports:', report.shopAddress);

      if (!report.id) {
        report.id = `rko_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      report.createdAt = report.createdAt || new Date().toISOString();
      const filePath = path.join(RKO_REPORTS_DIR, `${report.id}.json`);

      fs.writeFileSync(filePath, JSON.stringify(report, null, 2), 'utf8');
      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/rko-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      console.log('GET /api/rko-reports/:reportId', reportId);

      const filePath = path.join(RKO_REPORTS_DIR, `${reportId}.json`);

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

  app.put('/api/rko-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const updates = req.body;
      console.log('PUT /api/rko-reports/:reportId', reportId);

      const filePath = path.join(RKO_REPORTS_DIR, `${reportId}.json`);

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

  app.delete('/api/rko-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      console.log('DELETE /api/rko-reports/:reportId', reportId);

      const filePath = path.join(RKO_REPORTS_DIR, `${reportId}.json`);

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

  console.log('✅ RKO API initialized');
}

module.exports = { setupRkoAPI };

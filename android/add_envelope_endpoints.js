const fs = require('fs');
const path = require('path');

let code = fs.readFileSync('index.js', 'utf8');

// Найдем место для вставки - после SUPPLIERS
const insertMarker = '// =========== SUPPLIERS (ПОСТАВЩИКИ) ===========';
const insertIndex = code.indexOf(insertMarker);

if (insertIndex === -1) {
  console.log('Insert marker not found, trying alternative...');
  // Попробуем найти другое место - после app.listen или перед последними строками
  const altMarker = 'const SUPPLIERS_FILE';
  const altIndex = code.indexOf(altMarker);
  if (altIndex !== -1) {
    // Найдем конец блока suppliers (после DELETE /api/suppliers/:id)
    const deleteSupplierIndex = code.indexOf("app.delete('/api/suppliers/:id'");
    if (deleteSupplierIndex !== -1) {
      // Найдем конец этой функции
      let braceCount = 0;
      let endIndex = deleteSupplierIndex;
      for (let i = deleteSupplierIndex; i < code.length; i++) {
        if (code[i] === '{') braceCount++;
        if (code[i] === '}') {
          braceCount--;
          if (braceCount === 0) {
            // Найдем следующую закрывающую скобку и точку с запятой
            for (let j = i + 1; j < code.length; j++) {
              if (code[j] === '}') {
                endIndex = j + 3; // });\n
                break;
              }
            }
            break;
          }
        }
      }
      // Вставляем после suppliers
      code = code.slice(0, endIndex) + '\n\n' + envelopeEndpoints + code.slice(endIndex);
      fs.writeFileSync('index.js', code);
      console.log('Envelope endpoints added successfully (after suppliers)');
      process.exit(0);
    }
  }
  console.log('Could not find insertion point');
  process.exit(1);
}

// Envelope endpoints
const envelopeEndpoints = `// =========== ENVELOPE REPORTS (ОТЧЕТЫ КОНВЕРТОВ) ===========
const ENVELOPE_REPORTS_DIR = '/var/www/envelope-reports';

// Инициализация директории для отчетов конвертов
if (!fs.existsSync(ENVELOPE_REPORTS_DIR)) {
  fs.mkdirSync(ENVELOPE_REPORTS_DIR, { recursive: true });
}

// GET /api/envelope-reports - получить все отчеты конвертов
app.get('/api/envelope-reports', async (req, res) => {
  try {
    console.log('GET /api/envelope-reports');
    const files = fs.readdirSync(ENVELOPE_REPORTS_DIR);
    const reports = [];

    for (const file of files) {
      if (file.endsWith('.json')) {
        const data = JSON.parse(fs.readFileSync(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8'));

        // Фильтрация
        if (req.query.shopAddress && data.shopAddress !== req.query.shopAddress) continue;
        if (req.query.status && data.status !== req.query.status) continue;
        if (req.query.fromDate) {
          const fromDate = new Date(req.query.fromDate);
          const reportDate = new Date(data.createdAt);
          if (reportDate < fromDate) continue;
        }
        if (req.query.toDate) {
          const toDate = new Date(req.query.toDate);
          const reportDate = new Date(data.createdAt);
          if (reportDate > toDate) continue;
        }

        reports.push(data);
      }
    }

    // Сортировка по дате (новые первыми)
    reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    res.json({ success: true, reports });
  } catch (error) {
    console.error('Error getting envelope reports:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/envelope-reports/expired - просроченные отчеты (>24 часов без подтверждения)
app.get('/api/envelope-reports/expired', async (req, res) => {
  try {
    console.log('GET /api/envelope-reports/expired');
    const files = fs.readdirSync(ENVELOPE_REPORTS_DIR);
    const reports = [];
    const now = new Date();
    const expirationHours = 24;

    for (const file of files) {
      if (file.endsWith('.json')) {
        const data = JSON.parse(fs.readFileSync(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8'));

        if (data.status !== 'confirmed') {
          const createdAt = new Date(data.createdAt);
          const hoursDiff = (now - createdAt) / (1000 * 60 * 60);

          if (hoursDiff >= expirationHours) {
            reports.push(data);
          }
        }
      }
    }

    reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    res.json({ success: true, reports });
  } catch (error) {
    console.error('Error getting expired envelope reports:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/envelope-reports/:id - получить отчет по ID
app.get('/api/envelope-reports/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('GET /api/envelope-reports/:id', id);

    const filePath = path.join(ENVELOPE_REPORTS_DIR, id + '.json');

    if (fs.existsSync(filePath)) {
      const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      res.json({ success: true, report: data });
    } else {
      res.json({ success: false, error: 'Report not found' });
    }
  } catch (error) {
    console.error('Error getting envelope report:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/envelope-reports - создать отчет конверта
app.post('/api/envelope-reports', async (req, res) => {
  try {
    const report = req.body;
    console.log('POST /api/envelope-reports', report.id);

    // Устанавливаем значения по умолчанию
    if (!report.id) {
      report.id = 'envelope_' + Date.now();
    }
    report.createdAt = report.createdAt || new Date().toISOString();
    report.status = report.status || 'pending';

    const filePath = path.join(ENVELOPE_REPORTS_DIR, report.id + '.json');
    fs.writeFileSync(filePath, JSON.stringify(report, null, 2));

    res.json({ success: true, report });
  } catch (error) {
    console.error('Error creating envelope report:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/envelope-reports/:id - обновить отчет
app.put('/api/envelope-reports/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const updateData = req.body;
    console.log('PUT /api/envelope-reports/:id', id);

    const filePath = path.join(ENVELOPE_REPORTS_DIR, id + '.json');

    if (!fs.existsSync(filePath)) {
      return res.json({ success: false, error: 'Report not found' });
    }

    const existing = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const updated = { ...existing, ...updateData };
    fs.writeFileSync(filePath, JSON.stringify(updated, null, 2));

    res.json({ success: true, report: updated });
  } catch (error) {
    console.error('Error updating envelope report:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/envelope-reports/:id/confirm - подтвердить отчет
app.put('/api/envelope-reports/:id/confirm', async (req, res) => {
  try {
    const { id } = req.params;
    const { confirmedByAdmin, rating } = req.body;
    console.log('PUT /api/envelope-reports/:id/confirm', id, rating);

    const filePath = path.join(ENVELOPE_REPORTS_DIR, id + '.json');

    if (!fs.existsSync(filePath)) {
      return res.json({ success: false, error: 'Report not found' });
    }

    const report = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    report.status = 'confirmed';
    report.confirmedAt = new Date().toISOString();
    report.confirmedByAdmin = confirmedByAdmin;
    report.rating = rating;

    fs.writeFileSync(filePath, JSON.stringify(report, null, 2));

    res.json({ success: true, report });
  } catch (error) {
    console.error('Error confirming envelope report:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/envelope-reports/:id - удалить отчет
app.delete('/api/envelope-reports/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('DELETE /api/envelope-reports/:id', id);

    const filePath = path.join(ENVELOPE_REPORTS_DIR, id + '.json');

    if (!fs.existsSync(filePath)) {
      return res.json({ success: false, error: 'Report not found' });
    }

    fs.unlinkSync(filePath);
    res.json({ success: true });
  } catch (error) {
    console.error('Error deleting envelope report:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

`;

// Находим конец блока suppliers и вставляем после него
const supplierDeleteIndex = code.indexOf("app.delete('/api/suppliers/:id'", insertIndex);
if (supplierDeleteIndex !== -1) {
  // Найдем конец этой функции
  let braceCount = 0;
  let startCounting = false;
  let endIndex = supplierDeleteIndex;

  for (let i = supplierDeleteIndex; i < code.length; i++) {
    if (code[i] === '{') {
      startCounting = true;
      braceCount++;
    }
    if (code[i] === '}') {
      braceCount--;
      if (startCounting && braceCount === 0) {
        // Найдем следующую закрывающую скобку
        for (let j = i + 1; j < code.length; j++) {
          if (code[j] === '}') {
            // Пропустим точку с запятой и новую строку
            endIndex = j + 1;
            while (endIndex < code.length && (code[endIndex] === ';' || code[endIndex] === '\n' || code[endIndex] === '\r')) {
              endIndex++;
            }
            break;
          }
        }
        break;
      }
    }
  }

  code = code.slice(0, endIndex) + '\n\n' + envelopeEndpoints + code.slice(endIndex);
  fs.writeFileSync('index.js', code);
  console.log('Envelope endpoints added successfully');
} else {
  // Если не нашли delete endpoint поставщиков, добавим в конец перед app.listen
  const listenIndex = code.lastIndexOf('app.listen');
  if (listenIndex !== -1) {
    code = code.slice(0, listenIndex) + envelopeEndpoints + '\n' + code.slice(listenIndex);
    fs.writeFileSync('index.js', code);
    console.log('Envelope endpoints added before app.listen');
  } else {
    console.log('Could not find suitable insertion point');
    process.exit(1);
  }
}

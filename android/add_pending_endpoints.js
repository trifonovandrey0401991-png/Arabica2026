const fs = require('fs');
let code = fs.readFileSync('index.js', 'utf8');

// Найдем место перед shift-handover-reports для добавления pending endpoints
const shiftHandoverMarker = 'const SHIFT_HANDOVER_REPORTS_DIR';
const insertIndex = code.indexOf(shiftHandoverMarker);

if (insertIndex === -1) {
  console.log('SHIFT_HANDOVER_REPORTS_DIR marker not found');
  process.exit(1);
}

// Pending shift handover reports endpoints
const pendingEndpoints = `// =========== PENDING SHIFT HANDOVER REPORTS ===========
const PENDING_SHIFT_HANDOVER_FILE = '/var/www/pending-shift-handover-reports.json';

// Инициализация файла pending shift handover reports
function initPendingShiftHandoverFile() {
  if (!fs.existsSync(PENDING_SHIFT_HANDOVER_FILE)) {
    fs.writeFileSync(PENDING_SHIFT_HANDOVER_FILE, JSON.stringify({ reports: [] }, null, 2));
  }
}
initPendingShiftHandoverFile();

// GET /api/pending-shift-handover-reports - получить список непройденных сдач смен
app.get('/api/pending-shift-handover-reports', async (req, res) => {
  try {
    console.log('GET /api/pending-shift-handover-reports');
    const data = JSON.parse(fs.readFileSync(PENDING_SHIFT_HANDOVER_FILE, 'utf8'));
    res.json({ success: true, reports: data.reports || [] });
  } catch (error) {
    console.error('Error getting pending shift handover reports:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/pending-shift-handover-reports/generate - генерировать ежедневные записи
app.post('/api/pending-shift-handover-reports/generate', async (req, res) => {
  try {
    console.log('POST /api/pending-shift-handover-reports/generate');

    // Загружаем список магазинов
    const shopsFile = '/var/www/shops.json';
    if (!fs.existsSync(shopsFile)) {
      return res.json({ success: true, message: 'No shops file', generated: 0 });
    }

    const shopsData = JSON.parse(fs.readFileSync(shopsFile, 'utf8'));
    const shops = shopsData.shops || [];

    // Текущая дата
    const now = new Date();
    const today = now.toISOString().split('T')[0];

    // Загружаем существующие pending reports
    const data = JSON.parse(fs.readFileSync(PENDING_SHIFT_HANDOVER_FILE, 'utf8'));
    const existingReports = data.reports || [];

    // Проверяем какие уже есть на сегодня
    const existingToday = existingReports.filter(r => r.date === today);
    const existingKeys = new Set(existingToday.map(r => r.shopAddress + '_' + r.shiftType));

    const newReports = [];

    // Для каждого магазина генерируем 2 записи (утро и вечер)
    for (const shop of shops) {
      const shopAddress = shop.address || shop.name;

      // Утренняя смена - дедлайн 14:00
      const morningKey = shopAddress + '_morning';
      if (!existingKeys.has(morningKey)) {
        newReports.push({
          id: 'psh_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9),
          shopAddress: shopAddress,
          shiftType: 'morning',
          shiftLabel: 'Утро',
          date: today,
          deadline: '14:00',
          status: 'pending',
          completedBy: null,
          createdAt: now.toISOString(),
          completedAt: null
        });
      }

      // Вечерняя смена - дедлайн 22:00
      const eveningKey = shopAddress + '_evening';
      if (!existingKeys.has(eveningKey)) {
        newReports.push({
          id: 'psh_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9) + '_e',
          shopAddress: shopAddress,
          shiftType: 'evening',
          shiftLabel: 'Вечер',
          date: today,
          deadline: '22:00',
          status: 'pending',
          completedBy: null,
          createdAt: now.toISOString(),
          completedAt: null
        });
      }
    }

    // Добавляем новые записи
    data.reports = [...existingReports, ...newReports];
    fs.writeFileSync(PENDING_SHIFT_HANDOVER_FILE, JSON.stringify(data, null, 2));

    console.log('Generated', newReports.length, 'new pending shift handover reports');
    res.json({ success: true, generated: newReports.length });
  } catch (error) {
    console.error('Error generating pending shift handover reports:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/pending-shift-handover-reports/:id/complete - отметить как выполненную
app.put('/api/pending-shift-handover-reports/:id/complete', async (req, res) => {
  try {
    const { id } = req.params;
    const { completedBy } = req.body;
    console.log('PUT /api/pending-shift-handover-reports/:id/complete', id, completedBy);

    const data = JSON.parse(fs.readFileSync(PENDING_SHIFT_HANDOVER_FILE, 'utf8'));
    const reportIndex = data.reports.findIndex(r => r.id === id);

    if (reportIndex === -1) {
      return res.json({ success: false, error: 'Report not found' });
    }

    data.reports[reportIndex].status = 'completed';
    data.reports[reportIndex].completedBy = completedBy;
    data.reports[reportIndex].completedAt = new Date().toISOString();

    fs.writeFileSync(PENDING_SHIFT_HANDOVER_FILE, JSON.stringify(data, null, 2));
    res.json({ success: true, report: data.reports[reportIndex] });
  } catch (error) {
    console.error('Error completing pending shift handover report:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

`;

// Вставляем перед shift-handover-reports
code = code.slice(0, insertIndex) + pendingEndpoints + code.slice(insertIndex);

fs.writeFileSync('index.js', code);
console.log('Pending shift handover endpoints добавлены');

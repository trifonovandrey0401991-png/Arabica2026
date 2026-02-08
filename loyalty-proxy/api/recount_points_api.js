// =====================================================
// RECOUNT POINTS API (Баллы пересчёта)
//
// REFACTORED: Converted from sync to async I/O (2026-02-05)
// =====================================================

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const RECOUNT_POINTS_DIR = `${DATA_DIR}/recount-points`;
const RECOUNT_SETTINGS_FILE = `${DATA_DIR}/recount-settings/settings.json`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;

// Настройки по умолчанию
const DEFAULT_SETTINGS = {
  defaultPoints: 85,
  basePhotos: 3,
  stepPoints: 5,
  maxPhotos: 20,
  correctPhotoBonus: 0.2,
  incorrectPhotoPenalty: 2.5,
  questionsCount: 30
};

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Убедиться что директории существуют
async function ensureDirectories() {
  if (!(await fileExists(RECOUNT_POINTS_DIR))) {
    await fsp.mkdir(RECOUNT_POINTS_DIR, { recursive: true });
  }
  const settingsDir = path.dirname(RECOUNT_SETTINGS_FILE);
  if (!(await fileExists(settingsDir))) {
    await fsp.mkdir(settingsDir, { recursive: true });
  }
}

// Ensure directories exist (async IIFE)
(async () => {
  await ensureDirectories();
})();

module.exports = function setupRecountPointsAPI(app) {
  // Функция получения имени сотрудника по телефону из employees
  async function getEmployeeNameByPhone(phone) {
    if (!phone || !(await fileExists(EMPLOYEES_DIR))) return null;

    const normalizedPhone = phone.replace(/[\s+]/g, '');
    const employeeFiles = await fsp.readdir(EMPLOYEES_DIR);

    for (const file of employeeFiles) {
      if (!file.endsWith('.json')) continue;
      try {
        const content = await fsp.readFile(path.join(EMPLOYEES_DIR, file), 'utf8');
        const employee = JSON.parse(content);
        const empPhone = (employee.phone || '').replace(/[\s+]/g, '');
        if (empPhone === normalizedPhone) {
          return employee.name || null;
        }
      } catch (e) {
        // ignore
      }
    }
    return null;
  }

  // Хелпер для получения настроек
  async function getSettings() {
    try {
      if (await fileExists(RECOUNT_SETTINGS_FILE)) {
        const content = await fsp.readFile(RECOUNT_SETTINGS_FILE, 'utf8');
        return { ...DEFAULT_SETTINGS, ...JSON.parse(content) };
      }
    } catch (e) {
      console.error('Ошибка чтения настроек:', e);
    }
    return DEFAULT_SETTINGS;
  }

  // =====================================================
  // GET /api/recount-points - получить баллы всех сотрудников
  // =====================================================
  app.get('/api/recount-points', async (req, res) => {
    try {
      console.log('📥 GET /api/recount-points');

      if (!(await fileExists(RECOUNT_POINTS_DIR))) {
        return res.json({ success: true, points: [] });
      }

      const files = await fsp.readdir(RECOUNT_POINTS_DIR);
      const points = [];

      for (const file of files) {
        if (!file.endsWith('.json')) continue;

        try {
          const content = await fsp.readFile(path.join(RECOUNT_POINTS_DIR, file), 'utf8');
          const data = JSON.parse(content);

          // Обогащаем актуальным именем из employees
          const actualName = await getEmployeeNameByPhone(data.phone);
          if (actualName) {
            data.employeeName = actualName;
          }

          points.push(data);
        } catch (e) {
          console.error(`Error reading ${file}:`, e);
        }
      }

      // Сортируем по имени
      points.sort((a, b) => (a.employeeName || '').localeCompare(b.employeeName || ''));

      res.json({ success: true, points });
    } catch (error) {
      console.error('❌ Ошибка получения баллов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // =====================================================
  // GET /api/recount-points/:phone - получить баллы сотрудника
  // =====================================================
  app.get('/api/recount-points/:phone', async (req, res) => {
    try {
      const { phone } = req.params;
      const normalizedPhone = phone.replace(/[\s+]/g, '');

      console.log(`📥 GET /api/recount-points/${normalizedPhone}`);

      const filePath = path.join(RECOUNT_POINTS_DIR, `${normalizedPhone}.json`);

      if (!(await fileExists(filePath))) {
        // Если нет записи - создаём с дефолтными баллами
        const settings = await getSettings();
        const newPoints = {
          id: `rp_${Date.now()}`,
          employeeId: normalizedPhone,
          employeeName: await getEmployeeNameByPhone(normalizedPhone) || '',
          phone: normalizedPhone,
          points: settings.defaultPoints,
          updatedAt: new Date().toISOString(),
          updatedBy: null
        };

        await fsp.writeFile(filePath, JSON.stringify(newPoints, null, 2), 'utf8');
        return res.json({ success: true, points: newPoints });
      }

      const content = await fsp.readFile(filePath, 'utf8');
      const data = JSON.parse(content);

      // Обогащаем актуальным именем из employees
      const actualName = await getEmployeeNameByPhone(normalizedPhone);
      if (actualName) {
        data.employeeName = actualName;
      }

      res.json({ success: true, points: data });
    } catch (error) {
      console.error('❌ Ошибка получения баллов сотрудника:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // =====================================================
  // PUT /api/recount-points/:phone - обновить баллы сотрудника
  // =====================================================
  app.put('/api/recount-points/:phone', async (req, res) => {
    try {
      const { phone } = req.params;
      const { points, adminName, employeeName, reason } = req.body;
      const normalizedPhone = phone.replace(/[\s+]/g, '');

      console.log(`📤 PUT /api/recount-points/${normalizedPhone}: ${points}`);

      // Валидация
      if (points === undefined || points === null) {
        return res.status(400).json({ success: false, error: 'Не указаны баллы' });
      }

      const numPoints = parseFloat(points);
      if (isNaN(numPoints) || numPoints < 0 || numPoints > 100) {
        return res.status(400).json({ success: false, error: 'Баллы должны быть от 0 до 100' });
      }

      const filePath = path.join(RECOUNT_POINTS_DIR, `${normalizedPhone}.json`);

      let data = {
        id: `rp_${Date.now()}`,
        employeeId: normalizedPhone,
        employeeName: employeeName || '',
        phone: normalizedPhone,
        points: numPoints,
        updatedAt: new Date().toISOString(),
        updatedBy: adminName || 'Система'
      };

      // Если файл существует - обновляем
      if (await fileExists(filePath)) {
        const existing = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        data = {
          ...existing,
          points: numPoints,
          updatedAt: new Date().toISOString(),
          updatedBy: adminName || 'Система'
        };
        if (employeeName) {
          data.employeeName = employeeName;
        }
      }

      // Сохраняем историю изменений
      if (reason) {
        if (!data.history) data.history = [];
        data.history.push({
          oldPoints: data.points,
          newPoints: numPoints,
          change: numPoints - (data.points || 0),
          reason: reason,
          adminName: adminName || 'Система',
          date: new Date().toISOString()
        });
      }

      await fsp.writeFile(filePath, JSON.stringify(data, null, 2), 'utf8');

      console.log(`✅ Баллы обновлены: ${normalizedPhone} -> ${numPoints}`);
      res.json({ success: true, points: data });
    } catch (error) {
      console.error('❌ Ошибка обновления баллов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // =====================================================
  // POST /api/recount-points/init - инициализировать баллы всем
  // =====================================================
  app.post('/api/recount-points/init', async (req, res) => {
    try {
      console.log('📤 POST /api/recount-points/init');

      if (!(await fileExists(EMPLOYEES_DIR))) {
        return res.json({ success: true, count: 0, message: 'Нет сотрудников' });
      }

      const settings = await getSettings();
      const employeeFiles = await fsp.readdir(EMPLOYEES_DIR);
      let count = 0;

      for (const file of employeeFiles) {
        if (!file.endsWith('.json')) continue;

        try {
          const empContent = await fsp.readFile(path.join(EMPLOYEES_DIR, file), 'utf8');
          const employee = JSON.parse(empContent);

          // Пропускаем админов
          if (employee.isAdmin) continue;

          const phone = employee.phone?.replace(/[\s+]/g, '');
          if (!phone) continue;

          const pointsFile = path.join(RECOUNT_POINTS_DIR, `${phone}.json`);

          // Если файл уже существует - не перезаписываем
          if (await fileExists(pointsFile)) continue;

          const pointsData = {
            id: `rp_${Date.now()}_${count}`,
            employeeId: phone,
            employeeName: employee.name || '',
            phone: phone,
            points: settings.defaultPoints,
            updatedAt: new Date().toISOString(),
            updatedBy: 'Система (инициализация)'
          };

          await fsp.writeFile(pointsFile, JSON.stringify(pointsData, null, 2), 'utf8');
          count++;
        } catch (e) {
          console.error(`Error processing ${file}:`, e);
        }
      }

      console.log(`✅ Инициализировано баллов: ${count}`);
      res.json({ success: true, count });
    } catch (error) {
      console.error('❌ Ошибка инициализации баллов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // =====================================================
  // GET /api/recount-settings - получить общие настройки
  // =====================================================
  app.get('/api/recount-settings', async (req, res) => {
    try {
      console.log('📥 GET /api/recount-settings');

      const settings = await getSettings();
      res.json({ success: true, settings });
    } catch (error) {
      console.error('❌ Ошибка получения настроек:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // =====================================================
  // PUT/POST /api/recount-settings - обновить общие настройки
  // =====================================================
  const updateRecountSettings = async (req, res) => {
    try {
      console.log(`📤 ${req.method} /api/recount-settings`);

      const {
        defaultPoints,
        basePhotos,
        stepPoints,
        maxPhotos,
        correctPhotoBonus,
        incorrectPhotoPenalty,
        questionsCount
      } = req.body;

      const settings = {
        defaultPoints: defaultPoints !== undefined ? parseFloat(defaultPoints) : DEFAULT_SETTINGS.defaultPoints,
        basePhotos: basePhotos !== undefined ? parseInt(basePhotos) : DEFAULT_SETTINGS.basePhotos,
        stepPoints: stepPoints !== undefined ? parseFloat(stepPoints) : DEFAULT_SETTINGS.stepPoints,
        maxPhotos: maxPhotos !== undefined ? parseInt(maxPhotos) : DEFAULT_SETTINGS.maxPhotos,
        correctPhotoBonus: correctPhotoBonus !== undefined ? parseFloat(correctPhotoBonus) : DEFAULT_SETTINGS.correctPhotoBonus,
        incorrectPhotoPenalty: incorrectPhotoPenalty !== undefined ? parseFloat(incorrectPhotoPenalty) : DEFAULT_SETTINGS.incorrectPhotoPenalty,
        questionsCount: questionsCount !== undefined ? parseInt(questionsCount) : DEFAULT_SETTINGS.questionsCount,
        updatedAt: new Date().toISOString()
      };

      // Валидация
      if (settings.defaultPoints < 0 || settings.defaultPoints > 100) {
        return res.status(400).json({ success: false, error: 'defaultPoints должен быть от 0 до 100' });
      }
      if (settings.basePhotos < 1 || settings.basePhotos > 20) {
        return res.status(400).json({ success: false, error: 'basePhotos должен быть от 1 до 20' });
      }
      if (settings.maxPhotos < settings.basePhotos) {
        return res.status(400).json({ success: false, error: 'maxPhotos должен быть >= basePhotos' });
      }
      if (settings.questionsCount < 1 || settings.questionsCount > 500) {
        return res.status(400).json({ success: false, error: 'questionsCount должен быть от 1 до 500' });
      }

      const settingsDir = path.dirname(RECOUNT_SETTINGS_FILE);
      if (!(await fileExists(settingsDir))) {
        await fsp.mkdir(settingsDir, { recursive: true });
      }

      await fsp.writeFile(RECOUNT_SETTINGS_FILE, JSON.stringify(settings, null, 2), 'utf8');

      console.log('✅ Настройки обновлены');
      res.json({ success: true, settings });
    } catch (error) {
      console.error('❌ Ошибка обновления настроек:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  };

  // Регистрируем PUT и POST handlers
  app.put('/api/recount-settings', updateRecountSettings);
  app.post('/api/recount-settings', updateRecountSettings);

  // =====================================================
  // PATCH /api/recount-reports/:id/verify-photo - верифицировать фото
  // =====================================================
  app.patch('/api/recount-reports/:id/verify-photo', async (req, res) => {
    try {
      const { id } = req.params;
      const { photoIndex, status, adminName, employeePhone } = req.body;

      console.log(`📤 PATCH /api/recount-reports/${id}/verify-photo: ${photoIndex} -> ${status}`);

      // Валидация
      if (photoIndex === undefined || !status) {
        return res.status(400).json({ success: false, error: 'Не указан photoIndex или status' });
      }
      if (!['approved', 'rejected'].includes(status)) {
        return res.status(400).json({ success: false, error: 'status должен быть approved или rejected' });
      }

      // Находим отчёт
      const reportsDir = `${DATA_DIR}/recount-reports`;
      // Санитизируем ID (кириллица и спецсимволы заменяются на _)
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const reportFile = path.join(reportsDir, `${sanitizedId}.json`);

      if (!(await fileExists(reportFile))) {
        console.log(`❌ Файл отчёта не найден: ${reportFile}`);
        return res.status(404).json({ success: false, error: 'Отчёт не найден' });
      }

      const report = JSON.parse(await fsp.readFile(reportFile, 'utf8'));

      // Инициализируем массив верификаций если его нет
      if (!report.photoVerifications) {
        report.photoVerifications = [];
      }

      // Проверяем, не была ли уже верифицирована эта фотография
      const existingIndex = report.photoVerifications.findIndex(v => v.photoIndex === photoIndex);
      if (existingIndex !== -1 && report.photoVerifications[existingIndex].status !== 'pending') {
        return res.status(400).json({
          success: false,
          error: 'Эта фотография уже была верифицирована'
        });
      }

      // Получаем настройки для начисления баллов
      const settings = await getSettings();
      const pointsChange = status === 'approved'
        ? settings.correctPhotoBonus
        : -settings.incorrectPhotoPenalty;

      // Добавляем или обновляем верификацию
      const verification = {
        photoIndex: photoIndex,
        status: status,
        adminName: adminName || 'Администратор',
        verifiedAt: new Date().toISOString(),
        pointsChange: pointsChange
      };

      if (existingIndex !== -1) {
        report.photoVerifications[existingIndex] = verification;
      } else {
        report.photoVerifications.push(verification);
      }

      // Сохраняем отчёт
      await fsp.writeFile(reportFile, JSON.stringify(report, null, 2), 'utf8');

      // Обновляем баллы сотрудника
      if (employeePhone) {
        const normalizedPhone = employeePhone.replace(/[\s+]/g, '');
        const pointsFile = path.join(RECOUNT_POINTS_DIR, `${normalizedPhone}.json`);

        if (await fileExists(pointsFile)) {
          const pointsData = JSON.parse(await fsp.readFile(pointsFile, 'utf8'));
          const newPoints = Math.max(0, Math.min(100, pointsData.points + pointsChange));

          pointsData.points = newPoints;
          pointsData.updatedAt = new Date().toISOString();
          pointsData.updatedBy = `Система (${status === 'approved' ? 'фото принято' : 'фото отклонено'})`;

          // Добавляем в историю
          if (!pointsData.history) pointsData.history = [];
          pointsData.history.push({
            oldPoints: pointsData.points - pointsChange,
            newPoints: newPoints,
            change: pointsChange,
            reason: `Верификация фото в отчёте ${id}`,
            status: status,
            date: new Date().toISOString()
          });

          await fsp.writeFile(pointsFile, JSON.stringify(pointsData, null, 2), 'utf8');
          console.log(`✅ Баллы изменены: ${normalizedPhone} ${pointsChange > 0 ? '+' : ''}${pointsChange} -> ${newPoints}`);
        }
      }

      console.log(`✅ Фото ${photoIndex} верифицировано как ${status}`);
      res.json({
        success: true,
        verification,
        pointsChange
      });
    } catch (error) {
      console.error('❌ Ошибка верификации фото:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Recount Points API initialized');
};

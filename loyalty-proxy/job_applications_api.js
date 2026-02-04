// =====================================================
// JOB APPLICATIONS API (Заявки на трудоустройство)
// =====================================================

const fs = require('fs');
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || DATA_DIR;

const JOB_APPLICATIONS_DIR = `${DATA_DIR}/job-applications`;

// Нормализация телефонного номера (убираем все кроме цифр и +)
function normalizePhone(phone) {
  if (!phone) return '';
  // Убираем все символы кроме цифр
  let normalized = phone.replace(/[^\d]/g, '');
  // Если начинается с 8, заменяем на 7
  if (normalized.startsWith('8') && normalized.length === 11) {
    normalized = '7' + normalized.substring(1);
  }
  // Если начинается с 9 и длина 10, добавляем 7
  if (!normalized.startsWith('7') && normalized.length === 10) {
    normalized = '7' + normalized;
  }
  return normalized;
}

// Проверка дубликата по телефону (за последние 24 часа)
function checkDuplicateApplication(phone) {
  try {
    if (!fs.existsSync(JOB_APPLICATIONS_DIR)) return null;

    const files = fs.readdirSync(JOB_APPLICATIONS_DIR);
    const oneDayAgo = Date.now() - (24 * 60 * 60 * 1000);
    const normalizedPhone = normalizePhone(phone);

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const content = fs.readFileSync(path.join(JOB_APPLICATIONS_DIR, file), 'utf8');
      const appData = JSON.parse(content);

      const appNormalizedPhone = normalizePhone(appData.phone);
      const appCreatedTime = new Date(appData.createdAt).getTime();

      // Если номер совпадает и заявка создана менее 24 часов назад
      if (appNormalizedPhone === normalizedPhone && appCreatedTime > oneDayAgo) {
        return appData;
      }
    }

    return null;
  } catch (error) {
    console.error('❌ Ошибка проверки дубликата:', error);
    return null;
  }
}

// Функция отправки push-уведомления админам
async function sendPushToAdmins(title, body) {
  try {
    const { admin, firebaseInitialized } = require('./firebase-admin-config');
    if (!firebaseInitialized) {
      console.log('⚠️ Firebase не инициализирован, push не отправлен');
      return;
    }

    // Получаем список админов из employees
    const employeesDir = `${DATA_DIR}/employees`;
    if (!fs.existsSync(employeesDir)) return;

    const files = fs.readdirSync(employeesDir);
    const fcmTokensDir = `${DATA_DIR}/fcm-tokens`;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const employeeData = JSON.parse(fs.readFileSync(path.join(employeesDir, file), 'utf8'));

      if (employeeData.isAdmin && employeeData.phone) {
        const normalizedPhone = employeeData.phone.replace(/[\s+]/g, '');
        const tokenFile = path.join(fcmTokensDir, `${normalizedPhone}.json`);

        if (fs.existsSync(tokenFile)) {
          const tokenData = JSON.parse(fs.readFileSync(tokenFile, 'utf8'));
          if (tokenData.token) {
            try {
              await admin.messaging().send({
                token: tokenData.token,
                notification: { title, body },
                android: { priority: 'high' }
              });
              console.log(`✅ Push отправлен админу: ${employeeData.name}`);
            } catch (e) {
              console.log(`⚠️ Не удалось отправить push: ${e.message}`);
            }
          }
        }
      }
    }
  } catch (error) {
    console.error('❌ Ошибка отправки push:', error);
  }
}

module.exports = function setupJobApplicationsAPI(app) {
  // GET /api/job-applications - получить все заявки
  app.get('/api/job-applications', async (req, res) => {
    try {
      console.log('📥 GET /api/job-applications');

      if (!fs.existsSync(JOB_APPLICATIONS_DIR)) {
        fs.mkdirSync(JOB_APPLICATIONS_DIR, { recursive: true });
        return res.json({ success: true, applications: [], unviewedCount: 0 });
      }

      const files = fs.readdirSync(JOB_APPLICATIONS_DIR);
      const applications = [];
      let unviewedCount = 0;

      for (const file of files) {
        if (!file.endsWith('.json')) continue;

        const content = fs.readFileSync(path.join(JOB_APPLICATIONS_DIR, file), 'utf8');
        const appData = JSON.parse(content);
        applications.push(appData);

        if (!appData.isViewed) {
          unviewedCount++;
        }
      }

      // Сортируем по дате создания (новые первые)
      applications.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      res.json({ success: true, applications, unviewedCount });
    } catch (error) {
      console.error('❌ Ошибка получения заявок:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/job-applications - создать заявку
  app.post('/api/job-applications', async (req, res) => {
    try {
      const { fullName, phone, preferredShift, shopAddresses } = req.body;

      console.log(`📤 POST /api/job-applications: ${fullName}`);

      // Валидация
      if (!fullName || !phone || !preferredShift || !shopAddresses) {
        return res.status(400).json({
          success: false,
          error: 'Обязательные поля: fullName, phone, preferredShift, shopAddresses'
        });
      }

      // Проверка дубликата по телефону (за последние 24 часа)
      const duplicate = checkDuplicateApplication(phone);
      if (duplicate) {
        const hoursAgo = Math.floor((Date.now() - new Date(duplicate.createdAt).getTime()) / (1000 * 60 * 60));
        const hoursRemaining = 24 - hoursAgo;

        console.log(`⚠️ Дубликат заявки от ${duplicate.fullName} (${hoursAgo} часов назад)`);

        return res.status(429).json({
          success: false,
          error: `Вы уже подавали заявку ${hoursAgo} ${hoursAgo === 1 ? 'час' : hoursAgo < 5 ? 'часа' : 'часов'} назад. Повторная подача возможна через ${hoursRemaining} ${hoursRemaining === 1 ? 'час' : hoursRemaining < 5 ? 'часа' : 'часов'}.`,
          duplicateId: duplicate.id,
          canReapplyAt: new Date(new Date(duplicate.createdAt).getTime() + 24 * 60 * 60 * 1000).toISOString()
        });
      }

      if (!fs.existsSync(JOB_APPLICATIONS_DIR)) {
        fs.mkdirSync(JOB_APPLICATIONS_DIR, { recursive: true });
      }

      // Нормализуем телефон перед сохранением
      const normalizedPhone = normalizePhone(phone);

      const id = `job_${Date.now()}`;
      const application = {
        id,
        fullName,
        phone: normalizedPhone, // Сохраняем нормализованный
        preferredShift,
        shopAddresses,
        createdAt: new Date().toISOString(),
        isViewed: false,
        viewedAt: null,
        viewedBy: null,
        status: 'new', // Новая заявка
        adminNotes: null,
        statusUpdatedAt: null,
        notesUpdatedAt: null
      };

      const filePath = path.join(JOB_APPLICATIONS_DIR, `${id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(application, null, 2), 'utf8');

      console.log(`✅ Заявка создана: ${id}`);

      // Отправляем push-уведомление админам
      const shiftText = preferredShift === 'day' ? 'День' : 'Ночь';
      sendPushToAdmins(
        'Новая заявка на работу',
        `${fullName} хочет работать (${shiftText})`
      );

      res.json({ success: true, application });
    } catch (error) {
      console.error('❌ Ошибка создания заявки:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/job-applications/unviewed-count - получить количество непросмотренных
  app.get('/api/job-applications/unviewed-count', async (req, res) => {
    try {
      if (!fs.existsSync(JOB_APPLICATIONS_DIR)) {
        return res.json({ success: true, count: 0 });
      }

      const files = fs.readdirSync(JOB_APPLICATIONS_DIR);
      let count = 0;

      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        const content = fs.readFileSync(path.join(JOB_APPLICATIONS_DIR, file), 'utf8');
        const appData = JSON.parse(content);
        if (!appData.isViewed) count++;
      }

      res.json({ success: true, count });
    } catch (error) {
      console.error('❌ Ошибка:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PATCH /api/job-applications/:id/view - отметить как просмотренную
  app.patch('/api/job-applications/:id/view', async (req, res) => {
    try {
      const { id } = req.params;
      const { adminName } = req.body;

      console.log(`👁️ PATCH /api/job-applications/${id}/view`);

      const filePath = path.join(JOB_APPLICATIONS_DIR, `${id}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Заявка не найдена' });
      }

      const content = fs.readFileSync(filePath, 'utf8');
      const application = JSON.parse(content);

      application.isViewed = true;
      application.viewedAt = new Date().toISOString();
      application.viewedBy = adminName || 'Администратор';

      // Если статус был 'new', меняем на 'viewed'
      if (application.status === 'new' || !application.status) {
        application.status = 'viewed';
      }

      fs.writeFileSync(filePath, JSON.stringify(application, null, 2), 'utf8');

      console.log(`✅ Заявка ${id} отмечена как просмотренная`);
      res.json({ success: true, application });
    } catch (error) {
      console.error('❌ Ошибка:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PATCH /api/job-applications/:id/status - обновить статус
  app.patch('/api/job-applications/:id/status', async (req, res) => {
    try {
      const { id } = req.params;
      const { status } = req.body;

      console.log(`🔄 PATCH /api/job-applications/${id}/status -> ${status}`);

      const filePath = path.join(JOB_APPLICATIONS_DIR, `${id}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Заявка не найдена' });
      }

      const content = fs.readFileSync(filePath, 'utf8');
      const application = JSON.parse(content);

      application.status = status;
      application.statusUpdatedAt = new Date().toISOString();

      fs.writeFileSync(filePath, JSON.stringify(application, null, 2), 'utf8');

      console.log(`✅ Статус заявки ${id} обновлен: ${status}`);
      res.json({ success: true, application });
    } catch (error) {
      console.error('❌ Ошибка:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PATCH /api/job-applications/:id/notes - обновить комментарии
  app.patch('/api/job-applications/:id/notes', async (req, res) => {
    try {
      const { id } = req.params;
      const { adminNotes } = req.body;

      console.log(`📝 PATCH /api/job-applications/${id}/notes`);

      const filePath = path.join(JOB_APPLICATIONS_DIR, `${id}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Заявка не найдена' });
      }

      const content = fs.readFileSync(filePath, 'utf8');
      const application = JSON.parse(content);

      application.adminNotes = adminNotes;
      application.notesUpdatedAt = new Date().toISOString();

      fs.writeFileSync(filePath, JSON.stringify(application, null, 2), 'utf8');

      console.log(`✅ Комментарии к заявке ${id} обновлены`);
      res.json({ success: true, application });
    } catch (error) {
      console.error('❌ Ошибка:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Job Applications API initialized');
};

// =====================================================
// JOB APPLICATIONS API (Заявки на трудоустройство)
//
// REFACTORED: Converted from sync to async I/O (2026-02-05)
// =====================================================

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { isPaginationRequested, createPaginatedResponse, createDbPaginatedResponse } = require('../utils/pagination');
const { requireAuth } = require('../utils/session_middleware');
const { notifyCounterUpdate } = require('./counters_websocket');

const USE_DB = process.env.USE_DB_JOB_APPLICATIONS === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const JOB_APPLICATIONS_DIR = `${DATA_DIR}/job-applications`;

// Ensure directory exists (async IIFE)
(async () => {
  if (!(await fileExists(JOB_APPLICATIONS_DIR))) {
    await fsp.mkdir(JOB_APPLICATIONS_DIR, { recursive: true });
  }
})();

// ==================== DB converters ====================

function jobAppToDb(app) {
  return {
    id: app.id,
    full_name: app.fullName || null,
    phone: app.phone || null,
    preferred_shift: app.preferredShift || null,
    shop_addresses: app.shopAddresses || null,
    is_viewed: app.isViewed === true,
    viewed_at: app.viewedAt || null,
    viewed_by: app.viewedBy || null,
    status: app.status || 'new',
    admin_notes: app.adminNotes || null,
    status_updated_at: app.statusUpdatedAt || null,
    notes_updated_at: app.notesUpdatedAt || null,
    created_at: app.createdAt || new Date().toISOString()
  };
}

function dbToJobApp(row) {
  return {
    id: row.id,
    fullName: row.full_name,
    phone: row.phone,
    preferredShift: row.preferred_shift,
    shopAddresses: row.shop_addresses,
    isViewed: row.is_viewed,
    viewedAt: row.viewed_at ? new Date(row.viewed_at).toISOString() : null,
    viewedBy: row.viewed_by,
    status: row.status,
    adminNotes: row.admin_notes,
    statusUpdatedAt: row.status_updated_at ? new Date(row.status_updated_at).toISOString() : null,
    notesUpdatedAt: row.notes_updated_at ? new Date(row.notes_updated_at).toISOString() : null,
    createdAt: row.created_at ? new Date(row.created_at).toISOString() : null
  };
}

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
async function checkDuplicateApplication(phone) {
  try {
    const normalizedPhone = normalizePhone(phone);
    const oneDayAgo = new Date(Date.now() - (24 * 60 * 60 * 1000));

    if (USE_DB) {
      const result = await db.query(
        `SELECT * FROM "job_applications" WHERE "phone" = $1 AND "created_at" > $2 ORDER BY "created_at" DESC LIMIT 1`,
        [normalizedPhone, oneDayAgo.toISOString()]
      );
      if (result.rows.length > 0) return dbToJobApp(result.rows[0]);
      return null;
    }

    if (!(await fileExists(JOB_APPLICATIONS_DIR))) return null;

    const files = await fsp.readdir(JOB_APPLICATIONS_DIR);

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const content = await fsp.readFile(path.join(JOB_APPLICATIONS_DIR, file), 'utf8');
        const appData = JSON.parse(content);

        const appNormalizedPhone = normalizePhone(appData.phone);
        const appCreatedTime = new Date(appData.createdAt).getTime();

        if (appNormalizedPhone === normalizedPhone && appCreatedTime > oneDayAgo.getTime()) {
          return appData;
        }
      } catch (e) {
        // Skip invalid files
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
    const { admin, firebaseInitialized } = require('../firebase-admin-config');
    if (!firebaseInitialized) {
      console.log('⚠️ Firebase не инициализирован, push не отправлен');
      return;
    }

    // Получаем список админов из employees
    const employeesDir = `${DATA_DIR}/employees`;
    if (!(await fileExists(employeesDir))) return;

    const files = await fsp.readdir(employeesDir);
    const fcmTokensDir = `${DATA_DIR}/fcm-tokens`;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const employeeData = JSON.parse(await fsp.readFile(path.join(employeesDir, file), 'utf8'));

        if (employeeData.isAdmin && employeeData.phone) {
          const normalizedPhone = employeeData.phone.replace(/[^\d]/g, '');
          const tokenFile = path.join(fcmTokensDir, `${normalizedPhone}.json`);

          if (await fileExists(tokenFile)) {
            const tokenData = JSON.parse(await fsp.readFile(tokenFile, 'utf8'));
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
      } catch (e) {
        // Skip invalid employee files
      }
    }
  } catch (error) {
    console.error('❌ Ошибка отправки push:', error);
  }
}

module.exports = function setupJobApplicationsAPI(app) {
  // GET /api/job-applications - получить все заявки
  app.get('/api/job-applications', requireAuth, async (req, res) => {
    try {
      console.log('📥 GET /api/job-applications');

      if (USE_DB) {
        if (isPaginationRequested(req.query)) {
          const [result, countResult] = await Promise.all([
            db.findAllPaginated('job_applications', {
              orderBy: 'created_at', orderDir: 'DESC',
              page: parseInt(req.query.page) || 1,
              pageSize: Math.min(parseInt(req.query.limit) || 50, 200),
            }),
            db.query("SELECT COUNT(*) AS cnt FROM job_applications WHERE is_viewed = false"),
          ]);
          const response = createDbPaginatedResponse(result, 'applications', dbToJobApp);
          response.unviewedCount = parseInt(countResult.rows[0].cnt);
          return res.json(response);
        }
        const rows = await db.findAll('job_applications', { orderBy: 'created_at', orderDir: 'DESC' });
        const applications = rows.map(dbToJobApp);
        const unviewedCount = rows.filter(r => !r.is_viewed).length;
        return res.json({ success: true, applications, unviewedCount });
      }

      if (!(await fileExists(JOB_APPLICATIONS_DIR))) {
        await fsp.mkdir(JOB_APPLICATIONS_DIR, { recursive: true });
        return res.json({ success: true, applications: [], unviewedCount: 0 });
      }

      const files = await fsp.readdir(JOB_APPLICATIONS_DIR);
      const applications = [];
      let unviewedCount = 0;

      for (const file of files) {
        if (!file.endsWith('.json')) continue;

        try {
          const content = await fsp.readFile(path.join(JOB_APPLICATIONS_DIR, file), 'utf8');
          const appData = JSON.parse(content);
          applications.push(appData);

          if (!appData.isViewed) {
            unviewedCount++;
          }
        } catch (e) {
          console.error(`Error reading ${file}:`, e);
        }
      }

      // Сортируем по дате создания (новые первые)
      applications.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      if (isPaginationRequested(req.query)) {
        return res.json({ ...createPaginatedResponse(applications, req.query, 'applications'), unviewedCount });
      }
      res.json({ success: true, applications, unviewedCount });
    } catch (error) {
      console.error('❌ Ошибка получения заявок:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/job-applications - создать заявку
  app.post('/api/job-applications', requireAuth, async (req, res) => {
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
      const duplicate = await checkDuplicateApplication(phone);
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

      if (!(await fileExists(JOB_APPLICATIONS_DIR))) {
        await fsp.mkdir(JOB_APPLICATIONS_DIR, { recursive: true });
      }

      // Нормализуем телефон перед сохранением
      const normalizedPhone = normalizePhone(phone);

      const id = `job_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
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
      await writeJsonFile(filePath, application);

      if (USE_DB) {
        try { await db.upsert('job_applications', jobAppToDb(application)); }
        catch (dbErr) { console.error('DB save job_application error:', dbErr.message); }
      }

      console.log(`✅ Заявка создана: ${id}`);

      // Отправляем push-уведомление админам
      const shiftText = preferredShift === 'day' ? 'День' : 'Ночь';
      await sendPushToAdmins(
        'Новая заявка на работу',
        `${fullName} хочет работать (${shiftText})`
      );

      notifyCounterUpdate('jobApplications', { delta: 1 });
      res.json({ success: true, application });
    } catch (error) {
      console.error('❌ Ошибка создания заявки:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/job-applications/unviewed-count - получить количество непросмотренных
  app.get('/api/job-applications/unviewed-count', requireAuth, async (req, res) => {
    try {
      if (USE_DB) {
        const cnt = await db.count('job_applications', { is_viewed: false });
        return res.json({ success: true, count: cnt });
      }

      if (!(await fileExists(JOB_APPLICATIONS_DIR))) {
        return res.json({ success: true, count: 0 });
      }

      const files = await fsp.readdir(JOB_APPLICATIONS_DIR);
      let count = 0;

      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const content = await fsp.readFile(path.join(JOB_APPLICATIONS_DIR, file), 'utf8');
          const appData = JSON.parse(content);
          if (!appData.isViewed) count++;
        } catch (e) {
          // Skip invalid files
        }
      }

      res.json({ success: true, count });
    } catch (error) {
      console.error('❌ Ошибка:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PATCH /api/job-applications/:id/view - отметить как просмотренную
  app.patch('/api/job-applications/:id/view', requireAuth, async (req, res) => {
    try {
      const { id } = req.params;
      const { adminName } = req.body;

      console.log(`👁️ PATCH /api/job-applications/${id}/view`);

      const filePath = path.join(JOB_APPLICATIONS_DIR, `${id}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Заявка не найдена' });
      }

      const content = await fsp.readFile(filePath, 'utf8');
      const application = JSON.parse(content);

      application.isViewed = true;
      application.viewedAt = new Date().toISOString();
      application.viewedBy = adminName || 'Администратор';

      // Если статус был 'new', меняем на 'viewed'
      if (application.status === 'new' || !application.status) {
        application.status = 'viewed';
      }

      await writeJsonFile(filePath, application);

      if (USE_DB) {
        try { await db.upsert('job_applications', jobAppToDb(application)); }
        catch (dbErr) { console.error('DB update job_application error:', dbErr.message); }
      }

      console.log(`✅ Заявка ${id} отмечена как просмотренная`);
      res.json({ success: true, application });
    } catch (error) {
      console.error('❌ Ошибка:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PATCH /api/job-applications/:id/status - обновить статус
  app.patch('/api/job-applications/:id/status', requireAuth, async (req, res) => {
    try {
      const { id } = req.params;
      const { status } = req.body;

      console.log(`🔄 PATCH /api/job-applications/${id}/status -> ${status}`);

      const filePath = path.join(JOB_APPLICATIONS_DIR, `${id}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Заявка не найдена' });
      }

      const content = await fsp.readFile(filePath, 'utf8');
      const application = JSON.parse(content);

      application.status = status;
      application.statusUpdatedAt = new Date().toISOString();

      await writeJsonFile(filePath, application);

      if (USE_DB) {
        try { await db.upsert('job_applications', jobAppToDb(application)); }
        catch (dbErr) { console.error('DB update job_application status error:', dbErr.message); }
      }

      console.log(`✅ Статус заявки ${id} обновлен: ${status}`);
      res.json({ success: true, application });
    } catch (error) {
      console.error('❌ Ошибка:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PATCH /api/job-applications/:id/notes - обновить комментарии
  app.patch('/api/job-applications/:id/notes', requireAuth, async (req, res) => {
    try {
      const { id } = req.params;
      const { adminNotes } = req.body;

      console.log(`📝 PATCH /api/job-applications/${id}/notes`);

      const filePath = path.join(JOB_APPLICATIONS_DIR, `${id}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Заявка не найдена' });
      }

      const content = await fsp.readFile(filePath, 'utf8');
      const application = JSON.parse(content);

      application.adminNotes = adminNotes;
      application.notesUpdatedAt = new Date().toISOString();

      await writeJsonFile(filePath, application);

      if (USE_DB) {
        try { await db.upsert('job_applications', jobAppToDb(application)); }
        catch (dbErr) { console.error('DB update job_application notes error:', dbErr.message); }
      }

      console.log(`✅ Комментарии к заявке ${id} обновлены`);
      res.json({ success: true, application });
    } catch (error) {
      console.error('❌ Ошибка:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Job Applications API initialized ${USE_DB ? '(DB mode)' : '(file mode)'}`);
};

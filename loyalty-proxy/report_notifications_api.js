/**
 * API для уведомлений о новых отчётах
 * Типы отчётов:
 * - shift_handover (Пересменка)
 * - recount (Пересчёт товара)
 * - test (Тестирование)
 * - shift_report (Сдать смену)
 * - attendance (Я на работе)
 * - rko (РКО)
 */

const fs = require('fs');
const path = require('path');
const { admin, firebaseInitialized } = require('./firebase-admin-config');

// Директория хранения уведомлений
const NOTIFICATIONS_DIR = '/var/www/report-notifications';
const EMPLOYEES_DIR = '/var/www/employees';
const FCM_TOKENS_DIR = '/var/www/fcm-tokens';

// Создаём директорию если не существует
if (!fs.existsSync(NOTIFICATIONS_DIR)) {
  fs.mkdirSync(NOTIFICATIONS_DIR, { recursive: true });
}

// ==================== УТИЛИТЫ ====================

function loadJsonFile(filePath, defaultValue = []) {
  try {
    if (fs.existsSync(filePath)) {
      return JSON.parse(fs.readFileSync(filePath, 'utf8'));
    }
  } catch (e) {
    console.error('Error loading file:', filePath, e);
  }
  return defaultValue;
}

function saveJsonFile(filePath, data) {
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
}

function generateId() {
  return 'notif_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
}

// Получить все уведомления
function loadNotifications() {
  const filePath = path.join(NOTIFICATIONS_DIR, 'all.json');
  return loadJsonFile(filePath, []);
}

// Сохранить все уведомления
function saveNotifications(notifications) {
  const filePath = path.join(NOTIFICATIONS_DIR, 'all.json');
  saveJsonFile(filePath, notifications);
}

// Получить FCM токены админов
function getAdminFcmTokens() {
  const tokens = [];
  try {
    // Сначала получаем телефоны админов из списка сотрудников
    const adminPhones = [];
    const employeeFiles = fs.readdirSync(EMPLOYEES_DIR);
    for (const file of employeeFiles) {
      if (!file.endsWith('.json')) continue;
      const filePath = path.join(EMPLOYEES_DIR, file);
      const employee = loadJsonFile(filePath, null);
      if (employee && employee.isAdmin === true && employee.phone) {
        // Нормализуем телефон (убираем + и пробелы)
        const normalizedPhone = employee.phone.replace(/[\s\+]/g, '');
        adminPhones.push(normalizedPhone);
      }
    }

    console.log(`Найдено ${adminPhones.length} админов с телефонами:`, adminPhones);

    // Теперь ищем FCM токены для этих телефонов
    if (!fs.existsSync(FCM_TOKENS_DIR)) {
      console.log('Папка FCM токенов не существует');
      return tokens;
    }

    const tokenFiles = fs.readdirSync(FCM_TOKENS_DIR);
    for (const file of tokenFiles) {
      if (!file.endsWith('.json')) continue;
      const phone = file.replace('.json', '');
      if (adminPhones.includes(phone)) {
        const filePath = path.join(FCM_TOKENS_DIR, file);
        const tokenData = loadJsonFile(filePath, null);
        if (tokenData && tokenData.token) {
          tokens.push(tokenData.token);
          console.log(`Найден FCM токен для админа ${phone}`);
        }
      }
    }
  } catch (e) {
    console.error('Ошибка получения FCM токенов админов:', e);
  }
  return tokens;
}

// Отправить push-уведомление всем админам
async function sendPushNotification(title, body, data = {}) {
  if (!firebaseInitialized || !admin) {
    console.log('Firebase не инициализирован, push-уведомление не отправлено');
    return;
  }

  const tokens = getAdminFcmTokens();
  if (tokens.length === 0) {
    console.log('Нет FCM токенов админов для отправки уведомления');
    return;
  }

  console.log(`Отправка push-уведомления ${tokens.length} админам: ${title}`);

  for (const token of tokens) {
    try {
      await admin.messaging().send({
        token: token,
        notification: {
          title: title,
          body: body,
        },
        data: {
          ...data,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'reports_channel',
          },
        },
      });
      console.log('Push-уведомление отправлено:', token.substring(0, 20) + '...');
    } catch (e) {
      console.error('❌ Ошибка отправки push-уведомления:', e.message);
    }
  }
}

// Отправить push-уведомление конкретному пользователю по номеру телефона
async function sendPushToPhone(phone, title, body, data = {}) {
  if (!firebaseInitialized || !admin) {
    console.log('Firebase не инициализирован, push-уведомление не отправлено');
    return false;
  }

  try {
    // Нормализуем телефон (убираем + и пробелы)
    const normalizedPhone = phone.replace(/[\s\+]/g, '');
    const tokenFile = path.join(FCM_TOKENS_DIR, `${normalizedPhone}.json`);

    if (!fs.existsSync(tokenFile)) {
      console.log(`Нет FCM токена для телефона: ${phone}`);
      return false;
    }

    const tokenData = loadJsonFile(tokenFile, null);
    if (!tokenData || !tokenData.token) {
      console.log(`Некорректный FCM токен для телефона: ${phone}`);
      return false;
    }

    console.log(`Отправка push-уведомления на ${phone}: ${title}`);

    await admin.messaging().send({
      token: tokenData.token,
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...data,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'reviews_channel',
        },
      },
    });

    console.log(`✓ Push-уведомление отправлено на ${phone}`);
    return true;
  } catch (e) {
    console.error(`❌ Ошибка отправки push-уведомления на ${phone}:`, e.message);
    return false;
  }
}

// Названия типов отчётов на русском
const REPORT_TYPE_NAMES = {
  'shift_handover': 'Пересменка',
  'recount': 'Пересчёт товара',
  'test': 'Тестирование',
  'shift_report': 'Сдать смену',
  'attendance': 'Я на работе',
  'rko': 'РКО',
};

// ==================== SETUP FUNCTION ====================

function setupReportNotificationsAPI(app) {
  console.log('Setting up Report Notifications API...');

  // GET /api/report-notifications - Получить все уведомления
  app.get('/api/report-notifications', (req, res) => {
    try {
      const notifications = loadNotifications();
      res.json({ success: true, notifications });
    } catch (e) {
      console.error('Error getting notifications:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // GET /api/report-notifications/unviewed-counts - Получить количество непросмотренных по типам
  app.get('/api/report-notifications/unviewed-counts', (req, res) => {
    try {
      const notifications = loadNotifications();
      const counts = {
        shift_handover: 0,
        recount: 0,
        test: 0,
        shift_report: 0,
        attendance: 0,
        rko: 0,
        total: 0,
      };

      for (const notif of notifications) {
        if (!notif.viewedAt) {
          if (counts.hasOwnProperty(notif.reportType)) {
            counts[notif.reportType]++;
          }
          counts.total++;
        }
      }

      res.json({ success: true, counts });
    } catch (e) {
      console.error('Error getting unviewed counts:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/report-notifications - Создать уведомление о новом отчёте
  app.post('/api/report-notifications', async (req, res) => {
    try {
      const {
        reportType,      // Тип отчёта: shift_handover, recount, test, shift_report, attendance, rko
        reportId,        // ID отчёта
        employeeName,    // Имя сотрудника, создавшего отчёт
        shopName,        // Название магазина (опционально)
        description,     // Дополнительное описание (опционально)
      } = req.body;

      if (!reportType || !reportId) {
        return res.status(400).json({ success: false, error: 'Missing required fields: reportType, reportId' });
      }

      const notifications = loadNotifications();
      const now = new Date().toISOString();

      const newNotification = {
        id: generateId(),
        reportType,
        reportId,
        employeeName: employeeName || 'Неизвестный',
        shopName: shopName || null,
        description: description || null,
        createdAt: now,
        viewedAt: null,
        viewedBy: null,
      };

      notifications.push(newNotification);
      saveNotifications(notifications);

      console.log(`Создано уведомление о ${REPORT_TYPE_NAMES[reportType] || reportType}: ${employeeName}`);

      // Отправляем push-уведомление админам
      const typeName = REPORT_TYPE_NAMES[reportType] || reportType;
      const pushTitle = `Новый отчёт: ${typeName}`;
      let pushBody = `${employeeName}`;
      if (shopName) {
        pushBody += ` (${shopName})`;
      }

      await sendPushNotification(pushTitle, pushBody, {
        type: 'report_notification',
        reportType: reportType,
        reportId: reportId,
      });

      res.json({ success: true, notification: newNotification });
    } catch (e) {
      console.error('Error creating notification:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // PATCH /api/report-notifications/:id/view - Отметить уведомление как просмотренное
  app.patch('/api/report-notifications/:id/view', (req, res) => {
    try {
      const { id } = req.params;
      const { adminName } = req.body;

      const notifications = loadNotifications();
      const index = notifications.findIndex(n => n.id === id);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Notification not found' });
      }

      if (!notifications[index].viewedAt) {
        notifications[index].viewedAt = new Date().toISOString();
        notifications[index].viewedBy = adminName || 'admin';
        saveNotifications(notifications);
        console.log(`Уведомление ${id} отмечено как просмотренное`);
      }

      res.json({ success: true, notification: notifications[index] });
    } catch (e) {
      console.error('Error marking notification as viewed:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // PATCH /api/report-notifications/view-by-report - Отметить просмотренным по ID отчёта
  app.patch('/api/report-notifications/view-by-report', (req, res) => {
    try {
      const { reportType, reportId, adminName } = req.body;

      if (!reportType || !reportId) {
        return res.status(400).json({ success: false, error: 'Missing reportType or reportId' });
      }

      const notifications = loadNotifications();
      let updated = false;

      for (const notif of notifications) {
        if (notif.reportType === reportType && notif.reportId === reportId && !notif.viewedAt) {
          notif.viewedAt = new Date().toISOString();
          notif.viewedBy = adminName || 'admin';
          updated = true;
        }
      }

      if (updated) {
        saveNotifications(notifications);
        console.log(`Уведомления для ${reportType}/${reportId} отмечены как просмотренные`);
      }

      res.json({ success: true, updated });
    } catch (e) {
      console.error('Error marking notifications as viewed:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/report-notifications/mark-all-viewed - Отметить все уведомления типа как просмотренные
  app.post('/api/report-notifications/mark-all-viewed', (req, res) => {
    try {
      const { reportType, adminName } = req.body;

      const notifications = loadNotifications();
      const now = new Date().toISOString();
      let count = 0;

      for (const notif of notifications) {
        // Если указан тип - только этот тип, иначе все
        if ((!reportType || notif.reportType === reportType) && !notif.viewedAt) {
          notif.viewedAt = now;
          notif.viewedBy = adminName || 'admin';
          count++;
        }
      }

      if (count > 0) {
        saveNotifications(notifications);
        console.log(`Отмечено ${count} уведомлений как просмотренные (тип: ${reportType || 'все'})`);
      }

      res.json({ success: true, markedCount: count });
    } catch (e) {
      console.error('Error marking all as viewed:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // DELETE /api/report-notifications/cleanup - Удалить старые просмотренные уведомления (старше 30 дней)
  app.delete('/api/report-notifications/cleanup', (req, res) => {
    try {
      const notifications = loadNotifications();
      const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

      const filtered = notifications.filter(n => {
        // Оставляем непросмотренные или просмотренные менее 30 дней назад
        return !n.viewedAt || n.viewedAt > thirtyDaysAgo;
      });

      const removedCount = notifications.length - filtered.length;
      if (removedCount > 0) {
        saveNotifications(filtered);
        console.log(`Удалено ${removedCount} старых уведомлений`);
      }

      res.json({ success: true, removedCount });
    } catch (e) {
      console.error('Error cleaning up notifications:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  console.log('Report Notifications API setup complete');
}

module.exports = { setupReportNotificationsAPI, sendPushNotification, sendPushToPhone };

/**
 * API для уведомлений о новых отчётах
 * Типы отчётов:
 * - shift_handover (Пересменка)
 * - recount (Пересчёт товара)
 * - test (Тестирование)
 * - shift_report (Сдать смену)
 * - attendance (Я на работе)
 * - rko (РКО)
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, maskPhone } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const { requireAuth } = require('../utils/session_middleware');
const pushService = require('../utils/push_service');

// Директория хранения уведомлений
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const NOTIFICATIONS_DIR = `${DATA_DIR}/report-notifications`;

// Создаём директорию если не существует
(async () => {
  try {
    if (!(await fileExists(NOTIFICATIONS_DIR))) {
      await fsp.mkdir(NOTIFICATIONS_DIR, { recursive: true });
    }
  } catch (e) {
    console.error('Error creating notifications directory:', e.message);
  }
})();

// ==================== УТИЛИТЫ ====================

async function loadJsonFile(filePath, defaultValue = []) {
  try {
    if (await fileExists(filePath)) {
      const content = await fsp.readFile(filePath, 'utf8');
      return JSON.parse(content);
    }
  } catch (e) {
    console.error('Error loading file:', filePath, e);
  }
  return defaultValue;
}

function generateId() {
  return 'notif_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
}

// Получить все уведомления
async function loadNotifications() {
  const filePath = path.join(NOTIFICATIONS_DIR, 'all.json');
  return await loadJsonFile(filePath, []);
}

// Сохранить все уведомления
async function saveNotifications(notifications) {
  const filePath = path.join(NOTIFICATIONS_DIR, 'all.json');
  await writeJsonFile(filePath, notifications);
}

// Push-функции делегируются в push_service.js (BUG-06: единый модуль)
async function sendPushNotification(title, body, data = {}) {
  return pushService.sendPushToAllAdmins(title, body, data, 'reports_channel');
}

async function sendPushToPhone(phone, title, body, data = {}) {
  return pushService.sendPushToPhone(phone, title, body, data, 'reports_channel');
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
  app.get('/api/report-notifications', requireAuth, async (req, res) => {
    try {
      const notifications = await loadNotifications();
      res.json({ success: true, notifications });
    } catch (e) {
      console.error('Error getting notifications:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // GET /api/report-notifications/unviewed-counts - Получить количество непросмотренных по типам
  app.get('/api/report-notifications/unviewed-counts', requireAuth, async (req, res) => {
    try {
      const notifications = await loadNotifications();
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
  app.post('/api/report-notifications', requireAuth, async (req, res) => {
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

      const notifications = await loadNotifications();
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
      await saveNotifications(notifications);

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
  app.patch('/api/report-notifications/:id/view', requireAuth, async (req, res) => {
    try {
      const { id } = req.params;
      const { adminName } = req.body;

      const notifications = await loadNotifications();
      const index = notifications.findIndex(n => n.id === id);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Notification not found' });
      }

      if (!notifications[index].viewedAt) {
        notifications[index].viewedAt = new Date().toISOString();
        notifications[index].viewedBy = adminName || 'admin';
        await saveNotifications(notifications);
        console.log(`Уведомление ${id} отмечено как просмотренное`);
      }

      res.json({ success: true, notification: notifications[index] });
    } catch (e) {
      console.error('Error marking notification as viewed:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // PATCH /api/report-notifications/view-by-report - Отметить просмотренным по ID отчёта
  app.patch('/api/report-notifications/view-by-report', requireAuth, async (req, res) => {
    try {
      const { reportType, reportId, adminName } = req.body;

      if (!reportType || !reportId) {
        return res.status(400).json({ success: false, error: 'Missing reportType or reportId' });
      }

      const notifications = await loadNotifications();
      let updated = false;

      for (const notif of notifications) {
        if (notif.reportType === reportType && notif.reportId === reportId && !notif.viewedAt) {
          notif.viewedAt = new Date().toISOString();
          notif.viewedBy = adminName || 'admin';
          updated = true;
        }
      }

      if (updated) {
        await saveNotifications(notifications);
        console.log(`Уведомления для ${reportType}/${reportId} отмечены как просмотренные`);
      }

      res.json({ success: true, updated });
    } catch (e) {
      console.error('Error marking notifications as viewed:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/report-notifications/mark-all-viewed - Отметить все уведомления типа как просмотренные
  app.post('/api/report-notifications/mark-all-viewed', requireAuth, async (req, res) => {
    try {
      const { reportType, adminName } = req.body;

      const notifications = await loadNotifications();
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
        await saveNotifications(notifications);
        console.log(`Отмечено ${count} уведомлений как просмотренные (тип: ${reportType || 'все'})`);
      }

      res.json({ success: true, markedCount: count });
    } catch (e) {
      console.error('Error marking all as viewed:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // DELETE /api/report-notifications/cleanup - Удалить старые просмотренные уведомления (старше 30 дней)
  app.delete('/api/report-notifications/cleanup', requireAuth, async (req, res) => {
    try {
      const notifications = await loadNotifications();
      const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

      const filtered = notifications.filter(n => {
        // Оставляем непросмотренные или просмотренные менее 30 дней назад
        return !n.viewedAt || n.viewedAt > thirtyDaysAgo;
      });

      const removedCount = notifications.length - filtered.length;
      if (removedCount > 0) {
        await saveNotifications(filtered);
        console.log(`Удалено ${removedCount} старых уведомлений`);
      }

      res.json({ success: true, removedCount });
    } catch (e) {
      console.error('Error cleaning up notifications:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // ==================== PUSH ДЛЯ СОТРУДНИКОВ ====================

  // POST /api/push/report-status - Отправить push сотруднику о статусе отчёта
  // Используется при одобрении/отклонении отчётов админом
  app.post('/api/push/report-status', requireAuth, async (req, res) => {
    try {
      const {
        employeePhone,   // Телефон сотрудника
        reportType,      // Тип отчёта: shift_handover, recount, rko, envelope
        status,          // Статус: approved, rejected, confirmed
        reportDate,      // Дата отчёта (опционально)
        rating,          // Оценка (опционально)
        comment,         // Комментарий (опционально)
      } = req.body;

      if (!employeePhone || !reportType || !status) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: employeePhone, reportType, status'
        });
      }

      const typeName = REPORT_TYPE_NAMES[reportType] || reportType;
      let title, body;

      if (status === 'approved' || status === 'confirmed') {
        title = `${typeName} одобрена ✓`;
        body = rating ? `Оценка: ${rating}/5` : 'Ваш отчёт принят';
        if (reportDate) body = `${reportDate} - ${body}`;
      } else if (status === 'rejected') {
        title = `${typeName} отклонена`;
        body = comment || 'Требуется повторная отправка';
        if (reportDate) body = `${reportDate} - ${body}`;
      } else {
        title = `${typeName}: статус изменён`;
        body = `Новый статус: ${status}`;
      }

      const pushData = {
        type: 'report_status_changed',
        reportType: reportType,
        status: status,
      };

      const sent = await sendPushToPhone(employeePhone, title, body, pushData);

      console.log(`Push статуса отчёта ${reportType} → ${employeePhone}: ${sent ? 'отправлен' : 'не отправлен'}`);

      res.json({ success: true, sent });
    } catch (e) {
      console.error('Error sending report status push:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/push/test-assigned - Отправить push о назначении теста
  app.post('/api/push/test-assigned', requireAuth, async (req, res) => {
    try {
      const {
        employeePhone,   // Телефон сотрудника
        testTitle,       // Название теста
        testId,          // ID теста
        deadline,        // Дедлайн (опционально)
      } = req.body;

      if (!employeePhone || !testTitle) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: employeePhone, testTitle'
        });
      }

      const title = 'Новый тест назначен';
      let body = testTitle;
      if (deadline) body += ` (до ${deadline})`;

      const pushData = {
        type: 'test_assigned',
        testId: testId || '',
      };

      const sent = await sendPushToPhone(employeePhone, title, body, pushData);

      console.log(`Push о тесте → ${employeePhone}: ${sent ? 'отправлен' : 'не отправлен'}`);

      res.json({ success: true, sent });
    } catch (e) {
      console.error('Error sending test assigned push:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/push/schedule-updated - Отправить push об изменении графика
  app.post('/api/push/schedule-updated', requireAuth, async (req, res) => {
    try {
      const {
        employeePhone,   // Телефон сотрудника
        month,           // Месяц (YYYY-MM)
        shopName,        // Название магазина
        changes,         // Описание изменений (опционально)
      } = req.body;

      if (!employeePhone) {
        return res.status(400).json({
          success: false,
          error: 'Missing required field: employeePhone'
        });
      }

      const title = 'График работы обновлён';
      let body = shopName || 'Проверьте ваш график';
      if (month) body = `${month}: ${body}`;
      if (changes) body = changes;

      const pushData = {
        type: 'schedule_updated',
        month: month || '',
      };

      const sent = await sendPushToPhone(employeePhone, title, body, pushData);

      console.log(`Push о графике → ${employeePhone}: ${sent ? 'отправлен' : 'не отправлен'}`);

      res.json({ success: true, sent });
    } catch (e) {
      console.error('Error sending schedule push:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  console.log('Report Notifications API setup complete');
}

module.exports = { setupReportNotificationsAPI, sendPushNotification, sendPushToPhone };

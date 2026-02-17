/**
 * Shifts API - Shift Reports and Shift Handover Reports
 * Пересменка + Сдача смены
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 * REFACTORED: Added PostgreSQL support for shift_handover_reports (2026-02-17)
 * REFACTORED: Added PostgreSQL support for shift_reports (2026-02-17)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, sanitizeId } = require('../utils/file_helpers');
const { getMoscowTime } = require('../utils/moscow_time');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const { withLock } = require('../utils/file_lock');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');

const USE_DB_HANDOVER = process.env.USE_DB_SHIFT_HANDOVER === 'true';
const USE_DB_SHIFTS = process.env.USE_DB_SHIFTS === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SHIFT_REPORTS_DIR = `${DATA_DIR}/shift-reports`;
const SHIFT_HANDOVER_REPORTS_DIR = `${DATA_DIR}/shift-handover-reports`;

// Firebase Admin SDK
let admin = null;
try {
  const firebaseConfig = require('../firebase-admin-config');
  admin = firebaseConfig.admin;
} catch (e) {
  console.warn('⚠️ Shifts API: Firebase not available, push notifications disabled');
}

// Создаем директории, если их нет
(async () => {
  if (!await fileExists(SHIFT_REPORTS_DIR)) {
    await fsp.mkdir(SHIFT_REPORTS_DIR, { recursive: true });
  }
  if (!await fileExists(SHIFT_HANDOVER_REPORTS_DIR)) {
    await fsp.mkdir(SHIFT_HANDOVER_REPORTS_DIR, { recursive: true });
  }
})();

// Helper function to send push notification when shift report is confirmed
async function sendShiftConfirmationNotification(employeeIdentifier, rating) {
  try {
    console.log(`[ShiftNotification] Поиск сотрудника: ${employeeIdentifier}`);

    // Find employee in individual files (employee_*.json)
    const employeesDir = `${DATA_DIR}/employees`;
    if (!await fileExists(employeesDir)) {
      console.log('[ShiftNotification] Директория сотрудников не найдена');
      return;
    }

    const files = (await fsp.readdir(employeesDir)).filter(f => f.startsWith('employee_') && f.endsWith('.json'));
    let foundEmployee = null;

    for (const file of files) {
      try {
        const filePath = path.join(employeesDir, file);
        const employee = JSON.parse(await fsp.readFile(filePath, 'utf8'));

        if (employee.id === employeeIdentifier ||
            employee.name === employeeIdentifier ||
            employee.phone === employeeIdentifier) {
          foundEmployee = employee;
          break;
        }
      } catch (e) {
        // Skip invalid files
      }
    }

    if (!foundEmployee) {
      console.log(`[ShiftNotification] Сотрудник ${employeeIdentifier} не найден`);
      return;
    }

    if (!foundEmployee.phone) {
      console.log(`[ShiftNotification] У сотрудника ${foundEmployee.name} нет телефона`);
      return;
    }

    // Get FCM token from /var/www/fcm-tokens/{phone}.json
    const normalizedPhone = foundEmployee.phone.replace(/[^\d]/g, '');
    const tokenFile = path.join(`${DATA_DIR}/fcm-tokens`, `${normalizedPhone}.json`);

    if (!await fileExists(tokenFile)) {
      console.log(`[ShiftNotification] FCM токен не найден для телефона ${normalizedPhone}`);
      return;
    }

    const tokenData = JSON.parse(await fsp.readFile(tokenFile, 'utf8'));
    const fcmToken = tokenData.token;

    if (!fcmToken) {
      console.log(`[ShiftNotification] Пустой FCM токен для ${normalizedPhone}`);
      return;
    }

    // Send via Firebase
    const message = {
      notification: {
        title: 'Пересменка оценена',
        body: `Ваш отчёт оценён на ${rating} баллов`
      },
      token: fcmToken
    };

    if (admin && admin.messaging) {
      await admin.messaging().send(message);
      console.log(`[ShiftNotification] ✅ Push отправлен ${foundEmployee.name} (${normalizedPhone}): оценка ${rating}`);
    } else {
      console.log('[ShiftNotification] Firebase Admin не инициализирован');
    }
  } catch (error) {
    console.error('[ShiftNotification] Ошибка отправки push:', error.message);
  }
}

// ==================== DB CONVERSION (shift_reports) ====================

function dbShiftReportToCamel(row) {
  return {
    id: row.id,
    employeeName: row.employee_name,
    employeeId: row.employee_id,
    employeePhone: row.employee_phone,
    shopAddress: row.shop_address,
    shopName: row.shop_name,
    shiftType: row.shift_type,
    status: row.status,
    answers: typeof row.answers === 'string' ? JSON.parse(row.answers) : (row.answers || []),
    rating: row.rating,
    date: row.date,
    createdAt: row.created_at,
    submittedAt: row.submitted_at,
    deadline: row.deadline,
    reviewDeadline: row.review_deadline,
    confirmedAt: row.confirmed_at,
    confirmedByAdmin: row.confirmed_by_admin,
    failedAt: row.failed_at,
    rejectedAt: row.rejected_at,
    expiredAt: row.expired_at,
    completedBy: row.completed_by,
    isSynced: row.is_synced,
    savedAt: row.saved_at,
    updatedAt: row.updated_at,
  };
}

function camelToDbShift(body) {
  const data = {};
  if (body.id !== undefined) data.id = body.id;
  if (body.employeeName !== undefined) data.employee_name = body.employeeName;
  if (body.employeeId !== undefined) data.employee_id = body.employeeId;
  if (body.employeePhone !== undefined) data.employee_phone = body.employeePhone;
  if (body.phone !== undefined && !data.employee_phone) data.employee_phone = body.phone;
  if (body.shopAddress !== undefined) data.shop_address = body.shopAddress;
  if (body.shopName !== undefined) data.shop_name = body.shopName;
  if (body.shiftType !== undefined) data.shift_type = body.shiftType;
  if (body.status !== undefined) data.status = body.status;
  if (body.answers !== undefined) data.answers = JSON.stringify(body.answers);
  if (body.rating != null) data.rating = body.rating;
  if (body.date !== undefined) data.date = body.date;
  if (body.createdAt !== undefined) data.created_at = body.createdAt;
  if (body.timestamp !== undefined && !data.created_at) data.created_at = body.timestamp;
  if (body.submittedAt !== undefined) data.submitted_at = body.submittedAt;
  if (body.deadline !== undefined) data.deadline = body.deadline;
  if (body.reviewDeadline !== undefined) data.review_deadline = body.reviewDeadline;
  if (body.confirmedAt !== undefined) data.confirmed_at = body.confirmedAt;
  if (body.confirmedByAdmin !== undefined) data.confirmed_by_admin = body.confirmedByAdmin;
  if (body.failedAt !== undefined) data.failed_at = body.failedAt;
  if (body.rejectedAt !== undefined) data.rejected_at = body.rejectedAt;
  if (body.expiredAt !== undefined) data.expired_at = body.expiredAt;
  if (body.isSynced !== undefined) data.is_synced = body.isSynced;
  if (body.savedAt !== undefined) data.saved_at = body.savedAt;
  return data;
}

// ==================== DB CONVERSION (shift_handover_reports) ====================

function dbHandoverReportToCamel(row) {
  return {
    id: row.id,
    employeeName: row.employee_name,
    employeePhone: row.employee_phone,
    shopAddress: row.shop_address,
    shopName: row.shop_name,
    shiftType: row.shift_type,
    status: row.status,
    answers: typeof row.answers === 'string' ? JSON.parse(row.answers) : (row.answers || []),
    rating: row.rating,
    date: row.date,
    createdAt: row.created_at,
    submittedAt: row.submitted_at,
    reviewDeadline: row.review_deadline,
    confirmedAt: row.confirmed_at,
    confirmedByAdmin: row.confirmed_by_admin,
    failedAt: row.failed_at,
    rejectedAt: row.rejected_at,
    expiredAt: row.expired_at,
    completedBy: row.completed_by,
    aiVerificationSkipped: row.ai_verification_skipped,
    isSynced: row.is_synced,
    updatedAt: row.updated_at,
  };
}

function camelToDbHandover(body) {
  const data = {};
  if (body.id !== undefined) data.id = body.id;
  if (body.employeeName !== undefined) data.employee_name = body.employeeName;
  if (body.employeePhone !== undefined) data.employee_phone = body.employeePhone;
  if (body.shopAddress !== undefined) data.shop_address = body.shopAddress;
  if (body.shopName !== undefined) data.shop_name = body.shopName;
  if (body.shiftType !== undefined) data.shift_type = body.shiftType;
  if (body.status !== undefined) data.status = body.status;
  if (body.answers !== undefined) data.answers = JSON.stringify(body.answers);
  if (body.rating != null) data.rating = body.rating;
  if (body.date !== undefined) data.date = body.date;
  if (body.createdAt !== undefined) data.created_at = body.createdAt;
  if (body.confirmedAt !== undefined) data.confirmed_at = body.confirmedAt;
  if (body.confirmedByAdmin !== undefined) data.confirmed_by_admin = body.confirmedByAdmin;
  if (body.failedAt !== undefined) data.failed_at = body.failedAt;
  if (body.rejectedAt !== undefined) data.rejected_at = body.rejectedAt;
  if (body.expiredAt !== undefined) data.expired_at = body.expiredAt;
  if (body.completedBy !== undefined) data.completed_by = body.completedBy;
  if (body.aiVerificationSkipped !== undefined) data.ai_verification_skipped = body.aiVerificationSkipped;
  if (body.isSynced !== undefined) data.is_synced = body.isSynced;
  if (body.updatedAt !== undefined) data.updated_at = body.updatedAt;
  return data;
}

// ====================================================================================

function setupShiftsAPI(app, { sendPushToPhone, markShiftHandoverPendingCompleted, sendShiftHandoverNewReportNotification, getPendingShiftHandoverReports, getFailedShiftHandoverReports, calculateShiftPoints } = {}) {

  // ========== SHIFT REPORTS (Пересменка) ==========

  app.get('/api/shift-reports', async (req, res) => {
    try {
      const { employeeName, shopAddress, date, status, shiftType } = req.query;

      if (USE_DB_SHIFTS) {
        try {
          let sql = 'SELECT * FROM shift_reports WHERE 1=1';
          const params = [];
          let paramIdx = 1;

          if (employeeName) {
            sql += ` AND employee_name = $${paramIdx++}`;
            params.push(employeeName);
          }
          if (shopAddress) {
            sql += ` AND shop_address = $${paramIdx++}`;
            params.push(shopAddress);
          }
          if (date) {
            sql += ` AND (date = $${paramIdx} OR created_at::date = $${paramIdx}::date)`;
            params.push(date);
            paramIdx++;
          }
          if (status) {
            sql += ` AND status = $${paramIdx++}`;
            params.push(status);
          }
          if (shiftType) {
            sql += ` AND shift_type = $${paramIdx++}`;
            params.push(shiftType);
          }

          sql += ' ORDER BY created_at DESC';

          const result = await db.query(sql, params);
          const reports = result.rows.map(dbShiftReportToCamel);

          if (isPaginationRequested(req.query)) {
            return res.json(createPaginatedResponse(reports, req.query, 'reports'));
          }
          return res.json({ success: true, reports });
        } catch (dbErr) {
          console.error('[Shifts] DB read error, falling back to files:', dbErr.message);
        }
      }

      const reports = [];

      // Читаем из daily-файлов (формат scheduler'а: YYYY-MM-DD.json)
      if (await fileExists(SHIFT_REPORTS_DIR)) {
        let files = (await fsp.readdir(SHIFT_REPORTS_DIR)).filter(f => f.endsWith('.json'));

        // Оптимизация: если указана дата, читаем только соответствующий daily-файл
        if (date) {
          const targetFile = `${date}.json`;
          files = files.filter(f => f === targetFile || !(/^\d{4}-\d{2}-\d{2}\.json$/.test(f)));
        }

        for (const file of files) {
          try {
            const filePath = path.join(SHIFT_REPORTS_DIR, file);
            const content = await fsp.readFile(filePath, 'utf8');
            const data = JSON.parse(content);

            // Проверяем формат файла: daily (массив) или individual (объект)
            if (Array.isArray(data)) {
              // Daily файл: YYYY-MM-DD.json содержит массив отчётов
              const fileDate = file.replace('.json', ''); // YYYY-MM-DD

              for (const report of data) {
                // Фильтрация
                if (employeeName && report.employeeName !== employeeName) continue;
                if (shopAddress && report.shopAddress !== shopAddress) continue;
                if (date && !report.createdAt?.startsWith(date) && fileDate !== date) continue;
                if (status && report.status !== status) continue;
                if (shiftType && report.shiftType !== shiftType) continue;

                reports.push(report);
              }
            } else if (data.id) {
              // Individual файл (старый формат): report_id.json содержит один отчёт
              const report = data;
              if (employeeName && report.employeeName !== employeeName) continue;
              if (shopAddress && report.shopAddress !== shopAddress) continue;
              if (date && !report.timestamp?.startsWith(date) && !report.createdAt?.startsWith(date)) continue;
              if (status && report.status !== status) continue;
              if (shiftType && report.shiftType !== shiftType) continue;

              reports.push(report);
            }
          } catch (e) {
            console.error(`Ошибка чтения ${file}:`, e);
          }
        }
      }

      // Сортируем по дате создания (новые первыми)
      reports.sort((a, b) => {
        const dateA = new Date(a.createdAt || a.timestamp || 0);
        const dateB = new Date(b.createdAt || b.timestamp || 0);
        return dateB - dateA;
      });

      if (isPaginationRequested(req.query)) {
        res.json(createPaginatedResponse(reports, req.query, 'reports'));
      } else {
        res.json({ success: true, reports });
      }
    } catch (error) {
      console.error('Ошибка получения отчетов пересменки:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/shift-reports', async (req, res) => {
    try {
      const { getShiftSettings, loadTodayReports, saveTodayReports } = require('./shift_automation_scheduler');
      const settings = await getShiftSettings();
      const now = new Date();
      const today = now.toISOString().split('T')[0];
      const shiftType = req.body.shiftType;
      const shopAddress = req.body.shopAddress;

      // Функция для парсинга времени
      function parseTime(timeStr) {
        const [hours, minutes] = timeStr.split(':').map(Number);
        return { hours, minutes };
      }

      // Функция для проверки активного интервала
      function isWithinInterval(shiftType) {
        // Boy Scout: getMoscowTime вместо ручного UTC+3
        const moscowNow = getMoscowTime();
        const currentHour = moscowNow.getUTCHours();
        const currentMinute = moscowNow.getUTCMinutes();
        const currentMinutes = currentHour * 60 + currentMinute;

        if (shiftType === 'morning') {
          const start = parseTime(settings.morningStartTime);
          const end = parseTime(settings.morningEndTime);
          const startMinutes = start.hours * 60 + start.minutes;
          const endMinutes = end.hours * 60 + end.minutes;
          return currentMinutes >= startMinutes && currentMinutes < endMinutes;
        } else if (shiftType === 'evening') {
          const start = parseTime(settings.eveningStartTime);
          const end = parseTime(settings.eveningEndTime);
          const startMinutes = start.hours * 60 + start.minutes;
          const endMinutes = end.hours * 60 + end.minutes;
          return currentMinutes >= startMinutes && currentMinutes < endMinutes;
        }
        return false;
      }

      // Валидация времени - проверяем активен ли интервал
      if (shiftType && !isWithinInterval(shiftType)) {
        console.log(`[ShiftReports] TIME_EXPIRED: ${shiftType} интервал не активен для ${shopAddress}`);
        return res.status(400).json({
          success: false,
          error: 'TIME_EXPIRED',
          message: 'К сожалению вы не успели пройти пересменку вовремя'
        });
      }

      // Загружаем и обновляем отчёты под блокировкой файла (защита от гонки)
      const todayFile = path.join(SHIFT_REPORTS_DIR, `${today}.json`);
      const updatedReport = await withLock(todayFile, async () => {
        let reports = await loadTodayReports();

        // Ищем pending отчёт для этого магазина и типа смены
        const pendingIndex = reports.findIndex(r =>
          r.shopAddress === shopAddress &&
          r.shiftType === shiftType &&
          r.status === 'pending'
        );

        let result;

        if (pendingIndex !== -1) {
          // Обновляем существующий pending отчёт
          const reviewDeadline = new Date(now.getTime() + settings.adminReviewTimeout * 60 * 60 * 1000);

          reports[pendingIndex] = {
            ...reports[pendingIndex],
            employeeName: req.body.employeeName,
            employeeId: req.body.employeeId,
            answers: req.body.answers || [],
            status: 'review',
            submittedAt: now.toISOString(),
            reviewDeadline: reviewDeadline.toISOString(),
            timestamp: req.body.timestamp || now.toISOString(),
            ...(req.body.shortages !== undefined && { shortages: req.body.shortages }),
            ...(req.body.aiVerificationPassed !== undefined && { aiVerificationPassed: req.body.aiVerificationPassed }),
          };
          result = reports[pendingIndex];
          await saveTodayReports(reports);

          // DB dual-write
          if (USE_DB_SHIFTS) {
            try {
              const dbData = camelToDbShift(result);
              dbData.updated_at = new Date().toISOString();
              await db.upsert('shift_reports', dbData);
              console.log(`[ShiftReports] DB upsert: ${result.id}`);
            } catch (dbErr) {
              console.error('[ShiftReports] DB write error:', dbErr.message);
            }
          }

          console.log(`[ShiftReports] Pending отчёт обновлён до review: ${result.id}`);
        } else {
          // Нет pending отчёта - создаём новый (для обратной совместимости)
          const report = {
            id: req.body.id || `shift_report_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
            employeeName: req.body.employeeName,
            employeeId: req.body.employeeId,
            shopAddress: shopAddress,
            shopName: req.body.shopName,
            timestamp: req.body.timestamp || now.toISOString(),
            createdAt: now.toISOString(),
            answers: req.body.answers || [],
            status: 'review',
            shiftType: shiftType,
            submittedAt: now.toISOString(),
            reviewDeadline: new Date(now.getTime() + settings.adminReviewTimeout * 60 * 60 * 1000).toISOString(),
            ...(req.body.shortages !== undefined && { shortages: req.body.shortages }),
            ...(req.body.aiVerificationPassed !== undefined && { aiVerificationPassed: req.body.aiVerificationPassed }),
          };
          reports.push(report);
          await saveTodayReports(reports);
          result = report;

          // DB dual-write
          if (USE_DB_SHIFTS) {
            try {
              const dbData = camelToDbShift(result);
              dbData.updated_at = new Date().toISOString();
              await db.upsert('shift_reports', dbData);
              console.log(`[ShiftReports] DB upsert (new): ${result.id}`);
            } catch (dbErr) {
              console.error('[ShiftReports] DB write error:', dbErr.message);
            }
          }

          console.log(`[ShiftReports] Новый отчёт создан (без pending): ${report.id}`);
        }

        return result;
      });

      res.json({ success: true, report: updatedReport });
    } catch (error) {
      console.error('Ошибка сохранения отчета пересменки:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET - Get single shift report by ID
  app.get('/api/shift-reports/:id', async (req, res) => {
    try {
      const reportId = decodeURIComponent(req.params.id);
      let report = null;

      // DB lookup
      if (USE_DB_SHIFTS) {
        try {
          const row = await db.findById('shift_reports', reportId);
          if (row) report = dbShiftReportToCamel(row);
        } catch (dbErr) {
          console.error('[Shifts] DB read error (by id), falling back to files:', dbErr.message);
        }
      }

      // 1. Ищем в daily-файлах (формат scheduler'а: YYYY-MM-DD.json)
      if (!report && await fileExists(SHIFT_REPORTS_DIR)) {
        const files = (await fsp.readdir(SHIFT_REPORTS_DIR)).filter(f => /^\d{4}-\d{2}-\d{2}\.json$/.test(f));
        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(SHIFT_REPORTS_DIR, file), 'utf8');
            const reports = JSON.parse(content);
            if (Array.isArray(reports)) {
              const found = reports.find(r => r.id === reportId);
              if (found) { report = found; break; }
            }
          } catch (e) {
            console.error(`[Shifts] Error reading daily file ${file}:`, e.message);
          }
        }
      }

      // 2. Если не нашли в daily — ищем в individual файлах
      if (!report) {
        const reportFile = path.join(SHIFT_REPORTS_DIR, `${sanitizeId(reportId)}.json`);
        if (await fileExists(reportFile)) {
          const content = await fsp.readFile(reportFile, 'utf8');
          const data = JSON.parse(content);
          if (data && data.id) report = data;
        }
      }

      if (!report) {
        return res.status(404).json({ success: false, error: 'Отчёт не найден' });
      }

      // IDOR: проверка владельца или админ
      const ownerPhone = report.employeePhone || report.phone;
      if (ownerPhone && req.user && req.user.phone !== ownerPhone && !req.user.isAdmin) {
        return res.status(403).json({ success: false, error: 'Доступ запрещён' });
      }

      res.json({ success: true, report });
    } catch (error) {
      console.error('Ошибка получения отчета пересменки:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT - Update shift report (confirm/rate)
  app.put('/api/shift-reports/:id', async (req, res) => {
    try {
      const reportId = decodeURIComponent(req.params.id);
      let existingReport = null;
      let reportSource = null; // 'daily' or 'individual'
      let dailyFilePath = null;
      let dailyReports = null;
      let reportIndex = -1;

      // 1. Сначала ищем в daily-файлах (формат scheduler'а)
      if (await fileExists(SHIFT_REPORTS_DIR)) {
        const files = (await fsp.readdir(SHIFT_REPORTS_DIR)).filter(f => /^\d{4}-\d{2}-\d{2}\.json$/.test(f));

        for (const file of files) {
          const filePath = path.join(SHIFT_REPORTS_DIR, file);
          try {
            const content = await fsp.readFile(filePath, 'utf8');
            const reports = JSON.parse(content);
            if (Array.isArray(reports)) {
              const idx = reports.findIndex(r => r.id === reportId);
              if (idx !== -1) {
                existingReport = reports[idx];
                reportSource = 'daily';
                dailyFilePath = filePath;
                dailyReports = reports;
                reportIndex = idx;
                break;
              }
            }
          } catch (e) {
            console.error(`[Shifts] Error reading daily file ${file} for update:`, e.message);
          }
        }
      }

      // 2. Если не нашли в daily - ищем в individual файлах (старый формат)
      if (!existingReport) {
        const reportFile = path.join(SHIFT_REPORTS_DIR, `${reportId}.json`);
        if (await fileExists(reportFile)) {
          existingReport = JSON.parse(await fsp.readFile(reportFile, 'utf8'));
          reportSource = 'individual';
        }
      }

      if (!existingReport) {
        return res.status(404).json({ success: false, error: 'Отчет не найден' });
      }

      // IDOR: проверка — владелец может обновить свой отчёт, подтверждение/оценка — только админ
      const reportOwnerPhone = existingReport.employeePhone || existingReport.phone;
      if (req.body.rating !== undefined || req.body.confirmedAt) {
        // Подтверждение/оценка — только админ
        if (!req.user || !req.user.isAdmin) {
          return res.status(403).json({ success: false, error: 'Только администратор может подтвердить/оценить отчёт' });
        }
      } else if (reportOwnerPhone && req.user && req.user.phone !== reportOwnerPhone && !req.user.isAdmin) {
        return res.status(403).json({ success: false, error: 'Доступ запрещён' });
      }

      const updatedReport = { ...existingReport, ...req.body };

      // If rating is provided and confirmedAt is set, mark as confirmed
      if (req.body.rating !== undefined && req.body.confirmedAt) {
        updatedReport.status = 'confirmed';
        const rating = req.body.rating;

        // Начисление баллов эффективности
        try {
          // Загружаем настройки баллов пересменки
          const settingsFile = `${DATA_DIR}/points-settings/shift_points_settings.json`;
          let settings = {
            minPoints: -3,
            zeroThreshold: 7,
            maxPoints: 1,
            minRating: 1,
            maxRating: 10
          };
          if (await fileExists(settingsFile)) {
            const settingsContent = await fsp.readFile(settingsFile, 'utf8');
            settings = { ...settings, ...JSON.parse(settingsContent) };
          }

          // Рассчитываем баллы эффективности
          const efficiencyPoints = calculateShiftPoints ? calculateShiftPoints(rating, settings) : 0;
          console.log(`📊 Пересменка: баллы эффективности: ${efficiencyPoints} (оценка: ${rating})`);

          // Сохраняем баллы в efficiency-penalties
          const now = new Date();
          const monthKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
          const today = now.toISOString().split('T')[0];
          const efficiencyDir = `${DATA_DIR}/efficiency-penalties`;

          if (!await fileExists(efficiencyDir)) {
            await fsp.mkdir(efficiencyDir, { recursive: true });
          }

          const penaltiesFile = path.join(efficiencyDir, `${monthKey}.json`);
          const sourceId = `shift_rating_${reportId}`;

          // Записываем баллы под блокировкой файла
          await withLock(penaltiesFile, async () => {
            let penalties = [];
            if (await fileExists(penaltiesFile)) {
              penalties = JSON.parse(await fsp.readFile(penaltiesFile, 'utf8'));
            }

            // Проверяем дубликат
            const exists = penalties.some(p => p.sourceId === sourceId);
            if (!exists) {
              const employeePhone = existingReport.employeePhone || existingReport.phone;
              const penalty = {
                id: `ep_${Date.now()}`,
                type: 'employee',
                entityId: employeePhone || existingReport.employeeId,
                entityName: existingReport.employeeName,
                shopAddress: existingReport.shopAddress || null,
                employeeId: employeePhone || existingReport.employeeId,
                employeeName: existingReport.employeeName,
                category: 'shift',
                categoryName: 'Пересменка',
                date: today,
                points: Math.round(efficiencyPoints * 100) / 100,
                reason: `Оценка пересменки: ${rating}/10`,
                sourceId: sourceId,
                sourceType: 'shift_report',
                createdAt: now.toISOString()
              };

              penalties.push(penalty);
              await writeJsonFile(penaltiesFile, penalties);
              console.log(`✅ Баллы эффективности (пересменка) сохранены: ${efficiencyPoints} для ${existingReport.employeeName}`);
            }
          });
        } catch (effError) {
          console.error('⚠️ Ошибка начисления баллов эффективности:', effError.message);
        }

        // Send push notification to employee
        if (existingReport.employeeId || existingReport.employeeName) {
          try {
            const employeeIdentifier = existingReport.employeeId || existingReport.employeeName;
            await sendShiftConfirmationNotification(employeeIdentifier, rating);
          } catch (notifError) {
            console.error('Ошибка отправки уведомления сотруднику:', notifError);
          }
        }
      }

      updatedReport.updatedAt = new Date().toISOString();

      // DB dual-write
      if (USE_DB_SHIFTS) {
        try {
          const dbData = camelToDbShift(updatedReport);
          dbData.updated_at = updatedReport.updatedAt;
          await db.upsert('shift_reports', dbData);
          console.log(`[ShiftReports] DB upsert (update): ${reportId} → ${updatedReport.status}`);
        } catch (dbErr) {
          console.error('[ShiftReports] DB write error in PUT:', dbErr.message);
        }
      }

      // Сохраняем в соответствующий формат (под блокировкой для daily файлов)
      if (reportSource === 'daily' && dailyReports && reportIndex !== -1) {
        await withLock(dailyFilePath, async () => {
          // Перечитываем файл под блокировкой для актуальности
          const freshContent = await fsp.readFile(dailyFilePath, 'utf8');
          const freshReports = JSON.parse(freshContent);
          const freshIdx = freshReports.findIndex(r => r.id === reportId);
          if (freshIdx !== -1) {
            freshReports[freshIdx] = updatedReport;
          } else {
            freshReports.push(updatedReport);
          }
          await writeJsonFile(dailyFilePath, freshReports);
        });
      } else {
        const reportFile = path.join(SHIFT_REPORTS_DIR, `${reportId}.json`);
        await writeJsonFile(reportFile, updatedReport);
      }

      console.log(`Отчет пересменки обновлен: ${reportId}, статус: ${updatedReport.status}, оценка: ${updatedReport.rating}`);
      res.json({ success: true, report: updatedReport });
    } catch (error) {
      console.error('Ошибка обновления отчета пересменки:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ========== SHIFT HANDOVER REPORTS (Сдача смены) ==========

  // GET /api/shift-handover-reports - получить все отчеты сдачи смены
  app.get('/api/shift-handover-reports', async (req, res) => {
    try {
      console.log('GET /api/shift-handover-reports:', req.query);

      let reports;

      if (USE_DB_HANDOVER) {
        let query = 'SELECT * FROM shift_handover_reports WHERE 1=1';
        const params = [];
        let paramIdx = 1;

        if (req.query.employeeName) {
          query += ` AND employee_name = $${paramIdx++}`;
          params.push(req.query.employeeName);
        }
        if (req.query.shopAddress) {
          query += ` AND shop_address = $${paramIdx++}`;
          params.push(req.query.shopAddress);
        }
        if (req.query.date) {
          query += ` AND date = $${paramIdx++}`;
          params.push(req.query.date);
        }

        query += ' ORDER BY created_at DESC';

        const result = await db.query(query, params);
        reports = result.rows.map(dbHandoverReportToCamel);
      } else {
        reports = [];

        if (!await fileExists(SHIFT_HANDOVER_REPORTS_DIR)) {
          return res.json({ success: true, reports: [] });
        }

        const files = (await fsp.readdir(SHIFT_HANDOVER_REPORTS_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const filePath = path.join(SHIFT_HANDOVER_REPORTS_DIR, file);
            const content = await fsp.readFile(filePath, 'utf8');
            const report = JSON.parse(content);

            // Фильтрация по параметрам запроса
            let include = true;
            if (req.query.employeeName && report.employeeName !== req.query.employeeName) {
              include = false;
            }
            if (req.query.shopAddress && report.shopAddress !== req.query.shopAddress) {
              include = false;
            }
            if (req.query.date) {
              const reportDate = new Date(report.createdAt).toISOString().split('T')[0];
              if (reportDate !== req.query.date) {
                include = false;
              }
            }

            if (include) {
              reports.push(report);
            }
          } catch (e) {
            console.error(`Ошибка чтения файла ${file}:`, e);
          }
        }

        // Сортируем по дате (новые первыми)
        reports.sort((a, b) => {
          const dateA = new Date(a.createdAt || 0);
          const dateB = new Date(b.createdAt || 0);
          return dateB - dateA;
        });
      }

      res.json({ success: true, reports });
    } catch (error) {
      console.error('Ошибка получения отчетов сдачи смены:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/shift-handover-reports/:id - получить отчет по ID
  app.get('/api/shift-handover-reports/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('GET /api/shift-handover-reports/:id', id);

      let report;

      if (USE_DB_HANDOVER) {
        const row = await db.findById('shift_handover_reports', id);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Отчет не найден' });
        }
        report = dbHandoverReportToCamel(row);
      } else {
        const reportFile = path.join(SHIFT_HANDOVER_REPORTS_DIR, `${id}.json`);

        if (!await fileExists(reportFile)) {
          return res.status(404).json({ success: false, error: 'Отчет не найден' });
        }

        const content = await fsp.readFile(reportFile, 'utf8');
        report = JSON.parse(content);
      }

      res.json({ success: true, report });
    } catch (error) {
      console.error('Ошибка получения отчета сдачи смены:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/shift-handover-reports - создать отчет
  app.post('/api/shift-handover-reports', async (req, res) => {
    try {
      const report = req.body;
      console.log('POST /api/shift-handover-reports:', report.id);

      // Определяем тип смены по времени создания
      const createdAt = new Date(report.createdAt || Date.now());
      // UTC+3 (Moscow timezone)
      const createdHour = (createdAt.getUTCHours() + 3) % 24;
      const shiftType = createdHour >= 14 ? 'evening' : 'morning';

      if (USE_DB_HANDOVER) {
        const dbData = camelToDbHandover(report);
        dbData.id = report.id;
        dbData.date = report.date || (report.createdAt ? report.createdAt.split('T')[0] : new Date().toISOString().split('T')[0]);
        if (!dbData.shift_type) dbData.shift_type = shiftType;
        dbData.updated_at = new Date().toISOString();
        await db.upsert('shift_handover_reports', dbData);
      }

      // Dual-write: всегда сохраняем в файл (efficiency_penalties_api, execution_chain_api читают файлы)
      const safeId = sanitizeId(report.id);
      const reportFile = path.join(SHIFT_HANDOVER_REPORTS_DIR, `${safeId}.json`);
      await writeJsonFile(reportFile, report);

      // Отмечаем pending как выполненный
      if (markShiftHandoverPendingCompleted) {
        await markShiftHandoverPendingCompleted(report.shopAddress, shiftType, report.employeeName);
      }

      // Отправляем push-уведомление админу о новом отчёте
      if (sendShiftHandoverNewReportNotification) {
        await sendShiftHandoverNewReportNotification(report);
      }

      res.json({ success: true, message: 'Отчет сохранен' });
    } catch (error) {
      console.error('Ошибка сохранения отчета сдачи смены:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/shift-handover-reports/:id - обновить отчет (подтвердить/отклонить)
  app.put('/api/shift-handover-reports/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const updatedData = req.body;
      console.log('PUT /api/shift-handover-reports/:id', id, 'status:', updatedData.status);

      let existingReport;

      if (USE_DB_HANDOVER) {
        const row = await db.findById('shift_handover_reports', id);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Отчет не найден' });
        }
        existingReport = dbHandoverReportToCamel(row);
      } else {
        const reportFile = path.join(SHIFT_HANDOVER_REPORTS_DIR, `${id}.json`);

        if (!await fileExists(reportFile)) {
          return res.status(404).json({ success: false, error: 'Отчет не найден' });
        }

        existingReport = JSON.parse(await fsp.readFile(reportFile, 'utf8'));
      }

      const previousStatus = existingReport.status;

      // Объединяем данные
      const updatedReport = {
        ...existingReport,
        ...updatedData,
        updatedAt: new Date().toISOString()
      };

      if (USE_DB_HANDOVER) {
        const dbData = camelToDbHandover(updatedData);
        dbData.updated_at = new Date().toISOString();
        await db.updateById('shift_handover_reports', id, dbData);
      }

      // Dual-write: всегда сохраняем в файл
      const reportFile = path.join(SHIFT_HANDOVER_REPORTS_DIR, `${id}.json`);
      await writeJsonFile(reportFile, updatedReport);
      console.log('Отчет сдачи смены обновлен:', id, 'статус:', updatedReport.status);

      // Отправляем push-уведомление сотруднику при изменении статуса на approved/rejected
      if (previousStatus !== updatedReport.status &&
          (updatedReport.status === 'approved' || updatedReport.status === 'rejected')) {

        const employeePhone = updatedReport.employeePhone;
        if (employeePhone && sendPushToPhone) {
          try {
            const isApproved = updatedReport.status === 'approved';
            const title = isApproved ? 'Смена подтверждена' : 'Смена отклонена';
            const rating = updatedReport.rating || '';
            const body = isApproved
              ? `Ваша сдача смены подтверждена${rating ? ` с оценкой ${rating}/10` : ''}`
              : `Ваша сдача смены отклонена. Свяжитесь с администратором`;

            await sendPushToPhone(employeePhone, title, body, {
              type: 'shift_handover_status',
              status: updatedReport.status,
              rating: rating ? String(rating) : '',
              reportId: id
            });
            console.log(`[ShiftHandover] Push отправлен сотруднику ${employeePhone}: ${body}`);
          } catch (pushError) {
            console.error('[ShiftHandover] Ошибка отправки push:', pushError.message);
          }
        } else {
          console.log('[ShiftHandover] Push не отправлен: нет телефона или sendPushToPhone недоступен');
        }
      }

      res.json({ success: true, message: 'Отчет обновлен', report: updatedReport });
    } catch (error) {
      console.error('Ошибка обновления отчета сдачи смены:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/shift-handover-reports/:id - удалить отчет
  app.delete('/api/shift-handover-reports/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('DELETE /api/shift-handover-reports:', id);

      if (USE_DB_HANDOVER) {
        const row = await db.findById('shift_handover_reports', id);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Отчет не найден' });
        }
        await db.deleteById('shift_handover_reports', id);
      }

      // Dual-write: удаляем файл тоже
      const reportFile = path.join(SHIFT_HANDOVER_REPORTS_DIR, `${id}.json`);
      if (await fileExists(reportFile)) {
        await fsp.unlink(reportFile);
      } else if (!USE_DB_HANDOVER) {
        return res.status(404).json({ success: false, error: 'Отчет не найден' });
      }

      res.json({ success: true, message: 'Отчет успешно удален' });
    } catch (error) {
      console.error('Ошибка удаления отчета сдачи смены:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/shift-handover/pending - получить pending отчёты (не сданные смены)
  app.get('/api/shift-handover/pending', async (req, res) => {
    try {
      const pending = getPendingShiftHandoverReports ? await getPendingShiftHandoverReports() : [];
      console.log(`GET /api/shift-handover/pending: found ${pending.length} pending`);
      res.json({
        success: true,
        items: pending,
        count: pending.length
      });
    } catch (error) {
      console.error('Error getting pending shift handover reports:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/shift-handover/failed - получить failed отчёты (не в срок)
  app.get('/api/shift-handover/failed', async (req, res) => {
    try {
      const failed = getFailedShiftHandoverReports ? await getFailedShiftHandoverReports() : [];
      console.log(`GET /api/shift-handover/failed: found ${failed.length} failed`);
      res.json({
        success: true,
        items: failed,
        count: failed.length
      });
    } catch (error) {
      console.error('Error getting failed shift handover reports:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Shifts API initialized (shifts: ${USE_DB_SHIFTS ? 'PostgreSQL' : 'JSON files'}, handover: ${USE_DB_HANDOVER ? 'PostgreSQL' : 'JSON files'})`);
}

module.exports = { setupShiftsAPI };

/**
 * Shifts API - Shift Reports and Shift Handover Reports
 * Пересменка + Сдача смены
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, sanitizeId } = require('../utils/file_helpers');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');

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
    const normalizedPhone = foundEmployee.phone.replace(/[\s+]/g, '');
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

function setupShiftsAPI(app, { sendPushToPhone, markShiftHandoverPendingCompleted, sendShiftHandoverNewReportNotification, getPendingShiftHandoverReports, getFailedShiftHandoverReports, calculateShiftPoints } = {}) {

  // ========== SHIFT REPORTS (Пересменка) ==========

  app.get('/api/shift-reports', async (req, res) => {
    try {
      const { employeeName, shopAddress, date, status, shiftType } = req.query;
      const reports = [];

      // Читаем из daily-файлов (формат scheduler'а: YYYY-MM-DD.json)
      if (await fileExists(SHIFT_REPORTS_DIR)) {
        const files = (await fsp.readdir(SHIFT_REPORTS_DIR)).filter(f => f.endsWith('.json'));

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
      const settings = getShiftSettings();
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
        const currentHour = now.getHours();
        const currentMinute = now.getMinutes();
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

      // Загружаем отчёты из daily-файла scheduler'а
      let reports = loadTodayReports();

      // Ищем pending отчёт для этого магазина и типа смены
      const pendingIndex = reports.findIndex(r =>
        r.shopAddress === shopAddress &&
        r.shiftType === shiftType &&
        r.status === 'pending'
      );

      let updatedReport;

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
        updatedReport = reports[pendingIndex];
        saveTodayReports(reports);
        console.log(`[ShiftReports] Pending отчёт обновлён до review: ${updatedReport.id}`);
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
        saveTodayReports(reports);
        updatedReport = report;
        console.log(`[ShiftReports] Новый отчёт создан (без pending): ${report.id}`);
      }

      res.json({ success: true, report: updatedReport });
    } catch (error) {
      console.error('Ошибка сохранения отчета пересменки:', error);
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
          } catch (e) {}
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
          let penalties = [];
          if (await fileExists(penaltiesFile)) {
            penalties = JSON.parse(await fsp.readFile(penaltiesFile, 'utf8'));
          }

          // Проверяем дубликат
          const sourceId = `shift_rating_${reportId}`;
          const exists = penalties.some(p => p.sourceId === sourceId);
          if (!exists) {
            const employeePhone = existingReport.employeePhone || existingReport.phone;
            const penalty = {
              id: `ep_${Date.now()}`,
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
            await fsp.writeFile(penaltiesFile, JSON.stringify(penalties, null, 2), 'utf8');
            console.log(`✅ Баллы эффективности (пересменка) сохранены: ${efficiencyPoints} для ${existingReport.employeeName}`);
          }
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

      // Сохраняем в соответствующий формат
      if (reportSource === 'daily' && dailyReports && reportIndex !== -1) {
        dailyReports[reportIndex] = updatedReport;
        await fsp.writeFile(dailyFilePath, JSON.stringify(dailyReports, null, 2), 'utf8');
      } else {
        const reportFile = path.join(SHIFT_REPORTS_DIR, `${reportId}.json`);
        await fsp.writeFile(reportFile, JSON.stringify(updatedReport, null, 2), 'utf8');
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

      const reports = [];

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

      const reportFile = path.join(SHIFT_HANDOVER_REPORTS_DIR, `${id}.json`);

      if (!await fileExists(reportFile)) {
        return res.status(404).json({
          success: false,
          error: 'Отчет не найден'
        });
      }

      const content = await fsp.readFile(reportFile, 'utf8');
      const report = JSON.parse(content);

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

      const reportFile = path.join(SHIFT_HANDOVER_REPORTS_DIR, `${report.id}.json`);
      await fsp.writeFile(reportFile, JSON.stringify(report, null, 2), 'utf8');

      // Определяем тип смены по времени создания
      const createdAt = new Date(report.createdAt || Date.now());
      const createdHour = createdAt.getHours();
      const shiftType = createdHour >= 14 ? 'evening' : 'morning';

      // Отмечаем pending как выполненный
      if (markShiftHandoverPendingCompleted) {
        markShiftHandoverPendingCompleted(report.shopAddress, shiftType, report.employeeName);
      }

      // Отправляем push-уведомление админу о новом отчёте
      if (sendShiftHandoverNewReportNotification) {
        sendShiftHandoverNewReportNotification(report);
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

      const reportFile = path.join(SHIFT_HANDOVER_REPORTS_DIR, `${id}.json`);

      if (!await fileExists(reportFile)) {
        return res.status(404).json({
          success: false,
          error: 'Отчет не найден'
        });
      }

      // Загружаем существующий отчёт
      const existingData = await fsp.readFile(reportFile, 'utf8');
      const existingReport = JSON.parse(existingData);
      const previousStatus = existingReport.status;

      // Объединяем данные
      const updatedReport = {
        ...existingReport,
        ...updatedData,
        updatedAt: new Date().toISOString()
      };

      // Сохраняем обновлённый отчёт
      await fsp.writeFile(reportFile, JSON.stringify(updatedReport, null, 2), 'utf8');
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

      const reportFile = path.join(SHIFT_HANDOVER_REPORTS_DIR, `${id}.json`);

      if (!await fileExists(reportFile)) {
        return res.status(404).json({
          success: false,
          error: 'Отчет не найден'
        });
      }

      await fsp.unlink(reportFile);

      res.json({ success: true, message: 'Отчет успешно удален' });
    } catch (error) {
      console.error('Ошибка удаления отчета сдачи смены:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/shift-handover/pending - получить pending отчёты (не сданные смены)
  app.get('/api/shift-handover/pending', async (req, res) => {
    try {
      const pending = getPendingShiftHandoverReports ? getPendingShiftHandoverReports() : [];
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
      const failed = getFailedShiftHandoverReports ? getFailedShiftHandoverReports() : [];
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

  console.log('✅ Shifts API initialized');
}

module.exports = { setupShiftsAPI };

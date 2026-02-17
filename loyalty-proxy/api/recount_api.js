/**
 * Recount API - Пересчёт товара
 * POST (с TIME_EXPIRED), GET, GET /expired, GET /pending, POST /rating, POST /notify
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 * REFACTORED: Added PostgreSQL support for recount_reports (2026-02-17)
 */

const fsp = require('fs').promises;
const path = require('path');
const fetch = require('node-fetch');
const { writeJsonFile } = require('../utils/async_fs');
const { fileExists } = require('../utils/file_helpers');
const { getMoscowTime } = require('../utils/moscow_time');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const db = require('../utils/db');
const { dbInsertPenalty } = require('./efficiency_penalties_api');

const USE_DB = process.env.USE_DB_RECOUNT === 'true';
const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SCRIPT_URL = process.env.SCRIPT_URL;

// ==================== DB CONVERSION ====================

function dbRecountToCamel(row) {
  return {
    id: row.id,
    employeeName: row.employee_name,
    employeePhone: row.employee_phone,
    employeeId: row.employee_id,
    shopAddress: row.shop_address,
    shopName: row.shop_name,
    shiftType: row.shift_type,
    status: row.status,
    answers: typeof row.answers === 'string' ? JSON.parse(row.answers) : (row.answers || []),
    adminRating: row.admin_rating,
    adminName: row.admin_name,
    ratedAt: row.rated_at,
    date: row.date,
    createdAt: row.created_at,
    deadline: row.deadline,
    submittedAt: row.submitted_at,
    reviewDeadline: row.review_deadline,
    failedAt: row.failed_at,
    rejectedAt: row.rejected_at,
    completedBy: row.completed_by,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    duration: row.duration,
    expiredAt: row.expired_at,
    photoVerifications: typeof row.photo_verifications === 'string'
      ? JSON.parse(row.photo_verifications)
      : (row.photo_verifications || []),
    savedAt: row.saved_at,
    updatedAt: row.updated_at,
  };
}

function camelToDbRecount(body) {
  const data = {};
  if (body.id !== undefined) data.id = body.id;
  if (body.employeeName !== undefined) data.employee_name = body.employeeName;
  if (body.employeePhone !== undefined) data.employee_phone = body.employeePhone;
  if (body.employeeId !== undefined) data.employee_id = body.employeeId;
  if (body.shopAddress !== undefined) data.shop_address = body.shopAddress;
  if (body.shopName !== undefined) data.shop_name = body.shopName;
  if (body.shiftType !== undefined) data.shift_type = body.shiftType;
  if (body.status !== undefined) data.status = body.status;
  if (body.answers !== undefined) data.answers = JSON.stringify(body.answers);
  if (body.adminRating != null) data.admin_rating = body.adminRating;
  if (body.adminName !== undefined) data.admin_name = body.adminName;
  if (body.ratedAt !== undefined) data.rated_at = body.ratedAt;
  if (body.date !== undefined) data.date = body.date;
  if (body.createdAt !== undefined) data.created_at = body.createdAt;
  if (body.deadline !== undefined) data.deadline = body.deadline;
  if (body.submittedAt !== undefined) data.submitted_at = body.submittedAt;
  if (body.reviewDeadline !== undefined) data.review_deadline = body.reviewDeadline;
  if (body.failedAt !== undefined) data.failed_at = body.failedAt;
  if (body.rejectedAt !== undefined) data.rejected_at = body.rejectedAt;
  if (body.completedBy !== undefined) data.completed_by = body.completedBy;
  if (body.startedAt !== undefined) data.started_at = body.startedAt;
  if (body.completedAt !== undefined) data.completed_at = body.completedAt;
  if (body.duration != null) data.duration = body.duration;
  if (body.expiredAt !== undefined) data.expired_at = body.expiredAt;
  if (body.photoVerifications !== undefined) data.photo_verifications = body.photoVerifications ? JSON.stringify(body.photoVerifications) : null;
  if (body.savedAt !== undefined) data.saved_at = body.savedAt;
  return data;
}

function setupRecountAPI(app, { sendPushToPhone, calculateRecountPoints } = {}) {

  // POST /api/recount-reports - создание отчета пересчета с TIME_EXPIRED валидацией
  app.post('/api/recount-reports', async (req, res) => {
    try {
      console.log('POST /api/recount-reports:', JSON.stringify(req.body).substring(0, 200));

      // ============================================
      // TIME_EXPIRED валидация (аналогично пересменкам)
      // ============================================
      const shiftType = req.body.shiftType; // 'morning' | 'evening'

      if (shiftType) {
        // Загружаем настройки пересчёта
        const settingsFile = `${DATA_DIR}/points-settings/recount_points_settings.json`;
        let recountSettings = {
          morningStartTime: '08:00',
          morningEndTime: '14:00',
          eveningStartTime: '14:00',
          eveningEndTime: '23:00'
        };

        if (await fileExists(settingsFile)) {
          try {
            const settingsData = JSON.parse(await fsp.readFile(settingsFile, 'utf8'));
            recountSettings = { ...recountSettings, ...settingsData };
          } catch (e) {
            console.log('Ошибка чтения настроек пересчёта, используем дефолтные');
          }
        }

        // Boy Scout: getMoscowTime вместо ручного UTC+3
        const moscowTime = getMoscowTime();
        const currentHours = moscowTime.getUTCHours();
        const currentMinutes = moscowTime.getUTCMinutes();
        const currentTimeMinutes = currentHours * 60 + currentMinutes;

        // Определяем дедлайн для текущей смены
        let deadlineTime;
        if (shiftType === 'morning') {
          deadlineTime = recountSettings.morningEndTime;
        } else {
          deadlineTime = recountSettings.eveningEndTime;
        }

        // Парсим время дедлайна
        const [deadlineHours, deadlineMinutes] = deadlineTime.split(':').map(Number);
        const deadlineTimeMinutes = deadlineHours * 60 + deadlineMinutes;

        // Проверяем, не просрочено ли время
        if (currentTimeMinutes > deadlineTimeMinutes) {
          console.log(`⏰ TIME_EXPIRED: Текущее время ${currentHours}:${currentMinutes}, дедлайн ${deadlineTime}`);
          return res.status(400).json({
            success: false,
            error: 'TIME_EXPIRED',
            message: 'К сожалению вы не успели пройти пересчёт вовремя'
          });
        }
      }

      // ============================================
      // Сохранение отчёта
      // ============================================
      const reportsDir = `${DATA_DIR}/recount-reports`;
      if (!await fileExists(reportsDir)) {
        await fsp.mkdir(reportsDir, { recursive: true });
      }

      const reportId = req.body.id || `report_${Date.now()}`;
      // Санитизируем имя файла: заменяем недопустимые символы на подчеркивания
      const sanitizedId = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const reportFile = path.join(reportsDir, `${sanitizedId}.json`);

      // Загружаем настройки для вычисления reviewDeadline
      let adminReviewTimeout = 2; // часы по умолчанию
      const settingsFile = `${DATA_DIR}/points-settings/recount_points_settings.json`;
      if (await fileExists(settingsFile)) {
        try {
          const settings = JSON.parse(await fsp.readFile(settingsFile, 'utf8'));
          adminReviewTimeout = settings.adminReviewTimeout || 2;
        } catch (e) {
          console.error('[Recount] Error reading points settings:', e.message);
        }
      }

      const now = new Date();
      const reviewDeadline = new Date(now.getTime() + adminReviewTimeout * 60 * 60 * 1000);

      // Сохраняем отчет с временной меткой и статусом
      const reportData = {
        ...req.body,
        status: 'review', // Отчёт сразу идёт на проверку
        createdAt: now.toISOString(),
        savedAt: now.toISOString(),
        submittedAt: now.toISOString(),
        reviewDeadline: reviewDeadline.toISOString()
      };

      // DB + dual-write
      if (USE_DB) {
        try {
          const dbData = camelToDbRecount(reportData);
          dbData.updated_at = now.toISOString();
          await db.upsert('recount_reports', dbData);
          console.log('✅ Отчет пересчёта сохранен в DB:', reportId);
        } catch (dbErr) {
          console.error('[Recount] DB write error:', dbErr.message);
        }
      }

      // Всегда пишем в файл (dual-write для внешних потребителей)
      try {
        await writeJsonFile(reportFile, reportData);
        console.log('✅ Отчет пересчёта сохранен:', reportFile);
      } catch (writeError) {
        console.error('Ошибка записи файла:', writeError);
        throw writeError;
      }

      // Обновляем/удаляем соответствующий pending отчёт (созданный scheduler)
      try {
        const shopAddress = req.body.shopAddress;
        const reportShiftType = req.body.shiftType;
        if (shopAddress) {
          const pendingFiles = (await fsp.readdir(reportsDir)).filter(f => f.startsWith('pending_recount_') && f.endsWith('.json'));
          for (const pf of pendingFiles) {
            try {
              const pfPath = path.join(reportsDir, pf);
              const pfContent = JSON.parse(await fsp.readFile(pfPath, 'utf8'));
              if (pfContent.status === 'pending' && pfContent.shopAddress === shopAddress &&
                  (!reportShiftType || pfContent.shiftType === reportShiftType)) {
                // Удаляем pending — он заменён реальным отчётом
                await fsp.unlink(pfPath);
                console.log(`🗑️ Pending отчёт удалён: ${pf}`);
                break;
              }
            } catch (e) {
              // Пропускаем ошибки чтения отдельных файлов
            }
          }
        }
      } catch (e) {
        console.log('[Recount] Ошибка обновления pending отчёта (некритично):', e.message);
      }

      // Пытаемся также отправить в Google Apps Script (опционально)
      try {
        const response = await fetch(SCRIPT_URL, {
          method: 'post',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'createRecountReport',
            ...req.body
          }),
        });

        const contentType = response.headers.get('content-type');
        if (contentType && contentType.includes('application/json')) {
          const data = await response.json();
          if (data.success) {
            console.log('Отчет также отправлен в Google Apps Script');
          }
        }
      } catch (scriptError) {
        console.log('Google Apps Script не поддерживает это действие, отчет сохранен локально');
      }

      res.json({
        success: true,
        message: 'Отчет успешно сохранен',
        reportId: reportId,
        report: reportData
      });
    } catch (error) {
      console.error('Ошибка создания отчета:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при сохранении отчета'
      });
    }
  });

  // GET /api/recount-reports - получить отчеты пересчета
  app.get('/api/recount-reports', async (req, res) => {
    try {
      console.log('GET /api/recount-reports:', req.query);

      if (USE_DB) {
        try {
          let sql = 'SELECT * FROM recount_reports WHERE 1=1';
          const params = [];
          let paramIdx = 1;

          if (req.query.shopAddress) {
            sql += ` AND shop_address ILIKE $${paramIdx++}`;
            params.push(`%${req.query.shopAddress}%`);
          }
          if (req.query.employeeName) {
            sql += ` AND employee_name ILIKE $${paramIdx++}`;
            params.push(`%${req.query.employeeName}%`);
          }
          if (req.query.date) {
            sql += ` AND created_at::date = $${paramIdx++}`;
            params.push(req.query.date);
          }

          sql += ' ORDER BY created_at DESC';

          const result = await db.query(sql, params);
          const reports = result.rows.map(dbRecountToCamel);

          if (isPaginationRequested(req.query)) {
            return res.json(createPaginatedResponse(reports, req.query, 'reports'));
          }
          return res.json({ success: true, reports });
        } catch (dbErr) {
          console.error('[Recount] DB read error, falling back to files:', dbErr.message);
        }
      }

      const reportsDir = `${DATA_DIR}/recount-reports`;
      const reports = [];

      // Читаем отчеты из локальной директории
      if (await fileExists(reportsDir)) {
        const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const filePath = path.join(reportsDir, file);
            const content = await fsp.readFile(filePath, 'utf8');
            const report = JSON.parse(content);
            reports.push(report);
          } catch (e) {
            console.error(`Ошибка чтения файла ${file}:`, e);
          }
        }

        // Сортируем по дате создания (новые первыми)
        reports.sort((a, b) => {
          const dateA = new Date(a.createdAt || a.savedAt || 0);
          const dateB = new Date(b.createdAt || b.savedAt || 0);
          return dateB - dateA;
        });

        // Применяем фильтры из query параметров
        let filteredReports = reports;
        if (req.query.shopAddress) {
          filteredReports = filteredReports.filter(r =>
            r.shopAddress && r.shopAddress.includes(req.query.shopAddress)
          );
        }
        if (req.query.employeeName) {
          filteredReports = filteredReports.filter(r =>
            r.employeeName && r.employeeName.includes(req.query.employeeName)
          );
        }
        if (req.query.date) {
          const filterDate = new Date(req.query.date);
          filteredReports = filteredReports.filter(r => {
            const reportDate = new Date(r.completedAt || r.createdAt || r.savedAt);
            return reportDate.toDateString() === filterDate.toDateString();
          });
        }

        if (isPaginationRequested(req.query)) {
          return res.json(createPaginatedResponse(filteredReports, req.query, 'reports'));
        } else {
          return res.json({ success: true, reports: filteredReports });
        }
      }

      // Если директории нет, возвращаем пустой список
      res.json({ success: true, reports: [] });
    } catch (error) {
      console.error('Ошибка получения отчетов:', error);
      res.json({ success: true, reports: [] });
    }
  });

  // GET /api/recount-reports/expired - просроченные/failed/rejected отчеты
  app.get('/api/recount-reports/expired', async (req, res) => {
    try {
      console.log('GET /api/recount-reports/expired');

      if (USE_DB) {
        try {
          const result = await db.query(
            `SELECT * FROM recount_reports
             WHERE status IN ('expired', 'failed', 'rejected')
             ORDER BY COALESCE(expired_at, failed_at, rejected_at, completed_at) DESC`
          );
          const reports = result.rows.map(dbRecountToCamel);
          console.log(`Найдено просроченных отчетов: ${reports.length} (DB)`);
          return res.json({ success: true, reports });
        } catch (dbErr) {
          console.error('[Recount] DB read error (expired), falling back to files:', dbErr.message);
        }
      }

      const reportsDir = `${DATA_DIR}/recount-reports`;
      const reports = [];

      if (await fileExists(reportsDir)) {
        const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const filePath = path.join(reportsDir, file);
            const content = await fsp.readFile(filePath, 'utf8');
            const report = JSON.parse(content);

            // Фильтруем только просроченные статусы: expired, failed, rejected
            const status = report.status;
            if (status === 'expired' || status === 'failed' || status === 'rejected') {
              reports.push(report);
            }
          } catch (e) {
            console.error(`Ошибка чтения файла ${file}:`, e.message);
          }
        }

        // Сортируем по дате (новые сначала)
        reports.sort((a, b) => {
          const dateA = new Date(a.expiredAt || a.failedAt || a.rejectedAt || a.completedAt || 0);
          const dateB = new Date(b.expiredAt || b.failedAt || b.rejectedAt || b.completedAt || 0);
          return dateB - dateA;
        });

        console.log(`Найдено просроченных отчетов: ${reports.length}`);
        return res.json({ success: true, reports });
      }

      res.json({ success: true, reports: [] });
    } catch (error) {
      console.error('Ошибка получения просроченных отчетов:', error);
      res.json({ success: true, reports: [] });
    }
  });

  // GET /api/recount-reports/:id - получить один отчёт пересчёта по ID
  app.get('/api/recount-reports/:id', async (req, res) => {
    try {
      const reportId = decodeURIComponent(req.params.id);
      console.log(`GET /api/recount-reports/${reportId}`);

      let report = null;

      if (USE_DB) {
        try {
          const row = await db.findById('recount_reports', reportId);
          if (row) {
            report = dbRecountToCamel(row);
          }
        } catch (dbErr) {
          console.error('[Recount] DB read error (by id), falling back to files:', dbErr.message);
        }
      }

      if (!report) {
        const reportsDir = `${DATA_DIR}/recount-reports`;
        const sanitizedId = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
        const reportFile = path.join(reportsDir, `${sanitizedId}.json`);

        if (await fileExists(reportFile)) {
          const content = await fsp.readFile(reportFile, 'utf8');
          report = JSON.parse(content);
        }

        // Попробуем найти по частичному совпадению (как в rating endpoint)
        if (!report && await fileExists(reportsDir)) {
          const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));
          const matchingFile = files.find(f => f.includes(sanitizedId.substring(0, 20)));
          if (matchingFile) {
            const content = await fsp.readFile(path.join(reportsDir, matchingFile), 'utf8');
            report = JSON.parse(content);
          }
        }
      }

      if (!report) {
        return res.status(404).json({ success: false, error: 'Отчёт пересчёта не найден' });
      }

      // IDOR: проверка владельца или админ
      const ownerPhone = report.employeePhone || report.phone;
      if (ownerPhone && req.user && req.user.phone !== ownerPhone && !req.user.isAdmin) {
        return res.status(403).json({ success: false, error: 'Доступ запрещён' });
      }

      res.json({ success: true, report });
    } catch (error) {
      console.error('Ошибка получения отчёта пересчёта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/pending-recount-reports - ожидающие (pending) пересчёты
  // ПРИМЕЧАНИЕ: pending файлы хранятся ТОЛЬКО в файловой системе (эфемерные, scheduler)
  // Но если pending отчёт был обновлён через scheduler → его статус в DB тоже pending
  app.get('/api/pending-recount-reports', async (req, res) => {
    try {
      console.log('GET /api/pending-recount-reports');

      const reportsDir = `${DATA_DIR}/recount-reports`;
      const reports = [];

      if (await fileExists(reportsDir)) {
        const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const filePath = path.join(reportsDir, file);
            const content = await fsp.readFile(filePath, 'utf8');
            const report = JSON.parse(content);

            // Фильтруем только pending отчёты
            if (report.status === 'pending') {
              reports.push(report);
            }
          } catch (e) {
            console.error(`Ошибка чтения файла ${file}:`, e);
          }
        }

        // Сортируем по дате создания (новые первыми)
        reports.sort((a, b) => {
          const dateA = new Date(a.createdAt || 0);
          const dateB = new Date(b.createdAt || 0);
          return dateB - dateA;
        });

        console.log(`Найдено pending пересчётов: ${reports.length}`);
        return res.json({ success: true, reports });
      }

      res.json({ success: true, reports: [] });
    } catch (error) {
      console.error('Ошибка получения pending пересчётов:', error);
      res.json({ success: true, reports: [] });
    }
  });

  // POST /api/recount-reports/:reportId/rating - оценка отчета пересчёта (только админ)
  app.post('/api/recount-reports/:reportId/rating', async (req, res) => {
    try {
      // Оценка пересчёта — только админ
      if (!req.user || !req.user.isAdmin) {
        return res.status(403).json({ success: false, error: 'Только администратор может оценить отчёт пересчёта' });
      }

      let { reportId } = req.params;
      const { rating, adminName } = req.body;
      // Декодируем URL-кодированный reportId
      reportId = decodeURIComponent(reportId);
      // Санитизируем имя файла (как при сохранении)
      const sanitizedId = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      console.log(`POST /api/recount-reports/${reportId}/rating:`, req.body);
      console.log(`Санитизированный ID: ${sanitizedId}`);

      let report = null;
      let actualFile = null;

      // Загрузка из DB или файла
      if (USE_DB) {
        try {
          const row = await db.findById('recount_reports', reportId);
          if (row) report = dbRecountToCamel(row);
        } catch (dbErr) {
          console.error('[Recount] DB read error in rating:', dbErr.message);
        }
      }

      const reportsDir = `${DATA_DIR}/recount-reports`;
      if (!report) {
        const reportFile = path.join(reportsDir, `${sanitizedId}.json`);
        actualFile = reportFile;

        if (!await fileExists(reportFile)) {
          console.error(`Файл не найден: ${reportFile}`);
          const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));
          const matchingFile = files.find(f => f.includes(sanitizedId.substring(0, 20)));
          if (matchingFile) {
            console.log(`Найден файл по частичному совпадению: ${matchingFile}`);
            actualFile = path.join(reportsDir, matchingFile);
          } else {
            return res.status(404).json({ success: false, error: 'Отчет не найден' });
          }
        }

        const content = await fsp.readFile(actualFile, 'utf8');
        report = JSON.parse(content);
      } else {
        // Определяем путь к файлу для dual-write
        actualFile = path.join(reportsDir, `${sanitizedId}.json`);
        if (!await fileExists(actualFile)) {
          const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));
          const matchingFile = files.find(f => f.includes(sanitizedId.substring(0, 20)));
          if (matchingFile) actualFile = path.join(reportsDir, matchingFile);
        }
      }

      // Обновляем оценку и статус
      report.adminRating = rating;
      report.adminName = adminName;
      report.ratedAt = new Date().toISOString();
      report.status = 'confirmed';

      // DB dual-write
      if (USE_DB) {
        try {
          await db.updateById('recount_reports', reportId, {
            admin_rating: rating,
            admin_name: adminName,
            rated_at: report.ratedAt,
            status: 'confirmed',
            updated_at: new Date().toISOString()
          });
          console.log('✅ Оценка сохранена в DB:', reportId);
        } catch (dbErr) {
          console.error('[Recount] DB update error in rating:', dbErr.message);
        }
      }

      // Всегда пишем в файл (dual-write)
      if (actualFile && await fileExists(actualFile)) {
        await writeJsonFile(actualFile, report);
      }
      console.log('✅ Оценка сохранена для отчета:', reportId);

      // Загружаем настройки баллов пересчёта
      const settingsFile = `${DATA_DIR}/points-settings/recount_points_settings.json`;
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
      const efficiencyPoints = calculateRecountPoints ? calculateRecountPoints(rating, settings) : 0;
      console.log(`📊 Рассчитанные баллы эффективности: ${efficiencyPoints} (оценка: ${rating})`);

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
        if (!Array.isArray(penalties)) penalties = (penalties && penalties.penalties) || [];
      }

      // Проверяем дубликат
      const sourceId = `recount_rating_${reportId}`;
      const exists = penalties.some(p => p.sourceId === sourceId);
      if (!exists) {
        const penalty = {
          id: `ep_${Date.now()}`,
          type: 'employee',
          entityId: report.employeePhone || report.employeeId,
          entityName: report.employeeName,
          shopAddress: report.shopAddress || null,
          employeeId: report.employeePhone || report.employeeId,
          employeeName: report.employeeName,
          category: 'recount',
          categoryName: 'Пересчёт товара',
          date: today,
          points: Math.round(efficiencyPoints * 100) / 100,
          reason: `Оценка пересчёта: ${rating}/10`,
          sourceId: sourceId,
          sourceType: 'recount_report',
          createdAt: now.toISOString()
        };

        penalties.push(penalty);
        await writeJsonFile(penaltiesFile, penalties);
        // DB dual-write
        await dbInsertPenalty(penalty);
        console.log(`✅ Баллы эффективности сохранены: ${efficiencyPoints} для ${report.employeeName}`);
      }

      // Отправляем push-уведомление сотруднику
      const employeePhone = report.employeePhone;
      if (employeePhone && sendPushToPhone) {
        try {
          const title = 'Пересчёт оценён';
          const body = `Ваша оценка: ${rating}/10 (${efficiencyPoints > 0 ? '+' : ''}${Math.round(efficiencyPoints * 100) / 100} баллов)`;

          await sendPushToPhone(employeePhone, title, body, {
            type: 'recount_confirmed',
            rating: String(rating),
            points: String(efficiencyPoints)
          });
          console.log(`📱 Push-уведомление отправлено: ${employeePhone}`);
        } catch (pushError) {
          console.error('⚠️ Ошибка отправки push:', pushError.message);
        }
      }

      res.json({
        success: true,
        message: 'Оценка успешно сохранена',
        efficiencyPoints: Math.round(efficiencyPoints * 100) / 100
      });
    } catch (error) {
      console.error('❌ Ошибка оценки отчета:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/recount-reports/:reportId/notify - отправка push-уведомления
  app.post('/api/recount-reports/:reportId/notify', async (req, res) => {
    try {
      const { reportId } = req.params;
      console.log(`POST /api/recount-reports/${reportId}/notify`);

      // Здесь можно добавить логику отправки push-уведомлений
      res.json({ success: true, message: 'Уведомление отправлено' });
    } catch (error) {
      console.error('Ошибка отправки уведомления:', error);
      res.json({ success: true, message: 'Уведомление обработано' });
    }
  });

  console.log(`✅ Recount API initialized (storage: ${USE_DB ? 'PostgreSQL' : 'JSON files'})`);
}

module.exports = { setupRecountAPI };

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
const { writeJsonFile, withLock } = require('../utils/async_fs');
const { fileExists } = require('../utils/file_helpers');
const { getMoscowTime } = require('../utils/moscow_time');
const { isPaginationRequested, createPaginatedResponse, createDbPaginatedResponse } = require('../utils/pagination');
const db = require('../utils/db');
const { dbInsertPenalty } = require('./efficiency_penalties_api');
const { requireEmployee } = require('../utils/session_middleware');
const { notifyCounterUpdate } = require('./counters_websocket');
const { generateId } = require('../utils/id_generator');

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
    autoRated: row.auto_rated,
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
  if (body.autoRated != null) data.auto_rated = body.autoRated;
  return data;
}

function setupRecountAPI(app, { sendPushToPhone, calculateRecountPoints, sendPushNotification } = {}) {

  // POST /api/recount-reports - создание отчета пересчета с TIME_EXPIRED валидацией
  app.post('/api/recount-reports', requireEmployee, async (req, res) => {
    try {
      console.log('POST /api/recount-reports:', JSON.stringify(req.body).substring(0, 200));

      // ============================================
      // TIME_EXPIRED валидация (аналогично пересменкам)
      // ============================================
      const shiftType = req.body.shiftType; // 'morning' | 'evening'

      if (!shiftType || !['morning', 'evening'].includes(shiftType)) {
        return res.status(400).json({
          success: false,
          error: 'INVALID_SHIFT_TYPE',
          message: 'shiftType обязателен и должен быть "morning" или "evening"'
        });
      }

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

        // Проверяем время НАЧАЛА пересчёта (startedAt), а не текущее время
        // Если сотрудник начал вовремя — даём закончить (пересчёт занимает 5-10 мин)
        let checkTime;
        if (req.body.startedAt) {
          checkTime = new Date(req.body.startedAt);
          // Конвертируем в московское время
          checkTime = new Date(checkTime.getTime() + 3 * 60 * 60 * 1000);
        } else {
          checkTime = getMoscowTime();
        }
        const currentHours = checkTime.getUTCHours();
        const currentMinutes = checkTime.getUTCMinutes();
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
        // Для вечерней смены дедлайн может быть после полуночи (напр. 06:58)
        let isExpired = false;
        if (shiftType === 'evening' && deadlineTimeMinutes < 12 * 60) {
          // Midnight crossover: дедлайн в утренних часах = следующий день
          // Просрочено только если текущее время > дедлайна И < начала вечерней смены
          const [startH, startM] = recountSettings.eveningStartTime.split(':').map(Number);
          const eveningStartMinutes = startH * 60 + startM;
          // Если мы между дедлайном (утро) и началом вечерней (вечер) — просрочено
          isExpired = currentTimeMinutes > deadlineTimeMinutes && currentTimeMinutes < eveningStartMinutes;
        } else {
          isExpired = currentTimeMinutes > deadlineTimeMinutes;
        }

        if (isExpired) {
          console.log(`⏰ TIME_EXPIRED: Начало пересчёта ${currentHours}:${String(currentMinutes).padStart(2, '0')}, дедлайн ${deadlineTime}`);
          return res.status(400).json({
            success: false,
            error: 'TIME_EXPIRED',
            message: 'К сожалению вы не успели пройти пересчёт вовремя'
          });
        }
      }

      // ============================================
      // D1: Валидация barcode товаров по мастер-каталогу
      // ============================================
      if (Array.isArray(req.body.answers) && req.body.answers.length > 0) {
        const { getMasterProductByBarcode } = require('./master_catalog_api');
        for (const answer of req.body.answers) {
          const barcode = answer.barcode || answer.productId;
          if (barcode) {
            const product = await getMasterProductByBarcode(barcode);
            if (!product) {
              return res.status(400).json({
                success: false,
                error: 'PRODUCT_NOT_FOUND',
                message: `Товар с barcode "${barcode}" не найден в мастер-каталоге`
              });
            }
          }
        }
      }

      // ============================================
      // Сохранение отчёта
      // ============================================
      const reportsDir = `${DATA_DIR}/recount-reports`;
      if (!await fileExists(reportsDir)) {
        await fsp.mkdir(reportsDir, { recursive: true });
      }

      const reportId = req.body.id || `report_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
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

      // Сначала пишем файл (стандарт проекта: file first, DB second)
      try {
        await writeJsonFile(reportFile, reportData);
        console.log('✅ Отчет пересчёта сохранен:', reportFile);
      } catch (writeError) {
        console.error('Ошибка записи файла:', writeError);
        throw writeError;
      }

      // DB dual-write (после файла — если DB падает, файл уже есть)
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
                  reportShiftType && pfContent.shiftType === reportShiftType) {
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

      notifyCounterUpdate('pendingRecountReports', { delta: 1 });

      // Push-уведомление управляющей/админам о новом пересчёте
      if (sendPushNotification) {
        try {
          const employeeName = req.body.employeeName || 'Сотрудник';
          const shopAddress = req.body.shopAddress || '';
          await sendPushNotification(
            'Новый пересчёт',
            `${employeeName} (${shopAddress})`,
            { type: 'recount_submitted', reportId }
          );
        } catch (pushErr) {
          console.error('⚠️ Push recount notification error:', pushErr.message);
        }
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
  app.get('/api/recount-reports', requireEmployee, async (req, res) => {
    try {
      console.log('GET /api/recount-reports:', req.query);

      if (USE_DB) {
        try {
          const conditions = [];
          const params = [];
          let paramIdx = 1;

          if (req.query.shopAddress) {
            conditions.push(`shop_address ILIKE $${paramIdx++}`);
            params.push(`%${req.query.shopAddress}%`);
          }
          if (req.query.employeeName) {
            conditions.push(`employee_name ILIKE $${paramIdx++}`);
            params.push(`%${req.query.employeeName}%`);
          }
          if (req.query.date) {
            conditions.push(`(created_at AT TIME ZONE 'Europe/Moscow')::date = $${paramIdx++}`);
            params.push(req.query.date);
          }

          const where = conditions.length > 0 ? conditions.join(' AND ') : '1=1';

          // SQL-level pagination
          if (isPaginationRequested(req.query)) {
            const paginatedResult = await db.findAllPaginated('recount_reports', {
              where,
              whereParams: params,
              orderBy: 'created_at',
              orderDir: 'DESC',
              page: parseInt(req.query.page) || 1,
              pageSize: Math.min(parseInt(req.query.limit) || 50, 200),
            });
            return res.json(createDbPaginatedResponse(paginatedResult, 'reports', dbRecountToCamel));
          }

          const result = await db.query(
            `SELECT * FROM recount_reports WHERE ${where} ORDER BY created_at DESC LIMIT 5000`,
            params
          );
          const reports = result.rows.map(dbRecountToCamel);
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
  app.get('/api/recount-reports/expired', requireEmployee, async (req, res) => {
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
        if (isPaginationRequested(req.query)) {
          return res.json(createPaginatedResponse(reports, req.query, 'reports'));
        }
        return res.json({ success: true, reports });
      }

      res.json({ success: true, reports: [] });
    } catch (error) {
      console.error('Ошибка получения просроченных отчетов:', error);
      res.json({ success: true, reports: [] });
    }
  });

  // GET /api/recount-reports/:id - получить один отчёт пересчёта по ID
  app.get('/api/recount-reports/:id', requireEmployee, async (req, res) => {
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
  app.get('/api/pending-recount-reports', requireEmployee, async (req, res) => {
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
        if (isPaginationRequested(req.query)) {
          return res.json(createPaginatedResponse(reports, req.query, 'reports'));
        }
        return res.json({ success: true, reports });
      }

      res.json({ success: true, reports: [] });
    } catch (error) {
      console.error('Ошибка получения pending пересчётов:', error);
      res.json({ success: true, reports: [] });
    }
  });

  // POST /api/recount-reports/:reportId/rating - оценка отчета пересчёта (только админ)
  app.post('/api/recount-reports/:reportId/rating', requireEmployee, async (req, res) => {
    try {
      // Оценка пересчёта — админ или управляющая
      if (!req.user || (!req.user.isAdmin && !req.user.isManager)) {
        return res.status(403).json({ success: false, error: 'Только администратор или управляющая может оценить отчёт пересчёта' });
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

      // Block re-rating auto-rated reports
      if (report && report.autoRated) {
        return res.status(403).json({ success: false, error: 'Отчёт оценён автоматически (максимальная оценка). Переоценка невозможна.' });
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

      // Block re-rating auto-rated reports (check after file load too)
      if (report.autoRated) {
        return res.status(403).json({ success: false, error: 'Отчёт оценён автоматически (максимальная оценка). Переоценка невозможна.' });
      }

      // Обновляем оценку и статус
      report.adminRating = rating;
      report.adminName = adminName;
      report.ratedAt = new Date().toISOString();
      report.status = 'confirmed';

      // Файл первым (dual-write: файл → затем DB)
      if (actualFile && await fileExists(actualFile)) {
        await writeJsonFile(actualFile, report);
      }
      console.log('✅ Оценка сохранена для отчета:', reportId);

      // DB dual-write (после файла)
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

      // Сохраняем баллы в efficiency-penalties (московское время)
      const now = getMoscowTime();
      const monthKey = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
      const today = now.toISOString().split('T')[0];
      const efficiencyDir = `${DATA_DIR}/efficiency-penalties`;

      if (!await fileExists(efficiencyDir)) {
        await fsp.mkdir(efficiencyDir, { recursive: true });
      }

      const penaltiesFile = path.join(efficiencyDir, `${monthKey}.json`);
      const sourceId = `recount_rating_${reportId}`;

      // withLock: атомарный read-check-write — защита от race condition при двух одновременных оценках
      await withLock(`efficiency-penalties-${monthKey}`, async () => {
        let penalties = [];
        if (await fileExists(penaltiesFile)) {
          penalties = JSON.parse(await fsp.readFile(penaltiesFile, 'utf8'));
          if (!Array.isArray(penalties)) penalties = (penalties && penalties.penalties) || [];
        }

        // Проверяем дубликат внутри лока (защита от race condition)
        const exists = penalties.some(p => p.sourceId === sourceId);
        if (!exists) {
          const penalty = {
            id: generateId('ep'),
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
          await writeJsonFile(penaltiesFile, penalties, { useLock: false }); // already inside withLock
          // DB dual-write
          await dbInsertPenalty(penalty);
          console.log(`✅ Баллы эффективности сохранены: ${efficiencyPoints} для ${report.employeeName}`);
        } else {
          console.log(`[Recount] Дубликат sourceId пропущен: ${sourceId}`);
        }
      });

      // C4: Feedback loop — рейтинг admin → AI training
      // Если в ответах есть данные ИИ, сообщаем модели была ли она права
      if (Array.isArray(report.answers)) {
        try {
          const cigaretteVision = require('../modules/cigarette-vision');
          for (const answer of report.answers) {
            const pid = answer.productId || answer.barcode;
            if (!pid || answer.aiQuantity == null || answer.actualBalance == null) continue;
            const diff = Math.abs(answer.aiQuantity - answer.actualBalance);
            const isCorrect = diff <= 1;
            if (isCorrect && rating >= 8) {
              // ИИ был прав, высокая оценка → успех
              await cigaretteVision.reportAiSuccess(pid);
            } else if (!isCorrect && rating <= 4) {
              // ИИ ошибся, низкая оценка → сохраняем как ошибку для переобучения
              await cigaretteVision.reportAiError({
                productId: pid,
                productName: answer.productName || '',
                expectedCount: answer.actualBalance,
                aiCount: answer.aiQuantity,
                shopAddress: report.shopAddress || '',
              });
            }
          }
        } catch (aiErr) {
          console.warn('[Recount] C4 feedback loop error:', aiErr.message);
        }
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

      notifyCounterUpdate('pendingRecountReports', { delta: -1 });
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
  app.post('/api/recount-reports/:reportId/notify', requireEmployee, async (req, res) => {
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

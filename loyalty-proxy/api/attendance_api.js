/**
 * Attendance API
 * Отметки прихода, проверка опозданий, GPS-уведомления
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, maskPhone } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const { isPaginationRequested, createPaginatedResponse, createDbPaginatedResponse } = require('../utils/pagination');
const { dbInsertPenalty } = require('./efficiency_penalties_api');
const db = require('../utils/db');
const { getMoscowTime, getMoscowDateString } = require('../utils/moscow_time');
const { requireEmployee } = require('../utils/session_middleware');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const USE_DB = process.env.USE_DB_ATTENDANCE === 'true';
const ATTENDANCE_DIR = `${DATA_DIR}/attendance`;
const SHOPS_DIR = `${DATA_DIR}/shops`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;

// Кэш отправленных GPS-уведомлений (phone_date -> { shopAddress, notifiedAt })
const gpsNotificationCache = new Map();

// ============================================
// DB conversion helpers
// ============================================

function camelToDbAttendance(r) {
  return {
    id: r.id,
    employee_name: r.employeeName || null,
    employee_phone: r.employeePhone || null,
    shop_address: r.shopAddress || null,
    shop_name: r.shopName || null,
    shift_type: r.shiftType || null,
    status: r.status || 'confirmed',
    timestamp: r.timestamp || null,
    latitude: r.latitude != null ? r.latitude : null,
    longitude: r.longitude != null ? r.longitude : null,
    distance: r.distance != null ? r.distance : null,
    is_on_time: r.isOnTime != null ? r.isOnTime : null,
    late_minutes: r.lateMinutes != null ? r.lateMinutes : null,
    marked_at: r.markedAt || r.confirmedAt || null,
    deadline: r.deadline || null,
    failed_at: r.failedAt || null,
    created_at: r.createdAt || new Date().toISOString()
  };
}

function dbAttendanceToCamel(row) {
  return {
    id: row.id,
    employeeName: row.employee_name,
    employeePhone: row.employee_phone,
    shopAddress: row.shop_address,
    shopName: row.shop_name,
    shiftType: row.shift_type,
    status: row.status,
    timestamp: row.timestamp ? new Date(row.timestamp).toISOString() : null,
    latitude: row.latitude != null ? parseFloat(row.latitude) : null,
    longitude: row.longitude != null ? parseFloat(row.longitude) : null,
    distance: row.distance != null ? parseFloat(row.distance) : null,
    isOnTime: row.is_on_time,
    lateMinutes: row.late_minutes,
    markedAt: row.marked_at ? new Date(row.marked_at).toISOString() : null,
    deadline: row.deadline ? new Date(row.deadline).toISOString() : null,
    failedAt: row.failed_at ? new Date(row.failed_at).toISOString() : null,
    createdAt: row.created_at ? new Date(row.created_at).toISOString() : null
  };
}

// ============================================
// Вспомогательные функции
// ============================================

// Загрузить настройки магазина
async function loadShopSettings(shopAddress) {
  try {
    const settingsDir = `${DATA_DIR}/shop-settings`;
    const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const settingsFile = path.join(settingsDir, `${sanitizedAddress}.json`);

    if (!await fileExists(settingsFile)) {
      console.log(`Настройки магазина не найдены: ${shopAddress}`);
      return null;
    }

    const content = await fsp.readFile(settingsFile, 'utf8');
    return JSON.parse(content);
  } catch (error) {
    console.error('Ошибка загрузки настроек магазина:', error);
    return null;
  }
}

// Загрузить настройки баллов за attendance
async function loadAttendancePointsSettings() {
  try {
    const settingsFile = `${DATA_DIR}/points-settings/attendance.json`;

    if (!await fileExists(settingsFile)) {
      console.log('Настройки баллов attendance не найдены, используются значения по умолчанию');
      return { onTimePoints: 0.5, latePoints: -1 };
    }

    const content = await fsp.readFile(settingsFile, 'utf8');
    return JSON.parse(content);
  } catch (error) {
    console.error('Ошибка загрузки настроек баллов attendance:', error);
    return { onTimePoints: 0.5, latePoints: -1 };
  }
}

// Парсить время из строки "HH:mm" в минуты
function parseTimeToMinutes(timeStr) {
  if (!timeStr) return null;
  const parts = timeStr.split(':');
  if (parts.length !== 2) return null;
  const hours = parseInt(parts[0], 10);
  const minutes = parseInt(parts[1], 10);
  if (isNaN(hours) || isNaN(minutes)) return null;
  return hours * 60 + minutes;
}

// Проверить попадает ли время в интервал смены
async function checkShiftTime(timestamp, shopSettings) {
  const time = new Date(timestamp);
  // UTC+3 (Moscow timezone)
  const moscowTime = new Date(time.getTime() + 3 * 60 * 60 * 1000);
  const hour = moscowTime.getUTCHours();
  const minute = moscowTime.getUTCMinutes();
  const currentMinutes = hour * 60 + minute;

  console.log(`Проверка времени (МСК): ${hour}:${minute} (${currentMinutes} минут)`);

  if (!shopSettings) {
    console.log('Нет настроек магазина - пропускаем проверку');
    return { isOnTime: null, shiftType: null, needsShiftSelection: false, lateMinutes: 0 };
  }

  // Проверяем утреннюю смену
  if (shopSettings.morningShiftStart && shopSettings.morningShiftEnd) {
    const start = parseTimeToMinutes(shopSettings.morningShiftStart);
    const end = parseTimeToMinutes(shopSettings.morningShiftEnd);
    console.log(`Утренняя смена: ${start}-${end} минут`);

    if (start !== null && end !== null && currentMinutes >= start && currentMinutes <= end) {
      return { isOnTime: true, shiftType: 'morning', needsShiftSelection: false, lateMinutes: 0 };
    }
  }

  // Проверяем дневную смену (опциональная)
  if (shopSettings.dayShiftStart && shopSettings.dayShiftEnd) {
    const start = parseTimeToMinutes(shopSettings.dayShiftStart);
    const end = parseTimeToMinutes(shopSettings.dayShiftEnd);
    console.log(`Дневная смена: ${start}-${end} минут`);

    if (start !== null && end !== null && currentMinutes >= start && currentMinutes <= end) {
      return { isOnTime: true, shiftType: 'day', needsShiftSelection: false, lateMinutes: 0 };
    }
  }

  // Проверяем ночную смену
  if (shopSettings.nightShiftStart && shopSettings.nightShiftEnd) {
    const start = parseTimeToMinutes(shopSettings.nightShiftStart);
    const end = parseTimeToMinutes(shopSettings.nightShiftEnd);
    console.log(`Ночная смена: ${start}-${end} минут`);

    if (start !== null && end !== null && currentMinutes >= start && currentMinutes <= end) {
      return { isOnTime: true, shiftType: 'night', needsShiftSelection: false, lateMinutes: 0 };
    }
  }

  // Если не попал ни в один интервал - нужен выбор смены
  console.log('Время не попадает в интервалы смен - требуется выбор');
  return {
    isOnTime: null,
    shiftType: null,
    needsShiftSelection: true,
    lateMinutes: 0
  };
}

// Вычислить опоздание в минутах
async function calculateLateMinutes(timestamp, shiftType, shopSettings) {
  if (!shopSettings || !shiftType) return 0;

  const time = new Date(timestamp);
  // UTC+3 (Moscow timezone) — match checkShiftTime behavior
  const moscowTime = new Date(time.getTime() + 3 * 60 * 60 * 1000);
  const currentMinutes = moscowTime.getUTCHours() * 60 + moscowTime.getUTCMinutes();

  let shiftStart = null;
  if (shiftType === 'morning' && shopSettings.morningShiftStart) {
    shiftStart = parseTimeToMinutes(shopSettings.morningShiftStart);
  } else if (shiftType === 'day' && shopSettings.dayShiftStart) {
    shiftStart = parseTimeToMinutes(shopSettings.dayShiftStart);
  } else if (shiftType === 'night' && shopSettings.nightShiftStart) {
    shiftStart = parseTimeToMinutes(shopSettings.nightShiftStart);
  }

  if (shiftStart === null) return 0;

  // Если пришёл раньше или вовремя
  if (currentMinutes <= shiftStart) return 0;

  // Вычисляем опоздание
  return currentMinutes - shiftStart;
}

// Создать штраф за опоздание
async function createLatePenalty(employeeName, shopAddress, lateMinutes, shiftType) {
  try {
    const now = getMoscowTime();
    const monthKey = now.toISOString().slice(0, 7); // YYYY-MM (московское время)

    // Загружаем настройки баллов
    const pointsSettings = await loadAttendancePointsSettings();
    const penalty = pointsSettings.latePoints || -1;

    const penaltyRecord = {
      id: `late_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type: 'employee',
      entityId: employeeName,
      entityName: employeeName,
      shopAddress: shopAddress,
      employeeName: employeeName,
      category: 'attendance_late',
      categoryName: 'Опоздание на работу',
      date: now.toISOString().split('T')[0],
      points: penalty,
      reason: `Опоздание на ${lateMinutes} мин (${shiftType === 'morning' ? 'утренняя' : shiftType === 'day' ? 'дневная' : 'ночная'} смена)`,
      lateMinutes: lateMinutes,
      shiftType: shiftType,
      sourceType: 'attendance',
      createdAt: now.toISOString()
    };

    // Сохраняем в файл штрафов
    const penaltiesDir = `${DATA_DIR}/efficiency-penalties`;
    if (!await fileExists(penaltiesDir)) {
      await fsp.mkdir(penaltiesDir, { recursive: true });
    }

    const penaltiesFile = path.join(penaltiesDir, `${monthKey}.json`);
    let penalties = [];

    if (await fileExists(penaltiesFile)) {
      const content = await fsp.readFile(penaltiesFile, 'utf8');
      penalties = JSON.parse(content);
      if (!Array.isArray(penalties)) penalties = (penalties && penalties.penalties) || [];
    }

    penalties.push(penaltyRecord);
    await writeJsonFile(penaltiesFile, penalties);
    // DB dual-write
    await dbInsertPenalty(penaltyRecord);

    console.log(`Штраф создан: ${penalty} баллов за опоздание ${lateMinutes} мин для ${employeeName}`);
    return penaltyRecord;
  } catch (error) {
    console.error('Ошибка создания штрафа:', error);
    return null;
  }
}

// Создать бонус за своевременный приход
async function createOnTimeBonus(employeeName, shopAddress, shiftType) {
  try {
    const now = getMoscowTime();
    const monthKey = now.toISOString().slice(0, 7); // YYYY-MM (московское время)

    // Загружаем настройки баллов
    const pointsSettings = await loadAttendancePointsSettings();
    const bonus = pointsSettings.onTimePoints || 0.5;

    if (bonus <= 0) {
      console.log('Бонус за своевременный приход отключен (0 или меньше)');
      return null;
    }

    const bonusRecord = {
      id: `ontime_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type: 'employee',
      entityId: employeeName,
      entityName: employeeName,
      shopAddress: shopAddress,
      employeeName: employeeName,
      category: 'attendance_ontime',
      categoryName: 'Своевременный приход',
      date: now.toISOString().split('T')[0],
      points: bonus,
      reason: `Приход вовремя (${shiftType === 'morning' ? 'утренняя' : shiftType === 'day' ? 'дневная' : 'ночная'} смена)`,
      shiftType: shiftType,
      sourceType: 'attendance',
      createdAt: now.toISOString()
    };

    // Сохраняем в файл бонусов
    const penaltiesDir = `${DATA_DIR}/efficiency-penalties`;
    if (!await fileExists(penaltiesDir)) {
      await fsp.mkdir(penaltiesDir, { recursive: true });
    }

    const penaltiesFile = path.join(penaltiesDir, `${monthKey}.json`);
    let penalties = [];

    if (await fileExists(penaltiesFile)) {
      const content = await fsp.readFile(penaltiesFile, 'utf8');
      penalties = JSON.parse(content);
    }

    penalties.push(bonusRecord);
    await writeJsonFile(penaltiesFile, penalties);
    // DB dual-write
    await dbInsertPenalty(bonusRecord);

    console.log(`Бонус создан: +${bonus} баллов за своевременный приход для ${employeeName}`);
    return bonusRecord;
  } catch (error) {
    console.error('Ошибка создания бонуса:', error);
    return null;
  }
}

// Функция расчёта расстояния между координатами (Haversine formula)
function calculateGpsDistance(lat1, lon1, lat2, lon2) {
  const R = 6371000; // Радиус Земли в метрах
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return R * c;
}

// ============================================
// Setup function
// ============================================

function setupAttendanceAPI(app, {
  canMarkAttendance,
  markAttendancePendingCompleted,
  getPendingAttendanceReports,
  getFailedAttendanceReports,
  sendPushToPhone,
} = {}) {

  // POST /api/attendance - отметка прихода
  app.post('/api/attendance', requireEmployee, async (req, res) => {
    try {
      console.log('POST /api/attendance:', JSON.stringify(req.body).substring(0, 200));

      // Проверяем есть ли pending отчёт для этого магазина
      if (canMarkAttendance) {
        const canMark = canMarkAttendance(req.body.shopAddress);
        if (!canMark) {
          console.log('Отметка отклонена: нет pending отчёта для', req.body.shopAddress);
          return res.status(400).json({
            success: false,
            error: 'Сейчас не время для отметки. Подождите начала смены.',
            cannotMark: true
          });
        }
      }

      if (!await fileExists(ATTENDANCE_DIR)) {
        await fsp.mkdir(ATTENDANCE_DIR, { recursive: true });
      }

      const recordId = req.body.id || `attendance_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      const sanitizedId = recordId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const recordFile = path.join(ATTENDANCE_DIR, `${sanitizedId}.json`);

      // Загружаем настройки магазина
      const shopSettings = await loadShopSettings(req.body.shopAddress);

      // Проверяем время по интервалам смен
      const checkResult = await checkShiftTime(req.body.timestamp, shopSettings);

      const recordData = {
        ...req.body,
        isOnTime: checkResult.isOnTime,
        shiftType: checkResult.shiftType,
        lateMinutes: checkResult.lateMinutes,
        createdAt: new Date().toISOString(),
      };

      await writeJsonFile(recordFile, recordData);
      // DB dual-write
      if (USE_DB) {
        try {
          await db.upsert('attendance', camelToDbAttendance({ ...recordData, id: sanitizedId }));
        } catch (dbErr) {
          console.error('DB attendance insert error:', dbErr.message);
        }
      }
      console.log('Отметка сохранена:', recordFile);

      // Удаляем pending отчёт после успешной отметки
      if (markAttendancePendingCompleted) {
        markAttendancePendingCompleted(req.body.shopAddress, checkResult.shiftType);
      }

      // Если время вне интервала - возвращаем флаг для диалога выбора смены
      if (checkResult.needsShiftSelection) {
        return res.json({
          success: true,
          needsShiftSelection: true,
          recordId: sanitizedId,
          message: 'Выберите смену'
        });
      }

      // Если пришёл вовремя - создаём бонус
      if (checkResult.isOnTime === true) {
        await createOnTimeBonus(req.body.employeeName, req.body.shopAddress, checkResult.shiftType);
      }

      // Отправляем push-уведомление админу
      try {
        console.log('Push-уведомление отправлено админу');
      } catch (notifyError) {
        console.log('Ошибка отправки уведомления:', notifyError);
      }

      res.json({
        success: true,
        isOnTime: checkResult.isOnTime,
        shiftType: checkResult.shiftType,
        lateMinutes: checkResult.lateMinutes,
        message: checkResult.isOnTime ? 'Вы пришли вовремя!' : 'Отметка успешно сохранена',
        recordId: sanitizedId
      });
    } catch (error) {
      console.error('Ошибка сохранения отметки:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при сохранении отметки'
      });
    }
  });

  // POST /api/attendance/confirm-shift - подтверждение выбора смены
  app.post('/api/attendance/confirm-shift', requireEmployee, async (req, res) => {
    try {
      console.log('POST /api/attendance/confirm-shift: recordId:', req.body?.recordId, 'shift:', req.body?.selectedShift);

      const { recordId, selectedShift } = req.body;

      if (!recordId || !selectedShift) {
        return res.status(400).json({
          success: false,
          error: 'Отсутствуют обязательные поля: recordId, selectedShift'
        });
      }

      const sanitizedId = recordId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const recordFile = path.join(ATTENDANCE_DIR, `${sanitizedId}.json`);

      if (!await fileExists(recordFile)) {
        return res.status(404).json({
          success: false,
          error: 'Запись отметки не найдена'
        });
      }

      // Загружаем существующую запись
      const content = await fsp.readFile(recordFile, 'utf8');
      const record = JSON.parse(content);

      // Загружаем настройки магазина
      const shopSettings = await loadShopSettings(record.shopAddress);

      // Вычисляем опоздание
      const lateMinutes = await calculateLateMinutes(record.timestamp, selectedShift, shopSettings);

      // Обновляем запись
      record.shiftType = selectedShift;
      record.isOnTime = lateMinutes === 0;
      record.lateMinutes = lateMinutes;
      record.confirmedAt = new Date().toISOString();

      await writeJsonFile(recordFile, record);
      // DB dual-write
      if (USE_DB) {
        try {
          await db.upsert('attendance', camelToDbAttendance({ ...record, id: sanitizedId }));
        } catch (dbErr) {
          console.error('DB attendance update error:', dbErr.message);
        }
      }

      // Если опоздал - создаём штраф
      let penaltyCreated = false;
      if (lateMinutes > 0) {
        const penalty = await createLatePenalty(record.employeeName, record.shopAddress, lateMinutes, selectedShift);
        penaltyCreated = penalty !== null;
      } else {
        // Если пришёл вовремя - создаём бонус
        await createOnTimeBonus(record.employeeName, record.shopAddress, selectedShift);
      }

      const shiftNames = {
        morning: 'утренняя',
        day: 'дневная',
        night: 'ночная'
      };

      const message = lateMinutes > 0
        ? `Вы опоздали на ${lateMinutes} мин (${shiftNames[selectedShift]} смена). Начислен штраф.`
        : `Отметка подтверждена (${shiftNames[selectedShift]} смена)`;

      res.json({
        success: true,
        isOnTime: lateMinutes === 0,
        shiftType: selectedShift,
        lateMinutes: lateMinutes,
        penaltyCreated: penaltyCreated,
        message: message
      });
    } catch (error) {
      console.error('Ошибка подтверждения смены:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при подтверждении смены'
      });
    }
  });

  // GET /api/attendance/check - проверка отметки сегодня
  app.get('/api/attendance/check', requireEmployee, async (req, res) => {
    try {
      const employeeName = req.query.employeeName;
      if (!employeeName) {
        return res.json({ success: true, hasAttendance: false });
      }

      const todayStr = getMoscowDateString();

      // DB path
      if (USE_DB) {
        try {
          const result = await db.query(
            `SELECT id FROM attendance WHERE employee_name = $1 AND timestamp::date = $2::date LIMIT 1`,
            [employeeName, todayStr]
          );
          return res.json({ success: true, hasAttendance: result.rows.length > 0 });
        } catch (dbErr) {
          console.error('DB attendance check error:', dbErr.message);
        }
      }

      // File path
      if (!await fileExists(ATTENDANCE_DIR)) {
        return res.json({ success: true, hasAttendance: false });
      }

      const files = (await fsp.readdir(ATTENDANCE_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const filePath = path.join(ATTENDANCE_DIR, file);
          const content = await fsp.readFile(filePath, 'utf8');
          const record = JSON.parse(content);

          if (record.employeeName === employeeName) {
            const recordDate = new Date(record.timestamp);
            const recordDateStr = `${recordDate.getFullYear()}-${String(recordDate.getMonth() + 1).padStart(2, '0')}-${String(recordDate.getDate()).padStart(2, '0')}`;

            if (recordDateStr === todayStr) {
              return res.json({ success: true, hasAttendance: true });
            }
          }
        } catch (e) {
          console.error(`Ошибка чтения файла ${file}:`, e);
        }
      }

      res.json({ success: true, hasAttendance: false });
    } catch (error) {
      console.error('Ошибка проверки отметки:', error);
      res.json({ success: true, hasAttendance: false });
    }
  });

  // GET /api/attendance - получение списка отметок
  app.get('/api/attendance', requireEmployee, async (req, res) => {
    try {
      console.log('GET /api/attendance:', req.query);

      // DB path
      if (USE_DB) {
        try {
          // Build WHERE conditions for filters
          const whereParts = [];
          const whereParams = [];
          if (req.query.employeeName) {
            whereParts.push(`employee_name ILIKE $${whereParts.length + 1}`);
            whereParams.push(`%${req.query.employeeName}%`);
          }
          if (req.query.shopAddress) {
            whereParts.push(`shop_address ILIKE $${whereParts.length + 1}`);
            whereParams.push(`%${req.query.shopAddress}%`);
          }
          if (req.query.date) {
            whereParts.push(`timestamp::date = $${whereParts.length + 1}::date`);
            whereParams.push(req.query.date);
          }

          const dbOpts = {
            orderBy: 'created_at',
            orderDir: 'DESC',
            ...(whereParts.length > 0 ? { where: whereParts.join(' AND '), whereParams } : {}),
          };

          // SQL-level pagination when requested
          if (isPaginationRequested(req.query)) {
            const result = await db.findAllPaginated('attendance', {
              ...dbOpts,
              page: parseInt(req.query.page) || 1,
              pageSize: Math.min(parseInt(req.query.limit) || 50, 200),
            });
            return res.json(createDbPaginatedResponse(result, 'records', dbAttendanceToCamel));
          }

          // No pagination: return all
          const rows = await db.findAll('attendance', dbOpts);
          return res.json({ success: true, records: rows.map(dbAttendanceToCamel) });
        } catch (dbErr) {
          console.error('DB attendance list error:', dbErr.message);
        }
      }

      // File path
      const records = [];

      if (await fileExists(ATTENDANCE_DIR)) {
        const files = (await fsp.readdir(ATTENDANCE_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const filePath = path.join(ATTENDANCE_DIR, file);
            const content = await fsp.readFile(filePath, 'utf8');
            const record = JSON.parse(content);
            records.push(record);
          } catch (e) {
            console.error(`Ошибка чтения файла ${file}:`, e);
          }
        }

        // Сортируем по дате (новые первыми)
        records.sort((a, b) => {
          const dateA = new Date(a.timestamp || a.createdAt || 0);
          const dateB = new Date(b.timestamp || b.createdAt || 0);
          return dateB - dateA;
        });

        // Применяем фильтры
        let filteredRecords = records;
        if (req.query.employeeName) {
          filteredRecords = filteredRecords.filter(r =>
            r.employeeName && r.employeeName.includes(req.query.employeeName)
          );
        }
        if (req.query.shopAddress) {
          filteredRecords = filteredRecords.filter(r =>
            r.shopAddress && r.shopAddress.includes(req.query.shopAddress)
          );
        }
        if (req.query.date) {
          const filterDate = new Date(req.query.date);
          filteredRecords = filteredRecords.filter(r => {
            const recordDate = new Date(r.timestamp || r.createdAt);
            return recordDate.toDateString() === filterDate.toDateString();
          });
        }

        if (isPaginationRequested(req.query)) {
          return res.json(createPaginatedResponse(filteredRecords, req.query, 'records'));
        }
        return res.json({ success: true, records: filteredRecords });
      }

      res.json({ success: true, records: [] });
    } catch (error) {
      console.error('Ошибка получения отметок:', error);
      res.json({ success: true, records: [] });
    }
  });

  // GET /api/attendance/pending - получить pending отчеты
  app.get('/api/attendance/pending', requireEmployee, async (req, res) => {
    try {
      console.log('GET /api/attendance/pending');
      const reports = getPendingAttendanceReports ? getPendingAttendanceReports() : [];
      res.json({
        success: true,
        items: reports,
        count: reports.length
      });
    } catch (error) {
      console.error('Ошибка получения pending attendance:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при получении pending attendance'
      });
    }
  });

  // GET /api/attendance/failed - получить failed отчеты
  app.get('/api/attendance/failed', requireEmployee, async (req, res) => {
    try {
      console.log('GET /api/attendance/failed');
      const reports = getFailedAttendanceReports ? getFailedAttendanceReports() : [];
      res.json({
        success: true,
        items: reports,
        count: reports.length
      });
    } catch (error) {
      console.error('Ошибка получения failed attendance:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при получении failed attendance'
      });
    }
  });

  // GET /api/attendance/can-mark - проверить можно ли отмечаться на магазине
  app.get('/api/attendance/can-mark', requireEmployee, async (req, res) => {
    try {
      const { shopAddress } = req.query;
      console.log('GET /api/attendance/can-mark:', shopAddress);

      if (!shopAddress) {
        return res.status(400).json({
          success: false,
          canMark: false,
          error: 'shopAddress is required'
        });
      }

      const canMark = canMarkAttendance ? canMarkAttendance(shopAddress) : false;
      res.json({
        success: true,
        canMark: canMark,
        shopAddress: shopAddress
      });
    } catch (error) {
      console.error('Ошибка проверки can-mark attendance:', error);
      res.status(500).json({
        success: false,
        canMark: false,
        error: error.message || 'Ошибка проверки'
      });
    }
  });

  // POST /api/attendance/gps-check - Проверка GPS и отправка уведомления
  // No requireAuth: called from WorkManager background isolate where session token is unavailable.
  // Protected by global X-Api-Key middleware.
  app.post('/api/attendance/gps-check', async (req, res) => {
    try {
      const { lat, lng, phone, employeeName } = req.body;

      console.log(`[GPS-Check] Request: lat=${lat}, lng=${lng}, phone=${maskPhone(phone)}, employee=${employeeName}`);

      if (!lat || !lng || !phone) {
        return res.json({ success: true, notified: false, reason: 'missing_params' });
      }

      // 1. Загружаем список магазинов с координатами из отдельных файлов
      let shops = [];
      try {
        const shopFiles = (await fsp.readdir(SHOPS_DIR)).filter(f => f.startsWith('shop_') && f.endsWith('.json'));
        for (const file of shopFiles) {
          try {
            const data = await fsp.readFile(path.join(SHOPS_DIR, file), 'utf8');
            const shop = JSON.parse(data);
            if (shop.latitude && shop.longitude) {
              shops.push(shop);
            }
          } catch (e) {
            console.error(`[GPS-Check] Error loading shop ${file}:`, e.message);
          }
        }
        console.log(`[GPS-Check] Loaded ${shops.length} shops with coordinates`);
      } catch (e) {
        console.error('[GPS-Check] Error reading shops directory:', e.message);
      }

      if (shops.length === 0) {
        console.log('[GPS-Check] No shops found');
        return res.json({ success: true, notified: false, reason: 'no_shops' });
      }

      // 2. Находим ближайший магазин (в пределах 750м)
      let nearestShop = null;
      let minDistance = Infinity;
      const MAX_DISTANCE = 750; // метров

      for (const shop of shops) {
        if (shop.latitude && shop.longitude) {
          const distance = calculateGpsDistance(lat, lng, shop.latitude, shop.longitude);
          if (distance < minDistance && distance <= MAX_DISTANCE) {
            minDistance = distance;
            nearestShop = shop;
          }
        }
      }

      if (!nearestShop) {
        console.log('[GPS-Check] Employee not near any shop');
        return res.json({ success: true, notified: false, reason: 'not_near_shop' });
      }

      console.log(`[GPS-Check] Nearest shop: ${nearestShop.name} (${Math.round(minDistance)}m)`);

      // 3. Проверяем расписание - есть ли смена сегодня на этом магазине
      const today = getMoscowDateString();
      const monthKey = today.substring(0, 7); // YYYY-MM
      const scheduleFile = path.join(`${DATA_DIR}/work-schedules`, `${monthKey}.json`);

      // Сначала ищем сотрудника по телефону в базе employees
      let employeeId = null;
      try {
        const empFiles = (await fsp.readdir(EMPLOYEES_DIR)).filter(f => f.endsWith('.json'));
        for (const file of empFiles) {
          try {
            const empData = JSON.parse(await fsp.readFile(path.join(EMPLOYEES_DIR, file), 'utf8'));
            const empPhone = (empData.phone || '').replace(/\D/g, '');
            const checkPhone = phone.replace(/\D/g, '');
            if (empPhone && (empPhone === checkPhone || empPhone.endsWith(checkPhone.slice(-10)) || checkPhone.endsWith(empPhone.slice(-10)))) {
              employeeId = empData.id;
              console.log(`[GPS-Check] Found employee: ${empData.name} (${employeeId})`);
              break;
            }
          } catch (e) {
            console.error(`[GPS-Check] Error reading employee file ${file}:`, e.message);
          }
        }
      } catch (e) {
        console.error('[GPS-Check] Error loading employees:', e.message);
      }

      let hasShiftToday = false;
      if (await fileExists(scheduleFile)) {
        try {
          const data = await fsp.readFile(scheduleFile, 'utf8');
          const schedule = JSON.parse(data);
          const entries = schedule.entries || [];

          // Ищем смену по employeeId и адресу магазина
          hasShiftToday = entries.some(entry => {
            const idMatch = employeeId && entry.employeeId === employeeId;
            return idMatch &&
                   entry.shopAddress === nearestShop.address &&
                   entry.date === today;
          });

          if (hasShiftToday) {
            console.log(`[GPS-Check] Found shift for ${employeeId} at ${nearestShop.address}`);
          }
        } catch (e) {
          console.error('[GPS-Check] Error loading schedule:', e.message);
        }
      }

      if (!hasShiftToday) {
        console.log(`[GPS-Check] No shift today for ${maskPhone(phone)} at ${nearestShop.address}`);
        return res.json({ success: true, notified: false, reason: 'no_shift_here' });
      }

      // 4. Проверяем есть ли pending отчёт для этого магазина
      const pendingReports = getPendingAttendanceReports ? getPendingAttendanceReports() : [];
      const hasPending = pendingReports.some(r =>
        r.shopAddress === nearestShop.address && r.status === 'pending'
      );

      if (!hasPending) {
        console.log(`[GPS-Check] No pending attendance report for ${nearestShop.address}`);
        return res.json({ success: true, notified: false, reason: 'no_pending' });
      }

      // 5. Проверяем кэш (чтобы не спамить)
      const cacheKey = `${phone}_${today}`;
      const cached = gpsNotificationCache.get(cacheKey);
      if (cached && cached.shopAddress === nearestShop.address) {
        console.log(`[GPS-Check] Already notified ${maskPhone(phone)} for ${nearestShop.address} today`);
        return res.json({ success: true, notified: false, reason: 'already_notified' });
      }

      // 6. Отправляем push-уведомление
      const title = 'Не забудьте отметиться!';
      const body = `Я Вас вижу на магазине ${nearestShop.name || nearestShop.address}`;

      if (sendPushToPhone) {
        try {
          await sendPushToPhone(phone, title, body, {
            type: 'attendance_reminder',
            shopAddress: nearestShop.address
          });
          console.log(`[GPS-Check] Push sent to ${maskPhone(phone)} for ${nearestShop.address}`);
        } catch (e) {
          console.error('[GPS-Check] Error sending push:', e.message);
        }
      }

      // 7. Записываем в кэш
      gpsNotificationCache.set(cacheKey, {
        shopAddress: nearestShop.address,
        notifiedAt: new Date().toISOString()
      });

      res.json({
        success: true,
        notified: true,
        shop: nearestShop.address,
        shopName: nearestShop.name,
        distance: Math.round(minDistance)
      });

    } catch (error) {
      console.error('[GPS-Check] Error:', error);
      res.json({ success: true, notified: false, reason: 'error' });
    }
  });

  console.log('✅ Attendance API initialized');
}

module.exports = { setupAttendanceAPI, loadShopSettings, checkShiftTime, calculateLateMinutes, createLatePenalty, createOnTimeBonus, camelToDbAttendance, dbAttendanceToCamel };

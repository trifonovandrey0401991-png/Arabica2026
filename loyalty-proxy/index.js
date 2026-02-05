const express = require('express');
const http = require('http');
const fetch = require('node-fetch');
const bodyParser = require('body-parser');
const cors = require('cors');
const multer = require('multer');
const fs = require('fs');
const fsp = require('fs').promises;
const path = require('path');

// ============================================
// ASYNC HELPERS (for sync->async refactoring)
// ============================================
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function ensureDir(dirPath) {
  if (!(await fileExists(dirPath))) {
    await fsp.mkdir(dirPath, { recursive: true });
  }
}
const { exec, spawn } = require('child_process');
const util = require('util');
const ordersModule = require('./modules/orders');
const execPromise = util.promisify(exec);
const { preloadAdminCache, invalidateCache } = require('./utils/admin_cache');
const { createPaginatedResponse, isPaginationRequested } = require('./utils/pagination');
const DATA_DIR = process.env.DATA_DIR || '/var/www';


// ============================================
// SECURITY: Global Error Handlers
// ============================================
// Предотвращение падения сервера от неотловленных Promise rejection
process.on('unhandledRejection', (reason, promise) => {
  console.error('⚠️ UNHANDLED REJECTION:', reason);
  console.error('Promise:', promise);
  // Не завершаем процесс, просто логируем
});

// Предотвращение падения сервера от неотловленных исключений
process.on('uncaughtException', (error) => {
  console.error('🚨 UNCAUGHT EXCEPTION:', error);
  // Для критических ошибок лучше перезапустить через PM2
  // process.exit(1);
});

// Логируем предупреждения
process.on('warning', (warning) => {
  console.warn('⚠️ NODE WARNING:', warning.name, warning.message);
});

// Безопасная функция для запуска Python скриптов (защита от Command Injection)
function spawnPython(args) {
  return new Promise((resolve, reject) => {
    const process = spawn('python3', args, {
      stdio: ['pipe', 'pipe', 'pipe']
    });

    let stdout = '';
    let stderr = '';

    process.stdout.on('data', (data) => { stdout += data.toString(); });
    process.stderr.on('data', (data) => { stderr += data.toString(); });

    process.on('close', (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        reject(new Error(`Python script exited with code ${code}: ${stderr}`));
      }
    });

    process.on('error', (err) => {
      reject(err);
    });
  });
}
const setupJobApplicationsAPI = require('./job_applications_api');

const setupRecountPointsAPI = require("./recount_points_api");
const app = express();
const setupRatingWheelAPI = require("./rating_wheel_api");
const setupReferralsAPI = require("./referrals_api");
const { invalidateStatsCache, checkReferralLimit } = require("./referrals_api");
const { setupTasksAPI } = require("./tasks_api");
const { setupRecurringTasksAPI } = require("./recurring_tasks_api");
const { setupReportNotificationsAPI, sendPushNotification, sendPushToPhone } = require("./report_notifications_api");
const { setupClientsAPI } = require("./api/clients_api");
const { setupShiftTransfersAPI } = require("./api/shift_transfers_api");
const { setupTaskPointsSettingsAPI } = require("./api/task_points_settings_api");
const { setupPointsSettingsAPI, calculateRecountPoints, calculateShiftPoints } = require("./api/points_settings_api");
const { setupManagerEfficiencyAPI } = require("./api/manager_efficiency_api");
const { setupProductQuestionsAPI } = require("./api/product_questions_api");
const { setupProductQuestionsPenaltyScheduler } = require("./product_questions_penalty_scheduler");
const { setupOrderTimeoutAPI } = require("./order_timeout_api");
const { startShiftAutomationScheduler } = require("./api/shift_automation_scheduler");
const { startRecountAutomationScheduler } = require("./api/recount_automation_scheduler");
const { startRkoAutomationScheduler, getPendingReports: getPendingRkoReports, getFailedReports: getFailedRkoReports } = require("./api/rko_automation_scheduler");
const { startShiftHandoverAutomationScheduler, getPendingReports: getPendingShiftHandoverReports, getFailedReports: getFailedShiftHandoverReports, markPendingAsCompleted: markShiftHandoverPendingCompleted, sendAdminNewReportNotification: sendShiftHandoverNewReportNotification } = require("./api/shift_handover_automation_scheduler");
const { startAttendanceAutomationScheduler, getPendingReports: getPendingAttendanceReports, getFailedReports: getFailedAttendanceReports, canMarkAttendance, markPendingAsCompleted: markAttendancePendingCompleted } = require("./api/attendance_automation_scheduler");
const { startScheduler: startEnvelopeAutomationScheduler } = require("./api/envelope_automation_scheduler");
const { setupZReportAPI } = require("./api/z_report_api");
const { setupCigaretteVisionAPI } = require("./api/cigarette_vision_api");
const { setupShiftAiVerificationAPI } = require("./api/shift_ai_verification_api");
const { setupDataCleanupAPI } = require("./api/data_cleanup_api");
const { setupShopProductsAPI } = require("./api/shop_products_api");
const { setupMasterCatalogAPI } = require("./api/master_catalog_api");
const { setupGeofenceAPI } = require("./api/geofence_api");
const { setupEmployeeChatAPI } = require("./api/employee_chat_api");
const { setupChatWebSocket } = require("./api/employee_chat_websocket");
const { setupMediaAPI } = require("./api/media_api");
const { setupShopManagersAPI } = require("./api/shop_managers_api");
const { setupLoyaltyGamificationAPI } = require("./api/loyalty_gamification_api");
const authApiRouter = require("./api/auth_api");
const telegramBotService = require("./services/telegram_bot_service");

// ============================================
// SECURITY: API Key Authentication
// ============================================
// Генерация ключа: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
const API_KEY = process.env.API_KEY || null;
const API_KEY_ENABLED = process.env.API_KEY_ENABLED === 'true';

// Публичные endpoints которые не требуют аутентификации
const PUBLIC_ENDPOINTS = [
  '/health',
  '/',           // Proxy для Google Apps Script (регистрация, лояльность)
  '/upload-photo', // Загрузка фото (временно публичный)
  '/api/auth',   // Авторизация (регистрация, вход, сброс PIN)
];

const apiKeyMiddleware = (req, res, next) => {
  // Если аутентификация отключена - пропускаем
  if (!API_KEY_ENABLED || !API_KEY) {
    return next();
  }

  // Проверяем публичные endpoints
  if (PUBLIC_ENDPOINTS.some(ep => req.path === ep || req.path.startsWith(ep))) {
    return next();
  }

  // Проверяем API ключ
  const providedKey = req.headers['x-api-key'];
  if (!providedKey) {
    console.warn(`⚠️ API request without key: ${req.method} ${req.path}`);
    return res.status(401).json({
      success: false,
      error: 'API key required. Add X-API-Key header.'
    });
  }

  if (providedKey !== API_KEY) {
    console.warn(`⚠️ Invalid API key: ${req.method} ${req.path}`);
    return res.status(403).json({
      success: false,
      error: 'Invalid API key'
    });
  }

  next();
};

// Применяем middleware (только если включено)
if (API_KEY_ENABLED && API_KEY) {
  console.log('✅ API Key authentication ENABLED');
} else {
  console.log('⚠️ API Key authentication DISABLED (set API_KEY and API_KEY_ENABLED=true to enable)');
}

// Rate Limiting - защита от DDoS и brute-force атак
let rateLimit;
try {
  rateLimit = require('express-rate-limit');
} catch (e) {
  console.warn('⚠️ express-rate-limit не установлен. Rate limiting отключён.');
  rateLimit = null;
}

// Security Headers (helmet) - защита от XSS, clickjacking и др.
let helmet;
try {
  helmet = require('helmet');
} catch (e) {
  console.warn('⚠️ helmet не установлен. Security headers отключены.');
  helmet = null;
}

app.use(bodyParser.json({ limit: "50mb" }));

// Применяем Security Headers если helmet установлен
if (helmet) {
  app.use(helmet({
    contentSecurityPolicy: false, // Отключаем CSP для API (нет HTML)
    crossOriginEmbedderPolicy: false, // Для совместимости с мобильными приложениями
    crossOriginResourcePolicy: { policy: "cross-origin" }, // Разрешаем загрузку ресурсов
  }));
  console.log('✅ Security Headers (helmet) активированы');
}

// CORS - ограничиваем разрешённые источники
const corsOptions = {
  origin: function (origin, callback) {
    // Разрешаем запросы без origin (мобильные приложения, curl, Postman)
    if (!origin) return callback(null, true);

    // Разрешённые домены
    const allowedOrigins = [
      'https://arabica26.ru',
      'http://arabica26.ru',
      'http://localhost:3000',
      'http://localhost:8080',
      'http://127.0.0.1:3000',
    ];

    if (allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      console.warn(`⚠️ CORS blocked origin: ${origin}`);
      callback(new Error('Not allowed by CORS'), false);
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'X-API-Key'],
};
app.use(cors(corsOptions));

// GZIP/Deflate сжатие для уменьшения размера ответов
// Критично для /api/master-catalog/for-training (10MB → ~1MB)
let compression;
try {
  compression = require('compression');
  app.use(compression({
    filter: (req, res) => {
      // Сжимаем JSON ответы
      if (req.headers['x-no-compression']) return false;
      return compression.filter(req, res);
    },
    level: 6, // Баланс скорости и сжатия (1-9)
    threshold: 1024, // Сжимать ответы > 1KB
  }));
  console.log('✅ GZIP compression активировано');
} catch (e) {
  console.warn('⚠️ compression не установлен. Сжатие отключено. npm install compression');
}

// Trust proxy для корректной работы за nginx/reverse proxy
app.set('trust proxy', 1);

// Применяем API Key middleware
app.use(apiKeyMiddleware);

// Применяем Rate Limiting если пакет установлен
if (rateLimit) {
  // Общий лимит: 500 запросов в минуту с одного IP
  // Увеличено с 100 т.к. приложение делает много параллельных запросов
  // (сотрудники + регистрации + магазины + настройки)
  const generalLimiter = rateLimit({
    windowMs: 60 * 1000, // 1 минута
    max: 500,
    message: { success: false, error: 'Слишком много запросов. Попробуйте позже.' },
    standardHeaders: true,
    legacyHeaders: false,
    validate: { xForwardedForHeader: false }, // Отключаем валидацию т.к. trust proxy включен
  });

  // Умеренный лимит для финансовых endpoints: 50 запросов в минуту
  // Увеличено с 10 т.к. приложение загружает список + создаёт записи
  const financialLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 50,
    message: { success: false, error: 'Превышен лимит запросов. Подождите минуту.' },
    standardHeaders: true,
    legacyHeaders: false,
    validate: { xForwardedForHeader: false },
  });

  // Применяем общий лимит ко всем /api/* маршрутам
  app.use('/api/', generalLimiter);

  // Умеренный лимит для финансовых операций
  app.use('/api/withdrawals', financialLimiter);
  app.use('/api/bonus-penalties', financialLimiter);
  app.use('/api/rko', financialLimiter);

  console.log('✅ Rate Limiting активирован: 500 req/min (общий), 50 req/min (финансовые операции)');
}

// Статические файлы для редактора координат
app.use('/static', express.static(`${DATA_DIR}/html`));

// ============================================
// SECURITY: File Type Validation для всех uploads
// ============================================
// Добавлен application/octet-stream для поддержки загрузки из Flutter (камера иногда не передаёт MIME type)
const allowedImageTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'application/octet-stream'];
const allowedMediaTypes = [...allowedImageTypes, 'video/mp4', 'video/quicktime'];

const imageFileFilter = (req, file, cb) => {
  if (allowedImageTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error(`Invalid file type: ${file.mimetype}. Only JPEG, PNG, GIF, WebP allowed.`), false);
  }
};

const mediaFileFilter = (req, file, cb) => {
  if (allowedMediaTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error(`Invalid file type: ${file.mimetype}. Only images and videos allowed.`), false);
  }
};

// ============================================
// SECURITY: Path Traversal Protection
// ============================================
/**
 * Sanitize ID to prevent path traversal attacks
 * Removes any characters that could be used for directory traversal
 * @param {string} id - The ID to sanitize
 * @returns {string} - Sanitized ID safe for file paths
 */
function sanitizeId(id) {
  if (!id || typeof id !== 'string') return '';
  // Remove path traversal characters and keep only safe chars
  return id.replace(/[^a-zA-Z0-9_\-\.]/g, '_');
}

/**
 * Validate that resolved path stays within base directory
 * @param {string} baseDir - Base directory path
 * @param {string} filePath - Full file path to validate
 * @returns {boolean} - True if path is safe
 */
function isPathSafe(baseDir, filePath) {
  const resolvedBase = path.resolve(baseDir);
  const resolvedPath = path.resolve(filePath);
  return resolvedPath.startsWith(resolvedBase);
}

// Настройка multer для загрузки фото
const storage = multer.diskStorage({
  destination: async function (req, file, cb) {
    const uploadDir = `${DATA_DIR}/shift-photos`;
    // Создаем директорию, если её нет
    if (!await fileExists(uploadDir)) {
      await fsp.mkdir(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    // SECURITY: Защита от path traversal
    const originalName = Buffer.from(file.originalname, 'latin1').toString('utf8');
    // Удаляем любые символы пути и оставляем только безопасные символы
    const safeName = path.basename(originalName).replace(/[^a-zA-Z0-9_\-\.а-яА-ЯёЁ]/g, '_');
    // Добавляем timestamp для уникальности
    const uniqueName = `${Date.now()}_${safeName}`;
    cb(null, uniqueName);
  }
});

const upload = multer({
  storage: storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: imageFileFilter
});

// Настройка multer для загрузки эталонных фото сдачи смены
const shiftHandoverPhotoStorage = multer.diskStorage({
  destination: async function (req, file, cb) {
    const uploadDir = `${DATA_DIR}/shift-handover-question-photos`;
    // Создаем директорию, если её нет
    if (!await fileExists(uploadDir)) {
      await fsp.mkdir(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    // SECURITY: Защита от path traversal
    const originalName = Buffer.from(file.originalname, 'latin1').toString('utf8');
    const safeName = path.basename(originalName).replace(/[^a-zA-Z0-9_\-\.а-яА-ЯёЁ]/g, '_');
    const uniqueName = `${Date.now()}_${safeName}`;
    cb(null, uniqueName);
  }
});

const uploadShiftHandoverPhoto = multer({
  storage: shiftHandoverPhotoStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: imageFileFilter
});

// Настройка multer для загрузки фото вопросов о товарах
const productQuestionPhotoStorage = multer.diskStorage({
  destination: async function (req, file, cb) {
    const uploadDir = `${DATA_DIR}/product-question-photos`;
    // Создаем директорию, если её нет
    if (!await fileExists(uploadDir)) {
      await fsp.mkdir(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    // SECURITY: Защита от path traversal
    const timestamp = Date.now();
    const originalName = path.basename(file.originalname).replace(/[^a-zA-Z0-9_\-\.а-яА-ЯёЁ]/g, '_');
    const safeName = `product_question_${timestamp}_${originalName}`;
    cb(null, safeName);
  }
});

const uploadProductQuestionPhoto = multer({
  storage: productQuestionPhotoStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: imageFileFilter
});

// Настройка multer для загрузки медиа в чате
const chatMediaStorage = multer.diskStorage({
  destination: async (req, file, cb) => {
    const uploadDir = `${DATA_DIR}/chat-media`;
    if (!await fileExists(uploadDir)) {
      await fsp.mkdir(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const timestamp = Date.now();
    // SECURITY: Безопасное извлечение расширения
    const safeBasename = path.basename(file.originalname);
    const ext = (safeBasename.split('.').pop() || 'jpg').replace(/[^a-zA-Z0-9]/g, '');
    const safeName = `chat_${timestamp}_${Math.random().toString(36).substr(2, 9)}.${ext}`;
    cb(null, safeName);
  }
});

const uploadChatMedia = multer({
  storage: chatMediaStorage,
  limits: { fileSize: 20 * 1024 * 1024 }, // 20MB
  fileFilter: mediaFileFilter
});

// URL Google Apps Script для регистрации, лояльности и ролей
const SCRIPT_URL = process.env.SCRIPT_URL || "https://script.google.com/macros/s/AKfycbzaH6AqH8j9E93Tf4SFCie35oeESGfBL6p51cTHl9EvKq0Y5bfzg4UbmsDKB1B82yPS/exec";

app.post('/', async (req, res) => {
  try {
    console.log("POST request to script:", SCRIPT_URL);
    console.log("Request body:", JSON.stringify(req.body));
    
    const response = await fetch(SCRIPT_URL, {
      method: 'post',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body),
    });

    const contentType = response.headers.get('content-type');
    console.log("Response status:", response.status);
    console.log("Response content-type:", contentType);

    if (!contentType || !contentType.includes('application/json')) {
      const text = await response.text();
      console.error("Non-JSON response received:", text.substring(0, 200));
      throw new Error(`Сервер вернул HTML вместо JSON. Проверьте URL сервера: ${SCRIPT_URL}`);
    }

    const data = await response.json();
    res.json(data);
  } catch (error) {
    console.error("POST error:", error);
    res.status(500).json({ 
      success: false, 
      error: error.message || 'Ошибка при обращении к серверу'
    });
  }
});

app.get('/', async (req, res) => {
  try {
    console.log("GET request:", req.query);
    const queryString = new URLSearchParams(req.query).toString();
    const url = `${SCRIPT_URL}?${queryString}`;

    const response = await fetch(url);
    
    const contentType = response.headers.get('content-type');
    console.log("Response status:", response.status);
    console.log("Response content-type:", contentType);

    if (!contentType || !contentType.includes('application/json')) {
      const text = await response.text();
      console.error("Non-JSON response received:", text.substring(0, 200));
      throw new Error(`Сервер вернул HTML вместо JSON. Проверьте URL сервера: ${SCRIPT_URL}`);
    }

    const data = await response.json();
    res.json(data);
  } catch (error) {
    console.error("GET error:", error);
    res.status(500).json({ 
      success: false, 
      error: error.message || 'Ошибка при обращении к серверу'
    });
  }
});

// Эндпоинт для загрузки фото
app.post('/upload-photo', upload.single('file'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'Файл не загружен' });
    }

    const fileUrl = `https://arabica26.ru/shift-photos/${req.file.filename}`;
    console.log('Фото загружено:', req.file.filename);
    
    res.json({
      success: true,
      url: fileUrl,
      filePath: fileUrl, // Для совместимости с Flutter кодом
      filename: req.file.filename
    });
  } catch (error) {
    console.error('Ошибка загрузки фото:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Эндпоинт для создания отчета пересчета с TIME_EXPIRED валидацией
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

      // Получаем московское время (UTC+3)
      const now = new Date();
      const moscowTime = new Date(now.getTime() + 3 * 60 * 60 * 1000);
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
      } catch (e) {}
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

    try {
      await fsp.writeFile(reportFile, JSON.stringify(reportData, null, 2), 'utf8');
      console.log('✅ Отчет пересчёта сохранен:', reportFile);
    } catch (writeError) {
      console.error('Ошибка записи файла:', writeError);
      throw writeError;
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

// Эндпоинт для получения отчетов пересчета
app.get('/api/recount-reports', async (req, res) => {
  try {
    console.log('GET /api/recount-reports:', req.query);
    
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
      
      return res.json({ success: true, reports: filteredReports });
    }
    
    // Если директории нет, возвращаем пустой список
    res.json({ success: true, reports: [] });
  } catch (error) {
    console.error('Ошибка получения отчетов:', error);
    res.json({ success: true, reports: [] });
  }
});

// Эндпоинт для получения просроченных/failed/rejected отчетов пересчета
app.get('/api/recount-reports/expired', async (req, res) => {
  try {
    console.log('GET /api/recount-reports/expired');

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

// Эндпоинт для получения ожидающих (pending) пересчётов
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

// Эндпоинт для оценки отчета пересчёта
app.post('/api/recount-reports/:reportId/rating', async (req, res) => {
  try {
    let { reportId } = req.params;
    const { rating, adminName } = req.body;
    // Декодируем URL-кодированный reportId
    reportId = decodeURIComponent(reportId);
    // Санитизируем имя файла (как при сохранении)
    const sanitizedId = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    console.log(`POST /api/recount-reports/${reportId}/rating:`, req.body);
    console.log(`Санитизированный ID: ${sanitizedId}`);

    const reportsDir = `${DATA_DIR}/recount-reports`;
    let reportFile = path.join(reportsDir, `${sanitizedId}.json`);
    let actualFile = reportFile;

    if (!await fileExists(reportFile)) {
      console.error(`Файл не найден: ${reportFile}`);
      // Попробуем найти файл по частичному совпадению
      const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));
      const matchingFile = files.find(f => f.includes(sanitizedId.substring(0, 20)));
      if (matchingFile) {
        console.log(`Найден файл по частичному совпадению: ${matchingFile}`);
        actualFile = path.join(reportsDir, matchingFile);
      } else {
        return res.status(404).json({ success: false, error: 'Отчет не найден' });
      }
    }

    // Читаем отчет
    const content = await fsp.readFile(actualFile, 'utf8');
    const report = JSON.parse(content);

    // Обновляем оценку и статус
    report.adminRating = rating;
    report.adminName = adminName;
    report.ratedAt = new Date().toISOString();
    report.status = 'confirmed';

    // Сохраняем обновленный отчет
    await fsp.writeFile(actualFile, JSON.stringify(report, null, 2), 'utf8');
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
    const efficiencyPoints = calculateRecountPoints(rating, settings);
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
    }

    // Проверяем дубликат
    const sourceId = `recount_rating_${reportId}`;
    const exists = penalties.some(p => p.sourceId === sourceId);
    if (!exists) {
      const penalty = {
        id: `ep_${Date.now()}`,
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
      await fsp.writeFile(penaltiesFile, JSON.stringify(penalties, null, 2), 'utf8');
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

// Эндпоинт для отправки push-уведомления
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

// Статическая раздача фото
app.use('/shift-photos', express.static(`${DATA_DIR}/shift-photos`));
app.use('/product-question-photos', express.static(`${DATA_DIR}/product-question-photos`));

// ============================================
// Вспомогательные функции для проверки времени смены
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
  const hour = time.getHours();
  const minute = time.getMinutes();
  const currentMinutes = hour * 60 + minute;

  console.log(`Проверка времени: ${hour}:${minute} (${currentMinutes} минут)`);

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
  const currentMinutes = time.getHours() * 60 + time.getMinutes();

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
    const now = new Date();
    const monthKey = now.toISOString().slice(0, 7); // YYYY-MM

    // Загружаем настройки баллов
    const pointsSettings = loadAttendancePointsSettings();
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
    }

    penalties.push(penaltyRecord);
    await fsp.writeFile(penaltiesFile, JSON.stringify(penalties, null, 2), 'utf8');

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
    const now = new Date();
    const monthKey = now.toISOString().slice(0, 7); // YYYY-MM

    // Загружаем настройки баллов
    const pointsSettings = loadAttendancePointsSettings();
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
    await fsp.writeFile(penaltiesFile, JSON.stringify(penalties, null, 2), 'utf8');

    console.log(`Бонус создан: +${bonus} баллов за своевременный приход для ${employeeName}`);
    return bonusRecord;
  } catch (error) {
    console.error('Ошибка создания бонуса:', error);
    return null;
  }
}

// Эндпоинт для отметки прихода
app.post('/api/attendance', async (req, res) => {
  try {
    console.log('POST /api/attendance:', JSON.stringify(req.body).substring(0, 200));

    // Проверяем есть ли pending отчёт для этого магазина
    const canMark = canMarkAttendance(req.body.shopAddress);
    if (!canMark) {
      console.log('Отметка отклонена: нет pending отчёта для', req.body.shopAddress);
      return res.status(400).json({
        success: false,
        error: 'Сейчас не время для отметки. Подождите начала смены.',
        cannotMark: true
      });
    }

    const attendanceDir = `${DATA_DIR}/attendance`;
    if (!await fileExists(attendanceDir)) {
      await fsp.mkdir(attendanceDir, { recursive: true });
    }

    const recordId = req.body.id || `attendance_${Date.now()}`;
    const sanitizedId = recordId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const recordFile = path.join(attendanceDir, `${sanitizedId}.json`);

    // Загружаем настройки магазина
    const shopSettings = loadShopSettings(req.body.shopAddress);

    // Проверяем время по интервалам смен
    const checkResult = checkShiftTime(req.body.timestamp, shopSettings);

    const recordData = {
      ...req.body,
      isOnTime: checkResult.isOnTime,
      shiftType: checkResult.shiftType,
      lateMinutes: checkResult.lateMinutes,
      createdAt: new Date().toISOString(),
    };

    await fsp.writeFile(recordFile, JSON.stringify(recordData, null, 2), 'utf8');
    console.log('Отметка сохранена:', recordFile);

    // Удаляем pending отчёт после успешной отметки
    markAttendancePendingCompleted(req.body.shopAddress, checkResult.shiftType);

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
      createOnTimeBonus(req.body.employeeName, req.body.shopAddress, checkResult.shiftType);
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

// Эндпоинт для подтверждения выбора смены
app.post('/api/attendance/confirm-shift', async (req, res) => {
  try {
    console.log('POST /api/attendance/confirm-shift:', JSON.stringify(req.body));

    const { recordId, selectedShift } = req.body;

    if (!recordId || !selectedShift) {
      return res.status(400).json({
        success: false,
        error: 'Отсутствуют обязательные поля: recordId, selectedShift'
      });
    }

    const attendanceDir = `${DATA_DIR}/attendance`;
    const sanitizedId = recordId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const recordFile = path.join(attendanceDir, `${sanitizedId}.json`);

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
    const shopSettings = loadShopSettings(record.shopAddress);

    // Вычисляем опоздание
    const lateMinutes = calculateLateMinutes(record.timestamp, selectedShift, shopSettings);

    // Обновляем запись
    record.shiftType = selectedShift;
    record.isOnTime = lateMinutes === 0;
    record.lateMinutes = lateMinutes;
    record.confirmedAt = new Date().toISOString();

    await fsp.writeFile(recordFile, JSON.stringify(record, null, 2), 'utf8');

    // Если опоздал - создаём штраф
    let penaltyCreated = false;
    if (lateMinutes > 0) {
      const penalty = createLatePenalty(record.employeeName, record.shopAddress, lateMinutes, selectedShift);
      penaltyCreated = penalty !== null;
    } else {
      // Если пришёл вовремя - создаём бонус
      createOnTimeBonus(record.employeeName, record.shopAddress, selectedShift);
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

// Эндпоинт для проверки отметки сегодня
app.get('/api/attendance/check', async (req, res) => {
  try {
    const employeeName = req.query.employeeName;
    if (!employeeName) {
      return res.json({ success: true, hasAttendance: false });
    }
    
    const attendanceDir = `${DATA_DIR}/attendance`;
    if (!await fileExists(attendanceDir)) {
      return res.json({ success: true, hasAttendance: false });
    }
    
    const today = new Date();
    const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    
    const files = (await fsp.readdir(attendanceDir)).filter(f => f.endsWith('.json'));
    for (const file of files) {
      try {
        const filePath = path.join(attendanceDir, file);
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

// Эндпоинт для получения списка отметок
app.get('/api/attendance', async (req, res) => {
  try {
    console.log('GET /api/attendance:', req.query);
    
    const attendanceDir = `${DATA_DIR}/attendance`;
    const records = [];
    
    if (await fileExists(attendanceDir)) {
      const files = (await fsp.readdir(attendanceDir)).filter(f => f.endsWith('.json'));
      
      for (const file of files) {
        try {
          const filePath = path.join(attendanceDir, file);
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
      
      return res.json({ success: true, records: filteredRecords });
    }
    
    res.json({ success: true, records: [] });
  } catch (error) {
    console.error('Ошибка получения отметок:', error);
    res.json({ success: true, records: [] });
  }
});

// Настройка multer для загрузки фото сотрудников
const employeePhotoStorage = multer.diskStorage({
  destination: async function (req, file, cb) {
    const uploadDir = `${DATA_DIR}/employee-photos`;
    if (!await fileExists(uploadDir)) {
      await fsp.mkdir(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    // SECURITY: Sanitize phone and photoType to prevent path traversal
    const phone = (req.body.phone || 'unknown').replace(/[^a-zA-Z0-9_\-\+]/g, '_');
    const photoType = (req.body.photoType || 'photo').replace(/[^a-zA-Z0-9_\-]/g, '_');
    const safeName = `${phone}_${photoType}.jpg`;
    cb(null, safeName);
  }
});

const uploadEmployeePhoto = multer({
  storage: employeePhotoStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: imageFileFilter
});

// Эндпоинт для загрузки фото сотрудника
app.post('/upload-employee-photo', uploadEmployeePhoto.single('file'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'Файл не загружен' });
    }

    const fileUrl = `https://arabica26.ru/employee-photos/${req.file.filename}`;
    console.log('Фото сотрудника загружено:', req.file.filename);
    
    res.json({
      success: true,
      url: fileUrl,
      filename: req.file.filename
    });
  } catch (error) {
    console.error('Ошибка загрузки фото сотрудника:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Эндпоинт для сохранения регистрации сотрудника
app.post('/api/employee-registration', async (req, res) => {
  try {
    console.log('POST /api/employee-registration:', JSON.stringify(req.body).substring(0, 200));
    
    const registrationDir = `${DATA_DIR}/employee-registrations`;
    if (!await fileExists(registrationDir)) {
      await fsp.mkdir(registrationDir, { recursive: true });
    }
    
    const phone = req.body.phone;
    if (!phone) {
      return res.status(400).json({ success: false, error: 'Телефон не указан' });
    }
    
    // Санитизируем телефон для имени файла
    const sanitizedPhone = phone.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const registrationFile = path.join(registrationDir, `${sanitizedPhone}.json`);
    
    // Сохраняем регистрацию
    const registrationData = {
      ...req.body,
      updatedAt: new Date().toISOString(),
    };
    
    // Если файл существует, сохраняем createdAt из старого файла
    if (await fileExists(registrationFile)) {
      try {
        const oldContent = await fsp.readFile(registrationFile, 'utf8');
        const oldData = JSON.parse(oldContent);
        if (oldData.createdAt) {
          registrationData.createdAt = oldData.createdAt;
        }
      } catch (e) {
        console.error('Ошибка чтения старого файла:', e);
      }
    } else {
      registrationData.createdAt = new Date().toISOString();
    }
    
    await fsp.writeFile(registrationFile, JSON.stringify(registrationData, null, 2), 'utf8');
    console.log('Регистрация сохранена:', registrationFile);
    
    res.json({
      success: true,
      message: 'Регистрация успешно сохранена'
    });
  } catch (error) {
    console.error('Ошибка сохранения регистрации:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при сохранении регистрации'
    });
  }
});

// Эндпоинт для получения регистрации по телефону
app.get('/api/employee-registration/:phone', async (req, res) => {
  try {
    const phone = decodeURIComponent(req.params.phone);
    console.log('GET /api/employee-registration:', phone);
    
    const registrationDir = `${DATA_DIR}/employee-registrations`;
    const sanitizedPhone = phone.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const registrationFile = path.join(registrationDir, `${sanitizedPhone}.json`);
    
    if (!await fileExists(registrationFile)) {
      return res.json({ success: true, registration: null });
    }
    
    const content = await fsp.readFile(registrationFile, 'utf8');
    const registration = JSON.parse(content);
    
    res.json({ success: true, registration });
  } catch (error) {
    console.error('Ошибка получения регистрации:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении регистрации'
    });
  }
});

// Эндпоинт для верификации/снятия верификации сотрудника
app.post('/api/employee-registration/:phone/verify', async (req, res) => {
  try {
    const phone = decodeURIComponent(req.params.phone);
    const { isVerified, verifiedBy } = req.body;
    console.log('POST /api/employee-registration/:phone/verify:', phone, isVerified);
    
    const registrationDir = `${DATA_DIR}/employee-registrations`;
    const sanitizedPhone = phone.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const registrationFile = path.join(registrationDir, `${sanitizedPhone}.json`);
    
    if (!await fileExists(registrationFile)) {
      return res.status(404).json({
        success: false,
        error: 'Регистрация не найдена'
      });
    }
    
    const content = await fsp.readFile(registrationFile, 'utf8');
    const registration = JSON.parse(content);
    
    registration.isVerified = isVerified === true;
    // Сохраняем дату первой верификации, даже если верификация снята
    // Это нужно для отображения в списке "Не верифицированных сотрудников"
    if (isVerified) {
      // Верификация - устанавливаем дату, если её еще нет
      if (!registration.verifiedAt) {
        registration.verifiedAt = new Date().toISOString();
      }
      registration.verifiedBy = verifiedBy;
    } else {
      // Снятие верификации - устанавливаем дату, если её еще нет
      // Это нужно для отображения в списке "Не верифицированных сотрудников"
      if (!registration.verifiedAt) {
        registration.verifiedAt = new Date().toISOString();
      }
      // verifiedAt остается с датой (первой верификации или текущей датой при снятии)
      registration.verifiedBy = null;
    }
    registration.updatedAt = new Date().toISOString();
    
    await fsp.writeFile(registrationFile, JSON.stringify(registration, null, 2), 'utf8');
    console.log('Статус верификации обновлен:', registrationFile);

    // Если верификация снята - отправляем push уведомление сотруднику
    // чтобы приложение заблокировалось и потребовало перезапуск
    if (!isVerified) {
      try {
        await sendPushToPhone(
          phone,
          'Верификация отозвана',
          'Ваша верификация была отозвана администратором. Пожалуйста, перезапустите приложение.',
          { type: 'verification_revoked' }
        );
        console.log('Push-уведомление о снятии верификации отправлено:', phone);
      } catch (pushError) {
        console.error('Ошибка отправки push при снятии верификации:', pushError);
        // Не блокируем основную операцию из-за ошибки push
      }
    }

    res.json({
      success: true,
      message: isVerified ? 'Сотрудник верифицирован' : 'Верификация снята'
    });
  } catch (error) {
    console.error('Ошибка верификации:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при верификации'
    });
  }
});

// Эндпоинт для получения всех регистраций (для админа)
app.get('/api/employee-registrations', async (req, res) => {
  try {
    console.log('GET /api/employee-registrations');
    
    const registrationDir = `${DATA_DIR}/employee-registrations`;
    const registrations = [];
    
    if (await fileExists(registrationDir)) {
      const files = (await fsp.readdir(registrationDir)).filter(f => f.endsWith('.json'));
      
      for (const file of files) {
        try {
          const filePath = path.join(registrationDir, file);
          const content = await fsp.readFile(filePath, 'utf8');
          const registration = JSON.parse(content);
          registrations.push(registration);
        } catch (e) {
          console.error(`Ошибка чтения файла ${file}:`, e);
        }
      }
      
      // Сортируем по дате создания (новые первыми)
      registrations.sort((a, b) => {
        const dateA = new Date(a.createdAt || 0);
        const dateB = new Date(b.createdAt || 0);
        return dateB - dateA;
      });
    }
    
    res.json({ success: true, registrations });
  } catch (error) {
    console.error('Ошибка получения регистраций:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении регистраций'
    });
  }
});

// ========== API для сотрудников ==========

const EMPLOYEES_DIR = `${DATA_DIR}/employees`;

// GET /api/employees - получить всех сотрудников
app.get('/api/employees', async (req, res) => {
  try {
    console.log('GET /api/employees');

    let employees = [];

    if (!await fileExists(EMPLOYEES_DIR)) {
      await fsp.mkdir(EMPLOYEES_DIR, { recursive: true });
    }

    const files = (await fsp.readdir(EMPLOYEES_DIR)).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const filePath = path.join(EMPLOYEES_DIR, file);
        const content = await fsp.readFile(filePath, 'utf8');
        const employee = JSON.parse(content);
        employees.push(employee);
      } catch (e) {
        console.error(`Ошибка чтения файла ${file}:`, e);
      }
    }

    // SCALABILITY: Поддержка поиска по имени/телефону
    const { search } = req.query;
    if (search) {
      const searchLower = search.toLowerCase();
      employees = employees.filter(e =>
        (e.name && e.name.toLowerCase().includes(searchLower)) ||
        (e.phone && e.phone.includes(search)) ||
        (e.position && e.position.toLowerCase().includes(searchLower))
      );
    }

    // Сортируем по дате создания (новые первыми)
    employees.sort((a, b) => {
      const dateA = new Date(a.createdAt || 0);
      const dateB = new Date(b.createdAt || 0);
      return dateB - dateA;
    });

    // SCALABILITY: Пагинация если запрошена
    if (isPaginationRequested(req.query)) {
      res.json(createPaginatedResponse(employees, req.query, 'employees'));
    } else {
      // Backwards compatibility - возвращаем все без пагинации
      res.json({ success: true, employees });
    }
  } catch (error) {
    console.error('Ошибка получения сотрудников:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/employees/:id - получить сотрудника по ID
app.get('/api/employees/:id', async (req, res) => {
  try {
    const id = req.params.id;
    console.log('GET /api/employees:', id);
    
    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const employeeFile = path.join(EMPLOYEES_DIR, `${sanitizedId}.json`);
    
    if (!await fileExists(employeeFile)) {
      return res.status(404).json({
        success: false,
        error: 'Сотрудник не найден'
      });
    }
    
    const content = await fsp.readFile(employeeFile, 'utf8');
    const employee = JSON.parse(content);
    
    res.json({ success: true, employee });
  } catch (error) {
    console.error('Ошибка получения сотрудника:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Получить следующий свободный referralCode
async function getNextReferralCode() {
  try {
    if (!await fileExists(EMPLOYEES_DIR)) return 1;

    const files = (await fsp.readdir(EMPLOYEES_DIR)).filter(f => f.endsWith('.json'));
    const usedCodes = new Set();

    for (const file of files) {
      try {
        const content = await fsp.readFile(path.join(EMPLOYEES_DIR, file), 'utf8');
        const emp = JSON.parse(content);
        if (emp.referralCode) {
          usedCodes.add(emp.referralCode);
        }
      } catch (e) {}
    }

    for (let code = 1; code <= 1000; code++) {
      if (!usedCodes.has(code)) return code;
    }

    return null;
  } catch (error) {
    console.error('Ошибка получения referralCode:', error);
    return 1;
  }
}

// POST /api/employees - создать нового сотрудника
app.post('/api/employees', async (req, res) => {
  try {
    console.log('POST /api/employees:', JSON.stringify(req.body).substring(0, 200));
    
    if (!await fileExists(EMPLOYEES_DIR)) {
      await fsp.mkdir(EMPLOYEES_DIR, { recursive: true });
    }
    
    // Валидация обязательных полей
    if (!req.body.name || req.body.name.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Имя сотрудника обязательно'
      });
    }
    
    // Генерируем ID если не указан
    const id = req.body.id || `employee_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const employeeFile = path.join(EMPLOYEES_DIR, `${sanitizedId}.json`);
    
    const employee = {
      id: sanitizedId,
      referralCode: req.body.referralCode || getNextReferralCode(),
      name: req.body.name.trim(),
      position: req.body.position || null,
      department: req.body.department || null,
      phone: req.body.phone || null,
      email: req.body.email || null,
      isAdmin: req.body.isAdmin === true || req.body.isAdmin === 'true' || req.body.isAdmin === 1,
      isManager: req.body.isManager === true || req.body.isManager === 'true' || req.body.isManager === 1,
      employeeName: req.body.employeeName || null,
      preferredWorkDays: req.body.preferredWorkDays || [],
      preferredShops: req.body.preferredShops || [],
      shiftPreferences: req.body.shiftPreferences || {},
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    
    await fsp.writeFile(employeeFile, JSON.stringify(employee, null, 2), 'utf8');
    console.log('Сотрудник создан:', employeeFile);

    // SCALABILITY: Инвалидируем кэш isAdmin при создании сотрудника
    if (employee.phone) {
      invalidateCache(employee.phone);
    }

    res.json({ success: true, employee });
  } catch (error) {
    console.error('Ошибка создания сотрудника:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/employees/:id - обновить сотрудника
app.put('/api/employees/:id', async (req, res) => {
  try {
    const id = req.params.id;
    console.log('PUT /api/employees:', id);
    
    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const employeeFile = path.join(EMPLOYEES_DIR, `${sanitizedId}.json`);
    
    if (!await fileExists(employeeFile)) {
      return res.status(404).json({
        success: false,
        error: 'Сотрудник не найден'
      });
    }
    
    // Валидация обязательных полей
    if (!req.body.name || req.body.name.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Имя сотрудника обязательно'
      });
    }
    
    // Читаем существующие данные для сохранения createdAt
    const oldContent = await fsp.readFile(employeeFile, 'utf8');
    const oldEmployee = JSON.parse(oldContent);
    
    const employee = {
      id: sanitizedId,
      referralCode: req.body.referralCode || getNextReferralCode(),
      name: req.body.name.trim(),
      position: req.body.position !== undefined ? req.body.position : oldEmployee.position,
      department: req.body.department !== undefined ? req.body.department : oldEmployee.department,
      phone: req.body.phone !== undefined ? req.body.phone : oldEmployee.phone,
      email: req.body.email !== undefined ? req.body.email : oldEmployee.email,
      isAdmin: req.body.isAdmin !== undefined ? (req.body.isAdmin === true || req.body.isAdmin === 'true' || req.body.isAdmin === 1) : oldEmployee.isAdmin,
      isManager: req.body.isManager !== undefined ? (req.body.isManager === true || req.body.isManager === 'true' || req.body.isManager === 1) : oldEmployee.isManager,
      employeeName: req.body.employeeName !== undefined ? req.body.employeeName : oldEmployee.employeeName,
      preferredWorkDays: req.body.preferredWorkDays !== undefined ? req.body.preferredWorkDays : oldEmployee.preferredWorkDays,
      preferredShops: req.body.preferredShops !== undefined ? req.body.preferredShops : oldEmployee.preferredShops,
      shiftPreferences: req.body.shiftPreferences !== undefined ? req.body.shiftPreferences : oldEmployee.shiftPreferences,
      createdAt: oldEmployee.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    
    await fsp.writeFile(employeeFile, JSON.stringify(employee, null, 2), 'utf8');
    console.log('Сотрудник обновлен:', employeeFile);

    // SCALABILITY: Инвалидируем кэш isAdmin при изменении сотрудника
    invalidateCache(employee.phone);

    res.json({ success: true, employee });
  } catch (error) {
    console.error('Ошибка обновления сотрудника:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/employees/:id - удалить сотрудника
app.delete('/api/employees/:id', async (req, res) => {
  try {
    const id = req.params.id;
    console.log('DELETE /api/employees:', id);

    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const employeeFile = path.join(EMPLOYEES_DIR, `${sanitizedId}.json`);

    if (!await fileExists(employeeFile)) {
      return res.status(404).json({
        success: false,
        error: 'Сотрудник не найден'
      });
    }

    // SCALABILITY: Читаем телефон перед удалением для инвалидации кэша
    let employeePhone = null;
    try {
      const content = await fsp.readFile(employeeFile, 'utf8');
      const employee = JSON.parse(content);
      employeePhone = employee.phone;
    } catch (e) { /* ignore */ }

    await fsp.unlink(employeeFile);
    console.log('Сотрудник удален:', employeeFile);

    // SCALABILITY: Инвалидируем кэш isAdmin при удалении сотрудника
    if (employeePhone) {
      invalidateCache(employeePhone);
    }

    res.json({ success: true, message: 'Сотрудник удален' });
  } catch (error) {
    console.error('Ошибка удаления сотрудника:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ========== API для магазинов ==========

const SHOPS_DIR = `${DATA_DIR}/shops`;

// Дефолтные магазины (создаются при первом запуске)
const DEFAULT_SHOPS = [
  { id: 'shop_1', name: 'Арабика Винсады', address: 'с.Винсады,ул Подгорная 156д (На Выезде)', icon: 'store_outlined', latitude: 44.091173, longitude: 42.952451 },
  { id: 'shop_2', name: 'Арабика Лермонтов', address: 'Лермонтов,ул Пятигорская 19', icon: 'store_outlined', latitude: 44.100923, longitude: 42.967543 },
  { id: 'shop_3', name: 'Арабика Лермонтов (Площадь)', address: 'Лермонтов,Комсомольская 1 (На Площади)', icon: 'store_outlined', latitude: 44.104619, longitude: 42.970543 },
  { id: 'shop_4', name: 'Арабика Лермонтов (Остановка)', address: 'Лермонтов,пр-кт Лермонтова 1стр1 (На Остановке )', icon: 'store_outlined', latitude: 44.105379, longitude: 42.978421 },
  { id: 'shop_5', name: 'Арабика Ессентуки', address: 'Ессентуки , ул пятигорская 149/1 (Золотушка)', icon: 'store_mall_directory_outlined', latitude: 44.055559, longitude: 42.911012 },
  { id: 'shop_6', name: 'Арабика Иноземцево', address: 'Иноземцево , ул Гагарина 1', icon: 'store_outlined', latitude: 44.080153, longitude: 43.081593 },
  { id: 'shop_7', name: 'Арабика Пятигорск (Ромашка)', address: 'Пятигорск, 295-стрелковой дивизии 2А стр1 (ромашка)', icon: 'store_outlined', latitude: 44.061053, longitude: 43.063672 },
  { id: 'shop_8', name: 'Арабика Пятигорск', address: 'Пятигорск,ул Коллективная 26а', icon: 'store_outlined', latitude: 44.032997, longitude: 43.042525 },
];

// Инициализация директории магазинов
async function initShopsDir() {
  if (!await fileExists(SHOPS_DIR)) {
    await fsp.mkdir(SHOPS_DIR, { recursive: true });
    // Создаем дефолтные магазины
    for (const shop of DEFAULT_SHOPS) {
      const shopFile = path.join(SHOPS_DIR, `${shop.id}.json`);
      await fsp.writeFile(shopFile, JSON.stringify(shop, null, 2));
    }
    console.log('✅ Директория магазинов создана с дефолтными данными');
  }
}
initShopsDir();

// GET /api/shops - получить все магазины
app.get('/api/shops', async (req, res) => {
  try {
    console.log('GET /api/shops');

    const shops = [];
    const files = (await fsp.readdir(SHOPS_DIR)).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const content = await fsp.readFile(path.join(SHOPS_DIR, file), 'utf8');
        shops.push(JSON.parse(content));
      } catch (e) {
        console.error(`Ошибка чтения файла ${file}:`, e.message);
      }
    }

    res.json({ success: true, shops });
  } catch (error) {
    console.error('Ошибка получения магазинов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/shops/:id - получить магазин по ID
app.get('/api/shops/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('GET /api/shops/' + id);

    const shopFile = path.join(SHOPS_DIR, `${id}.json`);
    if (!await fileExists(shopFile)) {
      return res.status(404).json({ success: false, error: 'Магазин не найден' });
    }

    const shop = JSON.parse(await fsp.readFile(shopFile, 'utf8'));
    res.json({ success: true, shop });
  } catch (error) {
    console.error('Ошибка получения магазина:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/shops - создать магазин
app.post('/api/shops', async (req, res) => {
  try {
    const { name, address, latitude, longitude, icon } = req.body;
    console.log('POST /api/shops', req.body);

    const id = 'shop_' + Date.now();
    const shop = {
      id,
      name: name || '',
      address: address || '',
      icon: icon || 'store_outlined',
      latitude: latitude || null,
      longitude: longitude || null,
      createdAt: new Date().toISOString(),
    };

    const shopFile = path.join(SHOPS_DIR, `${id}.json`);
    await fsp.writeFile(shopFile, JSON.stringify(shop, null, 2));

    console.log('✅ Магазин создан:', id);
    res.json({ success: true, shop });
  } catch (error) {
    console.error('Ошибка создания магазина:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/shops/:id - обновить магазин
app.put('/api/shops/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const updates = req.body;
    console.log('PUT /api/shops/' + id, updates);

    const shopFile = path.join(SHOPS_DIR, `${id}.json`);
    if (!await fileExists(shopFile)) {
      return res.status(404).json({ success: false, error: 'Магазин не найден' });
    }

    const shop = JSON.parse(await fsp.readFile(shopFile, 'utf8'));

    // Обновляем только переданные поля
    if (updates.name !== undefined) shop.name = updates.name;
    if (updates.address !== undefined) shop.address = updates.address;
    if (updates.latitude !== undefined) shop.latitude = updates.latitude;
    if (updates.longitude !== undefined) shop.longitude = updates.longitude;
    if (updates.icon !== undefined) shop.icon = updates.icon;
    shop.updatedAt = new Date().toISOString();

    await fsp.writeFile(shopFile, JSON.stringify(shop, null, 2));

    console.log('✅ Магазин обновлен:', id);
    res.json({ success: true, shop });
  } catch (error) {
    console.error('Ошибка обновления магазина:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/shops/:id - удалить магазин
app.delete('/api/shops/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('DELETE /api/shops/' + id);

    const shopFile = path.join(SHOPS_DIR, `${id}.json`);
    if (!await fileExists(shopFile)) {
      return res.status(404).json({ success: false, error: 'Магазин не найден' });
    }

    await fsp.unlink(shopFile);

    console.log('✅ Магазин удален:', id);
    res.json({ success: true });
  } catch (error) {
    console.error('Ошибка удаления магазина:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ========== API для настроек магазинов (РКО) ==========

// Получить настройки магазина
app.get('/api/shop-settings/:shopAddress', async (req, res) => {
  try {
    const shopAddress = decodeURIComponent(req.params.shopAddress);
    console.log('GET /api/shop-settings:', shopAddress);
    
    const settingsDir = `${DATA_DIR}/shop-settings`;
    if (!await fileExists(settingsDir)) {
      await fsp.mkdir(settingsDir, { recursive: true });
    }
    
    const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const settingsFile = path.join(settingsDir, `${sanitizedAddress}.json`);
    
    if (!await fileExists(settingsFile)) {
      return res.json({ 
        success: true, 
        settings: null 
      });
    }
    
    const content = await fsp.readFile(settingsFile, 'utf8');
    const settings = JSON.parse(content);
    
    res.json({ success: true, settings });
  } catch (error) {
    console.error('Ошибка получения настроек магазина:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении настроек магазина'
    });
  }
});

// Сохранить настройки магазина
app.post('/api/shop-settings', async (req, res) => {
  try {
    console.log('📝 POST /api/shop-settings');
    console.log('   Тело запроса:', JSON.stringify(req.body, null, 2));
    
    const settingsDir = `${DATA_DIR}/shop-settings`;
    console.log('   Проверка директории:', settingsDir);
    
    if (!await fileExists(settingsDir)) {
      console.log('   Создание директории:', settingsDir);
      await fsp.mkdir(settingsDir, { recursive: true });
      console.log('   ✅ Директория создана');
    } else {
      console.log('   ✅ Директория существует');
    }
    
    const shopAddress = req.body.shopAddress;
    if (!shopAddress) {
      console.log('   ❌ Адрес магазина не указан');
      return res.status(400).json({ 
        success: false, 
        error: 'Адрес магазина не указан' 
      });
    }
    
    console.log('   Адрес магазина:', shopAddress);
    const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
    console.log('   Очищенный адрес:', sanitizedAddress);
    
    const settingsFile = path.join(settingsDir, `${sanitizedAddress}.json`);
    console.log('   Файл настроек:', settingsFile);
    
    // Если файл существует, сохраняем lastDocumentNumber из старого файла
    let lastDocumentNumber = req.body.lastDocumentNumber || 0;
    if (await fileExists(settingsFile)) {
      try {
        console.log('   Чтение существующего файла...');
        const oldContent = await fsp.readFile(settingsFile, 'utf8');
        const oldSettings = JSON.parse(oldContent);
        if (oldSettings.lastDocumentNumber !== undefined) {
          lastDocumentNumber = oldSettings.lastDocumentNumber;
          console.log('   Сохранен lastDocumentNumber:', lastDocumentNumber);
        }
      } catch (e) {
        console.error('   ⚠️ Ошибка чтения старого файла:', e);
      }
    } else {
      console.log('   Файл не существует, будет создан новый');
    }
    
    const settings = {
      shopAddress: shopAddress,
      address: req.body.address || '',
      inn: req.body.inn || '',
      directorName: req.body.directorName || '',
      lastDocumentNumber: lastDocumentNumber,
      // Интервалы времени для смен
      morningShiftStart: req.body.morningShiftStart || null,
      morningShiftEnd: req.body.morningShiftEnd || null,
      dayShiftStart: req.body.dayShiftStart || null,
      dayShiftEnd: req.body.dayShiftEnd || null,
      nightShiftStart: req.body.nightShiftStart || null,
      nightShiftEnd: req.body.nightShiftEnd || null,
      // Аббревиатуры для смен
      morningAbbreviation: req.body.morningAbbreviation || null,
      dayAbbreviation: req.body.dayAbbreviation || null,
      nightAbbreviation: req.body.nightAbbreviation || null,
      updatedAt: new Date().toISOString(),
    };
    
    if (await fileExists(settingsFile)) {
      try {
        const oldContent = await fsp.readFile(settingsFile, 'utf8');
        const oldSettings = JSON.parse(oldContent);
        if (oldSettings.createdAt) {
          settings.createdAt = oldSettings.createdAt;
          console.log('   Сохранена дата создания:', settings.createdAt);
        }
      } catch (e) {
        console.error('   ⚠️ Ошибка при чтении createdAt:', e);
      }
    } else {
      settings.createdAt = new Date().toISOString();
      console.log('   Установлена новая дата создания:', settings.createdAt);
    }
    
    console.log('   Сохранение настроек:', JSON.stringify(settings, null, 2));
    
    try {
      await fsp.writeFile(settingsFile, JSON.stringify(settings, null, 2), 'utf8');
      console.log('   ✅ Настройки магазина сохранены:', settingsFile);
      
      res.json({
        success: true,
        message: 'Настройки успешно сохранены',
        settings: settings
      });
    } catch (writeError) {
      console.error('   ❌ Ошибка записи файла:', writeError);
      throw writeError;
    }
  } catch (error) {
    console.error('❌ Ошибка сохранения настроек магазина:', error);
    console.error('   Stack:', error.stack);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при сохранении настроек'
    });
  }
});

// Получить следующий номер документа для магазина
app.get('/api/shop-settings/:shopAddress/document-number', async (req, res) => {
  try {
    const shopAddress = decodeURIComponent(req.params.shopAddress);
    console.log('GET /api/shop-settings/:shopAddress/document-number:', shopAddress);
    
    const settingsDir = `${DATA_DIR}/shop-settings`;
    const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const settingsFile = path.join(settingsDir, `${sanitizedAddress}.json`);
    
    if (!await fileExists(settingsFile)) {
      return res.json({ 
        success: true, 
        documentNumber: 1 
      });
    }
    
    const content = await fsp.readFile(settingsFile, 'utf8');
    const settings = JSON.parse(content);
    
    let nextNumber = (settings.lastDocumentNumber || 0) + 1;
    if (nextNumber > 50000) {
      nextNumber = 1;
    }
    
    res.json({ 
      success: true, 
      documentNumber: nextNumber 
    });
  } catch (error) {
    console.error('Ошибка получения номера документа:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении номера документа'
    });
  }
});

// Обновить номер документа для магазина
app.post('/api/shop-settings/:shopAddress/document-number', async (req, res) => {
  try {
    const shopAddress = decodeURIComponent(req.params.shopAddress);
    const { documentNumber } = req.body;
    console.log('POST /api/shop-settings/:shopAddress/document-number:', shopAddress, documentNumber);
    
    const settingsDir = `${DATA_DIR}/shop-settings`;
    if (!await fileExists(settingsDir)) {
      await fsp.mkdir(settingsDir, { recursive: true });
    }
    
    const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const settingsFile = path.join(settingsDir, `${sanitizedAddress}.json`);
    
    let settings = {};
    if (await fileExists(settingsFile)) {
      const content = await fsp.readFile(settingsFile, 'utf8');
      settings = JSON.parse(content);
    } else {
      settings.shopAddress = shopAddress;
      settings.createdAt = new Date().toISOString();
    }
    
    settings.lastDocumentNumber = documentNumber || 0;
    settings.updatedAt = new Date().toISOString();
    
    await fsp.writeFile(settingsFile, JSON.stringify(settings, null, 2), 'utf8');
    console.log('Номер документа обновлен:', settingsFile);
    
    res.json({
      success: true,
      message: 'Номер документа успешно обновлен'
    });
  } catch (error) {
    console.error('Ошибка обновления номера документа:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при обновлении номера документа'
    });
  }
});

// ========== API для РКО отчетов ==========

const rkoReportsDir = `${DATA_DIR}/rko-reports`;
const rkoMetadataFile = path.join(rkoReportsDir, 'rko_metadata.json');

// Инициализация директорий для РКО
(async () => {
  if (!await fileExists(rkoReportsDir)) {
    await fsp.mkdir(rkoReportsDir, { recursive: true });
  }
})();

// Загрузить метаданные РКО
async function loadRKOMetadata() {
  try {
    if (await fileExists(rkoMetadataFile)) {
      const content = await fsp.readFile(rkoMetadataFile, 'utf8');
      return JSON.parse(content);
    }
    return { items: [] };
  } catch (e) {
    console.error('Ошибка загрузки метаданных РКО:', e);
    return { items: [] };
  }
}

// Сохранить метаданные РКО
async function saveRKOMetadata(metadata) {
  try {
    await fsp.writeFile(rkoMetadataFile, JSON.stringify(metadata, null, 2), 'utf8');
  } catch (e) {
    console.error('Ошибка сохранения метаданных РКО:', e);
    throw e;
  }
}

// Очистка старых РКО для сотрудника (максимум 150)
async function cleanupEmployeeRKOs(employeeName) {
  const metadata = loadRKOMetadata();
  const employeeRKOs = metadata.items.filter(rko => rko.employeeName === employeeName);
  
  if (employeeRKOs.length > 150) {
    // Сортируем по дате (старые первыми)
    employeeRKOs.sort((a, b) => new Date(a.date) - new Date(b.date));
    
    // Удаляем старые
    const toDelete = employeeRKOs.slice(0, employeeRKOs.length - 150);
    
    for (const rko of toDelete) {
      // Удаляем файл
      const monthKey = new Date(rko.date).toISOString().substring(0, 7); // YYYY-MM
      const sanitizedEmployee = employeeName.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(rkoReportsDir, 'employee', sanitizedEmployee, monthKey, rko.fileName);
      if (await fileExists(filePath)) {
        await fsp.unlink(filePath);
        console.log('Удален старый РКО:', filePath);
      }
      
      // Удаляем из метаданных
      metadata.items = metadata.items.filter(item => 
        !(item.employeeName === employeeName && item.fileName === rko.fileName)
      );
    }
    
    saveRKOMetadata(metadata);
  }
}

// Очистка старых РКО для магазина (максимум 6 месяцев)
async function cleanupShopRKOs(shopAddress) {
  const metadata = loadRKOMetadata();
  const shopRKOs = metadata.items.filter(rko => rko.shopAddress === shopAddress);
  
  if (shopRKOs.length === 0) return;
  
  // Получаем уникальные месяцы
  const months = [...new Set(shopRKOs.map(rko => new Date(rko.date).toISOString().substring(0, 7)))];
  months.sort((a, b) => b.localeCompare(a)); // Новые первыми
  
  if (months.length > 6) {
    const monthsToDelete = months.slice(6);
    
    for (const monthKey of monthsToDelete) {
      const monthRKOs = shopRKOs.filter(rko => 
        new Date(rko.date).toISOString().substring(0, 7) === monthKey
      );
      
      for (const rko of monthRKOs) {
        // Удаляем файл
        const sanitizedEmployee = rko.employeeName.replace(/[^a-zA-Z0-9_\-]/g, '_');
        const filePath = path.join(rkoReportsDir, 'employee', sanitizedEmployee, monthKey, rko.fileName);
        if (await fileExists(filePath)) {
          await fsp.unlink(filePath);
          console.log('Удален старый РКО магазина:', filePath);
        }
        
        // Удаляем из метаданных
        metadata.items = metadata.items.filter(item => 
          !(item.shopAddress === shopAddress && item.fileName === rko.fileName)
        );
      }
    }
    
    saveRKOMetadata(metadata);
  }
}

// Загрузка РКО на сервер
app.post('/api/rko/upload', upload.single('docx'), async (req, res) => {
  try {
    console.log('📤 POST /api/rko/upload');
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'DOCX файл не загружен'
      });
    }
    
    const { fileName, employeeName, shopAddress, date, amount, rkoType } = req.body;
    
    if (!fileName || !employeeName || !shopAddress || !date) {
      return res.status(400).json({
        success: false,
        error: 'Не все обязательные поля указаны'
      });
    }
    
    // Создаем структуру директорий
    const monthKey = new Date(date).toISOString().substring(0, 7); // YYYY-MM
    const sanitizedEmployee = employeeName.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const employeeDir = path.join(rkoReportsDir, 'employee', sanitizedEmployee, monthKey);
    
    if (!await fileExists(employeeDir)) {
      await fsp.mkdir(employeeDir, { recursive: true });
    }
    
    // Сохраняем файл
    const filePath = path.join(employeeDir, fileName);
    fs.renameSync(req.file.path, filePath);
    console.log('РКО сохранен:', filePath);
    
    // Добавляем метаданные
    const metadata = loadRKOMetadata();
    const newRKO = {
      fileName: fileName,
      employeeName: employeeName,
      shopAddress: shopAddress,
      date: date,
      amount: parseFloat(amount) || 0,
      rkoType: rkoType || '',
      createdAt: new Date().toISOString(),
    };
    
    // Удаляем старую запись, если существует
    metadata.items = metadata.items.filter(item => item.fileName !== fileName);
    metadata.items.push(newRKO);
    
    saveRKOMetadata(metadata);
    
    // Очистка старых РКО
    cleanupEmployeeRKOs(employeeName);
    cleanupShopRKOs(shopAddress);
    
    res.json({
      success: true,
      message: 'РКО успешно загружен'
    });
  } catch (error) {
    console.error('Ошибка загрузки РКО:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при загрузке РКО'
    });
  }
});

// Получить список РКО сотрудника
app.get('/api/rko/list/employee/:employeeName', async (req, res) => {
  try {
    const employeeName = decodeURIComponent(req.params.employeeName);
    console.log('📋 GET /api/rko/list/employee:', employeeName);
    
    const metadata = loadRKOMetadata();
    // Нормализуем имена для сравнения (приводим к нижнему регистру и убираем лишние пробелы)
    const normalizedSearchName = employeeName.toLowerCase().trim().replace(/\s+/g, ' ');
    const employeeRKOs = metadata.items
      .filter(rko => {
        const normalizedRkoName = (rko.employeeName || '').toLowerCase().trim().replace(/\s+/g, ' ');
        return normalizedRkoName === normalizedSearchName;
      })
      .sort((a, b) => new Date(b.date) - new Date(a.date));
    
    // Последние 25
    const latest = employeeRKOs.slice(0, 25);
    
    // Группировка по месяцам
    const monthsMap = {};
    employeeRKOs.forEach(rko => {
      const monthKey = new Date(rko.date).toISOString().substring(0, 7);
      if (!monthsMap[monthKey]) {
        monthsMap[monthKey] = [];
      }
      monthsMap[monthKey].push(rko);
    });
    
    const months = Object.keys(monthsMap).sort((a, b) => b.localeCompare(a));
    
    res.json({
      success: true,
      latest: latest,
      months: months.map(monthKey => ({
        monthKey: monthKey,
        items: monthsMap[monthKey],
      })),
    });
  } catch (error) {
    console.error('Ошибка получения списка РКО сотрудника:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении списка РКО'
    });
  }
});

// Получить список РКО магазина
app.get('/api/rko/list/shop/:shopAddress', async (req, res) => {
  try {
    const shopAddress = decodeURIComponent(req.params.shopAddress);
    console.log('📋 GET /api/rko/list/shop:', shopAddress);
    
    const metadata = loadRKOMetadata();
    const now = new Date();
    const currentMonth = now.toISOString().substring(0, 7); // YYYY-MM
    
    // РКО за текущий месяц
    const currentMonthRKOs = metadata.items
      .filter(rko => {
        const rkoMonth = new Date(rko.date).toISOString().substring(0, 7);
        return rko.shopAddress === shopAddress && rkoMonth === currentMonth;
      })
      .sort((a, b) => new Date(b.date) - new Date(a.date));
    
    // Группировка по месяцам
    const monthsMap = {};
    metadata.items
      .filter(rko => rko.shopAddress === shopAddress)
      .forEach(rko => {
        const monthKey = new Date(rko.date).toISOString().substring(0, 7);
        if (!monthsMap[monthKey]) {
          monthsMap[monthKey] = [];
        }
        monthsMap[monthKey].push(rko);
      });
    
    const months = Object.keys(monthsMap).sort((a, b) => b.localeCompare(a));
    
    res.json({
      success: true,
      currentMonth: currentMonthRKOs,
      months: months.map(monthKey => ({
        monthKey: monthKey,
        items: monthsMap[monthKey],
      })),
    });
  } catch (error) {
    console.error('Ошибка получения списка РКО магазина:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении списка РКО'
    });
  }
});

// Получить все РКО за месяц (для эффективности)
app.get('/api/rko/all', async (req, res) => {
  try {
    const { month } = req.query; // YYYY-MM
    console.log('📋 GET /api/rko/all, month:', month);

    const metadata = loadRKOMetadata();

    let items = metadata.items || [];

    // Фильтруем по месяцу если указан
    if (month) {
      items = items.filter(rko => {
        const rkoMonth = new Date(rko.date).toISOString().substring(0, 7);
        return rkoMonth === month;
      });
    }

    // Сортируем по дате (новые первыми)
    items.sort((a, b) => new Date(b.date) - new Date(a.date));

    console.log(`✅ Найдено ${items.length} РКО${month ? ` за ${month}` : ''}`);

    res.json({
      success: true,
      items: items,
      count: items.length,
    });
  } catch (error) {
    console.error('Ошибка получения всех РКО:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении РКО'
    });
  }
});

// Получить DOCX файл РКО
app.get('/api/rko/file/:fileName', async (req, res) => {
  try {
    // Декодируем имя файла, обрабатывая возможные проблемы с кодировкой
    let fileName;
    try {
      fileName = decodeURIComponent(req.params.fileName);
    } catch (e) {
      // Если декодирование не удалось, используем оригинальное имя
      fileName = req.params.fileName;
    }
    console.log('📄 GET /api/rko/file:', fileName);
    console.log('📄 Оригинальный параметр:', req.params.fileName);
    
    const metadata = loadRKOMetadata();
    const rko = metadata.items.find(item => item.fileName === fileName);
    
    if (!rko) {
      console.error('РКО не найден в метаданных для файла:', fileName);
      return res.status(404).json({
        success: false,
        error: 'РКО не найден'
      });
    }
    
    const monthKey = new Date(rko.date).toISOString().substring(0, 7);
    const sanitizedEmployee = rko.employeeName.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(rkoReportsDir, 'employee', sanitizedEmployee, monthKey, fileName);
    
    console.log('Ищем файл по пути:', filePath);
    
    if (!await fileExists(filePath)) {
      console.error('Файл не найден по пути:', filePath);
      // Попробуем найти файл в других местах
      const allFiles = [];
      async function findFiles(dir, pattern) {
        try {
          const files = await fsp.readdir(dir);
          for (const file of files) {
            const filePath = path.join(dir, file);
            const stat = await fsp.stat(filePath);
            if (stat.isDirectory()) {
              await findFiles(filePath, pattern);
            } else if (file.includes(pattern) || file === pattern) {
              allFiles.push(filePath);
            }
          }
        } catch (e) {
          // Игнорируем ошибки
        }
      }
      await findFiles(rkoReportsDir, fileName);
      if (allFiles.length > 0) {
        console.log('Найден файл в альтернативном месте:', allFiles[0]);
        res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
        // Правильно кодируем имя файла для заголовка (RFC 5987)
        const encodedFileName = encodeURIComponent(fileName);
        res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodedFileName}`);
        return res.sendFile(allFiles[0]);
      }
      return res.status(404).json({
        success: false,
        error: 'Файл РКО не найден'
      });
    }
    
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    // Правильно кодируем имя файла для заголовка (RFC 5987)
    const encodedFileName = encodeURIComponent(fileName);
    res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodedFileName}`);
    res.sendFile(filePath);
  } catch (error) {
    console.error('Ошибка получения файла РКО:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении файла РКО'
    });
  }
});

// Генерация РКО из .docx шаблона
app.post('/api/rko/generate-from-docx', async (req, res) => {
  try {
    const {
      shopAddress,
      shopSettings,
      documentNumber,
      employeeData,
      amount,
      rkoType
    } = req.body;
    
    console.log('📝 POST /api/rko/generate-from-docx');
    console.log('Данные:', {
      shopAddress,
      documentNumber,
      employeeName: employeeData?.fullName,
      amount,
      rkoType
    });
    
    // Путь к Word шаблону
    let templateDocxPath = path.join(__dirname, '..', '.cursor', 'rko_template_new.docx');
    console.log('🔍 Ищем Word шаблон по пути:', templateDocxPath);
    if (!await fileExists(templateDocxPath)) {
      console.error('❌ Word шаблон не найден по пути:', templateDocxPath);
      // Пробуем альтернативный путь
      const altPath = '/root/.cursor/rko_template_new.docx';
      if (await fileExists(altPath)) {
        console.log('✅ Найден альтернативный путь:', altPath);
        templateDocxPath = altPath;
      } else {
        return res.status(404).json({
          success: false,
          error: `Word шаблон rko_template_new.docx не найден. Проверенные пути: ${templateDocxPath}, ${altPath}`
        });
      }
    }
    
    // Создаем временную директорию для работы
    const tempDir = '/tmp/rko_generation';
    if (!await fileExists(tempDir)) {
      await fsp.mkdir(tempDir, { recursive: true });
    }
    
    const tempDocxPath = path.join(tempDir, `rko_${Date.now()}.docx`);
    
    // Форматируем данные для замены
    const now = new Date();
    const dateStr = `${now.getDate().toString().padStart(2, '0')}.${(now.getMonth() + 1).toString().padStart(2, '0')}.${now.getFullYear()}`;
    
    // Форматируем имя директора
    let directorDisplayName = shopSettings.directorName;
    if (!directorDisplayName.toUpperCase().startsWith('ИП ')) {
      const nameWithoutIP = directorDisplayName.replace(/^ИП\s*/i, '');
      directorDisplayName = `ИП ${nameWithoutIP}`;
    }
    
    // Создаем короткое имя директора (первые буквы инициалов)
    function shortenName(fullName) {
      const parts = fullName.replace(/^ИП\s*/i, '').trim().split(/\s+/);
      if (parts.length >= 2) {
        const lastName = parts[0];
        const initials = parts.slice(1).map(p => p.charAt(0).toUpperCase() + '.').join(' ');
        return `${lastName} ${initials}`;
      }
      return fullName;
    }
    
    const directorShortName = shortenName(directorDisplayName);
    
    // Форматируем дату в слова (например, "2 декабря 2025 г.")
    function formatDateWords(date) {
      const months = [
        'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
        'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
      ];
      const day = date.getDate();
      const month = months[date.getMonth()];
      const year = date.getFullYear();
      return `${day} ${month} ${year} г.`;
    }
    
    const dateWords = formatDateWords(now);
    
    // Конвертируем сумму в пропись (упрощенная версия)
    const amountWords = convertAmountToWords(amount);
    
    // Подготавливаем данные для Python скрипта (формат плейсхолдеров)
    // Извлекаем адрес без префикса "Фактический адрес:" для плейсхолдера {SHOP}
    const shopAddressClean = shopSettings.address.replace(/^Фактический адрес:\s*/i, '').trim();
    
    // Формируем паспортные данные в новом формате
    const passportFormatted = `Серия ${employeeData.passportSeries} Номер ${employeeData.passportNumber} Кем Выдан: ${employeeData.issuedBy} Дата Выдачи: ${employeeData.issueDate}`;
    
    const data = {
      org_name: `${directorDisplayName} ИНН: ${shopSettings.inn}`,
      org_address: `Фактический адрес: ${shopSettings.address}`,
      shop_address: shopAddressClean, // Адрес без префикса для {SHOP}
      inn: shopSettings.inn, // Отдельное поле для плейсхолдера {INN}
      doc_number: documentNumber.toString(),
      doc_date: dateStr,
      amount_numeric: amount.toString().split('.')[0],
      fio_receiver: employeeData.fullName,
      basis: 'Зароботная плата', // Всегда "Зароботная плата" для {BASIS}
      amount_text: amountWords,
      attachment: '', // Опционально
      head_position: 'ИП',
      head_name: directorShortName,
      receiver_amount_text: amountWords,
      date_text: dateWords,
      passport_info: passportFormatted, // Новый формат: "Серия ... Номер ... Кем Выдан: ... Дата Выдачи: ..."
      passport_issuer: `${employeeData.issuedBy} Дата выдачи: ${employeeData.issueDate}`,
      cashier_name: directorShortName
    };
    
    // Вызываем Python скрипт для обработки Word шаблона
    const scriptPath = path.join(__dirname, 'rko_docx_processor.py');
    const dataJson = JSON.stringify(data); // Без экранирования - spawn передаёт аргументы безопасно

    try {
      // Обработка Word шаблона через python-docx (используем spawn для защиты от Command Injection)
      console.log(`Выполняем обработку Word шаблона: ${scriptPath} process`);
      const { stdout: processOutput } = await spawnPython([
        scriptPath, 'process', templateDocxPath, tempDocxPath, dataJson
      ]);
      
      const processResult = JSON.parse(processOutput);
      if (!processResult.success) {
        throw new Error(processResult.error || 'Ошибка обработки Word шаблона');
      }
      
      console.log('✅ Word документ успешно обработан');
      
      // Конвертируем DOCX в PDF
      const tempPdfPath = tempDocxPath.replace('.docx', '.pdf');
      console.log(`Конвертируем DOCX в PDF: ${tempDocxPath} -> ${tempPdfPath}`);
      
      try {
        // Конвертация DOCX в PDF (используем spawn для защиты от Command Injection)
        const { stdout: convertOutput } = await spawnPython([
          scriptPath, 'convert', tempDocxPath, tempPdfPath
        ]);
        
        const convertResult = JSON.parse(convertOutput);
        if (!convertResult.success) {
          throw new Error(convertResult.error || 'Ошибка конвертации в PDF');
        }
        
        console.log('✅ DOCX успешно сконвертирован в PDF');
        
        // Читаем PDF файл и отправляем
        const pdfBuffer = await fsp.readFile(tempPdfPath);
        
        // Очищаем временные файлы
        try {
          if (await fileExists(tempDocxPath)) await fsp.unlink(tempDocxPath);
          if (await fileExists(tempPdfPath)) await fsp.unlink(tempPdfPath);
        } catch (e) {
          console.error('Ошибка очистки временных файлов:', e);
        }
        
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', `attachment; filename="rko_${documentNumber}.pdf"`);
        res.send(pdfBuffer);
      } catch (convertError) {
        console.error('Ошибка конвертации в PDF:', convertError);
        // Если конвертация не удалась, отправляем DOCX
        console.log('Отправляем DOCX вместо PDF');
        const docxBuffer = await fsp.readFile(tempDocxPath);
        
        try {
          if (await fileExists(tempDocxPath)) await fsp.unlink(tempDocxPath);
        } catch (e) {
          console.error('Ошибка очистки временных файлов:', e);
        }
        
        res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
        res.setHeader('Content-Disposition', `attachment; filename="rko_${documentNumber}.docx"`);
        res.send(docxBuffer);
      }
      
      } catch (error) {
      console.error('Ошибка выполнения Python скрипта:', error);
      // Очищаем временные файлы при ошибке
      try {
        if (await fileExists(tempDocxPath)) await fsp.unlink(tempDocxPath);
      } catch (e) {}
      
      return res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при генерации РКО'
      });
    }
    
  } catch (error) {
    console.error('Ошибка генерации РКО PDF:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при генерации РКО'
    });
  }
});

// Вспомогательная функция для конвертации суммы в пропись
function convertAmountToWords(amount) {
  const rubles = Math.floor(amount);
  const kopecks = Math.round((amount - rubles) * 100);
  
  const ones = ['', 'один', 'два', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'];
  const tens = ['', '', 'двадцать', 'тридцать', 'сорок', 'пятьдесят', 'шестьдесят', 'семьдесят', 'восемьдесят', 'девяносто'];
  const hundreds = ['', 'сто', 'двести', 'триста', 'четыреста', 'пятьсот', 'шестьсот', 'семьсот', 'восемьсот', 'девятьсот'];
  const teens = ['десять', 'одиннадцать', 'двенадцать', 'тринадцать', 'четырнадцать', 'пятнадцать', 'шестнадцать', 'семнадцать', 'восемнадцать', 'девятнадцать'];
  
  function numberToWords(n) {
    if (n === 0) return 'ноль';
    if (n < 10) return ones[n];
    if (n < 20) return teens[n - 10];
    if (n < 100) {
      const ten = Math.floor(n / 10);
      const one = n % 10;
      return tens[ten] + (one > 0 ? ' ' + ones[one] : '');
    }
    if (n < 1000) {
      const hundred = Math.floor(n / 100);
      const remainder = n % 100;
      return hundreds[hundred] + (remainder > 0 ? ' ' + numberToWords(remainder) : '');
    }
    if (n < 1000000) {
      const thousand = Math.floor(n / 1000);
      const remainder = n % 1000;
      let thousandWord = 'тысяч';
      if (thousand % 10 === 1 && thousand % 100 !== 11) thousandWord = 'тысяча';
      else if ([2, 3, 4].includes(thousand % 10) && ![12, 13, 14].includes(thousand % 100)) thousandWord = 'тысячи';
      return numberToWords(thousand) + ' ' + thousandWord + (remainder > 0 ? ' ' + numberToWords(remainder) : '');
    }
    return n.toString();
  }
  
  const rublesWord = numberToWords(rubles);
  let rubleWord = 'рублей';
  if (rubles % 10 === 1 && rubles % 100 !== 11) rubleWord = 'рубль';
  else if ([2, 3, 4].includes(rubles % 10) && ![12, 13, 14].includes(rubles % 100)) rubleWord = 'рубля';
  
  const kopecksStr = kopecks.toString().padStart(2, '0');
  return `${rublesWord} ${rubleWord} ${kopecksStr} копеек`;
}

// ========== API для pending/failed РКО отчетов ==========

// Получить pending РКО отчеты
app.get('/api/rko/pending', async (req, res) => {
  try {
    console.log('📋 GET /api/rko/pending');
    const reports = getPendingRkoReports();
    res.json({
      success: true,
      items: reports,
      count: reports.length
    });
  } catch (error) {
    console.error('Ошибка получения pending РКО:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении pending РКО'
    });
  }
});

// Получить failed РКО отчеты
app.get('/api/rko/failed', async (req, res) => {
  try {
    console.log('📋 GET /api/rko/failed');
    const reports = getFailedRkoReports();
    res.json({
      success: true,
      items: reports,
      count: reports.length
    });
  } catch (error) {
    console.error('Ошибка получения failed РКО:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении failed РКО'
    });
  }
});

// ========== API для pending/failed Attendance отчетов ==========

// Получить pending Attendance отчеты
app.get('/api/attendance/pending', async (req, res) => {
  try {
    console.log('GET /api/attendance/pending');
    const reports = getPendingAttendanceReports();
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

// Получить failed Attendance отчеты
app.get('/api/attendance/failed', async (req, res) => {
  try {
    console.log('GET /api/attendance/failed');
    const reports = getFailedAttendanceReports();
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

// Проверить можно ли отмечаться на магазине
app.get('/api/attendance/can-mark', async (req, res) => {
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

    const canMark = canMarkAttendance(shopAddress);
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

// ==================== GPS ATTENDANCE NOTIFICATIONS ====================

// Кэш отправленных GPS-уведомлений (phone_date -> { shopAddress, notifiedAt })
const gpsNotificationCache = new Map();

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

// POST /api/attendance/gps-check - Проверка GPS и отправка уведомления
app.post('/api/attendance/gps-check', async (req, res) => {
  try {
    const { lat, lng, phone, employeeName } = req.body;

    console.log(`[GPS-Check] Request: lat=${lat}, lng=${lng}, phone=${phone}, employee=${employeeName}`);

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
    const today = new Date().toISOString().split('T')[0];
    const monthKey = today.substring(0, 7); // YYYY-MM
    const scheduleFile = path.join(`${DATA_DIR}/work-schedules`, `${monthKey}.json`);

    // Сначала ищем сотрудника по телефону в базе employees
    let employeeId = null;
    const employeesDir = `${DATA_DIR}/employees`;
    try {
      const empFiles = (await fsp.readdir(employeesDir)).filter(f => f.endsWith('.json'));
      for (const file of empFiles) {
        try {
          const empData = JSON.parse(await fsp.readFile(path.join(employeesDir, file), 'utf8'));
          const empPhone = (empData.phone || '').replace(/\D/g, '');
          const checkPhone = phone.replace(/\D/g, '');
          if (empPhone && (empPhone === checkPhone || empPhone.endsWith(checkPhone.slice(-10)) || checkPhone.endsWith(empPhone.slice(-10)))) {
            employeeId = empData.id;
            console.log(`[GPS-Check] Found employee: ${empData.name} (${employeeId})`);
            break;
          }
        } catch (e) {}
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
      console.log(`[GPS-Check] No shift today for ${phone} at ${nearestShop.address}`);
      return res.json({ success: true, notified: false, reason: 'no_shift_here' });
    }

    // 4. Проверяем есть ли pending отчёт для этого магазина
    const pendingReports = getPendingAttendanceReports();
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
      console.log(`[GPS-Check] Already notified ${phone} for ${nearestShop.address} today`);
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
        console.log(`[GPS-Check] Push sent to ${phone} for ${nearestShop.address}`);
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

// Endpoint для редактора координат
app.get('/rko_coordinates_editor.html', async (req, res) => {
  res.sendFile(`${DATA_DIR}/html/rko_coordinates_editor.html`);
});

// Endpoint для координат HTML
app.get('/coordinates.html', async (req, res) => {
  res.sendFile(`${DATA_DIR}/html/coordinates.html`);
});

// Endpoint для тестового PDF
app.get('/test_rko_corrected.pdf', async (req, res) => {
  res.sendFile(`${DATA_DIR}/html/test_rko_corrected.pdf`);
});

// Endpoint для изображения шаблона
app.get('/rko_template.jpg', async (req, res) => {
  res.sendFile(`${DATA_DIR}/html/rko_template.jpg`);
});

// Endpoint для финального тестового PDF
app.get('/test_rko_final.pdf', async (req, res) => {
  res.setHeader('Content-Type', 'application/pdf');
  res.sendFile(`${DATA_DIR}/html/test_rko_final.pdf`);
});

// Endpoint для нового тестового PDF с исправленными координатами
app.get('/test_rko_new_coords.pdf', async (req, res) => {
  res.setHeader('Content-Type', 'application/pdf');
  res.sendFile(`${DATA_DIR}/html/test_rko_new_coords.pdf`);
});

// Endpoint для тестового РКО КО-2 с фиксированными высотами
app.get('/test_rko_ko2_fixed.docx', async (req, res) => {
  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
  res.setHeader('Content-Disposition', 'inline; filename="test_rko_ko2_fixed.docx"');
  res.sendFile(`${DATA_DIR}/html/test_rko_ko2_fixed.docx`);
});

// ==================== API для выемок (главная касса) ====================

const WITHDRAWALS_DIR = `${DATA_DIR}/withdrawals`;
const MAIN_CASH_DIR = `${DATA_DIR}/main_cash`;

// Создаем директории, если их нет
(async () => {
  if (!await fileExists(WITHDRAWALS_DIR)) {
    await fsp.mkdir(WITHDRAWALS_DIR, { recursive: true, mode: 0o755 });
  }
  if (!await fileExists(MAIN_CASH_DIR)) {
    await fsp.mkdir(MAIN_CASH_DIR, { recursive: true, mode: 0o755 });
  }
})();

// Вспомогательная функция для загрузки всех сотрудников (для уведомлений)
async function loadAllEmployeesForWithdrawals() {
  if (!await fileExists(EMPLOYEES_DIR)) {
    return [];
  }

  const files = await fsp.readdir(EMPLOYEES_DIR);
  const employees = [];

  for (const file of files) {
    if (file.endsWith('.json')) {
      try {
        const filePath = path.join(EMPLOYEES_DIR, file);
        const data = await fsp.readFile(filePath, 'utf8');
        const employee = JSON.parse(data);
        employees.push(employee);
      } catch (err) {
        console.error(`Ошибка чтения сотрудника ${file}:`, err);
      }
    }
  }

  return employees;
}

// Получить FCM токены пользователей для уведомлений о выемках
// Получить FCM токен по телефону
async function getFCMTokenByPhoneForWithdrawals(phone) {
  try {
    const normalizedPhone = phone.replace(/[\s+]/g, "");
    const FCM_TOKENS_DIR = `${DATA_DIR}/fcm-tokens`;
    const path = require("path");
    const tokenFile = path.join(FCM_TOKENS_DIR, `${normalizedPhone}.json`);

    if (!await fileExists(tokenFile)) {
      return null;
    }

    const tokenData = JSON.parse(await fsp.readFile(tokenFile, "utf8"));
    return tokenData.token || null;
  } catch (err) {
    console.error(`Ошибка получения токена для ${phone}:`, err.message);
    return null;
  }
}

// Получить FCM токены пользователей для уведомлений о выемках
async function getFCMTokensForWithdrawalNotifications(phones) {
  const FCM_TOKENS_DIR = `${DATA_DIR}/fcm-tokens`;
  
  if (!await fileExists(FCM_TOKENS_DIR)) {
    console.log("⚠️  Папка FCM токенов не существует");
    return [];
  }

  const tokens = [];
  for (const phone of phones) {
    const token = getFCMTokenByPhoneForWithdrawals(phone);
    if (token) {
      tokens.push(token);
    }
  }

  return tokens;
}

// Отправить push-уведомления о выемке всем админам
async function sendWithdrawalNotifications(withdrawal) {
  try {
    // 1. Загрузить всех сотрудников
    const employees = loadAllEmployeesForWithdrawals();

    // 2. Отфильтровать админов
    const admins = employees.filter(e => e.isAdmin === true);

    if (admins.length === 0) {
      console.log('Нет админов для отправки уведомлений о выемке');
      return;
    }

    // 3. Получить FCM токены админов
    const adminPhones = admins.map(a => a.phone).filter(p => p);
    const tokens = getFCMTokensForWithdrawalNotifications(adminPhones);

    if (tokens.length === 0) {
      console.log('Нет FCM токенов для админов');
      return;
    }

    // 4. Отправить уведомление
    const message = {
      notification: {
        title: `Выемка: ${withdrawal.shopAddress}`,
        body: `${withdrawal.employeeName} сделал выемку на ${withdrawal.totalAmount.toFixed(0)} руб (${withdrawal.type.toUpperCase()})`,
      },
      data: {
        type: 'withdrawal',
        withdrawalId: withdrawal.id,
        shopAddress: withdrawal.shopAddress,
      },
    };

    await admin.messaging().sendMulticast({
      tokens: tokens,
      ...message,
    });

    console.log(`Отправлено уведомление о выемке ${tokens.length} админам`);
  } catch (err) {
    console.error('Ошибка отправки push-уведомлений о выемке:', err);
  }
}

// Отправить push-уведомления о подтверждении выемки
async function sendWithdrawalConfirmationNotifications(withdrawal) {
  try {
    // 1. Загрузить всех сотрудников
    const employees = loadAllEmployeesForWithdrawals();

    // 2. Отфильтровать админов
    const admins = employees.filter(e => e.isAdmin === true);

    if (admins.length === 0) {
      console.log("Нет админов для отправки уведомлений о подтверждении");
      return;
    }

    // 3. Получить FCM токены админов
    const adminPhones = admins.map(a => a.phone).filter(p => p);
    const tokens = getFCMTokensForWithdrawalNotifications(adminPhones);

    if (tokens.length === 0) {
      console.log("Нет FCM токенов для админов");
      return;
    }

    // 4. Отправить уведомление
    const message = {
      notification: {
        title: `Выемка подтверждена: ${withdrawal.shopAddress}`,
        body: `Выемка от ${withdrawal.employeeName} на ${withdrawal.totalAmount.toFixed(0)} руб (${withdrawal.type.toUpperCase()}) подтверждена`,
      },
      data: {
        type: "withdrawal_confirmed",
        withdrawalId: withdrawal.id,
        shopAddress: withdrawal.shopAddress,
      },
      android: {
        priority: "high",
        notification: {
          sound: "default",
          channelId: "withdrawals_channel",
        },
      },
    };

    await admin.messaging().sendMulticast({
      tokens: tokens,
      ...message,
    });

    console.log(`✅ Отправлено уведомление о подтверждении выемки ${tokens.length} админам`);
  } catch (err) {
    console.error("❌ Ошибка отправки push-уведомлений о подтверждении:", err);
  }
}

// Обновить баланс главной кассы после выемки
async function updateMainCashBalance(shopAddress, type, amount) {
  try {
    // Нормализовать адрес для имени файла
    const fileName = shopAddress.replace(/[^a-zA-Z0-9а-яА-Я]/g, '_') + '.json';
    const filePath = path.join(MAIN_CASH_DIR, fileName);

    let balance = {
      shopAddress: shopAddress,
      oooBalance: 0,
      ipBalance: 0,
      totalBalance: 0,
      lastUpdated: new Date().toISOString(),
    };

    // Загрузить существующий баланс если есть
    if (await fileExists(filePath)) {
      const data = await fsp.readFile(filePath, 'utf8');
      balance = JSON.parse(data);
    }

    // Уменьшить баланс по типу
    if (type === 'ooo') {
      balance.oooBalance -= amount;
    } else if (type === 'ip') {
      balance.ipBalance -= amount;
    }

    // Пересчитать общий баланс
    balance.totalBalance = balance.oooBalance + balance.ipBalance;
    balance.lastUpdated = new Date().toISOString();

    // Сохранить обновлённый баланс
    if (!await fileExists(MAIN_CASH_DIR)) {
      await fsp.mkdir(MAIN_CASH_DIR, { recursive: true, mode: 0o755 });
    }
    await fsp.writeFile(filePath, JSON.stringify(balance, null, 2), 'utf8');

    console.log(`Обновлён баланс ${shopAddress}: ${type}Balance -= ${amount}`);
  } catch (err) {
    console.error('Ошибка обновления баланса главной кассы:', err);
    throw err;
  }
}

// GET /api/withdrawals - получить все выемки с опциональными фильтрами
app.get('/api/withdrawals', async (req, res) => {
  try {
    const { shopAddress, type, fromDate, toDate } = req.query;

    const files = await fsp.readdir(WITHDRAWALS_DIR);
    let withdrawals = [];

    for (const file of files) {
      if (file.endsWith('.json')) {
        try {
          const filePath = path.join(WITHDRAWALS_DIR, file);
          const data = await fsp.readFile(filePath, 'utf8');
          const withdrawal = JSON.parse(data);
          withdrawals.push(withdrawal);
        } catch (err) {
          console.error(`Ошибка чтения выемки ${file}:`, err);
        }
      }
    }

    // Применить фильтры
    if (shopAddress) {
      withdrawals = withdrawals.filter(w => w.shopAddress === shopAddress);
    }

    if (type) {
      withdrawals = withdrawals.filter(w => w.type === type);
    }

    if (fromDate) {
      const from = new Date(fromDate);
      withdrawals = withdrawals.filter(w => new Date(w.createdAt) >= from);
    }

    if (toDate) {
      const to = new Date(toDate);
      withdrawals = withdrawals.filter(w => new Date(w.createdAt) <= to);
    }

    // Сортировать по дате (новые первые)
    withdrawals.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    res.json({ success: true, withdrawals });
  } catch (err) {
    console.error('Ошибка получения выемок:', err);
    res.status(500).json({ success: false, error: 'Ошибка получения выемок' });
  }
});

// POST /api/withdrawals - создать новую выемку
app.post('/api/withdrawals', async (req, res) => {
  try {
    const {
      shopAddress,
      employeeName,
      employeeId,
      type,
      expenses,
      adminName,
      category,          // 'withdrawal' | 'deposit' | 'transfer'
      transferDirection, // 'ooo_to_ip' | 'ip_to_ooo' (для переносов)
    } = req.body;

    // Валидация - для переносов employeeId может быть пустым
    const effectiveCategory = category || 'withdrawal';
    const isTransfer = effectiveCategory === 'transfer';

    if (!shopAddress || !employeeName || !type || !expenses || !Array.isArray(expenses)) {
      return res.status(400).json({ error: 'Не все обязательные поля заполнены' });
    }

    // employeeId обязателен только для выемок и внесений (не для переносов)
    if (!isTransfer && !employeeId) {
      return res.status(400).json({ error: 'ID сотрудника обязателен' });
    }

    if (type !== 'ooo' && type !== 'ip') {
      return res.status(400).json({ error: 'Тип должен быть ooo или ip' });
    }

    if (expenses.length === 0) {
      return res.status(400).json({ error: 'Добавьте хотя бы один расход' });
    }

    // Валидация расходов
    for (const expense of expenses) {
      if (!expense.amount || expense.amount <= 0) {
        return res.status(400).json({ error: 'Все суммы расходов должны быть положительными' });
      }

      if (!expense.supplierId && !expense.comment) {
        return res.status(400).json({ error: 'Для "Другого расхода" комментарий обязателен' });
      }
    }

    // Вычислить общую сумму
    const totalAmount = expenses.reduce((sum, expense) => sum + expense.amount, 0);

    // Создать выемку
    const withdrawal = {
      id: `withdrawal_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      shopAddress,
      employeeName,
      employeeId: employeeId || '',
      type,
      totalAmount,
      expenses,
      adminName: adminName || null,
      createdAt: new Date().toISOString(),
      confirmed: false,
      category: effectiveCategory,
      ...(transferDirection && { transferDirection }),
    };

    // Сохранить в файл
    const filePath = path.join(WITHDRAWALS_DIR, `${withdrawal.id}.json`);
    await fsp.writeFile(filePath, JSON.stringify(withdrawal, null, 2), 'utf8');

    // Обновить баланс главной кассы
    updateMainCashBalance(shopAddress, type, totalAmount);

    // Отправить push-уведомления админам
    await sendWithdrawalNotifications(withdrawal);

    res.json({ success: true, withdrawal });
  } catch (err) {
    console.error('Ошибка создания выемки:', err);
    res.status(500).json({ success: false, error: 'Ошибка создания выемки' });
  }
});

// PATCH /api/withdrawals/:id/confirm - подтвердить выемку
app.patch('/api/withdrawals/:id/confirm', async (req, res) => {
  try {
    const { id } = req.params;
    const filePath = path.join(WITHDRAWALS_DIR, `${id}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({ success: false, error: 'Выемка не найдена' });
    }

    // Прочитать выемку
    const withdrawal = JSON.parse(await fsp.readFile(filePath, 'utf8'));

    // Обновить статус
    withdrawal.confirmed = true;
    withdrawal.confirmedAt = new Date().toISOString();

    // Сохранить обратно
    await fsp.writeFile(filePath, JSON.stringify(withdrawal, null, 2), 'utf8');

    // Отправить push-уведомления о подтверждении
    await sendWithdrawalConfirmationNotifications(withdrawal);

    res.json({ success: true, withdrawal });
  } catch (err) {
    console.error('Ошибка подтверждения выемки:', err);
    res.status(500).json({ success: false, error: 'Ошибка подтверждения выемки' });
  }
});

// DELETE /api/withdrawals/:id - удалить выемку
app.delete('/api/withdrawals/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const filePath = path.join(WITHDRAWALS_DIR, `${id}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({ success: false, error: 'Выемка не найдена' });
    }

    await fsp.unlink(filePath);

    res.json({ success: true, message: 'Выемка удалена' });
  } catch (err) {
    console.error('Ошибка удаления выемки:', err);
    res.status(500).json({ success: false, error: 'Ошибка удаления выемки' });
  }
});

// PATCH /api/withdrawals/:id/cancel - отменить выемку
app.patch('/api/withdrawals/:id/cancel', async (req, res) => {
  try {
    const { id } = req.params;
    const { cancelledBy, cancelReason } = req.body;
    console.log('PATCH /api/withdrawals/:id/cancel', id);

    const filePath = path.join(WITHDRAWALS_DIR, `${id}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({ success: false, error: 'Withdrawal not found' });
    }

    const withdrawal = JSON.parse(await fsp.readFile(filePath, 'utf8'));

    if (withdrawal.status === 'cancelled') {
      return res.status(400).json({
        success: false,
        error: 'Withdrawal is already cancelled'
      });
    }

    withdrawal.status = 'cancelled';
    withdrawal.cancelledAt = new Date().toISOString();
    withdrawal.cancelledBy = cancelledBy || 'unknown';
    withdrawal.cancelReason = cancelReason || 'No reason provided';

    await fsp.writeFile(filePath, JSON.stringify(withdrawal, null, 2), 'utf8');

    res.json({ success: true, withdrawal });
  } catch (error) {
    console.error('Error cancelling withdrawal:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ==================== API для графика работы ====================

const WORK_SCHEDULES_DIR = `${DATA_DIR}/work-schedules`;
const WORK_SCHEDULE_TEMPLATES_DIR = `${DATA_DIR}/work-schedule-templates`;

// Создаем директории, если их нет
(async () => {
  if (!await fileExists(WORK_SCHEDULES_DIR)) {
    await fsp.mkdir(WORK_SCHEDULES_DIR, { recursive: true });
  }
  if (!await fileExists(WORK_SCHEDULE_TEMPLATES_DIR)) {
    await fsp.mkdir(WORK_SCHEDULE_TEMPLATES_DIR, { recursive: true });
  }
})();

// Вспомогательная функция для получения файла графика
function getScheduleFilePath(month) {
  return path.join(WORK_SCHEDULES_DIR, `${month}.json`);
}

// Вспомогательная функция для загрузки графика
async function loadSchedule(month) {
  const filePath = getScheduleFilePath(month);
  if (await fileExists(filePath)) {
    try {
      const data = await fsp.readFile(filePath, 'utf8');
      return JSON.parse(data);
    } catch (error) {
      console.error('Ошибка чтения графика:', error);
      return { month, entries: [] };
    }
  }
  return { month, entries: [] };
}

// Вспомогательная функция для сохранения графика
async function saveSchedule(schedule) {
  const filePath = getScheduleFilePath(schedule.month);
  try {
    await fsp.writeFile(filePath, JSON.stringify(schedule, null, 2), 'utf8');
    return true;
  } catch (error) {
    console.error('Ошибка сохранения графика:', error);
    return false;
  }
}

// GET /api/work-schedule?month=YYYY-MM - получить график на месяц
app.get('/api/work-schedule', async (req, res) => {
  try {
    const month = req.query.month;
    if (!month) {
      return res.status(400).json({ success: false, error: 'Не указан месяц (month)' });
    }

    const schedule = loadSchedule(month);
    console.log(`📥 Загружен график для ${month}: ${schedule.entries.length} записей`);
    res.json({ success: true, schedule });
  } catch (error) {
    console.error('Ошибка получения графика:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/work-schedule/employee/:employeeId?month=YYYY-MM - график сотрудника
app.get('/api/work-schedule/employee/:employeeId', async (req, res) => {
  try {
    const employeeId = req.params.employeeId;
    const month = req.query.month;
    if (!month) {
      return res.status(400).json({ success: false, error: 'Не указан месяц (month)' });
    }

    const schedule = loadSchedule(month);
    const employeeEntries = schedule.entries.filter(e => e.employeeId === employeeId);
    const employeeSchedule = { month, entries: employeeEntries };
    
    res.json({ success: true, schedule: employeeSchedule });
  } catch (error) {
    console.error('Ошибка получения графика сотрудника:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/work-schedule - создать/обновить смену
app.post('/api/work-schedule', async (req, res) => {
  try {
    const entry = req.body;
    if (!entry.month || !entry.employeeId || !entry.date || !entry.shiftType) {
      return res.status(400).json({
        success: false,
        error: 'Не указаны обязательные поля: month, employeeId, date, shiftType'
      });
    }

    const month = entry.month;
    const schedule = loadSchedule(month);

    // Если есть ID - это обновление существующей записи
    if (entry.id) {
      // Удаляем старую запись по ID
      schedule.entries = schedule.entries.filter(e => e.id !== entry.id);
    } else {
      // Новая запись - генерируем ID
      entry.id = `entry_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      // Удаляем возможные дубликаты для этого сотрудника, даты и типа смены
      schedule.entries = schedule.entries.filter(e =>
        !(e.employeeId === entry.employeeId &&
          e.date === entry.date &&
          e.shiftType === entry.shiftType)
      );
    }

    // Добавляем новую запись
    schedule.entries.push(entry);
    schedule.month = month;

    if (saveSchedule(schedule)) {
      res.json({ success: true, entry });

      // Отправляем push-уведомление сотруднику об изменении в графике
      try {
        const employeeFile = path.join(EMPLOYEES_DIR, `${entry.employeeId}.json`);
        if (await fileExists(employeeFile)) {
          const employeeData = JSON.parse(await fsp.readFile(employeeFile, 'utf8'));
          if (employeeData.phone) {
            const shiftLabels = { morning: 'Утренняя', day: 'Дневная', night: 'Ночная' };
            const shiftLabel = shiftLabels[entry.shiftType] || entry.shiftType;
            const dateFormatted = entry.date; // формат YYYY-MM-DD
            const dateParts = dateFormatted.split('-');
            const displayDate = dateParts.length === 3 ? `${dateParts[2]}.${dateParts[1]}` : dateFormatted;

            await sendPushToPhone(
              employeeData.phone,
              'Изменение в графике',
              `Ваша смена на ${displayDate}: ${shiftLabel}`,
              { type: 'schedule_change', date: entry.date, shiftType: entry.shiftType }
            );
            console.log(`Push-уведомление отправлено сотруднику ${employeeData.name || entry.employeeId} об изменении смены`);
          }
        }
      } catch (pushError) {
        console.error('Ошибка отправки push-уведомления о смене:', pushError.message);
        // Не прерываем работу, уведомление не критично
      }
    } else {
      res.status(500).json({ success: false, error: 'Ошибка сохранения графика' });
    }
  } catch (error) {
    console.error('Ошибка сохранения смены:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/work-schedule/clear - очистить весь месяц
app.delete('/api/work-schedule/clear', async (req, res) => {
  try {
    const month = req.query.month;

    if (!month) {
      return res.status(400).json({ success: false, error: 'Не указан месяц (month)' });
    }

    console.log(`🗑️ Запрос на очистку графика за месяц: ${month}`);

    const schedule = loadSchedule(month);
    const entriesCount = schedule.entries.length;

    if (entriesCount === 0) {
      console.log(`ℹ️ График за ${month} уже пуст`);
      return res.json({ success: true, message: 'График уже пуст', deletedCount: 0 });
    }

    // Очищаем все записи
    schedule.entries = [];

    if (saveSchedule(schedule)) {
      console.log(`✅ График за ${month} очищен. Удалено записей: ${entriesCount}`);
      res.json({
        success: true,
        message: `График очищен. Удалено смен: ${entriesCount}`,
        deletedCount: entriesCount
      });
    } else {
      console.error(`❌ Ошибка сохранения графика при очистке ${month}`);
      res.status(500).json({ success: false, error: 'Ошибка сохранения графика' });
    }
  } catch (error) {
    console.error('Ошибка очистки графика:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/work-schedule/:entryId - удалить смену
app.delete('/api/work-schedule/:entryId', async (req, res) => {
  try {
    const entryId = req.params.entryId;
    const month = req.query.month;
    
    if (!month) {
      return res.status(400).json({ success: false, error: 'Не указан месяц (month)' });
    }

    const schedule = loadSchedule(month);
    const initialLength = schedule.entries.length;
    schedule.entries = schedule.entries.filter(e => e.id !== entryId);

    if (schedule.entries.length < initialLength) {
      if (saveSchedule(schedule)) {
        res.json({ success: true, message: 'Смена удалена' });
      } else {
        res.status(500).json({ success: false, error: 'Ошибка сохранения графика' });
      }
    } else {
      res.status(404).json({ success: false, error: 'Смена не найдена' });
    }
  } catch (error) {
    console.error('Ошибка удаления смены:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/work-schedule/bulk - массовое создание смен
app.post('/api/work-schedule/bulk', async (req, res) => {
  try {
    const entries = req.body.entries;
    if (!Array.isArray(entries) || entries.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Не указаны записи (entries)'
      });
    }

    console.log(`📥 BULK-создание: получено ${entries.length} записей от клиента`);

    // Проверяем наличие дубликатов во входящих данных
    const duplicatesCheck = {};
    entries.forEach((e, i) => {
      const key = `${e.shopAddress}|${e.date}|${e.shiftType}`;
      if (duplicatesCheck[key]) {
        console.log(`⚠️ ДУБЛИКАТ ВО ВХОДЯЩИХ ДАННЫХ [${i}]: ${e.employeeName} → ${e.shopAddress}, ${e.date}, ${e.shiftType}`);
        console.log(`   Первое вхождение: [${duplicatesCheck[key].index}] ${duplicatesCheck[key].employeeName}`);
      } else {
        duplicatesCheck[key] = { index: i, employeeName: e.employeeName };
      }
    });

    // Группируем по месяцам
    const schedulesByMonth = {};
    entries.forEach((entry, index) => {
      if (!entry.month) {
        // Извлекаем месяц из даты
        const date = new Date(entry.date);
        entry.month = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
      }

      if (!schedulesByMonth[entry.month]) {
        schedulesByMonth[entry.month] = loadSchedule(entry.month);
      }

      // Генерируем уникальный ID, если его нет
      if (!entry.id) {
        entry.id = `entry_${Date.now()}_${index}_${Math.random().toString(36).substr(2, 9)}`;
      }

      // Удаляем старую запись для этого сотрудника, даты и типа смены, если есть
      // КРИТИЧНО: Также удаляем дубликаты по магазину+дате+типу смены (независимо от сотрудника)
      const beforeFilter = schedulesByMonth[entry.month].entries.length;

      schedulesByMonth[entry.month].entries = schedulesByMonth[entry.month].entries.filter(e => {
        // Удаляем если совпадают: сотрудник + дата + тип смены
        const sameEmployeeShift = (e.employeeId === entry.employeeId &&
                                    e.date === entry.date &&
                                    e.shiftType === entry.shiftType);

        // ИЛИ удаляем если совпадают: магазин + дата + тип смены (дубликат слота)
        const sameSlot = (e.shopAddress === entry.shopAddress &&
                          e.date === entry.date &&
                          e.shiftType === entry.shiftType);

        const shouldRemove = (sameEmployeeShift || sameSlot);

        if (shouldRemove) {
          console.log(`🗑️ Удаление дубликата: ${e.employeeName} → ${e.shopAddress}, ${e.date}, ${e.shiftType}`);
          console.log(`   Причина: ${sameEmployeeShift ? 'тот же сотрудник' : ''} ${sameSlot ? 'тот же слот' : ''}`);
        }

        return !shouldRemove;
      });

      const afterFilter = schedulesByMonth[entry.month].entries.length;
      if (beforeFilter !== afterFilter) {
        console.log(`📉 Фильтрация: было ${beforeFilter} записей, осталось ${afterFilter} (удалено ${beforeFilter - afterFilter})`);
      }

      // Добавляем новую запись
      schedulesByMonth[entry.month].entries.push(entry);
    });
    
    console.log(`📊 Массовое создание: обработано ${entries.length} записей, сохранено в ${Object.keys(schedulesByMonth).length} месяцах`);

    // Сохраняем все графики
    let allSaved = true;
    let totalSaved = 0;
    for (const month in schedulesByMonth) {
      const schedule = schedulesByMonth[month];
      if (saveSchedule(schedule)) {
        totalSaved += schedule.entries.length;
        console.log(`✅ Сохранен график для ${month}: ${schedule.entries.length} записей`);
      } else {
        allSaved = false;
        console.error(`❌ Ошибка сохранения графика для ${month}`);
      }
    }

    if (allSaved) {
      console.log(`✅ Всего сохранено записей в графиках: ${totalSaved}`);
      res.json({ success: true, message: `Создано ${entries.length} смен, всего в графиках: ${totalSaved}` });
    } else {
      res.status(500).json({ success: false, error: 'Ошибка сохранения некоторых графиков' });
    }
  } catch (error) {
    console.error('Ошибка массового создания смен:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/work-schedule/template - сохранить/применить шаблон
app.post('/api/work-schedule/template', async (req, res) => {
  try {
    const action = req.body.action; // 'save' или 'apply'
    const template = req.body.template;

    if (action === 'save') {
      if (!template || !template.name) {
        return res.status(400).json({ 
          success: false, 
          error: 'Не указан шаблон или его название' 
        });
      }

      // Генерируем ID, если его нет
      if (!template.id) {
        template.id = `template_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      const templateFile = path.join(WORK_SCHEDULE_TEMPLATES_DIR, `${template.id}.json`);
      await fsp.writeFile(templateFile, JSON.stringify(template, null, 2), 'utf8');
      
      res.json({ success: true, template });
    } else if (action === 'apply') {
      // Применение шаблона обрабатывается на клиенте
      res.json({ success: true, message: 'Шаблон применен' });
    } else {
      res.status(400).json({ success: false, error: 'Неизвестное действие' });
    }
  } catch (error) {
    console.error('Ошибка работы с шаблоном:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/work-schedule/template - получить список шаблонов
app.get('/api/work-schedule/template', async (req, res) => {
  try {
    const templates = [];
    
    if (await fileExists(WORK_SCHEDULE_TEMPLATES_DIR)) {
      const files = await fsp.readdir(WORK_SCHEDULE_TEMPLATES_DIR);
      for (const file of files) {
        if (file.endsWith('.json')) {
          try {
            const filePath = path.join(WORK_SCHEDULE_TEMPLATES_DIR, file);
            const data = await fsp.readFile(filePath, 'utf8');
            const template = JSON.parse(data);
            templates.push(template);
          } catch (error) {
            console.error(`Ошибка чтения шаблона ${file}:`, error);
          }
        }
      }
    }

    res.json({ success: true, templates });
  } catch (error) {
    console.error('Ошибка получения шаблонов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ========== API для поставщиков ==========

const SUPPLIERS_DIR = `${DATA_DIR}/suppliers`;

// GET /api/suppliers - получить всех поставщиков
app.get('/api/suppliers', async (req, res) => {
  try {
    console.log('GET /api/suppliers');
    
    const suppliers = [];
    
    if (!await fileExists(SUPPLIERS_DIR)) {
      await fsp.mkdir(SUPPLIERS_DIR, { recursive: true });
    }
    
    const files = (await fsp.readdir(SUPPLIERS_DIR)).filter(f => f.endsWith('.json'));
    
    for (const file of files) {
      try {
        const filePath = path.join(SUPPLIERS_DIR, file);
        const content = await fsp.readFile(filePath, 'utf8');
        const supplier = JSON.parse(content);
        suppliers.push(supplier);
      } catch (e) {
        console.error(`Ошибка чтения файла ${file}:`, e);
      }
    }
    
    // Сортируем по дате создания (новые первыми)
    suppliers.sort((a, b) => {
      const dateA = new Date(a.createdAt || 0);
      const dateB = new Date(b.createdAt || 0);
      return dateB - dateA;
    });
    
    res.json({ success: true, suppliers });
  } catch (error) {
    console.error('Ошибка получения поставщиков:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/suppliers/:id - получить поставщика по ID
app.get('/api/suppliers/:id', async (req, res) => {
  try {
    const id = req.params.id;
    console.log('GET /api/suppliers:', id);
    
    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const supplierFile = path.join(SUPPLIERS_DIR, `${sanitizedId}.json`);
    
    if (!await fileExists(supplierFile)) {
      return res.status(404).json({
        success: false,
        error: 'Поставщик не найден'
      });
    }
    
    const content = await fsp.readFile(supplierFile, 'utf8');
    const supplier = JSON.parse(content);
    
    res.json({ success: true, supplier });
  } catch (error) {
    console.error('Ошибка получения поставщика:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/suppliers - создать нового поставщика
app.post('/api/suppliers', async (req, res) => {
  try {
    console.log('POST /api/suppliers:', JSON.stringify(req.body).substring(0, 200));
    
    if (!await fileExists(SUPPLIERS_DIR)) {
      await fsp.mkdir(SUPPLIERS_DIR, { recursive: true });
    }
    
    // Валидация обязательных полей
    if (!req.body.name || req.body.name.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Наименование поставщика обязательно'
      });
    }
    
    if (!req.body.legalType || (req.body.legalType !== 'ООО' && req.body.legalType !== 'ИП')) {
      return res.status(400).json({
        success: false,
        error: 'Тип организации должен быть "ООО" или "ИП"'
      });
    }
    
    if (!req.body.paymentType || (req.body.paymentType !== 'Нал' && req.body.paymentType !== 'БезНал')) {
      return res.status(400).json({
        success: false,
        error: 'Тип оплаты должен быть "Нал" или "БезНал"'
      });
    }
    
    // Генерируем ID если не указан
    const id = req.body.id || `supplier_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const supplierFile = path.join(SUPPLIERS_DIR, `${sanitizedId}.json`);
    
    const supplier = {
      id: sanitizedId,
      referralCode: req.body.referralCode || getNextReferralCode(),
      name: req.body.name.trim(),
      inn: req.body.inn ? req.body.inn.trim() : null,
      legalType: req.body.legalType,
      phone: req.body.phone ? req.body.phone.trim() : null,
      email: req.body.email ? req.body.email.trim() : null,
      contactPerson: req.body.contactPerson ? req.body.contactPerson.trim() : null,
      paymentType: req.body.paymentType,
      shopDeliveries: req.body.shopDeliveries || null,
      // Устаревшее поле для обратной совместимости
      deliveryDays: req.body.deliveryDays || [],
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    await fsp.writeFile(supplierFile, JSON.stringify(supplier, null, 2), 'utf8');
    console.log('Поставщик создан:', supplierFile);

    res.json({ success: true, supplier });
  } catch (error) {
    console.error('Ошибка создания поставщика:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/suppliers/:id - обновить поставщика
app.put('/api/suppliers/:id', async (req, res) => {
  try {
    const id = req.params.id;
    console.log('PUT /api/suppliers:', id);
    
    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const supplierFile = path.join(SUPPLIERS_DIR, `${sanitizedId}.json`);
    
    if (!await fileExists(supplierFile)) {
      return res.status(404).json({
        success: false,
        error: 'Поставщик не найден'
      });
    }
    
    // Валидация обязательных полей
    if (!req.body.name || req.body.name.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Наименование поставщика обязательно'
      });
    }
    
    if (!req.body.legalType || (req.body.legalType !== 'ООО' && req.body.legalType !== 'ИП')) {
      return res.status(400).json({
        success: false,
        error: 'Тип организации должен быть "ООО" или "ИП"'
      });
    }
    
    if (!req.body.paymentType || (req.body.paymentType !== 'Нал' && req.body.paymentType !== 'БезНал')) {
      return res.status(400).json({
        success: false,
        error: 'Тип оплаты должен быть "Нал" или "БезНал"'
      });
    }
    
    // Читаем существующие данные для сохранения createdAt
    const oldContent = await fsp.readFile(supplierFile, 'utf8');
    const oldSupplier = JSON.parse(oldContent);
    
    const supplier = {
      id: sanitizedId,
      referralCode: req.body.referralCode || oldSupplier.referralCode || getNextReferralCode(),
      name: req.body.name.trim(),
      inn: req.body.inn ? req.body.inn.trim() : null,
      legalType: req.body.legalType,
      phone: req.body.phone ? req.body.phone.trim() : null,
      email: req.body.email ? req.body.email.trim() : null,
      contactPerson: req.body.contactPerson ? req.body.contactPerson.trim() : null,
      paymentType: req.body.paymentType,
      shopDeliveries: req.body.shopDeliveries || null,
      deliveryDays: req.body.deliveryDays || [],
      createdAt: oldSupplier.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    
    await fsp.writeFile(supplierFile, JSON.stringify(supplier, null, 2), 'utf8');
    console.log('Поставщик обновлен:', supplierFile);
    
    res.json({ success: true, supplier });
  } catch (error) {
    console.error('Ошибка обновления поставщика:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/suppliers/:id - удалить поставщика
app.delete('/api/suppliers/:id', async (req, res) => {
  try {
    const id = req.params.id;
    console.log('DELETE /api/suppliers:', id);
    
    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const supplierFile = path.join(SUPPLIERS_DIR, `${sanitizedId}.json`);
    
    if (!await fileExists(supplierFile)) {
      return res.status(404).json({
        success: false,
        error: 'Поставщик не найден'
      });
    }
    
    await fsp.unlink(supplierFile);
    console.log('Поставщик удален:', supplierFile);
    
    res.json({ success: true, message: 'Поставщик удален' });
  } catch (error) {
    console.error('Ошибка удаления поставщика:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// API для вопросов пересчета (Recount Questions)
// ============================================================================

const RECOUNT_QUESTIONS_DIR = `${DATA_DIR}/recount-questions`;

// Создаем директорию, если её нет
(async () => {
  if (!await fileExists(RECOUNT_QUESTIONS_DIR)) {
    await fsp.mkdir(RECOUNT_QUESTIONS_DIR, { recursive: true });
  }
})();

// Получить все вопросы пересчета
app.get('/api/recount-questions', async (req, res) => {
  try {
    console.log('GET /api/recount-questions:', req.query);

    const files = await fsp.readdir(RECOUNT_QUESTIONS_DIR);
    const questions = [];

    for (const file of files) {
      if (file.endsWith('.json')) {
        try {
          const filePath = path.join(RECOUNT_QUESTIONS_DIR, file);
          const data = await fsp.readFile(filePath, 'utf8');
          const question = JSON.parse(data);
          questions.push(question);
        } catch (error) {
          console.error(`Ошибка чтения вопроса ${file}:`, error);
        }
      }
    }

    res.json({
      success: true,
      questions: questions
    });
  } catch (error) {
    console.error('Ошибка получения вопросов пересчета:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Создать вопрос пересчета
app.post('/api/recount-questions', async (req, res) => {
  try {
    console.log('POST /api/recount-questions:', JSON.stringify(req.body).substring(0, 200));

    const questionId = req.body.id || `recount_question_${Date.now()}`;
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

    const questionData = {
      id: questionId,
      question: req.body.question,
      grade: req.body.grade || 1,
      referencePhotos: req.body.referencePhotos || {},
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    await fsp.writeFile(filePath, JSON.stringify(questionData, null, 2), 'utf8');
    console.log('Вопрос пересчета сохранен:', filePath);

    res.json({
      success: true,
      message: 'Вопрос успешно создан',
      question: questionData
    });
  } catch (error) {
    console.error('Ошибка создания вопроса пересчета:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Обновить вопрос пересчета
app.put('/api/recount-questions/:questionId', async (req, res) => {
  try {
    const { questionId } = req.params;
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({
        success: false,
        error: 'Вопрос не найден'
      });
    }

    const existingData = await fsp.readFile(filePath, 'utf8');
    const existingQuestion = JSON.parse(existingData);

    const updatedQuestion = {
      ...existingQuestion,
      ...(req.body.question !== undefined && { question: req.body.question }),
      ...(req.body.grade !== undefined && { grade: req.body.grade }),
      ...(req.body.referencePhotos !== undefined && { referencePhotos: req.body.referencePhotos }),
      updatedAt: new Date().toISOString()
    };

    await fsp.writeFile(filePath, JSON.stringify(updatedQuestion, null, 2), 'utf8');
    console.log('Вопрос пересчета обновлен:', filePath);

    res.json({
      success: true,
      message: 'Вопрос успешно обновлен',
      question: updatedQuestion
    });
  } catch (error) {
    console.error('Ошибка обновления вопроса пересчета:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Загрузить эталонное фото для вопроса пересчета
app.post('/api/recount-questions/:questionId/reference-photo', upload.single('photo'), async (req, res) => {
  try {
    const { questionId } = req.params;
    const { shopAddress } = req.body;

    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'Файл не загружен'
      });
    }

    if (!shopAddress) {
      return res.status(400).json({
        success: false,
        error: 'Не указан адрес магазина'
      });
    }

    const photoUrl = `https://arabica26.ru/shift-photos/${req.file.filename}`;
    console.log('Эталонное фото загружено:', req.file.filename, 'для магазина:', shopAddress);

    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

    if (await fileExists(filePath)) {
      const existingData = await fsp.readFile(filePath, 'utf8');
      const question = JSON.parse(existingData);

      if (!question.referencePhotos) {
        question.referencePhotos = {};
      }
      question.referencePhotos[shopAddress] = photoUrl;
      question.updatedAt = new Date().toISOString();

      await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
      console.log('Эталонное фото добавлено в вопрос пересчета:', questionId);
    }

    res.json({
      success: true,
      photoUrl: photoUrl,
      shopAddress: shopAddress
    });
  } catch (error) {
    console.error('Ошибка загрузки эталонного фото:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Удалить вопрос пересчета
app.delete('/api/recount-questions/:questionId', async (req, res) => {
  try {
    const { questionId } = req.params;
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({
        success: false,
        error: 'Вопрос не найден'
      });
    }

    await fsp.unlink(filePath);
    console.log('Вопрос пересчета удален:', filePath);

    res.json({
      success: true,
      message: 'Вопрос успешно удален'
    });
  } catch (error) {
    console.error('Ошибка удаления вопроса пересчета:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Массовая загрузка товаров пересчета (ЗАМЕНИТЬ ВСЕ)
// Формат: { products: [{ barcode, productGroup, productName, grade }] }
app.post('/api/recount-questions/bulk-upload', async (req, res) => {
  try {
    console.log('POST /api/recount-questions/bulk-upload:', req.body?.products?.length, 'товаров');

    const { products } = req.body;
    if (!products || !Array.isArray(products)) {
      return res.status(400).json({
        success: false,
        error: 'Необходим массив products'
      });
    }

    // Удаляем все существующие файлы
    const existingFiles = await fsp.readdir(RECOUNT_QUESTIONS_DIR);
    for (const file of existingFiles) {
      if (file.endsWith('.json')) {
        await fsp.unlink(path.join(RECOUNT_QUESTIONS_DIR, file));
      }
    }
    console.log(`Удалено ${existingFiles.length} существующих файлов`);

    // Создаем новые файлы
    const createdProducts = [];
    for (const product of products) {
      const barcode = product.barcode?.toString().trim();
      if (!barcode) continue;

      const productId = `product_${barcode}`;
      const sanitizedId = productId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

      const productData = {
        id: productId,
        barcode: barcode,
        productGroup: product.productGroup || '',
        productName: product.productName || '',
        grade: product.grade || 1,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };

      await fsp.writeFile(filePath, JSON.stringify(productData, null, 2), 'utf8');
      createdProducts.push(productData);
    }

    console.log(`Создано ${createdProducts.length} товаров`);

    res.json({
      success: true,
      message: `Загружено ${createdProducts.length} товаров`,
      questions: createdProducts
    });
  } catch (error) {
    console.error('Ошибка массовой загрузки товаров:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Массовое добавление НОВЫХ товаров (только с новыми баркодами)
// Формат: { products: [{ barcode, productGroup, productName, grade }] }
app.post('/api/recount-questions/bulk-add-new', async (req, res) => {
  try {
    console.log('POST /api/recount-questions/bulk-add-new:', req.body?.products?.length, 'товаров');

    const { products } = req.body;
    if (!products || !Array.isArray(products)) {
      return res.status(400).json({
        success: false,
        error: 'Необходим массив products'
      });
    }

    // Читаем существующие баркоды
    const existingBarcodes = new Set();
    const existingFiles = await fsp.readdir(RECOUNT_QUESTIONS_DIR);
    for (const file of existingFiles) {
      if (file.endsWith('.json')) {
        try {
          const data = await fsp.readFile(path.join(RECOUNT_QUESTIONS_DIR, file), 'utf8');
          const product = JSON.parse(data);
          if (product.barcode) {
            existingBarcodes.add(product.barcode.toString());
          }
        } catch (e) {
          console.error(`Ошибка чтения файла ${file}:`, e);
        }
      }
    }
    console.log(`Существующих товаров: ${existingBarcodes.size}`);

    // Добавляем только новые
    const addedProducts = [];
    let skipped = 0;
    for (const product of products) {
      const barcode = product.barcode?.toString().trim();
      if (!barcode) {
        skipped++;
        continue;
      }

      if (existingBarcodes.has(barcode)) {
        skipped++;
        continue;
      }

      const productId = `product_${barcode}`;
      const sanitizedId = productId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

      const productData = {
        id: productId,
        barcode: barcode,
        productGroup: product.productGroup || '',
        productName: product.productName || '',
        grade: product.grade || 1,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };

      await fsp.writeFile(filePath, JSON.stringify(productData, null, 2), 'utf8');
      addedProducts.push(productData);
      existingBarcodes.add(barcode);
    }

    console.log(`Добавлено ${addedProducts.length} новых товаров, пропущено ${skipped}`);

    res.json({
      success: true,
      message: `Добавлено ${addedProducts.length} новых товаров`,
      added: addedProducts.length,
      skipped: skipped,
      total: existingBarcodes.size,
      questions: addedProducts
    });
  } catch (error) {
    console.error('Ошибка добавления новых товаров:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// ============================================================================
// API для вопросов пересменки (Shift Questions)
// ============================================================================

const SHIFT_QUESTIONS_DIR = `${DATA_DIR}/shift-questions`;

// Создаем директорию, если её нет
(async () => {
  if (!await fileExists(SHIFT_QUESTIONS_DIR)) {
    await fsp.mkdir(SHIFT_QUESTIONS_DIR, { recursive: true });
  }
})();

// Получить все вопросы
app.get('/api/shift-questions', async (req, res) => {
  try {
    console.log('GET /api/shift-questions:', req.query);

    const files = await fsp.readdir(SHIFT_QUESTIONS_DIR);
    const questions = [];

    for (const file of files) {
      if (file.endsWith('.json')) {
        try {
          const filePath = path.join(SHIFT_QUESTIONS_DIR, file);
          const data = await fsp.readFile(filePath, 'utf8');
          const question = JSON.parse(data);
          questions.push(question);
        } catch (error) {
          console.error(`Ошибка чтения вопроса ${file}:`, error);
        }
      }
    }

    // Фильтр по магазину (если указан)
    let filteredQuestions = questions;
    if (req.query.shopAddress) {
      filteredQuestions = questions.filter(q => {
        // Если shops === null, вопрос для всех магазинов
        if (!q.shops || q.shops.length === 0) return true;
        // Иначе проверяем, есть ли магазин в списке
        return q.shops.includes(req.query.shopAddress);
      });
    }

    res.json({
      success: true,
      questions: filteredQuestions
    });
  } catch (error) {
    console.error('Ошибка получения вопросов:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Получить один вопрос по ID
app.get('/api/shift-questions/:questionId', async (req, res) => {
  try {
    const { questionId } = req.params;
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({
        success: false,
        error: 'Вопрос не найден'
      });
    }

    const data = await fsp.readFile(filePath, 'utf8');
    const question = JSON.parse(data);

    res.json({
      success: true,
      question
    });
  } catch (error) {
    console.error('Ошибка получения вопроса:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Создать новый вопрос
app.post('/api/shift-questions', async (req, res) => {
  try {
    console.log('POST /api/shift-questions:', JSON.stringify(req.body).substring(0, 200));

    const questionId = req.body.id || `shift_question_${Date.now()}`;
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

    const questionData = {
      id: questionId,
      question: req.body.question,
      answerFormatB: req.body.answerFormatB || null,
      answerFormatC: req.body.answerFormatC || null,
      shops: req.body.shops || null,
      referencePhotos: req.body.referencePhotos || {},
      isAiCheck: req.body.isAiCheck || false,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    await fsp.writeFile(filePath, JSON.stringify(questionData, null, 2), 'utf8');
    console.log('Вопрос сохранен:', filePath);

    res.json({
      success: true,
      message: 'Вопрос успешно создан',
      question: questionData
    });
  } catch (error) {
    console.error('Ошибка создания вопроса:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Обновить вопрос
app.put('/api/shift-questions/:questionId', async (req, res) => {
  try {
    const { questionId } = req.params;
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({
        success: false,
        error: 'Вопрос не найден'
      });
    }

    // Читаем существующий вопрос
    const existingData = await fsp.readFile(filePath, 'utf8');
    const existingQuestion = JSON.parse(existingData);

    // Обновляем только переданные поля
    const updatedQuestion = {
      ...existingQuestion,
      ...(req.body.question !== undefined && { question: req.body.question }),
      ...(req.body.answerFormatB !== undefined && { answerFormatB: req.body.answerFormatB }),
      ...(req.body.answerFormatC !== undefined && { answerFormatC: req.body.answerFormatC }),
      ...(req.body.shops !== undefined && { shops: req.body.shops }),
      ...(req.body.referencePhotos !== undefined && { referencePhotos: req.body.referencePhotos }),
      ...(req.body.isAiCheck !== undefined && { isAiCheck: req.body.isAiCheck }),
      updatedAt: new Date().toISOString()
    };

    await fsp.writeFile(filePath, JSON.stringify(updatedQuestion, null, 2), 'utf8');
    console.log('Вопрос обновлен:', filePath);

    res.json({
      success: true,
      message: 'Вопрос успешно обновлен',
      question: updatedQuestion
    });
  } catch (error) {
    console.error('Ошибка обновления вопроса:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Загрузить эталонное фото для вопроса
app.post('/api/shift-questions/:questionId/reference-photo', upload.single('photo'), async (req, res) => {
  try {
    const { questionId } = req.params;
    const { shopAddress } = req.body;

    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'Файл не загружен'
      });
    }

    if (!shopAddress) {
      return res.status(400).json({
        success: false,
        error: 'Не указан адрес магазина'
      });
    }

    const photoUrl = `https://arabica26.ru/shift-photos/${req.file.filename}`;
    console.log('Эталонное фото загружено:', req.file.filename, 'для магазина:', shopAddress);

    // Обновляем вопрос, добавляя URL эталонного фото
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

    if (await fileExists(filePath)) {
      const existingData = await fsp.readFile(filePath, 'utf8');
      const question = JSON.parse(existingData);

      // Добавляем или обновляем эталонное фото для данного магазина
      if (!question.referencePhotos) {
        question.referencePhotos = {};
      }
      question.referencePhotos[shopAddress] = photoUrl;
      question.updatedAt = new Date().toISOString();

      await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
      console.log('Эталонное фото добавлено в вопрос:', questionId);
    }

    res.json({
      success: true,
      photoUrl: photoUrl,
      shopAddress: shopAddress
    });
  } catch (error) {
    console.error('Ошибка загрузки эталонного фото:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Удалить вопрос
app.delete('/api/shift-questions/:questionId', async (req, res) => {
  try {
    const { questionId } = req.params;
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({
        success: false,
        error: 'Вопрос не найден'
      });
    }

    await fsp.unlink(filePath);
    console.log('Вопрос удален:', filePath);

    res.json({
      success: true,
      message: 'Вопрос успешно удален'
    });
  } catch (error) {
    console.error('Ошибка удаления вопроса:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// ============================================================================
// API для вопросов сдачи смены (Shift Handover Questions)
// ============================================================================

const SHIFT_HANDOVER_QUESTIONS_DIR = `${DATA_DIR}/shift-handover-questions`;

// Создаем директорию, если её нет
(async () => {
  if (!await fileExists(SHIFT_HANDOVER_QUESTIONS_DIR)) {
    await fsp.mkdir(SHIFT_HANDOVER_QUESTIONS_DIR, { recursive: true });
  }
})();

// Получить все вопросы
app.get('/api/shift-handover-questions', async (req, res) => {
  try {
    console.log('GET /api/shift-handover-questions:', req.query);

    const files = await fsp.readdir(SHIFT_HANDOVER_QUESTIONS_DIR);
    const questions = [];

    for (const file of files) {
      if (file.endsWith('.json')) {
        const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, file);
        const data = await fsp.readFile(filePath, 'utf8');
        const question = JSON.parse(data);

        // Фильтр по магазину, если указан
        if (req.query.shopAddress) {
          // Вопрос показывается если:
          // 1. У него shops == null (для всех магазинов)
          // 2. Или shops содержит указанный магазин
          if (!question.shops || question.shops.length === 0 || question.shops.includes(req.query.shopAddress)) {
            questions.push(question);
          }
        } else {
          questions.push(question);
        }
      }
    }

    // Сортировка по дате создания (новые в начале)
    questions.sort((a, b) => {
      const dateA = new Date(a.createdAt || 0);
      const dateB = new Date(b.createdAt || 0);
      return dateB - dateA;
    });

    res.json({
      success: true,
      questions: questions
    });
  } catch (error) {
    console.error('Ошибка получения вопросов сдачи смены:', error);
    res.status(500).json({
      success: false,
      error: error.message,
      questions: []
    });
  }
});

// Получить один вопрос по ID
app.get('/api/shift-handover-questions/:questionId', async (req, res) => {
  try {
    const { questionId } = req.params;
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({
        success: false,
        error: 'Вопрос не найден'
      });
    }

    const data = await fsp.readFile(filePath, 'utf8');
    const question = JSON.parse(data);

    res.json({
      success: true,
      question: question
    });
  } catch (error) {
    console.error('Ошибка получения вопроса сдачи смены:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Создать новый вопрос
app.post('/api/shift-handover-questions', async (req, res) => {
  try {
    console.log('POST /api/shift-handover-questions:', JSON.stringify(req.body).substring(0, 200));

    const questionId = req.body.id || `shift_handover_question_${Date.now()}`;
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

    const question = {
      id: questionId,
      question: req.body.question,
      answerFormatB: req.body.answerFormatB || null,
      answerFormatC: req.body.answerFormatC || null,
      shops: req.body.shops || [],
      referencePhotos: req.body.referencePhotos || {},
      targetRole: req.body.targetRole || null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
    console.log('Вопрос сдачи смены создан:', filePath);

    res.json({
      success: true,
      question: question
    });
  } catch (error) {
    console.error('Ошибка создания вопроса сдачи смены:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Обновить вопрос
app.put('/api/shift-handover-questions/:questionId', async (req, res) => {
  try {
    const { questionId } = req.params;
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({
        success: false,
        error: 'Вопрос не найден'
      });
    }

    const existingData = await fsp.readFile(filePath, 'utf8');
    const question = JSON.parse(existingData);

    // Обновляем только переданные поля
    if (req.body.question !== undefined) question.question = req.body.question;
    if (req.body.answerFormatB !== undefined) question.answerFormatB = req.body.answerFormatB;
    if (req.body.answerFormatC !== undefined) question.answerFormatC = req.body.answerFormatC;
    if (req.body.shops !== undefined) question.shops = req.body.shops;
    if (req.body.referencePhotos !== undefined) question.referencePhotos = req.body.referencePhotos;
    if (req.body.targetRole !== undefined) question.targetRole = req.body.targetRole;
    question.updatedAt = new Date().toISOString();

    await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
    console.log('Вопрос сдачи смены обновлен:', filePath);

    res.json({
      success: true,
      question: question
    });
  } catch (error) {
    console.error('Ошибка обновления вопроса сдачи смены:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Загрузить эталонное фото для вопроса
app.post('/api/shift-handover-questions/:questionId/reference-photo', uploadShiftHandoverPhoto.single('photo'), async (req, res) => {
  try {
    const { questionId } = req.params;
    const { shopAddress } = req.body;

    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'Файл не загружен'
      });
    }

    if (!shopAddress) {
      return res.status(400).json({
        success: false,
        error: 'Не указан адрес магазина'
      });
    }

    const photoUrl = `https://arabica26.ru/shift-handover-question-photos/${req.file.filename}`;
    console.log('Эталонное фото загружено:', req.file.filename, 'для магазина:', shopAddress);

    // Обновляем вопрос, добавляя URL эталонного фото
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

    if (await fileExists(filePath)) {
      const existingData = await fsp.readFile(filePath, 'utf8');
      const question = JSON.parse(existingData);

      // Добавляем или обновляем эталонное фото для данного магазина
      if (!question.referencePhotos) {
        question.referencePhotos = {};
      }
      question.referencePhotos[shopAddress] = photoUrl;
      question.updatedAt = new Date().toISOString();

      await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
      console.log('Эталонное фото добавлено в вопрос:', questionId);
    }

    res.json({
      success: true,
      photoUrl: photoUrl,
      shopAddress: shopAddress
    });
  } catch (error) {
    console.error('Ошибка загрузки эталонного фото:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Удалить вопрос
app.delete('/api/shift-handover-questions/:questionId', async (req, res) => {
  try {
    const { questionId } = req.params;
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({
        success: false,
        error: 'Вопрос не найден'
      });
    }

    await fsp.unlink(filePath);
    console.log('Вопрос сдачи смены удален:', filePath);

    res.json({
      success: true,
      message: 'Вопрос успешно удален'
    });
  } catch (error) {
    console.error('Ошибка удаления вопроса сдачи смены:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// ========== API для вопросов конверта (Envelope Questions) ==========
const ENVELOPE_QUESTIONS_DIR = `${DATA_DIR}/envelope-questions`;

// Создаем директорию, если её нет
(async () => {
  if (!await fileExists(ENVELOPE_QUESTIONS_DIR)) {
    await fsp.mkdir(ENVELOPE_QUESTIONS_DIR, { recursive: true });
  }
})();

// Дефолтные вопросы конверта для инициализации
const defaultEnvelopeQuestions = [
  { id: 'envelope_q_1', title: 'Выбор смены', description: 'Выберите тип смены', type: 'shift_select', section: 'general', order: 1, isRequired: true, isActive: true },
  { id: 'envelope_q_2', title: 'ООО: Z-отчет', description: 'Сфотографируйте Z-отчет ООО', type: 'photo', section: 'ooo', order: 2, isRequired: true, isActive: true },
  { id: 'envelope_q_3', title: 'ООО: Выручка и наличные', description: 'Введите данные ООО', type: 'numbers', section: 'ooo', order: 3, isRequired: true, isActive: true },
  { id: 'envelope_q_4', title: 'ООО: Фото конверта', description: 'Сфотографируйте сформированный конверт ООО', type: 'photo', section: 'ooo', order: 4, isRequired: true, isActive: true },
  { id: 'envelope_q_5', title: 'ИП: Z-отчет', description: 'Сфотографируйте Z-отчет ИП', type: 'photo', section: 'ip', order: 5, isRequired: true, isActive: true },
  { id: 'envelope_q_6', title: 'ИП: Выручка и наличные', description: 'Введите данные ИП', type: 'numbers', section: 'ip', order: 6, isRequired: true, isActive: true },
  { id: 'envelope_q_7', title: 'ИП: Расходы', description: 'Добавьте расходы', type: 'expenses', section: 'ip', order: 7, isRequired: true, isActive: true },
  { id: 'envelope_q_8', title: 'ИП: Фото конверта', description: 'Сфотографируйте сформированный конверт ИП', type: 'photo', section: 'ip', order: 8, isRequired: true, isActive: true },
  { id: 'envelope_q_9', title: 'Итог', description: 'Проверьте данные и отправьте отчет', type: 'summary', section: 'general', order: 9, isRequired: true, isActive: true },
];

// Инициализация дефолтных вопросов при старте
(async function initEnvelopeQuestions() {
  try {
    const files = await fsp.readdir(ENVELOPE_QUESTIONS_DIR);
    if (files.filter(f => f.endsWith('.json')).length === 0) {
      console.log('Инициализация дефолтных вопросов конверта...');
      for (const q of defaultEnvelopeQuestions) {
        const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${q.id}.json`);
        await fsp.writeFile(filePath, JSON.stringify({ ...q, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() }, null, 2));
      }
      console.log('✅ Дефолтные вопросы конверта созданы');
    }
  } catch (e) {
    console.error('Ошибка инициализации вопросов конверта:', e);
  }
})();

// GET /api/envelope-questions - получить все вопросы
app.get('/api/envelope-questions', async (req, res) => {
  try {
    console.log('GET /api/envelope-questions');
    const files = await fsp.readdir(ENVELOPE_QUESTIONS_DIR);
    const questions = [];

    for (const file of files) {
      if (file.endsWith('.json')) {
        const filePath = path.join(ENVELOPE_QUESTIONS_DIR, file);
        const data = await fsp.readFile(filePath, 'utf8');
        const question = JSON.parse(data);
        questions.push(question);
      }
    }

    // Сортировка по order
    questions.sort((a, b) => (a.order || 0) - (b.order || 0));

    res.json({ success: true, questions });
  } catch (error) {
    console.error('Ошибка получения вопросов конверта:', error);
    res.status(500).json({ success: false, error: error.message, questions: [] });
  }
});

// GET /api/envelope-questions/:id - получить один вопрос
app.get('/api/envelope-questions/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({ success: false, error: 'Вопрос не найден' });
    }

    const data = await fsp.readFile(filePath, 'utf8');
    const question = JSON.parse(data);

    res.json({ success: true, question });
  } catch (error) {
    console.error('Ошибка получения вопроса конверта:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/envelope-questions - создать вопрос
app.post('/api/envelope-questions', async (req, res) => {
  try {
    console.log('POST /api/envelope-questions:', JSON.stringify(req.body).substring(0, 200));

    const questionId = req.body.id || `envelope_q_${Date.now()}`;
    const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${sanitizedId}.json`);

    const question = {
      id: questionId,
      title: req.body.title || '',
      description: req.body.description || '',
      type: req.body.type || 'photo',
      section: req.body.section || 'general',
      order: req.body.order || 1,
      isRequired: req.body.isRequired !== false,
      isActive: req.body.isActive !== false,
      referencePhotoUrl: req.body.referencePhotoUrl || null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
    console.log('Вопрос конверта создан:', filePath);

    res.json({ success: true, question });
  } catch (error) {
    console.error('Ошибка создания вопроса конверта:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/envelope-questions/:id - обновить вопрос
app.put('/api/envelope-questions/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('PUT /api/envelope-questions:', id);

    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${sanitizedId}.json`);

    // Если файл не существует, создаем новый
    let question = {};
    if (await fileExists(filePath)) {
      const existingData = await fsp.readFile(filePath, 'utf8');
      question = JSON.parse(existingData);
    }

    // Обновляем поля
    if (req.body.title !== undefined) question.title = req.body.title;
    if (req.body.description !== undefined) question.description = req.body.description;
    if (req.body.type !== undefined) question.type = req.body.type;
    if (req.body.section !== undefined) question.section = req.body.section;
    if (req.body.order !== undefined) question.order = req.body.order;
    if (req.body.isRequired !== undefined) question.isRequired = req.body.isRequired;
    if (req.body.isActive !== undefined) question.isActive = req.body.isActive;
    if (req.body.referencePhotoUrl !== undefined) question.referencePhotoUrl = req.body.referencePhotoUrl;

    question.id = id;
    question.updatedAt = new Date().toISOString();
    if (!question.createdAt) question.createdAt = new Date().toISOString();

    await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
    console.log('Вопрос конверта обновлен:', filePath);

    res.json({ success: true, question });
  } catch (error) {
    console.error('Ошибка обновления вопроса конверта:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/envelope-questions/:id - удалить вопрос
app.delete('/api/envelope-questions/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('DELETE /api/envelope-questions:', id);

    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({ success: false, error: 'Вопрос не найден' });
    }

    await fsp.unlink(filePath);
    console.log('Вопрос конверта удален:', filePath);

    res.json({ success: true, message: 'Вопрос успешно удален' });
  } catch (error) {
    console.error('Ошибка удаления вопроса конверта:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ========== API для отчётов конвертов ==========
const ENVELOPE_REPORTS_DIR = `${DATA_DIR}/envelope-reports`;
(async () => {
  if (!await fileExists(ENVELOPE_REPORTS_DIR)) {
    await fsp.mkdir(ENVELOPE_REPORTS_DIR, { recursive: true });
  }
})();

// GET /api/envelope-reports - получить все отчеты
app.get('/api/envelope-reports', async (req, res) => {
  try {
    console.log('GET /api/envelope-reports:', req.query);
    let { shopAddress, status, fromDate, toDate } = req.query;

    // Декодируем shop address если он URL-encoded
    if (shopAddress && shopAddress.includes('%')) {
      try {
        shopAddress = decodeURIComponent(shopAddress);
        console.log(`  📋 Декодирован shop address: "${shopAddress}"`);
      } catch (e) {
        console.error('  ⚠️ Ошибка декодирования shopAddress:', e);
      }
    }

    // Нормализуем адрес магазина для сравнения (убираем лишние пробелы)
    const normalizedShopAddress = shopAddress ? shopAddress.trim() : null;
    if (normalizedShopAddress) {
      console.log(`  📋 Фильтр по магазину: "${normalizedShopAddress}" (длина: ${normalizedShopAddress.length})`);
    }

    const reports = [];
    if (await fileExists(ENVELOPE_REPORTS_DIR)) {
      const files = await fs.promises.readdir(ENVELOPE_REPORTS_DIR);
      const jsonFiles = files.filter(f => f.endsWith('.json'));
      console.log(`  📋 Найдено файлов конвертов: ${jsonFiles.length}`);

      for (const file of jsonFiles) {
        try {
          const content = await fs.promises.readFile(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8');
          const report = JSON.parse(content);

          // Применяем фильтры (с нормализацией адреса)
          if (normalizedShopAddress) {
            const reportShopTrimmed = report.shopAddress.trim();
            console.log(`  📋 Сравнение: "${reportShopTrimmed}" (длина: ${reportShopTrimmed.length}) === "${normalizedShopAddress}" (длина: ${normalizedShopAddress.length}) => ${reportShopTrimmed === normalizedShopAddress}`);
            if (reportShopTrimmed !== normalizedShopAddress) continue;
          }
          if (status && report.status !== status) continue;
          if (fromDate && new Date(report.createdAt) < new Date(fromDate)) continue;
          if (toDate && new Date(report.createdAt) > new Date(toDate)) continue;

          reports.push(report);
        } catch (e) {
          console.error(`Ошибка чтения ${file}:`, e);
        }
      }
    }

    // Сортируем по дате создания (новые первыми)
    reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    res.json({ success: true, reports });
  } catch (error) {
    console.error('Ошибка получения отчетов конвертов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/envelope-reports/expired - получить просроченные отчеты
app.get('/api/envelope-reports/expired', async (req, res) => {
  try {
    console.log('GET /api/envelope-reports/expired');

    const reports = [];
    if (await fileExists(ENVELOPE_REPORTS_DIR)) {
      const files = await fs.promises.readdir(ENVELOPE_REPORTS_DIR);
      const jsonFiles = files.filter(f => f.endsWith('.json'));

      for (const file of jsonFiles) {
        try {
          const content = await fs.promises.readFile(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8');
          const report = JSON.parse(content);

          // Проверяем: не подтверждён И прошло более 24 часов
          if (report.status === 'pending') {
            const createdAt = new Date(report.createdAt);
            const now = new Date();
            const diffHours = (now - createdAt) / (1000 * 60 * 60);

            if (diffHours >= 24) {
              reports.push(report);
            }
          }
        } catch (e) {
          console.error(`Ошибка чтения ${file}:`, e);
        }
      }
    }

    // Сортируем по дате создания (старые первыми)
    reports.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));

    res.json({ success: true, reports });
  } catch (error) {
    console.error('Ошибка получения просроченных отчетов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/envelope-reports/:id - получить один отчет
app.get('/api/envelope-reports/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('GET /api/envelope-reports/:id', id);

    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(ENVELOPE_REPORTS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({ success: false, error: 'Отчет не найден' });
    }

    const content = await fs.promises.readFile(filePath, 'utf8');
    const report = JSON.parse(content);

    res.json({ success: true, report });
  } catch (error) {
    console.error('Ошибка получения отчета:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/envelope-reports - создать новый отчет
app.post('/api/envelope-reports', async (req, res) => {
  try {
    console.log('POST /api/envelope-reports:', JSON.stringify(req.body).substring(0, 300));

    const reportId = req.body.id || `envelope_report_${Date.now()}`;
    const report = {
      ...req.body,
      id: reportId,
      createdAt: new Date().toISOString(),
      status: req.body.status || 'pending',
    };

    const sanitizedId = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(ENVELOPE_REPORTS_DIR, `${sanitizedId}.json`);

    await fs.promises.writeFile(filePath, JSON.stringify(report, null, 2), 'utf8');
    console.log('Отчет конверта создан:', filePath);

    res.json({ success: true, report });
  } catch (error) {
    console.error('Ошибка создания отчета конверта:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/envelope-reports/:id - обновить отчет
app.put('/api/envelope-reports/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('PUT /api/envelope-reports/:id', id);

    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(ENVELOPE_REPORTS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({ success: false, error: 'Отчет не найден' });
    }

    const content = await fs.promises.readFile(filePath, 'utf8');
    const existingReport = JSON.parse(content);

    const updatedReport = {
      ...existingReport,
      ...req.body,
      id: existingReport.id, // Не меняем ID
      createdAt: existingReport.createdAt, // Не меняем дату создания
    };

    await fs.promises.writeFile(filePath, JSON.stringify(updatedReport, null, 2), 'utf8');
    console.log('Отчет конверта обновлён:', filePath);

    res.json({ success: true, report: updatedReport });
  } catch (error) {
    console.error('Ошибка обновления отчета:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/envelope-reports/:id/confirm - подтвердить отчет с оценкой
app.put('/api/envelope-reports/:id/confirm', async (req, res) => {
  try {
    const { id } = req.params;
    const { confirmedByAdmin, rating } = req.body;
    console.log('PUT /api/envelope-reports/:id/confirm', id, confirmedByAdmin, rating);

    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(ENVELOPE_REPORTS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({ success: false, error: 'Отчет не найден' });
    }

    const content = await fs.promises.readFile(filePath, 'utf8');
    const report = JSON.parse(content);

    report.status = 'confirmed';
    report.confirmedAt = new Date().toISOString();
    report.confirmedByAdmin = confirmedByAdmin;
    report.rating = rating;

    await fs.promises.writeFile(filePath, JSON.stringify(report, null, 2), 'utf8');
    console.log('Отчет конверта подтверждён:', filePath);

    res.json({ success: true, report });
  } catch (error) {
    console.error('Ошибка подтверждения отчета:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/envelope-reports/:id - удалить отчет
app.delete('/api/envelope-reports/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('DELETE /api/envelope-reports/:id', id);

    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(ENVELOPE_REPORTS_DIR, `${sanitizedId}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({ success: false, error: 'Отчет не найден' });
    }

    await fs.promises.unlink(filePath);
    console.log('Отчет конверта удалён:', filePath);

    res.json({ success: true, message: 'Отчет успешно удален' });
  } catch (error) {
    console.error('Ошибка удаления отчета:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/envelope-pending - получить pending отчеты
app.get('/api/envelope-pending', async (req, res) => {
  try {
    console.log('GET /api/envelope-pending');
    const pendingDir = `${DATA_DIR}/envelope-pending`;
    const reports = [];

    if (await fileExists(pendingDir)) {
      const files = await fs.promises.readdir(pendingDir);

      for (const file of files) {
        if (file.startsWith('pending_env_')) {
          try {
            const content = await fs.promises.readFile(path.join(pendingDir, file), 'utf8');
            const data = JSON.parse(content);
            if (data.status === 'pending') {
              reports.push(data);
            }
          } catch (e) {
            console.error(`Ошибка чтения ${file}:`, e);
          }
        }
      }
    }

    // Сортируем по дате создания (новые первыми)
    reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    res.json(reports);
  } catch (error) {
    console.error('Ошибка получения pending отчетов:', error);
    res.status(500).json({ error: error.message });
  }
});

// GET /api/envelope-failed - получить failed отчеты
app.get('/api/envelope-failed', async (req, res) => {
  try {
    console.log('GET /api/envelope-failed');
    const pendingDir = `${DATA_DIR}/envelope-pending`;
    const reports = [];

    if (await fileExists(pendingDir)) {
      const files = await fs.promises.readdir(pendingDir);

      for (const file of files) {
        if (file.startsWith('pending_env_')) {
          try {
            const content = await fs.promises.readFile(path.join(pendingDir, file), 'utf8');
            const data = JSON.parse(content);
            if (data.status === 'failed') {
              reports.push(data);
            }
          } catch (e) {
            console.error(`Ошибка чтения ${file}:`, e);
          }
        }
      }
    }

    // Сортируем по дате создания (новые первыми)
    reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    res.json(reports);
  } catch (error) {
    console.error('Ошибка получения failed отчетов:', error);
    res.status(500).json({ error: error.message });
  }
});

// ========== API для клиентов ==========
const CLIENTS_DIR = `${DATA_DIR}/clients`;
(async () => {
  if (!await fileExists(CLIENTS_DIR)) {
    await fsp.mkdir(CLIENTS_DIR, { recursive: true });
  }
})();

app.get('/api/clients', async (req, res) => {
  try {
    let clients = [];
    if (await fileExists(CLIENTS_DIR)) {
      const files = await fs.promises.readdir(CLIENTS_DIR);
      const jsonFiles = files.filter(f => f.endsWith('.json'));
      const readPromises = jsonFiles.map(async (file) => {
        try {
          const content = await fs.promises.readFile(path.join(CLIENTS_DIR, file), 'utf8');
          return JSON.parse(content);
        } catch (e) {
          console.error(`Ошибка чтения ${file}:`, e);
          return null;
        }
      });
      const results = await Promise.all(readPromises);
      clients.push(...results.filter(r => r !== null));
    }

    // SCALABILITY: Поддержка поиска по имени/телефону
    const { search } = req.query;
    if (search) {
      const searchLower = search.toLowerCase();
      clients = clients.filter(c =>
        (c.name && c.name.toLowerCase().includes(searchLower)) ||
        (c.phone && c.phone.includes(search))
      );
    }

    // SCALABILITY: Сортировка по дате обновления (новые сверху)
    clients.sort((a, b) => {
      const dateA = new Date(a.updatedAt || a.createdAt || 0);
      const dateB = new Date(b.updatedAt || b.createdAt || 0);
      return dateB - dateA;
    });

    // SCALABILITY: Пагинация если запрошена
    if (isPaginationRequested(req.query)) {
      res.json(createPaginatedResponse(clients, req.query, 'clients'));
    } else {
      res.json({ success: true, clients });
    }
  } catch (error) {
    console.error('Ошибка получения клиентов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/clients', async (req, res) => {
  try {
    if (!req.body.phone) {
      return res.status(400).json({ success: false, error: 'Номер телефона обязателен' });
    }
    const normalizedPhone = req.body.phone.replace(/[\s\+]/g, '');
    const sanitizedPhone = normalizedPhone.replace(/[^0-9]/g, '_');
    const clientFile = path.join(CLIENTS_DIR, `${sanitizedPhone}.json`);

    // Проверяем, был ли уже referredBy у клиента ранее
    let existingClient = null;
    if (await fileExists(clientFile)) {
      existingClient = JSON.parse(await fsp.readFile(clientFile, 'utf8'));
    }
    const isNewReferral = req.body.referredBy && (!existingClient || !existingClient.referredBy);

    // ФАЗА 1.3: Проверка лимита рефералов (антифрод)
    if (isNewReferral) {
      const limitCheck = checkReferralLimit(parseInt(req.body.referredBy, 10));
      if (!limitCheck.allowed) {
        console.warn(`⚠️ АНТИФРОД: Блокировка приглашения от кода ${req.body.referredBy} (лимит превышен)`);
        return res.status(429).json({
          success: false,
          error: `Превышен дневной лимит приглашений для этого кода. Попробуйте завтра.`,
          limitExceeded: true,
          todayCount: limitCheck.todayCount,
          limit: limitCheck.limit
        });
      }
    }

    const client = {
      phone: normalizedPhone,
      name: req.body.name || '',
      clientName: req.body.clientName || req.body.name || '',
      fcmToken: req.body.fcmToken || null,
      referredBy: req.body.referredBy || null,
      referredAt: req.body.referredBy ? new Date().toISOString() : null,
      // ФАЗА 2.1: Статус реферала (registered, first_purchase, active)
      referralStatus: req.body.referredBy ? 'registered' : null,
      referralStatusHistory: req.body.referredBy ? [
        { status: 'registered', date: new Date().toISOString() }
      ] : [],
      createdAt: existingClient?.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    await fsp.writeFile(clientFile, JSON.stringify(client, null, 2), 'utf8');

    // Отправляем push-уведомление админам о новом приглашении
    if (isNewReferral) {
      try {
        // Ищем сотрудника по referralCode
        let employeeName = 'Сотрудник';
        const employeesDir = `${DATA_DIR}/employees`;
        if (await fileExists(employeesDir)) {
          const empFiles = (await fsp.readdir(employeesDir)).filter(f => f.endsWith('.json'));
          for (const empFile of empFiles) {
            const emp = JSON.parse(await fsp.readFile(path.join(employeesDir, empFile), 'utf8'));
            if (emp.referralCode === parseInt(req.body.referredBy, 10)) {
              employeeName = emp.name || 'Сотрудник';
              break;
            }
          }
        }

        const clientName = client.name || client.clientName || client.phone;
        await sendPushNotification(
          'Новый приглашённый клиент',
          `${clientName} приглашён ${employeeName}`,
          { type: 'new_referral', clientPhone: client.phone }
        );
        console.log(`✅ Push отправлен админам о новом приглашении: ${clientName} -> ${employeeName}`);
      } catch (pushError) {
        console.error('Ошибка отправки push о приглашении:', pushError);
      }

      // Инвалидируем кэш статистики рефералов (ФАЗА 1.1)
      try {
        invalidateStatsCache();
      } catch (cacheError) {
        console.error('Ошибка инвалидации кэша рефералов:', cacheError);
      }
    }

    res.json({ success: true, client });
  } catch (error) {
    console.error('Ошибка сохранения клиента:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/clients/:phone/free-drink - увеличить счётчик бесплатных напитков
app.post('/api/clients/:phone/free-drink', async (req, res) => {
  try {
    const { phone } = req.params;
    const { count = 1 } = req.body;

    const normalizedPhone = phone.replace(/[\s\+]/g, '');
    const sanitizedPhone = normalizedPhone.replace(/[^0-9]/g, '_');
    const clientFile = path.join(CLIENTS_DIR, `${sanitizedPhone}.json`);

    if (!await fileExists(clientFile)) {
      return res.status(404).json({ success: false, error: 'Клиент не найден' });
    }

    const client = JSON.parse(await fsp.readFile(clientFile, 'utf8'));
    client.freeDrinksGiven = (client.freeDrinksGiven || 0) + count;
    client.updatedAt = new Date().toISOString();

    await fsp.writeFile(clientFile, JSON.stringify(client, null, 2), 'utf8');

    console.log(`🍹 Выдан бесплатный напиток клиенту ${client.name || phone}. Всего: ${client.freeDrinksGiven}`);
    res.json({ success: true, client });
  } catch (error) {
    console.error('Ошибка обновления счётчика напитков:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ========== API для сообщений клиентам (network messages) ==========
const NETWORK_MESSAGES_DIR = `${DATA_DIR}/network-messages`;
(async () => {
  if (!await fileExists(NETWORK_MESSAGES_DIR)) {
    await fsp.mkdir(NETWORK_MESSAGES_DIR, { recursive: true });
  }
})();

// POST /api/clients/:phone/messages - отправить сообщение одному клиенту
app.post('/api/clients/:phone/messages', async (req, res) => {
  try {
    const { phone } = req.params;
    const { text, imageUrl, senderPhone } = req.body;

    if (!text) {
      return res.status(400).json({ success: false, error: 'Текст сообщения обязателен' });
    }

    const normalizedPhone = phone.replace(/[\s\+]/g, '');
    const sanitizedPhone = normalizedPhone.replace(/[^0-9]/g, '_');

    // Создаём сообщение
    const messageId = `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const message = {
      id: messageId,
      clientPhone: normalizedPhone,
      senderPhone: senderPhone || 'admin',
      text: text,
      imageUrl: imageUrl || null,
      timestamp: new Date().toISOString(),
      isRead: false,
      source: 'network' // сетевое сообщение от админа
    };

    // Сохраняем сообщение в файл клиента
    const messagesFile = path.join(NETWORK_MESSAGES_DIR, `${sanitizedPhone}.json`);
    let messages = [];
    if (await fileExists(messagesFile)) {
      messages = JSON.parse(await fsp.readFile(messagesFile, 'utf8'));
    }
    messages.push(message);
    await fsp.writeFile(messagesFile, JSON.stringify(messages, null, 2), 'utf8');

    // Отправляем push-уведомление клиенту
    try {
      const clientFile = path.join(CLIENTS_DIR, `${sanitizedPhone}.json`);
      if (await fileExists(clientFile)) {
        const client = JSON.parse(await fsp.readFile(clientFile, 'utf8'));
        if (client.fcmToken) {
          await sendPushToPhone(
            normalizedPhone,
            'Новое сообщение',
            text.length > 100 ? text.substring(0, 100) + '...' : text,
            { type: 'network_message', messageId }
          );
          console.log(`📨 Push отправлен клиенту ${normalizedPhone}`);
        }
      }
    } catch (pushError) {
      console.error('Ошибка отправки push клиенту:', pushError);
    }

    console.log(`📨 Сообщение отправлено клиенту ${normalizedPhone}`);
    res.json({ success: true, message });
  } catch (error) {
    console.error('Ошибка отправки сообщения клиенту:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/clients/messages/broadcast - отправить сообщение всем клиентам
app.post('/api/clients/messages/broadcast', async (req, res) => {
  try {
    const { text, imageUrl, senderPhone } = req.body;

    if (!text) {
      return res.status(400).json({ success: false, error: 'Текст сообщения обязателен' });
    }

    console.log(`📢 Рассылка сообщения всем клиентам: ${text.substring(0, 50)}...`);

    // Получаем всех клиентов
    const clients = [];
    if (await fileExists(CLIENTS_DIR)) {
      const files = (await fsp.readdir(CLIENTS_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const content = await fsp.readFile(path.join(CLIENTS_DIR, file), 'utf8');
          clients.push(JSON.parse(content));
        } catch (e) {
          console.error(`Ошибка чтения ${file}:`, e);
        }
      }
    }

    let sentCount = 0;
    const broadcastId = `broadcast_${Date.now()}`;

    for (const client of clients) {
      try {
        const normalizedPhone = client.phone.replace(/[\s\+]/g, '');
        const sanitizedPhone = normalizedPhone.replace(/[^0-9]/g, '_');

        // Создаём сообщение для этого клиента
        const messageId = `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        const message = {
          id: messageId,
          broadcastId: broadcastId,
          clientPhone: normalizedPhone,
          senderPhone: senderPhone || 'admin',
          text: text,
          imageUrl: imageUrl || null,
          timestamp: new Date().toISOString(),
          isRead: false,
          source: 'broadcast'
        };

        // Сохраняем сообщение
        const messagesFile = path.join(NETWORK_MESSAGES_DIR, `${sanitizedPhone}.json`);
        let messages = [];
        if (await fileExists(messagesFile)) {
          messages = JSON.parse(await fsp.readFile(messagesFile, 'utf8'));
        }
        messages.push(message);
        await fsp.writeFile(messagesFile, JSON.stringify(messages, null, 2), 'utf8');

        // Отправляем push если есть токен
        if (client.fcmToken) {
          try {
            await sendPushToPhone(
              normalizedPhone,
              'Новое сообщение от Arabica',
              text.length > 100 ? text.substring(0, 100) + '...' : text,
              { type: 'broadcast_message', messageId, broadcastId }
            );
          } catch (pushError) {
            // Игнорируем ошибки push для отдельных клиентов
          }
        }

        sentCount++;
      } catch (clientError) {
        console.error(`Ошибка отправки клиенту ${client.phone}:`, clientError);
      }
    }

    console.log(`📢 Рассылка завершена: ${sentCount}/${clients.length} клиентов`);
    res.json({
      success: true,
      sentCount,
      totalClients: clients.length,
      broadcastId
    });
  } catch (error) {
    console.error('Ошибка рассылки:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/clients/:phone/messages - получить сообщения клиента
app.get('/api/clients/:phone/messages', async (req, res) => {
  try {
    const { phone } = req.params;
    const normalizedPhone = phone.replace(/[\s\+]/g, '');
    const sanitizedPhone = normalizedPhone.replace(/[^0-9]/g, '_');

    const messagesFile = path.join(NETWORK_MESSAGES_DIR, `${sanitizedPhone}.json`);
    let messages = [];
    if (await fileExists(messagesFile)) {
      messages = JSON.parse(await fsp.readFile(messagesFile, 'utf8'));
    }

    res.json({ success: true, messages });
  } catch (error) {
    console.error('Ошибка получения сообщений:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ========== API для отчетов пересменки ==========
const SHIFT_REPORTS_DIR = `${DATA_DIR}/shift-reports`;
(async () => {
  if (!await fileExists(SHIFT_REPORTS_DIR)) {
    await fsp.mkdir(SHIFT_REPORTS_DIR, { recursive: true });
  }
})();

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

    res.json({ success: true, reports });
  } catch (error) {
    console.error('Ошибка получения отчетов пересменки:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/shift-reports', async (req, res) => {
  try {
    const { getShiftSettings, loadTodayReports, saveTodayReports } = require('./api/shift_automation_scheduler');
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
        const efficiencyPoints = calculateShiftPoints(rating, settings);
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

// ========== API для статей обучения ==========
const TRAINING_ARTICLES_DIR = `${DATA_DIR}/training-articles`;
(async () => {
  if (!await fileExists(TRAINING_ARTICLES_DIR)) {
    await fsp.mkdir(TRAINING_ARTICLES_DIR, { recursive: true });
  }
})();

app.get('/api/training-articles', async (req, res) => {
  try {
    const articles = [];
    if (await fileExists(TRAINING_ARTICLES_DIR)) {
      const files = (await fsp.readdir(TRAINING_ARTICLES_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const content = await fsp.readFile(path.join(TRAINING_ARTICLES_DIR, file), 'utf8');
          articles.push(JSON.parse(content));
        } catch (e) {
          console.error(`Ошибка чтения ${file}:`, e);
        }
      }
    }
    res.json({ success: true, articles });
  } catch (error) {
    console.error('Ошибка получения статей обучения:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/training-articles', async (req, res) => {
  try {
    const article = {
      id: `training_article_${Date.now()}`,
      group: req.body.group,
      title: req.body.title,
      content: req.body.content || '',  // Контент статьи
      visibility: req.body.visibility || 'all',  // Видимость: 'all' или 'managers'
      createdAt: new Date().toISOString(),
    };
    // URL опционален (для обратной совместимости)
    if (req.body.url) {
      article.url = req.body.url;
    }
    // Блоки контента (текст + изображения)
    if (req.body.contentBlocks && Array.isArray(req.body.contentBlocks)) {
      article.contentBlocks = req.body.contentBlocks;
    }
    const articleFile = path.join(TRAINING_ARTICLES_DIR, `${article.id}.json`);
    await fsp.writeFile(articleFile, JSON.stringify(article, null, 2), 'utf8');
    res.json({ success: true, article });
  } catch (error) {
    console.error('Ошибка создания статьи обучения:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.put('/api/training-articles/:id', async (req, res) => {
  try {
    const safeId = sanitizeId(req.params.id);
    const articleFile = path.join(TRAINING_ARTICLES_DIR, `${safeId}.json`);
    if (!isPathSafe(TRAINING_ARTICLES_DIR, articleFile)) {
      return res.status(400).json({ success: false, error: 'Invalid article ID' });
    }
    if (!await fileExists(articleFile)) {
      return res.status(404).json({ success: false, error: 'Статья не найдена' });
    }
    const article = JSON.parse(await fsp.readFile(articleFile, 'utf8'));
    if (req.body.group !== undefined) article.group = req.body.group;
    if (req.body.title !== undefined) article.title = req.body.title;
    if (req.body.content !== undefined) article.content = req.body.content;
    if (req.body.url !== undefined) article.url = req.body.url;
    if (req.body.visibility !== undefined) article.visibility = req.body.visibility;
    // Блоки контента (текст + изображения)
    if (req.body.contentBlocks !== undefined) {
      article.contentBlocks = req.body.contentBlocks;
    }
    article.updatedAt = new Date().toISOString();
    await fsp.writeFile(articleFile, JSON.stringify(article, null, 2), 'utf8');
    res.json({ success: true, article });
  } catch (error) {
    console.error('Ошибка обновления статьи обучения:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.delete('/api/training-articles/:id', async (req, res) => {
  try {
    const safeId = sanitizeId(req.params.id);
    const articleFile = path.join(TRAINING_ARTICLES_DIR, `${safeId}.json`);
    if (!isPathSafe(TRAINING_ARTICLES_DIR, articleFile)) {
      return res.status(400).json({ success: false, error: 'Invalid article ID' });
    }
    if (!await fileExists(articleFile)) {
      return res.status(404).json({ success: false, error: 'Статья не найдена' });
    }
    await fsp.unlink(articleFile);
    res.json({ success: true });
  } catch (error) {
    console.error('Ошибка удаления статьи обучения:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Настройка multer для загрузки изображений статей обучения
const TRAINING_ARTICLES_MEDIA_DIR = `${DATA_DIR}/training-articles-media`;
(async () => {
  if (!await fileExists(TRAINING_ARTICLES_MEDIA_DIR)) {
    await fsp.mkdir(TRAINING_ARTICLES_MEDIA_DIR, { recursive: true });
  }
})();

const trainingArticleMediaStorage = multer.diskStorage({
  destination: async function (req, file, cb) {
    if (!await fileExists(TRAINING_ARTICLES_MEDIA_DIR)) {
      await fsp.mkdir(TRAINING_ARTICLES_MEDIA_DIR, { recursive: true });
    }
    cb(null, TRAINING_ARTICLES_MEDIA_DIR);
  },
  filename: function (req, file, cb) {
    // SECURITY: Безопасное извлечение расширения
    const safeBasename = path.basename(file.originalname);
    const ext = path.extname(safeBasename).replace(/[^a-zA-Z0-9\.]/g, '') || '.jpg';
    const uniqueName = `training_img_${Date.now()}_${Math.random().toString(36).substr(2, 9)}${ext}`;
    cb(null, uniqueName);
  }
});

const uploadTrainingArticleMedia = multer({
  storage: trainingArticleMediaStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: function (req, file, cb) {
    const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
    if (allowedTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Разрешены только изображения (JPEG, PNG, GIF, WebP)'));
    }
  }
});

// Загрузка изображения для статьи обучения
app.post('/api/training-articles/upload-image', uploadTrainingArticleMedia.single('image'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'Файл не загружен' });
    }

    const imageUrl = `https://arabica26.ru/training-articles-media/${req.file.filename}`;
    console.log(`📷 Загружено изображение статьи обучения: ${req.file.filename}`);

    res.json({
      success: true,
      imageUrl: imageUrl,
      filename: req.file.filename,
    });
  } catch (error) {
    console.error('Ошибка загрузки изображения статьи:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Удаление изображения статьи обучения
app.delete('/api/training-articles/delete-image/:filename', async (req, res) => {
  try {
    const filename = req.params.filename;
    const filePath = path.join(TRAINING_ARTICLES_MEDIA_DIR, filename);

    if (!await fileExists(filePath)) {
      return res.status(404).json({ success: false, error: 'Изображение не найдено' });
    }

    await fsp.unlink(filePath);
    console.log(`🗑️ Удалено изображение статьи обучения: ${filename}`);

    res.json({ success: true });
  } catch (error) {
    console.error('Ошибка удаления изображения статьи:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Статические файлы для изображений статей обучения
app.use('/training-articles-media', express.static(TRAINING_ARTICLES_MEDIA_DIR));

// ========== API для вопросов тестирования ==========
const TEST_QUESTIONS_DIR = `${DATA_DIR}/test-questions`;
(async () => {
  if (!await fileExists(TEST_QUESTIONS_DIR)) {
    await fsp.mkdir(TEST_QUESTIONS_DIR, { recursive: true });
  }
})();

app.get('/api/test-questions', async (req, res) => {
  try {
    const questions = [];
    if (await fileExists(TEST_QUESTIONS_DIR)) {
      const files = (await fsp.readdir(TEST_QUESTIONS_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const content = await fsp.readFile(path.join(TEST_QUESTIONS_DIR, file), 'utf8');
          questions.push(JSON.parse(content));
        } catch (e) {
          console.error(`Ошибка чтения ${file}:`, e);
        }
      }
    }
    res.json({ success: true, questions });
  } catch (error) {
    console.error('Ошибка получения вопросов тестирования:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/test-questions', async (req, res) => {
  try {
    const question = {
      id: `test_question_${Date.now()}`,
      question: req.body.question,
      answerA: req.body.answerA,
      answerB: req.body.answerB,
      answerC: req.body.answerC,
      correctAnswer: req.body.correctAnswer,
      createdAt: new Date().toISOString(),
    };
    const questionFile = path.join(TEST_QUESTIONS_DIR, `${question.id}.json`);
    await fsp.writeFile(questionFile, JSON.stringify(question, null, 2), 'utf8');
    res.json({ success: true, question });
  } catch (error) {
    console.error('Ошибка создания вопроса тестирования:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.put('/api/test-questions/:id', async (req, res) => {
  try {
    const safeId = sanitizeId(req.params.id);
    const questionFile = path.join(TEST_QUESTIONS_DIR, `${safeId}.json`);
    if (!isPathSafe(TEST_QUESTIONS_DIR, questionFile)) {
      return res.status(400).json({ success: false, error: 'Invalid question ID' });
    }
    if (!await fileExists(questionFile)) {
      return res.status(404).json({ success: false, error: 'Вопрос не найден' });
    }
    const question = JSON.parse(await fsp.readFile(questionFile, 'utf8'));
    if (req.body.question) question.question = req.body.question;
    if (req.body.answerA) question.answerA = req.body.answerA;
    if (req.body.answerB) question.answerB = req.body.answerB;
    if (req.body.answerC) question.answerC = req.body.answerC;
    if (req.body.correctAnswer) question.correctAnswer = req.body.correctAnswer;
    question.updatedAt = new Date().toISOString();
    await fsp.writeFile(questionFile, JSON.stringify(question, null, 2), 'utf8');
    res.json({ success: true, question });
  } catch (error) {
    console.error('Ошибка обновления вопроса тестирования:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.delete('/api/test-questions/:id', async (req, res) => {
  try {
    const safeId = sanitizeId(req.params.id);
    const questionFile = path.join(TEST_QUESTIONS_DIR, `${safeId}.json`);
    if (!isPathSafe(TEST_QUESTIONS_DIR, questionFile)) {
      return res.status(400).json({ success: false, error: 'Invalid question ID' });
    }
    if (!await fileExists(questionFile)) {
      return res.status(404).json({ success: false, error: 'Вопрос не найден' });
    }
    await fsp.unlink(questionFile);
    res.json({ success: true });
  } catch (error) {
    console.error('Ошибка удаления вопроса тестирования:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ========== API для результатов тестирования ==========
const TEST_RESULTS_DIR = `${DATA_DIR}/test-results`;
(async () => {
  if (!await fileExists(TEST_RESULTS_DIR)) {
    await fsp.mkdir(TEST_RESULTS_DIR, { recursive: true });
  }
})();

// GET /api/test-results - получить все результаты тестов
app.get('/api/test-results', async (req, res) => {
  try {
    console.log('GET /api/test-results');
    const results = [];
    if (await fileExists(TEST_RESULTS_DIR)) {
      const files = (await fsp.readdir(TEST_RESULTS_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const content = await fsp.readFile(path.join(TEST_RESULTS_DIR, file), 'utf8');
          const result = JSON.parse(content);
          results.push(result);
        } catch (e) {
          console.error(`Ошибка чтения ${file}:`, e);
        }
      }
    }
    // Сортировка по дате (новые сначала)
    results.sort((a, b) => new Date(b.completedAt) - new Date(a.completedAt));
    console.log(`✅ Найдено результатов тестов: ${results.length}`);
    res.json({ success: true, results });
  } catch (error) {
    console.error('Ошибка получения результатов тестов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * Начисление баллов за прохождение теста
 * Использует линейную интерполяцию для расчета баллов
 */
async function assignTestPoints(result) {
  try {
    const now = new Date(result.completedAt || Date.now());
    const today = now.toISOString().split('T')[0];
    const monthKey = today.substring(0, 7); // YYYY-MM

    // Загрузка настроек баллов
    const settingsFile = `${DATA_DIR}/points-settings/test_points_settings.json`;
    let settings = {
      maxPoints: 5,
      minPoints: -2,
      zeroThreshold: 12
    };

    if (await fileExists(settingsFile)) {
      try {
        const settingsData = await fsp.readFile(settingsFile, 'utf8');
        settings = JSON.parse(settingsData);
      } catch (e) {
        console.error('Error loading test settings:', e);
      }
    }

    // Расчет баллов через линейную интерполяцию
    const { score, totalQuestions } = result;
    let points = 0;

    if (totalQuestions === 0) {
      points = 0;
    } else if (score <= 0) {
      points = settings.minPoints;
    } else if (score >= totalQuestions) {
      points = settings.maxPoints;
    } else if (score <= settings.zeroThreshold) {
      // Интерполяция от minPoints до 0
      points = settings.minPoints + (0 - settings.minPoints) * (score / settings.zeroThreshold);
    } else {
      // Интерполяция от 0 до maxPoints
      const range = totalQuestions - settings.zeroThreshold;
      points = (settings.maxPoints - 0) * ((score - settings.zeroThreshold) / range);
    }

    // Округление до 2 знаков
    points = Math.round(points * 100) / 100;

    // Дедупликация
    const sourceId = `test_${result.id}`;
    const PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;
    if (!await fileExists(PENALTIES_DIR)) {
      await fsp.mkdir(PENALTIES_DIR, { recursive: true });
    }

    const penaltiesFile = path.join(PENALTIES_DIR, `${monthKey}.json`);
    let penalties = [];

    if (await fileExists(penaltiesFile)) {
      try {
        penalties = JSON.parse(await fsp.readFile(penaltiesFile, 'utf8'));
      } catch (e) {
        console.error('Error reading penalties file:', e);
      }
    }

    const exists = penalties.some(p => p.sourceId === sourceId);
    if (exists) {
      console.log(`Points already assigned for test ${result.id}, skipping`);
      return { success: true, skipped: true };
    }

    // Создание записи
    const entry = {
      id: `test_pts_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type: 'employee',
      entityId: result.employeePhone,
      entityName: result.employeeName,
      shopAddress: result.shopAddress || '',
      employeeName: result.employeeName,
      category: points >= 0 ? 'test_bonus' : 'test_penalty',
      categoryName: 'Прохождение теста',
      date: today,
      points: points,
      reason: `Тест: ${score}/${totalQuestions} правильных (${Math.round((score/totalQuestions)*100)}%)`,
      sourceId: sourceId,
      sourceType: 'test_result',
      createdAt: now.toISOString()
    };

    penalties.push(entry);
    await fsp.writeFile(penaltiesFile, JSON.stringify(penalties, null, 2), 'utf8');

    console.log(`✅ Test points assigned: ${result.employeeName} (${points >= 0 ? '+' : ''}${points} points)`);
    return { success: true, points: points };
  } catch (error) {
    console.error('Error assigning test points:', error);
    return { success: false, error: error.message };
  }
}

// POST /api/test-results - сохранить результат теста
app.post('/api/test-results', async (req, res) => {
  try {
    console.log('POST /api/test-results', req.body);
    const result = {
      id: req.body.id || `test_result_${Date.now()}`,
      employeeName: req.body.employeeName,
      employeePhone: req.body.employeePhone,
      score: req.body.score,
      totalQuestions: req.body.totalQuestions,
      timeSpent: req.body.timeSpent,
      completedAt: req.body.completedAt || new Date().toISOString(),
      shopAddress: req.body.shopAddress,
    };

    const resultFile = path.join(TEST_RESULTS_DIR, `${result.id}.json`);
    await fsp.writeFile(resultFile, JSON.stringify(result, null, 2), 'utf8');

    console.log(`✅ Результат теста сохранен: ${result.employeeName} - ${result.score}/${result.totalQuestions}`);

    // Начисление баллов за тест
    const pointsResult = await assignTestPoints(result);

    res.json({
      success: true,
      result,
      pointsAssigned: pointsResult.success,
      points: pointsResult.points
    });
  } catch (error) {
    console.error('Ошибка сохранения результата теста:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ========== API для отзывов ==========
const REVIEWS_DIR = `${DATA_DIR}/reviews`;
(async () => {
  if (!await fileExists(REVIEWS_DIR)) {
    await fsp.mkdir(REVIEWS_DIR, { recursive: true });
  }
})();

app.get('/api/reviews', async (req, res) => {
  try {
    const { phone } = req.query;
    const reviews = [];
    if (await fileExists(REVIEWS_DIR)) {
      const files = (await fsp.readdir(REVIEWS_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const content = await fsp.readFile(path.join(REVIEWS_DIR, file), 'utf8');
          const review = JSON.parse(content);
          if (!phone || review.clientPhone === phone) {
            reviews.push(review);
          }
        } catch (e) {
          console.error(`Ошибка чтения ${file}:`, e);
        }
      }
    }
    res.json({ success: true, reviews });
  } catch (error) {
    console.error('Ошибка получения отзывов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/reviews', async (req, res) => {
  try {
    const review = {
      id: `review_${Date.now()}`,
      clientPhone: req.body.clientPhone,
      clientName: req.body.clientName,
      shopAddress: req.body.shopAddress,
      reviewType: req.body.reviewType,
      reviewText: req.body.reviewText,
      messages: [],
      createdAt: new Date().toISOString(),
      hasUnreadFromClient: true,  // Новый отзыв непрочитан для админа
      hasUnreadFromAdmin: false,
    };
    const reviewFile = path.join(REVIEWS_DIR, `${review.id}.json`);
    await fsp.writeFile(reviewFile, JSON.stringify(review, null, 2), 'utf8');

    // Отправить push-уведомление админам
    const reviewEmoji = review.reviewType === 'positive' ? '👍' : '👎';
    await sendPushNotification(
      `Новый ${reviewEmoji} отзыв`,
      `${review.clientName} - ${review.shopAddress}`,
      {
        type: 'review_created',
        reviewId: review.id,
        reviewType: review.reviewType,
        shopAddress: review.shopAddress,
      }
    );

    res.json({ success: true, review });
  } catch (error) {
    console.error('Ошибка создания отзыва:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/reviews/:id', async (req, res) => {
  try {
    const safeId = sanitizeId(req.params.id);
    const reviewFile = path.join(REVIEWS_DIR, `${safeId}.json`);
    if (!isPathSafe(REVIEWS_DIR, reviewFile)) {
      return res.status(400).json({ success: false, error: 'Invalid review ID' });
    }
    if (!await fileExists(reviewFile)) {
      return res.status(404).json({ success: false, error: 'Отзыв не найден' });
    }
    const review = JSON.parse(await fsp.readFile(reviewFile, 'utf8'));
    res.json({ success: true, review });
  } catch (error) {
    console.error('Ошибка получения отзыва:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/reviews/:id/messages', async (req, res) => {
  try {
    const safeId = sanitizeId(req.params.id);
    const reviewFile = path.join(REVIEWS_DIR, `${safeId}.json`);
    if (!isPathSafe(REVIEWS_DIR, reviewFile)) {
      return res.status(400).json({ success: false, error: 'Invalid review ID' });
    }
    if (!await fileExists(reviewFile)) {
      return res.status(404).json({ success: false, error: 'Отзыв не найден' });
    }
    const review = JSON.parse(await fsp.readFile(reviewFile, 'utf8'));
    const message = {
      id: `message_${Date.now()}`,
      sender: req.body.sender,
      senderName: req.body.senderName,
      text: req.body.text,
      timestamp: new Date().toISOString(),
      createdAt: new Date().toISOString(),
      isRead: false,
    };
    review.messages = review.messages || [];
    review.messages.push(message);

    // Установить флаги непрочитанности и отправить push в зависимости от отправителя
    if (message.sender === 'client') {
      // Сообщение от клиента - отправить push админам
      review.hasUnreadFromClient = true;

      await sendPushNotification(
        'Новое сообщение в отзыве',
        `${review.clientName}: ${message.text.substring(0, 50)}${message.text.length > 50 ? '...' : ''}`,
        {
          type: 'review_message',
          reviewId: review.id,
          shopAddress: review.shopAddress,
        }
      );
    } else if (message.sender === 'admin') {
      // Сообщение от админа - отправить push клиенту
      review.hasUnreadFromAdmin = true;

      await sendPushToPhone(
        review.clientPhone,
        'Ответ на ваш отзыв',
        message.text.substring(0, 50) + (message.text.length > 50 ? '...' : ''),
        {
          type: 'review_message',
          reviewId: review.id,
        }
      );
    }

    await fsp.writeFile(reviewFile, JSON.stringify(review, null, 2), 'utf8');
    res.json({ success: true, message });
  } catch (error) {
    console.error('Ошибка добавления сообщения:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/reviews/:id/mark-read - Отметить диалог как прочитанный
app.post('/api/reviews/:id/mark-read', async (req, res) => {
  try {
    const safeId = sanitizeId(req.params.id);
    const reviewFile = path.join(REVIEWS_DIR, `${safeId}.json`);
    if (!isPathSafe(REVIEWS_DIR, reviewFile)) {
      return res.status(400).json({ success: false, error: 'Invalid review ID' });
    }
    if (!await fileExists(reviewFile)) {
      return res.status(404).json({ success: false, error: 'Отзыв не найден' });
    }

    const review = JSON.parse(await fsp.readFile(reviewFile, 'utf8'));
    const { readerType } = req.body; // 'admin' или 'client'

    if (!readerType) {
      return res.status(400).json({ success: false, error: 'readerType обязателен' });
    }

    // Обновить флаги и отметить сообщения как прочитанные
    if (readerType === 'admin') {
      review.hasUnreadFromClient = false;
      // Отметить все сообщения от клиента как прочитанные
      if (review.messages) {
        review.messages.forEach(msg => {
          if (msg.sender === 'client') {
            msg.isRead = true;
          }
        });
      }
    } else if (readerType === 'client') {
      review.hasUnreadFromAdmin = false;
      // Отметить все сообщения от админа как прочитанные
      if (review.messages) {
        review.messages.forEach(msg => {
          if (msg.sender === 'admin') {
            msg.isRead = true;
          }
        });
      }
    }

    await fsp.writeFile(reviewFile, JSON.stringify(review, null, 2), 'utf8');
    res.json({ success: true });
  } catch (error) {
    console.error('Ошибка отметки диалога как прочитанного:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});


// ============================================
// Recipes API
// ============================================
const RECIPES_DIR = `${DATA_DIR}/recipes`;
const RECIPE_PHOTOS_DIR = `${DATA_DIR}/recipe-photos`;

(async () => {
  if (!await fileExists(RECIPES_DIR)) {
    await fsp.mkdir(RECIPES_DIR, { recursive: true });
  }
  if (!await fileExists(RECIPE_PHOTOS_DIR)) {
    await fsp.mkdir(RECIPE_PHOTOS_DIR, { recursive: true });
  }
})();

// GET /api/recipes - получить все рецепты
app.get('/api/recipes', async (req, res) => {
  try {
    console.log('GET /api/recipes');
    const recipes = [];
    
    if (await fileExists(RECIPES_DIR)) {
      const files = (await fsp.readdir(RECIPES_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const content = await fsp.readFile(path.join(RECIPES_DIR, file), 'utf8');
          const recipe = JSON.parse(content);
          recipes.push(recipe);
        } catch (e) {
          console.error(`Ошибка чтения ${file}:`, e);
        }
      }
    }
    
    console.log(`✅ Найдено рецептов: ${recipes.length}`);
    res.json({ success: true, recipes });
  } catch (error) {
    console.error('Ошибка получения рецептов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/recipes/:id - получить рецепт по ID
app.get('/api/recipes/:id', async (req, res) => {
  try {
    const safeId = sanitizeId(req.params.id);
    const recipeFile = path.join(RECIPES_DIR, `${safeId}.json`);
    if (!isPathSafe(RECIPES_DIR, recipeFile)) {
      return res.status(400).json({ success: false, error: 'Invalid recipe ID' });
    }
    if (!await fileExists(recipeFile)) {
      return res.status(404).json({ success: false, error: 'Рецепт не найден' });
    }
    
    const recipe = JSON.parse(await fsp.readFile(recipeFile, 'utf8'));
    res.json({ success: true, recipe });
  } catch (error) {
    console.error('Ошибка получения рецепта:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/recipes/photo/:recipeId - получить фото рецепта
app.get('/api/recipes/photo/:recipeId', async (req, res) => {
  try {
    const safeRecipeId = sanitizeId(req.params.recipeId);
    const photoPath = path.join(RECIPE_PHOTOS_DIR, `${safeRecipeId}.jpg`);
    if (!isPathSafe(RECIPE_PHOTOS_DIR, photoPath)) {
      return res.status(400).json({ success: false, error: 'Invalid recipe ID' });
    }
    if (await fileExists(photoPath)) {
      res.sendFile(photoPath);
    } else {
      res.status(404).json({ success: false, error: 'Фото не найдено' });
    }
  } catch (error) {
    console.error('Ошибка получения фото рецепта:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/recipes - создать новый рецепт
app.post('/api/recipes', async (req, res) => {
  try {
    const { name, category, price, ingredients, steps } = req.body;
    console.log('POST /api/recipes:', name);

    if (!name || !category) {
      return res.status(400).json({ success: false, error: 'Название и категория обязательны' });
    }

    const id = `recipe_${Date.now()}`;
    const recipe = {
      id,
      name,
      category,
      price: price || '',
      ingredients: ingredients || '',
      steps: steps || '',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    const recipeFile = path.join(RECIPES_DIR, `${id}.json`);
    await fsp.writeFile(recipeFile, JSON.stringify(recipe, null, 2), 'utf8');

    res.json({ success: true, recipe });
  } catch (error) {
    console.error('Ошибка создания рецепта:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/recipes/:id - обновить рецепт
app.put('/api/recipes/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const updates = req.body;
    console.log('PUT /api/recipes:', id);

    const recipeFile = path.join(RECIPES_DIR, `${id}.json`);

    if (!await fileExists(recipeFile)) {
      return res.status(404).json({ success: false, error: 'Рецепт не найден' });
    }

    const content = await fsp.readFile(recipeFile, 'utf8');
    const recipe = JSON.parse(content);

    // Обновляем поля
    if (updates.name) recipe.name = updates.name;
    if (updates.category) recipe.category = updates.category;
    if (updates.price !== undefined) recipe.price = updates.price;
    if (updates.ingredients !== undefined) recipe.ingredients = updates.ingredients;
    if (updates.steps !== undefined) recipe.steps = updates.steps;
    if (updates.photoUrl !== undefined) recipe.photoUrl = updates.photoUrl;
    recipe.updatedAt = new Date().toISOString();

    await fsp.writeFile(recipeFile, JSON.stringify(recipe, null, 2), 'utf8');

    res.json({ success: true, recipe });
  } catch (error) {
    console.error('Ошибка обновления рецепта:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/recipes/:id - удалить рецепт
app.delete('/api/recipes/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('DELETE /api/recipes:', id);

    const recipeFile = path.join(RECIPES_DIR, `${id}.json`);

    if (!await fileExists(recipeFile)) {
      return res.status(404).json({ success: false, error: 'Рецепт не найден' });
    }

    // Удаляем файл рецепта
    await fsp.unlink(recipeFile);

    // Удаляем фото рецепта, если есть
    const photoPath = path.join(RECIPE_PHOTOS_DIR, `${id}.jpg`);
    if (await fileExists(photoPath)) {
      await fsp.unlink(photoPath);
    }

    res.json({ success: true, message: 'Рецепт успешно удален' });
  } catch (error) {
    console.error('Ошибка удаления рецепта:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================
// Shift Handover Reports API
// ============================================
const SHIFT_HANDOVER_REPORTS_DIR = `${DATA_DIR}/shift-handover-reports`;

(async () => {
  if (!await fileExists(SHIFT_HANDOVER_REPORTS_DIR)) {
    await fsp.mkdir(SHIFT_HANDOVER_REPORTS_DIR, { recursive: true });
  }
})();

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
    const { id } = req.params;
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
    markShiftHandoverPendingCompleted(report.shopAddress, shiftType, report.employeeName);

    // Отправляем push-уведомление админу о новом отчёте
    sendShiftHandoverNewReportNotification(report);

    res.json({ success: true, message: 'Отчет сохранен' });
  } catch (error) {
    console.error('Ошибка сохранения отчета сдачи смены:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/shift-handover-reports/:id - обновить отчет (подтвердить/отклонить)
app.put('/api/shift-handover-reports/:id', async (req, res) => {
  try {
    const { id } = req.params;
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
    const { id } = req.params;
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
    const pending = getPendingShiftHandoverReports();
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
    const failed = getFailedShiftHandoverReports();
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

// ============================================
// Menu API
// ============================================
const MENU_DIR = `${DATA_DIR}/menu`;

(async () => {
  if (!await fileExists(MENU_DIR)) {
    await fsp.mkdir(MENU_DIR, { recursive: true });
  }
})();

// GET /api/menu - получить все позиции меню
app.get('/api/menu', async (req, res) => {
  try {
    console.log('GET /api/menu');

    const items = [];

    if (!await fileExists(MENU_DIR)) {
      return res.json({ success: true, items: [] });
    }

    const files = (await fsp.readdir(MENU_DIR)).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const filePath = path.join(MENU_DIR, file);
        const content = await fsp.readFile(filePath, 'utf8');
        const item = JSON.parse(content);
        items.push(item);
      } catch (e) {
        console.error(`Ошибка чтения файла ${file}:`, e);
      }
    }

    // Сортируем по категории и названию
    items.sort((a, b) => {
      const catCompare = (a.category || '').localeCompare(b.category || '');
      if (catCompare !== 0) return catCompare;
      return (a.name || '').localeCompare(b.name || '');
    });

    res.json({ success: true, items });
  } catch (error) {
    console.error('Ошибка получения меню:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/menu/:id - получить позицию меню по ID
app.get('/api/menu/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('GET /api/menu/:id', id);

    const itemFile = path.join(MENU_DIR, `${id}.json`);

    if (!await fileExists(itemFile)) {
      return res.status(404).json({
        success: false,
        error: 'Позиция меню не найдена'
      });
    }

    const content = await fsp.readFile(itemFile, 'utf8');
    const item = JSON.parse(content);

    res.json({ success: true, item });
  } catch (error) {
    console.error('Ошибка получения позиции меню:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/menu - создать позицию меню
app.post('/api/menu', async (req, res) => {
  try {
    const item = req.body;
    console.log('POST /api/menu:', item.name);

    // Генерируем ID если его нет
    if (!item.id) {
      item.id = `menu_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }

    const itemFile = path.join(MENU_DIR, `${item.id}.json`);
    await fsp.writeFile(itemFile, JSON.stringify(item, null, 2), 'utf8');

    res.json({ success: true, item });
  } catch (error) {
    console.error('Ошибка создания позиции меню:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/menu/:id - обновить позицию меню
app.put('/api/menu/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const updates = req.body;
    console.log('PUT /api/menu/:id', id);

    const itemFile = path.join(MENU_DIR, `${id}.json`);

    if (!await fileExists(itemFile)) {
      return res.status(404).json({
        success: false,
        error: 'Позиция меню не найдена'
      });
    }

    const content = await fsp.readFile(itemFile, 'utf8');
    const item = JSON.parse(content);

    // Обновляем поля
    Object.assign(item, updates);
    item.id = id; // Сохраняем оригинальный ID

    await fsp.writeFile(itemFile, JSON.stringify(item, null, 2), 'utf8');

    res.json({ success: true, item });
  } catch (error) {
    console.error('Ошибка обновления позиции меню:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/menu/:id - удалить позицию меню
app.delete('/api/menu/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('DELETE /api/menu/:id', id);

    const itemFile = path.join(MENU_DIR, `${id}.json`);

    if (!await fileExists(itemFile)) {
      return res.status(404).json({
        success: false,
        error: 'Позиция меню не найдена'
      });
    }

    await fsp.unlink(itemFile);

    res.json({ success: true, message: 'Позиция меню удалена' });
  } catch (error) {
    console.error('Ошибка удаления позиции меню:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================
// Orders API
// ============================================
const ORDERS_DIR = `${DATA_DIR}/orders`;

(async () => {
  if (!await fileExists(ORDERS_DIR)) {
    await fsp.mkdir(ORDERS_DIR, { recursive: true });
  }
})();

// POST /api/orders - создать заказ
app.post('/api/orders', async (req, res) => {
  try {
    console.log('POST /api/orders', req.body);
    const { clientPhone, clientName, shopAddress, items, totalPrice, comment } = req.body;
    const normalizedPhone = clientPhone.replace(/[\s+]/g, '');

    const order = await ordersModule.createOrder({
      clientPhone: normalizedPhone,
      clientName,
      shopAddress,
      items,
      totalPrice,
      comment
    });

    console.log(`✅ Создан заказ #${order.orderNumber} от ${clientName}`);
    res.json({ success: true, order });
  } catch (err) {
    console.error('❌ Ошибка создания заказа:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/orders - получить заказы (с фильтрацией по clientPhone)
app.get('/api/orders', async (req, res) => {
  try {
    console.log('GET /api/orders', req.query);
    const filters = {};
    if (req.query.clientPhone) {
      filters.clientPhone = req.query.clientPhone.replace(/[\s+]/g, '');
    }
    if (req.query.status) filters.status = req.query.status;
    if (req.query.shopAddress) filters.shopAddress = req.query.shopAddress;

    const orders = await ordersModule.getOrders(filters);
    res.json({ success: true, orders });
  } catch (err) {
    console.error('❌ Ошибка получения заказов:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/orders/unviewed-count - получить количество непросмотренных заказов
// ВАЖНО: этот route должен быть ПЕРЕД /api/orders/:id
app.get('/api/orders/unviewed-count', async (req, res) => {
  try {
    console.log('GET /api/orders/unviewed-count');
    const counts = await ordersModule.getUnviewedOrdersCounts();
    res.json({
      success: true,
      rejected: counts.rejected,
      unconfirmed: counts.unconfirmed,
      total: counts.total
    });
  } catch (error) {
    console.error('Ошибка получения непросмотренных заказов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/orders/mark-viewed/:type - отметить заказы как просмотренные
// ВАЖНО: этот route должен быть ПЕРЕД /api/orders/:id
app.post('/api/orders/mark-viewed/:type', async (req, res) => {
  try {
    const { type } = req.params;
    console.log('POST /api/orders/mark-viewed/' + type);

    if (type !== 'rejected' && type !== 'unconfirmed') {
      return res.status(400).json({
        success: false,
        error: 'Incorrect type: should be rejected or unconfirmed'
      });
    }

    const success = await ordersModule.saveLastViewedAt(type, new Date());
    res.json({ success });
  } catch (error) {
    console.error('Ошибка отметки заказов как просмотренных:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/orders/:id - получить заказ по ID
app.get('/api/orders/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('GET /api/orders/:id', id);

    const orderFile = path.join(ORDERS_DIR, `${id}.json`);

    if (!await fileExists(orderFile)) {
      return res.status(404).json({
        success: false,
        error: 'Заказ не найден'
      });
    }

    const content = await fsp.readFile(orderFile, 'utf8');
    const order = JSON.parse(content);

    res.json({ success: true, order });
  } catch (error) {
    console.error('Ошибка получения заказа:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PATCH /api/orders/:id - обновить статус заказа
app.patch('/api/orders/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const updates = {};
    
    if (req.body.status) updates.status = req.body.status;
    if (req.body.acceptedBy) updates.acceptedBy = req.body.acceptedBy;
    if (req.body.rejectedBy) updates.rejectedBy = req.body.rejectedBy;
    if (req.body.rejectionReason) updates.rejectionReason = req.body.rejectionReason;
    
    const order = await ordersModule.updateOrderStatus(id, updates);
    console.log(`✅ Заказ #${order.orderNumber} обновлен: ${updates.status}`);
    res.json({ success: true, order });
  } catch (err) {
    console.error('❌ Ошибка обновления заказа:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// DELETE /api/orders/:id - удалить заказ
app.delete('/api/orders/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('DELETE /api/orders/:id', id);

    const orderFile = path.join(ORDERS_DIR, `${id}.json`);

    if (!await fileExists(orderFile)) {
      return res.status(404).json({
        success: false,
        error: 'Заказ не найден'
      });
    }

    await fsp.unlink(orderFile);

    res.json({ success: true, message: 'Заказ удален' });
  } catch (error) {
    console.error('Ошибка удаления заказа:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/fcm-tokens - сохранение FCM токена
app.post('/api/fcm-tokens', async (req, res) => {
  try {
    console.log('POST /api/fcm-tokens', req.body);
    const { phone, token } = req.body;

    if (!phone || !token) {
      return res.status(400).json({ success: false, error: 'phone и token обязательны' });
    }

    const normalizedPhone = phone.replace(/[\s+]/g, '');

    const tokenDir = `${DATA_DIR}/fcm-tokens`;
    if (!await fileExists(tokenDir)) {
      await fsp.mkdir(tokenDir, { recursive: true });
    }

    const tokenFile = path.join(tokenDir, `${normalizedPhone}.json`);
    await fsp.writeFile(tokenFile, JSON.stringify({
      phone: normalizedPhone,
      token,
      updatedAt: new Date().toISOString()
    }, null, 2), 'utf8');

    console.log(`✅ FCM токен сохранен для ${normalizedPhone}`);
    res.json({ success: true });
  } catch (err) {
    console.error('❌ Ошибка сохранения FCM токена:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ==================== ПРЕМИИ И ШТРАФЫ ====================
const BONUS_PENALTIES_DIR = `${DATA_DIR}/bonus-penalties`;

// Вспомогательная функция для получения месяца в формате YYYY-MM
function getCurrentMonth() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

// Вспомогательная функция для получения прошлого месяца
function getPreviousMonth() {
  const now = new Date();
  now.setMonth(now.getMonth() - 1);
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

// GET /api/bonus-penalties - получить премии/штрафы за месяц
app.get('/api/bonus-penalties', async (req, res) => {
  try {
    const month = req.query.month || getCurrentMonth();
    const employeeId = req.query.employeeId;

    console.log(`📥 GET /api/bonus-penalties month=${month}, employeeId=${employeeId || 'all'}`);

    // Создаем директорию, если её нет
    if (!await fileExists(BONUS_PENALTIES_DIR)) {
      await fsp.mkdir(BONUS_PENALTIES_DIR, { recursive: true });
    }

    const filePath = path.join(BONUS_PENALTIES_DIR, `${month}.json`);

    if (!await fileExists(filePath)) {
      return res.json({ success: true, records: [], total: 0 });
    }

    const content = await fsp.readFile(filePath, 'utf8');
    const data = JSON.parse(content);
    let records = data.records || [];

    // Фильтрация по сотруднику, если указан
    if (employeeId) {
      records = records.filter(r => r.employeeId === employeeId);
    }

    // Подсчет общей суммы
    let total = 0;
    records.forEach(r => {
      if (r.type === 'bonus') {
        total += r.amount;
      } else {
        total -= r.amount;
      }
    });

    res.json({ success: true, records, total });
  } catch (error) {
    console.error('❌ Ошибка получения премий/штрафов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bonus-penalties - создать премию/штраф
app.post('/api/bonus-penalties', async (req, res) => {
  try {
    const { employeeId, employeeName, type, amount, comment, adminName } = req.body;

    console.log(`📤 POST /api/bonus-penalties: ${type} ${amount} для ${employeeName}`);

    // Валидация
    if (!employeeId || !employeeName || !type || !amount) {
      return res.status(400).json({
        success: false,
        error: 'Обязательные поля: employeeId, employeeName, type, amount'
      });
    }

    if (type !== 'bonus' && type !== 'penalty') {
      return res.status(400).json({
        success: false,
        error: 'type должен быть "bonus" или "penalty"'
      });
    }

    if (amount <= 0) {
      return res.status(400).json({
        success: false,
        error: 'amount должен быть положительным числом'
      });
    }

    // Создаем директорию, если её нет
    if (!await fileExists(BONUS_PENALTIES_DIR)) {
      await fsp.mkdir(BONUS_PENALTIES_DIR, { recursive: true });
    }

    const month = getCurrentMonth();
    const filePath = path.join(BONUS_PENALTIES_DIR, `${month}.json`);

    // Читаем существующие данные или создаем новый файл
    let data = { records: [] };
    if (await fileExists(filePath)) {
      const content = await fsp.readFile(filePath, 'utf8');
      data = JSON.parse(content);
    }

    // Создаем новую запись
    const newRecord = {
      id: `bp_${Date.now()}`,
      employeeId,
      employeeName,
      type,
      amount: parseFloat(amount),
      comment: comment || '',
      adminName: adminName || 'Администратор',
      createdAt: new Date().toISOString(),
      month
    };

    data.records.push(newRecord);

    // Сохраняем
    await fsp.writeFile(filePath, JSON.stringify(data, null, 2), 'utf8');

    console.log(`✅ Создана запись ${type}: ${amount} для ${employeeName}`);
    res.json({ success: true, record: newRecord });
  } catch (error) {
    console.error('❌ Ошибка создания премии/штрафа:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/bonus-penalties/:id - удалить премию/штраф
app.delete('/api/bonus-penalties/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const month = req.query.month || getCurrentMonth();

    console.log(`🗑️ DELETE /api/bonus-penalties/${id} month=${month}`);

    const filePath = path.join(BONUS_PENALTIES_DIR, `${month}.json`);

    if (!await fileExists(filePath)) {
      return res.status(404).json({ success: false, error: 'Записи не найдены' });
    }

    const content = await fsp.readFile(filePath, 'utf8');
    const data = JSON.parse(content);

    const index = data.records.findIndex(r => r.id === id);
    if (index === -1) {
      return res.status(404).json({ success: false, error: 'Запись не найдена' });
    }

    data.records.splice(index, 1);
    await fsp.writeFile(filePath, JSON.stringify(data, null, 2), 'utf8');

    console.log(`✅ Запись ${id} удалена`);
    res.json({ success: true });
  } catch (error) {
    console.error('❌ Ошибка удаления премии/штрафа:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/bonus-penalties/summary/:employeeId - получить сводку для сотрудника
app.get('/api/bonus-penalties/summary/:employeeId', async (req, res) => {
  try {
    const { employeeId } = req.params;

    console.log(`📊 GET /api/bonus-penalties/summary/${employeeId}`);

    if (!await fileExists(BONUS_PENALTIES_DIR)) {
      return res.json({
        success: true,
        currentMonth: { total: 0, records: [] },
        previousMonth: { total: 0, records: [] }
      });
    }

    const currentMonth = getCurrentMonth();
    const previousMonth = getPreviousMonth();

    // Функция для чтения и суммирования по месяцу
    const getMonthData = async (month) => {
      const filePath = path.join(BONUS_PENALTIES_DIR, `${month}.json`);
      if (!await fileExists(filePath)) {
        return { total: 0, records: [] };
      }

      const content = await fsp.readFile(filePath, 'utf8');
      const data = JSON.parse(content);
      const records = (data.records || []).filter(r => r.employeeId === employeeId);

      let total = 0;
      records.forEach(r => {
        if (r.type === 'bonus') {
          total += r.amount;
        } else {
          total -= r.amount;
        }
      });

      return { total, records };
    };

    res.json({
      success: true,
      currentMonth: await getMonthData(currentMonth),
      previousMonth: await getMonthData(previousMonth)
    });
  } catch (error) {
    console.error('❌ Ошибка получения сводки:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ========== BATCH API для данных эффективности ==========

/**
 * Helper функция для загрузки отчётов пересменки за период
 */
async function loadShiftReportsForPeriod(startDate, endDate) {
  const reports = [];

  if (!await fileExists(SHIFT_REPORTS_DIR)) {
    return reports;
  }

  const files = (await fsp.readdir(SHIFT_REPORTS_DIR)).filter(f => f.endsWith('.json'));

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(SHIFT_REPORTS_DIR, file), 'utf8');
      const report = JSON.parse(content);

      // Проверяем период
      const reportDate = new Date(report.createdAt || report.timestamp);
      if (reportDate >= startDate && reportDate <= endDate) {
        reports.push(report);
      }
    } catch (e) {
      console.error(`Ошибка чтения shift report ${file}:`, e.message);
    }
  }

  return reports;
}

/**
 * Helper функция для загрузки отчётов пересчёта за период
 */
async function loadRecountReportsForPeriod(startDate, endDate) {
  const reports = [];
  const reportsDir = `${DATA_DIR}/recount-reports`;

  if (!await fileExists(reportsDir)) {
    return reports;
  }

  const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(reportsDir, file), 'utf8');
      const report = JSON.parse(content);

      // Проверяем период
      const reportDate = new Date(report.completedAt || report.createdAt);
      if (reportDate >= startDate && reportDate <= endDate) {
        reports.push(report);
      }
    } catch (e) {
      console.error(`Ошибка чтения recount report ${file}:`, e.message);
    }
  }

  return reports;
}

/**
 * Helper функция для загрузки отчётов сдачи смены за период
 */
async function loadShiftHandoverReportsForPeriod(startDate, endDate) {
  const reports = [];

  if (!await fileExists(SHIFT_HANDOVER_REPORTS_DIR)) {
    return reports;
  }

  const files = (await fsp.readdir(SHIFT_HANDOVER_REPORTS_DIR)).filter(f => f.endsWith('.json'));

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(SHIFT_HANDOVER_REPORTS_DIR, file), 'utf8');
      const report = JSON.parse(content);

      // Проверяем период
      const reportDate = new Date(report.createdAt);
      if (reportDate >= startDate && reportDate <= endDate) {
        reports.push(report);
      }
    } catch (e) {
      console.error(`Ошибка чтения shift handover report ${file}:`, e.message);
    }
  }

  return reports;
}

/**
 * Helper функция для загрузки записей посещаемости за период
 */
async function loadAttendanceForPeriod(startDate, endDate) {
  const records = [];
  const attendanceDir = `${DATA_DIR}/attendance`;

  if (!await fileExists(attendanceDir)) {
    return records;
  }

  const files = (await fsp.readdir(attendanceDir)).filter(f => f.endsWith('.json'));

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(attendanceDir, file), 'utf8');
      const record = JSON.parse(content);

      // Проверяем период
      const recordDate = new Date(record.timestamp || record.createdAt);
      if (recordDate >= startDate && recordDate <= endDate) {
        records.push(record);
      }
    } catch (e) {
      console.error(`Ошибка чтения attendance record ${file}:`, e.message);
    }
  }

  return records;
}

/**
 * GET /api/efficiency/reports-batch
 * Batch endpoint для загрузки всех отчётов за месяц одним запросом
 *
 * Query параметры:
 * - month (обязательный): формат YYYY-MM (например 2025-01)
 *
 * Возвращает:
 * {
 *   success: true,
 *   month: "2025-01",
 *   shifts: [...],
 *   recounts: [...],
 *   handovers: [...],
 *   attendance: [...]
 * }
 */
app.get('/api/efficiency/reports-batch', async (req, res) => {
  try {
    const { month } = req.query;

    // Валидация формата месяца
    if (!month || !month.match(/^\d{4}-\d{2}$/)) {
      return res.status(400).json({
        success: false,
        error: 'Неверный формат месяца. Используйте YYYY-MM (например 2025-01)'
      });
    }

    console.log(`📊 GET /api/efficiency/reports-batch?month=${month}`);

    // Парсим год и месяц
    const [year, monthNum] = month.split('-').map(Number);

    // Дополнительная валидация месяца
    if (monthNum < 1 || monthNum > 12) {
      return res.status(400).json({
        success: false,
        error: 'Неверный номер месяца. Используйте месяц от 01 до 12'
      });
    }

    // Создаём границы периода
    const startDate = new Date(year, monthNum - 1, 1, 0, 0, 0);
    const endDate = new Date(year, monthNum, 0, 23, 59, 59);

    console.log(`  📅 Период: ${startDate.toISOString()} - ${endDate.toISOString()}`);

    // Загружаем все типы отчётов параллельно
    const startTime = Date.now();

    const shifts = loadShiftReportsForPeriod(startDate, endDate);
    const recounts = loadRecountReportsForPeriod(startDate, endDate);
    const handovers = loadShiftHandoverReportsForPeriod(startDate, endDate);
    const attendance = loadAttendanceForPeriod(startDate, endDate);

    const loadTime = Date.now() - startTime;

    console.log(`  ✅ Загружено за ${loadTime}ms:`);
    console.log(`     - shifts: ${shifts.length}`);
    console.log(`     - recounts: ${recounts.length}`);
    console.log(`     - handovers: ${handovers.length}`);
    console.log(`     - attendance: ${attendance.length}`);
    console.log(`     - ИТОГО: ${shifts.length + recounts.length + handovers.length + attendance.length} записей`);

    res.json({
      success: true,
      month,
      shifts,
      recounts,
      handovers,
      attendance
    });
  } catch (error) {
    console.error('❌ Ошибка загрузки batch отчётов:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * GET /api/efficiency-penalties
 * Получить штрафы эффективности за месяц
 * Query params: month (YYYY-MM)
 */
app.get('/api/efficiency-penalties', async (req, res) => {
  try {
    const { month } = req.query;

    // Валидация формата месяца
    if (!month || !month.match(/^\d{4}-\d{2}$/)) {
      return res.status(400).json({
        success: false,
        error: 'Неверный формат месяца. Используйте YYYY-MM (например 2026-02)'
      });
    }

    console.log(`📊 GET /api/efficiency-penalties?month=${month}`);

    const penaltiesDir = `${DATA_DIR}/efficiency-penalties`;
    const penaltiesFile = path.join(penaltiesDir, `${month}.json`);

    let penalties = [];
    if (await fileExists(penaltiesFile)) {
      const content = await fsp.readFile(penaltiesFile, 'utf8');
      penalties = JSON.parse(content);
    }

    console.log(`  ✅ Загружено ${penalties.length} штрафов за ${month}`);

    res.json({
      success: true,
      month,
      penalties
    });
  } catch (error) {
    console.error('❌ Ошибка загрузки штрафов:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Initialize Job Applications API
setupJobApplicationsAPI(app);

// Создаём HTTP сервер для поддержки WebSocket
const server = http.createServer(app);

// Инициализируем WebSocket для чата
setupChatWebSocket(server);

// SCALABILITY: Предзагрузка кэша админов при старте сервера
// Это предотвращает сканирование всех файлов сотрудников при каждом запросе
preloadAdminCache();

server.listen(3000, () => console.log("Proxy listening on port 3000 (HTTP + WebSocket)"));
setupRecountPointsAPI(app);
setupReferralsAPI(app);
setupRatingWheelAPI(app);
setupTasksAPI(app);
setupRecurringTasksAPI(app);
setupReportNotificationsAPI(app);
setupClientsAPI(app);
setupShiftTransfersAPI(app);
setupTaskPointsSettingsAPI(app);
setupPointsSettingsAPI(app);
setupManagerEfficiencyAPI(app);
setupProductQuestionsAPI(app, uploadProductQuestionPhoto);
setupZReportAPI(app);
setupCigaretteVisionAPI(app);
setupShiftAiVerificationAPI(app);
setupDataCleanupAPI(app);
setupShopProductsAPI(app);
setupMasterCatalogAPI(app);
setupGeofenceAPI(app, sendPushToPhone);
setupEmployeeChatAPI(app);
setupMediaAPI(app, uploadChatMedia);
setupShopManagersAPI(app);
setupLoyaltyGamificationAPI(app);

// Auth API (регистрация, вход, сброс PIN)
app.use('/api/auth', authApiRouter);

// Initialize Telegram Bot for OTP
telegramBotService.initBot().catch(err => {
  console.error('❌ Failed to initialize Telegram bot:', err.message);
});

// Start product questions penalty scheduler
setupProductQuestionsPenaltyScheduler();

// Start shift automation scheduler (auto-create reports, check deadlines, penalties)
startShiftAutomationScheduler();

// Start recount automation scheduler (auto-create reports, check deadlines, penalties)
startRecountAutomationScheduler();

// Start RKO automation scheduler (auto-create reports, check deadlines, penalties)
startRkoAutomationScheduler();

// Start Shift Handover automation scheduler (auto-create reports, check deadlines, admin timeout)
startShiftHandoverAutomationScheduler();

// Start Attendance automation scheduler (auto-create reports, check deadlines, penalties)
startAttendanceAutomationScheduler();

// Start Envelope automation scheduler (auto-create reports, check deadlines, penalties)
startEnvelopeAutomationScheduler();

// Start order timeout scheduler (auto-expire orders and create penalties)
setupOrderTimeoutAPI(app);

// ============================================
// HEALTH CHECK ENDPOINT
// ============================================
app.get('/health', async (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    version: '2.0.0'
  });
});

// ============================================
// GRACEFUL SHUTDOWN
// ============================================
const gracefulShutdown = (signal) => {
  console.log(`\n🛑 Received ${signal}. Starting graceful shutdown...`);

  // Остановить приём новых соединений
  server.close((err) => {
    if (err) {
      console.error('❌ Error during server close:', err);
      process.exit(1);
    }

    console.log('✅ HTTP server closed');
    console.log('✅ All connections terminated');
    console.log('👋 Graceful shutdown complete');
    process.exit(0);
  });

  // Принудительное завершение через 10 секунд если не успели
  setTimeout(() => {
    console.error('⚠️ Forced shutdown after 10s timeout');
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// ═══════════════════════════════════════════════════════════════════
// LOYALTY PROMO API
// ═══════════════════════════════════════════════════════════════════
const LOYALTY_PROMO_FILE = `${DATA_DIR}/loyalty-promo.json`;

// GET /api/loyalty-promo - получить настройки акции
app.get('/api/loyalty-promo', async (req, res) => {
  try {
    let settings = {
      promoText: 'При покупке 9 напитков 10-й бесплатно',
      pointsRequired: 9,
      drinksToGive: 1,
      success: true
    };

    if (await fileExists(LOYALTY_PROMO_FILE)) {
      const data = JSON.parse(await fsp.readFile(LOYALTY_PROMO_FILE, 'utf8'));
      settings = { ...settings, ...data, success: true };
    }

    console.log('GET /api/loyalty-promo:', settings.pointsRequired + '+' + settings.drinksToGive);
    res.json(settings);
  } catch (e) {
    console.error('Error getting loyalty-promo:', e);
    res.status(500).json({ success: false, error: e.message });
  }
});

// POST /api/loyalty-promo - сохранить настройки акции (только админ)
app.post('/api/loyalty-promo', async (req, res) => {
  try {
    const { promoText, pointsRequired, drinksToGive, employeePhone } = req.body;

    // Проверка на админа или разработчика
    const normalizedPhone = (employeePhone || '').replace(/[\s\+]/g, '');
    const employees = await loadAllEmployeesForWithdrawals();
    const employee = employees.find(e => e.phone && e.phone.replace(/[\s\+]/g, '') === normalizedPhone);
    const isAdminOrDev = employee && (employee.isAdmin === true || employee.role === 'developer');
    if (!isAdminOrDev) {
      console.log('POST /api/loyalty-promo: denied for non-admin', normalizedPhone);
      return res.status(403).json({ success: false, error: 'Доступ запрещён' });
    }

    const settings = {
      promoText: promoText || '',
      pointsRequired: parseInt(pointsRequired) || 9,
      drinksToGive: parseInt(drinksToGive) || 1,
      updatedAt: new Date().toISOString(),
      updatedBy: normalizedPhone
    };

    await fsp.writeFile(LOYALTY_PROMO_FILE, JSON.stringify(settings, null, 2), 'utf8');
    console.log('POST /api/loyalty-promo:', settings.pointsRequired + '+' + settings.drinksToGive, 'by', normalizedPhone);
    res.json({ success: true, ...settings });
  } catch (e) {
    console.error('Error saving loyalty-promo:', e);
    res.status(500).json({ success: false, error: e.message });
  }
});

// ==================== APP VERSION ====================
const APP_VERSION_FILE = `${DATA_DIR}/app-version.json`;

// GET /api/app-version - получить информацию о версии приложения
app.get("/api/app-version", async (req, res) => {
  try {
    if (await fileExists(APP_VERSION_FILE)) {
      const data = JSON.parse(await fsp.readFile(APP_VERSION_FILE, "utf8"));
      return res.json(data);
    }
    
    // Дефолтные значения
    return res.json({
      latestVersion: "1.0.0",
      latestVersionCode: 1,
      minVersion: "1.0.0",
      minVersionCode: 1,
      forceUpdate: false,
      updateMessage: "Доступна новая версия приложения",
      playStoreUrl: "https://play.google.com/store/apps/details?id=com.arabica.app"
    });
  } catch (e) {
    console.error("Ошибка чтения версии:", e);
    return res.status(500).json({ error: "Ошибка получения версии" });
  }
});

// POST /api/app-version - обновить информацию о версии (только админ)
app.post("/api/app-version", async (req, res) => {
  try {
    const { employeePhone, ...versionData } = req.body;
    
    // Проверка админа
    if (!employeePhone) {
      return res.status(403).json({ error: "Требуется авторизация" });
    }
    
    const normalizedPhone = employeePhone.replace(/[\s\+]/g, "");
    let isAdminOrDev = false;

    const employeeFiles = (await fsp.readdir(EMPLOYEES_DIR)).filter(f => f.endsWith(".json"));
    for (const file of employeeFiles) {
      try {
        const emp = JSON.parse(await fsp.readFile(path.join(EMPLOYEES_DIR, file), "utf8"));
        if (emp.phone && emp.phone.replace(/[\s\+]/g, "") === normalizedPhone && (emp.isAdmin || emp.role === 'developer')) {
          isAdminOrDev = true;
          break;
        }
      } catch (e) {}
    }

    if (!isAdminOrDev) {
      return res.status(403).json({ error: "Доступ только для администраторов" });
    }
    
    // Сохраняем версию
    await fsp.writeFile(APP_VERSION_FILE, JSON.stringify(versionData, null, 2));
    return res.json({ success: true });
  } catch (e) {
    console.error("Ошибка сохранения версии:", e);
    return res.status(500).json({ error: "Ошибка сохранения версии" });
  }
});

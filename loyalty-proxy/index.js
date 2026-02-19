const express = require('express');
const http = require('http');
const fetch = require('node-fetch');
const bodyParser = require('body-parser');
const cors = require('cors');
const multer = require('multer');
const fsp = require('fs').promises;
const path = require('path');

const { spawn } = require('child_process');
const { preloadAdminCache, startPeriodicRebuild, invalidateCache } = require('./utils/admin_cache');
const { createPaginatedResponse, isPaginationRequested } = require('./utils/pagination');
const { writeJsonFile } = require('./utils/async_fs');
const dataCache = require('./utils/data_cache');
const { maskPhone, fileExists } = require('./utils/file_helpers');
const { compressUpload } = require('./utils/image_compress');
const db = require('./utils/db');
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
  // Критическая ошибка — PM2 автоматически перезапустит процесс
  process.exit(1);
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
const setupJobApplicationsAPI = require('./api/job_applications_api');

const setupRecountPointsAPI = require("./api/recount_points_api");
const app = express();
const setupRatingWheelAPI = require("./api/rating_wheel_api");
const setupReferralsAPI = require("./api/referrals_api");
const { setupTasksAPI } = require("./api/tasks_api");
const { setupRecurringTasksAPI } = require("./api/recurring_tasks_api");
const { setupReportNotificationsAPI, sendPushNotification, sendPushToPhone } = require("./api/report_notifications_api");
const { setupClientsAPI } = require("./api/clients_api");
const { setupShiftTransfersAPI } = require("./api/shift_transfers_api");
const { setupTaskPointsSettingsAPI } = require("./api/task_points_settings_api");
const { setupPointsSettingsAPI, calculateRecountPoints, calculateShiftPoints } = require("./api/points_settings_api");
const { setupManagerEfficiencyAPI } = require("./api/manager_efficiency_api");
const { setupProductQuestionsAPI } = require("./api/product_questions_api");
const { setupProductQuestionsPenaltyScheduler } = require("./api/product_questions_penalty_scheduler");
const { setupOrderTimeoutAPI } = require("./api/order_timeout_api");
const { startShiftAutomationScheduler } = require("./api/shift_automation_scheduler");
const { startRecountAutomationScheduler } = require("./api/recount_automation_scheduler");
const { startRkoAutomationScheduler, getPendingReports: getPendingRkoReports, getFailedReports: getFailedRkoReports } = require("./api/rko_automation_scheduler");
const { startShiftHandoverAutomationScheduler, getPendingReports: getPendingShiftHandoverReports, getFailedReports: getFailedShiftHandoverReports, markPendingAsCompleted: markShiftHandoverPendingCompleted, sendAdminNewReportNotification: sendShiftHandoverNewReportNotification } = require("./api/shift_handover_automation_scheduler");
const { startAttendanceAutomationScheduler, getPendingReports: getPendingAttendanceReports, getFailedReports: getFailedAttendanceReports, canMarkAttendance, markPendingAsCompleted: markAttendancePendingCompleted } = require("./api/attendance_automation_scheduler");
const { startScheduler: startEnvelopeAutomationScheduler } = require("./api/envelope_automation_scheduler");
const { setupZReportAPI } = require("./api/z_report_api");
const { setupCigaretteVisionAPI } = require("./api/cigarette_vision_api");
const { setupShiftAiVerificationAPI } = require("./api/shift_ai_verification_api");
const { setupDataCleanupAPI, startAutoCleanupScheduler } = require("./api/data_cleanup_api");
const { setupShopProductsAPI } = require("./api/shop_products_api");
const { setupMasterCatalogAPI } = require("./api/master_catalog_api");
const { setupGeofenceAPI } = require("./api/geofence_api");
const { setupEmployeeChatAPI } = require("./api/employee_chat_api");
const { setupChatWebSocket } = require("./api/employee_chat_websocket");
const { setupMediaAPI } = require("./api/media_api");
const { setupShopManagersAPI } = require("./api/shop_managers_api");
const { setupLoyaltyGamificationAPI } = require("./api/loyalty_gamification_api");
const { setupCoffeeMachineAPI } = require("./api/coffee_machine_api");
const { startCoffeeMachineAutomation } = require("./api/coffee_machine_automation_scheduler");
const { setupExecutionChainAPI } = require("./api/execution_chain_api");
const { setupShopsAPI } = require('./api/shops_api');
const { setupMenuAPI } = require('./api/menu_api');
const { setupLoyaltyPromoAPI } = require('./api/loyalty_promo_api');
const { setupShopSettingsAPI } = require('./api/shop_settings_api');
const { setupEfficiencyPenaltiesAPI } = require('./api/efficiency_penalties_api');
const { setupDashboardBatchAPI } = require('./api/dashboard_batch_api');
const { setupWorkScheduleAPI } = require('./api/work_schedule_api');
const { setupWithdrawalsAPI, loadAllEmployeesForWithdrawals } = require('./api/withdrawals_api');
const { setupShiftsAPI } = require('./api/shifts_api');
const { setupEmployeesAPI } = require('./api/employees_api');
const { setupRecountAPI } = require('./api/recount_api');
const { setupAttendanceAPI } = require('./api/attendance_api');
const { setupPendingAPI } = require('./api/pending_api');
const { setupShopCoordinatesAPI } = require('./api/shop_coordinates_api');
const { setupSuppliersAPI } = require('./api/suppliers_api');
const { setupTrainingAPI } = require('./api/training_api');
const { setupTestsAPI } = require('./api/tests_api');
const { setupReviewsAPI } = require('./api/reviews_api');
const { setupRecipesAPI } = require('./api/recipes_api');
const { setupRkoAPI } = require('./api/rko_api');
const { setupEnvelopeAPI } = require('./api/envelope_api');
const { setupOrdersAPI } = require('./api/orders_api');
const { setupRecountQuestionsAPI } = require('./api/recount_questions_api');
const { setupShiftQuestionsAPI } = require('./api/shift_questions_api');
const { setupShiftHandoverQuestionsAPI } = require('./api/shift_handover_questions_api');
const { setupBonusPenaltiesAPI } = require('./api/bonus_penalties_api');
const { setupEmployeeRegistrationAPI } = require('./api/employee_registration_api');
const { getNextReferralCode } = require('./api/employees_api');
const authApiRouter = require("./api/auth_api");
const telegramBotService = require("./services/telegram_bot_service");
const { sessionMiddleware, initSessionMiddleware } = require("./utils/session_middleware");

// ============================================
// SECURITY: API Key Authentication
// ============================================
// Генерация ключа: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
const API_KEY = process.env.API_KEY || null;
const API_KEY_ENABLED = process.env.API_KEY_ENABLED !== 'false';

// Публичные endpoints которые не требуют аутентификации
const PUBLIC_ENDPOINTS = [
  '/health',
  '/',           // Proxy для Google Apps Script (регистрация, лояльность)
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

app.use(bodyParser.json({ limit: "10mb" }));

// Применяем Security Headers если helmet установлен
if (helmet) {
  app.use(helmet({
    contentSecurityPolicy: false, // Отключаем CSP для API (нет HTML)
    crossOriginEmbedderPolicy: false, // Для совместимости с мобильными приложениями
    crossOriginResourcePolicy: { policy: "cross-origin" }, // Разрешаем загрузку ресурсов
    hsts: { maxAge: 31536000, includeSubDomains: true }, // HSTS — принудительный HTTPS на 1 год
  }));
  console.log('✅ Security Headers (helmet) активированы');
}

// CORS - ограничиваем разрешённые источники
const corsOptions = {
  origin: function (origin, callback) {
    // Разрешаем запросы без origin (мобильные приложения, curl, Postman)
    if (!origin) return callback(null, true);

    // Разрешённые домены (только HTTPS в продакшн, HTTP только для localhost)
    const allowedOrigins = [
      'https://arabica26.ru',
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

// Применяем Session middleware (неблокирующий - только заполняет req.user)
app.use(sessionMiddleware);

// ============================================
// SECURITY: Require auth for write operations
// ============================================
// Все POST/PUT/DELETE/PATCH требуют авторизованную сессию
// (кроме public endpoints: auth, shop-products sync)
const PUBLIC_WRITE_PATHS = [
  '/',                   // Loyalty API proxy (регистрация клиентов, баллы — вызывается до авторизации)
  '/api/auth',           // Регистрация, вход, сброс PIN
  '/api/shop-products',  // Синхронизация товаров (своя авторизация по x-sync-key)
  '/api/fcm-tokens',     // Регистрация FCM push-токенов (вызывается до/после логина)
  '/api/geofence',           // Проверка геозоны клиента (вызывается без admin-сессии)
  '/api/geofence-settings',  // Настройки геозоны (сохранение из админки)
  '/api/shops',          // CRUD магазинов (управление из приложения)
  '/api/shop-settings',  // Настройки магазинов (управление из приложения)
  '/api/recipes',        // CRUD рецептов + загрузка фото
  '/api/employee-registration', // Регистрация сотрудников + верификация
  '/upload-employee-photo',     // Загрузка фото документов сотрудников
  '/api/shift-questions',       // CRUD + reorder вопросов пересменки
  '/api/test-questions',        // CRUD вопросов тестирования
  '/api/test-settings',         // Настройки тестирования (длительность)
  '/api/clients',               // Сообщения клиентам + рассылка
  '/api/client-dialogs',        // Диалоги с руководством + сетевые сообщения
  '/api/shift-handover-reports', // Отчёты пересменки (отправка сотрудниками)
  '/api/shift-reports',          // Отчёты смен (отправка сотрудниками)
  '/api/recount-reports',        // Отчёты пересчёта (отправка сотрудниками)
  '/api/envelope-reports',       // Отчёты конвертов (отправка сотрудниками)
  '/api/test-results',           // Результаты тестирования (отправка сотрудниками)
  '/api/report-notifications',   // Уведомления об отчётах
  '/upload-photo',               // Загрузка фото отчётов
  '/api/attendance',             // Отметки посещаемости
  '/api/rko',                    // РКО отчёты
  '/api/shift-handover-questions', // CRUD вопросов сдачи смены
  '/api/recount-questions',      // CRUD вопросов пересчёта
  '/api/envelope-questions',     // CRUD вопросов конвертов
];

app.use((req, res, next) => {
  // Только write-операции
  if (!['POST', 'PUT', 'DELETE', 'PATCH'].includes(req.method)) {
    return next();
  }

  // Пропускаем публичные write paths
  if (PUBLIC_WRITE_PATHS.some(p => req.path === p || req.path.startsWith(p + '/') || req.path.startsWith(p + '?'))) {
    return next();
  }

  // Требуем авторизацию
  if (!req.user) {
    const authHeader = req.headers['authorization'];
    console.warn(`⚠️ Unauthenticated write blocked: ${req.method} ${req.path} | Auth header: ${authHeader ? authHeader.substring(0, 20) + '...' : 'MISSING'}`);
    return res.status(401).json({
      success: false,
      error: 'Требуется авторизация. Войдите в приложение.'
    });
  }

  next();
});

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
    keyGenerator: (req) => req.user?.phone || req.ip, // Per-user rate limiting
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

  // Строгий лимит для auth endpoints: 10 запросов в минуту (защита от brute-force)
  const authLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 10,
    message: { success: false, error: 'Слишком много попыток авторизации. Подождите минуту.' },
    standardHeaders: true,
    legacyHeaders: false,
    validate: { xForwardedForHeader: false },
  });

  // Применяем общий лимит ко всем /api/* маршрутам
  app.use('/api/', generalLimiter);

  // Строгий лимит для auth операций
  app.use('/api/auth', authLimiter);

  // Умеренный лимит для финансовых операций
  app.use('/api/withdrawals', financialLimiter);
  app.use('/api/bonus-penalties', financialLimiter);
  app.use('/api/rko', financialLimiter);

  console.log('✅ Rate Limiting активирован: 500 req/min (общий), 10 req/min (auth), 50 req/min (финансовые)');
}

// Статические файлы для редактора координат
app.use('/static', express.static(`${DATA_DIR}/html`));

// ============================================
// SECURITY: File Type Validation для всех uploads
// ============================================
// SECURITY: Убран application/octet-stream — проверяем расширение файла вместо слепого доверия MIME
const allowedImageTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
const allowedMediaTypes = [...allowedImageTypes, 'video/mp4', 'video/quicktime'];
const allowedImageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
const allowedMediaExtensions = [...allowedImageExtensions, '.mp4', '.mov'];

const imageFileFilter = (req, file, cb) => {
  const ext = path.extname(file.originalname || '').toLowerCase();
  // Проверяем MIME type ИЛИ расширение (Flutter камера иногда шлёт octet-stream)
  if (allowedImageTypes.includes(file.mimetype) || allowedImageExtensions.includes(ext)) {
    cb(null, true);
  } else {
    cb(new Error(`Invalid file type: ${file.mimetype}. Only JPEG, PNG, GIF, WebP allowed.`), false);
  }
};

const mediaFileFilter = (req, file, cb) => {
  const ext = path.extname(file.originalname || '').toLowerCase();
  if (allowedMediaTypes.includes(file.mimetype) || allowedMediaExtensions.includes(ext)) {
    cb(null, true);
  } else {
    cb(new Error(`Invalid file type: ${file.mimetype}. Only images and videos allowed.`), false);
  }
};

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

// Настройка multer для загрузки документов (РКО)
const allowedDocTypes = ['application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/msword', 'application/pdf', 'application/octet-stream'];
const docFileFilter = (req, file, cb) => {
  if (allowedDocTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error(`Invalid file type: ${file.mimetype}. Only DOCX, DOC, PDF allowed.`), false);
  }
};

const rkoStorage = multer.diskStorage({
  destination: async function (req, file, cb) {
    const uploadDir = `${DATA_DIR}/rko-uploads-temp`;
    if (!await fileExists(uploadDir)) {
      await fsp.mkdir(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    const timestamp = Date.now();
    const originalName = path.basename(file.originalname).replace(/[^a-zA-Z0-9_\-\.а-яА-ЯёЁ]/g, '_');
    cb(null, `rko_${timestamp}_${originalName}`);
  }
});

const uploadRKO = multer({
  storage: rkoStorage,
  limits: { fileSize: 15 * 1024 * 1024 }, // 15MB для документов
  fileFilter: docFileFilter
});

// URL Google Apps Script для регистрации, лояльности и ролей
const SCRIPT_URL = process.env.SCRIPT_URL;
if (!SCRIPT_URL) {
  console.error('WARNING: SCRIPT_URL env variable is not set! Google Apps Script integration will not work.');
}

app.post('/', async (req, res) => {
  try {
    console.log("POST request to script");
    console.log("Request action:", req.body?.action || 'unknown');
    
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
app.post('/upload-photo', upload.single('file'), compressUpload, (req, res) => {
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
// Статическая раздача фото
app.use('/shift-photos', express.static(`${DATA_DIR}/shift-photos`));
app.use('/product-question-photos', express.static(`${DATA_DIR}/product-question-photos`));
app.use('/coffee-machine-photos', express.static(`${DATA_DIR}/coffee-machine-photos`));

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
app.post('/upload-employee-photo', uploadEmployeePhoto.single('file'), compressUpload, (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'Файл не загружен' });
    }

    // C-06 fix: проверка владельца — авторизованный не-админ может загружать только свои фото
    const requestPhone = (req.body.phone || '').replace(/[^\d]/g, '');
    if (req.user && !req.user.isAdmin) {
      const userPhone = (req.user.phone || '').replace(/[^\d]/g, '');
      if (userPhone && requestPhone && userPhone !== requestPhone) {
        console.warn(`⚠️ Попытка загрузки фото для чужого номера: ${requestPhone} (сессия: ${userPhone})`);
        return res.status(403).json({ success: false, error: 'Можно загружать фото только для своего номера' });
      }
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

const EMPLOYEES_DIR = `${DATA_DIR}/employees`;

// POST /api/fcm-tokens - сохранение FCM токена
app.post('/api/fcm-tokens', async (req, res) => {
  try {
    console.log('POST /api/fcm-tokens phone:', maskPhone(req.body?.phone));
    const { phone, token } = req.body;

    if (!phone || !token) {
      return res.status(400).json({ success: false, error: 'phone и token обязательны' });
    }

    const normalizedPhone = phone.replace(/[^\d]/g, '');

    const tokenDir = `${DATA_DIR}/fcm-tokens`;
    if (!await fileExists(tokenDir)) {
      await fsp.mkdir(tokenDir, { recursive: true });
    }

    const tokenFile = path.join(tokenDir, `${normalizedPhone}.json`);
    await writeJsonFile(tokenFile, {
      phone: normalizedPhone,
      token,
      updatedAt: new Date().toISOString()
    });

    console.log(`✅ FCM токен сохранен для ${normalizedPhone}`);
    res.json({ success: true });
  } catch (err) {
    console.error('❌ Ошибка сохранения FCM токена:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Initialize Job Applications API
setupJobApplicationsAPI(app);

// Создаём HTTP сервер для поддержки WebSocket
const server = http.createServer(app);

// Инициализируем WebSocket для чата
const wss = setupChatWebSocket(server);

// SCALABILITY: Async предзагрузка кэша админов + периодическое обновление
preloadAdminCache().catch(e => console.error('AdminCache preload error:', e.message));
startPeriodicRebuild();

// SCALABILITY: Кэш employees/shops данных (Fix #17)
dataCache.preload().catch(e => console.error('DataCache preload error:', e.message));
dataCache.startPeriodicRebuild();

// Инициализация session middleware (индекс token -> session)
initSessionMiddleware().catch(e => {
  console.error('Session middleware init error:', e.message);
});

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
setupCoffeeMachineAPI(app);
setupExecutionChainAPI(app);

// Migrated modules (inline routes removed from index.js)
setupShopsAPI(app);
setupMenuAPI(app);
setupLoyaltyPromoAPI(app, { loadAllEmployeesForWithdrawals });
setupShopSettingsAPI(app);
setupEfficiencyPenaltiesAPI(app);
setupDashboardBatchAPI(app);
setupWorkScheduleAPI(app, { sendPushToPhone });
setupWithdrawalsAPI(app);
setupShiftsAPI(app, { sendPushToPhone, markShiftHandoverPendingCompleted, sendShiftHandoverNewReportNotification, getPendingShiftHandoverReports, getFailedShiftHandoverReports, calculateShiftPoints });
setupEmployeesAPI(app, { isPaginationRequested, createPaginatedResponse, invalidateCache });
setupRecountAPI(app, { sendPushToPhone, calculateRecountPoints });
setupAttendanceAPI(app, { canMarkAttendance, markAttendancePendingCompleted, getPendingAttendanceReports, getFailedAttendanceReports, sendPushToPhone });
setupPendingAPI(app);
setupShopCoordinatesAPI(app);
setupSuppliersAPI(app, { getNextReferralCode });
setupTrainingAPI(app);
setupTestsAPI(app);
setupReviewsAPI(app, { sendPushNotification, sendPushToPhone });
setupRecipesAPI(app);
setupRkoAPI(app, { uploadRKO, spawnPython, getPendingRkoReports, getFailedRkoReports });
setupEnvelopeAPI(app);
setupOrdersAPI(app);
setupRecountQuestionsAPI(app, { upload });
setupShiftQuestionsAPI(app, { upload });
setupShiftHandoverQuestionsAPI(app, { uploadShiftHandoverPhoto });
setupBonusPenaltiesAPI(app);
setupEmployeeRegistrationAPI(app, { sendPushToPhone });

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
setTimeout(() => startEnvelopeAutomationScheduler(), 10000);

// Start Coffee Machine automation scheduler (auto-create reports, check deadlines, penalties)
setTimeout(() => startCoffeeMachineAutomation(), 12000);

// Start order timeout scheduler (auto-expire orders and create penalties)
setupOrderTimeoutAPI(app);

// Start auto-cleanup scheduler (daily at 3:00 AM — expired sessions, old logs, old data)
startAutoCleanupScheduler();

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

  // Закрываем WebSocket сервер
  if (wss) {
    wss.close(() => {
      console.log('✅ WebSocket server closed');
    });
  }

  // Закрываем пул PostgreSQL
  db.close().catch(err => {
    console.error('❌ Error closing DB pool:', err.message);
  });

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
    // B-10: isAdmin from req.user.isAdmin, not from body
    if (!req.user) {
      return res.status(401).json({ error: "Требуется авторизация" });
    }
    if (!req.user.isAdmin) {
      return res.status(403).json({ error: "Доступ только для администраторов" });
    }

    const versionData = req.body;

    // B-01: writeJsonFile with file locking
    await writeJsonFile(APP_VERSION_FILE, versionData);
    return res.json({ success: true });
  } catch (e) {
    console.error("Ошибка сохранения версии:", e);
    return res.status(500).json({ error: "Ошибка сохранения версии" });
  }
});

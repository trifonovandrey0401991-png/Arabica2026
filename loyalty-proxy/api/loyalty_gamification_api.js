/**
 * Loyalty Gamification API
 *
 * Управление уровнями клиентов, значками, колесом удачи и призами клиентов
 */

const fsp = require('fs').promises;
const path = require('path');
const multer = require('multer');
const crypto = require('crypto');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const CLIENTS_DIR = `${DATA_DIR}/clients`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;
const FCM_TOKENS_DIR = `${DATA_DIR}/fcm-tokens`;
const GAMIFICATION_DIR = `${DATA_DIR}/loyalty-gamification`;
const BADGES_DIR = `${GAMIFICATION_DIR}/badges`;
const WHEEL_HISTORY_DIR = `${GAMIFICATION_DIR}/wheel-history`;
const CLIENT_PRIZES_DIR = `${GAMIFICATION_DIR}/client-prizes`;
const SETTINGS_FILE = `${GAMIFICATION_DIR}/settings.json`;

// Firebase для push-уведомлений
let admin, firebaseInitialized;
try {
  const firebaseConfig = require('../firebase-admin-config');
  admin = firebaseConfig.admin;
  firebaseInitialized = firebaseConfig.firebaseInitialized;
} catch (e) {
  console.log('Firebase not initialized for gamification API');
  firebaseInitialized = false;
}

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Ensure directories exist
async function ensureDirectories() {
  for (const dir of [GAMIFICATION_DIR, BADGES_DIR, WHEEL_HISTORY_DIR, CLIENT_PRIZES_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
}

// Generate unique QR token
function generateQrToken() {
  return 'qr_' + crypto.randomBytes(16).toString('hex');
}

// Generate prize ID
function generatePrizeId() {
  return 'prize_' + Date.now() + '_' + crypto.randomBytes(4).toString('hex');
}

// Get FCM tokens for admins AND developers
async function getAdminAndDeveloperFcmTokens() {
  const tokens = [];
  try {
    const adminPhones = [];
    if (await fileExists(EMPLOYEES_DIR)) {
      const employeeFiles = await fsp.readdir(EMPLOYEES_DIR);
      for (const file of employeeFiles) {
        if (!file.endsWith('.json')) continue;
        const filePath = path.join(EMPLOYEES_DIR, file);
        const content = await fsp.readFile(filePath, 'utf8');
        const employee = JSON.parse(content);
        // isAdmin === true OR role === 'developer'
        if (employee && (employee.isAdmin === true || employee.role === 'developer') && employee.phone) {
          const normalizedPhone = employee.phone.replace(/[\s\+]/g, '');
          adminPhones.push(normalizedPhone);
        }
      }
    }

    console.log(`Найдено ${adminPhones.length} админов/разработчиков для push о призе`);

    if (!(await fileExists(FCM_TOKENS_DIR))) {
      return tokens;
    }

    const tokenFiles = await fsp.readdir(FCM_TOKENS_DIR);
    for (const file of tokenFiles) {
      if (!file.endsWith('.json')) continue;
      const phone = file.replace('.json', '');
      if (adminPhones.includes(phone)) {
        const filePath = path.join(FCM_TOKENS_DIR, file);
        const content = await fsp.readFile(filePath, 'utf8');
        const tokenData = JSON.parse(content);
        if (tokenData && tokenData.token) {
          tokens.push(tokenData.token);
        }
      }
    }
  } catch (e) {
    console.error('Ошибка получения FCM токенов:', e);
  }
  return tokens;
}

// Send push notification to admins/developers
async function sendPrizePushNotification(title, body, data = {}) {
  if (!firebaseInitialized || !admin) {
    console.log('Firebase не инициализирован, push о призе не отправлен');
    return;
  }

  const tokens = await getAdminAndDeveloperFcmTokens();
  if (tokens.length === 0) {
    console.log('Нет FCM токенов для push о призе');
    return;
  }

  console.log(`Отправка push о призе ${tokens.length} получателям: ${title}`);

  for (const token of tokens) {
    try {
      const stringData = Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      );

      await admin.messaging().send({
        token: token,
        notification: { title, body },
        data: {
          ...stringData,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'prizes_channel',
          },
        },
      });
      console.log('Push о призе отправлен:', token.substring(0, 20) + '...');
    } catch (e) {
      console.error('❌ Ошибка отправки push о призе:', e.message);
    }
  }
}

// Find pending prize for client
async function findPendingPrize(phone) {
  try {
    if (!(await fileExists(CLIENT_PRIZES_DIR))) {
      return null;
    }
    const files = await fsp.readdir(CLIENT_PRIZES_DIR);
    for (const file of files) {
      if (!file.endsWith('.json')) continue;
      const filePath = path.join(CLIENT_PRIZES_DIR, file);
      const content = await fsp.readFile(filePath, 'utf8');
      const prize = JSON.parse(content);
      if (prize.clientPhone === phone && prize.status === 'pending') {
        return prize;
      }
    }
  } catch (e) {
    console.error('Error finding pending prize:', e);
  }
  return null;
}

// Load prize by ID
async function loadPrize(prizeId) {
  try {
    const filePath = path.join(CLIENT_PRIZES_DIR, `${prizeId}.json`);
    if (await fileExists(filePath)) {
      const content = await fsp.readFile(filePath, 'utf8');
      return JSON.parse(content);
    }
  } catch (e) {
    console.error('Error loading prize:', e);
  }
  return null;
}

// Save prize
async function savePrize(prize) {
  const filePath = path.join(CLIENT_PRIZES_DIR, `${prize.id}.json`);
  await fsp.writeFile(filePath, JSON.stringify(prize, null, 2), 'utf8');
}

// Find prize by QR token
async function findPrizeByToken(qrToken) {
  try {
    if (!(await fileExists(CLIENT_PRIZES_DIR))) {
      return null;
    }
    const files = await fsp.readdir(CLIENT_PRIZES_DIR);
    for (const file of files) {
      if (!file.endsWith('.json')) continue;
      const filePath = path.join(CLIENT_PRIZES_DIR, file);
      const content = await fsp.readFile(filePath, 'utf8');
      const prize = JSON.parse(content);
      if (prize.qrToken === qrToken) {
        return prize;
      }
    }
  } catch (e) {
    console.error('Error finding prize by token:', e);
  }
  return null;
}

// Default settings with 10 levels
function getDefaultSettings() {
  return {
    levels: [
      { id: 1, name: 'Новичок', minFreeDrinks: 0, badge: { type: 'icon', value: 'coffee' }, colorHex: '#78909C' },
      { id: 2, name: 'Любитель', minFreeDrinks: 2, badge: { type: 'icon', value: 'favorite' }, colorHex: '#4CAF50' },
      { id: 3, name: 'Ценитель', minFreeDrinks: 5, badge: { type: 'icon', value: 'star' }, colorHex: '#2196F3' },
      { id: 4, name: 'Знаток', minFreeDrinks: 10, badge: { type: 'icon', value: 'workspace_premium' }, colorHex: '#9C27B0' },
      { id: 5, name: 'Эксперт', minFreeDrinks: 20, badge: { type: 'icon', value: 'military_tech' }, colorHex: '#FF9800' },
      { id: 6, name: 'Мастер', minFreeDrinks: 35, badge: { type: 'icon', value: 'emoji_events' }, colorHex: '#E91E63' },
      { id: 7, name: 'Гуру', minFreeDrinks: 50, badge: { type: 'icon', value: 'diamond' }, colorHex: '#00BCD4' },
      { id: 8, name: 'VIP', minFreeDrinks: 75, badge: { type: 'icon', value: 'verified' }, colorHex: '#673AB7' },
      { id: 9, name: 'Элита', minFreeDrinks: 100, badge: { type: 'icon', value: 'grade' }, colorHex: '#FF5722' },
      { id: 10, name: 'Легенда', minFreeDrinks: 150, badge: { type: 'icon', value: 'auto_awesome' }, colorHex: '#FFD700' }
    ],
    wheel: {
      enabled: true,
      freeDrinksPerSpin: 5,
      sectors: [
        { index: 0, text: '+5 баллов', probability: 0.25, colorHex: '#4CAF50', prizeType: 'bonus_points', prizeValue: 5 },
        { index: 1, text: '+10 баллов', probability: 0.15, colorHex: '#2196F3', prizeType: 'bonus_points', prizeValue: 10 },
        { index: 2, text: 'Скидка 10%', probability: 0.15, colorHex: '#9C27B0', prizeType: 'discount', prizeValue: 10 },
        { index: 3, text: 'Бесплатный напиток', probability: 0.10, colorHex: '#FF9800', prizeType: 'free_drink', prizeValue: 1 },
        { index: 4, text: '+20 баллов', probability: 0.10, colorHex: '#E91E63', prizeType: 'bonus_points', prizeValue: 20 },
        { index: 5, text: 'Скидка 15%', probability: 0.08, colorHex: '#00BCD4', prizeType: 'discount', prizeValue: 15 },
        { index: 6, text: '+3 балла', probability: 0.10, colorHex: '#607D8B', prizeType: 'bonus_points', prizeValue: 3 },
        { index: 7, text: 'Мерч Arabica', probability: 0.04, colorHex: '#795548', prizeType: 'merch', prizeValue: 1 },
        { index: 8, text: '+50 баллов', probability: 0.02, colorHex: '#FFD700', prizeType: 'bonus_points', prizeValue: 50 },
        { index: 9, text: '2 бесплатных напитка', probability: 0.01, colorHex: '#FF5722', prizeType: 'free_drink', prizeValue: 2 }
      ]
    },
    updatedAt: new Date().toISOString()
  };
}

// Load settings
async function loadSettings() {
  try {
    if (await fileExists(SETTINGS_FILE)) {
      const content = await fsp.readFile(SETTINGS_FILE, 'utf8');
      return JSON.parse(content);
    }
  } catch (e) {
    console.error('Error loading gamification settings:', e);
  }
  return getDefaultSettings();
}

// Save settings
async function saveSettings(settings) {
  settings.updatedAt = new Date().toISOString();
  await fsp.writeFile(SETTINGS_FILE, JSON.stringify(settings, null, 2), 'utf8');
}

// Calculate client's level based on freeDrinksGiven
function calculateLevel(freeDrinksGiven, levels) {
  let currentLevel = levels[0];
  for (const level of levels) {
    if (freeDrinksGiven >= level.minFreeDrinks) {
      currentLevel = level;
    }
  }
  return currentLevel;
}

// Calculate earned badges (all levels up to current)
function calculateEarnedBadges(freeDrinksGiven, levels) {
  const badges = [];
  for (const level of levels) {
    if (freeDrinksGiven >= level.minFreeDrinks) {
      badges.push(level.id);
    }
  }
  return badges;
}

// Configure multer for badge uploads
const storage = multer.diskStorage({
  destination: async (req, file, cb) => {
    await ensureDirectories();
    cb(null, BADGES_DIR);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    const name = `badge_${Date.now()}${ext}`;
    cb(null, name);
  }
});

const upload = multer({
  storage,
  limits: { fileSize: 2 * 1024 * 1024 }, // 2MB limit
  fileFilter: (req, file, cb) => {
    const allowedTypes = ['image/png', 'image/jpeg', 'image/jpg', 'image/gif', 'image/webp'];
    if (allowedTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type. Only PNG, JPEG, GIF, WEBP allowed.'));
    }
  }
});

function setupLoyaltyGamificationAPI(app) {
  // Initialize directories
  ensureDirectories();

  // ===== SETTINGS =====

  // GET settings
  app.get('/api/loyalty-gamification/settings', async (req, res) => {
    try {
      console.log('GET /api/loyalty-gamification/settings');
      const settings = await loadSettings();
      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting gamification settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST settings (admin only)
  app.post('/api/loyalty-gamification/settings', async (req, res) => {
    try {
      console.log('POST /api/loyalty-gamification/settings');
      const { levels, wheel } = req.body;

      const settings = await loadSettings();

      if (levels) {
        settings.levels = levels;
      }
      if (wheel) {
        settings.wheel = wheel;
      }

      await saveSettings(settings);
      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving gamification settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== BADGE UPLOAD =====

  app.post('/api/loyalty-gamification/upload-badge', upload.single('badge'), async (req, res) => {
    try {
      console.log('POST /api/loyalty-gamification/upload-badge');

      if (!req.file) {
        return res.status(400).json({ success: false, error: 'No file uploaded' });
      }

      const badgeUrl = `/loyalty-gamification/badges/${req.file.filename}`;
      res.json({ success: true, filename: req.file.filename, url: badgeUrl });
    } catch (error) {
      console.error('Error uploading badge:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Serve badge images
  app.use('/loyalty-gamification/badges', require('express').static(BADGES_DIR));

  // ===== CLIENT DATA =====

  // GET client gamification data
  app.get('/api/loyalty-gamification/client/:phone', async (req, res) => {
    try {
      const phone = req.params.phone.replace(/[\s+]/g, '');
      console.log('GET /api/loyalty-gamification/client:', phone);

      const clientPath = path.join(CLIENTS_DIR, `${phone}.json`);
      const settings = await loadSettings();

      let client = {
        phone,
        freeDrinksGiven: 0,
        currentLevel: 1,
        earnedBadges: [1],
        wheelSpinsAvailable: 0,
        wheelSpinsUsed: 0
      };

      if (await fileExists(clientPath)) {
        const content = await fsp.readFile(clientPath, 'utf8');
        const clientData = JSON.parse(content);
        client = { ...client, ...clientData };
      }

      // Calculate current level and badges
      const freeDrinksGiven = client.freeDrinksGiven || 0;
      const currentLevel = calculateLevel(freeDrinksGiven, settings.levels);
      const earnedBadges = calculateEarnedBadges(freeDrinksGiven, settings.levels);

      // Calculate wheel progress
      const wheelSpinsUsed = client.wheelSpinsUsed || 0;
      const totalSpinsEarned = Math.floor(freeDrinksGiven / settings.wheel.freeDrinksPerSpin);
      const wheelSpinsAvailable = Math.max(0, totalSpinsEarned - wheelSpinsUsed);
      const drinksToNextSpin = settings.wheel.freeDrinksPerSpin - (freeDrinksGiven % settings.wheel.freeDrinksPerSpin);

      // Find next level
      let nextLevel = null;
      let drinksToNextLevel = null;
      for (const level of settings.levels) {
        if (level.minFreeDrinks > freeDrinksGiven) {
          nextLevel = level;
          drinksToNextLevel = level.minFreeDrinks - freeDrinksGiven;
          break;
        }
      }

      res.json({
        success: true,
        client: {
          phone: client.phone,
          name: client.name,
          freeDrinksGiven,
          currentLevel,
          earnedBadges,
          wheelSpinsAvailable,
          wheelSpinsUsed,
          drinksToNextSpin,
          nextLevel,
          drinksToNextLevel
        },
        settings: {
          levels: settings.levels,
          wheel: settings.wheel
        }
      });
    } catch (error) {
      console.error('Error getting client gamification data:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== WHEEL SPIN =====

  app.post('/api/loyalty-gamification/spin', async (req, res) => {
    try {
      const { phone } = req.body;
      console.log('POST /api/loyalty-gamification/spin:', phone);

      if (!phone) {
        return res.status(400).json({ success: false, error: 'Phone required' });
      }

      const normalizedPhone = phone.replace(/[\s+]/g, '');
      const clientPath = path.join(CLIENTS_DIR, `${normalizedPhone}.json`);
      const settings = await loadSettings();

      if (!settings.wheel.enabled) {
        return res.status(400).json({ success: false, error: 'Wheel is disabled' });
      }

      if (!(await fileExists(clientPath))) {
        return res.status(404).json({ success: false, error: 'Client not found' });
      }

      // Check for pending prize - client can only have ONE pending prize
      const pendingPrize = await findPendingPrize(normalizedPhone);
      if (pendingPrize) {
        return res.status(400).json({
          success: false,
          error: 'У вас есть невыданный приз. Получите его перед следующей прокруткой.',
          hasPendingPrize: true,
          pendingPrize: {
            id: pendingPrize.id,
            prize: pendingPrize.prize
          }
        });
      }

      const content = await fsp.readFile(clientPath, 'utf8');
      const client = JSON.parse(content);

      const freeDrinksGiven = client.freeDrinksGiven || 0;
      const wheelSpinsUsed = client.wheelSpinsUsed || 0;
      const totalSpinsEarned = Math.floor(freeDrinksGiven / settings.wheel.freeDrinksPerSpin);
      const wheelSpinsAvailable = Math.max(0, totalSpinsEarned - wheelSpinsUsed);

      if (wheelSpinsAvailable <= 0) {
        return res.status(400).json({ success: false, error: 'No spins available' });
      }

      // Spin the wheel (weighted random)
      const sectors = settings.wheel.sectors;
      const random = Math.random();
      let cumulative = 0;
      let winSector = sectors[0];

      for (const sector of sectors) {
        cumulative += sector.probability;
        if (random <= cumulative) {
          winSector = sector;
          break;
        }
      }

      // Update client
      client.wheelSpinsUsed = (client.wheelSpinsUsed || 0) + 1;
      client.lastWheelSpin = new Date().toISOString();
      client.updatedAt = new Date().toISOString();

      await fsp.writeFile(clientPath, JSON.stringify(client, null, 2), 'utf8');

      // Create prize record for client (all prizes now require manual issuance)
      const prizeId = generatePrizeId();
      const qrToken = generateQrToken();
      const now = new Date().toISOString();

      const prizeRecord = {
        id: prizeId,
        clientPhone: normalizedPhone,
        clientName: client.name || 'Клиент',
        prize: winSector.text,
        prizeType: winSector.prizeType,
        prizeValue: winSector.prizeValue,
        spinDate: now,
        status: 'pending',
        qrToken: qrToken,
        qrUsed: false,
        issuedBy: null,
        issuedByName: null,
        issuedAt: null
      };

      await savePrize(prizeRecord);
      console.log(`🎁 Создан приз для клиента ${normalizedPhone}: ${winSector.text}`);

      // Save spin to history
      const spinRecord = {
        id: `spin_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        phone: normalizedPhone,
        clientName: client.name,
        sectorIndex: winSector.index,
        prize: winSector.text,
        prizeType: winSector.prizeType,
        prizeValue: winSector.prizeValue,
        spunAt: now,
        prizeId: prizeId, // Link to prize record
        isProcessed: false // All prizes need manual issuance now
      };

      const monthKey = new Date().toISOString().slice(0, 7);
      const historyPath = path.join(WHEEL_HISTORY_DIR, `${monthKey}.json`);

      let history = [];
      if (await fileExists(historyPath)) {
        const historyContent = await fsp.readFile(historyPath, 'utf8');
        history = JSON.parse(historyContent);
      }
      history.push(spinRecord);
      await fsp.writeFile(historyPath, JSON.stringify(history, null, 2), 'utf8');

      // Send push notification to admins/developers
      const pushTitle = 'Клиент выиграл приз!';
      const pushBody = `${client.name || normalizedPhone}: ${winSector.text}`;
      await sendPrizePushNotification(pushTitle, pushBody, {
        type: 'client_wheel_prize',
        prizeId: prizeId,
        clientPhone: normalizedPhone,
        prizeName: winSector.text
      });

      res.json({
        success: true,
        spin: spinRecord,
        remainingSpins: wheelSpinsAvailable - 1,
        hasPendingPrize: true,
        prize: {
          id: prizeId,
          prize: winSector.text,
          prizeType: winSector.prizeType,
          prizeValue: winSector.prizeValue,
          qrToken: qrToken
        }
      });
    } catch (error) {
      console.error('Error spinning wheel:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET wheel history
  app.get('/api/loyalty-gamification/wheel-history', async (req, res) => {
    try {
      const { month, phone } = req.query;
      console.log('GET /api/loyalty-gamification/wheel-history:', month, phone);

      const monthKey = month || new Date().toISOString().slice(0, 7);
      const historyPath = path.join(WHEEL_HISTORY_DIR, `${monthKey}.json`);

      let history = [];
      if (await fileExists(historyPath)) {
        const content = await fsp.readFile(historyPath, 'utf8');
        history = JSON.parse(content);
      }

      if (phone) {
        const normalizedPhone = phone.replace(/[\s+]/g, '');
        history = history.filter(h => h.phone === normalizedPhone);
      }

      res.json({ success: true, history });
    } catch (error) {
      console.error('Error getting wheel history:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PATCH mark prize as processed
  app.patch('/api/loyalty-gamification/wheel-history/:id/process', async (req, res) => {
    try {
      const { id } = req.params;
      const { processedBy } = req.body;
      console.log('PATCH /api/loyalty-gamification/wheel-history/:id/process:', id);

      // Find and update in all history files
      const files = await fsp.readdir(WHEEL_HISTORY_DIR);

      for (const file of files) {
        if (!file.endsWith('.json')) continue;

        const historyPath = path.join(WHEEL_HISTORY_DIR, file);
        const content = await fsp.readFile(historyPath, 'utf8');
        const history = JSON.parse(content);

        const record = history.find(h => h.id === id);
        if (record) {
          record.isProcessed = true;
          record.processedBy = processedBy;
          record.processedAt = new Date().toISOString();

          await fsp.writeFile(historyPath, JSON.stringify(history, null, 2), 'utf8');
          return res.json({ success: true, record });
        }
      }

      res.status(404).json({ success: false, error: 'Record not found' });
    } catch (error) {
      console.error('Error processing prize:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CLIENT PRIZES (Призы клиентов) =====

  // GET pending prize for client
  app.get('/api/loyalty-gamification/client/:phone/pending-prize', async (req, res) => {
    try {
      const phone = req.params.phone.replace(/[\s+]/g, '');
      console.log('GET /api/loyalty-gamification/client/:phone/pending-prize:', phone);

      const prize = await findPendingPrize(phone);

      if (prize) {
        res.json({
          success: true,
          hasPendingPrize: true,
          prize: {
            id: prize.id,
            prize: prize.prize,
            prizeType: prize.prizeType,
            prizeValue: prize.prizeValue,
            spinDate: prize.spinDate,
            qrToken: prize.qrToken
          }
        });
      } else {
        res.json({
          success: true,
          hasPendingPrize: false,
          prize: null
        });
      }
    } catch (error) {
      console.error('Error getting pending prize:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST generate new QR token for prize
  app.post('/api/loyalty-gamification/generate-qr', async (req, res) => {
    try {
      const { prizeId, phone } = req.body;
      console.log('POST /api/loyalty-gamification/generate-qr:', prizeId || phone);

      let prize;
      if (prizeId) {
        prize = await loadPrize(prizeId);
      } else if (phone) {
        const normalizedPhone = phone.replace(/[\s+]/g, '');
        prize = await findPendingPrize(normalizedPhone);
      }

      if (!prize) {
        return res.status(404).json({ success: false, error: 'Prize not found' });
      }

      if (prize.status !== 'pending') {
        return res.status(400).json({ success: false, error: 'Prize already issued' });
      }

      // Generate new QR token
      prize.qrToken = generateQrToken();
      prize.qrUsed = false;
      await savePrize(prize);

      console.log(`🔄 Новый QR-токен сгенерирован для приза ${prize.id}`);

      res.json({
        success: true,
        qrToken: prize.qrToken,
        prize: {
          id: prize.id,
          prize: prize.prize,
          prizeType: prize.prizeType,
          prizeValue: prize.prizeValue
        }
      });
    } catch (error) {
      console.error('Error generating QR:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST scan prize QR code (employee action)
  app.post('/api/loyalty-gamification/scan-prize', async (req, res) => {
    try {
      const { qrToken } = req.body;
      console.log('POST /api/loyalty-gamification/scan-prize:', qrToken);

      if (!qrToken) {
        return res.status(400).json({ success: false, error: 'QR token required' });
      }

      const prize = await findPrizeByToken(qrToken);

      if (!prize) {
        return res.status(404).json({ success: false, error: 'Приз не найден или QR недействителен' });
      }

      if (prize.status !== 'pending') {
        return res.status(400).json({
          success: false,
          error: 'Этот приз уже выдан',
          prize: {
            id: prize.id,
            prize: prize.prize,
            status: prize.status,
            issuedAt: prize.issuedAt,
            issuedByName: prize.issuedByName
          }
        });
      }

      if (prize.qrUsed) {
        return res.status(400).json({
          success: false,
          error: 'QR-код уже был отсканирован. Попросите клиента показать новый QR.',
          prizeId: prize.id
        });
      }

      // Mark QR as used (prevents double scanning)
      prize.qrUsed = true;
      await savePrize(prize);

      console.log(`📱 QR приза отсканирован: ${prize.id} - ${prize.prize}`);

      res.json({
        success: true,
        prize: {
          id: prize.id,
          clientPhone: prize.clientPhone,
          clientName: prize.clientName,
          prize: prize.prize,
          prizeType: prize.prizeType,
          prizeValue: prize.prizeValue,
          spinDate: prize.spinDate,
          status: prize.status
        }
      });
    } catch (error) {
      console.error('Error scanning prize:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST issue prize (employee confirms delivery)
  app.post('/api/loyalty-gamification/issue-prize', async (req, res) => {
    try {
      const { prizeId, employeePhone, employeeName } = req.body;
      console.log('POST /api/loyalty-gamification/issue-prize:', prizeId);

      if (!prizeId) {
        return res.status(400).json({ success: false, error: 'Prize ID required' });
      }

      const prize = await loadPrize(prizeId);

      if (!prize) {
        return res.status(404).json({ success: false, error: 'Prize not found' });
      }

      if (prize.status !== 'pending') {
        return res.status(400).json({ success: false, error: 'Prize already issued' });
      }

      // Update prize status
      prize.status = 'issued';
      prize.issuedBy = employeePhone || 'unknown';
      prize.issuedByName = employeeName || 'Сотрудник';
      prize.issuedAt = new Date().toISOString();

      await savePrize(prize);

      // Apply prize to client account
      const clientPath = path.join(CLIENTS_DIR, `${prize.clientPhone}.json`);
      if (await fileExists(clientPath)) {
        const content = await fsp.readFile(clientPath, 'utf8');
        const client = JSON.parse(content);

        if (prize.prizeType === 'bonus_points') {
          client.points = (client.points || 0) + prize.prizeValue;
        } else if (prize.prizeType === 'free_drink') {
          client.freeDrinks = (client.freeDrinks || 0) + prize.prizeValue;
        }
        // discount and merch are noted but don't change client fields

        client.updatedAt = new Date().toISOString();
        await fsp.writeFile(clientPath, JSON.stringify(client, null, 2), 'utf8');
      }

      // Update spin history
      if (prize.spinId) {
        // Find and update in wheel history
        const files = await fsp.readdir(WHEEL_HISTORY_DIR);
        for (const file of files) {
          if (!file.endsWith('.json')) continue;
          const historyPath = path.join(WHEEL_HISTORY_DIR, file);
          const content = await fsp.readFile(historyPath, 'utf8');
          const history = JSON.parse(content);
          const record = history.find(h => h.prizeId === prizeId);
          if (record) {
            record.isProcessed = true;
            record.processedBy = employeeName || employeePhone;
            record.processedAt = prize.issuedAt;
            await fsp.writeFile(historyPath, JSON.stringify(history, null, 2), 'utf8');
            break;
          }
        }
      }

      console.log(`✅ Приз выдан: ${prize.id} - ${prize.prize} клиенту ${prize.clientPhone}`);

      // Send push notification to admins/developers about prize issuance
      const issuePushTitle = 'Приз выдан';
      const issuePushBody = `${prize.clientName}: ${prize.prize} (выдал: ${prize.issuedByName})`;
      await sendPrizePushNotification(issuePushTitle, issuePushBody, {
        type: 'client_prize_issued',
        prizeId: prize.id,
        clientPhone: prize.clientPhone,
        prizeName: prize.prize,
        issuedBy: prize.issuedByName
      });

      res.json({
        success: true,
        message: 'Приз выдан',
        prize: {
          id: prize.id,
          prize: prize.prize,
          status: prize.status,
          issuedAt: prize.issuedAt,
          issuedByName: prize.issuedByName
        }
      });
    } catch (error) {
      console.error('Error issuing prize:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST postpone prize (generate new QR, keep pending)
  app.post('/api/loyalty-gamification/postpone-prize', async (req, res) => {
    try {
      const { prizeId } = req.body;
      console.log('POST /api/loyalty-gamification/postpone-prize:', prizeId);

      if (!prizeId) {
        return res.status(400).json({ success: false, error: 'Prize ID required' });
      }

      const prize = await loadPrize(prizeId);

      if (!prize) {
        return res.status(404).json({ success: false, error: 'Prize not found' });
      }

      if (prize.status !== 'pending') {
        return res.status(400).json({ success: false, error: 'Prize already issued' });
      }

      // Generate new QR token for next time
      prize.qrToken = generateQrToken();
      prize.qrUsed = false;

      await savePrize(prize);

      console.log(`⏸️ Приз отложен, новый QR: ${prize.id}`);

      res.json({
        success: true,
        message: 'Приз отложен. Клиент может показать новый QR позже.',
        qrToken: prize.qrToken
      });
    } catch (error) {
      console.error('Error postponing prize:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET client prizes report
  app.get('/api/loyalty-gamification/client-prizes-report', async (req, res) => {
    try {
      const { status, month, limit = 100 } = req.query;
      console.log('GET /api/loyalty-gamification/client-prizes-report:', { status, month });

      const prizes = [];

      if (!(await fileExists(CLIENT_PRIZES_DIR))) {
        return res.json({ success: true, prizes: [] });
      }

      const files = await fsp.readdir(CLIENT_PRIZES_DIR);

      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        const filePath = path.join(CLIENT_PRIZES_DIR, file);
        const content = await fsp.readFile(filePath, 'utf8');
        const prize = JSON.parse(content);

        // Filter by status if specified
        if (status && prize.status !== status) continue;

        // Filter by month if specified
        if (month) {
          const prizeMonth = prize.spinDate.slice(0, 7);
          if (prizeMonth !== month) continue;
        }

        prizes.push(prize);
      }

      // Sort by date (newest first)
      prizes.sort((a, b) => new Date(b.spinDate) - new Date(a.spinDate));

      // Apply limit
      const limitedPrizes = prizes.slice(0, parseInt(limit));

      res.json({
        success: true,
        prizes: limitedPrizes,
        total: prizes.length
      });
    } catch (error) {
      console.error('Error getting client prizes report:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Loyalty Gamification API initialized (with client prizes)');
}

module.exports = { setupLoyaltyGamificationAPI };

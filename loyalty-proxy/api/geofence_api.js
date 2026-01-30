/**
 * API для геофенсинг push-уведомлений
 * Отправляет push-уведомления клиентам при входе в радиус магазина
 */

const fs = require('fs');
const path = require('path');

// Директории хранения данных
const GEOFENCE_SETTINGS_FILE = '/var/www/geofence-settings.json';
const GEOFENCE_NOTIFICATIONS_DIR = '/var/www/geofence-notifications';
const SHOPS_DIR = '/var/www/shops';

// Создаём директории если не существуют
if (!fs.existsSync(GEOFENCE_NOTIFICATIONS_DIR)) {
  fs.mkdirSync(GEOFENCE_NOTIFICATIONS_DIR, { recursive: true });
}

// ==================== УТИЛИТЫ ====================

function loadJsonFile(filePath, defaultValue = null) {
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

/**
 * Загрузить настройки геозоны
 */
function loadGeofenceSettings() {
  const defaultSettings = {
    enabled: true,
    radiusMeters: 500,
    notificationTitle: 'Arabica рядом!',
    notificationBody: 'Вы рядом с нашей кофейней. Заходите за ароматным кофе!',
    cooldownHours: 24,
    updatedAt: new Date().toISOString(),
    updatedBy: 'system'
  };

  const settings = loadJsonFile(GEOFENCE_SETTINGS_FILE, null);
  return settings || defaultSettings;
}

/**
 * Сохранить настройки геозоны
 */
function saveGeofenceSettings(settings) {
  saveJsonFile(GEOFENCE_SETTINGS_FILE, settings);
}

/**
 * Загрузить все магазины с координатами
 */
function loadShopsWithCoordinates() {
  const shops = [];

  if (!fs.existsSync(SHOPS_DIR)) {
    console.log('Папка магазинов не существует');
    return shops;
  }

  const files = fs.readdirSync(SHOPS_DIR);
  for (const file of files) {
    if (!file.endsWith('.json')) continue;
    try {
      const filePath = path.join(SHOPS_DIR, file);
      const shop = loadJsonFile(filePath, null);
      if (shop && shop.latitude && shop.longitude) {
        // Валидация координат
        const lat = parseFloat(shop.latitude);
        const lon = parseFloat(shop.longitude);
        if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
          shops.push({
            id: shop.id || file.replace('.json', ''),
            name: shop.name || '',
            address: shop.address || '',
            latitude: lat,
            longitude: lon
          });
        }
      }
    } catch (e) {
      console.error(`Ошибка чтения магазина ${file}:`, e);
    }
  }

  return shops;
}

/**
 * Рассчитать расстояние между двумя точками (формула Хаверсина)
 * @returns расстояние в метрах
 */
function calculateGpsDistance(lat1, lon1, lat2, lon2) {
  const R = 6371000; // Радиус Земли в метрах
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Проверить, было ли уведомление отправлено в период cooldown
 */
function wasNotificationSentRecently(phone, shopId, cooldownHours) {
  try {
    const today = new Date().toISOString().split('T')[0];
    const normalizedPhone = phone.replace(/[\s+]/g, '');
    const notificationFile = path.join(
      GEOFENCE_NOTIFICATIONS_DIR,
      `${normalizedPhone}_${today}.json`
    );

    if (!fs.existsSync(notificationFile)) {
      return false;
    }

    const notifications = loadJsonFile(notificationFile, []);
    const now = new Date();

    for (const n of notifications) {
      if (n.shopId === shopId) {
        const sentAt = new Date(n.sentAt);
        const hoursSinceSent = (now - sentAt) / (1000 * 60 * 60);
        if (hoursSinceSent < cooldownHours) {
          return true;
        }
      }
    }

    return false;
  } catch (e) {
    console.error('Ошибка проверки истории уведомлений:', e);
    return false;
  }
}

/**
 * Сохранить запись об отправленном уведомлении
 */
function saveNotificationRecord(phone, shop, distance) {
  try {
    const today = new Date().toISOString().split('T')[0];
    const normalizedPhone = phone.replace(/[\s+]/g, '');
    const notificationFile = path.join(
      GEOFENCE_NOTIFICATIONS_DIR,
      `${normalizedPhone}_${today}.json`
    );

    const notifications = loadJsonFile(notificationFile, []);

    notifications.push({
      phone: normalizedPhone,
      shopId: shop.id,
      shopName: shop.name,
      shopAddress: shop.address,
      sentAt: new Date().toISOString(),
      distance: Math.round(distance)
    });

    saveJsonFile(notificationFile, notifications);
    console.log(`📍 Геозона: записано уведомление для ${phone} -> ${shop.address}`);
  } catch (e) {
    console.error('Ошибка сохранения записи уведомления:', e);
  }
}

/**
 * Очистить старые файлы уведомлений (старше 7 дней)
 */
function cleanupOldNotifications() {
  try {
    if (!fs.existsSync(GEOFENCE_NOTIFICATIONS_DIR)) return;

    const files = fs.readdirSync(GEOFENCE_NOTIFICATIONS_DIR);
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      // Извлекаем дату из имени файла (phone_YYYY-MM-DD.json)
      const match = file.match(/_(\d{4}-\d{2}-\d{2})\.json$/);
      if (match) {
        const fileDate = new Date(match[1]);
        if (fileDate < sevenDaysAgo) {
          fs.unlinkSync(path.join(GEOFENCE_NOTIFICATIONS_DIR, file));
          console.log(`🗑️ Удалён старый файл геозоны: ${file}`);
        }
      }
    }
  } catch (e) {
    console.error('Ошибка очистки старых уведомлений:', e);
  }
}

// ==================== API SETUP ====================

function setupGeofenceAPI(app, sendPushToPhone) {
  console.log('📍 Геофенсинг API инициализирован');

  // Очистка при старте
  cleanupOldNotifications();

  // Очистка каждые 24 часа
  setInterval(cleanupOldNotifications, 24 * 60 * 60 * 1000);

  // GET /api/geofence-settings - получить настройки
  app.get('/api/geofence-settings', (req, res) => {
    try {
      const settings = loadGeofenceSettings();
      res.json({ success: true, settings });
    } catch (e) {
      console.error('Ошибка получения настроек геозоны:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/geofence-settings - обновить настройки (только админ)
  app.post('/api/geofence-settings', (req, res) => {
    try {
      const { enabled, radiusMeters, notificationTitle, notificationBody, cooldownHours } = req.body;

      const settings = loadGeofenceSettings();

      if (typeof enabled === 'boolean') settings.enabled = enabled;
      if (radiusMeters && radiusMeters > 0) settings.radiusMeters = parseInt(radiusMeters);
      if (notificationTitle) settings.notificationTitle = notificationTitle;
      if (notificationBody) settings.notificationBody = notificationBody;
      if (cooldownHours && cooldownHours > 0) settings.cooldownHours = parseInt(cooldownHours);

      settings.updatedAt = new Date().toISOString();
      settings.updatedBy = req.body.updatedBy || 'admin';

      saveGeofenceSettings(settings);

      console.log('📍 Настройки геозоны обновлены:', settings);
      res.json({ success: true, settings });
    } catch (e) {
      console.error('Ошибка обновления настроек геозоны:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/geofence/client-check - проверка геозоны клиента
  app.post('/api/geofence/client-check', async (req, res) => {
    try {
      const { clientPhone, latitude, longitude } = req.body;

      // Валидация входных данных
      if (!clientPhone || latitude === undefined || longitude === undefined) {
        return res.json({ success: false, error: 'Missing required fields' });
      }

      const lat = parseFloat(latitude);
      const lon = parseFloat(longitude);

      if (isNaN(lat) || isNaN(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
        return res.json({ success: false, error: 'Invalid coordinates' });
      }

      // 1. Загрузить настройки
      const settings = loadGeofenceSettings();
      if (!settings.enabled) {
        return res.json({ success: true, triggered: false, reason: 'disabled' });
      }

      // 2. Загрузить магазины с координатами
      const shops = loadShopsWithCoordinates();
      console.log(`📍 Геозона: загружено ${shops.length} магазинов, клиент: ${lat}, ${lon}, радиус: ${settings.radiusMeters}м`);

      if (shops.length === 0) {
        return res.json({ success: true, triggered: false, reason: 'no_shops' });
      }

      // 3. Найти ближайший магазин в радиусе
      let closestShop = null;
      let closestDistance = Infinity;

      for (const shop of shops) {
        const distance = calculateGpsDistance(lat, lon, shop.latitude, shop.longitude);
        console.log(`📍 ${shop.name}: ${Math.round(distance)}м`);

        if (distance < closestDistance) {
          closestDistance = distance;
          closestShop = shop;
        }

        if (distance <= settings.radiusMeters) {
          // 4. Проверить cooldown
          if (wasNotificationSentRecently(clientPhone, shop.id, settings.cooldownHours)) {
            console.log(`📍 Геозона: cooldown активен для ${clientPhone} -> ${shop.address}`);
            continue;
          }

          // 5. Отправить push
          if (sendPushToPhone) {
            const sent = await sendPushToPhone(
              clientPhone,
              settings.notificationTitle,
              settings.notificationBody,
              { type: 'geofence', shopId: shop.id, shopAddress: shop.address }
            );

            if (sent) {
              // 6. Записать в историю
              saveNotificationRecord(clientPhone, shop, distance);

              console.log(`📍 Геозона: push отправлен ${clientPhone} -> ${shop.address} (${Math.round(distance)}м)`);

              return res.json({
                success: true,
                triggered: true,
                shopId: shop.id,
                shopAddress: shop.address,
                distance: Math.round(distance)
              });
            }
          }
        }
      }

      console.log(`📍 Геозона: ближайший магазин "${closestShop?.name}" на ${Math.round(closestDistance)}м (радиус: ${settings.radiusMeters}м)`);
      res.json({
        success: true,
        triggered: false,
        reason: 'not_in_radius',
        debug: {
          closestShop: closestShop?.name,
          closestDistance: Math.round(closestDistance),
          radiusMeters: settings.radiusMeters,
          shopsChecked: shops.length
        }
      });
    } catch (e) {
      console.error('Ошибка проверки геозоны:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // GET /api/geofence/stats - статистика уведомлений (для админа)
  app.get('/api/geofence/stats', (req, res) => {
    try {
      const { date } = req.query;
      const targetDate = date || new Date().toISOString().split('T')[0];

      const notifications = [];

      if (fs.existsSync(GEOFENCE_NOTIFICATIONS_DIR)) {
        const files = fs.readdirSync(GEOFENCE_NOTIFICATIONS_DIR);
        for (const file of files) {
          if (file.includes(targetDate) && file.endsWith('.json')) {
            const filePath = path.join(GEOFENCE_NOTIFICATIONS_DIR, file);
            const fileNotifications = loadJsonFile(filePath, []);
            notifications.push(...fileNotifications);
          }
        }
      }

      // Группировка по магазинам
      const byShop = {};
      for (const n of notifications) {
        if (!byShop[n.shopId]) {
          byShop[n.shopId] = {
            shopId: n.shopId,
            shopAddress: n.shopAddress,
            count: 0
          };
        }
        byShop[n.shopId].count++;
      }

      res.json({
        success: true,
        date: targetDate,
        totalNotifications: notifications.length,
        byShop: Object.values(byShop),
        notifications: notifications.slice(-50) // Последние 50
      });
    } catch (e) {
      console.error('Ошибка получения статистики геозоны:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });
}

module.exports = { setupGeofenceAPI };

/**
 * API для управления менеджерами магазинов (мультитенантность)
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 *
 * Структура данных shop-managers.json:
 * {
 *   "developers": ["79XXXXXXXXXX"],  // Телефоны разработчиков (видят всё)
 *   "managers": [
 *     {
 *       "phone": "79001234567",
 *       "name": "Иван Иванов",
 *       "managedShops": ["shop_1", "shop_2"],
 *       "employees": ["79111111111", "79222222222"]
 *     }
 *   ],
 *   "storeManagers": [
 *     {
 *       "phone": "79444444444",
 *       "shopId": "shop_1",
 *       "canSeeAllManagerShops": false
 *     }
 *   ]
 * }
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const SHOP_MANAGERS_FILE = `${DATA_DIR}/shop-managers.json`;

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

/**
 * Инициализация файла shop-managers.json
 */
async function initShopManagersFile() {
  if (!(await fileExists(SHOP_MANAGERS_FILE))) {
    const defaultData = {
      developers: [],
      managers: [],
      storeManagers: []
    };
    await fsp.writeFile(SHOP_MANAGERS_FILE, JSON.stringify(defaultData, null, 2), 'utf8');
    console.log('Created shop-managers.json with default structure');
  }
}

/**
 * Загрузить данные shop-managers
 */
async function loadShopManagers() {
  try {
    await initShopManagersFile();
    const content = await fsp.readFile(SHOP_MANAGERS_FILE, 'utf8');
    return JSON.parse(content);
  } catch (error) {
    console.error('Error loading shop-managers.json:', error);
    return { developers: [], managers: [], storeManagers: [] };
  }
}

/**
 * Сохранить данные shop-managers
 */
async function saveShopManagers(data) {
  try {
    await fsp.writeFile(SHOP_MANAGERS_FILE, JSON.stringify(data, null, 2), 'utf8');
    return true;
  } catch (error) {
    console.error('Error saving shop-managers.json:', error);
    return false;
  }
}

/**
 * Нормализация телефона
 * M-11: Унифицировано — только цифры (как sanitizePhone в file_helpers)
 */
function normalizePhone(phone) {
  if (!phone) return '';
  return phone.toString().replace(/[^\d]/g, '');
}

/**
 * Проверить, является ли телефон разработчиком
 */
async function isDeveloper(phone) {
  const data = await loadShopManagers();
  const normalizedPhone = normalizePhone(phone);
  return data.developers.some(dev => normalizePhone(dev) === normalizedPhone);
}

/**
 * Получить данные управляющего (admin) по телефону
 */
async function getManagerData(phone) {
  const data = await loadShopManagers();
  const normalizedPhone = normalizePhone(phone);
  return data.managers.find(m => normalizePhone(m.phone) === normalizedPhone) || null;
}

/**
 * Получить данные заведующей магазина по телефону
 */
async function getStoreManagerData(phone) {
  const data = await loadShopManagers();
  const normalizedPhone = normalizePhone(phone);
  return data.storeManagers.find(sm => normalizePhone(sm.phone) === normalizedPhone) || null;
}

/**
 * Получить роль пользователя для мультитенантности
 */
async function getUserMultitenantRole(phone) {
  const normalizedPhone = normalizePhone(phone);

  // 1. Проверка на разработчика
  if (await isDeveloper(normalizedPhone)) {
    return {
      role: 'developer',
      managedShopIds: [], // Видит все
      managedEmployees: [] // Видит всех
    };
  }

  // 2. Проверка на управляющего (admin)
  const managerData = await getManagerData(normalizedPhone);
  if (managerData) {
    return {
      role: 'admin',
      managedShopIds: managerData.managedShops || [],
      managedEmployees: managerData.employees || [],
      managerName: managerData.name
    };
  }

  // 3. Проверка на заведующую магазина
  const storeManagerData = await getStoreManagerData(normalizedPhone);
  if (storeManagerData) {
    // Поддержка множественных магазинов (managedShopIds) и обратная совместимость (shopId)
    const managedShopIds = storeManagerData.managedShopIds ||
      (storeManagerData.shopId ? [storeManagerData.shopId] : []);

    return {
      role: 'manager',
      primaryShopId: storeManagerData.shopId || (managedShopIds.length > 0 ? managedShopIds[0] : null),
      managedShopIds: managedShopIds,
      canSeeAllManagerShops: storeManagerData.canSeeAllManagerShops || false
    };
  }

  // По умолчанию - не мультитенантный пользователь
  return null;
}

/**
 * Настройка API endpoints
 */
function setupShopManagersAPI(app) {

  // GET /api/shop-managers - получить конфигурацию (только для developer)
  app.get('/api/shop-managers', async (req, res) => {
    try {
      const { phone } = req.query;

      if (!phone) {
        return res.status(400).json({ success: false, error: 'Phone required' });
      }

      const normalizedPhone = normalizePhone(phone);

      // Только developer может видеть полную конфигурацию
      if (!(await isDeveloper(normalizedPhone))) {
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const data = await loadShopManagers();
      res.json({ success: true, data });

    } catch (error) {
      console.error('Error in GET /api/shop-managers:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/shop-managers/role/:phone - получить мультитенантную роль
  app.get('/api/shop-managers/role/:phone', async (req, res) => {
    try {
      const { phone } = req.params;
      const role = await getUserMultitenantRole(phone);

      res.json({
        success: true,
        role: role,
        isDeveloper: await isDeveloper(phone),
        isManager: role?.role === 'admin',
        isStoreManager: role?.role === 'manager'
      });

    } catch (error) {
      console.error('Error in GET /api/shop-managers/role:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/shop-managers/developers - добавить разработчика (только developer)
  app.post('/api/shop-managers/developers', async (req, res) => {
    try {
      const { adminPhone, developerPhone } = req.body;

      if (!(await isDeveloper(adminPhone))) {
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const data = await loadShopManagers();
      const normalizedPhone = normalizePhone(developerPhone);

      if (!data.developers.includes(normalizedPhone)) {
        data.developers.push(normalizedPhone);
        await saveShopManagers(data);
      }

      res.json({ success: true });

    } catch (error) {
      console.error('Error in POST /api/shop-managers/developers:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/shop-managers/developers/:phone - удалить разработчика
  app.delete('/api/shop-managers/developers/:phone', async (req, res) => {
    try {
      const { phone } = req.params;
      const { adminPhone } = req.query;

      if (!(await isDeveloper(adminPhone))) {
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const data = await loadShopManagers();
      const normalizedPhone = normalizePhone(phone);
      data.developers = data.developers.filter(d => normalizePhone(d) !== normalizedPhone);
      await saveShopManagers(data);

      res.json({ success: true });

    } catch (error) {
      console.error('Error in DELETE /api/shop-managers/developers:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/shop-managers/managers - добавить/обновить управляющего
  app.post('/api/shop-managers/managers', async (req, res) => {
    try {
      const { adminPhone, manager } = req.body;

      if (!(await isDeveloper(adminPhone))) {
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const data = await loadShopManagers();
      const normalizedPhone = normalizePhone(manager.phone);

      // Найти существующего или создать нового
      const existingIndex = data.managers.findIndex(
        m => normalizePhone(m.phone) === normalizedPhone
      );

      const managerData = {
        phone: normalizedPhone,
        name: manager.name || '',
        managedShops: manager.managedShops || [],
        employees: manager.employees || []
      };

      if (existingIndex >= 0) {
        data.managers[existingIndex] = managerData;
      } else {
        data.managers.push(managerData);
      }

      await saveShopManagers(data);
      res.json({ success: true, manager: managerData });

    } catch (error) {
      console.error('Error in POST /api/shop-managers/managers:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/shop-managers/managers/:phone - удалить управляющего
  app.delete('/api/shop-managers/managers/:phone', async (req, res) => {
    try {
      const { phone } = req.params;
      const { adminPhone } = req.query;

      if (!(await isDeveloper(adminPhone))) {
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const data = await loadShopManagers();
      const normalizedPhone = normalizePhone(phone);
      data.managers = data.managers.filter(m => normalizePhone(m.phone) !== normalizedPhone);
      await saveShopManagers(data);

      res.json({ success: true });

    } catch (error) {
      console.error('Error in DELETE /api/shop-managers/managers:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/shop-managers/managers/:phone/shops - обновить магазины управляющего
  app.put('/api/shop-managers/managers/:phone/shops', async (req, res) => {
    try {
      const { phone } = req.params;
      const { adminPhone, shopIds } = req.body;

      if (!(await isDeveloper(adminPhone))) {
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const data = await loadShopManagers();
      const normalizedPhone = normalizePhone(phone);
      const manager = data.managers.find(m => normalizePhone(m.phone) === normalizedPhone);

      if (!manager) {
        return res.status(404).json({ success: false, error: 'Manager not found' });
      }

      manager.managedShops = shopIds || [];
      await saveShopManagers(data);

      res.json({ success: true, manager });

    } catch (error) {
      console.error('Error in PUT /api/shop-managers/managers/:phone/shops:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/shop-managers/managers/:phone/employees - обновить сотрудников управляющего
  app.put('/api/shop-managers/managers/:phone/employees', async (req, res) => {
    try {
      const { phone } = req.params;
      const { adminPhone, employeePhones } = req.body;

      if (!(await isDeveloper(adminPhone))) {
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const data = await loadShopManagers();
      const normalizedPhone = normalizePhone(phone);
      const manager = data.managers.find(m => normalizePhone(m.phone) === normalizedPhone);

      if (!manager) {
        return res.status(404).json({ success: false, error: 'Manager not found' });
      }

      manager.employees = (employeePhones || []).map(p => normalizePhone(p));
      await saveShopManagers(data);

      res.json({ success: true, manager });

    } catch (error) {
      console.error('Error in PUT /api/shop-managers/managers/:phone/employees:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/shop-managers/store-managers - добавить/обновить заведующую магазина
  app.post('/api/shop-managers/store-managers', async (req, res) => {
    try {
      const { adminPhone, storeManager } = req.body;

      if (!(await isDeveloper(adminPhone))) {
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const data = await loadShopManagers();
      const normalizedPhone = normalizePhone(storeManager.phone);

      const existingIndex = data.storeManagers.findIndex(
        sm => normalizePhone(sm.phone) === normalizedPhone
      );

      const storeManagerData = {
        phone: normalizedPhone,
        shopId: storeManager.shopId,
        canSeeAllManagerShops: storeManager.canSeeAllManagerShops || false
      };

      if (existingIndex >= 0) {
        data.storeManagers[existingIndex] = storeManagerData;
      } else {
        data.storeManagers.push(storeManagerData);
      }

      await saveShopManagers(data);
      res.json({ success: true, storeManager: storeManagerData });

    } catch (error) {
      console.error('Error in POST /api/shop-managers/store-managers:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/shop-managers/store-managers - список всех заведующих (для admin/developer)
  app.get('/api/shop-managers/store-managers', async (req, res) => {
    try {
      const { phone } = req.query;

      if (!phone) {
        return res.status(400).json({ success: false, error: 'Phone required' });
      }

      const normalizedPhone = normalizePhone(phone);
      const isDev = await isDeveloper(normalizedPhone);
      const managerData = await getManagerData(normalizedPhone);

      if (!isDev && !managerData) {
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const data = await loadShopManagers();
      const storeManagers = (data.storeManagers || []).map(sm => ({
        ...sm,
        // Обеспечиваем наличие managedShopIds
        managedShopIds: sm.managedShopIds || (sm.shopId ? [sm.shopId] : [])
      }));

      res.json({ success: true, storeManagers });

    } catch (error) {
      console.error('Error in GET /api/shop-managers/store-managers:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/shop-managers/store-managers/:phone/shops - обновить магазины заведующей
  app.put('/api/shop-managers/store-managers/:phone/shops', async (req, res) => {
    try {
      const { phone } = req.params;
      const { adminPhone, managedShopIds } = req.body;

      if (!adminPhone) {
        return res.status(400).json({ success: false, error: 'adminPhone required' });
      }

      const normalizedAdminPhone = normalizePhone(adminPhone);
      const isDev = await isDeveloper(normalizedAdminPhone);
      const managerData = await getManagerData(normalizedAdminPhone);

      if (!isDev && !managerData) {
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const data = await loadShopManagers();
      const normalizedPhone = normalizePhone(phone);
      let sm = data.storeManagers.find(s => normalizePhone(s.phone) === normalizedPhone);

      if (!sm) {
        // Заведующей нет в storeManagers — создаём новую запись
        sm = { phone: normalizedPhone, managedShopIds: [] };
        if (!data.storeManagers) data.storeManagers = [];
        data.storeManagers.push(sm);
        console.log(`📝 Created new storeManager entry for ${normalizedPhone}`);
      }

      sm.managedShopIds = managedShopIds || [];
      // Обратная совместимость — shopId = первый из списка
      if (managedShopIds && managedShopIds.length > 0) {
        sm.shopId = managedShopIds[0];
      }

      await saveShopManagers(data);
      console.log(`✅ Store manager ${normalizedPhone} shops updated: ${(managedShopIds || []).length} shops`);
      res.json({ success: true, storeManager: sm });

    } catch (error) {
      console.error('Error in PUT /api/shop-managers/store-managers/:phone/shops:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/shop-managers/store-managers/:phone - удалить заведующую
  app.delete('/api/shop-managers/store-managers/:phone', async (req, res) => {
    try {
      const { phone } = req.params;
      const { adminPhone } = req.query;

      if (!(await isDeveloper(adminPhone))) {
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const data = await loadShopManagers();
      const normalizedPhone = normalizePhone(phone);
      data.storeManagers = data.storeManagers.filter(
        sm => normalizePhone(sm.phone) !== normalizedPhone
      );
      await saveShopManagers(data);

      res.json({ success: true });

    } catch (error) {
      console.error('Error in DELETE /api/shop-managers/store-managers:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('Shop Managers API initialized');
}

// Экспорт функций для использования в других модулях
module.exports = {
  setupShopManagersAPI,
  loadShopManagers,
  saveShopManagers,
  isDeveloper,
  getManagerData,
  getStoreManagerData,
  getUserMultitenantRole,
  normalizePhone
};

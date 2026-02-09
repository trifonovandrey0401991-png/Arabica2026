/**
 * Employees API - CRUD сотрудников
 * Поиск, пагинация, referralCode, кэш invalidation
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');
const dataCache = require('../utils/data_cache');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;

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
      } catch (e) {
        console.error(`[Employees] Error reading employee file ${file}:`, e.message);
      }
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

function setupEmployeesAPI(app, { isPaginationRequested, createPaginatedResponse, invalidateCache } = {}) {

  // GET /api/employees - получить всех сотрудников
  app.get('/api/employees', async (req, res) => {
    try {
      console.log('GET /api/employees');

      // SCALABILITY: Используем кэш если доступен, иначе читаем с диска
      let employees = dataCache.getEmployees();

      if (!employees) {
        employees = [];
        if (!await fileExists(EMPLOYEES_DIR)) {
          await fsp.mkdir(EMPLOYEES_DIR, { recursive: true });
        }
        const files = (await fsp.readdir(EMPLOYEES_DIR)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const filePath = path.join(EMPLOYEES_DIR, file);
            const content = await fsp.readFile(filePath, 'utf8');
            employees.push(JSON.parse(content));
          } catch (e) {
            console.error(`Ошибка чтения файла ${file}:`, e);
          }
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
      if (isPaginationRequested && isPaginationRequested(req.query)) {
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

  // POST /api/employees - создать нового сотрудника
  app.post('/api/employees', async (req, res) => {
    try {
      // Только админ может создавать сотрудников
      if (!req.user || !req.user.isAdmin) {
        return res.status(403).json({ success: false, error: 'Доступ запрещён: требуются права администратора' });
      }

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
        referralCode: req.body.referralCode || (await getNextReferralCode()),
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

      // SCALABILITY: Инвалидируем кэши при создании сотрудника
      if (employee.phone && invalidateCache) {
        invalidateCache(employee.phone);
      }
      dataCache.invalidateEmployees();

      res.json({ success: true, employee });
    } catch (error) {
      console.error('Ошибка создания сотрудника:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/employees/:id - обновить сотрудника
  app.put('/api/employees/:id', async (req, res) => {
    try {
      // Только админ может редактировать сотрудников
      if (!req.user || !req.user.isAdmin) {
        return res.status(403).json({ success: false, error: 'Доступ запрещён: требуются права администратора' });
      }

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
        referralCode: req.body.referralCode || (await getNextReferralCode()),
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

      // SCALABILITY: Инвалидируем кэши при изменении сотрудника
      if (invalidateCache) {
        invalidateCache(employee.phone);
      }
      dataCache.invalidateEmployees();

      res.json({ success: true, employee });
    } catch (error) {
      console.error('Ошибка обновления сотрудника:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/employees/:id - удалить сотрудника
  app.delete('/api/employees/:id', async (req, res) => {
    try {
      // Только админ может удалять сотрудников
      if (!req.user || !req.user.isAdmin) {
        return res.status(403).json({ success: false, error: 'Доступ запрещён: требуются права администратора' });
      }

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

      // SCALABILITY: Инвалидируем кэши при удалении сотрудника
      if (employeePhone && invalidateCache) {
        invalidateCache(employeePhone);
      }
      dataCache.invalidateEmployees();

      res.json({ success: true, message: 'Сотрудник удален' });
    } catch (error) {
      console.error('Ошибка удаления сотрудника:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Employees API initialized');
}

module.exports = { setupEmployeesAPI, getNextReferralCode };

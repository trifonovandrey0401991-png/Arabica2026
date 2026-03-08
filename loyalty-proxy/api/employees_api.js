/**
 * Employees API - CRUD сотрудников
 * Поиск, пагинация, referralCode, кэш invalidation
 *
 * Feature flag: USE_DB_EMPLOYEES=true → PostgreSQL, false → JSON files
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, sanitizeId } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const dataCache = require('../utils/data_cache');
const db = require('../utils/db');
const { createDbPaginatedResponse } = require('../utils/pagination');
const { requireEmployee, requireAdmin } = require('../utils/session_middleware');

const { loadShopManagers, saveShopManagers, normalizePhone: normPhone } = require('./shop_managers_api');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;
const USE_DB = process.env.USE_DB_EMPLOYEES === 'true';

/**
 * Получить следующий свободный referralCode (1-1000)
 */
async function getNextReferralCode() {
  try {
    let usedCodes;

    if (USE_DB) {
      const result = await db.query('SELECT referral_code FROM employees WHERE referral_code IS NOT NULL');
      usedCodes = new Set(result.rows.map(r => r.referral_code));
    } else {
      if (!await fileExists(EMPLOYEES_DIR)) return 1;

      const files = (await fsp.readdir(EMPLOYEES_DIR)).filter(f => f.endsWith('.json'));
      usedCodes = new Set();

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

/**
 * Парсинг boolean из req.body (true, 'true', 1 → true)
 */
function parseBool(value) {
  return value === true || value === 'true' || value === 1;
}

function setupEmployeesAPI(app, { isPaginationRequested, createPaginatedResponse, invalidateCache } = {}) {

  // GET /api/employees - получить всех сотрудников
  app.get('/api/employees', requireEmployee, async (req, res) => {
    try {
      console.log('GET /api/employees');
      let employees;

      if (USE_DB) {
        // SQL-level pagination with search
        if (isPaginationRequested && isPaginationRequested(req.query)) {
          const { search } = req.query;
          let where;
          let whereParams;
          if (search) {
            where = '(name ILIKE $1 OR phone LIKE $2 OR position ILIKE $3)';
            const pattern = `%${search}%`;
            whereParams = [pattern, pattern, pattern];
          }
          const result = await db.findAllPaginated('employees', {
            where,
            whereParams,
            orderBy: 'created_at',
            orderDir: 'DESC',
            page: parseInt(req.query.page) || 1,
            pageSize: Math.min(parseInt(req.query.limit) || 50, 200),
          });
          return res.json(createDbPaginatedResponse(result, 'employees', dbEmployeeToCamel));
        }

        const rows = await db.findAll('employees', { orderBy: 'created_at', orderDir: 'DESC' });
        employees = rows.map(dbEmployeeToCamel);
      } else {
        // SCALABILITY: Используем кэш если доступен, иначе читаем с диска
        employees = dataCache.getEmployees();

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

        // Сортируем по дате создания (новые первыми)
        employees.sort((a, b) => {
          const dateA = new Date(a.createdAt || 0);
          const dateB = new Date(b.createdAt || 0);
          return dateB - dateA;
        });
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

      // SCALABILITY: Пагинация если запрошена
      if (isPaginationRequested && isPaginationRequested(req.query)) {
        res.json(createPaginatedResponse(employees, req.query, 'employees'));
      } else {
        res.json({ success: true, employees });
      }
    } catch (error) {
      console.error('Ошибка получения сотрудников:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/employees/:id - получить сотрудника по ID
  app.get('/api/employees/:id', requireEmployee, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('GET /api/employees:', id);

      let employee;

      if (USE_DB) {
        const row = await db.findById('employees', id);
        if (!row) return res.status(404).json({ success: false, error: 'Сотрудник не найден' });
        employee = dbEmployeeToCamel(row);
      } else {
        const employeeFile = path.join(EMPLOYEES_DIR, `${id}.json`);
        if (!await fileExists(employeeFile)) {
          return res.status(404).json({ success: false, error: 'Сотрудник не найден' });
        }
        const content = await fsp.readFile(employeeFile, 'utf8');
        employee = JSON.parse(content);
      }

      res.json({ success: true, employee });
    } catch (error) {
      console.error('Ошибка получения сотрудника:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/employees - создать нового сотрудника
  app.post('/api/employees', requireAdmin, async (req, res) => {
    try {
      console.log('POST /api/employees:', JSON.stringify(req.body).substring(0, 200));

      // Валидация обязательных полей
      if (!req.body.name || req.body.name.trim() === '') {
        return res.status(400).json({ success: false, error: 'Имя сотрудника обязательно' });
      }

      // Валидация формата телефона (если указан)
      if (req.body.phone) {
        const phoneClean = req.body.phone.replace(/[\s+\-()]/g, '');
        if (!/^\d{10,15}$/.test(phoneClean)) {
          return res.status(400).json({ success: false, error: 'Неверный формат телефона' });
        }
      }

      // Валидация формата email (если указан)
      if (req.body.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(req.body.email)) {
        return res.status(400).json({ success: false, error: 'Неверный формат email' });
      }

      // Генерируем ID если не указан
      const rawId = req.body.id || `employee_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      const id = sanitizeId(rawId);
      const now = new Date().toISOString();
      const referralCode = req.body.referralCode || (await getNextReferralCode());

      let employee;

      if (USE_DB) {
        const row = await db.insert('employees', {
          id,
          referral_code: referralCode,
          name: req.body.name.trim(),
          position: req.body.position || null,
          department: req.body.department || null,
          phone: req.body.phone || null,
          email: req.body.email || null,
          is_admin: false, // Roles managed ONLY via shop-managers
          is_manager: false, // Roles managed ONLY via shop-managers
          employee_name: req.body.employeeName || null,
          preferred_work_days: req.body.preferredWorkDays || [],
          preferred_shops: req.body.preferredShops || [],
          shift_preferences: req.body.shiftPreferences || {},
          created_at: now,
          updated_at: now
        });
        employee = dbEmployeeToCamel(row);
      } else {
        if (!await fileExists(EMPLOYEES_DIR)) {
          await fsp.mkdir(EMPLOYEES_DIR, { recursive: true });
        }

        employee = {
          id,
          referralCode,
          name: req.body.name.trim(),
          position: req.body.position || null,
          department: req.body.department || null,
          phone: req.body.phone || null,
          email: req.body.email || null,
          isAdmin: false, // Roles managed ONLY via shop-managers
          isManager: false, // Roles managed ONLY via shop-managers
          employeeName: req.body.employeeName || null,
          preferredWorkDays: req.body.preferredWorkDays || [],
          preferredShops: req.body.preferredShops || [],
          shiftPreferences: req.body.shiftPreferences || {},
          createdAt: now,
          updatedAt: now,
        };
        const employeeFile = path.join(EMPLOYEES_DIR, `${id}.json`);
        await writeJsonFile(employeeFile, employee);
      }

      console.log('✅ Сотрудник создан:', id);

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
  app.put('/api/employees/:id', requireAdmin, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('PUT /api/employees:', id);

      // Валидация обязательных полей
      if (!req.body.name || req.body.name.trim() === '') {
        return res.status(400).json({ success: false, error: 'Имя сотрудника обязательно' });
      }

      // Валидация формата телефона (если указан)
      if (req.body.phone) {
        const phoneClean = req.body.phone.replace(/[\s+\-()]/g, '');
        if (!/^\d{10,15}$/.test(phoneClean)) {
          return res.status(400).json({ success: false, error: 'Неверный формат телефона' });
        }
      }

      // Валидация формата email (если указан)
      if (req.body.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(req.body.email)) {
        return res.status(400).json({ success: false, error: 'Неверный формат email' });
      }

      let employee;

      if (USE_DB) {
        const existing = await db.findById('employees', id);
        if (!existing) return res.status(404).json({ success: false, error: 'Сотрудник не найден' });

        const updateData = { updated_at: new Date().toISOString() };
        // Обязательные поля
        updateData.name = req.body.name.trim();
        updateData.referral_code = req.body.referralCode || existing.referral_code;
        // Опциональные — обновляем только если переданы
        if (req.body.position !== undefined) updateData.position = req.body.position;
        if (req.body.department !== undefined) updateData.department = req.body.department;
        if (req.body.phone !== undefined) updateData.phone = req.body.phone;
        if (req.body.email !== undefined) updateData.email = req.body.email;
        // isAdmin/isManager ignored — roles managed ONLY via shop-managers
        if (req.body.employeeName !== undefined) updateData.employee_name = req.body.employeeName;
        if (req.body.preferredWorkDays !== undefined) updateData.preferred_work_days = req.body.preferredWorkDays;
        if (req.body.preferredShops !== undefined) updateData.preferred_shops = req.body.preferredShops;
        if (req.body.shiftPreferences !== undefined) updateData.shift_preferences = req.body.shiftPreferences;

        const row = await db.updateById('employees', id, updateData);
        employee = dbEmployeeToCamel(row);

        // Cascade phone change to all related tables
        if (req.body.phone && existing.phone && req.body.phone !== existing.phone) {
          const oldPhone = existing.phone;
          const newPhone = req.body.phone.replace(/[\s+\-()]/g, '');
          try {
            await db.transaction(async (client) => {
              // Reference tables (employee_phone / assignee_phone / phone columns)
              const cascadeTables = [
                ['shift_reports', 'employee_phone'],
                ['shift_handover_reports', 'employee_phone'],
                ['recount_reports', 'employee_phone'],
                ['envelope_reports', 'employee_phone'],
                ['coffee_machine_reports', 'employee_phone'],
                ['rko_reports', 'employee_phone'],
                ['efficiency_penalties', 'employee_phone'],
                ['attendance', 'employee_phone'],
                ['task_assignments', 'assignee_phone'],
                ['recurring_task_instances', 'assignee_phone'],
                ['messenger_participants', 'phone'],
                ['auth_sessions', 'phone'],
              ];
              for (const [table, col] of cascadeTables) {
                await client.query(`UPDATE ${table} SET ${col} = $1 WHERE ${col} = $2`, [newPhone, oldPhone]);
              }

              // Tables with phone as PRIMARY KEY (need DELETE + INSERT)
              for (const pkTable of ['auth_pins', 'trusted_devices', 'fcm_tokens', 'messenger_profiles']) {
                const oldRow = await client.query(`SELECT * FROM ${pkTable} WHERE phone = $1`, [oldPhone]);
                if (oldRow.rows.length > 0) {
                  await client.query(`DELETE FROM ${pkTable} WHERE phone = $1`, [oldPhone]);
                  const rowData = { ...oldRow.rows[0], phone: newPhone };
                  const cols = Object.keys(rowData);
                  const placeholders = cols.map((_, i) => `$${i + 1}`);
                  await client.query(
                    `INSERT INTO ${pkTable} (${cols.join(',')}) VALUES (${placeholders.join(',')})`,
                    cols.map(c => rowData[c])
                  );
                }
              }

              // employee_registrations (PK = id = phone)
              const regRow = await client.query('SELECT * FROM employee_registrations WHERE id = $1', [oldPhone]);
              if (regRow.rows.length > 0) {
                await client.query('DELETE FROM employee_registrations WHERE id = $1', [oldPhone]);
                await client.query(
                  'INSERT INTO employee_registrations (id, data, created_at) VALUES ($1, $2, $3)',
                  [newPhone, regRow.rows[0].data, regRow.rows[0].created_at]
                );
              }
            });

            // Rename JSON registration file (dual-write)
            const oldRegFile = path.join(DATA_DIR, 'employee-registrations', `${oldPhone}.json`);
            const newRegFile = path.join(DATA_DIR, 'employee-registrations', `${newPhone}.json`);
            try {
              if (await fileExists(oldRegFile)) {
                const content = await fsp.readFile(oldRegFile, 'utf8');
                const data = JSON.parse(content);
                data.phone = newPhone;
                await writeJsonFile(newRegFile, data);
                await fsp.unlink(oldRegFile);
              }
            } catch (fsErr) {
              console.error('⚠️ JSON registration rename error:', fsErr.message);
            }

            console.log(`✅ Phone cascaded: ${oldPhone} → ${newPhone}`);
          } catch (cascErr) {
            console.error('⚠️ Phone cascade error (employee record updated OK):', cascErr.message);
          }
        }
      } else {
        const employeeFile = path.join(EMPLOYEES_DIR, `${id}.json`);
        if (!await fileExists(employeeFile)) {
          return res.status(404).json({ success: false, error: 'Сотрудник не найден' });
        }

        // Читаем существующие данные для сохранения createdAt
        const oldContent = await fsp.readFile(employeeFile, 'utf8');
        const oldEmployee = JSON.parse(oldContent);

        employee = {
          id,
          referralCode: req.body.referralCode || oldEmployee.referralCode,
          name: req.body.name.trim(),
          position: req.body.position !== undefined ? req.body.position : oldEmployee.position,
          department: req.body.department !== undefined ? req.body.department : oldEmployee.department,
          phone: req.body.phone !== undefined ? req.body.phone : oldEmployee.phone,
          email: req.body.email !== undefined ? req.body.email : oldEmployee.email,
          isAdmin: oldEmployee.isAdmin, // Roles managed ONLY via shop-managers
          isManager: oldEmployee.isManager, // Roles managed ONLY via shop-managers
          employeeName: req.body.employeeName !== undefined ? req.body.employeeName : oldEmployee.employeeName,
          preferredWorkDays: req.body.preferredWorkDays !== undefined ? req.body.preferredWorkDays : oldEmployee.preferredWorkDays,
          preferredShops: req.body.preferredShops !== undefined ? req.body.preferredShops : oldEmployee.preferredShops,
          shiftPreferences: req.body.shiftPreferences !== undefined ? req.body.shiftPreferences : oldEmployee.shiftPreferences,
          createdAt: oldEmployee.createdAt || new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        };

        await writeJsonFile(employeeFile, employee);
      }

      console.log('✅ Сотрудник обновлен:', id);

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
  app.delete('/api/employees/:id', requireAdmin, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('DELETE /api/employees:', id);

      let employeePhone = null;

      if (USE_DB) {
        // Читаем телефон перед удалением для инвалидации кэша
        const existing = await db.findById('employees', id);
        if (!existing) return res.status(404).json({ success: false, error: 'Сотрудник не найден' });
        employeePhone = existing.phone;

        await db.deleteById('employees', id);
      } else {
        const employeeFile = path.join(EMPLOYEES_DIR, `${id}.json`);
        if (!await fileExists(employeeFile)) {
          return res.status(404).json({ success: false, error: 'Сотрудник не найден' });
        }

        // Читаем телефон перед удалением для инвалидации кэша
        try {
          const content = await fsp.readFile(employeeFile, 'utf8');
          const employee = JSON.parse(content);
          employeePhone = employee.phone;
        } catch (e) { /* ignore */ }

        await fsp.unlink(employeeFile);
      }

      console.log('✅ Сотрудник удален:', id);

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

  console.log(`✅ Employees API initialized (storage: ${USE_DB ? 'PostgreSQL' : 'JSON files'})`);
}

/**
 * Преобразование DB row (snake_case) → camelCase (для совместимости с Flutter)
 */
function dbEmployeeToCamel(row) {
  return {
    id: row.id,
    referralCode: row.referral_code,
    name: row.name,
    position: row.position,
    department: row.department,
    phone: row.phone,
    email: row.email,
    isAdmin: row.is_admin,
    isManager: row.is_manager,
    employeeName: row.employee_name,
    preferredWorkDays: row.preferred_work_days,
    preferredShops: row.preferred_shops,
    shiftPreferences: row.shift_preferences,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

module.exports = { setupEmployeesAPI, getNextReferralCode };

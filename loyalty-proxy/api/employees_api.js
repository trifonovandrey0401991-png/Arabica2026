/**
 * Employees API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const EMPLOYEES_DIR = `${DATA_DIR}/employees`;
const EMPLOYEE_REGISTRATIONS_DIR = `${DATA_DIR}/employee-registrations`;
const EMPLOYEE_PHOTOS_DIR = `${DATA_DIR}/employee-photos`;

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Ensure directories exist (async IIFE)
(async () => {
  for (const dir of [EMPLOYEES_DIR, EMPLOYEE_REGISTRATIONS_DIR, EMPLOYEE_PHOTOS_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

function setupEmployeesAPI(app, uploadEmployeePhoto) {
  // ===== EMPLOYEE REGISTRATION =====

  app.post('/api/employee-registration', async (req, res) => {
    try {
      const { phone, name, shopAddress, position } = req.body;
      console.log('POST /api/employee-registration:', phone);

      const normalizedPhone = phone.replace(/[\s+]/g, '');
      const filePath = path.join(EMPLOYEE_REGISTRATIONS_DIR, `${normalizedPhone}.json`);

      const registration = {
        phone: normalizedPhone,
        name,
        shopAddress,
        position,
        status: 'pending',
        createdAt: new Date().toISOString()
      };

      await fsp.writeFile(filePath, JSON.stringify(registration, null, 2), 'utf8');
      res.json({ success: true, registration });
    } catch (error) {
      console.error('Error creating registration:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/employee-registration/:phone', async (req, res) => {
    try {
      const { phone } = req.params;
      const normalizedPhone = phone.replace(/[\s+]/g, '');
      const filePath = path.join(EMPLOYEE_REGISTRATIONS_DIR, `${normalizedPhone}.json`);

      if (await fileExists(filePath)) {
        const data = await fsp.readFile(filePath, 'utf8');
        const registration = JSON.parse(data);
        res.json({ success: true, registration });
      } else {
        res.json({ success: false, error: 'Registration not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/employee-registration/:phone/verify', async (req, res) => {
    try {
      const { phone } = req.params;
      const { approved, adminName } = req.body;

      const normalizedPhone = phone.replace(/[\s+]/g, '');
      const filePath = path.join(EMPLOYEE_REGISTRATIONS_DIR, `${normalizedPhone}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Registration not found' });
      }

      const data = await fsp.readFile(filePath, 'utf8');
      const registration = JSON.parse(data);
      registration.status = approved ? 'approved' : 'rejected';
      registration.verifiedBy = adminName;
      registration.verifiedAt = new Date().toISOString();

      await fsp.writeFile(filePath, JSON.stringify(registration, null, 2), 'utf8');
      res.json({ success: true, registration });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/employee-registrations', async (req, res) => {
    try {
      console.log('GET /api/employee-registrations');
      const registrations = [];

      if (await fileExists(EMPLOYEE_REGISTRATIONS_DIR)) {
        const files = (await fsp.readdir(EMPLOYEE_REGISTRATIONS_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(EMPLOYEE_REGISTRATIONS_DIR, file), 'utf8');
            registrations.push(JSON.parse(content));
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      registrations.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, registrations });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== EMPLOYEES =====

  app.get('/api/employees', async (req, res) => {
    try {
      console.log('GET /api/employees');
      const employees = [];

      if (await fileExists(EMPLOYEES_DIR)) {
        const files = (await fsp.readdir(EMPLOYEES_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(EMPLOYEES_DIR, file), 'utf8');
            employees.push(JSON.parse(content));
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      res.json({ success: true, employees });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/employees/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(EMPLOYEES_DIR, `${sanitizedId}.json`);

      if (await fileExists(filePath)) {
        const data = await fsp.readFile(filePath, 'utf8');
        const employee = JSON.parse(data);
        res.json({ success: true, employee });
      } else {
        res.status(404).json({ success: false, error: 'Employee not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/employees', async (req, res) => {
    try {
      const employee = req.body;
      console.log('POST /api/employees:', employee.name);

      if (!employee.id) {
        employee.id = `employee_${Date.now()}`;
      }

      const sanitizedId = employee.id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(EMPLOYEES_DIR, `${sanitizedId}.json`);

      employee.createdAt = new Date().toISOString();
      await fsp.writeFile(filePath, JSON.stringify(employee, null, 2), 'utf8');

      res.json({ success: true, employee });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/employees/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const updateData = req.body;

      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(EMPLOYEES_DIR, `${sanitizedId}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Employee not found' });
      }

      const data = await fsp.readFile(filePath, 'utf8');
      const existing = JSON.parse(data);
      const updated = { ...existing, ...updateData, id };
      updated.updatedAt = new Date().toISOString();

      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, employee: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/employees/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(EMPLOYEES_DIR, `${sanitizedId}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Employee not found' });
      }

      await fsp.unlink(filePath);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== EMPLOYEE PHOTO UPLOAD =====

  app.post('/upload-employee-photo', uploadEmployeePhoto.single('file'), (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ success: false, error: 'No file provided' });
      }

      const photoUrl = `https://arabica26.ru/employee-photos/${req.file.filename}`;
      console.log('Employee photo uploaded:', photoUrl);
      res.json({ success: true, photoUrl });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Employees API initialized');
}

module.exports = { setupEmployeesAPI };

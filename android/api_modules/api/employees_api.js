const fs = require('fs');
const path = require('path');

const EMPLOYEES_DIR = '/var/www/employees';
const EMPLOYEE_REGISTRATIONS_DIR = '/var/www/employee-registrations';
const EMPLOYEE_PHOTOS_DIR = '/var/www/employee-photos';

[EMPLOYEES_DIR, EMPLOYEE_REGISTRATIONS_DIR, EMPLOYEE_PHOTOS_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

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

      fs.writeFileSync(filePath, JSON.stringify(registration, null, 2), 'utf8');
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

      if (fs.existsSync(filePath)) {
        const registration = JSON.parse(fs.readFileSync(filePath, 'utf8'));
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

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Registration not found' });
      }

      const registration = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      registration.status = approved ? 'approved' : 'rejected';
      registration.verifiedBy = adminName;
      registration.verifiedAt = new Date().toISOString();

      fs.writeFileSync(filePath, JSON.stringify(registration, null, 2), 'utf8');
      res.json({ success: true, registration });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/employee-registrations', async (req, res) => {
    try {
      console.log('GET /api/employee-registrations');
      const registrations = [];

      if (fs.existsSync(EMPLOYEE_REGISTRATIONS_DIR)) {
        const files = fs.readdirSync(EMPLOYEE_REGISTRATIONS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(EMPLOYEE_REGISTRATIONS_DIR, file), 'utf8');
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

  app.get('/api/employees', (req, res) => {
    try {
      console.log('GET /api/employees');
      const employees = [];

      if (fs.existsSync(EMPLOYEES_DIR)) {
        const files = fs.readdirSync(EMPLOYEES_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(EMPLOYEES_DIR, file), 'utf8');
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

  app.get('/api/employees/:id', (req, res) => {
    try {
      const { id } = req.params;
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(EMPLOYEES_DIR, `${sanitizedId}.json`);

      if (fs.existsSync(filePath)) {
        const employee = JSON.parse(fs.readFileSync(filePath, 'utf8'));
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
      fs.writeFileSync(filePath, JSON.stringify(employee, null, 2), 'utf8');

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

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Employee not found' });
      }

      const existing = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const updated = { ...existing, ...updateData, id };
      updated.updatedAt = new Date().toISOString();

      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, employee: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/employees/:id', (req, res) => {
    try {
      const { id } = req.params;
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(EMPLOYEES_DIR, `${sanitizedId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Employee not found' });
      }

      fs.unlinkSync(filePath);
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

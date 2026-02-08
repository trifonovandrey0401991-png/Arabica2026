/**
 * Suppliers API
 * CRUD операции для поставщиков
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SUPPLIERS_DIR = path.join(DATA_DIR, 'suppliers');

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Initialize directory on module load
(async () => {
  try {
    await fsp.mkdir(SUPPLIERS_DIR, { recursive: true });
  } catch (e) {
    console.error('Failed to create suppliers directory:', e);
  }
})();

function setupSuppliersAPI(app) {
  app.get('/api/suppliers', async (req, res) => {
    try {
      console.log('GET /api/suppliers');
      const suppliers = [];

      let files = [];
      try {
        files = await fsp.readdir(SUPPLIERS_DIR);
      } catch {
        files = [];
      }

      const jsonFiles = files.filter(f => f.endsWith('.json'));

      for (const file of jsonFiles) {
        try {
          const filePath = path.join(SUPPLIERS_DIR, file);
          const content = await fsp.readFile(filePath, 'utf8');
          suppliers.push(JSON.parse(content));
        } catch (e) {
          console.error('Ошибка чтения файла ' + file + ':', e);
        }
      }

      suppliers.sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
      res.json({ success: true, suppliers });
    } catch (error) {
      console.error('Ошибка получения поставщиков:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/suppliers/:id', async (req, res) => {
    try {
      const id = req.params.id;
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const supplierFile = path.join(SUPPLIERS_DIR, sanitizedId + '.json');

      if (!(await fileExists(supplierFile))) {
        return res.status(404).json({ success: false, error: 'Поставщик не найден' });
      }

      const content = await fsp.readFile(supplierFile, 'utf8');
      const supplier = JSON.parse(content);
      res.json({ success: true, supplier });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/suppliers', async (req, res) => {
    try {
      console.log('POST /api/suppliers:', JSON.stringify(req.body).substring(0, 200));

      if (!req.body.name || req.body.name.trim() === '') {
        return res.status(400).json({ success: false, error: 'Наименование поставщика обязательно' });
      }
      if (!req.body.legalType || !['ООО', 'ИП'].includes(req.body.legalType)) {
        return res.status(400).json({ success: false, error: 'Тип организации должен быть "ООО" или "ИП"' });
      }
      if (!req.body.paymentType || !['Нал', 'БезНал'].includes(req.body.paymentType)) {
        return res.status(400).json({ success: false, error: 'Тип оплаты должен быть "Нал" или "БезНал"' });
      }

      await fsp.mkdir(SUPPLIERS_DIR, { recursive: true });

      const id = req.body.id || 'supplier_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const supplierFile = path.join(SUPPLIERS_DIR, sanitizedId + '.json');

      const supplier = {
        id: sanitizedId,
        name: req.body.name.trim(),
        inn: req.body.inn ? req.body.inn.trim() : null,
        legalType: req.body.legalType,
        deliveryDays: req.body.deliveryDays || [],
        phone: req.body.phone ? req.body.phone.trim() : null,
        paymentType: req.body.paymentType,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };

      await fsp.writeFile(supplierFile, JSON.stringify(supplier, null, 2), 'utf8');
      console.log('Поставщик создан:', supplierFile);
      res.json({ success: true, supplier });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/suppliers/:id', async (req, res) => {
    try {
      const id = req.params.id;
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const supplierFile = path.join(SUPPLIERS_DIR, sanitizedId + '.json');

      if (!(await fileExists(supplierFile))) {
        return res.status(404).json({ success: false, error: 'Поставщик не найден' });
      }

      if (!req.body.name || req.body.name.trim() === '') {
        return res.status(400).json({ success: false, error: 'Наименование поставщика обязательно' });
      }
      if (!req.body.legalType || !['ООО', 'ИП'].includes(req.body.legalType)) {
        return res.status(400).json({ success: false, error: 'Тип организации должен быть "ООО" или "ИП"' });
      }
      if (!req.body.paymentType || !['Нал', 'БезНал'].includes(req.body.paymentType)) {
        return res.status(400).json({ success: false, error: 'Тип оплаты должен быть "Нал" или "БезНал"' });
      }

      const oldContent = await fsp.readFile(supplierFile, 'utf8');
      const oldSupplier = JSON.parse(oldContent);

      const supplier = {
        id: sanitizedId,
        name: req.body.name.trim(),
        inn: req.body.inn ? req.body.inn.trim() : null,
        legalType: req.body.legalType,
        deliveryDays: req.body.deliveryDays || [],
        phone: req.body.phone ? req.body.phone.trim() : null,
        paymentType: req.body.paymentType,
        createdAt: oldSupplier.createdAt || new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };

      await fsp.writeFile(supplierFile, JSON.stringify(supplier, null, 2), 'utf8');
      res.json({ success: true, supplier });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/suppliers/:id', async (req, res) => {
    try {
      const id = req.params.id;
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const supplierFile = path.join(SUPPLIERS_DIR, sanitizedId + '.json');

      if (!(await fileExists(supplierFile))) {
        return res.status(404).json({ success: false, error: 'Поставщик не найден' });
      }

      await fsp.unlink(supplierFile);
      res.json({ success: true, message: 'Поставщик удален' });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Suppliers API initialized');
}

module.exports = { setupSuppliersAPI };

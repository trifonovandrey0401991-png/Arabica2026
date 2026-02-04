const fs = require('fs');
const path = require('path');

const SUPPLIERS_DIR = '/var/www/suppliers';

if (!fs.existsSync(SUPPLIERS_DIR)) {
  fs.mkdirSync(SUPPLIERS_DIR, { recursive: true });
}

function setupSuppliersAPI(app) {
  app.get('/api/suppliers', (req, res) => {
    try {
      console.log('GET /api/suppliers');
      const suppliers = [];
      const files = fs.readdirSync(SUPPLIERS_DIR).filter(f => f.endsWith('.json'));

      for (const file of files) {
        try {
          const filePath = path.join(SUPPLIERS_DIR, file);
          const content = fs.readFileSync(filePath, 'utf8');
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

  app.get('/api/suppliers/:id', (req, res) => {
    try {
      const id = req.params.id;
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const supplierFile = path.join(SUPPLIERS_DIR, sanitizedId + '.json');

      if (!fs.existsSync(supplierFile)) {
        return res.status(404).json({ success: false, error: 'Поставщик не найден' });
      }

      const supplier = JSON.parse(fs.readFileSync(supplierFile, 'utf8'));
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

      fs.writeFileSync(supplierFile, JSON.stringify(supplier, null, 2), 'utf8');
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

      if (!fs.existsSync(supplierFile)) {
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

      const oldSupplier = JSON.parse(fs.readFileSync(supplierFile, 'utf8'));

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

      fs.writeFileSync(supplierFile, JSON.stringify(supplier, null, 2), 'utf8');
      res.json({ success: true, supplier });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/suppliers/:id', (req, res) => {
    try {
      const id = req.params.id;
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const supplierFile = path.join(SUPPLIERS_DIR, sanitizedId + '.json');

      if (!fs.existsSync(supplierFile)) {
        return res.status(404).json({ success: false, error: 'Поставщик не найден' });
      }

      fs.unlinkSync(supplierFile);
      res.json({ success: true, message: 'Поставщик удален' });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Suppliers API initialized');
}

module.exports = { setupSuppliersAPI };

/**
 * Suppliers API
 * CRUD операции для поставщиков
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SUPPLIERS_DIR = `${DATA_DIR}/suppliers`;

async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

function setupSuppliersAPI(app, { getNextReferralCode } = {}) {
  // GET /api/suppliers - получить всех поставщиков
  app.get('/api/suppliers', async (req, res) => {
    try {
      console.log('GET /api/suppliers');

      const suppliers = [];

      if (!await fileExists(SUPPLIERS_DIR)) {
        await fsp.mkdir(SUPPLIERS_DIR, { recursive: true });
      }

      const files = (await fsp.readdir(SUPPLIERS_DIR)).filter(f => f.endsWith('.json'));

      for (const file of files) {
        try {
          const filePath = path.join(SUPPLIERS_DIR, file);
          const content = await fsp.readFile(filePath, 'utf8');
          const supplier = JSON.parse(content);
          suppliers.push(supplier);
        } catch (e) {
          console.error(`Ошибка чтения файла ${file}:`, e);
        }
      }

      // Сортируем по дате создания (новые первыми)
      suppliers.sort((a, b) => {
        const dateA = new Date(a.createdAt || 0);
        const dateB = new Date(b.createdAt || 0);
        return dateB - dateA;
      });

      res.json({ success: true, suppliers });
    } catch (error) {
      console.error('Ошибка получения поставщиков:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/suppliers/:id - получить поставщика по ID
  app.get('/api/suppliers/:id', async (req, res) => {
    try {
      const id = req.params.id;
      console.log('GET /api/suppliers:', id);

      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const supplierFile = path.join(SUPPLIERS_DIR, `${sanitizedId}.json`);

      if (!await fileExists(supplierFile)) {
        return res.status(404).json({
          success: false,
          error: 'Поставщик не найден'
        });
      }

      const content = await fsp.readFile(supplierFile, 'utf8');
      const supplier = JSON.parse(content);

      res.json({ success: true, supplier });
    } catch (error) {
      console.error('Ошибка получения поставщика:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/suppliers - создать нового поставщика
  app.post('/api/suppliers', async (req, res) => {
    try {
      console.log('POST /api/suppliers:', JSON.stringify(req.body).substring(0, 200));

      if (!await fileExists(SUPPLIERS_DIR)) {
        await fsp.mkdir(SUPPLIERS_DIR, { recursive: true });
      }

      // Валидация обязательных полей
      if (!req.body.name || req.body.name.trim() === '') {
        return res.status(400).json({
          success: false,
          error: 'Наименование поставщика обязательно'
        });
      }

      if (!req.body.legalType || (req.body.legalType !== 'ООО' && req.body.legalType !== 'ИП')) {
        return res.status(400).json({
          success: false,
          error: 'Тип организации должен быть "ООО" или "ИП"'
        });
      }

      if (!req.body.paymentType || (req.body.paymentType !== 'Нал' && req.body.paymentType !== 'БезНал')) {
        return res.status(400).json({
          success: false,
          error: 'Тип оплаты должен быть "Нал" или "БезНал"'
        });
      }

      // Генерируем ID если не указан
      const id = req.body.id || `supplier_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const supplierFile = path.join(SUPPLIERS_DIR, `${sanitizedId}.json`);

      const supplier = {
        id: sanitizedId,
        referralCode: req.body.referralCode || (getNextReferralCode ? await getNextReferralCode() : null),
        name: req.body.name.trim(),
        inn: req.body.inn ? req.body.inn.trim() : null,
        legalType: req.body.legalType,
        phone: req.body.phone ? req.body.phone.trim() : null,
        email: req.body.email ? req.body.email.trim() : null,
        contactPerson: req.body.contactPerson ? req.body.contactPerson.trim() : null,
        paymentType: req.body.paymentType,
        shopDeliveries: req.body.shopDeliveries || null,
        // Устаревшее поле для обратной совместимости
        deliveryDays: req.body.deliveryDays || [],
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };

      await fsp.writeFile(supplierFile, JSON.stringify(supplier, null, 2), 'utf8');
      console.log('Поставщик создан:', supplierFile);

      res.json({ success: true, supplier });
    } catch (error) {
      console.error('Ошибка создания поставщика:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/suppliers/:id - обновить поставщика
  app.put('/api/suppliers/:id', async (req, res) => {
    try {
      const id = req.params.id;
      console.log('PUT /api/suppliers:', id);

      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const supplierFile = path.join(SUPPLIERS_DIR, `${sanitizedId}.json`);

      if (!await fileExists(supplierFile)) {
        return res.status(404).json({
          success: false,
          error: 'Поставщик не найден'
        });
      }

      // Валидация обязательных полей
      if (!req.body.name || req.body.name.trim() === '') {
        return res.status(400).json({
          success: false,
          error: 'Наименование поставщика обязательно'
        });
      }

      if (!req.body.legalType || (req.body.legalType !== 'ООО' && req.body.legalType !== 'ИП')) {
        return res.status(400).json({
          success: false,
          error: 'Тип организации должен быть "ООО" или "ИП"'
        });
      }

      if (!req.body.paymentType || (req.body.paymentType !== 'Нал' && req.body.paymentType !== 'БезНал')) {
        return res.status(400).json({
          success: false,
          error: 'Тип оплаты должен быть "Нал" или "БезНал"'
        });
      }

      // Читаем существующие данные для сохранения createdAt
      const oldContent = await fsp.readFile(supplierFile, 'utf8');
      const oldSupplier = JSON.parse(oldContent);

      const supplier = {
        id: sanitizedId,
        referralCode: req.body.referralCode || oldSupplier.referralCode || (getNextReferralCode ? await getNextReferralCode() : null),
        name: req.body.name.trim(),
        inn: req.body.inn ? req.body.inn.trim() : null,
        legalType: req.body.legalType,
        phone: req.body.phone ? req.body.phone.trim() : null,
        email: req.body.email ? req.body.email.trim() : null,
        contactPerson: req.body.contactPerson ? req.body.contactPerson.trim() : null,
        paymentType: req.body.paymentType,
        shopDeliveries: req.body.shopDeliveries || null,
        deliveryDays: req.body.deliveryDays || [],
        createdAt: oldSupplier.createdAt || new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };

      await fsp.writeFile(supplierFile, JSON.stringify(supplier, null, 2), 'utf8');
      console.log('Поставщик обновлен:', supplierFile);

      res.json({ success: true, supplier });
    } catch (error) {
      console.error('Ошибка обновления поставщика:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/suppliers/:id - удалить поставщика
  app.delete('/api/suppliers/:id', async (req, res) => {
    try {
      const id = req.params.id;
      console.log('DELETE /api/suppliers:', id);

      const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const supplierFile = path.join(SUPPLIERS_DIR, `${sanitizedId}.json`);

      if (!await fileExists(supplierFile)) {
        return res.status(404).json({
          success: false,
          error: 'Поставщик не найден'
        });
      }

      await fsp.unlink(supplierFile);
      console.log('Поставщик удален:', supplierFile);

      res.json({ success: true, message: 'Поставщик удален' });
    } catch (error) {
      console.error('Ошибка удаления поставщика:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Suppliers API initialized');
}

module.exports = { setupSuppliersAPI };

/**
 * Suppliers API
 * CRUD операции для поставщиков
 *
 * Feature flag: USE_DB_SUPPLIERS=true → PostgreSQL, false → JSON files
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, sanitizeId } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SUPPLIERS_DIR = `${DATA_DIR}/suppliers`;
const USE_DB = process.env.USE_DB_SUPPLIERS === 'true';

function setupSuppliersAPI(app, { getNextReferralCode } = {}) {
  // GET /api/suppliers - получить всех поставщиков
  app.get('/api/suppliers', async (req, res) => {
    try {
      console.log('GET /api/suppliers');
      let suppliers;

      if (USE_DB) {
        const rows = await db.findAll('suppliers', { orderBy: 'created_at', orderDir: 'DESC' });
        suppliers = rows.map(dbSupplierToCamel);
      } else {
        suppliers = [];

        if (!await fileExists(SUPPLIERS_DIR)) {
          await fsp.mkdir(SUPPLIERS_DIR, { recursive: true });
        }

        const files = (await fsp.readdir(SUPPLIERS_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const filePath = path.join(SUPPLIERS_DIR, file);
            const content = await fsp.readFile(filePath, 'utf8');
            suppliers.push(JSON.parse(content));
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
      }

      res.json({ success: true, suppliers });
    } catch (error) {
      console.error('Ошибка получения поставщиков:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/suppliers/:id - получить поставщика по ID
  app.get('/api/suppliers/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('GET /api/suppliers:', id);

      let supplier;

      if (USE_DB) {
        const row = await db.findById('suppliers', id);
        if (!row) return res.status(404).json({ success: false, error: 'Поставщик не найден' });
        supplier = dbSupplierToCamel(row);
      } else {
        const supplierFile = path.join(SUPPLIERS_DIR, `${id}.json`);
        if (!await fileExists(supplierFile)) {
          return res.status(404).json({ success: false, error: 'Поставщик не найден' });
        }
        const content = await fsp.readFile(supplierFile, 'utf8');
        supplier = JSON.parse(content);
      }

      res.json({ success: true, supplier });
    } catch (error) {
      console.error('Ошибка получения поставщика:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/suppliers - создать нового поставщика
  app.post('/api/suppliers', async (req, res) => {
    try {
      if (!req.user) return res.status(401).json({ error: 'Unauthorized' });

      console.log('POST /api/suppliers:', JSON.stringify(req.body).substring(0, 200));

      // Валидация обязательных полей
      if (!req.body.name || req.body.name.trim() === '') {
        return res.status(400).json({ success: false, error: 'Наименование поставщика обязательно' });
      }

      if (!req.body.legalType || (req.body.legalType !== 'ООО' && req.body.legalType !== 'ИП')) {
        return res.status(400).json({ success: false, error: 'Тип организации должен быть "ООО" или "ИП"' });
      }

      if (!req.body.paymentType || (req.body.paymentType !== 'Нал' && req.body.paymentType !== 'БезНал')) {
        return res.status(400).json({ success: false, error: 'Тип оплаты должен быть "Нал" или "БезНал"' });
      }

      // Генерируем ID если не указан
      const rawId = req.body.id || `supplier_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      const id = sanitizeId(rawId);
      const now = new Date().toISOString();
      const referralCode = req.body.referralCode || (getNextReferralCode ? await getNextReferralCode() : null);

      let supplier;

      if (USE_DB) {
        const row = await db.insert('suppliers', {
          id,
          referral_code: referralCode,
          name: req.body.name.trim(),
          inn: req.body.inn ? req.body.inn.trim() : null,
          legal_type: req.body.legalType,
          phone: req.body.phone ? req.body.phone.trim() : null,
          email: req.body.email ? req.body.email.trim() : null,
          contact_person: req.body.contactPerson ? req.body.contactPerson.trim() : null,
          payment_type: req.body.paymentType,
          shop_deliveries: req.body.shopDeliveries || null,
          delivery_days: req.body.deliveryDays || [],
          created_at: now,
          updated_at: now
        });
        supplier = dbSupplierToCamel(row);
      } else {
        supplier = {
          id,
          referralCode,
          name: req.body.name.trim(),
          inn: req.body.inn ? req.body.inn.trim() : null,
          legalType: req.body.legalType,
          phone: req.body.phone ? req.body.phone.trim() : null,
          email: req.body.email ? req.body.email.trim() : null,
          contactPerson: req.body.contactPerson ? req.body.contactPerson.trim() : null,
          paymentType: req.body.paymentType,
          shopDeliveries: req.body.shopDeliveries || null,
          deliveryDays: req.body.deliveryDays || [],
          createdAt: now,
          updatedAt: now,
        };
        const supplierFile = path.join(SUPPLIERS_DIR, `${id}.json`);
        await writeJsonFile(supplierFile, supplier);
      }

      console.log('✅ Поставщик создан:', id);
      res.json({ success: true, supplier });
    } catch (error) {
      console.error('Ошибка создания поставщика:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/suppliers/:id - обновить поставщика
  app.put('/api/suppliers/:id', async (req, res) => {
    try {
      if (!req.user) return res.status(401).json({ error: 'Unauthorized' });

      const id = sanitizeId(req.params.id);
      console.log('PUT /api/suppliers:', id);

      // Валидация обязательных полей
      if (!req.body.name || req.body.name.trim() === '') {
        return res.status(400).json({ success: false, error: 'Наименование поставщика обязательно' });
      }

      if (!req.body.legalType || (req.body.legalType !== 'ООО' && req.body.legalType !== 'ИП')) {
        return res.status(400).json({ success: false, error: 'Тип организации должен быть "ООО" или "ИП"' });
      }

      if (!req.body.paymentType || (req.body.paymentType !== 'Нал' && req.body.paymentType !== 'БезНал')) {
        return res.status(400).json({ success: false, error: 'Тип оплаты должен быть "Нал" или "БезНал"' });
      }

      let supplier;

      if (USE_DB) {
        const existing = await db.findById('suppliers', id);
        if (!existing) return res.status(404).json({ success: false, error: 'Поставщик не найден' });

        const row = await db.updateById('suppliers', id, {
          referral_code: req.body.referralCode || existing.referral_code,
          name: req.body.name.trim(),
          inn: req.body.inn ? req.body.inn.trim() : null,
          legal_type: req.body.legalType,
          phone: req.body.phone ? req.body.phone.trim() : null,
          email: req.body.email ? req.body.email.trim() : null,
          contact_person: req.body.contactPerson ? req.body.contactPerson.trim() : null,
          payment_type: req.body.paymentType,
          shop_deliveries: req.body.shopDeliveries || null,
          delivery_days: req.body.deliveryDays || [],
          updated_at: new Date().toISOString()
        });
        supplier = dbSupplierToCamel(row);
      } else {
        const supplierFile = path.join(SUPPLIERS_DIR, `${id}.json`);
        if (!await fileExists(supplierFile)) {
          return res.status(404).json({ success: false, error: 'Поставщик не найден' });
        }

        // Читаем существующие данные для сохранения createdAt
        const oldContent = await fsp.readFile(supplierFile, 'utf8');
        const oldSupplier = JSON.parse(oldContent);

        supplier = {
          id,
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

        await writeJsonFile(supplierFile, supplier);
      }

      console.log('✅ Поставщик обновлен:', id);
      res.json({ success: true, supplier });
    } catch (error) {
      console.error('Ошибка обновления поставщика:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/suppliers/:id - удалить поставщика
  app.delete('/api/suppliers/:id', async (req, res) => {
    try {
      if (!req.user) return res.status(401).json({ error: 'Unauthorized' });

      const id = sanitizeId(req.params.id);
      console.log('DELETE /api/suppliers:', id);

      if (USE_DB) {
        const deleted = await db.deleteById('suppliers', id);
        if (!deleted) return res.status(404).json({ success: false, error: 'Поставщик не найден' });
      } else {
        const supplierFile = path.join(SUPPLIERS_DIR, `${id}.json`);
        if (!await fileExists(supplierFile)) {
          return res.status(404).json({ success: false, error: 'Поставщик не найден' });
        }
        await fsp.unlink(supplierFile);
      }

      console.log('✅ Поставщик удален:', id);
      res.json({ success: true, message: 'Поставщик удален' });
    } catch (error) {
      console.error('Ошибка удаления поставщика:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Suppliers API initialized (storage: ${USE_DB ? 'PostgreSQL' : 'JSON files'})`);
}

/**
 * Преобразование DB row (snake_case) → camelCase (для совместимости с Flutter)
 */
function dbSupplierToCamel(row) {
  return {
    id: row.id,
    referralCode: row.referral_code,
    name: row.name,
    inn: row.inn,
    legalType: row.legal_type,
    phone: row.phone,
    email: row.email,
    contactPerson: row.contact_person,
    paymentType: row.payment_type,
    shopDeliveries: row.shop_deliveries,
    deliveryDays: row.delivery_days,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

module.exports = { setupSuppliersAPI };

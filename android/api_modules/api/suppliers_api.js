const fs = require('fs');
const path = require('path');

const SUPPLIERS_DIR = '/var/www/suppliers';

if (!fs.existsSync(SUPPLIERS_DIR)) {
  fs.mkdirSync(SUPPLIERS_DIR, { recursive: true });
}

function setupSuppliersAPI(app) {
  // ===== SUPPLIERS =====

  app.get('/api/suppliers', async (req, res) => {
    try {
      console.log('GET /api/suppliers');
      const suppliers = [];

      if (fs.existsSync(SUPPLIERS_DIR)) {
        const files = fs.readdirSync(SUPPLIERS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(SUPPLIERS_DIR, file), 'utf8');
            suppliers.push(JSON.parse(content));
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      suppliers.sort((a, b) => (a.name || '').localeCompare(b.name || ''));
      res.json({ success: true, suppliers });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/suppliers', async (req, res) => {
    try {
      const supplier = req.body;
      console.log('POST /api/suppliers:', supplier.name);

      if (!supplier.id) {
        supplier.id = `supplier_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      supplier.createdAt = supplier.createdAt || new Date().toISOString();
      supplier.updatedAt = new Date().toISOString();

      const filePath = path.join(SUPPLIERS_DIR, `${supplier.id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(supplier, null, 2), 'utf8');

      res.json({ success: true, supplier });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/suppliers/:supplierId', async (req, res) => {
    try {
      const { supplierId } = req.params;
      console.log('GET /api/suppliers/:supplierId', supplierId);

      const filePath = path.join(SUPPLIERS_DIR, `${supplierId}.json`);

      if (fs.existsSync(filePath)) {
        const supplier = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        res.json({ success: true, supplier });
      } else {
        res.status(404).json({ success: false, error: 'Supplier not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/suppliers/:supplierId', async (req, res) => {
    try {
      const { supplierId } = req.params;
      const updates = req.body;
      console.log('PUT /api/suppliers/:supplierId', supplierId);

      const filePath = path.join(SUPPLIERS_DIR, `${supplierId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Supplier not found' });
      }

      const supplier = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const updated = { ...supplier, ...updates, updatedAt: new Date().toISOString() };

      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, supplier: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/suppliers/:supplierId', async (req, res) => {
    try {
      const { supplierId } = req.params;
      console.log('DELETE /api/suppliers/:supplierId', supplierId);

      const filePath = path.join(SUPPLIERS_DIR, `${supplierId}.json`);

      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Supplier not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Suppliers API initialized');
}

module.exports = { setupSuppliersAPI };

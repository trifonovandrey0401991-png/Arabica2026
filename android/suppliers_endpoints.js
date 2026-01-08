// =========== SUPPLIERS (ПОСТАВЩИКИ) ===========
const SUPPLIERS_DIR = '/var/www/suppliers';

// Инициализация директории поставщиков
if (!fs.existsSync(SUPPLIERS_DIR)) {
  fs.mkdirSync(SUPPLIERS_DIR, { recursive: true });
}

// GET /api/suppliers - получить всех поставщиков
app.get('/api/suppliers', async (req, res) => {
  try {
    console.log('GET /api/suppliers');
    const files = fs.readdirSync(SUPPLIERS_DIR);
    const suppliers = [];

    for (const file of files) {
      if (file.endsWith('.json')) {
        const data = JSON.parse(fs.readFileSync(path.join(SUPPLIERS_DIR, file), 'utf8'));
        suppliers.push(data);
      }
    }

    // Сортировка по имени
    suppliers.sort((a, b) => (a.name || '').localeCompare(b.name || ''));

    res.json({ success: true, suppliers });
  } catch (error) {
    console.error('Error getting suppliers:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/suppliers/:id - получить поставщика по ID
app.get('/api/suppliers/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('GET /api/suppliers/:id', id);

    const filePath = path.join(SUPPLIERS_DIR, id + '.json');

    if (fs.existsSync(filePath)) {
      const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      res.json({ success: true, supplier: data });
    } else {
      res.json({ success: false, error: 'Supplier not found' });
    }
  } catch (error) {
    console.error('Error getting supplier:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/suppliers - создать поставщика
app.post('/api/suppliers', async (req, res) => {
  try {
    const supplier = req.body;
    console.log('POST /api/suppliers:', JSON.stringify(supplier).substring(0, 200));

    // Добавляем ID если не указан
    if (!supplier.id) {
      supplier.id = 'supplier_' + Date.now();
    }
    supplier.createdAt = supplier.createdAt || new Date().toISOString();

    const filePath = path.join(SUPPLIERS_DIR, supplier.id + '.json');
    fs.writeFileSync(filePath, JSON.stringify(supplier, null, 2));
    console.log('Поставщик создан:', filePath);

    res.json({ success: true, supplier });
  } catch (error) {
    console.error('Error creating supplier:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/suppliers/:id - обновить поставщика
app.put('/api/suppliers/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const updateData = req.body;
    console.log('PUT /api/suppliers/:id', id);

    const filePath = path.join(SUPPLIERS_DIR, id + '.json');

    if (!fs.existsSync(filePath)) {
      return res.json({ success: false, error: 'Supplier not found' });
    }

    updateData.updatedAt = new Date().toISOString();
    const existing = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const updated = { ...existing, ...updateData };
    fs.writeFileSync(filePath, JSON.stringify(updated, null, 2));

    res.json({ success: true, supplier: updated });
  } catch (error) {
    console.error('Error updating supplier:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/suppliers/:id - удалить поставщика
app.delete('/api/suppliers/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('DELETE /api/suppliers/:id', id);

    const filePath = path.join(SUPPLIERS_DIR, id + '.json');

    if (!fs.existsSync(filePath)) {
      return res.json({ success: false, error: 'Supplier not found' });
    }

    fs.unlinkSync(filePath);
    res.json({ success: true });
  } catch (error) {
    console.error('Error deleting supplier:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});


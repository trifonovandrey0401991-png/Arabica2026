const fs = require('fs');
const path = require('path');

let code = fs.readFileSync('index.js', 'utf8');

// Найдем место для вставки - перед PENDING SHIFT HANDOVER
const insertMarker = '// =========== PENDING SHIFT HANDOVER REPORTS ===========';
const insertIndex = code.indexOf(insertMarker);

if (insertIndex === -1) {
  console.log('Insert marker not found, trying alternative...');
  // Попробуем найти другое место
  const altMarker = 'const SHIFT_HANDOVER_REPORTS_DIR';
  const altIndex = code.indexOf(altMarker);
  if (altIndex === -1) {
    console.log('Could not find insertion point');
    process.exit(1);
  }
}

// Suppliers endpoints
const suppliersEndpoints = `// =========== SUPPLIERS (ПОСТАВЩИКИ) ===========
const SUPPLIERS_FILE = '/var/www/suppliers.json';

// Инициализация файла поставщиков
function initSuppliersFile() {
  if (!fs.existsSync(SUPPLIERS_FILE)) {
    fs.writeFileSync(SUPPLIERS_FILE, JSON.stringify({ suppliers: [] }, null, 2));
  }
}
initSuppliersFile();

// GET /api/suppliers - получить всех поставщиков
app.get('/api/suppliers', async (req, res) => {
  try {
    console.log('GET /api/suppliers');
    const data = JSON.parse(fs.readFileSync(SUPPLIERS_FILE, 'utf8'));
    res.json({ success: true, suppliers: data.suppliers || [] });
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

    const data = JSON.parse(fs.readFileSync(SUPPLIERS_FILE, 'utf8'));
    const supplier = (data.suppliers || []).find(s => s.id === id);

    if (supplier) {
      res.json({ success: true, supplier });
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
    console.log('POST /api/suppliers', supplier.name);

    const data = JSON.parse(fs.readFileSync(SUPPLIERS_FILE, 'utf8'));
    if (!data.suppliers) data.suppliers = [];

    // Добавляем ID если не указан
    if (!supplier.id) {
      supplier.id = 'supplier_' + Date.now();
    }
    supplier.createdAt = supplier.createdAt || new Date().toISOString();

    data.suppliers.push(supplier);
    fs.writeFileSync(SUPPLIERS_FILE, JSON.stringify(data, null, 2));

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

    const data = JSON.parse(fs.readFileSync(SUPPLIERS_FILE, 'utf8'));
    const index = (data.suppliers || []).findIndex(s => s.id === id);

    if (index === -1) {
      return res.json({ success: false, error: 'Supplier not found' });
    }

    updateData.updatedAt = new Date().toISOString();
    data.suppliers[index] = { ...data.suppliers[index], ...updateData };
    fs.writeFileSync(SUPPLIERS_FILE, JSON.stringify(data, null, 2));

    res.json({ success: true, supplier: data.suppliers[index] });
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

    const data = JSON.parse(fs.readFileSync(SUPPLIERS_FILE, 'utf8'));
    const index = (data.suppliers || []).findIndex(s => s.id === id);

    if (index === -1) {
      return res.json({ success: false, error: 'Supplier not found' });
    }

    data.suppliers.splice(index, 1);
    fs.writeFileSync(SUPPLIERS_FILE, JSON.stringify(data, null, 2));

    res.json({ success: true });
  } catch (error) {
    console.error('Error deleting supplier:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

`;

// Вставляем перед PENDING SHIFT HANDOVER или SHIFT_HANDOVER_REPORTS
const finalIndex = code.indexOf(insertMarker);
if (finalIndex !== -1) {
  code = code.slice(0, finalIndex) + suppliersEndpoints + code.slice(finalIndex);
} else {
  const altMarker = 'const SHIFT_HANDOVER_REPORTS_DIR';
  const altIndex = code.indexOf(altMarker);
  code = code.slice(0, altIndex) + suppliersEndpoints + code.slice(altIndex);
}

fs.writeFileSync('index.js', code);
console.log('Suppliers endpoints added successfully');

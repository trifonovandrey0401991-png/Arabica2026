const fs = require('fs');
const path = require('path');

const MENU_DIR = '/var/www/menu';

if (!fs.existsSync(MENU_DIR)) {
  fs.mkdirSync(MENU_DIR, { recursive: true });
}

function setupMenuAPI(app) {
  // ===== MENU =====

  app.get('/api/menu', async (req, res) => {
    try {
      console.log('GET /api/menu');
      const { shopAddress, category } = req.query;
      const items = [];

      if (fs.existsSync(MENU_DIR)) {
        const files = fs.readdirSync(MENU_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(MENU_DIR, file), 'utf8');
            const item = JSON.parse(content);

            if (shopAddress && item.shopAddress !== shopAddress) continue;
            if (category && item.category !== category) continue;

            items.push(item);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      items.sort((a, b) => (a.order || 0) - (b.order || 0));
      res.json({ success: true, items });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/menu', async (req, res) => {
    try {
      const item = req.body;
      console.log('POST /api/menu:', item.name);

      if (!item.id) {
        item.id = `menu_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      item.createdAt = item.createdAt || new Date().toISOString();
      item.updatedAt = new Date().toISOString();

      const filePath = path.join(MENU_DIR, `${item.id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(item, null, 2), 'utf8');

      res.json({ success: true, item });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/menu/:itemId', async (req, res) => {
    try {
      const { itemId } = req.params;
      const updates = req.body;
      console.log('PUT /api/menu:', itemId);

      const filePath = path.join(MENU_DIR, `${itemId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Menu item not found' });
      }

      const item = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const updated = { ...item, ...updates, updatedAt: new Date().toISOString() };

      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, item: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/menu/:itemId', async (req, res) => {
    try {
      const { itemId } = req.params;
      console.log('DELETE /api/menu:', itemId);

      const filePath = path.join(MENU_DIR, `${itemId}.json`);

      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Menu item not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== MENU CATEGORIES =====

  app.get('/api/menu-categories', async (req, res) => {
    try {
      console.log('GET /api/menu-categories');
      const categories = new Set();

      if (fs.existsSync(MENU_DIR)) {
        const files = fs.readdirSync(MENU_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(MENU_DIR, file), 'utf8');
            const item = JSON.parse(content);
            if (item.category) {
              categories.add(item.category);
            }
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      res.json({ success: true, categories: Array.from(categories).sort() });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Menu API initialized');
}

module.exports = { setupMenuAPI };

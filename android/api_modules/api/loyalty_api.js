const fs = require('fs');
const path = require('path');

const CLIENTS_DIR = '/var/www/clients';
const LOYALTY_TRANSACTIONS_DIR = '/var/www/loyalty-transactions';

[CLIENTS_DIR, LOYALTY_TRANSACTIONS_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

function setupLoyaltyAPI(app) {
  // ===== LOYALTY POINTS =====

  app.post('/api/loyalty/add-points', async (req, res) => {
    try {
      const { phone, points, shopAddress, reason } = req.body;
      console.log('POST /api/loyalty/add-points:', phone, points);

      if (!phone || !points) {
        return res.status(400).json({ success: false, error: 'Phone and points required' });
      }

      const normalizedPhone = phone.replace(/[\s+]/g, '');
      const clientPath = path.join(CLIENTS_DIR, `${normalizedPhone}.json`);

      let client = { phone: normalizedPhone, points: 0, createdAt: new Date().toISOString() };
      if (fs.existsSync(clientPath)) {
        client = JSON.parse(fs.readFileSync(clientPath, 'utf8'));
      }

      client.points = (client.points || 0) + points;
      client.updatedAt = new Date().toISOString();

      fs.writeFileSync(clientPath, JSON.stringify(client, null, 2), 'utf8');

      // Log transaction
      const transactionId = `tx_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      const transaction = {
        id: transactionId,
        phone: normalizedPhone,
        type: 'add',
        points,
        shopAddress,
        reason,
        createdAt: new Date().toISOString()
      };

      const txPath = path.join(LOYALTY_TRANSACTIONS_DIR, `${transactionId}.json`);
      fs.writeFileSync(txPath, JSON.stringify(transaction, null, 2), 'utf8');

      res.json({ success: true, client, transaction });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/loyalty/spend-points', async (req, res) => {
    try {
      const { phone, points, shopAddress, reason } = req.body;
      console.log('POST /api/loyalty/spend-points:', phone, points);

      if (!phone || !points) {
        return res.status(400).json({ success: false, error: 'Phone and points required' });
      }

      const normalizedPhone = phone.replace(/[\s+]/g, '');
      const clientPath = path.join(CLIENTS_DIR, `${normalizedPhone}.json`);

      if (!fs.existsSync(clientPath)) {
        return res.status(404).json({ success: false, error: 'Client not found' });
      }

      const client = JSON.parse(fs.readFileSync(clientPath, 'utf8'));

      if ((client.points || 0) < points) {
        return res.status(400).json({ success: false, error: 'Insufficient points' });
      }

      client.points = (client.points || 0) - points;
      client.updatedAt = new Date().toISOString();

      fs.writeFileSync(clientPath, JSON.stringify(client, null, 2), 'utf8');

      // Log transaction
      const transactionId = `tx_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      const transaction = {
        id: transactionId,
        phone: normalizedPhone,
        type: 'spend',
        points,
        shopAddress,
        reason,
        createdAt: new Date().toISOString()
      };

      const txPath = path.join(LOYALTY_TRANSACTIONS_DIR, `${transactionId}.json`);
      fs.writeFileSync(txPath, JSON.stringify(transaction, null, 2), 'utf8');

      res.json({ success: true, client, transaction });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/loyalty/balance/:phone', async (req, res) => {
    try {
      const phone = req.params.phone.replace(/[\s+]/g, '');
      console.log('GET /api/loyalty/balance:', phone);

      const clientPath = path.join(CLIENTS_DIR, `${phone}.json`);

      if (fs.existsSync(clientPath)) {
        const client = JSON.parse(fs.readFileSync(clientPath, 'utf8'));
        res.json({ success: true, phone, points: client.points || 0 });
      } else {
        res.json({ success: true, phone, points: 0 });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/loyalty/transactions/:phone', async (req, res) => {
    try {
      const phone = req.params.phone.replace(/[\s+]/g, '');
      console.log('GET /api/loyalty/transactions:', phone);

      const transactions = [];

      if (fs.existsSync(LOYALTY_TRANSACTIONS_DIR)) {
        const files = fs.readdirSync(LOYALTY_TRANSACTIONS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(LOYALTY_TRANSACTIONS_DIR, file), 'utf8');
            const tx = JSON.parse(content);

            if (tx.phone === phone) {
              transactions.push(tx);
            }
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      transactions.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, transactions });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== QR CODE SCANNING =====

  app.post('/api/qr-scan', async (req, res) => {
    try {
      const { qr, action, shopAddress, employeeName } = req.body;
      console.log('POST /api/qr-scan:', qr, action);

      if (!qr) {
        return res.status(400).json({ success: false, error: 'QR code required' });
      }

      // Find client by QR (assuming QR is phone or client ID)
      const normalizedPhone = qr.replace(/[\s+]/g, '');
      const clientPath = path.join(CLIENTS_DIR, `${normalizedPhone}.json`);

      let client = { phone: normalizedPhone, points: 0, createdAt: new Date().toISOString() };
      if (fs.existsSync(clientPath)) {
        client = JSON.parse(fs.readFileSync(clientPath, 'utf8'));
      }

      if (action === 'addPoint') {
        client.points = (client.points || 0) + 1;
        client.lastVisit = new Date().toISOString();
        client.lastShop = shopAddress;
        client.updatedAt = new Date().toISOString();

        fs.writeFileSync(clientPath, JSON.stringify(client, null, 2), 'utf8');

        res.json({ success: true, client, message: 'Point added' });
      } else {
        res.json({ success: true, client });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Loyalty API initialized');
}

module.exports = { setupLoyaltyAPI };

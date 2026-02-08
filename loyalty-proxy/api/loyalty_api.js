/**
 * Loyalty API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const CLIENTS_DIR = `${DATA_DIR}/clients`;
const LOYALTY_TRANSACTIONS_DIR = `${DATA_DIR}/loyalty-transactions`;

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Ensure directories exist
(async () => {
  for (const dir of [CLIENTS_DIR, LOYALTY_TRANSACTIONS_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

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
      if (await fileExists(clientPath)) {
        const content = await fsp.readFile(clientPath, 'utf8');
        client = JSON.parse(content);
      }

      client.points = (client.points || 0) + points;
      client.updatedAt = new Date().toISOString();

      await fsp.writeFile(clientPath, JSON.stringify(client, null, 2), 'utf8');

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
      await fsp.writeFile(txPath, JSON.stringify(transaction, null, 2), 'utf8');

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

      if (!(await fileExists(clientPath))) {
        return res.status(404).json({ success: false, error: 'Client not found' });
      }

      const content = await fsp.readFile(clientPath, 'utf8');
      const client = JSON.parse(content);

      if ((client.points || 0) < points) {
        return res.status(400).json({ success: false, error: 'Insufficient points' });
      }

      client.points = (client.points || 0) - points;
      client.updatedAt = new Date().toISOString();

      await fsp.writeFile(clientPath, JSON.stringify(client, null, 2), 'utf8');

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
      await fsp.writeFile(txPath, JSON.stringify(transaction, null, 2), 'utf8');

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

      if (await fileExists(clientPath)) {
        const content = await fsp.readFile(clientPath, 'utf8');
        const client = JSON.parse(content);
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

      if (await fileExists(LOYALTY_TRANSACTIONS_DIR)) {
        const files = (await fsp.readdir(LOYALTY_TRANSACTIONS_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(LOYALTY_TRANSACTIONS_DIR, file), 'utf8');
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
      if (await fileExists(clientPath)) {
        const content = await fsp.readFile(clientPath, 'utf8');
        client = JSON.parse(content);
      }

      if (action === 'addPoint') {
        client.points = (client.points || 0) + 1;
        client.lastVisit = new Date().toISOString();
        client.lastShop = shopAddress;
        client.updatedAt = new Date().toISOString();

        await fsp.writeFile(clientPath, JSON.stringify(client, null, 2), 'utf8');

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

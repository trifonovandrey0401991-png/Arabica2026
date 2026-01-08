const fs = require('fs');
const path = require('path');

const WITHDRAWALS_DIR = '/var/www/withdrawals';

if (!fs.existsSync(WITHDRAWALS_DIR)) {
  fs.mkdirSync(WITHDRAWALS_DIR, { recursive: true });
}

function setupWithdrawalsAPI(app) {
  // ===== WITHDRAWALS (Выемки) =====

  app.get('/api/withdrawals', async (req, res) => {
    try {
      console.log('GET /api/withdrawals');
      const { shopAddress, type, fromDate, toDate } = req.query;
      const withdrawals = [];

      if (fs.existsSync(WITHDRAWALS_DIR)) {
        const files = fs.readdirSync(WITHDRAWALS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(WITHDRAWALS_DIR, file), 'utf8');
            const withdrawal = JSON.parse(content);

            if (shopAddress && withdrawal.shopAddress !== shopAddress) continue;
            if (type && withdrawal.type !== type) continue;
            if (fromDate && withdrawal.createdAt < fromDate) continue;
            if (toDate && withdrawal.createdAt > toDate) continue;

            withdrawals.push(withdrawal);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      withdrawals.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, withdrawals });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/withdrawals', async (req, res) => {
    try {
      const withdrawal = req.body;
      console.log('POST /api/withdrawals:', withdrawal.shopAddress, withdrawal.amount);

      if (!withdrawal.shopAddress || !withdrawal.amount) {
        return res.status(400).json({ success: false, error: 'Shop address and amount required' });
      }

      if (!withdrawal.id) {
        withdrawal.id = `wd_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      withdrawal.createdAt = withdrawal.createdAt || new Date().toISOString();

      const filePath = path.join(WITHDRAWALS_DIR, `${withdrawal.id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(withdrawal, null, 2), 'utf8');

      res.json({ success: true, withdrawal });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/withdrawals/:withdrawalId', async (req, res) => {
    try {
      const { withdrawalId } = req.params;
      console.log('GET /api/withdrawals/:withdrawalId', withdrawalId);

      const filePath = path.join(WITHDRAWALS_DIR, `${withdrawalId}.json`);

      if (fs.existsSync(filePath)) {
        const withdrawal = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        res.json({ success: true, withdrawal });
      } else {
        res.status(404).json({ success: false, error: 'Withdrawal not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/withdrawals/:withdrawalId', async (req, res) => {
    try {
      const { withdrawalId } = req.params;
      console.log('DELETE /api/withdrawals/:withdrawalId', withdrawalId);

      const filePath = path.join(WITHDRAWALS_DIR, `${withdrawalId}.json`);

      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Withdrawal not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CLEANUP OLD WITHDRAWALS (90 days retention) =====

  const cleanupOldWithdrawals = () => {
    try {
      const retentionDays = 90;
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - retentionDays);

      if (fs.existsSync(WITHDRAWALS_DIR)) {
        const files = fs.readdirSync(WITHDRAWALS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const filePath = path.join(WITHDRAWALS_DIR, file);
            const content = fs.readFileSync(filePath, 'utf8');
            const withdrawal = JSON.parse(content);

            if (new Date(withdrawal.createdAt) < cutoffDate) {
              fs.unlinkSync(filePath);
              console.log(`Deleted old withdrawal: ${file}`);
            }
          } catch (e) {
            console.error(`Error processing ${file}:`, e);
          }
        }
      }
    } catch (error) {
      console.error('Error cleaning up old withdrawals:', error);
    }
  };

  // Run cleanup daily
  setInterval(cleanupOldWithdrawals, 24 * 60 * 60 * 1000);
  // Also run once on startup
  setTimeout(cleanupOldWithdrawals, 60000);

  console.log('✅ Withdrawals API initialized');
}

module.exports = { setupWithdrawalsAPI };

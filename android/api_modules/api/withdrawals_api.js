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
      const { shopAddress, type, fromDate, toDate, includeCancelled } = req.query;
      const withdrawals = [];

      if (fs.existsSync(WITHDRAWALS_DIR)) {
        const files = fs.readdirSync(WITHDRAWALS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(WITHDRAWALS_DIR, file), 'utf8');
            const withdrawal = JSON.parse(content);

            // Фильтруем отменённые выемки, если не запрошено явно
            if (withdrawal.status === 'cancelled' && includeCancelled !== 'true') {
              continue;
            }

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

      // Валидация данных: проверка корректности сумм
      if (withdrawal.expenses && Array.isArray(withdrawal.expenses)) {
        // Проверка что все расходы имеют положительные суммы
        for (const expense of withdrawal.expenses) {
          if (!expense.amount || expense.amount < 0) {
            return res.status(400).json({
              success: false,
              error: 'All expenses must have positive amounts'
            });
          }
        }

        // Проверка что totalAmount соответствует сумме всех расходов
        const calculatedTotal = withdrawal.expenses.reduce((sum, exp) => sum + (exp.amount || 0), 0);
        const totalAmount = withdrawal.totalAmount || withdrawal.amount;

        // Используем небольшую погрешность для сравнения float чисел
        if (Math.abs(calculatedTotal - totalAmount) > 0.01) {
          return res.status(400).json({
            success: false,
            error: `Total amount mismatch: expected ${calculatedTotal}, got ${totalAmount}`
          });
        }
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

  app.patch('/api/withdrawals/:withdrawalId/cancel', async (req, res) => {
    try {
      const { withdrawalId } = req.params;
      const { cancelledBy, cancelReason } = req.body;
      console.log('PATCH /api/withdrawals/:withdrawalId/cancel', withdrawalId);

      const filePath = path.join(WITHDRAWALS_DIR, `${withdrawalId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Withdrawal not found' });
      }

      const withdrawal = JSON.parse(fs.readFileSync(filePath, 'utf8'));

      // Проверка что выемка еще не отменена
      if (withdrawal.status === 'cancelled') {
        return res.status(400).json({
          success: false,
          error: 'Withdrawal is already cancelled'
        });
      }

      // Отмена выемки
      withdrawal.status = 'cancelled';
      withdrawal.cancelledAt = new Date().toISOString();
      withdrawal.cancelledBy = cancelledBy || 'unknown';
      withdrawal.cancelReason = cancelReason || 'No reason provided';

      fs.writeFileSync(filePath, JSON.stringify(withdrawal, null, 2), 'utf8');

      res.json({ success: true, withdrawal });
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

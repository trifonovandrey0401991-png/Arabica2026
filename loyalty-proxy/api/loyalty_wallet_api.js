/**
 * Loyalty Wallet API
 * Кошелёк баллов лояльности (бесконечное накопление)
 *
 * Заменяет старую систему "9 напитков = 1 бесплатный" на:
 * - Бесконечное накопление баллов
 * - Списание за напитки или товары магазина
 * - История транзакций
 *
 * Создано: 2026-02-24
 */

const fsp = require('fs').promises;
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireAuth } = require('../utils/session_middleware');
const { getMoscowTime } = require('../utils/moscow_time');

const USE_DB = process.env.USE_DB_LOYALTY_WALLET !== 'false'; // default true
const DATA_DIR = process.env.DATA_DIR || '/var/www';
const CLIENTS_DIR = `${DATA_DIR}/clients`;
const TRANSACTIONS_DIR = `${DATA_DIR}/loyalty-transactions`;

/**
 * Read client data from DB (primary) or file (fallback)
 */
async function readClientFile(phone) {
  // Try DB first
  if (USE_DB) {
    try {
      const row = await db.findById('clients', phone, 'phone');
      if (row) {
        return {
          phone: row.phone,
          name: row.name,
          loyaltyPoints: row.loyalty_points || 0,
          totalPointsEarned: row.total_points_earned || 0,
          isWholesale: row.is_wholesale || false,
        };
      }
    } catch (e) {
      console.error('[LoyaltyWallet] DB read error:', e.message);
    }
  }
  // Fallback to JSON
  const filePath = path.join(CLIENTS_DIR, `${phone}.json`);
  if (await fileExists(filePath)) {
    return JSON.parse(await fsp.readFile(filePath, 'utf8'));
  }
  return null;
}

/**
 * Save client data to file + DB
 */
async function saveClientData(phone, clientData) {
  // JSON first
  const filePath = path.join(CLIENTS_DIR, `${phone}.json`);
  await writeJsonFile(filePath, clientData);

  // DB second
  if (USE_DB) {
    try {
      await db.query(
        `UPDATE clients SET loyalty_points = $1, total_points_earned = $2, is_wholesale = $3, updated_at = NOW() WHERE phone = $4`,
        [clientData.loyaltyPoints || 0, clientData.totalPointsEarned || 0, clientData.isWholesale || false, phone]
      );
    } catch (e) {
      console.error('[LoyaltyWallet] DB update error:', e.message);
    }
  }
}

/**
 * Save transaction to file + DB
 */
async function saveTransaction(tx) {
  // JSON file
  const txDir = path.join(TRANSACTIONS_DIR, tx.clientPhone);
  await fsp.mkdir(txDir, { recursive: true });
  const txPath = path.join(txDir, `${tx.id}.json`);
  await writeJsonFile(txPath, tx);

  // DB
  if (USE_DB) {
    try {
      await db.upsert('loyalty_transactions', {
        id: tx.id,
        client_phone: tx.clientPhone,
        type: tx.type,
        amount: tx.amount,
        balance_after: tx.balanceAfter,
        description: tx.description || null,
        source_type: tx.sourceType || null,
        source_id: tx.sourceId || null,
        employee_phone: tx.employeePhone || null,
        created_at: tx.createdAt,
      });
    } catch (e) {
      console.error('[LoyaltyWallet] DB transaction save error:', e.message);
    }
  }
}

/**
 * Add points to client wallet
 * @returns {{ loyaltyPoints, totalPointsEarned, transactionId }}
 */
async function addPoints(phone, amount, { sourceType, sourceId, employeePhone, description } = {}) {
  const client = await readClientFile(phone);
  if (!client) throw new Error(`Client ${phone} not found`);

  const oldBalance = client.loyaltyPoints || 0;
  const newBalance = oldBalance + amount;
  const totalEarned = (client.totalPointsEarned || 0) + amount;

  client.loyaltyPoints = newBalance;
  client.totalPointsEarned = totalEarned;
  client.updatedAt = new Date().toISOString();

  await saveClientData(phone, client);

  const tx = {
    id: `ltx_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
    clientPhone: phone,
    type: 'earn',
    amount: amount,
    balanceAfter: newBalance,
    description: description || `+${amount} баллов`,
    sourceType: sourceType || 'qr_scan',
    sourceId: sourceId || null,
    employeePhone: employeePhone || null,
    createdAt: new Date().toISOString(),
  };
  await saveTransaction(tx);

  return { loyaltyPoints: newBalance, totalPointsEarned: totalEarned, transactionId: tx.id };
}

/**
 * Spend points from client wallet
 * @returns {{ loyaltyPoints, transactionId }}
 */
async function spendPoints(phone, amount, { sourceType, sourceId, description } = {}) {
  const client = await readClientFile(phone);
  if (!client) throw new Error(`Client ${phone} not found`);

  const oldBalance = client.loyaltyPoints || 0;
  if (oldBalance < amount) {
    throw new Error(`Insufficient points: have ${oldBalance}, need ${amount}`);
  }

  const newBalance = oldBalance - amount;
  client.loyaltyPoints = newBalance;
  client.updatedAt = new Date().toISOString();

  await saveClientData(phone, client);

  const tx = {
    id: `ltx_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
    clientPhone: phone,
    type: 'spend',
    amount: -amount,
    balanceAfter: newBalance,
    description: description || `Списание ${amount} баллов`,
    sourceType: sourceType || 'shop_purchase',
    sourceId: sourceId || null,
    employeePhone: null,
    createdAt: new Date().toISOString(),
  };
  await saveTransaction(tx);

  return { loyaltyPoints: newBalance, transactionId: tx.id };
}

/**
 * Get client balance
 */
async function getBalance(phone) {
  const client = await readClientFile(phone);
  if (!client) return { loyaltyPoints: 0, totalPointsEarned: 0, isWholesale: false };
  return {
    loyaltyPoints: client.loyaltyPoints || 0,
    totalPointsEarned: client.totalPointsEarned || 0,
    isWholesale: client.isWholesale || false,
  };
}

// ============================================
// HTTP API
// ============================================

function setupLoyaltyWalletAPI(app) {

  // GET /api/loyalty/balance/:phone - get client's point balance
  app.get('/api/loyalty/balance/:phone', requireAuth, async (req, res) => {
    try {
      const phone = (req.params.phone || '').replace(/[^\d]/g, '');
      if (!phone) return res.status(400).json({ success: false, error: 'Phone required' });

      const balance = await getBalance(phone);
      res.json({ success: true, ...balance });
    } catch (e) {
      console.error('GET /api/loyalty/balance error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/loyalty/add-points - employee scans QR, adds points to client
  app.post('/api/loyalty/add-points', requireAuth, async (req, res) => {
    try {
      const { phone, points, employeePhone, source } = req.body;
      const normalizedPhone = (phone || '').replace(/[^\d]/g, '');
      if (!normalizedPhone) return res.status(400).json({ success: false, error: 'Phone required' });

      const amount = parseInt(points) || 0;
      if (amount <= 0) return res.status(400).json({ success: false, error: 'Points must be positive' });

      const result = await addPoints(normalizedPhone, amount, {
        sourceType: source || 'qr_scan',
        employeePhone: (employeePhone || '').replace(/[^\d]/g, ''),
        description: `+${amount} баллов (QR-сканирование)`,
      });

      console.log(`[LoyaltyWallet] +${amount} points for ${normalizedPhone}, balance: ${result.loyaltyPoints}`);
      res.json({ success: true, ...result });
    } catch (e) {
      console.error('POST /api/loyalty/add-points error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/loyalty/spend-points - deduct points from client wallet
  app.post('/api/loyalty/spend-points', requireAuth, async (req, res) => {
    try {
      const { phone, points, description, sourceType, sourceId } = req.body;
      const normalizedPhone = (phone || '').replace(/[^\d]/g, '');
      if (!normalizedPhone) return res.status(400).json({ success: false, error: 'Phone required' });

      const amount = parseInt(points) || 0;
      if (amount <= 0) return res.status(400).json({ success: false, error: 'Points must be positive' });

      const result = await spendPoints(normalizedPhone, amount, {
        sourceType: sourceType || 'shop_purchase',
        sourceId,
        description: description || `Списание ${amount} баллов`,
      });

      console.log(`[LoyaltyWallet] -${amount} points for ${normalizedPhone}, balance: ${result.loyaltyPoints}`);
      res.json({ success: true, ...result });
    } catch (e) {
      if (e.message.startsWith('Insufficient points')) {
        return res.status(400).json({ success: false, error: e.message, code: 'INSUFFICIENT_POINTS' });
      }
      console.error('POST /api/loyalty/spend-points error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // GET /api/loyalty/transactions/:phone - transaction history
  app.get('/api/loyalty/transactions/:phone', requireAuth, async (req, res) => {
    try {
      const phone = (req.params.phone || '').replace(/[^\d]/g, '');
      if (!phone) return res.status(400).json({ success: false, error: 'Phone required' });

      const page = parseInt(req.query.page) || 1;
      const limit = Math.min(parseInt(req.query.limit) || 50, 100);
      const offset = (page - 1) * limit;

      let transactions = [];
      let total = 0;

      if (USE_DB) {
        const countResult = await db.query(
          'SELECT COUNT(*) as cnt FROM loyalty_transactions WHERE client_phone = $1',
          [phone]
        );
        total = parseInt(countResult.rows[0].cnt) || 0;

        const result = await db.query(
          'SELECT * FROM loyalty_transactions WHERE client_phone = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3',
          [phone, limit, offset]
        );
        transactions = result.rows.map(row => ({
          id: row.id,
          type: row.type,
          amount: row.amount,
          balanceAfter: row.balance_after,
          description: row.description,
          sourceType: row.source_type,
          sourceId: row.source_id,
          employeePhone: row.employee_phone,
          createdAt: row.created_at,
        }));
      } else {
        // Fallback: read from files
        const txDir = path.join(TRANSACTIONS_DIR, phone);
        if (await fileExists(txDir)) {
          const files = await fsp.readdir(txDir);
          const allTx = [];
          for (const file of files) {
            if (!file.endsWith('.json')) continue;
            const data = JSON.parse(await fsp.readFile(path.join(txDir, file), 'utf8'));
            allTx.push(data);
          }
          allTx.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
          total = allTx.length;
          transactions = allTx.slice(offset, offset + limit);
        }
      }

      res.json({
        success: true,
        transactions,
        pagination: { total, page, pageSize: limit, totalPages: Math.ceil(total / limit) },
      });
    } catch (e) {
      console.error('GET /api/loyalty/transactions error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // ============================================
  // DRINK REDEMPTION (Phase 2)
  // ============================================

  // POST /api/loyalty/redeem-drink - client selects drink, generates QR token
  app.post('/api/loyalty/redeem-drink', requireAuth, async (req, res) => {
    try {
      const { clientPhone, recipeId, recipeName, pointsPrice } = req.body;
      const phone = (clientPhone || '').replace(/[^\d]/g, '');
      if (!phone) return res.status(400).json({ success: false, error: 'Phone required' });
      if (!recipeId || !pointsPrice) return res.status(400).json({ success: false, error: 'Recipe and pointsPrice required' });

      const amount = parseInt(pointsPrice);
      const balance = await getBalance(phone);
      if (balance.loyaltyPoints < amount) {
        return res.status(400).json({
          success: false,
          error: `Недостаточно баллов: ${balance.loyaltyPoints} из ${amount}`,
          code: 'INSUFFICIENT_POINTS',
          currentBalance: balance.loyaltyPoints,
          required: amount,
        });
      }

      // Create redemption record with QR token
      const redemptionId = `rdm_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
      const qrToken = `redemption_${uuidv4()}`;

      const redemption = {
        id: redemptionId,
        clientPhone: phone,
        recipeId,
        recipeName: recipeName || '',
        pointsPrice: amount,
        qrToken,
        status: 'pending', // pending -> scanned -> confirmed
        createdAt: new Date().toISOString(),
      };

      // Save to file
      const redemptionsDir = `${DATA_DIR}/loyalty-redemptions`;
      await fsp.mkdir(redemptionsDir, { recursive: true });
      await writeJsonFile(path.join(redemptionsDir, `${redemptionId}.json`), redemption);

      console.log(`[LoyaltyWallet] Drink redemption created: ${redemptionId}, ${recipeName} for ${amount} points`);
      res.json({ success: true, redemptionId, qrToken });
    } catch (e) {
      console.error('POST /api/loyalty/redeem-drink error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/loyalty/scan-redemption - employee scans redemption QR
  app.post('/api/loyalty/scan-redemption', requireAuth, async (req, res) => {
    try {
      const { qrToken } = req.body;
      if (!qrToken) return res.status(400).json({ success: false, error: 'QR token required' });

      // Find redemption by QR token
      const redemptionsDir = `${DATA_DIR}/loyalty-redemptions`;
      if (!(await fileExists(redemptionsDir))) {
        return res.status(404).json({ success: false, error: 'Redemption not found' });
      }

      const files = await fsp.readdir(redemptionsDir);
      let redemption = null;
      let redemptionPath = null;

      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        const data = JSON.parse(await fsp.readFile(path.join(redemptionsDir, file), 'utf8'));
        if (data.qrToken === qrToken) {
          redemption = data;
          redemptionPath = path.join(redemptionsDir, file);
          break;
        }
      }

      if (!redemption) {
        return res.status(404).json({ success: false, error: 'Redemption not found' });
      }

      if (redemption.status === 'confirmed') {
        return res.status(400).json({ success: false, error: 'Already confirmed', code: 'ALREADY_CONFIRMED' });
      }

      // Mark as scanned
      redemption.status = 'scanned';
      redemption.scannedAt = new Date().toISOString();
      await writeJsonFile(redemptionPath, redemption);

      res.json({
        success: true,
        redemption: {
          id: redemption.id,
          clientPhone: redemption.clientPhone,
          recipeName: redemption.recipeName,
          pointsPrice: redemption.pointsPrice,
          status: redemption.status,
        },
      });
    } catch (e) {
      console.error('POST /api/loyalty/scan-redemption error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/loyalty/confirm-redemption - employee confirms drink delivery, points deducted
  app.post('/api/loyalty/confirm-redemption', requireAuth, async (req, res) => {
    try {
      const { redemptionId, employeePhone } = req.body;
      if (!redemptionId) return res.status(400).json({ success: false, error: 'Redemption ID required' });

      const redemptionPath = path.join(`${DATA_DIR}/loyalty-redemptions`, `${redemptionId}.json`);
      if (!(await fileExists(redemptionPath))) {
        return res.status(404).json({ success: false, error: 'Redemption not found' });
      }

      const redemption = JSON.parse(await fsp.readFile(redemptionPath, 'utf8'));

      if (redemption.status === 'confirmed') {
        return res.status(400).json({ success: false, error: 'Already confirmed', code: 'ALREADY_CONFIRMED' });
      }

      // Deduct points
      const result = await spendPoints(redemption.clientPhone, redemption.pointsPrice, {
        sourceType: 'drink_redemption',
        sourceId: redemptionId,
        description: `Напиток: ${redemption.recipeName} (${redemption.pointsPrice} баллов)`,
      });

      // Update redemption status
      redemption.status = 'confirmed';
      redemption.confirmedAt = new Date().toISOString();
      redemption.confirmedBy = (employeePhone || '').replace(/[^\d]/g, '');
      await writeJsonFile(redemptionPath, redemption);

      console.log(`[LoyaltyWallet] Drink redemption confirmed: ${redemptionId}, -${redemption.pointsPrice} points`);
      res.json({ success: true, newBalance: result.loyaltyPoints });
    } catch (e) {
      if (e.message.startsWith('Insufficient points')) {
        return res.status(400).json({ success: false, error: e.message, code: 'INSUFFICIENT_POINTS' });
      }
      console.error('POST /api/loyalty/confirm-redemption error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // ============================================
  // DATA MIGRATION (one-time)
  // ============================================

  async function migrateExistingClients() {
    try {
      // Check if already migrated
      if (USE_DB) {
        const flag = await db.findById('app_settings', 'loyalty_wallet_migration_done', 'key');
        if (flag) {
          console.log('[LoyaltyWallet] Migration already done, skipping');
          return;
        }
      }

      const migrationFlagPath = `${DATA_DIR}/loyalty-wallet-migration-done.json`;
      if (await fileExists(migrationFlagPath)) {
        console.log('[LoyaltyWallet] Migration already done (file flag), skipping');
        return;
      }

      console.log('[LoyaltyWallet] Starting one-time migration of existing clients...');

      // Read loyalty promo settings for conversion factor
      let pointsRequired = 9;
      const promoPath = `${DATA_DIR}/loyalty-promo.json`;
      if (await fileExists(promoPath)) {
        const promo = JSON.parse(await fsp.readFile(promoPath, 'utf8'));
        pointsRequired = promo.pointsRequired || 9;
      }

      // Migrate clients from files
      if (await fileExists(CLIENTS_DIR)) {
        const files = await fsp.readdir(CLIENTS_DIR);
        let migrated = 0;
        for (const file of files) {
          if (!file.endsWith('.json')) continue;
          try {
            const clientPath = path.join(CLIENTS_DIR, file);
            const client = JSON.parse(await fsp.readFile(clientPath, 'utf8'));

            // Convert: current points (0-8) -> loyalty_points, freeDrinksGiven * pointsRequired -> total_earned
            if (client.loyaltyPoints === undefined) {
              client.loyaltyPoints = client.points || 0;
              client.totalPointsEarned = (client.freeDrinksGiven || 0) * pointsRequired + (client.points || 0);
              client.isWholesale = client.isWholesale || false;
              await writeJsonFile(clientPath, client);
              migrated++;
            }
          } catch (e) {
            // Skip broken files
          }
        }
        console.log(`[LoyaltyWallet] Migrated ${migrated} client files`);
      }

      // Migrate in DB
      if (USE_DB) {
        try {
          // Set loyalty_points = 0 for all clients that haven't been set yet
          // (old points were 0-8 cycle, we start fresh for wallet)
          await db.query(`
            UPDATE clients
            SET loyalty_points = 0,
                total_points_earned = COALESCE((
                  SELECT (c.data->>'freeDrinksGiven')::int * ${pointsRequired}
                  FROM clients c2
                  LEFT JOIN LATERAL (
                    SELECT data FROM jsonb_array_elements('{}'::jsonb) AS data
                  ) c ON true
                  WHERE c2.phone = clients.phone
                ), 0)
            WHERE loyalty_points = 0 AND total_points_earned = 0
          `);
        } catch (e) {
          console.log('[LoyaltyWallet] DB migration note:', e.message);
        }

        await db.upsert('app_settings', {
          key: 'loyalty_wallet_migration_done',
          data: { migratedAt: new Date().toISOString() },
          updated_at: new Date().toISOString(),
        }, 'key');
      }

      await writeJsonFile(migrationFlagPath, { migratedAt: new Date().toISOString() });
      console.log('[LoyaltyWallet] Migration complete');
    } catch (e) {
      console.error('[LoyaltyWallet] Migration error:', e.message);
    }
  }

  // Run migration on startup
  migrateExistingClients();

  console.log(`✅ Loyalty Wallet API initialized ${USE_DB ? '(DB mode)' : '(file mode)'}`);
}

module.exports = { setupLoyaltyWalletAPI, addPoints, spendPoints, getBalance };

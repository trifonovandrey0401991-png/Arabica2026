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
 * Обновлено: 2026-02-26 — DB для redemptions, пуш admin+dev, отчётные эндпоинты
 */

const fsp = require('fs').promises;
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const { fileExists, loadJsonFile } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireAuth, requireAdmin } = require('../utils/session_middleware');
const { getMoscowTime } = require('../utils/moscow_time');
const { sendPushToAdminsAndDevelopers } = require('../utils/push_service');

const USE_DB = process.env.USE_DB_LOYALTY_WALLET !== 'false'; // default true
const DATA_DIR = process.env.DATA_DIR || '/var/www';
const CLIENTS_DIR = `${DATA_DIR}/clients`;
const TRANSACTIONS_DIR = `${DATA_DIR}/loyalty-transactions`;
const REDEMPTIONS_DIR = `${DATA_DIR}/loyalty-redemptions`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;

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
 * Uses atomic SQL UPDATE to prevent race conditions on concurrent requests
 * @returns {{ loyaltyPoints, totalPointsEarned, transactionId }}
 */
async function addPoints(phone, amount, { sourceType, sourceId, employeePhone, description } = {}) {
  let newBalance, totalEarned;

  if (USE_DB) {
    // Atomic increment — prevents race condition when two requests arrive simultaneously
    const result = await db.query(
      `UPDATE clients
       SET loyalty_points = COALESCE(loyalty_points, 0) + $1,
           total_points_earned = COALESCE(total_points_earned, 0) + $1,
           updated_at = NOW()
       WHERE phone = $2
       RETURNING loyalty_points, total_points_earned`,
      [amount, phone]
    );
    if (result.rows.length === 0) throw new Error(`Client ${phone} not found`);
    newBalance = result.rows[0].loyalty_points;
    totalEarned = result.rows[0].total_points_earned;

    // Sync JSON file from DB result (backup, not source of truth)
    try {
      const filePath = path.join(CLIENTS_DIR, `${phone}.json`);
      if (await fileExists(filePath)) {
        const client = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        client.loyaltyPoints = newBalance;
        client.totalPointsEarned = totalEarned;
        client.updatedAt = new Date().toISOString();
        await writeJsonFile(filePath, client);
      }
    } catch (fileErr) {
      console.error('[LoyaltyWallet] JSON sync error in addPoints:', fileErr.message);
    }
  } else {
    // File-only mode (fallback) — no DB, use old read-modify-write
    const client = await readClientFile(phone);
    if (!client) throw new Error(`Client ${phone} not found`);

    newBalance = (client.loyaltyPoints || 0) + amount;
    totalEarned = (client.totalPointsEarned || 0) + amount;

    client.loyaltyPoints = newBalance;
    client.totalPointsEarned = totalEarned;
    client.updatedAt = new Date().toISOString();

    await saveClientData(phone, client);
  }

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
 * Uses atomic SQL UPDATE with balance check to prevent double-spending
 * @returns {{ loyaltyPoints, transactionId }}
 */
async function spendPoints(phone, amount, { sourceType, sourceId, description } = {}) {
  let newBalance;

  if (USE_DB) {
    // Atomic decrement with balance check — prevents double-spending race condition
    // UPDATE returns 0 rows if balance < amount, so no points are deducted
    const result = await db.query(
      `UPDATE clients
       SET loyalty_points = loyalty_points - $1,
           updated_at = NOW()
       WHERE phone = $2 AND COALESCE(loyalty_points, 0) >= $1
       RETURNING loyalty_points`,
      [amount, phone]
    );
    if (result.rows.length === 0) {
      // Either client not found or insufficient balance — check which
      const client = await db.findById('clients', phone, 'phone');
      if (!client) throw new Error(`Client ${phone} not found`);
      throw new Error(`Insufficient points: have ${client.loyalty_points || 0}, need ${amount}`);
    }
    newBalance = result.rows[0].loyalty_points;

    // Sync JSON file from DB result (backup, not source of truth)
    try {
      const filePath = path.join(CLIENTS_DIR, `${phone}.json`);
      if (await fileExists(filePath)) {
        const client = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        client.loyaltyPoints = newBalance;
        client.updatedAt = new Date().toISOString();
        await writeJsonFile(filePath, client);
      }
    } catch (fileErr) {
      console.error('[LoyaltyWallet] JSON sync error in spendPoints:', fileErr.message);
    }
  } else {
    // File-only mode (fallback) — no DB, use old read-modify-write
    const client = await readClientFile(phone);
    if (!client) throw new Error(`Client ${phone} not found`);

    const oldBalance = client.loyaltyPoints || 0;
    if (oldBalance < amount) {
      throw new Error(`Insufficient points: have ${oldBalance}, need ${amount}`);
    }

    newBalance = oldBalance - amount;
    client.loyaltyPoints = newBalance;
    client.updatedAt = new Date().toISOString();

    await saveClientData(phone, client);
  }

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

/**
 * Save redemption to file + DB
 */
async function saveRedemption(redemption) {
  // JSON first
  await fsp.mkdir(REDEMPTIONS_DIR, { recursive: true });
  await writeJsonFile(path.join(REDEMPTIONS_DIR, `${redemption.id}.json`), redemption);

  // DB second
  if (USE_DB) {
    try {
      await db.upsert('loyalty_redemptions', {
        id: redemption.id,
        client_phone: redemption.clientPhone,
        client_name: redemption.clientName || null,
        recipe_id: redemption.recipeId || null,
        recipe_name: redemption.recipeName || null,
        points_price: redemption.pointsPrice,
        qr_token: redemption.qrToken,
        status: redemption.status,
        shop_address: redemption.shopAddress || null,
        created_at: redemption.createdAt,
        scanned_at: redemption.scannedAt || null,
        confirmed_at: redemption.confirmedAt || null,
        confirmed_by: redemption.confirmedBy || null,
      });
    } catch (e) {
      console.error('[LoyaltyWallet] DB redemption save error:', e.message);
    }
  }
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
  app.post('/api/loyalty/add-points', requireAdmin, async (req, res) => {
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
  app.post('/api/loyalty/spend-points', requireAdmin, async (req, res) => {
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
  // DRINK REDEMPTION
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

      // Look up client name
      let clientName = '';
      try {
        const client = await readClientFile(phone);
        clientName = client?.name || '';
      } catch (e) {
        // Non-critical, proceed without name
      }

      // Create redemption record with QR token
      const redemptionId = `rdm_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
      const qrToken = `redemption_${uuidv4()}`;

      const redemption = {
        id: redemptionId,
        clientPhone: phone,
        clientName,
        recipeId,
        recipeName: recipeName || '',
        pointsPrice: amount,
        qrToken,
        status: 'pending', // pending -> scanned -> confirmed
        shopAddress: null,
        createdAt: new Date().toISOString(),
      };

      await saveRedemption(redemption);

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

      let redemption = null;

      // DB-first lookup
      if (USE_DB) {
        try {
          const result = await db.query(
            'SELECT * FROM loyalty_redemptions WHERE qr_token = $1',
            [qrToken]
          );
          if (result.rows.length > 0) {
            const row = result.rows[0];
            redemption = {
              id: row.id,
              clientPhone: row.client_phone,
              clientName: row.client_name || '',
              recipeId: row.recipe_id,
              recipeName: row.recipe_name,
              pointsPrice: row.points_price,
              qrToken: row.qr_token,
              status: row.status,
              shopAddress: row.shop_address,
              createdAt: row.created_at,
              confirmedBy: row.confirmed_by,
            };
          }
        } catch (e) {
          console.error('[LoyaltyWallet] DB scan lookup error:', e.message);
        }
      }

      // File fallback if not found in DB
      if (!redemption) {
        if (!(await fileExists(REDEMPTIONS_DIR))) {
          return res.status(404).json({ success: false, error: 'Redemption not found' });
        }
        const files = await fsp.readdir(REDEMPTIONS_DIR);
        for (const file of files) {
          if (!file.endsWith('.json')) continue;
          const data = await loadJsonFile(path.join(REDEMPTIONS_DIR, file), null);
          if (data && data.qrToken === qrToken) {
            redemption = data;
            break;
          }
        }
      }

      if (!redemption) {
        return res.status(404).json({ success: false, error: 'Redemption not found' });
      }

      if (redemption.status === 'confirmed') {
        return res.status(400).json({ success: false, error: 'Already confirmed', code: 'ALREADY_CONFIRMED' });
      }

      // Mark as scanned
      const scannedAt = new Date().toISOString();

      // Update file
      const redemptionPath = path.join(REDEMPTIONS_DIR, `${redemption.id}.json`);
      if (await fileExists(redemptionPath)) {
        const fileData = await loadJsonFile(redemptionPath, redemption);
        fileData.status = 'scanned';
        fileData.scannedAt = scannedAt;
        await writeJsonFile(redemptionPath, fileData);
      }

      // Update DB
      if (USE_DB) {
        try {
          await db.query(
            'UPDATE loyalty_redemptions SET status = $1, scanned_at = $2 WHERE id = $3',
            ['scanned', scannedAt, redemption.id]
          );
        } catch (e) {
          console.error('[LoyaltyWallet] DB scan update error:', e.message);
        }
      }

      res.json({
        success: true,
        redemption: {
          id: redemption.id,
          clientPhone: redemption.clientPhone,
          clientName: redemption.clientName || '',
          recipeName: redemption.recipeName,
          pointsPrice: redemption.pointsPrice,
          status: 'scanned',
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
      const { redemptionId, employeePhone, shopAddress } = req.body;
      if (!redemptionId) return res.status(400).json({ success: false, error: 'Redemption ID required' });

      const normalizedEmployeePhone = (employeePhone || '').replace(/[^\d]/g, '');

      // Read redemption — try DB first, then file
      let redemption = null;

      if (USE_DB) {
        try {
          const result = await db.query(
            'SELECT * FROM loyalty_redemptions WHERE id = $1',
            [redemptionId]
          );
          if (result.rows.length > 0) {
            const row = result.rows[0];
            redemption = {
              id: row.id,
              clientPhone: row.client_phone,
              clientName: row.client_name || '',
              recipeId: row.recipe_id,
              recipeName: row.recipe_name,
              pointsPrice: row.points_price,
              qrToken: row.qr_token,
              status: row.status,
            };
          }
        } catch (e) {
          console.error('[LoyaltyWallet] DB confirm read error:', e.message);
        }
      }

      if (!redemption) {
        const redemptionPath = path.join(REDEMPTIONS_DIR, `${redemptionId}.json`);
        if (!(await fileExists(redemptionPath))) {
          return res.status(404).json({ success: false, error: 'Redemption not found' });
        }
        redemption = await loadJsonFile(redemptionPath, null);
      }

      if (!redemption) {
        return res.status(404).json({ success: false, error: 'Redemption not found' });
      }

      if (redemption.status === 'confirmed') {
        return res.status(400).json({ success: false, error: 'Already confirmed', code: 'ALREADY_CONFIRMED' });
      }

      // Determine shop address: use provided value or look up from employee file
      let finalShopAddress = (shopAddress || '').trim() || null;
      if (!finalShopAddress && normalizedEmployeePhone) {
        try {
          const empPath = path.join(EMPLOYEES_DIR, `${normalizedEmployeePhone}.json`);
          if (await fileExists(empPath)) {
            const emp = await loadJsonFile(empPath, null);
            finalShopAddress = emp?.shopAddress || null;
          }
        } catch (e) {
          // Non-critical
        }
      }

      // Deduct points
      const result = await spendPoints(redemption.clientPhone, redemption.pointsPrice, {
        sourceType: 'drink_redemption',
        sourceId: redemptionId,
        description: `Напиток: ${redemption.recipeName} (${redemption.pointsPrice} баллов)`,
      });

      const confirmedAt = new Date().toISOString();

      // Update file
      const redemptionFilePath = path.join(REDEMPTIONS_DIR, `${redemptionId}.json`);
      if (await fileExists(redemptionFilePath)) {
        const fileData = await loadJsonFile(redemptionFilePath, {});
        fileData.status = 'confirmed';
        fileData.confirmedAt = confirmedAt;
        fileData.confirmedBy = normalizedEmployeePhone;
        fileData.shopAddress = finalShopAddress;
        await writeJsonFile(redemptionFilePath, fileData);
      }

      // Update DB — upsert so file-only records (created before server update) also get saved
      if (USE_DB) {
        try {
          await db.upsert('loyalty_redemptions', {
            id: redemptionId,
            client_phone: redemption.clientPhone,
            client_name: redemption.clientName || null,
            recipe_id: redemption.recipeId || null,
            recipe_name: redemption.recipeName || null,
            points_price: redemption.pointsPrice,
            qr_token: redemption.qrToken || `redemption_legacy_${redemptionId}`,
            status: 'confirmed',
            shop_address: finalShopAddress,
            confirmed_at: confirmedAt,
            confirmed_by: normalizedEmployeePhone,
          });
        } catch (e) {
          console.error('[LoyaltyWallet] DB redemption confirm error:', e.message);
        }
      }

      console.log(`[LoyaltyWallet] Drink confirmed: ${redemptionId}, -${redemption.pointsPrice} points, shop: ${finalShopAddress}`);

      // Push to admins and developers
      try {
        const clientLabel = redemption.clientName || redemption.clientPhone;
        await sendPushToAdminsAndDevelopers(
          'Бонус выдан 🎁',
          `${clientLabel}: ${redemption.recipeName} (${redemption.pointsPrice} баллов)`,
          { type: 'redemption_confirmed', redemptionId },
          'prizes_channel'
        );
      } catch (pushErr) {
        console.error('[LoyaltyWallet] Push error:', pushErr.message);
      }

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
  // REPORTS
  // ============================================

  // GET /api/loyalty/redemptions - all confirmed, with optional period and shops filter
  app.get('/api/loyalty/redemptions', requireAdmin, async (req, res) => {
    try {
      const { period, shops } = req.query;
      const shopList = shops ? shops.split(',').map(s => s.trim()).filter(Boolean) : null;

      let redemptions = [];

      if (USE_DB) {
        let query = 'SELECT * FROM loyalty_redemptions WHERE status = $1';
        const params = ['confirmed'];

        if (period === 'week') {
          query += ` AND confirmed_at >= NOW() - INTERVAL '7 days'`;
        } else if (period === 'month') {
          query += ` AND confirmed_at >= NOW() - INTERVAL '30 days'`;
        }

        if (shopList && shopList.length > 0) {
          query += ` AND shop_address = ANY($${params.length + 1})`;
          params.push(shopList);
        }

        query += ' ORDER BY confirmed_at DESC LIMIT 500';

        const result = await db.query(query, params);
        redemptions = result.rows.map(row => ({
          id: row.id,
          clientPhone: row.client_phone,
          clientName: row.client_name || '',
          recipeId: row.recipe_id,
          recipeName: row.recipe_name || '',
          pointsPrice: row.points_price,
          shopAddress: row.shop_address,
          confirmedAt: row.confirmed_at,
          confirmedBy: row.confirmed_by,
        }));
      } else {
        // File fallback
        if (await fileExists(REDEMPTIONS_DIR)) {
          const files = await fsp.readdir(REDEMPTIONS_DIR);
          const cutoffMs = period === 'week'
            ? Date.now() - 7 * 24 * 3600 * 1000
            : period === 'month'
            ? Date.now() - 30 * 24 * 3600 * 1000
            : null;

          for (const file of files) {
            if (!file.endsWith('.json')) continue;
            try {
              const data = await loadJsonFile(path.join(REDEMPTIONS_DIR, file), null);
              if (!data || data.status !== 'confirmed') continue;
              if (cutoffMs && data.confirmedAt && new Date(data.confirmedAt).getTime() < cutoffMs) continue;
              if (shopList && shopList.length > 0 && !shopList.includes(data.shopAddress)) continue;
              redemptions.push({
                id: data.id,
                clientPhone: data.clientPhone,
                clientName: data.clientName || '',
                recipeId: data.recipeId,
                recipeName: data.recipeName || '',
                pointsPrice: data.pointsPrice,
                shopAddress: data.shopAddress,
                confirmedAt: data.confirmedAt,
                confirmedBy: data.confirmedBy,
              });
            } catch (e) {
              // Skip broken files
            }
          }
          redemptions.sort((a, b) => new Date(b.confirmedAt) - new Date(a.confirmedAt));
          redemptions = redemptions.slice(0, 500);
        }
      }

      res.json({ success: true, redemptions });
    } catch (e) {
      console.error('GET /api/loyalty/redemptions error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // GET /api/loyalty/redemptions/by-client - summary per client
  app.get('/api/loyalty/redemptions/by-client', requireAdmin, async (req, res) => {
    try {
      const { shops } = req.query;
      const shopList = shops ? shops.split(',').map(s => s.trim()).filter(Boolean) : null;

      let clients = [];

      if (USE_DB) {
        let query = `
          SELECT client_phone, client_name, COUNT(*) AS cnt, SUM(points_price) AS total_points
          FROM loyalty_redemptions
          WHERE status = 'confirmed'
        `;
        const params = [];

        if (shopList && shopList.length > 0) {
          query += ` AND shop_address = ANY($1)`;
          params.push(shopList);
        }

        query += ' GROUP BY client_phone, client_name ORDER BY cnt DESC LIMIT 200';

        const result = await db.query(query, params);
        clients = result.rows.map(row => ({
          clientPhone: row.client_phone,
          clientName: row.client_name || '',
          count: parseInt(row.cnt),
          totalPoints: parseInt(row.total_points) || 0,
        }));
      } else {
        // File fallback — aggregate
        if (await fileExists(REDEMPTIONS_DIR)) {
          const files = await fsp.readdir(REDEMPTIONS_DIR);
          const aggregated = {};
          for (const file of files) {
            if (!file.endsWith('.json')) continue;
            try {
              const data = await loadJsonFile(path.join(REDEMPTIONS_DIR, file), null);
              if (!data || data.status !== 'confirmed') continue;
              if (shopList && shopList.length > 0 && !shopList.includes(data.shopAddress)) continue;
              const key = data.clientPhone;
              if (!aggregated[key]) {
                aggregated[key] = {
                  clientPhone: data.clientPhone,
                  clientName: data.clientName || '',
                  count: 0,
                  totalPoints: 0,
                };
              }
              aggregated[key].count++;
              aggregated[key].totalPoints += data.pointsPrice || 0;
            } catch (e) {
              // Skip
            }
          }
          clients = Object.values(aggregated).sort((a, b) => b.count - a.count).slice(0, 200);
        }
      }

      res.json({ success: true, clients });
    } catch (e) {
      console.error('GET /api/loyalty/redemptions/by-client error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // GET /api/loyalty/redemptions/history/:phone - history for one client
  app.get('/api/loyalty/redemptions/history/:phone', requireAdmin, async (req, res) => {
    try {
      const phone = (req.params.phone || '').replace(/[^\d]/g, '');
      if (!phone) return res.status(400).json({ success: false, error: 'Phone required' });

      let redemptions = [];

      if (USE_DB) {
        const result = await db.query(
          `SELECT * FROM loyalty_redemptions WHERE client_phone = $1 AND status = 'confirmed' ORDER BY confirmed_at DESC LIMIT 100`,
          [phone]
        );
        redemptions = result.rows.map(row => ({
          id: row.id,
          recipeId: row.recipe_id,
          recipeName: row.recipe_name || '',
          pointsPrice: row.points_price,
          shopAddress: row.shop_address,
          confirmedAt: row.confirmed_at,
          confirmedBy: row.confirmed_by,
        }));
      } else {
        // File fallback
        if (await fileExists(REDEMPTIONS_DIR)) {
          const files = await fsp.readdir(REDEMPTIONS_DIR);
          for (const file of files) {
            if (!file.endsWith('.json')) continue;
            try {
              const data = await loadJsonFile(path.join(REDEMPTIONS_DIR, file), null);
              if (!data || data.clientPhone !== phone || data.status !== 'confirmed') continue;
              redemptions.push({
                id: data.id,
                recipeId: data.recipeId,
                recipeName: data.recipeName || '',
                pointsPrice: data.pointsPrice,
                shopAddress: data.shopAddress,
                confirmedAt: data.confirmedAt,
                confirmedBy: data.confirmedBy,
              });
            } catch (e) {
              // Skip
            }
          }
          redemptions.sort((a, b) => new Date(b.confirmedAt) - new Date(a.confirmedAt));
          redemptions = redemptions.slice(0, 100);
        }
      }

      res.json({ success: true, redemptions });
    } catch (e) {
      console.error('GET /api/loyalty/redemptions/history error:', e.message);
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

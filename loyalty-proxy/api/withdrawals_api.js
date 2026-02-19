/**
 * Withdrawals API
 * Выемки из кассы (ООО/ИП) с уведомлениями и балансом главной кассы
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, sanitizeId, maskPhone } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const db = require('../utils/db');
const { requireAuth } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_WITHDRAWALS === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const WITHDRAWALS_DIR = `${DATA_DIR}/withdrawals`;
const MAIN_CASH_DIR = `${DATA_DIR}/main_cash`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;
const FCM_TOKENS_DIR = `${DATA_DIR}/fcm-tokens`;

const pushService = require('../utils/push_service');

// Firebase Admin SDK (legacy, kept for backward compat)
let admin = null;
try {
  const firebaseConfig = require('../firebase-admin-config');
  admin = firebaseConfig.admin;
} catch (e) {
  console.warn('⚠️ Withdrawals API: Firebase not available, push notifications disabled');
}

// Создаем директории, если их нет
(async () => {
  if (!await fileExists(WITHDRAWALS_DIR)) {
    await fsp.mkdir(WITHDRAWALS_DIR, { recursive: true, mode: 0o755 });
  }
  if (!await fileExists(MAIN_CASH_DIR)) {
    await fsp.mkdir(MAIN_CASH_DIR, { recursive: true, mode: 0o755 });
  }
})();

// Вспомогательная функция для загрузки всех сотрудников (для уведомлений)
async function loadAllEmployeesForWithdrawals() {
  if (!await fileExists(EMPLOYEES_DIR)) {
    return [];
  }

  const files = await fsp.readdir(EMPLOYEES_DIR);
  const employees = [];

  for (const file of files) {
    if (file.endsWith('.json')) {
      try {
        const filePath = path.join(EMPLOYEES_DIR, file);
        const data = await fsp.readFile(filePath, 'utf8');
        const employee = JSON.parse(data);
        employees.push(employee);
      } catch (err) {
        console.error(`Ошибка чтения сотрудника ${file}:`, err);
      }
    }
  }

  return employees;
}

// Получить FCM токен по телефону
async function getFCMTokenByPhoneForWithdrawals(phone) {
  try {
    const normalizedPhone = phone.replace(/[^\d]/g, "");
    const tokenFile = path.join(FCM_TOKENS_DIR, `${normalizedPhone}.json`);

    if (!await fileExists(tokenFile)) {
      return null;
    }

    const tokenData = JSON.parse(await fsp.readFile(tokenFile, "utf8"));
    return tokenData.token || null;
  } catch (err) {
    console.error(`Ошибка получения токена для ${maskPhone(phone)}:`, err.message);
    return null;
  }
}

// Получить FCM токены пользователей для уведомлений о выемках
async function getFCMTokensForWithdrawalNotifications(phones) {
  if (!await fileExists(FCM_TOKENS_DIR)) {
    console.log("⚠️  Папка FCM токенов не существует");
    return [];
  }

  const tokens = [];
  for (const phone of phones) {
    const token = await getFCMTokenByPhoneForWithdrawals(phone);
    if (token) {
      tokens.push(token);
    }
  }

  return tokens;
}

// Отправить push-уведомления о выемке всем админам
async function sendWithdrawalNotifications(withdrawal) {
  try {
    const title = `Выемка: ${withdrawal.shopAddress}`;
    const body = `${withdrawal.employeeName} сделал выемку на ${withdrawal.totalAmount.toFixed(0)} руб (${withdrawal.type.toUpperCase()})`;
    await pushService.sendPushToAllAdmins(title, body, {
      type: 'withdrawal',
      withdrawalId: withdrawal.id,
      shopAddress: withdrawal.shopAddress,
    }, 'withdrawals_channel');
  } catch (err) {
    console.error('Ошибка отправки push-уведомлений о выемке:', err.message);
  }
}

// Отправить push-уведомления о подтверждении выемки
async function sendWithdrawalConfirmationNotifications(withdrawal) {
  try {
    const title = `Выемка подтверждена: ${withdrawal.shopAddress}`;
    const body = `Выемка от ${withdrawal.employeeName} на ${withdrawal.totalAmount.toFixed(0)} руб (${withdrawal.type.toUpperCase()}) подтверждена`;
    await pushService.sendPushToAllAdmins(title, body, {
      type: 'withdrawal_confirmed',
      withdrawalId: withdrawal.id,
      shopAddress: withdrawal.shopAddress,
    }, 'withdrawals_channel');
  } catch (err) {
    console.error('Ошибка отправки push-уведомлений о подтверждении:', err.message);
  }
}

// Обновить баланс главной кассы после выемки
async function updateMainCashBalance(shopAddress, type, amount) {
  try {
    // Нормализовать адрес для имени файла
    const fileName = shopAddress.replace(/[^a-zA-Z0-9а-яА-Я]/g, '_') + '.json';
    const filePath = path.join(MAIN_CASH_DIR, fileName);

    let balance = {
      shopAddress: shopAddress,
      oooBalance: 0,
      ipBalance: 0,
      totalBalance: 0,
      lastUpdated: new Date().toISOString(),
    };

    // Загрузить существующий баланс если есть
    if (await fileExists(filePath)) {
      const data = await fsp.readFile(filePath, 'utf8');
      balance = JSON.parse(data);
    }

    // Уменьшить баланс по типу
    if (type === 'ooo') {
      balance.oooBalance -= amount;
    } else if (type === 'ip') {
      balance.ipBalance -= amount;
    }

    // Пересчитать общий баланс
    balance.totalBalance = balance.oooBalance + balance.ipBalance;
    balance.lastUpdated = new Date().toISOString();

    // Сохранить обновлённый баланс
    if (!await fileExists(MAIN_CASH_DIR)) {
      await fsp.mkdir(MAIN_CASH_DIR, { recursive: true, mode: 0o755 });
    }
    await writeJsonFile(filePath, balance);

    console.log(`Обновлён баланс ${shopAddress}: ${type}Balance -= ${amount}`);
  } catch (err) {
    console.error('Ошибка обновления баланса главной кассы:', err);
    throw err;
  }
}

function setupWithdrawalsAPI(app) {
  // GET /api/withdrawals - получить все выемки с опциональными фильтрами
  app.get('/api/withdrawals', requireAuth, async (req, res) => {
    try {
      const { shopAddress, type, fromDate, toDate } = req.query;

      if (USE_DB) {
        const rows = await db.findAll('withdrawals', { orderBy: 'created_at', orderDir: 'DESC' });
        let withdrawals = rows.map(r => r.data);
        if (shopAddress) withdrawals = withdrawals.filter(w => w.shopAddress === shopAddress);
        if (type) withdrawals = withdrawals.filter(w => w.type === type);
        if (fromDate) { const from = new Date(fromDate); withdrawals = withdrawals.filter(w => new Date(w.createdAt) >= from); }
        if (toDate) { const to = new Date(toDate); withdrawals = withdrawals.filter(w => new Date(w.createdAt) <= to); }
        if (isPaginationRequested(req.query)) {
          return res.json(createPaginatedResponse(withdrawals, req.query, 'withdrawals'));
        }
        return res.json({ success: true, withdrawals });
      }

      const files = await fsp.readdir(WITHDRAWALS_DIR);
      let withdrawals = [];

      for (const file of files) {
        if (file.endsWith('.json')) {
          try {
            const filePath = path.join(WITHDRAWALS_DIR, file);
            const data = await fsp.readFile(filePath, 'utf8');
            const withdrawal = JSON.parse(data);
            withdrawals.push(withdrawal);
          } catch (err) {
            console.error(`Ошибка чтения выемки ${file}:`, err);
          }
        }
      }

      // Применить фильтры
      if (shopAddress) {
        withdrawals = withdrawals.filter(w => w.shopAddress === shopAddress);
      }

      if (type) {
        withdrawals = withdrawals.filter(w => w.type === type);
      }

      if (fromDate) {
        const from = new Date(fromDate);
        withdrawals = withdrawals.filter(w => new Date(w.createdAt) >= from);
      }

      if (toDate) {
        const to = new Date(toDate);
        withdrawals = withdrawals.filter(w => new Date(w.createdAt) <= to);
      }

      // Сортировать по дате (новые первые)
      withdrawals.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      if (isPaginationRequested(req.query)) {
        return res.json(createPaginatedResponse(withdrawals, req.query, 'withdrawals'));
      }
      res.json({ success: true, withdrawals });
    } catch (err) {
      console.error('Ошибка получения выемок:', err);
      res.status(500).json({ success: false, error: 'Ошибка получения выемок' });
    }
  });

  // POST /api/withdrawals - создать новую выемку
  app.post('/api/withdrawals', requireAuth, async (req, res) => {
    try {
      const {
        shopAddress,
        employeeName,
        employeeId,
        type,
        expenses,
        adminName,
        category,          // 'withdrawal' | 'deposit' | 'transfer'
        transferDirection, // 'ooo_to_ip' | 'ip_to_ooo' (для переносов)
      } = req.body;

      // Валидация - для переносов employeeId может быть пустым
      const effectiveCategory = category || 'withdrawal';
      const isTransfer = effectiveCategory === 'transfer';

      if (!shopAddress || !employeeName || !type || !expenses || !Array.isArray(expenses)) {
        return res.status(400).json({ error: 'Не все обязательные поля заполнены' });
      }

      // employeeId обязателен только для выемок и внесений (не для переносов)
      if (!isTransfer && !employeeId) {
        return res.status(400).json({ error: 'ID сотрудника обязателен' });
      }

      if (type !== 'ooo' && type !== 'ip') {
        return res.status(400).json({ error: 'Тип должен быть ooo или ip' });
      }

      if (expenses.length === 0) {
        return res.status(400).json({ error: 'Добавьте хотя бы один расход' });
      }

      // Валидация расходов
      for (const expense of expenses) {
        if (!expense.amount || expense.amount <= 0) {
          return res.status(400).json({ error: 'Все суммы расходов должны быть положительными' });
        }

        if (!expense.supplierId && !expense.comment) {
          return res.status(400).json({ error: 'Для "Другого расхода" комментарий обязателен' });
        }
      }

      // Вычислить общую сумму
      const totalAmount = expenses.reduce((sum, expense) => sum + expense.amount, 0);

      // Создать выемку
      const withdrawal = {
        id: `withdrawal_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        shopAddress,
        employeeName,
        employeeId: employeeId || '',
        type,
        totalAmount,
        expenses,
        adminName: adminName || null,
        createdAt: new Date().toISOString(),
        confirmed: false,
        category: effectiveCategory,
        ...(transferDirection && { transferDirection }),
      };

      // Сохранить в файл
      const filePath = path.join(WITHDRAWALS_DIR, `${withdrawal.id}.json`);
      await writeJsonFile(filePath, withdrawal);

      if (USE_DB) {
        try { await db.upsert('withdrawals', { id: withdrawal.id, data: withdrawal, created_at: withdrawal.createdAt }); }
        catch (dbErr) { console.error('DB save withdrawal error:', dbErr.message); }
      }

      // Обновить баланс главной кассы
      await updateMainCashBalance(shopAddress, type, totalAmount);

      // Отправить push-уведомления админам
      await sendWithdrawalNotifications(withdrawal);

      res.json({ success: true, withdrawal });
    } catch (err) {
      console.error('Ошибка создания выемки:', err);
      res.status(500).json({ success: false, error: 'Ошибка создания выемки' });
    }
  });

  // PATCH /api/withdrawals/:id/confirm - подтвердить выемку
  app.patch('/api/withdrawals/:id/confirm', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('PATCH /api/withdrawals/:id/confirm', id);
      const filePath = path.join(WITHDRAWALS_DIR, `${id}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({ success: false, error: 'Выемка не найдена' });
      }

      // Прочитать выемку
      const withdrawal = JSON.parse(await fsp.readFile(filePath, 'utf8'));

      // Обновить статус
      withdrawal.confirmed = true;
      withdrawal.confirmedAt = new Date().toISOString();

      // Сохранить обратно
      await writeJsonFile(filePath, withdrawal);

      if (USE_DB) {
        try { await db.upsert('withdrawals', { id: withdrawal.id, data: withdrawal }); }
        catch (dbErr) { console.error('DB update withdrawal confirm error:', dbErr.message); }
      }

      // Отправить push-уведомления о подтверждении
      await sendWithdrawalConfirmationNotifications(withdrawal);

      res.json({ success: true, withdrawal });
    } catch (err) {
      console.error('Ошибка подтверждения выемки:', err);
      res.status(500).json({ success: false, error: 'Ошибка подтверждения выемки' });
    }
  });

  // DELETE /api/withdrawals/:id - удалить выемку
  app.delete('/api/withdrawals/:id', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const filePath = path.join(WITHDRAWALS_DIR, `${id}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({ success: false, error: 'Выемка не найдена' });
      }

      await fsp.unlink(filePath);

      if (USE_DB) {
        try { await db.deleteById('withdrawals', id); }
        catch (dbErr) { console.error('DB delete withdrawal error:', dbErr.message); }
      }

      res.json({ success: true, message: 'Выемка удалена' });
    } catch (err) {
      console.error('Ошибка удаления выемки:', err);
      res.status(500).json({ success: false, error: 'Ошибка удаления выемки' });
    }
  });

  // PATCH /api/withdrawals/:id/cancel - отменить выемку
  app.patch('/api/withdrawals/:id/cancel', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const { cancelledBy, cancelReason } = req.body;
      console.log('PATCH /api/withdrawals/:id/cancel', id);

      const filePath = path.join(WITHDRAWALS_DIR, `${id}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({ success: false, error: 'Withdrawal not found' });
      }

      const withdrawal = JSON.parse(await fsp.readFile(filePath, 'utf8'));

      if (withdrawal.status === 'cancelled') {
        return res.status(400).json({
          success: false,
          error: 'Withdrawal is already cancelled'
        });
      }

      withdrawal.status = 'cancelled';
      withdrawal.cancelledAt = new Date().toISOString();
      withdrawal.cancelledBy = cancelledBy || 'unknown';
      withdrawal.cancelReason = cancelReason || 'No reason provided';

      await writeJsonFile(filePath, withdrawal);

      if (USE_DB) {
        try { await db.upsert('withdrawals', { id: withdrawal.id, data: withdrawal }); }
        catch (dbErr) { console.error('DB update withdrawal cancel error:', dbErr.message); }
      }

      res.json({ success: true, withdrawal });
    } catch (error) {
      console.error('Error cancelling withdrawal:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Withdrawals API initialized ${USE_DB ? '(DB mode)' : '(file mode)'}`);
}

module.exports = { setupWithdrawalsAPI, loadAllEmployeesForWithdrawals };

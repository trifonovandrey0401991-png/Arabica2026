/**
 * Withdrawals API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const admin = require('firebase-admin');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const WITHDRAWALS_DIR = `${DATA_DIR}/withdrawals`;
const MAIN_CASH_DIR = `${DATA_DIR}/main_cash`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;
const FCM_TOKENS_DIR = `${DATA_DIR}/fcm-tokens`;

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Убедиться что директория существует
async function ensureDirectoryExists(dir) {
  if (!(await fileExists(dir))) {
    await fsp.mkdir(dir, { recursive: true, mode: 0o755 });
  }
}

// Загрузить всех сотрудников
async function loadAllEmployees() {
  if (!(await fileExists(EMPLOYEES_DIR))) {
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

// Получить FCM токен пользователя по телефону
async function getFCMTokenByPhone(phone) {
  try {
    const normalizedPhone = phone.replace(/[\s+]/g, '');
    const tokenFile = path.join(FCM_TOKENS_DIR, `${normalizedPhone}.json`);

    if (!(await fileExists(tokenFile))) {
      return null;
    }

    const data = await fsp.readFile(tokenFile, 'utf8');
    const tokenData = JSON.parse(data);
    return tokenData.token || null;
  } catch (err) {
    console.error(`Ошибка получения токена для ${phone}:`, err.message);
    return null;
  }
}

// Получить FCM токены пользователей
async function getFCMTokensForUsers(phones) {
  if (!(await fileExists(FCM_TOKENS_DIR))) {
    console.log('⚠️  Папка FCM токенов не существует');
    return [];
  }

  const tokens = [];
  for (const phone of phones) {
    const token = await getFCMTokenByPhone(phone);
    if (token) {
      tokens.push(token);
    }
  }

  return tokens;
}

// Отправить push-уведомления о новой выемке
async function sendWithdrawalNotifications(withdrawal) {
  try {
    // 1. Загрузить всех сотрудников
    const employees = await loadAllEmployees();

    // 2. Отфильтровать админов
    const admins = employees.filter(e => e.isAdmin === true);

    if (admins.length === 0) {
      console.log('Нет админов для отправки уведомлений о создании');
      return;
    }

    // 3. Получить FCM токены админов
    const adminPhones = admins.map(a => a.phone).filter(p => p);
    const tokens = await getFCMTokensForUsers(adminPhones);

    if (tokens.length === 0) {
      console.log('Нет FCM токенов для админов');
      return;
    }

    // 4. Отправить уведомление
    const message = {
      notification: {
        title: `Новая выемка: ${withdrawal.shopAddress}`,
        body: `${withdrawal.employeeName} сделал выемку на ${withdrawal.totalAmount.toFixed(0)} руб (${withdrawal.type.toUpperCase()})`,
      },
      data: {
        type: 'withdrawal_created',
        withdrawalId: withdrawal.id,
        shopAddress: withdrawal.shopAddress,
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'withdrawals_channel',
        },
      },
    };

    await admin.messaging().sendMulticast({
      tokens: tokens,
      ...message,
    });

    console.log(`✅ Отправлено уведомление о создании выемки ${tokens.length} админам`);
  } catch (err) {
    console.error('❌ Ошибка отправки push-уведомлений о создании:', err);
  }
}

// Отправить push-уведомления о подтверждении выемки
async function sendWithdrawalConfirmationNotifications(withdrawal) {
  try {
    // 1. Загрузить всех сотрудников
    const employees = await loadAllEmployees();

    // 2. Отфильтровать админов
    const admins = employees.filter(e => e.isAdmin === true);

    if (admins.length === 0) {
      console.log('Нет админов для отправки уведомлений о подтверждении');
      return;
    }

    // 3. Получить FCM токены админов
    const adminPhones = admins.map(a => a.phone).filter(p => p);
    const tokens = await getFCMTokensForUsers(adminPhones);

    if (tokens.length === 0) {
      console.log('Нет FCM токенов для админов');
      return;
    }

    // 4. Отправить уведомление
    const message = {
      notification: {
        title: `Выемка подтверждена: ${withdrawal.shopAddress}`,
        body: `Выемка от ${withdrawal.employeeName} на ${withdrawal.totalAmount.toFixed(0)} руб (${withdrawal.type.toUpperCase()}) подтверждена`,
      },
      data: {
        type: 'withdrawal_confirmed',
        withdrawalId: withdrawal.id,
        shopAddress: withdrawal.shopAddress,
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'withdrawals_channel',
        },
      },
    };

    await admin.messaging().sendMulticast({
      tokens: tokens,
      ...message,
    });

    console.log(`✅ Отправлено уведомление о подтверждении выемки ${tokens.length} админам`);
  } catch (err) {
    console.error('❌ Ошибка отправки push-уведомлений о подтверждении:', err);
  }
}

// Обновить баланс главной кассы
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
    await ensureDirectoryExists(MAIN_CASH_DIR);
    await fsp.writeFile(filePath, JSON.stringify(balance, null, 2), 'utf8');

    console.log(`Обновлён баланс ${shopAddress}: ${type}Balance -= ${amount}`);
  } catch (err) {
    console.error('Ошибка обновления баланса главной кассы:', err);
    throw err;
  }
}

function registerWithdrawalsAPI(app) {
  // GET /api/withdrawals - получить все выемки с опциональными фильтрами
  app.get('/api/withdrawals', async (req, res) => {
    try {
      await ensureDirectoryExists(WITHDRAWALS_DIR);

      const { shopAddress, type, fromDate, toDate } = req.query;

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

      res.json({ success: true, withdrawals });
    } catch (err) {
      console.error('Ошибка получения выемок:', err);
      res.status(500).json({ success: false, error: 'Ошибка получения выемок' });
    }
  });

  // POST /api/withdrawals - создать новую выемку
  app.post('/api/withdrawals', async (req, res) => {
    try {
      const {
        shopAddress,
        employeeName,
        employeeId,
        type,
        expenses,
        adminName,
      } = req.body;

      // Валидация
      if (!shopAddress || !employeeName || !employeeId || !type || !expenses || !Array.isArray(expenses)) {
        return res.status(400).json({ success: false, error: 'Не все обязательные поля заполнены' });
      }

      if (type !== 'ooo' && type !== 'ip') {
        return res.status(400).json({ success: false, error: 'Тип должен быть ooo или ip' });
      }

      if (expenses.length === 0) {
        return res.status(400).json({ success: false, error: 'Добавьте хотя бы один расход' });
      }

      // Валидация расходов
      for (const expense of expenses) {
        if (!expense.amount || expense.amount <= 0) {
          return res.status(400).json({ success: false, error: 'Все суммы расходов должны быть положительными' });
        }

        if (!expense.supplierId && !expense.comment) {
          return res.status(400).json({ success: false, error: 'Для "Другого расхода" комментарий обязателен' });
        }
      }

      // Вычислить общую сумму
      const totalAmount = expenses.reduce((sum, expense) => sum + expense.amount, 0);

      // Создать выемку
      const withdrawal = {
        id: `withdrawal_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        shopAddress,
        employeeName,
        employeeId,
        type,
        totalAmount,
        expenses,
        adminName: adminName || null,
        createdAt: new Date().toISOString(),
        confirmed: false, // По умолчанию не подтверждена
      };

      // Сохранить в файл
      await ensureDirectoryExists(WITHDRAWALS_DIR);
      const filePath = path.join(WITHDRAWALS_DIR, `${withdrawal.id}.json`);
      await fsp.writeFile(filePath, JSON.stringify(withdrawal, null, 2), 'utf8');

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
  app.patch('/api/withdrawals/:id/confirm', async (req, res) => {
    try {
      const { id } = req.params;
      const filePath = path.join(WITHDRAWALS_DIR, `${id}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Выемка не найдена' });
      }

      // Загрузить выемку
      const data = await fsp.readFile(filePath, 'utf8');
      const withdrawal = JSON.parse(data);

      // Проверить что уже не подтверждена
      if (withdrawal.confirmed === true) {
        return res.status(400).json({ success: false, error: 'Выемка уже подтверждена' });
      }

      // Обновить статус
      withdrawal.confirmed = true;
      withdrawal.confirmedAt = new Date().toISOString();

      // Сохранить обновлённую выемку
      await fsp.writeFile(filePath, JSON.stringify(withdrawal, null, 2), 'utf8');

      // Отправить push-уведомления админам о подтверждении
      await sendWithdrawalConfirmationNotifications(withdrawal);

      res.json({ success: true, withdrawal });
    } catch (err) {
      console.error('Ошибка подтверждения выемки:', err);
      res.status(500).json({ success: false, error: 'Ошибка подтверждения выемки' });
    }
  });

  // DELETE /api/withdrawals/:id - удалить выемку
  app.delete('/api/withdrawals/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const filePath = path.join(WITHDRAWALS_DIR, `${id}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Выемка не найдена' });
      }

      await fsp.unlink(filePath);

      res.json({ success: true, message: 'Выемка удалена' });
    } catch (err) {
      console.error('Ошибка удаления выемки:', err);
      res.status(500).json({ success: false, error: 'Ошибка удаления выемки' });
    }
  });
}

module.exports = { registerWithdrawalsAPI };

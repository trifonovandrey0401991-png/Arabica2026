const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const WITHDRAWALS_DIR = '/var/www/withdrawals';
const MAIN_CASH_DIR = '/var/www/main_cash';
const EMPLOYEES_DIR = '/var/www/employees';
const FCM_TOKENS_FILE = '/var/www/fcm_tokens.json';

// Убедиться что директория существует
function ensureDirectoryExists(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true, mode: 0o755 });
  }
}

// Загрузить всех сотрудников
function loadAllEmployees() {
  if (!fs.existsSync(EMPLOYEES_DIR)) {
    return [];
  }

  const files = fs.readdirSync(EMPLOYEES_DIR);
  const employees = [];

  for (const file of files) {
    if (file.endsWith('.json')) {
      try {
        const filePath = path.join(EMPLOYEES_DIR, file);
        const data = fs.readFileSync(filePath, 'utf8');
        const employee = JSON.parse(data);
        employees.push(employee);
      } catch (err) {
        console.error(`Ошибка чтения сотрудника ${file}:`, err);
      }
    }
  }

  return employees;
}

// Получить FCM токены пользователей
async function getFCMTokensForUsers(phones) {
  if (!fs.existsSync(FCM_TOKENS_FILE)) {
    return [];
  }

  try {
    const data = fs.readFileSync(FCM_TOKENS_FILE, 'utf8');
    const allTokens = JSON.parse(data);

    const tokens = [];
    for (const phone of phones) {
      if (allTokens[phone]) {
        tokens.push(allTokens[phone]);
      }
    }

    return tokens;
  } catch (err) {
    console.error('Ошибка загрузки FCM токенов:', err);
    return [];
  }
}

// Отправить push-уведомления о выемке
async function sendWithdrawalNotifications(withdrawal) {
  try {
    // 1. Загрузить всех сотрудников
    const employees = loadAllEmployees();

    // 2. Отфильтровать админов
    const admins = employees.filter(e => e.isAdmin === true);

    if (admins.length === 0) {
      console.log('Нет админов для отправки уведомлений');
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
        title: `Выемка: ${withdrawal.shopAddress}`,
        body: `${withdrawal.employeeName} сделал выемку на ${withdrawal.totalAmount.toFixed(0)} руб (${withdrawal.type.toUpperCase()})`,
      },
      data: {
        type: 'withdrawal',
        withdrawalId: withdrawal.id,
        shopAddress: withdrawal.shopAddress,
      },
    };

    await admin.messaging().sendMulticast({
      tokens: tokens,
      ...message,
    });

    console.log(`Отправлено уведомление о выемке ${tokens.length} админам`);
  } catch (err) {
    console.error('Ошибка отправки push-уведомлений:', err);
  }
}

// Обновить баланс главной кассы
function updateMainCashBalance(shopAddress, type, amount) {
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
    if (fs.existsSync(filePath)) {
      const data = fs.readFileSync(filePath, 'utf8');
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
    ensureDirectoryExists(MAIN_CASH_DIR);
    fs.writeFileSync(filePath, JSON.stringify(balance, null, 2), 'utf8');

    console.log(`Обновлён баланс ${shopAddress}: ${type}Balance -= ${amount}`);
  } catch (err) {
    console.error('Ошибка обновления баланса главной кассы:', err);
    throw err;
  }
}

function registerWithdrawalsAPI(app) {
  // GET /api/withdrawals - получить все выемки с опциональными фильтрами
  app.get('/api/withdrawals', (req, res) => {
    try {
      ensureDirectoryExists(WITHDRAWALS_DIR);

      const { shopAddress, type, fromDate, toDate } = req.query;

      const files = fs.readdirSync(WITHDRAWALS_DIR);
      let withdrawals = [];

      for (const file of files) {
        if (file.endsWith('.json')) {
          try {
            const filePath = path.join(WITHDRAWALS_DIR, file);
            const data = fs.readFileSync(filePath, 'utf8');
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

      res.json({ withdrawals });
    } catch (err) {
      console.error('Ошибка получения выемок:', err);
      res.status(500).json({ error: 'Ошибка получения выемок' });
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
        return res.status(400).json({ error: 'Не все обязательные поля заполнены' });
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
        employeeId,
        type,
        totalAmount,
        expenses,
        adminName: adminName || null,
        createdAt: new Date().toISOString(),
      };

      // Сохранить в файл
      ensureDirectoryExists(WITHDRAWALS_DIR);
      const filePath = path.join(WITHDRAWALS_DIR, `${withdrawal.id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(withdrawal, null, 2), 'utf8');

      // Обновить баланс главной кассы
      updateMainCashBalance(shopAddress, type, totalAmount);

      // Отправить push-уведомления админам
      await sendWithdrawalNotifications(withdrawal);

      res.json({ withdrawal });
    } catch (err) {
      console.error('Ошибка создания выемки:', err);
      res.status(500).json({ error: 'Ошибка создания выемки' });
    }
  });

  // DELETE /api/withdrawals/:id - удалить выемку
  app.delete('/api/withdrawals/:id', (req, res) => {
    try {
      const { id } = req.params;
      const filePath = path.join(WITHDRAWALS_DIR, `${id}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ error: 'Выемка не найдена' });
      }

      fs.unlinkSync(filePath);

      res.json({ success: true, message: 'Выемка удалена' });
    } catch (err) {
      console.error('Ошибка удаления выемки:', err);
      res.status(500).json({ error: 'Ошибка удаления выемки' });
    }
  });
}

module.exports = { registerWithdrawalsAPI };

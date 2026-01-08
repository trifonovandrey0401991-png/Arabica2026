// ========== API для передачи смен ==========

const SHIFT_TRANSFERS_FILE = '/var/www/shift-transfers.json';

// Вспомогательные функции для передачи смен
function loadShiftTransfers() {
  try {
    if (fs.existsSync(SHIFT_TRANSFERS_FILE)) {
      const data = fs.readFileSync(SHIFT_TRANSFERS_FILE, 'utf8');
      return JSON.parse(data).requests || [];
    }
  } catch (e) {
    console.error('Ошибка загрузки shift-transfers:', e);
  }
  return [];
}

function saveShiftTransfers(requests) {
  const data = { requests, updatedAt: new Date().toISOString() };
  fs.writeFileSync(SHIFT_TRANSFERS_FILE, JSON.stringify(data, null, 2), 'utf8');
}

// Очистка устаревших запросов (старше 30 дней)
function cleanupExpiredTransfers(requests) {
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  return requests.filter(r => {
    const createdAt = new Date(r.createdAt);
    if (createdAt < thirtyDaysAgo && r.status === 'pending') {
      r.status = 'expired';
    }
    // Удаляем очень старые записи (60 дней)
    const sixtyDaysAgo = new Date();
    sixtyDaysAgo.setDate(sixtyDaysAgo.getDate() - 60);
    return createdAt > sixtyDaysAgo;
  });
}

// POST /api/shift-transfers - создать запрос на передачу смены
app.post('/api/shift-transfers', (req, res) => {
  try {
    console.log('POST /api/shift-transfers', req.body);

    const {
      fromEmployeeId,
      fromEmployeeName,
      toEmployeeId,
      toEmployeeName,
      scheduleEntryId,
      shiftDate,
      shopAddress,
      shopName,
      shiftType,
      comment
    } = req.body;

    if (!fromEmployeeId || !scheduleEntryId || !shiftDate) {
      return res.status(400).json({
        success: false,
        error: 'Не указаны обязательные поля'
      });
    }

    let requests = loadShiftTransfers();
    requests = cleanupExpiredTransfers(requests);

    const newRequest = {
      id: 'transfer_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9),
      fromEmployeeId,
      fromEmployeeName,
      toEmployeeId: toEmployeeId || null,
      toEmployeeName: toEmployeeName || null,
      scheduleEntryId,
      shiftDate,
      shopAddress,
      shopName,
      shiftType,
      comment: comment || null,
      status: 'pending',
      acceptedByEmployeeId: null,
      acceptedByEmployeeName: null,
      createdAt: new Date().toISOString(),
      acceptedAt: null,
      resolvedAt: null,
      isReadByRecipient: false,
      isReadByAdmin: false
    };

    requests.push(newRequest);
    saveShiftTransfers(requests);

    console.log('Создан запрос на передачу смены: ' + fromEmployeeName + ' -> ' + (toEmployeeName || 'всем'));
    res.json({ success: true, request: newRequest });
  } catch (error) {
    console.error('Ошибка создания запроса на передачу:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/shift-transfers/employee/:employeeId - уведомления для сотрудника
app.get('/api/shift-transfers/employee/:employeeId', (req, res) => {
  try {
    const { employeeId } = req.params;
    console.log('GET /api/shift-transfers/employee/' + employeeId);

    let requests = loadShiftTransfers();
    requests = cleanupExpiredTransfers(requests);
    saveShiftTransfers(requests);

    // Фильтруем: адресовано этому сотруднику или всем (broadcast)
    // И НЕ от этого сотрудника (свои запросы не показываем как входящие)
    const filtered = requests.filter(r =>
      r.fromEmployeeId !== employeeId &&
      (r.toEmployeeId === employeeId || r.toEmployeeId === null) &&
      ['pending', 'accepted'].includes(r.status)
    );

    // Сортируем: непрочитанные первыми, потом по дате
    filtered.sort((a, b) => {
      if (a.isReadByRecipient !== b.isReadByRecipient) {
        return a.isReadByRecipient ? 1 : -1;
      }
      return new Date(b.createdAt) - new Date(a.createdAt);
    });

    res.json({ success: true, requests: filtered });
  } catch (error) {
    console.error('Ошибка получения уведомлений:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/shift-transfers/employee/:employeeId/outgoing - исходящие запросы сотрудника
app.get('/api/shift-transfers/employee/:employeeId/outgoing', (req, res) => {
  try {
    const { employeeId } = req.params;
    console.log('GET /api/shift-transfers/employee/' + employeeId + '/outgoing');

    let requests = loadShiftTransfers();
    requests = cleanupExpiredTransfers(requests);

    // Запросы, которые создал этот сотрудник
    const filtered = requests.filter(r => r.fromEmployeeId === employeeId);
    filtered.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    res.json({ success: true, requests: filtered });
  } catch (error) {
    console.error('Ошибка получения исходящих запросов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/shift-transfers/employee/:employeeId/unread-count - счетчик непрочитанных
app.get('/api/shift-transfers/employee/:employeeId/unread-count', (req, res) => {
  try {
    const { employeeId } = req.params;

    const requests = loadShiftTransfers();
    const count = requests.filter(r =>
      r.fromEmployeeId !== employeeId &&
      (r.toEmployeeId === employeeId || r.toEmployeeId === null) &&
      r.status === 'pending' &&
      !r.isReadByRecipient
    ).length;

    res.json({ success: true, count });
  } catch (error) {
    console.error('Ошибка подсчета непрочитанных:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/shift-transfers/admin - запросы для администратора
app.get('/api/shift-transfers/admin', (req, res) => {
  try {
    console.log('GET /api/shift-transfers/admin');

    let requests = loadShiftTransfers();
    requests = cleanupExpiredTransfers(requests);
    saveShiftTransfers(requests);

    // Для админа показываем запросы со статусом accepted (ждут одобрения)
    const filtered = requests.filter(r => r.status === 'accepted');
    filtered.sort((a, b) => {
      if (a.isReadByAdmin !== b.isReadByAdmin) {
        return a.isReadByAdmin ? 1 : -1;
      }
      return new Date(b.acceptedAt || b.createdAt) - new Date(a.acceptedAt || a.createdAt);
    });

    res.json({ success: true, requests: filtered });
  } catch (error) {
    console.error('Ошибка получения запросов для админа:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/shift-transfers/admin/unread-count - счетчик непрочитанных для админа
app.get('/api/shift-transfers/admin/unread-count', (req, res) => {
  try {
    const requests = loadShiftTransfers();
    const count = requests.filter(r =>
      r.status === 'accepted' && !r.isReadByAdmin
    ).length;

    res.json({ success: true, count });
  } catch (error) {
    console.error('Ошибка подсчета непрочитанных для админа:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/shift-transfers/:id/accept - сотрудник принимает запрос
app.put('/api/shift-transfers/:id/accept', (req, res) => {
  try {
    const { id } = req.params;
    const { employeeId, employeeName } = req.body;
    console.log('PUT /api/shift-transfers/' + id + '/accept', { employeeId, employeeName });

    let requests = loadShiftTransfers();
    const index = requests.findIndex(r => r.id === id);

    if (index === -1) {
      return res.status(404).json({ success: false, error: 'Запрос не найден' });
    }

    const request = requests[index];

    if (request.status !== 'pending') {
      return res.status(400).json({ success: false, error: 'Запрос уже обработан' });
    }

    request.status = 'accepted';
    request.acceptedByEmployeeId = employeeId;
    request.acceptedByEmployeeName = employeeName;
    request.acceptedAt = new Date().toISOString();
    request.isReadByRecipient = true;
    request.isReadByAdmin = false;

    saveShiftTransfers(requests);

    console.log('Запрос ' + id + ' принят сотрудником ' + employeeName);
    res.json({ success: true, request });
  } catch (error) {
    console.error('Ошибка принятия запроса:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/shift-transfers/:id/reject - сотрудник отклоняет запрос
app.put('/api/shift-transfers/:id/reject', (req, res) => {
  try {
    const { id } = req.params;
    console.log('PUT /api/shift-transfers/' + id + '/reject');

    let requests = loadShiftTransfers();
    const index = requests.findIndex(r => r.id === id);

    if (index === -1) {
      return res.status(404).json({ success: false, error: 'Запрос не найден' });
    }

    const request = requests[index];

    // Для персонального запроса меняем статус на rejected
    // Для broadcast запроса просто помечаем как прочитанный (другие могут принять)
    if (request.toEmployeeId !== null) {
      request.status = 'rejected';
      request.resolvedAt = new Date().toISOString();
    }
    request.isReadByRecipient = true;

    saveShiftTransfers(requests);

    console.log('Запрос ' + id + ' отклонен');
    res.json({ success: true, request });
  } catch (error) {
    console.error('Ошибка отклонения запроса:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/shift-transfers/:id/approve - админ одобряет запрос
app.put('/api/shift-transfers/:id/approve', (req, res) => {
  try {
    const { id } = req.params;
    console.log('PUT /api/shift-transfers/' + id + '/approve');

    let requests = loadShiftTransfers();
    const index = requests.findIndex(r => r.id === id);

    if (index === -1) {
      return res.status(404).json({ success: false, error: 'Запрос не найден' });
    }

    const request = requests[index];

    if (request.status !== 'accepted') {
      return res.status(400).json({ success: false, error: 'Запрос должен быть в статусе "принят"' });
    }

    // Обновляем график работы
    const shiftDate = new Date(request.shiftDate);
    const monthStr = shiftDate.getFullYear() + '-' + String(shiftDate.getMonth() + 1).padStart(2, '0');
    const scheduleFile = path.join(WORK_SCHEDULES_DIR, monthStr + '.json');

    if (fs.existsSync(scheduleFile)) {
      const scheduleData = JSON.parse(fs.readFileSync(scheduleFile, 'utf8'));
      const entryIndex = scheduleData.entries.findIndex(e => e.id === request.scheduleEntryId);

      if (entryIndex !== -1) {
        // Меняем сотрудника в записи графика
        scheduleData.entries[entryIndex].employeeId = request.acceptedByEmployeeId;
        scheduleData.entries[entryIndex].employeeName = request.acceptedByEmployeeName;
        scheduleData.updatedAt = new Date().toISOString();

        fs.writeFileSync(scheduleFile, JSON.stringify(scheduleData, null, 2), 'utf8');
        console.log('График обновлен: смена передана ' + request.acceptedByEmployeeName);
      }
    }

    request.status = 'approved';
    request.resolvedAt = new Date().toISOString();
    request.isReadByAdmin = true;

    saveShiftTransfers(requests);

    console.log('Запрос ' + id + ' одобрен, график обновлен');
    res.json({ success: true, request });
  } catch (error) {
    console.error('Ошибка одобрения запроса:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/shift-transfers/:id/decline - админ отклоняет запрос
app.put('/api/shift-transfers/:id/decline', (req, res) => {
  try {
    const { id } = req.params;
    console.log('PUT /api/shift-transfers/' + id + '/decline');

    let requests = loadShiftTransfers();
    const index = requests.findIndex(r => r.id === id);

    if (index === -1) {
      return res.status(404).json({ success: false, error: 'Запрос не найден' });
    }

    const request = requests[index];
    request.status = 'declined';
    request.resolvedAt = new Date().toISOString();
    request.isReadByAdmin = true;

    saveShiftTransfers(requests);

    console.log('Запрос ' + id + ' отклонен администратором');
    res.json({ success: true, request });
  } catch (error) {
    console.error('Ошибка отклонения запроса админом:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/shift-transfers/:id/read - отметить как прочитанное
app.put('/api/shift-transfers/:id/read', (req, res) => {
  try {
    const { id } = req.params;
    const { isAdmin } = req.body;

    let requests = loadShiftTransfers();
    const index = requests.findIndex(r => r.id === id);

    if (index === -1) {
      return res.status(404).json({ success: false, error: 'Запрос не найден' });
    }

    if (isAdmin) {
      requests[index].isReadByAdmin = true;
    } else {
      requests[index].isReadByRecipient = true;
    }

    saveShiftTransfers(requests);
    res.json({ success: true });
  } catch (error) {
    console.error('Ошибка отметки как прочитанное:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

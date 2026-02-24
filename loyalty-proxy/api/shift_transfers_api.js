/**
 * Shift Transfers API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const { isAdminPhone } = require('../utils/admin_cache');
const { maskPhone, fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const { requireAuth } = require('../utils/session_middleware');
const { notifyCounterUpdate } = require('./counters_websocket');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const SHIFT_TRANSFERS_FILE = `${DATA_DIR}/shift-transfers.json`;
const WORK_SCHEDULES_DIR = `${DATA_DIR}/work-schedules`;

// Импорт модуля уведомлений
const {
  notifyTransferCreated,
  notifyTransferAccepted,
  notifyTransferRejected,
  notifyTransferApproved,
  notifyTransferDeclined,
  notifyOthersDeclined,
} = require('./shift_transfers_notifications');

// Helper functions
async function loadShiftTransfers() {
  try {
    if (await fileExists(SHIFT_TRANSFERS_FILE)) {
      const data = await fsp.readFile(SHIFT_TRANSFERS_FILE, 'utf8');
      return JSON.parse(data).requests || [];
    }
  } catch (e) {
    console.error('Error loading shift-transfers:', e);
  }
  return [];
}

async function saveShiftTransfers(requests) {
  const data = { requests, updatedAt: new Date().toISOString() };
  await writeJsonFile(SHIFT_TRANSFERS_FILE, data);
}

// Cleanup expired transfers (older than 30 days with pending status)
function cleanupExpiredTransfers(requests) {
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  return requests.filter(r => {
    const createdAt = new Date(r.createdAt);
    if (createdAt < thirtyDaysAgo && (r.status === 'pending' || r.status === 'has_acceptances')) {
      return false;
    }
    return true;
  });
}

// ==================== WORK SCHEDULE UPDATE ====================

/**
 * Обновить график работы при одобрении передачи смены
 * @param {Object} transfer - Данные о передаче смены
 * @param {string} newEmployeeId - ID нового сотрудника
 * @param {string} newEmployeeName - Имя нового сотрудника
 */
async function updateWorkSchedule(transfer, newEmployeeId, newEmployeeName) {
  try {
    const shiftDate = new Date(transfer.shiftDate);
    const monthKey = `${shiftDate.getFullYear()}-${String(shiftDate.getMonth() + 1).padLeft(2, '0')}`;
    const scheduleFile = path.join(WORK_SCHEDULES_DIR, `${monthKey}.json`);

    if (!(await fileExists(scheduleFile))) {
      console.log(`[ShiftTransfer] Schedule file not found: ${scheduleFile}`);
      return false;
    }

    const content = await fsp.readFile(scheduleFile, 'utf8');
    const scheduleData = JSON.parse(content);
    const entries = scheduleData.entries || [];

    // Найти запись в графике
    const entryIndex = entries.findIndex(e =>
      e.id === transfer.scheduleEntryId ||
      (e.date === transfer.shiftDate.split('T')[0] &&
       e.shopAddress === transfer.shopAddress &&
       e.shiftType === transfer.shiftType &&
       e.employeeId === transfer.fromEmployeeId)
    );

    if (entryIndex === -1) {
      console.log(`[ShiftTransfer] Schedule entry not found for transfer ${transfer.id}`);
      return false;
    }

    // Обновить запись
    const oldEntry = entries[entryIndex];
    entries[entryIndex] = {
      ...oldEntry,
      employeeId: newEmployeeId,
      employeeName: newEmployeeName,
      transferredFrom: {
        employeeId: transfer.fromEmployeeId,
        employeeName: transfer.fromEmployeeName,
        transferId: transfer.id,
        transferredAt: new Date().toISOString()
      }
    };

    scheduleData.entries = entries;
    scheduleData.updatedAt = new Date().toISOString();

    await writeJsonFile(scheduleFile, scheduleData);
    console.log(`[ShiftTransfer] Schedule updated: ${transfer.fromEmployeeName} → ${newEmployeeName}`);
    return true;
  } catch (e) {
    console.error('[ShiftTransfer] Error updating schedule:', e);
    return false;
  }
}

// Polyfill for String.prototype.padLeft
if (!String.prototype.padLeft) {
  String.prototype.padLeft = function(length, char) {
    return (char.repeat(length) + this).slice(-length);
  };
}

function setupShiftTransfersAPI(app) {
  // ===== GET ALL SHIFT TRANSFERS =====
  app.get('/api/shift-transfers', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/shift-transfers');
      const { shopAddress, status, employeeName } = req.query;

      let requests = await loadShiftTransfers();

      // Cleanup expired
      const cleanedRequests = cleanupExpiredTransfers(requests);
      if (cleanedRequests.length !== requests.length) {
        await saveShiftTransfers(cleanedRequests);
        requests = cleanedRequests;
      }

      // Filter
      if (shopAddress) {
        requests = requests.filter(r => r.shopAddress === shopAddress);
      }
      if (status) {
        requests = requests.filter(r => r.status === status);
      }
      if (employeeName) {
        requests = requests.filter(r =>
          r.fromEmployeeName === employeeName || r.toEmployeeName === employeeName
        );
      }

      requests.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, requests });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET EMPLOYEE REQUESTS (incoming - broadcast or addressed to this employee) =====
  app.get('/api/shift-transfers/employee/:employeeId', requireAuth, async (req, res) => {
    try {
      const { employeeId } = req.params;
      console.log('GET /api/shift-transfers/employee/:employeeId', employeeId);

      let requests = await loadShiftTransfers();

      // Cleanup expired
      const cleanedRequests = cleanupExpiredTransfers(requests);
      if (cleanedRequests.length !== requests.length) {
        await saveShiftTransfers(cleanedRequests);
        requests = cleanedRequests;
      }

      // Filter: requests where:
      // - toEmployeeId matches OR it's a broadcast (toEmployeeId is null)
      // - AND not sent by this employee themselves
      // - AND status is pending or has_acceptances (can still accept)
      // - AND this employee hasn't already accepted (check acceptedBy array)
      requests = requests.filter(r => {
        if (r.fromEmployeeId === employeeId) return false;
        if (r.toEmployeeId && r.toEmployeeId !== employeeId) return false;
        if (r.status !== 'pending' && r.status !== 'has_acceptances') return false;

        // Check if already accepted by this employee
        const acceptedBy = r.acceptedBy || [];
        const alreadyAccepted = acceptedBy.some(a => a.employeeId === employeeId);
        if (alreadyAccepted) return false;

        // Check if already rejected by this employee (broadcast requests)
        const rejectedBy = r.rejectedBy || [];
        const alreadyRejected = rejectedBy.some(a => a.employeeId === employeeId);
        if (alreadyRejected) return false;

        return true;
      });

      requests.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, requests });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET EMPLOYEE OUTGOING REQUESTS =====
  app.get('/api/shift-transfers/employee/:employeeId/outgoing', requireAuth, async (req, res) => {
    try {
      const { employeeId } = req.params;
      console.log('GET /api/shift-transfers/employee/:employeeId/outgoing', employeeId);

      let requests = await loadShiftTransfers();

      // Filter: requests sent by this employee
      requests = requests.filter(r => r.fromEmployeeId === employeeId);

      requests.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, requests });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET EMPLOYEE UNREAD COUNT =====
  app.get('/api/shift-transfers/employee/:employeeId/unread-count', requireAuth, async (req, res) => {
    try {
      const { employeeId } = req.params;
      console.log('GET /api/shift-transfers/employee/:employeeId/unread-count', employeeId);

      const requests = await loadShiftTransfers();

      // Count unread incoming requests
      const count = requests.filter(r => {
        if (r.fromEmployeeId === employeeId) return false;
        if (r.toEmployeeId && r.toEmployeeId !== employeeId) return false;
        if (r.status !== 'pending' && r.status !== 'has_acceptances') return false;
        if (r.isReadByRecipient) return false;

        // Check if already accepted
        const acceptedBy = r.acceptedBy || [];
        if (acceptedBy.some(a => a.employeeId === employeeId)) return false;

        // Check if already rejected (broadcast requests)
        const rejectedBy = r.rejectedBy || [];
        if (rejectedBy.some(a => a.employeeId === employeeId)) return false;

        return true;
      }).length;

      res.json({ success: true, count });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET ADMIN REQUESTS (with acceptances, waiting for approval) =====
  app.get('/api/shift-transfers/admin', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/shift-transfers/admin');

      let requests = await loadShiftTransfers();

      // Filter: requests that have acceptances (status = 'has_acceptances' or legacy 'accepted')
      requests = requests.filter(r => {
        if (r.status === 'has_acceptances') return true;
        if (r.status === 'accepted') return true; // Legacy support
        return false;
      });

      requests.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, requests });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET ADMIN UNREAD COUNT =====
  app.get('/api/shift-transfers/admin/unread-count', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/shift-transfers/admin/unread-count');

      const requests = await loadShiftTransfers();

      // Count unread requests with acceptances
      const count = requests.filter(r =>
        (r.status === 'has_acceptances' || r.status === 'accepted') && !r.isReadByAdmin
      ).length;

      res.json({ success: true, count });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CREATE SHIFT TRANSFER REQUEST =====
  app.post('/api/shift-transfers', requireAuth, async (req, res) => {
    try {
      const transfer = req.body;
      console.log('POST /api/shift-transfers:', transfer.fromEmployeeName, '->', transfer.toEmployeeName || 'всем');

      if (!transfer.fromEmployeeId || !transfer.fromEmployeeName || !transfer.shiftDate) {
        return res.status(400).json({
          success: false,
          error: 'fromEmployeeId, fromEmployeeName, and shiftDate are required'
        });
      }

      const requests = await loadShiftTransfers();

      // Generate ID if not provided
      if (!transfer.id) {
        transfer.id = `transfer_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      transfer.createdAt = new Date().toISOString();
      transfer.status = 'pending';
      transfer.acceptedBy = []; // Массив принявших сотрудников
      transfer.isReadByRecipient = false;
      transfer.isReadByAdmin = false;

      requests.push(transfer);
      await saveShiftTransfers(requests);

      // ✅ Отправка уведомлений
      try {
        await notifyTransferCreated(transfer);
      } catch (e) {
        console.error('Ошибка отправки уведомлений:', e);
      }

      notifyCounterUpdate('shiftTransferRequests', { delta: 1 });
      res.json({ success: true, request: transfer });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET SINGLE SHIFT TRANSFER =====
  app.get('/api/shift-transfers/:requestId', requireAuth, async (req, res) => {
    try {
      const { requestId } = req.params;
      const requests = await loadShiftTransfers();
      const request = requests.find(r => r.id === requestId);

      if (request) {
        res.json({ success: true, request });
      } else {
        res.status(404).json({ success: false, error: 'Request not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== EMPLOYEE ACCEPTS REQUEST (добавляется в массив acceptedBy) =====
  app.put('/api/shift-transfers/:requestId/accept', requireAuth, async (req, res) => {
    try {
      const { requestId } = req.params;
      const { employeeId, employeeName } = req.body;
      console.log('PUT /api/shift-transfers/:requestId/accept:', requestId, employeeName);

      if (!employeeId || !employeeName) {
        return res.status(400).json({
          success: false,
          error: 'employeeId and employeeName are required'
        });
      }

      const requests = await loadShiftTransfers();
      const index = requests.findIndex(r => r.id === requestId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Request not found' });
      }

      const transfer = requests[index];

      // Проверка: можно ли ещё принять
      if (transfer.status !== 'pending' && transfer.status !== 'has_acceptances') {
        return res.status(400).json({
          success: false,
          error: 'This request can no longer be accepted'
        });
      }

      // Инициализация массива если нет
      if (!transfer.acceptedBy) {
        transfer.acceptedBy = [];
      }

      // Проверка: не принял ли уже этот сотрудник
      const alreadyAccepted = transfer.acceptedBy.some(a => a.employeeId === employeeId);
      if (alreadyAccepted) {
        return res.status(400).json({
          success: false,
          error: 'You have already accepted this request'
        });
      }

      // Добавляем в массив принявших
      transfer.acceptedBy.push({
        employeeId: employeeId,
        employeeName: employeeName,
        acceptedAt: new Date().toISOString()
      });

      // Меняем статус на "есть принявшие"
      transfer.status = 'has_acceptances';
      transfer.isReadByAdmin = false; // Reset for admin notification

      // Для обратной совместимости сохраняем данные первого принявшего
      if (transfer.acceptedBy.length === 1) {
        transfer.acceptedByEmployeeId = employeeId;
        transfer.acceptedByEmployeeName = employeeName;
        transfer.acceptedAt = new Date().toISOString();
      }

      requests[index] = transfer;
      await saveShiftTransfers(requests);

      // ✅ Отправка уведомлений
      try {
        await notifyTransferAccepted(transfer, employeeId, employeeName);
      } catch (e) {
        console.error('Ошибка отправки уведомлений:', e);
      }

      res.json({ success: true, request: transfer });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== EMPLOYEE REJECTS REQUEST =====
  app.put('/api/shift-transfers/:requestId/reject', requireAuth, async (req, res) => {
    try {
      const { requestId } = req.params;
      const { employeeId, employeeName } = req.body;
      console.log('PUT /api/shift-transfers/:requestId/reject:', requestId, employeeName || 'unknown');

      const requests = await loadShiftTransfers();
      const index = requests.findIndex(r => r.id === requestId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Request not found' });
      }

      const transfer = requests[index];

      // Если это адресный запрос одному сотруднику - отклоняем полностью
      if (transfer.toEmployeeId) {
        transfer.status = 'rejected';
        transfer.resolvedAt = new Date().toISOString();
        transfer.rejectedByEmployeeId = employeeId || transfer.toEmployeeId;
        transfer.rejectedByEmployeeName = employeeName || transfer.toEmployeeName;
      } else {
        // Для broadcast - просто помечаем что этот сотрудник отклонил
        // Запрос остаётся активным для других
        if (!transfer.rejectedBy) {
          transfer.rejectedBy = [];
        }
        transfer.rejectedBy.push({
          employeeId: employeeId,
          employeeName: employeeName,
          rejectedAt: new Date().toISOString()
        });
      }

      requests[index] = transfer;
      await saveShiftTransfers(requests);

      // ✅ Отправка уведомлений
      try {
        await notifyTransferRejected(transfer, employeeId, employeeName);
      } catch (e) {
        console.error('Ошибка отправки уведомлений:', e);
      }

      res.json({ success: true, request: transfer });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ADMIN APPROVES REQUEST (выбирает одного из принявших) =====
  app.put('/api/shift-transfers/:requestId/approve', requireAuth, async (req, res) => {
    try {
      const { requestId } = req.params;
      const { selectedEmployeeId } = req.body; // ID выбранного сотрудника
      console.log('PUT /api/shift-transfers/:requestId/approve:', requestId, 'selected:', selectedEmployeeId);

      const requests = await loadShiftTransfers();
      const index = requests.findIndex(r => r.id === requestId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Request not found' });
      }

      const transfer = requests[index];
      const acceptedBy = transfer.acceptedBy || [];

      // Определяем кого одобряем
      let approvedEmployee = null;

      if (selectedEmployeeId) {
        // Админ явно выбрал сотрудника
        approvedEmployee = acceptedBy.find(a => a.employeeId === selectedEmployeeId);
      } else if (acceptedBy.length === 1) {
        // Только один принял - автоматически выбираем его
        approvedEmployee = acceptedBy[0];
      } else if (transfer.acceptedByEmployeeId) {
        // Legacy: используем старое поле
        approvedEmployee = {
          employeeId: transfer.acceptedByEmployeeId,
          employeeName: transfer.acceptedByEmployeeName
        };
      }

      if (!approvedEmployee) {
        return res.status(400).json({
          success: false,
          error: 'No employee selected for approval. Please specify selectedEmployeeId.'
        });
      }

      // Обновляем статус
      transfer.status = 'approved';
      transfer.resolvedAt = new Date().toISOString();
      transfer.approvedEmployeeId = approvedEmployee.employeeId;
      transfer.approvedEmployeeName = approvedEmployee.employeeName;

      // Для обратной совместимости
      transfer.acceptedByEmployeeId = approvedEmployee.employeeId;
      transfer.acceptedByEmployeeName = approvedEmployee.employeeName;

      requests[index] = transfer;
      await saveShiftTransfers(requests);

      // ✅ Обновляем график работы
      const scheduleUpdated = await updateWorkSchedule(
        transfer,
        approvedEmployee.employeeId,
        approvedEmployee.employeeName
      );

      if (!scheduleUpdated) {
        console.log('[ShiftTransfer] Warning: Schedule was not updated');
      }

      // ✅ Отправка уведомлений
      try {
        // Уведомление одобренным
        await notifyTransferApproved(transfer, approvedEmployee);

        // Уведомление остальным (кто принял но не был выбран)
        const declinedEmployees = acceptedBy.filter(a => a.employeeId !== approvedEmployee.employeeId);
        if (declinedEmployees.length > 0) {
          await notifyOthersDeclined(transfer, declinedEmployees);
        }
      } catch (e) {
        console.error('Ошибка отправки уведомлений:', e);
      }

      notifyCounterUpdate('shiftTransferRequests', { delta: -1 });
      res.json({
        success: true,
        request: transfer,
        scheduleUpdated: scheduleUpdated
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ADMIN DECLINES REQUEST =====
  app.put('/api/shift-transfers/:requestId/decline', requireAuth, async (req, res) => {
    try {
      const { requestId } = req.params;
      console.log('PUT /api/shift-transfers/:requestId/decline:', requestId);

      const requests = await loadShiftTransfers();
      const index = requests.findIndex(r => r.id === requestId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Request not found' });
      }

      requests[index].status = 'declined';
      requests[index].resolvedAt = new Date().toISOString();

      await saveShiftTransfers(requests);

      // ✅ Отправка уведомлений всем участникам
      try {
        await notifyTransferDeclined(requests[index]);
      } catch (e) {
        console.error('Ошибка отправки уведомлений:', e);
      }

      res.json({ success: true, request: requests[index] });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== MARK AS READ =====
  app.put('/api/shift-transfers/:requestId/read', requireAuth, async (req, res) => {
    try {
      const { requestId } = req.params;
      const { phone } = req.body;

      if (!phone) {
        return res.status(400).json({ success: false, error: 'Phone is required' });
      }

      // B-10: isAdmin only from DB, never from body
      const isAdminUser = isAdminPhone(phone);
      console.log('PUT /api/shift-transfers/:requestId/read:', requestId, 'phone:', maskPhone(phone), 'isAdmin:', isAdminUser);

      const requests = await loadShiftTransfers();
      const index = requests.findIndex(r => r.id === requestId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Request not found' });
      }

      if (isAdminUser) {
        requests[index].isReadByAdmin = true;
      } else {
        requests[index].isReadByRecipient = true;
      }

      await saveShiftTransfers(requests);
      res.json({ success: true, request: requests[index] });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== DELETE SHIFT TRANSFER =====
  app.delete('/api/shift-transfers/:requestId', requireAuth, async (req, res) => {
    try {
      const { requestId } = req.params;
      console.log('DELETE /api/shift-transfers:', requestId);

      const requests = await loadShiftTransfers();
      const index = requests.findIndex(r => r.id === requestId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Request not found' });
      }

      requests.splice(index, 1);
      await saveShiftTransfers(requests);

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Shift Transfers API initialized (with multiple acceptances support)');
}

module.exports = { setupShiftTransfersAPI };

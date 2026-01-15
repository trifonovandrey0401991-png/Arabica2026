const fs = require('fs');

const SHIFT_TRANSFERS_FILE = '/var/www/shift-transfers.json';

// Импорт модуля уведомлений
const {
  notifyTransferCreated,
  notifyTransferAccepted,
  notifyTransferRejected,
  notifyTransferApproved,
  notifyTransferDeclined,
} = require('./shift_transfers_notifications');

// Helper functions
function loadShiftTransfers() {
  try {
    if (fs.existsSync(SHIFT_TRANSFERS_FILE)) {
      const data = fs.readFileSync(SHIFT_TRANSFERS_FILE, 'utf8');
      return JSON.parse(data).requests || [];
    }
  } catch (e) {
    console.error('Error loading shift-transfers:', e);
  }
  return [];
}

function saveShiftTransfers(requests) {
  const data = { requests, updatedAt: new Date().toISOString() };
  fs.writeFileSync(SHIFT_TRANSFERS_FILE, JSON.stringify(data, null, 2), 'utf8');
}

// Cleanup expired transfers (older than 30 days with pending status)
function cleanupExpiredTransfers(requests) {
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  return requests.filter(r => {
    const createdAt = new Date(r.createdAt);
    if (createdAt < thirtyDaysAgo && r.status === 'pending') {
      return false;
    }
    return true;
  });
}

function setupShiftTransfersAPI(app) {
  // ===== GET ALL SHIFT TRANSFERS =====
  app.get('/api/shift-transfers', async (req, res) => {
    try {
      console.log('GET /api/shift-transfers');
      const { shopAddress, status, employeeName } = req.query;

      let requests = loadShiftTransfers();

      // Cleanup expired
      const cleanedRequests = cleanupExpiredTransfers(requests);
      if (cleanedRequests.length !== requests.length) {
        saveShiftTransfers(cleanedRequests);
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
  app.get('/api/shift-transfers/employee/:employeeId', async (req, res) => {
    try {
      const { employeeId } = req.params;
      console.log('GET /api/shift-transfers/employee/:employeeId', employeeId);

      let requests = loadShiftTransfers();

      // Cleanup expired
      const cleanedRequests = cleanupExpiredTransfers(requests);
      if (cleanedRequests.length !== requests.length) {
        saveShiftTransfers(cleanedRequests);
        requests = cleanedRequests;
      }

      // Filter: requests where toEmployeeId matches OR it's a broadcast (toEmployeeId is null)
      // AND not sent by this employee themselves
      requests = requests.filter(r =>
        r.fromEmployeeId !== employeeId &&
        (r.toEmployeeId === employeeId || !r.toEmployeeId)
      );

      requests.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, requests });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET EMPLOYEE OUTGOING REQUESTS =====
  app.get('/api/shift-transfers/employee/:employeeId/outgoing', async (req, res) => {
    try {
      const { employeeId } = req.params;
      console.log('GET /api/shift-transfers/employee/:employeeId/outgoing', employeeId);

      let requests = loadShiftTransfers();

      // Filter: requests sent by this employee
      requests = requests.filter(r => r.fromEmployeeId === employeeId);

      requests.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, requests });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET EMPLOYEE UNREAD COUNT =====
  app.get('/api/shift-transfers/employee/:employeeId/unread-count', async (req, res) => {
    try {
      const { employeeId } = req.params;
      console.log('GET /api/shift-transfers/employee/:employeeId/unread-count', employeeId);

      const requests = loadShiftTransfers();

      // Count unread incoming requests
      const count = requests.filter(r =>
        r.fromEmployeeId !== employeeId &&
        (r.toEmployeeId === employeeId || !r.toEmployeeId) &&
        !r.isReadByRecipient &&
        r.status === 'pending'
      ).length;

      res.json({ success: true, count });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET ADMIN REQUESTS =====
  app.get('/api/shift-transfers/admin', async (req, res) => {
    try {
      console.log('GET /api/shift-transfers/admin');

      let requests = loadShiftTransfers();

      // Filter: requests pending admin approval (accepted by employee)
      requests = requests.filter(r => r.status === 'accepted');

      requests.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, requests });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET ADMIN UNREAD COUNT =====
  app.get('/api/shift-transfers/admin/unread-count', async (req, res) => {
    try {
      console.log('GET /api/shift-transfers/admin/unread-count');

      const requests = loadShiftTransfers();

      // Count unread requests pending admin approval
      const count = requests.filter(r =>
        r.status === 'accepted' && !r.isReadByAdmin
      ).length;

      res.json({ success: true, count });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CREATE SHIFT TRANSFER REQUEST =====
  app.post('/api/shift-transfers', async (req, res) => {
    try {
      const transfer = req.body;
      console.log('POST /api/shift-transfers:', transfer.fromEmployeeName, '->', transfer.toEmployeeName || 'всем');

      if (!transfer.fromEmployeeId || !transfer.fromEmployeeName || !transfer.shiftDate) {
        return res.status(400).json({
          success: false,
          error: 'fromEmployeeId, fromEmployeeName, and shiftDate are required'
        });
      }

      const requests = loadShiftTransfers();

      // Generate ID if not provided
      if (!transfer.id) {
        transfer.id = `transfer_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      transfer.createdAt = new Date().toISOString();
      transfer.status = transfer.status || 'pending';
      transfer.isReadByRecipient = false;
      transfer.isReadByAdmin = false;

      requests.push(transfer);
      saveShiftTransfers(requests);

      // ✅ Отправка уведомлений
      try {
        await notifyTransferCreated(transfer);
      } catch (e) {
        console.error('Ошибка отправки уведомлений:', e);
      }

      res.json({ success: true, request: transfer });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET SINGLE SHIFT TRANSFER =====
  app.get('/api/shift-transfers/:requestId', async (req, res) => {
    try {
      const { requestId } = req.params;
      const requests = loadShiftTransfers();
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

  // ===== EMPLOYEE ACCEPTS REQUEST =====
  app.put('/api/shift-transfers/:requestId/accept', async (req, res) => {
    try {
      const { requestId } = req.params;
      const { employeeId, employeeName } = req.body;
      console.log('PUT /api/shift-transfers/:requestId/accept:', requestId, employeeName);

      const requests = loadShiftTransfers();
      const index = requests.findIndex(r => r.id === requestId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Request not found' });
      }

      requests[index].status = 'accepted';
      requests[index].acceptedByEmployeeId = employeeId;
      requests[index].acceptedByEmployeeName = employeeName;
      requests[index].acceptedAt = new Date().toISOString();
      requests[index].isReadByAdmin = false; // Reset for admin notification

      saveShiftTransfers(requests);

      // ✅ Отправка уведомлений
      try {
        await notifyTransferAccepted(requests[index]);
      } catch (e) {
        console.error('Ошибка отправки уведомлений:', e);
      }

      res.json({ success: true, request: requests[index] });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== EMPLOYEE REJECTS REQUEST =====
  app.put('/api/shift-transfers/:requestId/reject', async (req, res) => {
    try {
      const { requestId } = req.params;
      console.log('PUT /api/shift-transfers/:requestId/reject:', requestId);

      const requests = loadShiftTransfers();
      const index = requests.findIndex(r => r.id === requestId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Request not found' });
      }

      requests[index].status = 'rejected';
      requests[index].resolvedAt = new Date().toISOString();

      saveShiftTransfers(requests);

      // ✅ Отправка уведомлений
      try {
        await notifyTransferRejected(requests[index]);
      } catch (e) {
        console.error('Ошибка отправки уведомлений:', e);
      }

      res.json({ success: true, request: requests[index] });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ADMIN APPROVES REQUEST =====
  app.put('/api/shift-transfers/:requestId/approve', async (req, res) => {
    try {
      const { requestId } = req.params;
      console.log('PUT /api/shift-transfers/:requestId/approve:', requestId);

      const requests = loadShiftTransfers();
      const index = requests.findIndex(r => r.id === requestId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Request not found' });
      }

      requests[index].status = 'approved';
      requests[index].resolvedAt = new Date().toISOString();

      saveShiftTransfers(requests);

      // ✅ Отправка уведомлений
      try {
        await notifyTransferApproved(requests[index]);
      } catch (e) {
        console.error('Ошибка отправки уведомлений:', e);
      }

      // TODO: Update work schedule automatically
      // The Flutter app should call work-schedule API to update the schedule

      res.json({ success: true, request: requests[index] });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ADMIN DECLINES REQUEST =====
  app.put('/api/shift-transfers/:requestId/decline', async (req, res) => {
    try {
      const { requestId } = req.params;
      console.log('PUT /api/shift-transfers/:requestId/decline:', requestId);

      const requests = loadShiftTransfers();
      const index = requests.findIndex(r => r.id === requestId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Request not found' });
      }

      requests[index].status = 'declined';
      requests[index].resolvedAt = new Date().toISOString();

      saveShiftTransfers(requests);

      // ✅ Отправка уведомлений
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
  app.put('/api/shift-transfers/:requestId/read', async (req, res) => {
    try {
      const { requestId } = req.params;
      const { isAdmin } = req.body;
      console.log('PUT /api/shift-transfers/:requestId/read:', requestId, 'isAdmin:', isAdmin);

      const requests = loadShiftTransfers();
      const index = requests.findIndex(r => r.id === requestId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Request not found' });
      }

      if (isAdmin) {
        requests[index].isReadByAdmin = true;
      } else {
        requests[index].isReadByRecipient = true;
      }

      saveShiftTransfers(requests);
      res.json({ success: true, request: requests[index] });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== DELETE SHIFT TRANSFER =====
  app.delete('/api/shift-transfers/:requestId', async (req, res) => {
    try {
      const { requestId } = req.params;
      console.log('DELETE /api/shift-transfers:', requestId);

      const requests = loadShiftTransfers();
      const index = requests.findIndex(r => r.id === requestId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Request not found' });
      }

      requests.splice(index, 1);
      saveShiftTransfers(requests);

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Shift Transfers API initialized');
}

module.exports = { setupShiftTransfersAPI };

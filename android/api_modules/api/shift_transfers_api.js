const fs = require('fs');
const path = require('path');

const SHIFT_TRANSFERS_FILE = '/var/www/shift-transfers.json';

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

// Cleanup expired transfers (older than 30 days)
function cleanupExpiredTransfers(requests) {
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  return requests.filter(r => {
    const createdAt = new Date(r.createdAt);
    if (createdAt < thirtyDaysAgo && r.status === 'pending') {
      return false; // Remove expired pending requests
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
          r.fromEmployee === employeeName || r.toEmployee === employeeName
        );
      }

      requests.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, requests });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CREATE SHIFT TRANSFER REQUEST =====
  app.post('/api/shift-transfers', async (req, res) => {
    try {
      const transfer = req.body;
      console.log('POST /api/shift-transfers:', transfer.fromEmployee, '->', transfer.toEmployee);

      if (!transfer.fromEmployee || !transfer.toEmployee || !transfer.date) {
        return res.status(400).json({
          success: false,
          error: 'fromEmployee, toEmployee, and date are required'
        });
      }

      const requests = loadShiftTransfers();

      if (!transfer.id) {
        transfer.id = `transfer_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      transfer.createdAt = new Date().toISOString();
      transfer.status = transfer.status || 'pending';

      requests.push(transfer);
      saveShiftTransfers(requests);

      res.json({ success: true, transfer });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET SINGLE SHIFT TRANSFER =====
  app.get('/api/shift-transfers/:transferId', async (req, res) => {
    try {
      const { transferId } = req.params;
      const requests = loadShiftTransfers();
      const transfer = requests.find(r => r.id === transferId);

      if (transfer) {
        res.json({ success: true, transfer });
      } else {
        res.status(404).json({ success: false, error: 'Transfer not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== UPDATE SHIFT TRANSFER (approve/reject) =====
  app.put('/api/shift-transfers/:transferId', async (req, res) => {
    try {
      const { transferId } = req.params;
      const updates = req.body;
      console.log('PUT /api/shift-transfers:', transferId, updates.status);

      const requests = loadShiftTransfers();
      const index = requests.findIndex(r => r.id === transferId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Transfer not found' });
      }

      requests[index] = {
        ...requests[index],
        ...updates,
        updatedAt: new Date().toISOString()
      };

      saveShiftTransfers(requests);
      res.json({ success: true, transfer: requests[index] });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== DELETE SHIFT TRANSFER =====
  app.delete('/api/shift-transfers/:transferId', async (req, res) => {
    try {
      const { transferId } = req.params;
      console.log('DELETE /api/shift-transfers:', transferId);

      const requests = loadShiftTransfers();
      const index = requests.findIndex(r => r.id === transferId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Transfer not found' });
      }

      requests.splice(index, 1);
      saveShiftTransfers(requests);

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== APPROVE SHIFT TRANSFER =====
  app.post('/api/shift-transfers/:transferId/approve', async (req, res) => {
    try {
      const { transferId } = req.params;
      const { approvedBy } = req.body;
      console.log('POST /api/shift-transfers/:transferId/approve:', transferId);

      const requests = loadShiftTransfers();
      const index = requests.findIndex(r => r.id === transferId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Transfer not found' });
      }

      requests[index].status = 'approved';
      requests[index].approvedBy = approvedBy;
      requests[index].approvedAt = new Date().toISOString();

      saveShiftTransfers(requests);
      res.json({ success: true, transfer: requests[index] });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== REJECT SHIFT TRANSFER =====
  app.post('/api/shift-transfers/:transferId/reject', async (req, res) => {
    try {
      const { transferId } = req.params;
      const { rejectedBy, reason } = req.body;
      console.log('POST /api/shift-transfers/:transferId/reject:', transferId);

      const requests = loadShiftTransfers();
      const index = requests.findIndex(r => r.id === transferId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Transfer not found' });
      }

      requests[index].status = 'rejected';
      requests[index].rejectedBy = rejectedBy;
      requests[index].rejectionReason = reason;
      requests[index].rejectedAt = new Date().toISOString();

      saveShiftTransfers(requests);
      res.json({ success: true, transfer: requests[index] });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Shift Transfers API initialized');
}

module.exports = { setupShiftTransfersAPI };

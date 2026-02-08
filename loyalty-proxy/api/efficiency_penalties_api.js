/**
 * Efficiency Penalties API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const EFFICIENCY_PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Ensure directory exists
async function ensureDir() {
  if (!(await fileExists(EFFICIENCY_PENALTIES_DIR))) {
    await fsp.mkdir(EFFICIENCY_PENALTIES_DIR, { recursive: true });
  }
}

// Get month key from date (YYYY-MM)
function getMonthKey(date) {
  if (!date) {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  }
  return date.substring(0, 7);
}

// Generate unique ID
function generateId() {
  return `penalty_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

// Load penalties for a month
async function loadMonthPenalties(monthKey) {
  await ensureDir();
  const filePath = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);

  if (await fileExists(filePath)) {
    try {
      const content = await fsp.readFile(filePath, 'utf8');
      return JSON.parse(content);
    } catch (e) {
      console.error(`Error reading penalties for ${monthKey}:`, e);
      return { monthKey, penalties: [] };
    }
  }
  return { monthKey, penalties: [] };
}

// Save penalties for a month
async function saveMonthPenalties(monthKey, data) {
  await ensureDir();
  const filePath = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);
  data.updatedAt = new Date().toISOString();
  await fsp.writeFile(filePath, JSON.stringify(data, null, 2), 'utf8');
}

// Add penalty
async function addPenalty(penalty) {
  const monthKey = getMonthKey(penalty.date);
  const data = await loadMonthPenalties(monthKey);

  if (!penalty.id) {
    penalty.id = generateId();
  }
  penalty.createdAt = new Date().toISOString();

  data.penalties.push(penalty);
  await saveMonthPenalties(monthKey, data);

  return penalty;
}

// Check if penalty already exists (to avoid duplicates)
async function penaltyExists(date, shiftType, shopAddress, type) {
  const monthKey = getMonthKey(date);
  const data = await loadMonthPenalties(monthKey);

  return data.penalties.some(p =>
    p.date === date &&
    p.shiftType === shiftType &&
    p.shopAddress === shopAddress &&
    p.type === type
  );
}

function setupEfficiencyPenaltiesAPI(app) {
  // GET /api/efficiency-penalties - Get penalties for a period
  app.get('/api/efficiency-penalties', async (req, res) => {
    try {
      const { month, shopAddress, employeeName, type, fromDate, toDate } = req.query;

      console.log('GET /api/efficiency-penalties', { month, shopAddress, employeeName, type });

      let allPenalties = [];

      if (month) {
        // Load specific month
        const data = await loadMonthPenalties(month);
        allPenalties = data.penalties || [];
      } else if (fromDate && toDate) {
        // Load range of months
        const startMonth = getMonthKey(fromDate);
        const endMonth = getMonthKey(toDate);

        // Simple approach: load all months between start and end
        const startDate = new Date(fromDate);
        const endDate = new Date(toDate);

        const months = new Set();
        const current = new Date(startDate);
        while (current <= endDate) {
          months.add(getMonthKey(current.toISOString().split('T')[0]));
          current.setMonth(current.getMonth() + 1);
        }

        for (const m of months) {
          const data = await loadMonthPenalties(m);
          allPenalties.push(...(data.penalties || []));
        }

        // Filter by exact date range
        allPenalties = allPenalties.filter(p => p.date >= fromDate && p.date <= toDate);
      } else {
        // Default: current month
        const data = await loadMonthPenalties(getMonthKey());
        allPenalties = data.penalties || [];
      }

      // Apply filters
      if (shopAddress) {
        allPenalties = allPenalties.filter(p => p.shopAddress === shopAddress || p.entityId === shopAddress);
      }
      if (employeeName) {
        allPenalties = allPenalties.filter(p => p.entityId === employeeName || p.employeeName === employeeName);
      }
      if (type) {
        allPenalties = allPenalties.filter(p => p.type === type);
      }

      // Sort by date descending
      allPenalties.sort((a, b) => new Date(b.date) - new Date(a.date));

      res.json({ success: true, penalties: allPenalties });
    } catch (error) {
      console.error('Error getting efficiency penalties:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/efficiency-penalties - Create a penalty
  app.post('/api/efficiency-penalties', async (req, res) => {
    try {
      const penalty = req.body;
      console.log('POST /api/efficiency-penalties:', penalty);

      // Validate required fields
      if (!penalty.type || !penalty.entityId || !penalty.date || penalty.points === undefined) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: type, entityId, date, points'
        });
      }

      // Check for duplicates if it's a shift penalty
      if (penalty.category === 'shift_penalty') {
        if (await penaltyExists(penalty.date, penalty.shiftType, penalty.shopAddress, penalty.type)) {
          return res.json({
            success: true,
            duplicate: true,
            message: 'Penalty already exists for this shift'
          });
        }
      }

      const savedPenalty = await addPenalty(penalty);

      res.json({ success: true, penalty: savedPenalty });
    } catch (error) {
      console.error('Error creating efficiency penalty:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/efficiency-penalties/bulk - Create multiple penalties
  app.post('/api/efficiency-penalties/bulk', async (req, res) => {
    try {
      const { penalties } = req.body;
      console.log('POST /api/efficiency-penalties/bulk:', penalties?.length || 0, 'penalties');

      if (!penalties || !Array.isArray(penalties)) {
        return res.status(400).json({
          success: false,
          error: 'penalties array is required'
        });
      }

      const savedPenalties = [];
      const skipped = [];

      for (const penalty of penalties) {
        // Check for duplicates
        if (penalty.category === 'shift_penalty') {
          if (await penaltyExists(penalty.date, penalty.shiftType, penalty.shopAddress, penalty.type)) {
            skipped.push(penalty);
            continue;
          }
        }

        const saved = await addPenalty(penalty);
        savedPenalties.push(saved);
      }

      console.log(`  Created: ${savedPenalties.length}, Skipped: ${skipped.length}`);

      res.json({
        success: true,
        created: savedPenalties.length,
        skipped: skipped.length,
        penalties: savedPenalties
      });
    } catch (error) {
      console.error('Error creating bulk efficiency penalties:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/efficiency-penalties/:id - Delete a penalty
  app.delete('/api/efficiency-penalties/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const { month } = req.query;

      console.log('DELETE /api/efficiency-penalties:', id);

      // Need to search in the specified month or all months
      const searchMonths = month ? [month] : [];

      if (!month) {
        // List all month files
        await ensureDir();
        const files = (await fsp.readdir(EFFICIENCY_PENALTIES_DIR)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          searchMonths.push(file.replace('.json', ''));
        }
      }

      for (const m of searchMonths) {
        const data = await loadMonthPenalties(m);
        const index = data.penalties.findIndex(p => p.id === id);

        if (index !== -1) {
          data.penalties.splice(index, 1);
          await saveMonthPenalties(m, data);
          return res.json({ success: true });
        }
      }

      res.status(404).json({ success: false, error: 'Penalty not found' });
    } catch (error) {
      console.error('Error deleting efficiency penalty:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/efficiency-penalties/summary - Get summary by shop or employee
  app.get('/api/efficiency-penalties/summary', async (req, res) => {
    try {
      const { month, groupBy } = req.query;
      const monthKey = month || getMonthKey();

      console.log('GET /api/efficiency-penalties/summary', { monthKey, groupBy });

      const data = await loadMonthPenalties(monthKey);
      const penalties = data.penalties || [];

      const summary = {};

      for (const penalty of penalties) {
        const key = groupBy === 'employee'
          ? (penalty.type === 'employee' ? penalty.entityId : null)
          : penalty.shopAddress;

        if (!key) continue;

        if (!summary[key]) {
          summary[key] = {
            entityId: key,
            totalPoints: 0,
            count: 0,
            penalties: []
          };
        }

        summary[key].totalPoints += penalty.points;
        summary[key].count++;
        summary[key].penalties.push(penalty);
      }

      const result = Object.values(summary).sort((a, b) => a.totalPoints - b.totalPoints);

      res.json({ success: true, summary: result, month: monthKey });
    } catch (error) {
      console.error('Error getting efficiency penalties summary:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Efficiency Penalties API initialized');
}

module.exports = { setupEfficiencyPenaltiesAPI, addPenalty, penaltyExists, loadMonthPenalties };

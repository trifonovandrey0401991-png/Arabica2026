const fs = require('fs');
const path = require('path');

// Directories
const TEST_RESULTS_DIR = '/var/www/test-results';
const EFFICIENCY_PENALTIES_DIR = '/var/www/efficiency-penalties';
const POINTS_SETTINGS_DIR = '/var/www/points-settings';
const PENALTY_STATE_DIR = '/var/www/test-penalty-state';
const STATE_FILE = path.join(PENALTY_STATE_DIR, 'processed.json');

// ============================================
// Helper: Load JSON file safely
// ============================================
function loadJsonFile(filePath, defaultValue) {
  if (!fs.existsSync(filePath)) {
    return defaultValue;
  }
  try {
    const data = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(data);
  } catch (e) {
    console.error(`Error loading JSON from ${filePath}:`, e.message);
    return defaultValue;
  }
}

// ============================================
// State Management
// ============================================
function loadState() {
  const defaultState = {
    lastCheckTime: null,
    processedTests: []
  };

  if (!fs.existsSync(STATE_FILE)) {
    return defaultState;
  }

  try {
    const data = fs.readFileSync(STATE_FILE, 'utf8');
    return JSON.parse(data);
  } catch (e) {
    console.error('Error loading test penalty state:', e.message);
    return defaultState;
  }
}

function saveState(state) {
  try {
    if (!fs.existsSync(PENALTY_STATE_DIR)) {
      fs.mkdirSync(PENALTY_STATE_DIR, { recursive: true });
    }

    // Cleanup: keep only last 1000 IDs to prevent unbounded growth
    state.processedTests = state.processedTests.slice(-1000);
    state.lastCheckTime = new Date().toISOString();

    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2), 'utf8');
  } catch (e) {
    console.error('Error saving test penalty state:', e.message);
  }
}

// ============================================
// Assign Test Points
// ============================================
async function assignTestPointsFromResult(result, settings) {
  try {
    const now = new Date(result.completedAt || Date.now());
    const today = now.toISOString().split('T')[0];
    const monthKey = today.substring(0, 7); // YYYY-MM

    // Calculate points using linear interpolation
    const { score, totalQuestions } = result;
    let points = 0;

    if (totalQuestions === 0) {
      points = 0;
    } else if (score <= 0) {
      points = settings.minPoints;
    } else if (score >= totalQuestions) {
      points = settings.maxPoints;
    } else if (score <= settings.zeroThreshold) {
      // Interpolate from minPoints to 0
      points = settings.minPoints + (0 - settings.minPoints) * (score / settings.zeroThreshold);
    } else {
      // Interpolate from 0 to maxPoints
      const range = totalQuestions - settings.zeroThreshold;
      points = (settings.maxPoints - 0) * ((score - settings.zeroThreshold) / range);
    }

    // Round to 2 decimals
    points = Math.round(points * 100) / 100;

    // Check deduplication
    const sourceId = `test_${result.id}`;
    if (!fs.existsSync(EFFICIENCY_PENALTIES_DIR)) {
      fs.mkdirSync(EFFICIENCY_PENALTIES_DIR, { recursive: true });
    }

    const penaltiesFile = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);
    let penalties = loadJsonFile(penaltiesFile, []);

    const exists = penalties.some(p => p.sourceId === sourceId);
    if (exists) {
      console.log(`   ⏭️  Points already assigned for test ${result.id}, skipping`);
      return { success: true, skipped: true };
    }

    // Create entry
    const entry = {
      id: `test_pts_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type: 'employee',
      entityId: result.employeePhone,
      entityName: result.employeeName,
      shopAddress: result.shopAddress || '',
      employeeName: result.employeeName,
      category: points >= 0 ? 'test_bonus' : 'test_penalty',
      categoryName: 'Прохождение теста',
      date: today,
      points: points,
      reason: `Тест: ${score}/${totalQuestions} правильных (${Math.round((score/totalQuestions)*100)}%)`,
      sourceId: sourceId,
      sourceType: 'test_result',
      createdAt: now.toISOString()
    };

    penalties.push(entry);
    fs.writeFileSync(penaltiesFile, JSON.stringify(penalties, null, 2), 'utf8');

    console.log(`   ✅ Test points assigned: ${result.employeeName} (${points >= 0 ? '+' : ''}${points} points)`);
    return { success: true, points: points };
  } catch (error) {
    console.error(`   ❌ Error assigning test points for ${result.id}:`, error.message);
    return { success: false, error: error.message };
  }
}

// ============================================
// Process Test Results
// ============================================
async function processTestResults() {
  console.log('\n🔍 [TEST SCHEDULER] Starting test results processing...');

  try {
    const state = loadState();

    // Load settings
    const settingsFile = path.join(POINTS_SETTINGS_DIR, 'test_points_settings.json');
    const settings = loadJsonFile(settingsFile, {
      minPoints: -2,
      zeroThreshold: 15,
      maxPoints: 1
    });

    console.log(`   📋 Settings: minPoints=${settings.minPoints}, zeroThreshold=${settings.zeroThreshold}, maxPoints=${settings.maxPoints}`);

    // Load all test results
    if (!fs.existsSync(TEST_RESULTS_DIR)) {
      console.log('   ⚠️  Test results directory does not exist');
      return;
    }

    const files = fs.readdirSync(TEST_RESULTS_DIR).filter(f => f.endsWith('.json'));
    console.log(`   📁 Found ${files.length} test result files`);

    let processed = 0;
    let skipped = 0;
    let errors = 0;

    for (const file of files) {
      try {
        const filePath = path.join(TEST_RESULTS_DIR, file);
        const result = JSON.parse(fs.readFileSync(filePath, 'utf8'));

        // Skip if already processed
        if (state.processedTests.includes(result.id)) {
          skipped++;
          continue;
        }

        // Assign points
        const assignResult = await assignTestPointsFromResult(result, settings);

        if (assignResult.success) {
          if (!assignResult.skipped) {
            processed++;
          } else {
            skipped++;
          }
          // Mark as processed
          state.processedTests.push(result.id);
        } else {
          errors++;
        }
      } catch (error) {
        console.error(`   ❌ Error processing ${file}:`, error.message);
        errors++;
      }
    }

    // Save state
    saveState(state);

    console.log(`\n✅ [TEST SCHEDULER] Processing complete:`);
    console.log(`   📊 Processed: ${processed}`);
    console.log(`   ⏭️  Skipped: ${skipped}`);
    console.log(`   ❌ Errors: ${errors}`);
  } catch (error) {
    console.error('❌ [TEST SCHEDULER] Fatal error:', error.message);
  }
}

// ============================================
// Start Scheduler
// ============================================
function startScheduler() {
  console.log('🚀 [TEST SCHEDULER] Starting test results penalty scheduler...');
  console.log('   ⏰ Running every hour');

  // Run immediately on start
  processTestResults();

  // Then run every hour
  setInterval(() => {
    processTestResults();
  }, 60 * 60 * 1000); // 1 hour
}

// Export for use in index.js
module.exports = { startScheduler, processTestResults };

// If run directly
if (require.main === module) {
  startScheduler();
}

/**
 * Wave 7b Migration: Medium-complexity modules → PostgreSQL
 *
 * Migrates:
 *   1. shop-coordinates/   → shop_coordinates (NEW TABLE)
 *   2. test-questions/     → test_questions (existing, data JSONB)
 *   3. test-results/       → test_results (existing, data JSONB)
 *   4. test-settings.json  → app_settings key='test_settings'
 *   5. shop-managers.json  → app_settings key='shop_managers'
 *   6. withdrawals/        → withdrawals (ALTER: +data JSONB)
 *   7. shop-products/      → shop_products (NEW TABLE)
 *   8. referrals-viewed.json → app_settings key='referrals_viewed'
 *   9. auth-sessions/      → auth_sessions (ALTER: +data JSONB, +updated_at, UNIQUE phone)
 *  10. auth-pins/          → auth_pins (ALTER: +data JSONB, +updated_at)
 *
 * Run: node scripts/migrate_wave7b_medium.js
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

async function main() {
  console.log('=== Wave 7b Migration: Medium-complexity modules ===\n');

  await patchSchema();

  const stats = {
    shopCoordinates: 0,
    testQuestions: 0,
    testResults: 0,
    testSettings: 0,
    shopManagers: 0,
    withdrawals: 0,
    shopProducts: 0,
    referralsViewed: 0,
    authSessions: 0,
    authPins: 0,
    errors: 0
  };

  await migrateJsonbDir('shop-coordinates', 'shop_coordinates', stats, 'shopCoordinates');
  await migrateJsonbDir('test-questions', 'test_questions', stats, 'testQuestions');
  await migrateJsonbDir('test-results', 'test_results', stats, 'testResults');
  await migrateSingletonConfig('test-settings.json', 'test_settings', stats, 'testSettings');
  await migrateSingletonConfig('shop-managers.json', 'shop_managers', stats, 'shopManagers');
  await migrateWithdrawals(stats);
  await migrateJsonbDir('shop-products', 'shop_products', stats, 'shopProducts');
  await migrateSingletonConfig('referrals-viewed.json', 'referrals_viewed', stats, 'referralsViewed');
  await migrateAuthSessions(stats);
  await migrateAuthPins(stats);

  console.log('\n=== SUMMARY ===');
  for (const [key, val] of Object.entries(stats)) {
    if (key !== 'errors') console.log(`  ${key}: ${val}`);
  }
  console.log(`  Errors: ${stats.errors}`);
  const total = Object.values(stats).reduce((a, b) => a + b, 0) - stats.errors;
  console.log(`  Total records: ${total}`);

  await db.close();
  process.exit(stats.errors > 0 ? 1 : 0);
}

// ============================================
// Schema patches
// ============================================

async function patchSchema() {
  console.log('Phase 0: Schema patches...');

  const patches = [
    // New tables
    `CREATE TABLE IF NOT EXISTS shop_coordinates (
      id TEXT PRIMARY KEY,
      data JSONB NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )`,

    `CREATE TABLE IF NOT EXISTS shop_products (
      id TEXT PRIMARY KEY,
      data JSONB NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )`,

    // Add missing updated_at to test_questions and test_results
    `ALTER TABLE test_questions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW()`,
    `ALTER TABLE test_results ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW()`,

    // Add data JSONB column to auth_pins (PK is phone — already correct)
    `ALTER TABLE auth_pins ADD COLUMN IF NOT EXISTS data JSONB`,
    `ALTER TABLE auth_pins ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW()`,

    // Add data JSONB + updated_at to auth_sessions
    `ALTER TABLE auth_sessions ADD COLUMN IF NOT EXISTS data JSONB`,
    `ALTER TABLE auth_sessions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW()`,

    // Add data JSONB to withdrawals
    `ALTER TABLE withdrawals ADD COLUMN IF NOT EXISTS data JSONB`,

    // Make phone UNIQUE in auth_sessions for upsert (one session per phone)
    // Using CREATE UNIQUE INDEX which is IF NOT EXISTS safe
    `CREATE UNIQUE INDEX IF NOT EXISTS auth_sessions_phone_uq ON auth_sessions(phone)`
  ];

  let applied = 0;
  for (const sql of patches) {
    try {
      await db.query(sql);
      applied++;
    } catch (e) {
      if (!e.message.includes('already exists')) {
        console.warn(`  Patch warning: ${e.message}`);
      } else {
        applied++;
      }
    }
  }
  console.log(`  Applied ${applied}/${patches.length} schema patches`);
}

// ============================================
// Generic JSONB directory migration
// ============================================

async function migrateJsonbDir(dirName, tableName, stats, statsKey) {
  console.log(`\nMigrating ${dirName}/ → ${tableName}...`);

  const dir = path.join(DATA_DIR, dirName);
  let files;
  try {
    files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  } catch (e) {
    console.log(`  No ${dirName} directory: ${e.message}`);
    return;
  }

  console.log(`  Found ${files.length} files`);

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const data = JSON.parse(content);
      const id = data.id || file.replace('.json', '');

      await db.upsert(tableName, {
        id: id,
        data: data,
        created_at: data.createdAt || data.created_at || new Date().toISOString(),
        updated_at: data.updatedAt || data.updated_at || new Date().toISOString()
      });
      stats[statsKey]++;
    } catch (e) {
      if (!e.message.includes('duplicate key')) {
        console.error(`  Error ${file}: ${e.message}`);
        stats.errors++;
      } else {
        stats[statsKey]++;
      }
    }
  }

  console.log(`  Done: ${stats[statsKey]} records`);
}

// ============================================
// Singleton config → app_settings
// ============================================

async function migrateSingletonConfig(fileName, settingsKey, stats, statsKey) {
  console.log(`\nMigrating ${fileName} → app_settings key='${settingsKey}'...`);

  const filePath = path.join(DATA_DIR, fileName);
  try {
    const content = await fsp.readFile(filePath, 'utf8');
    const data = JSON.parse(content);

    await db.upsert('app_settings', {
      key: settingsKey,
      data: data,
      updated_at: new Date().toISOString()
    }, 'key');

    stats[statsKey] = 1;
    console.log(`  Done: 1 record`);
  } catch (e) {
    if (e.code === 'ENOENT') {
      console.log(`  File not found: ${fileName} (skipped)`);
    } else {
      console.error(`  Error: ${e.message}`);
      stats.errors++;
    }
  }
}

// ============================================
// Withdrawals (explicit columns table + new data JSONB)
// ============================================

async function migrateWithdrawals(stats) {
  console.log('\nMigrating withdrawals/ → withdrawals...');

  const dir = path.join(DATA_DIR, 'withdrawals');
  let files;
  try {
    files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  } catch (e) {
    console.log(`  No withdrawals directory: ${e.message}`);
    return;
  }

  console.log(`  Found ${files.length} files`);

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const w = JSON.parse(content);
      const id = w.id || file.replace('.json', '');

      // Table has explicit columns + new data JSONB
      // Populate both for compatibility
      await db.upsert('withdrawals', {
        id: id,
        data: w,
        shop_address: w.shopAddress || null,
        employee_name: w.employeeName || null,
        employee_id: w.employeeId || null,
        type: w.type || null,
        total_amount: w.totalAmount || null,
        expenses: JSON.stringify(w.expenses || []),
        admin_name: w.adminName || null,
        confirmed: w.confirmed === true,
        category: w.category || null,
        transfer_direction: w.transferDirection || null,
        confirmed_at: w.confirmedAt || null,
        created_at: w.createdAt || new Date().toISOString()
      });
      stats.withdrawals++;
    } catch (e) {
      if (!e.message.includes('duplicate key')) {
        console.error(`  Error ${file}: ${e.message}`);
        stats.errors++;
      } else {
        stats.withdrawals++;
      }
    }
  }

  console.log(`  Done: ${stats.withdrawals} records`);
}

// ============================================
// Auth sessions (SERIAL PK table + new data JSONB, upsert on phone)
// ============================================

async function migrateAuthSessions(stats) {
  console.log('\nMigrating auth-sessions/ → auth_sessions...');

  const dir = path.join(DATA_DIR, 'auth-sessions');
  let files;
  try {
    files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  } catch (e) {
    console.log(`  No auth-sessions directory: ${e.message}`);
    return;
  }

  console.log(`  Found ${files.length} files`);

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const session = JSON.parse(content);
      const phone = file.replace('.json', '');

      // Convert Unix ms timestamps to ISO strings
      let createdAt = session.createdAt;
      if (typeof createdAt === 'number' || (typeof createdAt === 'string' && /^\d{10,13}$/.test(createdAt))) {
        createdAt = new Date(Number(createdAt)).toISOString();
      }
      createdAt = createdAt || new Date().toISOString();

      // Use raw query for INSERT ON CONFLICT on phone (unique index)
      // since the PK is id SERIAL, we upsert on phone unique index
      await db.query(
        `INSERT INTO auth_sessions (phone, session_token, employee_id, is_admin, data, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (phone) DO UPDATE SET
           session_token = EXCLUDED.session_token,
           employee_id = EXCLUDED.employee_id,
           is_admin = EXCLUDED.is_admin,
           data = EXCLUDED.data,
           updated_at = EXCLUDED.updated_at`,
        [
          phone,
          session.sessionToken || '',
          session.employeeId || null,
          session.isAdmin === true,
          JSON.stringify(session),
          createdAt,
          new Date().toISOString()
        ]
      );
      stats.authSessions++;
    } catch (e) {
      if (!e.message.includes('duplicate key')) {
        console.error(`  Error ${file}: ${e.message}`);
        stats.errors++;
      } else {
        stats.authSessions++;
      }
    }
  }

  console.log(`  Done: ${stats.authSessions} records`);
}

// ============================================
// Auth pins (phone PK + new data JSONB)
// ============================================

async function migrateAuthPins(stats) {
  console.log('\nMigrating auth-pins/ → auth_pins...');

  const dir = path.join(DATA_DIR, 'auth-pins');
  let files;
  try {
    files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  } catch (e) {
    console.log(`  No auth-pins directory: ${e.message}`);
    return;
  }

  console.log(`  Found ${files.length} files`);

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const pin = JSON.parse(content);
      const phone = file.replace('.json', '');

      // Populate both explicit columns and data JSONB
      await db.upsert('auth_pins', {
        phone: phone,
        pin_hash: pin.pinHash || pin.pin_hash || '',
        hash_type: pin.hashType || pin.hash_type || 'sha256',
        salt: pin.salt || null,
        failed_attempts: pin.failedAttempts || pin.failed_attempts || 0,
        locked_until: pin.lockedUntil || pin.locked_until || null,
        data: pin,
        updated_at: new Date().toISOString()
      }, 'phone');
      stats.authPins++;
    } catch (e) {
      if (!e.message.includes('duplicate key')) {
        console.error(`  Error ${file}: ${e.message}`);
        stats.errors++;
      } else {
        stats.authPins++;
      }
    }
  }

  console.log(`  Done: ${stats.authPins} records`);
}

// ============================================
// RUN
// ============================================

main().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});

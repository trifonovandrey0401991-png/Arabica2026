/**
 * Wave 7c Migration: Complex modules → PostgreSQL
 *
 * Migrates:
 *   1. master-catalog/products.json     → app_settings key='master_catalog_products'
 *   2. master-catalog/mappings.json     → app_settings key='master_catalog_mappings'
 *   3. master-catalog/pending-codes.json → app_settings key='master_catalog_pending_codes'
 *   4. product-questions/              → product_questions (existing table)
 *   5. product-question-dialogs/       → product_question_dialogs (NEW TABLE)
 *   6. loyalty-gamification/settings.json → app_settings key='loyalty_gamification_settings'
 *   7. loyalty-gamification/client-prizes/ → fortune_wheel_results
 *   8. loyalty-gamification/wheel-history/ → fortune_wheel_results
 *   9. employee-ratings/               → employee_ratings (existing table)
 *  10. fortune-wheel/settings.json     → app_settings key='fortune_wheel_settings'
 *  11. fortune-wheel/spins/            → app_settings key='fortune_wheel_spins_YYYY-MM'
 *  12. fortune-wheel/history/          → app_settings key='fortune_wheel_history_YYYY-MM'
 *
 * Run: node scripts/migrate_wave7c_complex.js
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

async function main() {
  console.log('=== Wave 7c Migration: Complex modules ===\n');

  await patchSchema();

  const stats = {
    masterProducts: 0, masterMappings: 0, masterPending: 0,
    productQuestions: 0, productDialogs: 0,
    gamificationSettings: 0, clientPrizes: 0, wheelHistory: 0,
    employeeRatings: 0,
    fortuneSettings: 0, fortuneSpins: 0, fortuneHistory: 0,
    errors: 0
  };

  // Master catalog (3 singletons)
  await migrateSingletonConfig('master-catalog/products.json', 'master_catalog_products', stats, 'masterProducts');
  await migrateSingletonConfig('master-catalog/mappings.json', 'master_catalog_mappings', stats, 'masterMappings');
  await migrateSingletonConfig('master-catalog/pending-codes.json', 'master_catalog_pending_codes', stats, 'masterPending');

  // Product questions
  await migrateJsonbDir('product-questions', 'product_questions', stats, 'productQuestions');
  await migrateJsonbDir('product-question-dialogs', 'product_question_dialogs', stats, 'productDialogs');

  // Loyalty gamification
  await migrateSingletonConfig('loyalty-gamification/settings.json', 'loyalty_gamification_settings', stats, 'gamificationSettings');
  await migrateClientPrizes(stats);
  await migrateMonthlyFiles('loyalty-gamification/wheel-history', 'fortune_wheel_results', stats, 'wheelHistory');

  // Employee ratings
  await migrateMonthlyRatings(stats);

  // Fortune wheel
  await migrateSingletonConfig('fortune-wheel/settings.json', 'fortune_wheel_settings', stats, 'fortuneSettings');
  await migrateMonthlyToAppSettings('fortune-wheel/spins', 'fortune_wheel_spins', stats, 'fortuneSpins');
  await migrateMonthlyToAppSettings('fortune-wheel/history', 'fortune_wheel_history', stats, 'fortuneHistory');

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
    `CREATE TABLE IF NOT EXISTS product_question_dialogs (
      id TEXT PRIMARY KEY,
      data JSONB NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )`,
    // Add updated_at to product_questions if missing
    `ALTER TABLE product_questions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW()`
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
        created_at: data.createdAt || data.timestamp || new Date().toISOString(),
        updated_at: data.updatedAt || new Date().toISOString()
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

async function migrateSingletonConfig(filePath, settingsKey, stats, statsKey) {
  console.log(`\nMigrating ${filePath} → app_settings key='${settingsKey}'...`);

  const fullPath = path.join(DATA_DIR, filePath);
  try {
    const content = await fsp.readFile(fullPath, 'utf8');
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
      console.log(`  File not found: ${filePath} (skipped)`);
    } else {
      console.error(`  Error: ${e.message}`);
      stats.errors++;
    }
  }
}

// ============================================
// Client prizes → fortune_wheel_results
// ============================================

async function migrateClientPrizes(stats) {
  console.log('\nMigrating loyalty-gamification/client-prizes/ → fortune_wheel_results...');

  const dir = path.join(DATA_DIR, 'loyalty-gamification', 'client-prizes');
  let files;
  try {
    files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  } catch (e) {
    console.log(`  No client-prizes directory: ${e.message}`);
    return;
  }

  console.log(`  Found ${files.length} files`);

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const prize = JSON.parse(content);

      await db.query(
        'INSERT INTO fortune_wheel_results (client_phone, data, created_at) VALUES ($1, $2, $3)',
        [prize.clientPhone || null, prize, prize.createdAt || new Date().toISOString()]
      );
      stats.clientPrizes++;
    } catch (e) {
      if (!e.message.includes('duplicate key')) {
        console.error(`  Error ${file}: ${e.message}`);
        stats.errors++;
      } else {
        stats.clientPrizes++;
      }
    }
  }

  console.log(`  Done: ${stats.clientPrizes} records`);
}

// ============================================
// Monthly files → fortune_wheel_results (for wheel history)
// ============================================

async function migrateMonthlyFiles(dirName, tableName, stats, statsKey) {
  console.log(`\nMigrating ${dirName}/ → ${tableName}...`);

  const dir = path.join(DATA_DIR, dirName);
  let files;
  try {
    files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  } catch (e) {
    console.log(`  No ${dirName} directory: ${e.message}`);
    return;
  }

  console.log(`  Found ${files.length} monthly files`);

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const data = JSON.parse(content);

      // Monthly file is an array of spin records
      if (Array.isArray(data)) {
        for (const record of data) {
          await db.query(
            'INSERT INTO fortune_wheel_results (client_phone, data, created_at) VALUES ($1, $2, $3)',
            [record.clientPhone || null, record, record.timestamp || new Date().toISOString()]
          );
          stats[statsKey]++;
        }
      }
    } catch (e) {
      console.error(`  Error ${file}: ${e.message}`);
      stats.errors++;
    }
  }

  console.log(`  Done: ${stats[statsKey]} records`);
}

// ============================================
// Employee ratings (monthly)
// ============================================

async function migrateMonthlyRatings(stats) {
  console.log('\nMigrating employee-ratings/ → employee_ratings...');

  const dir = path.join(DATA_DIR, 'employee-ratings');
  let files;
  try {
    files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  } catch (e) {
    console.log(`  No employee-ratings directory: ${e.message}`);
    return;
  }

  console.log(`  Found ${files.length} monthly files`);

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const data = JSON.parse(content);
      const monthKey = file.replace('.json', '');

      await db.upsert('employee_ratings', {
        id: monthKey,
        data: data,
        updated_at: data.calculatedAt || new Date().toISOString()
      });
      stats.employeeRatings++;
    } catch (e) {
      if (!e.message.includes('duplicate key')) {
        console.error(`  Error ${file}: ${e.message}`);
        stats.errors++;
      } else {
        stats.employeeRatings++;
      }
    }
  }

  console.log(`  Done: ${stats.employeeRatings} records`);
}

// ============================================
// Monthly files → app_settings (for spins/history)
// ============================================

async function migrateMonthlyToAppSettings(dirName, keyPrefix, stats, statsKey) {
  console.log(`\nMigrating ${dirName}/ → app_settings key='${keyPrefix}_YYYY-MM'...`);

  const dir = path.join(DATA_DIR, dirName);
  let files;
  try {
    files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  } catch (e) {
    console.log(`  No ${dirName} directory: ${e.message}`);
    return;
  }

  console.log(`  Found ${files.length} monthly files`);

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const data = JSON.parse(content);
      const monthKey = file.replace('.json', '');

      await db.upsert('app_settings', {
        key: `${keyPrefix}_${monthKey}`,
        data: data,
        updated_at: new Date().toISOString()
      }, 'key');
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
// RUN
// ============================================

main().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});

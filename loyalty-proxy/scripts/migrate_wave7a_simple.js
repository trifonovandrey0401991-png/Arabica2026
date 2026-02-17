/**
 * Wave 7a Migration: Simple CRUD modules → PostgreSQL
 *
 * Migrates:
 *   1. menu/ → menu_items (NEW TABLE)
 *   2. job-applications/ → job_applications (explicit columns)
 *   3. recipes/ → recipes (data JSONB)
 *   4. training-articles/ → training_articles (data JSONB)
 *   5. shift-questions/ → shift_questions (data JSONB)
 *   6. recount-questions/ → recount_questions (data JSONB)
 *   7. employee-registrations/ → employee_registrations (data JSONB)
 *   8. shop-settings/ → shop_settings (shop_address PK, data JSONB)
 *   9. task-points-config.json → app_settings key='task_points_config'
 *  10. loyalty-promo.json → app_settings key='loyalty_promo' (verify)
 *
 * Run: node scripts/migrate_wave7a_simple.js
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

async function main() {
  console.log('=== Wave 7a Migration: Simple CRUD modules ===\n');

  await patchSchema();

  const stats = {
    menu: 0, jobApplications: 0, recipes: 0, training: 0,
    shiftQuestions: 0, recountQuestions: 0, employeeRegistrations: 0,
    shopSettings: 0, taskPointsConfig: 0, loyaltyPromo: 0, errors: 0
  };

  await migrateJsonbDir('menu', 'menu_items', stats, 'menu');
  await migrateJobApplications(stats);
  await migrateJsonbDir('recipes', 'recipes', stats, 'recipes');
  await migrateJsonbDir('training-articles', 'training_articles', stats, 'training');
  await migrateJsonbDir('shift-questions', 'shift_questions', stats, 'shiftQuestions');
  await migrateJsonbDir('recount-questions', 'recount_questions', stats, 'recountQuestions');
  await migrateEmployeeRegistrations(stats);
  await migrateShopSettings(stats);
  await migrateSingletonConfig('task-points-config.json', 'task_points_config', stats, 'taskPointsConfig');
  await migrateSingletonConfig('loyalty-promo.json', 'loyalty_promo', stats, 'loyaltyPromo');

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
    `CREATE TABLE IF NOT EXISTS menu_items (
      id TEXT PRIMARY KEY,
      data JSONB NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )`
  ];

  for (const sql of patches) {
    try {
      await db.query(sql);
    } catch (e) {
      if (!e.message.includes('already exists')) {
        console.warn(`  Patch warning: ${e.message}`);
      }
    }
  }
  console.log(`  Applied ${patches.length} schema patches`);
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
        created_at: data.createdAt || new Date().toISOString(),
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
// Job applications (explicit columns)
// ============================================

async function migrateJobApplications(stats) {
  console.log('\nMigrating job-applications/ → job_applications...');

  const dir = path.join(DATA_DIR, 'job-applications');
  let files;
  try {
    files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  } catch (e) {
    console.log(`  No job-applications directory: ${e.message}`);
    return;
  }

  console.log(`  Found ${files.length} files`);

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const app = JSON.parse(content);

      await db.upsert('job_applications', {
        id: app.id || file.replace('.json', ''),
        full_name: app.fullName || null,
        phone: app.phone || null,
        preferred_shift: app.preferredShift || null,
        shop_addresses: app.shopAddresses || null,
        is_viewed: app.isViewed === true,
        viewed_at: app.viewedAt || null,
        viewed_by: app.viewedBy || null,
        status: app.status || 'new',
        admin_notes: app.adminNotes || null,
        status_updated_at: app.statusUpdatedAt || null,
        notes_updated_at: app.notesUpdatedAt || null,
        created_at: app.createdAt || new Date().toISOString()
      });
      stats.jobApplications++;
    } catch (e) {
      if (!e.message.includes('duplicate key')) {
        console.error(`  Error ${file}: ${e.message}`);
        stats.errors++;
      } else {
        stats.jobApplications++;
      }
    }
  }

  console.log(`  Done: ${stats.jobApplications} records`);
}

// ============================================
// Employee registrations (phone as PK in file, id in table)
// ============================================

async function migrateEmployeeRegistrations(stats) {
  console.log('\nMigrating employee-registrations/ → employee_registrations...');

  const dir = path.join(DATA_DIR, 'employee-registrations');
  let files;
  try {
    files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  } catch (e) {
    console.log(`  No employee-registrations directory: ${e.message}`);
    return;
  }

  console.log(`  Found ${files.length} files`);

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const data = JSON.parse(content);
      // Use phone as ID (file is named by phone)
      const id = data.phone || file.replace('.json', '');

      await db.upsert('employee_registrations', {
        id: id,
        data: data,
        created_at: data.createdAt || new Date().toISOString()
      });
      stats.employeeRegistrations++;
    } catch (e) {
      if (!e.message.includes('duplicate key')) {
        console.error(`  Error ${file}: ${e.message}`);
        stats.errors++;
      } else {
        stats.employeeRegistrations++;
      }
    }
  }

  console.log(`  Done: ${stats.employeeRegistrations} records`);
}

// ============================================
// Shop settings (shop_address as PK)
// ============================================

async function migrateShopSettings(stats) {
  console.log('\nMigrating shop-settings/ → shop_settings...');

  const dir = path.join(DATA_DIR, 'shop-settings');
  let files;
  try {
    files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  } catch (e) {
    console.log(`  No shop-settings directory: ${e.message}`);
    return;
  }

  console.log(`  Found ${files.length} files`);

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const data = JSON.parse(content);
      const shopAddress = data.shopAddress || file.replace('.json', '');

      await db.upsert('shop_settings', {
        shop_address: shopAddress,
        data: data,
        created_at: data.createdAt || new Date().toISOString(),
        updated_at: data.updatedAt || new Date().toISOString()
      }, 'shop_address');
      stats.shopSettings++;
    } catch (e) {
      if (!e.message.includes('duplicate key')) {
        console.error(`  Error ${file}: ${e.message}`);
        stats.errors++;
      } else {
        stats.shopSettings++;
      }
    }
  }

  console.log(`  Done: ${stats.shopSettings} records`);
}

// ============================================
// Singleton config files → app_settings
// ============================================

async function migrateSingletonConfig(fileName, settingsKey, stats, statsKey) {
  console.log(`\nMigrating ${fileName} → app_settings['${settingsKey}']...`);

  const filePath = path.join(DATA_DIR, fileName);
  try {
    const content = await fsp.readFile(filePath, 'utf8');
    const data = JSON.parse(content);

    await db.upsert('app_settings', {
      key: settingsKey,
      data: data,
      updated_at: data.updatedAt || new Date().toISOString()
    }, 'key');
    stats[statsKey] = 1;
    console.log(`  Done: 1 record`);
  } catch (e) {
    if (e.code === 'ENOENT') {
      console.log(`  File not found, skipping`);
    } else {
      console.error(`  Error: ${e.message}`);
      stats.errors++;
    }
  }
}

main().catch(e => {
  console.error('Migration failed:', e);
  process.exit(1);
});

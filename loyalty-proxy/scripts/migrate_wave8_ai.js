/**
 * Wave 8 Migration: AI Modules → PostgreSQL
 *
 * Migrates:
 *   1. z-report-templates.json → z_report_templates
 *   2. z-report-training-samples.json → z_report_training_samples
 *   3. z-report-learned-patterns.json → app_settings (key = 'z_report_learned_patterns')
 *   4. cigarette-training-samples.json → cigarette_samples
 *   5. cigarette-training-settings.json → app_settings (key = 'cigarette_vision_settings')
 *   6. shift-ai-settings/products.json → app_settings (key = 'shift_ai_settings')
 *   7. shift-ai-annotations/*.json → shift_ai_annotations
 *
 * Run on server: node scripts/migrate_wave8_ai.js
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');

const DATA_DIR = path.join(__dirname, '..', 'data');
const VAR_WWW = process.env.DATA_DIR || '/var/www';

async function main() {
  console.log('=== Wave 8 Migration: AI Modules ===\n');

  await createTables();

  const stats = {
    zReportTemplates: 0,
    zReportSamples: 0,
    zReportPatterns: 0,
    cigaretteSamples: 0,
    cigaretteSettings: 0,
    shiftAiSettings: 0,
    shiftAiAnnotations: 0,
    errors: 0,
  };

  await migrateZReportTemplates(stats);
  await migrateZReportSamples(stats);
  await migrateZReportPatterns(stats);
  await migrateCigaretteSamples(stats);
  await migrateCigaretteSettings(stats);
  await migrateShiftAiSettings(stats);
  await migrateShiftAiAnnotations(stats);

  console.log('\n=== SUMMARY ===');
  for (const [key, val] of Object.entries(stats)) {
    if (key !== 'errors') console.log(`  ${key}: ${val}`);
  }
  console.log(`  Errors: ${stats.errors}`);

  // Verify counts
  console.log('\n=== VERIFY DB COUNTS ===');
  const tables = ['z_report_templates', 'z_report_training_samples', 'cigarette_samples', 'shift_ai_annotations'];
  for (const table of tables) {
    try {
      const result = await db.query(`SELECT count(*) as cnt FROM ${table}`);
      console.log(`  ${table}: ${result.rows[0].cnt}`);
    } catch (e) {
      console.error(`  ${table}: ERROR - ${e.message}`);
    }
  }

  // Check app_settings
  const settingsKeys = ['z_report_learned_patterns', 'cigarette_vision_settings', 'shift_ai_settings'];
  for (const key of settingsKeys) {
    try {
      const row = await db.findById('app_settings', key, 'key');
      console.log(`  app_settings[${key}]: ${row ? 'EXISTS' : 'NOT FOUND'}`);
    } catch (e) {
      console.error(`  app_settings[${key}]: ERROR - ${e.message}`);
    }
  }

  await db.close();
  process.exit(stats.errors > 0 ? 1 : 0);
}

// ============================================
// Schema
// ============================================

async function createTables() {
  console.log('Creating tables...');

  const sqlFile = path.join(__dirname, 'create_wave8_tables.sql');
  const sql = await fsp.readFile(sqlFile, 'utf8');

  // Split by semicolons and execute each statement
  const statements = sql
    .split(';')
    .map(s => s.trim())
    .filter(s => s.length > 0 && !s.startsWith('--'));

  for (const stmt of statements) {
    try {
      await db.query(stmt);
    } catch (e) {
      // Ignore "already exists" errors
      if (!e.message.includes('already exists')) {
        console.error('SQL error:', e.message);
      }
    }
  }

  console.log('Tables ready.\n');
}

// ============================================
// Z-Report Templates
// ============================================

async function migrateZReportTemplates(stats) {
  console.log('--- Z-Report Templates ---');
  const file = path.join(DATA_DIR, 'z-report-templates.json');

  try {
    const raw = await fsp.readFile(file, 'utf8');
    const data = JSON.parse(raw);
    const templates = data.templates || [];

    for (const template of templates) {
      try {
        await db.upsert('z_report_templates', {
          id: template.id,
          data: template,
          created_at: template.createdAt || new Date().toISOString(),
          updated_at: template.updatedAt || new Date().toISOString(),
        });
        stats.zReportTemplates++;
      } catch (e) {
        console.error(`  Template ${template.id}: ${e.message}`);
        stats.errors++;
      }
    }

    console.log(`  Migrated: ${stats.zReportTemplates} templates`);
  } catch (e) {
    if (e.code === 'ENOENT') {
      console.log('  File not found, skipping');
    } else {
      console.error('  Error:', e.message);
      stats.errors++;
    }
  }
}

// ============================================
// Z-Report Training Samples
// ============================================

async function migrateZReportSamples(stats) {
  console.log('--- Z-Report Training Samples ---');
  const file = path.join(DATA_DIR, 'z-report-training-samples.json');

  try {
    const raw = await fsp.readFile(file, 'utf8');
    const data = JSON.parse(raw);
    const samples = data.samples || [];

    for (const sample of samples) {
      try {
        await db.upsert('z_report_training_samples', {
          id: sample.id,
          shop_id: sample.shopId || null,
          template_id: sample.templateId || null,
          data: sample,
          created_at: sample.createdAt || new Date().toISOString(),
        });
        stats.zReportSamples++;
      } catch (e) {
        console.error(`  Sample ${sample.id}: ${e.message}`);
        stats.errors++;
      }
    }

    console.log(`  Migrated: ${stats.zReportSamples} samples`);
  } catch (e) {
    if (e.code === 'ENOENT') {
      console.log('  File not found, skipping');
    } else {
      console.error('  Error:', e.message);
      stats.errors++;
    }
  }
}

// ============================================
// Z-Report Learned Patterns → app_settings
// ============================================

async function migrateZReportPatterns(stats) {
  console.log('--- Z-Report Learned Patterns ---');
  const file = path.join(DATA_DIR, 'z-report-learned-patterns.json');

  try {
    const raw = await fsp.readFile(file, 'utf8');
    const data = JSON.parse(raw);

    await db.upsert('app_settings', {
      key: 'z_report_learned_patterns',
      data: data,
      updated_at: data.lastUpdated || new Date().toISOString(),
    }, 'key');
    stats.zReportPatterns = 1;

    const patternCounts = {};
    for (const [field, patterns] of Object.entries(data.patterns || {})) {
      patternCounts[field] = patterns.length;
    }
    console.log(`  Migrated: 1 record, patterns:`, patternCounts);
  } catch (e) {
    if (e.code === 'ENOENT') {
      console.log('  File not found, skipping');
    } else {
      console.error('  Error:', e.message);
      stats.errors++;
    }
  }
}

// ============================================
// Cigarette Vision Samples
// ============================================

async function migrateCigaretteSamples(stats) {
  console.log('--- Cigarette Vision Samples ---');
  const file = path.join(DATA_DIR, 'cigarette-training-samples.json');

  try {
    const raw = await fsp.readFile(file, 'utf8');
    const data = JSON.parse(raw);
    const samples = data.samples || [];

    for (const sample of samples) {
      try {
        await db.upsert('cigarette_samples', {
          id: sample.id,
          product_id: sample.productId || null,
          type: sample.type || null,
          shop_address: sample.shopAddress || null,
          data: sample,
          created_at: sample.createdAt || new Date().toISOString(),
        });
        stats.cigaretteSamples++;
      } catch (e) {
        console.error(`  Sample ${sample.id}: ${e.message}`);
        stats.errors++;
      }
    }

    console.log(`  Migrated: ${stats.cigaretteSamples} samples`);
  } catch (e) {
    if (e.code === 'ENOENT') {
      console.log('  File not found, skipping');
    } else {
      console.error('  Error:', e.message);
      stats.errors++;
    }
  }
}

// ============================================
// Cigarette Vision Settings → app_settings
// ============================================

async function migrateCigaretteSettings(stats) {
  console.log('--- Cigarette Vision Settings ---');
  const file = path.join(DATA_DIR, 'cigarette-training-settings.json');

  try {
    const raw = await fsp.readFile(file, 'utf8');
    const data = JSON.parse(raw);

    await db.upsert('app_settings', {
      key: 'cigarette_vision_settings',
      data: data,
      updated_at: new Date().toISOString(),
    }, 'key');
    stats.cigaretteSettings = 1;

    console.log(`  Migrated: 1 settings record`);
  } catch (e) {
    if (e.code === 'ENOENT') {
      console.log('  File not found, skipping');
    } else {
      console.error('  Error:', e.message);
      stats.errors++;
    }
  }
}

// ============================================
// Shift AI Settings → app_settings
// ============================================

async function migrateShiftAiSettings(stats) {
  console.log('--- Shift AI Settings ---');
  const file = path.join(VAR_WWW, 'shift-ai-settings', 'products.json');

  try {
    const raw = await fsp.readFile(file, 'utf8');
    const data = JSON.parse(raw);

    await db.upsert('app_settings', {
      key: 'shift_ai_settings',
      data: data,
      updated_at: new Date().toISOString(),
    }, 'key');
    stats.shiftAiSettings = 1;

    const productCount = Object.keys(data).length;
    console.log(`  Migrated: 1 settings record (${productCount} products)`);
  } catch (e) {
    if (e.code === 'ENOENT') {
      console.log('  File not found, skipping');
    } else {
      console.error('  Error:', e.message);
      stats.errors++;
    }
  }
}

// ============================================
// Shift AI Annotations
// ============================================

async function migrateShiftAiAnnotations(stats) {
  console.log('--- Shift AI Annotations ---');
  const dir = path.join(VAR_WWW, 'shift-ai-annotations');

  try {
    const files = await fsp.readdir(dir);
    const jsonFiles = files.filter(f => f.endsWith('.json'));

    for (const file of jsonFiles) {
      try {
        const raw = await fsp.readFile(path.join(dir, file), 'utf8');
        const annotation = JSON.parse(raw);

        await db.upsert('shift_ai_annotations', {
          id: annotation.id || file.replace('.json', ''),
          product_id: annotation.productId || null,
          barcode: annotation.barcode || null,
          shop_address: annotation.shopAddress || null,
          data: annotation,
          created_at: annotation.createdAt || new Date().toISOString(),
        });
        stats.shiftAiAnnotations++;
      } catch (e) {
        console.error(`  Annotation ${file}: ${e.message}`);
        stats.errors++;
      }
    }

    console.log(`  Migrated: ${stats.shiftAiAnnotations} annotations`);
  } catch (e) {
    if (e.code === 'ENOENT') {
      console.log('  Directory not found, skipping');
    } else {
      console.error('  Error:', e.message);
      stats.errors++;
    }
  }
}

main().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});

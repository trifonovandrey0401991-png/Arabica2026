/**
 * Migration Wave 4c: Bonus/Penalties
 * Monthly JSON files → PostgreSQL
 *
 * Run: node scripts/migrate_wave4_bonus_penalties.js
 * Safe for re-run (upsert by id)
 *
 * Source: /var/www/bonus-penalties/YYYY-MM.json
 * Format: {records: [{id, employeeId, employeeName, type, amount, comment, adminName, createdAt, month}]}
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const BONUS_PENALTIES_DIR = `${DATA_DIR}/bonus-penalties`;

function camelToDb(r) {
  return {
    id: r.id,
    employee_id: r.employeeId || null,
    employee_name: r.employeeName || null,
    type: r.type || 'bonus',
    amount: r.amount != null ? r.amount : 0,
    comment: r.comment || null,
    admin_name: r.adminName || null,
    month: r.month || null,
    created_at: r.createdAt || new Date().toISOString()
  };
}

async function migrateBonusPenalties() {
  if (!await fileExists(BONUS_PENALTIES_DIR)) {
    console.log('  No bonus-penalties directory found, skipping');
    return { count: 0, errors: 0, skipped: 0 };
  }

  const files = (await fsp.readdir(BONUS_PENALTIES_DIR)).filter(f => f.endsWith('.json'));
  console.log(`  Found ${files.length} monthly files\n`);

  let count = 0;
  let errors = 0;
  let skipped = 0;

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(BONUS_PENALTIES_DIR, file), 'utf8');
      const data = JSON.parse(content);
      const records = data.records || [];

      console.log(`  ${file}: ${records.length} records`);

      for (const r of records) {
        if (!r.id) {
          console.log(`    Skip: no id in record`);
          skipped++;
          continue;
        }

        try {
          await db.upsert('bonus_penalties', camelToDb(r));
          count++;
          console.log(`    ${r.id} | ${r.employeeName} | ${r.type} | ${r.amount}`);
        } catch (e) {
          console.error(`    Error: ${r.id} — ${e.message}`);
          errors++;
        }
      }
    } catch (e) {
      console.error(`  Error reading ${file}: ${e.message}`);
      errors++;
    }
  }

  return { count, errors, skipped };
}

async function main() {
  console.log('=== Wave 4c Migration: Bonus/Penalties ===\n');

  try {
    const health = await db.healthCheck();
    console.log(`DB connected: ${health.dbSizeMB} MB, pool: ${JSON.stringify(health.pool)}\n`);

    console.log('--- Bonus/Penalties ---');
    const result = await migrateBonusPenalties();
    console.log(`\nResult: ${result.count} migrated, ${result.errors} errors, ${result.skipped} skipped\n`);

    const dbCount = await db.count('bonus_penalties');
    console.log(`Verification: ${dbCount} records in bonus_penalties table`);

    const sample = await db.query(
      'SELECT id, employee_name, type, amount, month FROM bonus_penalties ORDER BY created_at DESC LIMIT 5'
    );
    console.log('\nSample records:');
    for (const row of sample.rows) {
      console.log(`  ${row.id} | ${row.employee_name} | ${row.type} | ${row.amount} | ${row.month}`);
    }

  } catch (e) {
    console.error('Migration failed:', e);
    process.exit(1);
  }

  await db.close();
  console.log('\n=== Done ===');
}

main();

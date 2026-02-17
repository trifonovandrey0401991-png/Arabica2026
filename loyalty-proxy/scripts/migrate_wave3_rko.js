/**
 * Миграция Wave 3f: RKO Reports
 * JSON metadata → PostgreSQL
 *
 * Запуск: node scripts/migrate_wave3_rko.js
 * Безопасно для повторного запуска (upsert)
 *
 * Источник: /var/www/rko-reports/rko_metadata.json
 * Формат: { items: [...] } — центральный файл метаданных
 * У записей НЕТ id — используем fileName как PRIMARY KEY
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

async function migrateRkoReports() {
  const metadataFile = `${DATA_DIR}/rko-reports/rko_metadata.json`;
  if (!await fileExists(metadataFile)) {
    console.log('⚠️  RKO metadata file not found, skipping');
    return { count: 0, errors: 0, skipped: 0 };
  }

  const content = await fsp.readFile(metadataFile, 'utf8');
  const data = JSON.parse(content);
  const items = Array.isArray(data) ? data : (data.items || []);

  let count = 0;
  let errors = 0;
  let skipped = 0;

  for (const r of items) {
    if (!r.fileName) {
      console.log('  ⚠️  Skip item: no fileName');
      skipped++;
      continue;
    }

    try {
      // Derive date from date field or createdAt
      const dateStr = r.date ? r.date.split('T')[0] : null;

      // Use fileName as ID (items don't have id field)
      const id = r.id || r.fileName;

      await db.upsert('rko_reports', {
        id: id,
        file_name: r.fileName,
        original_name: r.originalName || r.fileName,
        employee_name: r.employeeName || null,
        employee_phone: r.employeePhone || null,
        shop_address: r.shopAddress || null,
        shop_name: r.shopName || null,
        date: dateStr,
        amount: r.amount != null ? r.amount : null,
        rko_type: r.rkoType || null,
        shift_type: r.shiftType || null,
        file_path: r.filePath || null,
        status: r.status || 'uploaded',
        rating: r.rating != null ? r.rating : null,
        confirmed_by: r.confirmedBy || null,
        confirmed_at: r.confirmedAt || null,
        rejected_by: r.rejectedBy || null,
        rejected_at: r.rejectedAt || null,
        reject_reason: r.rejectReason || null,
        created_at: r.createdAt || new Date().toISOString(),
        updated_at: new Date().toISOString()
      });

      count++;
      const shortId = id.substring(0, 60);
      console.log(`  ✅ ${shortId} (${r.shopAddress || 'no shop'}, ${r.rkoType || 'no type'})`);
    } catch (e) {
      console.error(`  ❌ Error migrating ${r.fileName}:`, e.message);
      errors++;
    }
  }

  return { count, errors, skipped };
}

// ==================== MAIN ====================

async function main() {
  console.log('=== Wave 3f Migration: RKO Reports ===\n');

  try {
    const health = await db.healthCheck();
    console.log(`DB connected: ${health.dbSizeMB} MB, pool: ${JSON.stringify(health.pool)}\n`);

    console.log('--- RKO Reports ---');
    const result = await migrateRkoReports();
    console.log(`\nResult: ${result.count} migrated, ${result.errors} errors, ${result.skipped} skipped\n`);

    const dbCount = await db.count('rko_reports');
    console.log(`Verification: ${dbCount} records in rko_reports table`);

    const sample = await db.query('SELECT id, employee_name, shop_address, rko_type, amount, date FROM rko_reports LIMIT 5');
    console.log('\nSample records:');
    for (const row of sample.rows) {
      console.log(`  ${(row.id || '').substring(0, 50)} | ${row.employee_name} | ${row.rko_type} | ${row.amount} | ${row.date}`);
    }

  } catch (e) {
    console.error('Migration failed:', e);
    process.exit(1);
  }

  await db.close();
  console.log('\n=== Done ===');
}

main();

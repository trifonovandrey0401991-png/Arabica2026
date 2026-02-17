/**
 * Миграция Wave 3a: Envelope Reports
 * JSON файлы → PostgreSQL
 *
 * Запуск: node scripts/migrate_wave3_envelope.js
 * Безопасно для повторного запуска (upsert)
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

async function migrateEnvelopeReports() {
  const dir = `${DATA_DIR}/envelope-reports`;
  if (!await fileExists(dir)) {
    console.log('⚠️  Envelope reports directory not found, skipping');
    return 0;
  }

  const files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  let count = 0;
  let errors = 0;

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const r = JSON.parse(content);

      if (!r.id) {
        console.log(`  ⚠️  Skip ${file}: no id`);
        continue;
      }

      // Derive date from createdAt if not present
      const date = r.date || (r.createdAt ? r.createdAt.split('T')[0] : null);

      await db.upsert('envelope_reports', {
        id: r.id,
        employee_name: r.employeeName || null,
        employee_phone: r.employeePhone || null,
        shop_address: r.shopAddress || null,
        shift_type: r.shiftType || null,
        status: r.status || 'pending',
        date: date,
        ooo_z_report_photo_url: r.oooZReportPhotoUrl || null,
        ooo_revenue: r.oooRevenue != null ? r.oooRevenue : null,
        ooo_cash: r.oooCash != null ? r.oooCash : null,
        ooo_expenses: JSON.stringify(r.oooExpenses || []),
        ooo_envelope_photo_url: r.oooEnvelopePhotoUrl || null,
        ooo_ofd_not_sent: r.oooOfdNotSent != null ? r.oooOfdNotSent : null,
        ip_z_report_photo_url: r.ipZReportPhotoUrl || null,
        ip_revenue: r.ipRevenue != null ? r.ipRevenue : null,
        ip_cash: r.ipCash != null ? r.ipCash : null,
        expenses: JSON.stringify(r.expenses || []),
        ip_envelope_photo_url: r.ipEnvelopePhotoUrl || null,
        ip_ofd_not_sent: r.ipOfdNotSent != null ? r.ipOfdNotSent : null,
        rating: r.rating != null ? r.rating : null,
        created_at: r.createdAt || new Date().toISOString(),
        confirmed_at: r.confirmedAt || null,
        confirmed_by_admin: r.confirmedByAdmin || null,
        failed_at: r.failedAt || null,
        updated_at: new Date().toISOString()
      });

      count++;
      console.log(`  ✅ ${r.id} (${r.shopAddress || 'no shop'}, ${r.status})`);
    } catch (e) {
      console.error(`  ❌ Error migrating ${file}:`, e.message);
      errors++;
    }
  }

  return { count, errors };
}

// ==================== MAIN ====================

async function main() {
  console.log('=== Wave 3a Migration: Envelope Reports ===\n');

  try {
    // Health check
    const health = await db.healthCheck();
    console.log(`DB connected: ${health.dbSizeMB} MB, pool: ${JSON.stringify(health.pool)}\n`);

    // Migrate
    console.log('--- Envelope Reports ---');
    const result = await migrateEnvelopeReports();
    console.log(`\nResult: ${result.count} migrated, ${result.errors} errors\n`);

    // Verify
    const dbCount = await db.count('envelope_reports');
    console.log(`Verification: ${dbCount} records in envelope_reports table`);

    // Show sample
    const sample = await db.query('SELECT id, employee_name, shop_address, status, date FROM envelope_reports LIMIT 3');
    console.log('\nSample records:');
    for (const row of sample.rows) {
      console.log(`  ${row.id} | ${row.employee_name} | ${row.shop_address} | ${row.status} | ${row.date}`);
    }

  } catch (e) {
    console.error('Migration failed:', e);
    process.exit(1);
  }

  await db.close();
  console.log('\n=== Done ===');
}

main();

/**
 * Миграция Wave 3b: Shift Handover Reports
 * JSON файлы → PostgreSQL
 *
 * Запуск: node scripts/migrate_wave3_shift_handover.js
 * Безопасно для повторного запуска (upsert)
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

async function migrateShiftHandoverReports() {
  const dir = `${DATA_DIR}/shift-handover-reports`;
  if (!await fileExists(dir)) {
    console.log('⚠️  Shift handover reports directory not found, skipping');
    return { count: 0, errors: 0 };
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

      // Determine shift type from createdAt hour (Moscow time)
      let shiftType = r.shiftType || null;
      if (!shiftType && r.createdAt) {
        const createdHour = (new Date(r.createdAt).getUTCHours() + 3) % 24;
        shiftType = createdHour >= 14 ? 'evening' : 'morning';
      }

      await db.upsert('shift_handover_reports', {
        id: r.id,
        employee_name: r.employeeName || null,
        employee_phone: r.employeePhone || null,
        shop_address: r.shopAddress || null,
        shop_name: r.shopName || null,
        shift_type: shiftType,
        status: r.status || 'pending',
        answers: JSON.stringify(r.answers || []),
        rating: r.rating != null ? r.rating : null,
        date: date,
        created_at: r.createdAt || new Date().toISOString(),
        confirmed_at: r.confirmedAt || null,
        confirmed_by_admin: r.confirmedByAdmin || null,
        failed_at: r.failedAt || null,
        rejected_at: r.rejectedAt || null,
        expired_at: r.expiredAt || null,
        completed_by: r.completedBy || null,
        ai_verification_skipped: r.aiVerificationSkipped || false,
        is_synced: r.isSynced || false,
        updated_at: r.updatedAt || new Date().toISOString()
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
  console.log('=== Wave 3b Migration: Shift Handover Reports ===\n');

  try {
    // Health check
    const health = await db.healthCheck();
    console.log(`DB connected: ${health.dbSizeMB} MB, pool: ${JSON.stringify(health.pool)}\n`);

    // Migrate
    console.log('--- Shift Handover Reports ---');
    const result = await migrateShiftHandoverReports();
    console.log(`\nResult: ${result.count} migrated, ${result.errors} errors\n`);

    // Verify
    const dbCount = await db.count('shift_handover_reports');
    console.log(`Verification: ${dbCount} records in shift_handover_reports table`);

    // Show sample
    const sample = await db.query('SELECT id, employee_name, shop_address, status, date FROM shift_handover_reports LIMIT 3');
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

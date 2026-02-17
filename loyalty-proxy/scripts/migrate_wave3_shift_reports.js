/**
 * Миграция Wave 3e: Shift Reports
 * JSON файлы → PostgreSQL
 *
 * Запуск: node scripts/migrate_wave3_shift_reports.js
 * Безопасно для повторного запуска (upsert)
 *
 * Два формата файлов:
 * 1. Daily files: YYYY-MM-DD.json (массив отчётов, включая pending)
 * 2. Legacy individual files: EmployeeName_ShopAddress_Date.json
 *
 * Pending отчёты НЕ мигрируются (эфемерные, создаются scheduler-ом)
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

async function migrateShiftReports() {
  const dir = `${DATA_DIR}/shift-reports`;
  if (!await fileExists(dir)) {
    console.log('⚠️  Shift reports directory not found, skipping');
    return { count: 0, errors: 0, skipped: 0 };
  }

  const files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  let count = 0;
  let errors = 0;
  let skipped = 0;

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const data = JSON.parse(content);

      // Daily file (array) or individual file (object)?
      const reports = Array.isArray(data) ? data : (data.id ? [data] : []);

      for (const r of reports) {
        // Пропускаем pending/failed — эфемерные
        if (!r.id) { skipped++; continue; }
        if (r.id.startsWith('pending_')) { skipped++; continue; }
        if (r.status === 'failed') { skipped++; continue; }

        try {
          const date = r.date || (r.createdAt ? r.createdAt.split('T')[0] : null);

          await db.upsert('shift_reports', {
            id: r.id,
            employee_name: r.employeeName || null,
            employee_id: r.employeeId || null,
            employee_phone: r.employeePhone || r.phone || null,
            shop_address: r.shopAddress || null,
            shop_name: r.shopName || null,
            shift_type: r.shiftType || null,
            status: r.status || (r.confirmedAt ? 'confirmed' : 'review'),
            answers: JSON.stringify(r.answers || []),
            rating: r.rating != null ? r.rating : null,
            date: date,
            created_at: r.createdAt || r.timestamp || new Date().toISOString(),
            submitted_at: r.submittedAt || null,
            deadline: r.deadline || null,
            review_deadline: r.reviewDeadline || null,
            confirmed_at: r.confirmedAt || null,
            confirmed_by_admin: r.confirmedByAdmin || null,
            failed_at: r.failedAt || null,
            rejected_at: r.rejectedAt || null,
            expired_at: r.expiredAt || null,
            is_synced: r.isSynced || false,
            saved_at: r.savedAt || null,
            updated_at: r.updatedAt || new Date().toISOString()
          });

          count++;
          const idShort = (r.id || '').substring(0, 50);
          console.log(`  ✅ ${idShort} (${r.shopAddress || 'no shop'}, ${r.status || 'no status'})`);
        } catch (e) {
          console.error(`  ❌ Error migrating report ${r.id}:`, e.message);
          errors++;
        }
      }
    } catch (e) {
      console.error(`  ❌ Error reading file ${file}:`, e.message);
      errors++;
    }
  }

  return { count, errors, skipped };
}

// ==================== MAIN ====================

async function main() {
  console.log('=== Wave 3e Migration: Shift Reports ===\n');

  try {
    const health = await db.healthCheck();
    console.log(`DB connected: ${health.dbSizeMB} MB, pool: ${JSON.stringify(health.pool)}\n`);

    console.log('--- Shift Reports ---');
    const result = await migrateShiftReports();
    console.log(`\nResult: ${result.count} migrated, ${result.errors} errors, ${result.skipped} skipped\n`);

    const dbCount = await db.count('shift_reports');
    console.log(`Verification: ${dbCount} records in shift_reports table`);

    const sample = await db.query('SELECT id, employee_name, shop_address, status, rating, date FROM shift_reports LIMIT 5');
    console.log('\nSample records:');
    for (const row of sample.rows) {
      console.log(`  ${(row.id || '').substring(0, 50)} | ${row.employee_name} | ${row.status} | rating=${row.rating} | ${row.date}`);
    }

  } catch (e) {
    console.error('Migration failed:', e);
    process.exit(1);
  }

  await db.close();
  console.log('\n=== Done ===');
}

main();

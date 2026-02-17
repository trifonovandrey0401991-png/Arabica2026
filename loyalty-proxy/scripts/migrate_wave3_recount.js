/**
 * Миграция Wave 3d: Recount Reports
 * JSON файлы → PostgreSQL
 *
 * Запуск: node scripts/migrate_wave3_recount.js
 * Безопасно для повторного запуска (upsert)
 *
 * ВАЖНО: мигрируются только реальные отчёты (не pending_recount_*)
 * Pending файлы — эфемерные, создаются scheduler-ом каждый день
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

async function migrateRecountReports() {
  const dir = `${DATA_DIR}/recount-reports`;
  if (!await fileExists(dir)) {
    console.log('⚠️  Recount reports directory not found, skipping');
    return { count: 0, errors: 0, skipped: 0 };
  }

  const files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  let count = 0;
  let errors = 0;
  let skipped = 0;

  for (const file of files) {
    // Пропускаем pending файлы — они эфемерные
    if (file.startsWith('pending_recount_')) {
      skipped++;
      continue;
    }

    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const r = JSON.parse(content);

      if (!r.id) {
        console.log(`  ⚠️  Skip ${file}: no id`);
        skipped++;
        continue;
      }

      // Derive date from createdAt or completedAt
      const date = r.date || (r.createdAt ? r.createdAt.split('T')[0] : null);

      await db.upsert('recount_reports', {
        id: r.id,
        employee_name: r.employeeName || null,
        employee_phone: r.employeePhone || null,
        employee_id: r.employeeId || r.employeePhone || null,
        shop_address: r.shopAddress || null,
        shop_name: r.shopName || null,
        shift_type: r.shiftType || null,
        status: r.status || (r.adminRating != null ? 'confirmed' : 'review'),
        answers: JSON.stringify(r.answers || []),
        admin_rating: r.adminRating != null ? r.adminRating : null,
        admin_name: r.adminName || null,
        rated_at: r.ratedAt || null,
        date: date,
        created_at: r.createdAt || new Date().toISOString(),
        deadline: r.deadline || null,
        submitted_at: r.submittedAt || null,
        review_deadline: r.reviewDeadline || null,
        failed_at: r.failedAt || null,
        rejected_at: r.rejectedAt || null,
        completed_by: r.completedBy || null,
        started_at: r.startedAt || null,
        completed_at: r.completedAt || null,
        duration: r.duration != null ? r.duration : null,
        expired_at: r.expiredAt || null,
        photo_verifications: r.photoVerifications ? JSON.stringify(r.photoVerifications) : null,
        saved_at: r.savedAt || null,
        updated_at: new Date().toISOString()
      });

      count++;
      console.log(`  ✅ ${r.id.substring(0, 60)} (${r.shopAddress || 'no shop'}, ${r.status || 'no status'})`);
    } catch (e) {
      console.error(`  ❌ Error migrating ${file}:`, e.message);
      errors++;
    }
  }

  return { count, errors, skipped };
}

// ==================== MAIN ====================

async function main() {
  console.log('=== Wave 3d Migration: Recount Reports ===\n');

  try {
    const health = await db.healthCheck();
    console.log(`DB connected: ${health.dbSizeMB} MB, pool: ${JSON.stringify(health.pool)}\n`);

    console.log('--- Recount Reports ---');
    const result = await migrateRecountReports();
    console.log(`\nResult: ${result.count} migrated, ${result.errors} errors, ${result.skipped} skipped (pending)\n`);

    const dbCount = await db.count('recount_reports');
    console.log(`Verification: ${dbCount} records in recount_reports table`);

    const sample = await db.query('SELECT id, employee_name, shop_address, status, admin_rating, date FROM recount_reports LIMIT 5');
    console.log('\nSample records:');
    for (const row of sample.rows) {
      console.log(`  ${(row.id || '').substring(0, 50)} | ${row.employee_name} | ${row.status} | rating=${row.admin_rating} | ${row.date}`);
    }

  } catch (e) {
    console.error('Migration failed:', e);
    process.exit(1);
  }

  await db.close();
  console.log('\n=== Done ===');
}

main();

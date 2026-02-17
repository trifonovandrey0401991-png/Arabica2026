/**
 * Миграция Wave 3c: Coffee Machine Reports
 * JSON файлы → PostgreSQL
 *
 * Запуск: node scripts/migrate_wave3_coffee_machine.js
 * Безопасно для повторного запуска (upsert)
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

async function migrateCoffeeMachineReports() {
  const dir = `${DATA_DIR}/coffee-machine-reports`;
  if (!await fileExists(dir)) {
    console.log('⚠️  Coffee machine reports directory not found, skipping');
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

      const date = r.date || (r.createdAt ? r.createdAt.split('T')[0] : null);

      await db.upsert('coffee_machine_reports', {
        id: r.id,
        employee_name: r.employeeName || null,
        employee_phone: r.employeePhone || null,
        shop_address: r.shopAddress || null,
        shift_type: r.shiftType || null,
        date: date,
        readings: JSON.stringify(r.readings || []),
        computer_number: r.computerNumber != null ? r.computerNumber : null,
        computer_photo_url: r.computerPhotoUrl || null,
        sum_of_machines: r.sumOfMachines != null ? r.sumOfMachines : null,
        has_discrepancy: r.hasDiscrepancy || false,
        discrepancy_amount: r.discrepancyAmount != null ? r.discrepancyAmount : 0,
        status: r.status || 'pending',
        rating: r.rating != null ? r.rating : null,
        created_at: r.createdAt || new Date().toISOString(),
        confirmed_at: r.confirmedAt || null,
        confirmed_by_admin: r.confirmedByAdmin || null,
        rejected_at: r.rejectedAt || null,
        rejected_by_admin: r.rejectedByAdmin || null,
        reject_reason: r.rejectReason || null,
        failed_at: r.failedAt || null,
        completed_by: r.completedBy || null,
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
  console.log('=== Wave 3c Migration: Coffee Machine Reports ===\n');

  try {
    const health = await db.healthCheck();
    console.log(`DB connected: ${health.dbSizeMB} MB, pool: ${JSON.stringify(health.pool)}\n`);

    console.log('--- Coffee Machine Reports ---');
    const result = await migrateCoffeeMachineReports();
    console.log(`\nResult: ${result.count} migrated, ${result.errors} errors\n`);

    const dbCount = await db.count('coffee_machine_reports');
    console.log(`Verification: ${dbCount} records in coffee_machine_reports table`);

    const sample = await db.query('SELECT id, employee_name, shop_address, status, date FROM coffee_machine_reports LIMIT 3');
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

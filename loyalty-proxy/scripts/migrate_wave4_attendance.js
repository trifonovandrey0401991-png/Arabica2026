/**
 * Migration Wave 4b: Attendance
 * Individual JSON files → PostgreSQL
 *
 * Run: node scripts/migrate_wave4_attendance.js
 * Safe for re-run (upsert by id)
 *
 * Source: /var/www/attendance/*.json
 * Format: Individual files (standard) or legacy daily aggregate {records:[]}
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const ATTENDANCE_DIR = `${DATA_DIR}/attendance`;

function camelToDb(r) {
  return {
    id: r.id,
    employee_name: r.employeeName || null,
    employee_phone: r.employeePhone || null,
    shop_address: r.shopAddress || null,
    shop_name: r.shopName || null,
    shift_type: r.shiftType || null,
    status: r.status || 'confirmed',
    timestamp: r.timestamp || null,
    latitude: r.latitude != null ? r.latitude : null,
    longitude: r.longitude != null ? r.longitude : null,
    distance: r.distance != null ? r.distance : null,
    is_on_time: r.isOnTime != null ? r.isOnTime : null,
    late_minutes: r.lateMinutes != null ? r.lateMinutes : null,
    marked_at: r.markedAt || r.confirmedAt || null,
    deadline: r.deadline || null,
    failed_at: r.failedAt || null,
    created_at: r.createdAt || new Date().toISOString()
  };
}

async function migrateAttendance() {
  if (!await fileExists(ATTENDANCE_DIR)) {
    console.log('  No attendance directory found, skipping');
    return { count: 0, errors: 0, skipped: 0 };
  }

  const files = (await fsp.readdir(ATTENDANCE_DIR)).filter(f => f.endsWith('.json'));
  console.log(`  Found ${files.length} files\n`);

  let count = 0;
  let errors = 0;
  let skipped = 0;

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(ATTENDANCE_DIR, file), 'utf8');
      const data = JSON.parse(content);

      // Legacy format: {identifier, date, records: [...]}
      if (data.records && Array.isArray(data.records)) {
        console.log(`  Legacy format: ${file} (${data.records.length} records)`);
        for (const r of data.records) {
          if (!r.id) {
            r.id = `legacy_${file}_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
          }
          try {
            await db.upsert('attendance', camelToDb(r));
            count++;
          } catch (e) {
            console.error(`    Error: ${r.id} — ${e.message}`);
            errors++;
          }
        }
        continue;
      }

      // Standard format: individual record
      if (!data.id) {
        console.log(`  Skip: no id in ${file}`);
        skipped++;
        continue;
      }

      await db.upsert('attendance', camelToDb(data));
      count++;
      console.log(`  ${data.id.substring(0, 50)} | ${data.employeeName} | ${data.shiftType || 'n/a'}`);
    } catch (e) {
      console.error(`  Error reading ${file}: ${e.message}`);
      errors++;
    }
  }

  return { count, errors, skipped };
}

async function main() {
  console.log('=== Wave 4b Migration: Attendance ===\n');

  try {
    const health = await db.healthCheck();
    console.log(`DB connected: ${health.dbSizeMB} MB, pool: ${JSON.stringify(health.pool)}\n`);

    console.log('--- Attendance ---');
    const result = await migrateAttendance();
    console.log(`\nResult: ${result.count} migrated, ${result.errors} errors, ${result.skipped} skipped\n`);

    const dbCount = await db.count('attendance');
    console.log(`Verification: ${dbCount} records in attendance table`);

    const sample = await db.query(
      'SELECT id, employee_name, shop_address, shift_type, is_on_time FROM attendance ORDER BY created_at DESC LIMIT 5'
    );
    console.log('\nSample records:');
    for (const row of sample.rows) {
      const shortId = (row.id || '').substring(0, 50);
      console.log(`  ${shortId} | ${row.employee_name} | ${row.shift_type} | onTime: ${row.is_on_time}`);
    }

  } catch (e) {
    console.error('Migration failed:', e);
    process.exit(1);
  }

  await db.close();
  console.log('\n=== Done ===');
}

main();

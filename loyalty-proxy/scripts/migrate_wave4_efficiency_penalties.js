/**
 * Migration Wave 4a: Efficiency Penalties
 * JSON monthly files → PostgreSQL
 *
 * Run: node scripts/migrate_wave4_efficiency_penalties.js
 * Safe for re-run (upsert by id)
 *
 * Source: /var/www/efficiency-penalties/YYYY-MM.json
 * Format: ARRAY [...] (most writers) or OBJECT {monthKey, penalties: [...]}
 *
 * 11 writer modules, 4 reader modules — central efficiency registry
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const EFFICIENCY_PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;

async function migrateEfficiencyPenalties() {
  if (!await fileExists(EFFICIENCY_PENALTIES_DIR)) {
    console.log('  No efficiency-penalties directory found, skipping');
    return { count: 0, errors: 0, skipped: 0 };
  }

  const files = (await fsp.readdir(EFFICIENCY_PENALTIES_DIR))
    .filter(f => f.endsWith('.json'));

  console.log(`  Found ${files.length} monthly files\n`);

  let count = 0;
  let errors = 0;
  let skipped = 0;

  for (const file of files) {
    const monthKey = file.replace('.json', '');
    console.log(`--- ${monthKey} ---`);

    try {
      const content = await fsp.readFile(
        path.join(EFFICIENCY_PENALTIES_DIR, file), 'utf8'
      );
      const parsed = JSON.parse(content);

      // Handle both formats: ARRAY [...] and OBJECT {penalties: [...]}
      let penalties;
      if (Array.isArray(parsed)) {
        penalties = parsed;
      } else if (parsed && parsed.penalties && Array.isArray(parsed.penalties)) {
        penalties = parsed.penalties;
      } else {
        console.log(`  Unexpected format in ${file}, skipping`);
        skipped++;
        continue;
      }

      console.log(`  ${penalties.length} penalties in ${file}`);

      for (const p of penalties) {
        if (!p.id) {
          // Generate ID for penalties without one
          p.id = `migrated_${monthKey}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        }

        if (!p.category) {
          console.log(`  Skip: no category (id=${p.id})`);
          skipped++;
          continue;
        }

        try {
          await db.upsert('efficiency_penalties', {
            id: p.id,
            type: p.type || 'employee',
            entity_id: p.entityId || null,
            entity_name: p.entityName || null,
            shop_address: p.shopAddress || null,
            employee_name: p.employeeName || null,
            employee_phone: p.employeePhone || null,
            employee_id: p.employeeId || null,
            category: p.category,
            category_name: p.categoryName || null,
            date: p.date || null,
            shift_type: p.shiftType || null,
            points: p.points != null ? p.points : 0,
            reason: p.reason || null,
            source_id: p.sourceId || null,
            source_type: p.sourceType || null,
            late_minutes: p.lateMinutes != null ? p.lateMinutes : null,
            task_id: p.taskId || null,
            assignment_id: p.assignmentId || null,
            created_at: p.createdAt || new Date().toISOString(),
            updated_at: new Date().toISOString()
          });

          count++;
        } catch (e) {
          console.error(`  Error: ${p.id} — ${e.message}`);
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

// ==================== MAIN ====================

async function main() {
  console.log('=== Wave 4a Migration: Efficiency Penalties ===\n');

  try {
    const health = await db.healthCheck();
    console.log(`DB connected: ${health.dbSizeMB} MB, pool: ${JSON.stringify(health.pool)}\n`);

    console.log('--- Efficiency Penalties ---');
    const result = await migrateEfficiencyPenalties();
    console.log(`\nResult: ${result.count} migrated, ${result.errors} errors, ${result.skipped} skipped\n`);

    const dbCount = await db.count('efficiency_penalties');
    console.log(`Verification: ${dbCount} records in efficiency_penalties table`);

    const sample = await db.query(
      'SELECT id, employee_name, category, points, date, source_type FROM efficiency_penalties ORDER BY created_at DESC LIMIT 5'
    );
    console.log('\nSample records (latest 5):');
    for (const row of sample.rows) {
      const shortId = (row.id || '').substring(0, 40);
      console.log(`  ${shortId} | ${row.employee_name} | ${row.category} | ${row.points} | ${row.date}`);
    }

    // Category breakdown
    const categories = await db.query(
      'SELECT category, COUNT(*) as cnt FROM efficiency_penalties GROUP BY category ORDER BY cnt DESC'
    );
    console.log('\nBy category:');
    for (const row of categories.rows) {
      console.log(`  ${row.category}: ${row.cnt}`);
    }

  } catch (e) {
    console.error('Migration failed:', e);
    process.exit(1);
  }

  await db.close();
  console.log('\n=== Done ===');
}

main();

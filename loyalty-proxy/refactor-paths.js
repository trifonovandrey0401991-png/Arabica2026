/**
 * Automated Path Refactoring Script
 *
 * Заменяет все '/var/www' на DATA_DIR во всех JS файлах.
 * Добавляет определение DATA_DIR в начало каждого файла.
 *
 * Запуск:
 *   node refactor-paths.js --dry-run  # Только показать изменения
 *   node refactor-paths.js            # Применить изменения
 *   node refactor-paths.js --revert   # Откатить изменения (из бэкапов)
 */

const fs = require('fs');
const path = require('path');

const BACKUP_DIR = './backups-refactor';
const DRY_RUN = process.argv.includes('--dry-run');
const REVERT = process.argv.includes('--revert');

// Файлы для рефакторинга
const FILES_TO_PROCESS = [
  'index.js',
  'efficiency_calc.js',
  'rating_wheel_api.js',
  'referrals_api.js',
  'job_applications_api.js',
  'order_notifications_api.js',
  'order_timeout_api.js',
  'product_questions_penalty_scheduler.js',
  'recount_points_api.js',
  'recurring_tasks_api.js',
  'report_notifications_api.js',
  'tasks_api.js',
  // API files
  'api/attendance_api.js',
  'api/attendance_automation_scheduler.js',
  'api/cigarette_vision_api.js',
  'api/clients_api.js',
  'api/data_cleanup_api.js',
  'api/efficiency_penalties_api.js',
  'api/employee_chat_api.js',
  'api/employee_chat_websocket.js',
  'api/employees_api.js',
  'api/envelope_api.js',
  'api/envelope_automation_scheduler.js',
  'api/geofence_api.js',
  'api/loyalty_api.js',
  'api/loyalty_promo_api.js',
  'api/manager_efficiency_api.js',
  'api/master_catalog_api.js',
  'api/master_catalog_notifications.js',
  'api/media_api.js',
  'api/menu_api.js',
  'api/orders_api.js',
  'api/pending_api.js',
  'api/points_settings_api.js',
  'api/product_questions_api.js',
  'api/product_questions_notifications.js',
  'api/recipes_api.js',
  'api/recount_api.js',
  'api/recount_automation_scheduler.js',
  'api/recurring_tasks_api.js',
  'api/reviews_api.js',
  'api/rko_api.js',
  'api/rko_automation_scheduler.js',
  'api/shift_ai_verification_api.js',
  'api/shift_automation_scheduler.js',
  'api/shift_handover_automation_scheduler.js',
  'api/shift_transfers_api.js',
  'api/shifts_api.js',
  'api/shop_managers_api.js',
  'api/shop_products_api.js',
  'api/task_points_settings_api.js',
  'api/training_api.js',
  'api/withdrawals_api.js',
  'api/work_schedule_api.js',
  'api/z_report_api.js',
  // Modules
  'modules/orders.js',
  'modules/z-report-vision.js',
  // Utils
  'utils/admin_cache.js',
  'utils/pagination.js',
];

// Строка для добавления в начало файлов (СРАЗУ после require блока, ДО констант с путями)
const DATA_DIR_DEFINITION = `const DATA_DIR = process.env.DATA_DIR || '/var/www';
`;

// Статистика
let stats = {
  filesProcessed: 0,
  filesModified: 0,
  replacements: 0,
  errors: []
};

function ensureBackupDir() {
  if (!fs.existsSync(BACKUP_DIR)) {
    fs.mkdirSync(BACKUP_DIR, { recursive: true });
  }
}

function backupFile(filePath) {
  const backupPath = path.join(BACKUP_DIR, filePath.replace(/\//g, '_'));
  const content = fs.readFileSync(filePath, 'utf8');
  fs.writeFileSync(backupPath, content);
  return backupPath;
}

function revertFile(filePath) {
  const backupPath = path.join(BACKUP_DIR, filePath.replace(/\//g, '_'));
  if (fs.existsSync(backupPath)) {
    const content = fs.readFileSync(backupPath, 'utf8');
    fs.writeFileSync(filePath, content);
    return true;
  }
  return false;
}

function processFile(filePath) {
  if (!fs.existsSync(filePath)) {
    stats.errors.push(`File not found: ${filePath}`);
    return;
  }

  stats.filesProcessed++;
  let content = fs.readFileSync(filePath, 'utf8');
  const originalContent = content;

  // Подсчёт замен
  const matches = content.match(/['"`]\/var\/www/g);
  const matchCount = matches ? matches.length : 0;

  if (matchCount === 0) {
    console.log(`  ⏭️  ${filePath} - no changes needed`);
    return;
  }

  // Проверяем, есть ли уже DATA_DIR определение
  const hasDataDir = content.includes('const DATA_DIR = process.env.DATA_DIR');

  // Добавляем DATA_DIR если нет
  if (!hasDataDir) {
    // Находим место СРАЗУ после последнего require(), но ДО констант с путями
    const lines = content.split('\n');
    let insertIndex = 0;
    let foundRequire = false;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();

      // Отслеживаем require строки
      if (line.includes('require(')) {
        foundRequire = true;
        insertIndex = i + 1;
      }
      // Если нашли require и теперь видим const с путём - вставляем ДО него
      else if (foundRequire && line.startsWith('const ') && line.includes('/var/www')) {
        insertIndex = i;
        break;
      }
      // Пропускаем пустые строки и комментарии после require
      else if (foundRequire && (line === '' || line.startsWith('//'))) {
        // Если следующая строка с путём - вставляем тут
        if (i + 1 < lines.length && lines[i + 1].includes('/var/www')) {
          insertIndex = i + 1;
          break;
        }
      }
      // Выходим если дошли до функций/экспортов
      else if (line.startsWith('function') || line.startsWith('app.') ||
               line.startsWith('module.exports') || line.startsWith('class ')) {
        break;
      }
    }

    // Вставляем DATA_DIR
    lines.splice(insertIndex, 0, DATA_DIR_DEFINITION);
    content = lines.join('\n');
  }

  // Заменяем '/var/www' на DATA_DIR
  // Паттерны замены:
  // '/var/www/shops' -> `${DATA_DIR}/shops`
  // '/var/www' + '/shops' -> DATA_DIR + '/shops'
  // path.join('/var/www', 'shops') -> path.join(DATA_DIR, 'shops')

  // Замена строковых литералов с путями
  content = content.replace(
    /(['"`])\/var\/www\//g,
    '`${DATA_DIR}/'
  );

  // Закрываем шаблонные строки правильно
  content = content.replace(
    /\`\$\{DATA_DIR\}\/([^'"`\n]+)(['"])/g,
    '`${DATA_DIR}/$1`'
  );

  // Замена path.join('/var/www', ...)
  content = content.replace(
    /path\.join\s*\(\s*['"]\/var\/www['"]\s*,/g,
    'path.join(DATA_DIR,'
  );

  // Замена '/var/www' в конкатенации
  content = content.replace(
    /['"]\/var\/www['"]\s*\+/g,
    'DATA_DIR +'
  );

  // Замена оставшихся '/var/www' (без trailing slash)
  content = content.replace(
    /(['"])\/var\/www\1/g,
    'DATA_DIR'
  );

  stats.replacements += matchCount;

  if (content !== originalContent) {
    stats.filesModified++;
    if (DRY_RUN) {
      console.log(`  📝 ${filePath} - would modify (${matchCount} replacements)`);
    } else {
      backupFile(filePath);
      fs.writeFileSync(filePath, content);
      console.log(`  ✅ ${filePath} - modified (${matchCount} replacements)`);
    }
  }
}

function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('  Path Refactoring Script');
  console.log('  Replace /var/www -> DATA_DIR');
  console.log('═══════════════════════════════════════════════════════════');
  console.log('');

  if (DRY_RUN) {
    console.log('🔍 DRY RUN MODE - no files will be modified\n');
  } else if (REVERT) {
    console.log('⏪ REVERT MODE - restoring from backups\n');
    ensureBackupDir();
    let reverted = 0;
    for (const file of FILES_TO_PROCESS) {
      if (revertFile(file)) {
        console.log(`  ✅ Reverted: ${file}`);
        reverted++;
      }
    }
    console.log(`\n✅ Reverted ${reverted} files from backups`);
    return;
  } else {
    console.log('🔧 APPLY MODE - files will be modified\n');
    ensureBackupDir();
  }

  console.log('Processing files...\n');

  for (const file of FILES_TO_PROCESS) {
    processFile(file);
  }

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('  Summary');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(`  Files processed:  ${stats.filesProcessed}`);
  console.log(`  Files modified:   ${stats.filesModified}`);
  console.log(`  Total replacements: ${stats.replacements}`);

  if (stats.errors.length > 0) {
    console.log('\n  Errors:');
    for (const err of stats.errors) {
      console.log(`    ❌ ${err}`);
    }
  }

  if (DRY_RUN) {
    console.log('\n📌 Run without --dry-run to apply changes');
  } else if (!REVERT) {
    console.log(`\n📁 Backups saved to: ${BACKUP_DIR}/`);
    console.log('📌 To revert: node refactor-paths.js --revert');
  }
}

main();

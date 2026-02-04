/**
 * Setup Local Development Environment
 *
 * Создаёт структуру директорий для локального тестирования
 * Запуск: node setup-local.js
 */

const fs = require('fs');
const path = require('path');

// Базовая директория для тестовых данных
const DATA_DIR = process.env.DATA_DIR || './test-data';

// Все директории из серверного кода
const directories = [
  'ai-recognition-stats',
  'app-logs',
  'attendance',
  'attendance-automation-state',
  'attendance-pending',
  'bonus-penalties',
  'cache/referral-stats',
  'chat-media',
  'client-dialogs',
  'client-messages',
  'client-messages-management',
  'client-messages-network',
  'client-reviews',
  'clients',
  'dbf-stocks',
  'dbf-sync-settings',
  'efficiency-penalties',
  'employee-chats',
  'employee-photos',
  'employee-ratings',
  'employee-registrations',
  'employees',
  'envelope-automation-state',
  'envelope-pending',
  'envelope-questions',
  'envelope-reports',
  'fcm-tokens',
  'fortune-wheel',
  'geofence-notifications',
  'html',
  'job-applications',
  'logs',
  'loyalty-transactions',
  'main_cash',
  'master-catalog',
  'menu',
  'network-messages',
  'orders',
  'pending-recount-reports',
  'pending-shift-reports',
  'points-settings',
  'product-question-dialogs',
  'product-question-penalty-state',
  'product-question-photos',
  'product-questions',
  'recipe-photos',
  'recipes',
  'recount-automation-state',
  'recount-points',
  'recount-questions',
  'recount-reports',
  'recount-settings',
  'recurring-task-instances',
  'recurring-tasks',
  'referral-clients',
  'report-notifications',
  'reviews',
  'rko',
  'rko-automation-state',
  'rko-files',
  'rko-pending',
  'rko-reports',
  'shift-ai-annotations',
  'shift-ai-settings',
  'shift-automation-state',
  'shift-handover-automation-state',
  'shift-handover-pending',
  'shift-handover-question-photos',
  'shift-handover-questions',
  'shift-handover-reports',
  'shift-handovers',
  'shift-photos',
  'shift-questions',
  'shift-reports',
  'shop-coordinates',
  'shop-products',
  'shops',
  'shop-settings',
  'suppliers',
  'task-assignments',
  'task-media',
  'tasks',
  'test-questions',
  'test-results',
  'training-articles',
  'training-articles-media',
  'withdrawals',
  'work-schedules',
  'work-schedule-templates',
];

// JSON файлы с дефолтным содержимым
const jsonFiles = {
  'geofence-settings.json': {
    enabled: false,
    radius: 100,
    cooldownHours: 24,
    notificationTitle: 'Добро пожаловать!',
    notificationBody: 'Вы рядом с кофейней Arabica'
  },
  'loyalty-promo.json': {
    promoText: 'Собери 10 напитков и получи 1 бесплатно!',
    pointsRequired: 10,
    drinksToGive: 1
  },
  'orders-viewed-rejected.json': [],
  'orders-viewed-unconfirmed.json': [],
  'pending-shift-handover-reports.json': [],
  'referrals-viewed.json': [],
  'shift-transfers.json': [],
  'shop-managers.json': {},
  'task-points-config.json': {
    pointsPerTask: 1,
    maxPointsPerDay: 10
  },
  'shops/shops.json': [],
  'rko-reports/rko_metadata.json': [],
  'points-settings/attendance.json': {
    enabled: true,
    pointsPerAttendance: 1
  },
  'points-settings/envelope_points_settings.json': {
    morningStart: '07:00',
    morningEnd: '09:00',
    eveningStart: '19:00',
    eveningEnd: '21:00',
    pointsPerEnvelope: 1,
    penaltyPoints: -5
  },
  'points-settings/recount_points_settings.json': {
    pointsPerRecount: 1
  },
  'points-settings/referrals.json': {
    basePoints: 1,
    milestoneThreshold: 5,
    milestonePoints: 3
  },
  'points-settings/shift_points_settings.json': {
    pointsPerShift: 1
  },
  'points-settings/test_points_settings.json': {
    pointsPerTest: 1
  },
  'recount-settings/settings.json': {
    enabled: true
  },
  'dbf-sync-settings/api-keys.json': {},
  'cache/referral-stats/stats.json': {}
};

// Создание директорий
console.log('📁 Creating directories...');
for (const dir of directories) {
  const fullPath = path.join(DATA_DIR, dir);
  if (!fs.existsSync(fullPath)) {
    fs.mkdirSync(fullPath, { recursive: true });
    console.log(`  ✓ ${dir}`);
  }
}

// Создание JSON файлов
console.log('\n📄 Creating JSON files...');
for (const [file, content] of Object.entries(jsonFiles)) {
  const fullPath = path.join(DATA_DIR, file);
  const dir = path.dirname(fullPath);

  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  if (!fs.existsSync(fullPath)) {
    fs.writeFileSync(fullPath, JSON.stringify(content, null, 2));
    console.log(`  ✓ ${file}`);
  }
}

// Создание тестового магазина
const testShop = {
  id: 'shop_test',
  name: 'Тестовый магазин',
  address: 'ул. Тестовая, 1',
  latitude: 55.7558,
  longitude: 37.6173,
  isActive: true
};
const shopsPath = path.join(DATA_DIR, 'shops/shop_test.json');
if (!fs.existsSync(shopsPath)) {
  fs.writeFileSync(shopsPath, JSON.stringify(testShop, null, 2));
  console.log('  ✓ shops/shop_test.json (test shop)');
}

// Создание тестового сотрудника
const testEmployee = {
  id: 'emp_test',
  name: 'Тест Тестов',
  phone: '79001234567',
  role: 'employee',
  shopId: 'shop_test',
  isActive: true
};
const employeesPath = path.join(DATA_DIR, 'employees/emp_test.json');
if (!fs.existsSync(employeesPath)) {
  fs.writeFileSync(employeesPath, JSON.stringify(testEmployee, null, 2));
  console.log('  ✓ employees/emp_test.json (test employee)');
}

// Создание тестового админа
const testAdmin = {
  id: 'admin_test',
  name: 'Админ Тестов',
  phone: '79009876543',
  role: 'admin',
  isActive: true
};
const adminPath = path.join(DATA_DIR, 'employees/admin_test.json');
if (!fs.existsSync(adminPath)) {
  fs.writeFileSync(adminPath, JSON.stringify(testAdmin, null, 2));
  console.log('  ✓ employees/admin_test.json (test admin)');
}

console.log('\n✅ Local environment setup complete!');
console.log(`\n📍 Data directory: ${path.resolve(DATA_DIR)}`);
console.log('\n🚀 To start server locally:');
console.log(`   DATA_DIR=${DATA_DIR} node index.js`);
console.log('\n   Or on Windows PowerShell:');
console.log(`   $env:DATA_DIR="${DATA_DIR}"; node index.js`);

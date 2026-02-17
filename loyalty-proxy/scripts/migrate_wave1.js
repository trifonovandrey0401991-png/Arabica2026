#!/usr/bin/env node
/**
 * Migration Wave 1: shops, employees, suppliers, points_settings, shop_settings, app_settings
 *
 * Читает JSON-файлы → INSERT в PostgreSQL.
 * Запуск: node scripts/migrate_wave1.js
 * Безопасен для повторного запуска (ON CONFLICT DO UPDATE).
 */

const path = require('path');
const fsp = require('fs').promises;
const db = require('../utils/db');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

// ============================================
// Утилиты
// ============================================

async function loadJsonDir(dir) {
  try {
    await fsp.access(dir);
  } catch {
    console.log(`  Directory not found: ${dir}, skipping`);
    return [];
  }

  const files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  const items = [];

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      items.push({ filename: file, data: JSON.parse(content) });
    } catch (e) {
      console.warn(`  Skipping corrupted file: ${file} — ${e.message}`);
    }
  }

  return items;
}

// ============================================
// Миграция shops
// ============================================

async function migrateShops() {
  console.log('\n=== Migrating SHOPS ===');
  const items = await loadJsonDir(path.join(DATA_DIR, 'shops'));
  let migrated = 0;

  for (const { data } of items) {
    if (!data.id || !data.address) {
      console.warn('  Skipping shop without id/address:', data.name);
      continue;
    }

    await db.upsert('shops', {
      id: data.id,
      name: data.name || '',
      address: data.address,
      latitude: data.latitude || null,
      longitude: data.longitude || null,
      created_at: data.createdAt || new Date().toISOString(),
      updated_at: data.updatedAt || new Date().toISOString()
    });
    migrated++;
  }

  console.log(`  Migrated ${migrated} shops`);
  return migrated;
}

// ============================================
// Миграция employees
// ============================================

async function migrateEmployees() {
  console.log('\n=== Migrating EMPLOYEES ===');
  const items = await loadJsonDir(path.join(DATA_DIR, 'employees'));
  let migrated = 0;

  for (const { data } of items) {
    if (!data.id || !data.phone) {
      console.warn('  Skipping employee without id/phone:', data.name);
      continue;
    }

    await db.upsert('employees', {
      id: data.id,
      referral_code: data.referralCode || null,
      name: data.name || '',
      phone: data.phone,
      is_admin: data.isAdmin || false,
      is_manager: data.isManager || false,
      employee_name: data.employeeName || null,
      preferred_work_days: data.preferredWorkDays || [],
      preferred_shops: data.preferredShops || [],
      shift_preferences: data.shiftPreferences ? JSON.stringify(data.shiftPreferences) : null,
      created_at: data.createdAt || new Date().toISOString(),
      updated_at: data.updatedAt || new Date().toISOString()
    });
    migrated++;
  }

  console.log(`  Migrated ${migrated} employees`);
  return migrated;
}

// ============================================
// Миграция suppliers
// ============================================

async function migrateSuppliers() {
  console.log('\n=== Migrating SUPPLIERS ===');
  const items = await loadJsonDir(path.join(DATA_DIR, 'suppliers'));
  let migrated = 0;

  for (const { data } of items) {
    if (!data.id) {
      console.warn('  Skipping supplier without id:', data.name);
      continue;
    }

    await db.upsert('suppliers', {
      id: data.id,
      referral_code: data.referralCode || null,
      name: data.name || '',
      inn: data.inn || null,
      legal_type: data.legalType || null,
      phone: data.phone || null,
      email: data.email || null,
      contact_person: data.contactPerson || null,
      payment_type: data.paymentType || null,
      shop_deliveries: data.shopDeliveries || null,
      delivery_days: data.deliveryDays || [],
      created_at: data.createdAt || new Date().toISOString(),
      updated_at: data.updatedAt || new Date().toISOString()
    });
    migrated++;
  }

  console.log(`  Migrated ${migrated} suppliers`);
  return migrated;
}

// ============================================
// Миграция points_settings
// ============================================

async function migratePointsSettings() {
  console.log('\n=== Migrating POINTS_SETTINGS ===');
  const items = await loadJsonDir(path.join(DATA_DIR, 'points-settings'));
  let migrated = 0;

  for (const { filename, data } of items) {
    const category = filename.replace('.json', '');
    const id = data.id || category;

    await db.upsert('points_settings', {
      id: id,
      category: data.category || category,
      data: JSON.stringify(data),
      created_at: data.createdAt || new Date().toISOString(),
      updated_at: data.updatedAt || new Date().toISOString()
    });
    migrated++;
  }

  console.log(`  Migrated ${migrated} points_settings`);
  return migrated;
}

// ============================================
// Миграция shop_settings
// ============================================

async function migrateShopSettings() {
  console.log('\n=== Migrating SHOP_SETTINGS ===');
  const items = await loadJsonDir(path.join(DATA_DIR, 'shop-settings'));
  let migrated = 0;
  let skipped = 0;

  for (const { filename, data } of items) {
    // Пропускаем тестовые файлы
    if (filename.includes('test') || filename.includes('Test') || filename === 'sdfsfdds.json' || filename === 'dasdasdasd.json') {
      skipped++;
      continue;
    }

    const shopAddress = data.shopAddress || data.address || filename.replace('.json', '').replace(/_/g, ' ');
    if (!shopAddress) {
      skipped++;
      continue;
    }

    await db.upsert('shop_settings', {
      shop_address: shopAddress,
      data: JSON.stringify(data),
      created_at: data.createdAt || new Date().toISOString(),
      updated_at: data.updatedAt || new Date().toISOString()
    }, 'shop_address');
    migrated++;
  }

  console.log(`  Migrated ${migrated} shop_settings (skipped ${skipped} test files)`);
  return migrated;
}

// ============================================
// Миграция singleton app_settings
// ============================================

async function migrateAppSettings() {
  console.log('\n=== Migrating APP_SETTINGS ===');
  let migrated = 0;

  const singletons = [
    { key: 'app_version', path: path.join(DATA_DIR, 'app-version.json') },
    { key: 'shop_managers', path: path.join(DATA_DIR, 'shop-managers.json') },
    { key: 'geofence_settings', path: path.join(DATA_DIR, 'geofence-settings.json') },
    { key: 'test_settings', path: path.join(DATA_DIR, 'test-settings.json') },
    { key: 'loyalty_promo', path: path.join(DATA_DIR, 'loyalty-promo.json') },
    { key: 'execution_chains', path: path.join(DATA_DIR, 'execution-chains.json') },
  ];

  for (const { key, path: filePath } of singletons) {
    try {
      await fsp.access(filePath);
      const content = await fsp.readFile(filePath, 'utf8');
      const data = JSON.parse(content);

      await db.upsert('app_settings', {
        key: key,
        data: JSON.stringify(data),
        updated_at: new Date().toISOString()
      }, 'key');
      migrated++;
      console.log(`  Migrated: ${key}`);
    } catch (e) {
      if (e.code === 'ENOENT') {
        console.log(`  Skipping ${key} — file not found`);
      } else {
        console.warn(`  Error migrating ${key}: ${e.message}`);
      }
    }
  }

  console.log(`  Migrated ${migrated} app_settings`);
  return migrated;
}

// ============================================
// Миграция automation_state
// ============================================

async function migrateAutomationState() {
  console.log('\n=== Migrating AUTOMATION_STATE ===');
  let migrated = 0;

  const schedulers = [
    'shift', 'recount', 'envelope', 'attendance',
    'coffee-machine', 'rko', 'shift-handover'
  ];

  for (const name of schedulers) {
    const statePath = path.join(DATA_DIR, `${name}-automation-state`, 'state.json');
    try {
      await fsp.access(statePath);
      const content = await fsp.readFile(statePath, 'utf8');
      const data = JSON.parse(content);

      await db.upsert('automation_state', {
        scheduler_name: name,
        state: JSON.stringify(data),
        updated_at: new Date().toISOString()
      }, 'scheduler_name');
      migrated++;
      console.log(`  Migrated: ${name}`);
    } catch (e) {
      if (e.code === 'ENOENT') {
        console.log(`  Skipping ${name} — state file not found`);
      } else {
        console.warn(`  Error: ${name} — ${e.message}`);
      }
    }
  }

  console.log(`  Migrated ${migrated} automation states`);
  return migrated;
}

// ============================================
// MAIN
// ============================================

async function main() {
  console.log('========================================');
  console.log('  Migration Wave 1 — Core Entities');
  console.log('  Data source: ' + DATA_DIR);
  console.log('========================================');

  const totals = {};
  try {
    totals.shops = await migrateShops();
    totals.employees = await migrateEmployees();
    totals.suppliers = await migrateSuppliers();
    totals.pointsSettings = await migratePointsSettings();
    totals.shopSettings = await migrateShopSettings();
    totals.appSettings = await migrateAppSettings();
    totals.automationState = await migrateAutomationState();

    console.log('\n========================================');
    console.log('  WAVE 1 COMPLETE');
    console.log('  Results:', JSON.stringify(totals));
    console.log('========================================');
  } catch (err) {
    console.error('\n!!! MIGRATION ERROR !!!');
    console.error(err);
    process.exit(1);
  } finally {
    await db.close();
  }
}

main();

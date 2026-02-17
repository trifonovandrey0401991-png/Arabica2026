/**
 * Миграция Wave 2: Clients, Orders, Reviews
 * JSON файлы → PostgreSQL
 *
 * Запуск: node scripts/migrate_wave2.js
 * Безопасно для повторного запуска (upsert)
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

async function migrateClients() {
  const dir = `${DATA_DIR}/clients`;
  if (!await fileExists(dir)) {
    console.log('⚠️  Clients directory not found, skipping');
    return 0;
  }

  const files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  let count = 0;

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const c = JSON.parse(content);

      // Клиенты хранятся по телефону (имя файла = телефон)
      const phone = c.phone || file.replace('.json', '');
      if (!phone || phone === 'undefined') {
        console.log(`  ⚠️  Skip ${file}: no phone`);
        continue;
      }

      await db.upsert('clients', {
        phone,
        name: c.name || null,
        client_name: c.clientName || null,
        fcm_token: c.fcmToken || null,
        referred_by: c.referredBy || null,
        referred_at: c.referredAt || null,
        is_admin: c.isAdmin === true,
        employee_name: c.employeeName || null,
        created_at: c.createdAt || new Date().toISOString(),
        updated_at: c.updatedAt || new Date().toISOString()
      }, 'phone');

      count++;
    } catch (e) {
      console.error(`  ❌ Error migrating client ${file}:`, e.message);
    }
  }

  return count;
}

async function migrateOrders() {
  const dir = `${DATA_DIR}/orders`;
  if (!await fileExists(dir)) {
    console.log('⚠️  Orders directory not found, skipping');
    return 0;
  }

  const files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  let count = 0;

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const o = JSON.parse(content);

      if (!o.id) {
        console.log(`  ⚠️  Skip ${file}: no id`);
        continue;
      }

      await db.upsert('orders', {
        id: o.id,
        order_number: o.orderNumber || null,
        client_phone: o.clientPhone || null,
        client_name: o.clientName || null,
        shop_address: o.shopAddress || null,
        items: JSON.stringify(o.items || []),
        total_price: o.totalPrice || null,
        comment: o.comment || null,
        status: o.status || 'pending',
        accepted_by: o.acceptedBy || null,
        rejected_by: o.rejectedBy || null,
        rejection_reason: o.rejectionReason || null,
        rejected_at: o.rejectedAt || null,
        expired_at: o.expiredAt || null,
        created_at: o.createdAt || new Date().toISOString(),
        updated_at: o.updatedAt || new Date().toISOString()
      }, 'id');

      count++;
    } catch (e) {
      console.error(`  ❌ Error migrating order ${file}:`, e.message);
    }
  }

  return count;
}

async function migrateReviews() {
  const dir = `${DATA_DIR}/reviews`;
  if (!await fileExists(dir)) {
    console.log('⚠️  Reviews directory not found, skipping');
    return 0;
  }

  const files = (await fsp.readdir(dir)).filter(f => f.startsWith('review_') && f.endsWith('.json'));
  let count = 0;

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const r = JSON.parse(content);

      if (!r.id) {
        console.log(`  ⚠️  Skip ${file}: no id`);
        continue;
      }

      await db.upsert('reviews', {
        id: r.id,
        client_phone: r.clientPhone || null,
        client_name: r.clientName || null,
        shop_address: r.shopAddress || null,
        review_type: r.reviewType || null,
        review_text: r.reviewText || null,
        messages: JSON.stringify(r.messages || []),
        has_unread_from_client: r.hasUnreadFromClient === true,
        has_unread_from_admin: r.hasUnreadFromAdmin === true,
        created_at: r.createdAt || new Date().toISOString()
      }, 'id');

      count++;
    } catch (e) {
      console.error(`  ❌ Error migrating review ${file}:`, e.message);
    }
  }

  return count;
}

async function main() {
  console.log('🚀 Wave 2 Migration: Clients, Orders, Reviews\n');

  try {
    await db.healthCheck();
    console.log('✅ Database connected\n');

    console.log('--- Migrating Clients ---');
    const clientsCount = await migrateClients();
    console.log(`✅ Clients: ${clientsCount} records\n`);

    console.log('--- Migrating Orders ---');
    const ordersCount = await migrateOrders();
    console.log(`✅ Orders: ${ordersCount} records\n`);

    console.log('--- Migrating Reviews ---');
    const reviewsCount = await migrateReviews();
    console.log(`✅ Reviews: ${reviewsCount} records\n`);

    console.log('=================================');
    console.log(`Total migrated: ${clientsCount + ordersCount + reviewsCount} records`);
    console.log('=================================');
  } catch (error) {
    console.error('❌ Migration failed:', error);
  } finally {
    await db.close();
  }
}

main();

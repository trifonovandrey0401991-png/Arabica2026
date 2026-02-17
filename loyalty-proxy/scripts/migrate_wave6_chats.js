/**
 * Wave 6 Migration: Chats & Communication → PostgreSQL
 *
 * Migrates:
 *   1. employee-chats/ → employee_chats + chat_messages
 *   2. client-messages-network/ → client_messages (channel='network')
 *   3. client-messages-management/ → client_messages (channel='management')
 *   4. client-messages/{phone}/{shop}.json → client_messages (channel='dialog')
 *
 * Run: node scripts/migrate_wave6_chats.js
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

async function main() {
  console.log('=== Wave 6 Migration: Chats & Communication ===\n');

  // Phase 1: Schema patches
  await patchSchema();

  // Phase 2: Migrate employee chats
  const ecStats = await migrateEmployeeChats();

  // Phase 3: Migrate client messages (3 channels)
  const cmStats = await migrateClientMessages();

  // Summary
  console.log('\n=== SUMMARY ===');
  console.log(`Employee chats: ${ecStats.chats} chats, ${ecStats.messages} messages`);
  console.log(`Client network msgs:    ${cmStats.network}`);
  console.log(`Client management msgs: ${cmStats.management}`);
  console.log(`Client dialog msgs:     ${cmStats.dialog}`);
  const total = ecStats.chats + ecStats.messages + cmStats.network + cmStats.management + cmStats.dialog;
  const errors = ecStats.errors + cmStats.errors;
  console.log(`Total records: ${total}`);
  console.log(`Errors: ${errors}`);

  await db.close();
  process.exit(errors > 0 ? 1 : 0);
}

// ============================================
// Phase 1: Schema patches
// ============================================

async function patchSchema() {
  console.log('Phase 1: Schema patches...');

  const patches = [
    // employee_chats extensions
    `ALTER TABLE employee_chats ADD COLUMN IF NOT EXISTS participant_names JSONB`,
    `ALTER TABLE employee_chats ADD COLUMN IF NOT EXISTS shop_address TEXT`,
    `ALTER TABLE employee_chats ADD COLUMN IF NOT EXISTS shop_members TEXT[]`,
    `ALTER TABLE employee_chats ADD COLUMN IF NOT EXISTS creator_phone TEXT`,
    `ALTER TABLE employee_chats ADD COLUMN IF NOT EXISTS creator_name TEXT`,
    `ALTER TABLE employee_chats ADD COLUMN IF NOT EXISTS image_url TEXT`,

    // chat_messages extensions
    `ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS reactions JSONB`,
    `ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS forwarded_from JSONB`,

    // client_messages extensions
    `ALTER TABLE client_messages ADD COLUMN IF NOT EXISTS is_read_by_manager BOOLEAN DEFAULT false`,
    `ALTER TABLE client_messages ADD COLUMN IF NOT EXISTS is_broadcast BOOLEAN DEFAULT false`,
  ];

  let applied = 0;
  for (const sql of patches) {
    try {
      await db.query(sql);
      applied++;
    } catch (e) {
      // Column may already exist — that's fine
      if (!e.message.includes('already exists')) {
        console.warn(`  Patch warning: ${e.message}`);
      }
      applied++;
    }
  }
  console.log(`  Applied ${applied}/${patches.length} schema patches`);
}

// ============================================
// Phase 2: Employee chats
// ============================================

async function migrateEmployeeChats() {
  console.log('\nPhase 2: Migrate employee chats...');
  const stats = { chats: 0, messages: 0, errors: 0 };

  const chatsDir = path.join(DATA_DIR, 'employee-chats');
  let files;
  try {
    files = (await fsp.readdir(chatsDir)).filter(f => f.endsWith('.json'));
  } catch (e) {
    console.log(`  No employee-chats directory found: ${e.message}`);
    return stats;
  }

  console.log(`  Found ${files.length} chat files`);

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(chatsDir, file), 'utf8');
      const chat = JSON.parse(content);

      // Insert chat metadata
      await db.upsert('employee_chats', {
        id: chat.id,
        type: chat.type || 'general',
        name: chat.name || null,
        participants: chat.participants || null,
        participant_names: chat.participantNames || null,
        shop_address: chat.shopAddress || null,
        shop_members: chat.shopMembers || null,
        creator_phone: chat.creatorPhone || null,
        creator_name: chat.creatorName || null,
        image_url: chat.imageUrl || null,
        created_at: chat.createdAt || new Date().toISOString(),
        updated_at: chat.updatedAt || new Date().toISOString()
      });
      stats.chats++;

      // Insert messages
      const messages = chat.messages || [];
      for (let i = 0; i < messages.length; i++) {
        const msg = messages[i];
        try {
          const msgId = msg.id || `msg_migrated_${chat.id}_${i}_${Date.now()}`;
          await db.upsert('chat_messages', {
            id: msgId,
            chat_id: chat.id,
            sender_phone: msg.senderPhone || null,
            sender_name: msg.senderName || null,
            text: msg.text || null,
            image_url: msg.imageUrl || null,
            read_by: msg.readBy || [],
            reactions: msg.reactions || null,
            forwarded_from: msg.forwardedFrom || null,
            timestamp: msg.timestamp || new Date().toISOString()
          });
          stats.messages++;
        } catch (e) {
          if (!e.message.includes('duplicate key')) {
            console.error(`\n  Error msg ${msg.id || i} in ${chat.id}: ${e.message}`);
            stats.errors++;
          }
        }
      }

      process.stdout.write(`\r  Migrated ${stats.chats}/${files.length} chats, ${stats.messages} messages`);
    } catch (e) {
      console.error(`\n  Error file ${file}: ${e.message}`);
      stats.errors++;
    }
  }

  console.log(`\n  Done: ${stats.chats} chats, ${stats.messages} messages, ${stats.errors} errors`);
  return stats;
}

// ============================================
// Phase 3: Client messages
// ============================================

async function migrateClientMessages() {
  console.log('\nPhase 3: Migrate client messages...');
  const stats = { network: 0, management: 0, dialog: 0, errors: 0 };

  // 3a: Network messages (flat files per phone)
  await migrateClientChannel(
    path.join(DATA_DIR, 'client-messages-network'),
    'network',
    stats,
    'network'
  );

  // 3b: Management messages (flat files per phone)
  await migrateClientChannel(
    path.join(DATA_DIR, 'client-messages-management'),
    'management',
    stats,
    'management'
  );

  // 3c: Dialog messages (subdirectories per phone, files per shop)
  await migrateClientDialogMessages(
    path.join(DATA_DIR, 'client-messages'),
    stats
  );

  console.log(`  Done: network=${stats.network}, management=${stats.management}, dialog=${stats.dialog}, errors=${stats.errors}`);
  return stats;
}

/**
 * Migrate a flat channel directory: {phone}.json → client_messages rows
 */
async function migrateClientChannel(dir, channel, stats, statsKey) {
  let files;
  try {
    files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  } catch (e) {
    console.log(`  No ${channel} directory: ${e.message}`);
    return;
  }

  console.log(`  ${channel}: ${files.length} files`);

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      const dialog = JSON.parse(content);
      const phone = dialog.phone || file.replace('.json', '');

      for (const msg of (dialog.messages || [])) {
        try {
          const msgId = msg.id || `msg_migrated_${channel}_${phone}_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
          await db.upsert('client_messages', {
            id: msgId,
            client_phone: phone,
            channel: channel,
            shop_address: null,
            text: msg.text || null,
            image_url: msg.imageUrl || null,
            sender_type: msg.senderType || msg.from || null,
            sender_name: msg.senderName || null,
            sender_phone: msg.senderPhone || null,
            is_read_by_client: msg.isReadByClient === true || msg.readByClient === true,
            is_read_by_admin: msg.isReadByAdmin === true || msg.readByAdmin === true,
            is_read_by_manager: msg.isReadByManager === true,
            is_broadcast: msg.isBroadcast === true,
            data: null,
            timestamp: msg.timestamp || new Date().toISOString()
          });
          stats[statsKey]++;
        } catch (e) {
          if (!e.message.includes('duplicate key')) {
            stats.errors++;
          }
        }
      }
    } catch (e) {
      console.error(`  Error reading ${file}: ${e.message}`);
      stats.errors++;
    }
  }
}

/**
 * Migrate dialog messages: {phone}/{shop}.json → client_messages rows
 */
async function migrateClientDialogMessages(dir, stats) {
  let phoneDirs;
  try {
    phoneDirs = await fsp.readdir(dir);
  } catch (e) {
    console.log(`  No client-messages directory: ${e.message}`);
    return;
  }

  console.log(`  dialog: ${phoneDirs.length} phone directories`);

  for (const phoneDir of phoneDirs) {
    const phonePath = path.join(dir, phoneDir);
    try {
      const stat = await fsp.stat(phonePath);
      if (!stat.isDirectory()) continue;

      const files = (await fsp.readdir(phonePath)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const content = await fsp.readFile(path.join(phonePath, file), 'utf8');
          const dialog = JSON.parse(content);
          const phone = dialog.phone || phoneDir;
          const shopAddress = dialog.shopAddress || file.replace('.json', '');

          for (const msg of (dialog.messages || [])) {
            try {
              const msgId = msg.id || `msg_migrated_dialog_${phone}_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
              await db.upsert('client_messages', {
                id: msgId,
                client_phone: phone,
                channel: 'dialog',
                shop_address: shopAddress,
                text: msg.text || null,
                image_url: msg.imageUrl || null,
                sender_type: msg.senderType || msg.from || null,
                sender_name: msg.senderName || null,
                sender_phone: msg.senderPhone || null,
                is_read_by_client: msg.isReadByClient === true,
                is_read_by_admin: msg.isReadByAdmin === true,
                is_read_by_manager: false,
                is_broadcast: false,
                data: msg.data || null,
                timestamp: msg.timestamp || new Date().toISOString()
              });
              stats.dialog++;
            } catch (e) {
              if (!e.message.includes('duplicate key')) {
                stats.errors++;
              }
            }
          }
        } catch (e) {
          stats.errors++;
        }
      }
    } catch (e) {
      // Not a directory or read error — skip
    }
  }
}

main().catch(e => {
  console.error('Migration failed:', e);
  process.exit(1);
});

/**
 * Messenger API — полностью изолированный модуль мессенджера
 *
 * Таблицы: messenger_conversations, messenger_participants, messenger_messages
 * WebSocket: /ws/messenger (отдельный от /ws/employee-chat)
 * Медиа: /var/www/messenger-media/
 *
 * Ни один import не зависит от employee_chat модулей.
 */

const path = require('path');
const fsp = require('fs').promises;
const multer = require('multer');
const db = require('../utils/db');
const { requireAuth } = require('../utils/session_middleware');
const pushService = require('../utils/push_service');
const dataCache = require('../utils/data_cache');

// WebSocket уведомления (опционально)
let wsNotify = null;
try {
  wsNotify = require('./messenger_websocket');
} catch (e) {
  console.log('⚠️ Messenger WebSocket модуль не загружен');
}

const DATA_DIR = process.env.DATA_DIR || '/var/www';

/**
 * Генерация уникального ID
 */
function generateId(prefix) {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`;
}

/**
 * Check if phone is a participant of the conversation. Returns true/false.
 */
async function isParticipant(conversationId, phone) {
  const result = await db.query(
    'SELECT 1 FROM messenger_participants WHERE conversation_id = $1 AND phone = $2 LIMIT 1',
    [conversationId, phone]
  );
  return result.rows.length > 0;
}

/**
 * Основная функция инициализации API
 * @param {Express} app
 * @param {multer} uploadMedia — multer instance для загрузки файлов
 */
function setupMessengerAPI(app, uploadMedia) {

  // ============================================
  // CONVERSATIONS
  // ============================================

  /**
   * GET /api/messenger/conversations?phone=X&limit=50&offset=0
   * Список разговоров для пользователя с последним сообщением и непрочитанными
   */
  app.get('/api/messenger/conversations', requireAuth, async (req, res) => {
    try {
      const { limit = 50, offset = 0 } = req.query;
      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');
      const parsedLimit = Math.min(parseInt(limit) || 50, 100);
      const parsedOffset = parseInt(offset) || 0;

      // Оптимизировано: 2 запроса вместо N коррелированных подзапросов.
      // Запрос 1: диалоги + последнее сообщение + unread_count (без participants)
      const convResult = await db.query(`
        SELECT
          c.*,
          p.last_read_at,
          CASE WHEN lm.id IS NOT NULL THEN
            json_build_object(
              'id', lm.id, 'sender_phone', lm.sender_phone, 'sender_name', lm.sender_name,
              'type', lm.type, 'content', lm.content, 'media_url', lm.media_url,
              'voice_duration', lm.voice_duration, 'is_deleted', lm.is_deleted, 'created_at', lm.created_at
            )
          ELSE NULL END as last_message,
          p.unread_count
        FROM messenger_conversations c
        JOIN messenger_participants p ON p.conversation_id = c.id AND p.phone = $1
        LEFT JOIN LATERAL (
          SELECT id, sender_phone, sender_name, type, content, media_url, voice_duration, is_deleted, created_at
          FROM messenger_messages
          WHERE conversation_id = c.id AND is_deleted = false
            AND id NOT IN (SELECT message_id FROM messenger_hidden_messages WHERE phone = $1)
          ORDER BY created_at DESC
          LIMIT 1
        ) lm ON true
        ORDER BY COALESCE(lm.created_at, c.created_at) DESC
        LIMIT $2 OFFSET $3
      `, [normalizedPhone, parsedLimit, parsedOffset]);

      const conversations = convResult.rows;

      if (conversations.length > 0) {
        // Запрос 2: batch-загрузка всех участников для всех диалогов одним запросом
        const convIds = conversations.map(c => c.id);
        const partResult = await db.query(`
          SELECT pp.conversation_id, pp.phone, COALESCE(mp.display_name, pp.name) AS name, pp.role, pp.last_read_at, mp.avatar_url
          FROM messenger_participants pp
          LEFT JOIN messenger_profiles mp ON mp.phone = pp.phone
          WHERE pp.conversation_id = ANY($1)
        `, [convIds]);

        // Группируем участников по conversation_id
        const partMap = {};
        for (const row of partResult.rows) {
          if (!partMap[row.conversation_id]) partMap[row.conversation_id] = [];
          partMap[row.conversation_id].push({
            phone: row.phone,
            name: row.name,
            role: row.role,
            last_read_at: row.last_read_at,
            avatar_url: row.avatar_url,
          });
        }

        // Присоединяем участников к диалогам
        for (const conv of conversations) {
          conv.participants = partMap[conv.id] || [];
        }
      }

      res.json({ success: true, conversations });
    } catch (error) {
      console.error('[Messenger] GET conversations error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/conversations/private
   * Получить или создать приватный чат (1-на-1)
   */
  app.post('/api/messenger/conversations/private', requireAuth, async (req, res) => {
    try {
      const { phone2, name1, name2 } = req.body;
      if (!phone2) return res.status(400).json({ success: false, error: 'phone2 required' });

      const p1 = req.user.phone.replace(/[^\d]/g, '');
      const p2 = phone2.replace(/[^\d]/g, '');

      // Стабильный ID — sorted phones
      const sorted = [p1, p2].sort();
      const conversationId = `private_${sorted[0]}_${sorted[1]}`;

      // Проверяем существование
      const existing = await db.findById('messenger_conversations', conversationId);
      if (existing) {
        // Подтягиваем participants
        const parts = await db.query(
          'SELECT phone, name, role FROM messenger_participants WHERE conversation_id = $1',
          [conversationId]
        );
        return res.json({
          success: true,
          conversation: { ...existing, participants: parts.rows },
          created: false
        });
      }

      // Создаём новый
      const isSaved = p1 === p2; // "Избранное" — чат с самим собой
      await db.transaction(async (client) => {
        await client.query(
          `INSERT INTO messenger_conversations (id, type, name, created_at, updated_at)
           VALUES ($1, 'private', $2, NOW(), NOW())`,
          [conversationId, isSaved ? 'Избранное' : null]
        );
        if (isSaved) {
          // Один участник
          await client.query(
            `INSERT INTO messenger_participants (conversation_id, phone, name, role, joined_at)
             VALUES ($1, $2, $3, 'member', NOW())`,
            [conversationId, p1, name1 || null]
          );
        } else {
          await client.query(
            `INSERT INTO messenger_participants (conversation_id, phone, name, role, joined_at)
             VALUES ($1, $2, $3, 'member', NOW()), ($1, $4, $5, 'member', NOW())`,
            [conversationId, p1, name1 || null, p2, name2 || null]
          );
        }
      });

      // Invalidate WS participants cache so first message is delivered
      if (wsNotify) wsNotify.invalidateParticipantsCache(conversationId);

      const conversation = await db.findById('messenger_conversations', conversationId);
      const parts = await db.query(
        'SELECT phone, name, role FROM messenger_participants WHERE conversation_id = $1',
        [conversationId]
      );

      res.json({
        success: true,
        conversation: { ...conversation, participants: parts.rows },
        created: true
      });
    } catch (error) {
      console.error('[Messenger] POST conversations/private error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/conversations/group
   * Создать групповой чат
   */
  app.post('/api/messenger/conversations/group', requireAuth, async (req, res) => {
    try {
      const { creatorName, name, participants } = req.body;
      if (!name || !participants || participants.length < 1) {
        return res.status(400).json({ success: false, error: 'name, participants required (min 1 participant)' });
      }

      if (participants.length > 100) {
        return res.status(400).json({ success: false, error: 'Maximum 100 participants' });
      }

      const normalizedCreator = req.user.phone.replace(/[^\d]/g, '');
      const conversationId = generateId('group');

      await db.transaction(async (client) => {
        await client.query(
          `INSERT INTO messenger_conversations (id, type, name, creator_phone, creator_name, created_at, updated_at)
           VALUES ($1, 'group', $2, $3, $4, NOW(), NOW())`,
          [conversationId, name, normalizedCreator, creatorName || null]
        );

        // Создатель — admin
        await client.query(
          `INSERT INTO messenger_participants (conversation_id, phone, name, role, joined_at)
           VALUES ($1, $2, $3, 'admin', NOW())`,
          [conversationId, normalizedCreator, creatorName || null]
        );

        // Остальные участники — members
        for (const p of participants) {
          const pPhone = (p.phone || p).toString().replace(/[^\d]/g, '');
          if (pPhone === normalizedCreator) continue; // уже добавлен
          const pName = p.name || null;
          await client.query(
            `INSERT INTO messenger_participants (conversation_id, phone, name, role, joined_at)
             VALUES ($1, $2, $3, 'member', NOW())
             ON CONFLICT (conversation_id, phone) DO NOTHING`,
            [conversationId, pPhone, pName]
          );
        }
      });

      const conversation = await db.findById('messenger_conversations', conversationId);
      const parts = await db.query(
        'SELECT phone, name, role FROM messenger_participants WHERE conversation_id = $1',
        [conversationId]
      );

      res.json({
        success: true,
        conversation: { ...conversation, participants: parts.rows }
      });
    } catch (error) {
      console.error('[Messenger] POST conversations/group error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * GET /api/messenger/conversations/:id
   * Получить данные разговора
   */
  app.get('/api/messenger/conversations/:id', requireAuth, async (req, res) => {
    try {
      const requesterPhone = req.user.phone.replace(/[^\d]/g, '');
      const conversation = await db.findById('messenger_conversations', req.params.id);
      if (!conversation) return res.status(404).json({ success: false, error: 'Conversation not found' });

      if (!(await isParticipant(req.params.id, requesterPhone))) {
        return res.status(403).json({ success: false, error: 'Not a participant' });
      }

      const parts = await db.query(
        `SELECT mp.phone, COALESCE(p.display_name, mp.name) AS name, mp.role, mp.joined_at, mp.last_read_at, p.avatar_url
         FROM messenger_participants mp
         LEFT JOIN messenger_profiles p ON p.phone = mp.phone
         WHERE mp.conversation_id = $1`,
        [req.params.id]
      );

      res.json({ success: true, conversation: { ...conversation, participants: parts.rows } });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * PUT /api/messenger/conversations/:id
   * Обновить групповой чат (только создатель)
   */
  app.put('/api/messenger/conversations/:id', requireAuth, async (req, res) => {
    try {
      const { name, avatarUrl } = req.body;

      const conversation = await db.findById('messenger_conversations', req.params.id);
      if (!conversation) return res.status(404).json({ success: false, error: 'Not found' });
      if (conversation.type !== 'group') return res.status(400).json({ success: false, error: 'Only groups can be updated' });

      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');
      if (conversation.creator_phone !== normalizedPhone) {
        return res.status(403).json({ success: false, error: 'Only creator can update group' });
      }

      const updates = { updated_at: new Date().toISOString() };
      if (name !== undefined) updates.name = name;
      if (avatarUrl !== undefined) updates.avatar_url = avatarUrl;

      const updated = await db.updateById('messenger_conversations', req.params.id, updates);
      res.json({ success: true, conversation: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/messenger/conversations/:id
   * Удалить групповой чат (только создатель). CASCADE удалит participants и messages.
   */
  app.delete('/api/messenger/conversations/:id', requireAuth, async (req, res) => {
    try {
      const conversation = await db.findById('messenger_conversations', req.params.id);
      if (!conversation) return res.status(404).json({ success: false, error: 'Not found' });

      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');
      if (conversation.type === 'group' && conversation.creator_phone !== normalizedPhone) {
        return res.status(403).json({ success: false, error: 'Only creator can delete group' });
      }

      await db.deleteById('messenger_conversations', req.params.id);
      if (wsNotify) wsNotify.invalidateParticipantsCache(req.params.id);

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // PARTICIPANTS (GROUP MANAGEMENT)
  // ============================================

  /**
   * POST /api/messenger/conversations/:id/participants
   * Добавить участников в группу (только создатель)
   */
  app.post('/api/messenger/conversations/:id/participants', requireAuth, async (req, res) => {
    try {
      const { phones } = req.body;
      if (!phones || !phones.length) {
        return res.status(400).json({ success: false, error: 'phones[] required' });
      }

      const conversation = await db.findById('messenger_conversations', req.params.id);
      if (!conversation || conversation.type !== 'group') {
        return res.status(400).json({ success: false, error: 'Group not found' });
      }

      const normalizedRequester = req.user.phone.replace(/[^\d]/g, '');
      if (conversation.creator_phone !== normalizedRequester) {
        return res.status(403).json({ success: false, error: 'Only creator can add members' });
      }

      const added = [];
      for (const p of phones) {
        const pPhone = (p.phone || p).toString().replace(/[^\d]/g, '');
        const pName = p.name || null;
        try {
          await db.query(
            `INSERT INTO messenger_participants (conversation_id, phone, name, role, joined_at)
             VALUES ($1, $2, $3, 'member', NOW())
             ON CONFLICT (conversation_id, phone) DO NOTHING`,
            [req.params.id, pPhone, pName]
          );
          added.push(pPhone);
        } catch (e) {
          // пропускаем дубликаты
        }
      }

      if (wsNotify) wsNotify.invalidateParticipantsCache(req.params.id);
      res.json({ success: true, added });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/messenger/conversations/:id/participants/:phone
   * Удалить участника из группы (только создатель)
   */
  app.delete('/api/messenger/conversations/:id/participants/:phone', requireAuth, async (req, res) => {
    try {
      const conversation = await db.findById('messenger_conversations', req.params.id);
      if (!conversation || conversation.type !== 'group') {
        return res.status(400).json({ success: false, error: 'Group not found' });
      }

      const normalizedRequester = req.user.phone.replace(/[^\d]/g, '');
      if (conversation.creator_phone !== normalizedRequester) {
        return res.status(403).json({ success: false, error: 'Only creator can remove members' });
      }

      const targetPhone = req.params.phone.replace(/[^\d]/g, '');
      await db.query(
        'DELETE FROM messenger_participants WHERE conversation_id = $1 AND phone = $2',
        [req.params.id, targetPhone]
      );

      if (wsNotify) wsNotify.invalidateParticipantsCache(req.params.id);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/conversations/:id/leave
   * Выйти из группы
   */
  app.post('/api/messenger/conversations/:id/leave', requireAuth, async (req, res) => {
    try {
      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');
      await db.query(
        'DELETE FROM messenger_participants WHERE conversation_id = $1 AND phone = $2',
        [req.params.id, normalizedPhone]
      );

      if (wsNotify) wsNotify.invalidateParticipantsCache(req.params.id);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // MESSAGES
  // ============================================

  /**
   * GET /api/messenger/conversations/:id/messages?limit=50&before=ISO
   * Получить сообщения с пагинацией (от новых к старым)
   */
  app.get('/api/messenger/conversations/:id/messages', requireAuth, async (req, res) => {
    try {
      const { limit = 50, before } = req.query;
      const conversationId = req.params.id;

      const requesterPhone = req.user.phone.replace(/[^\d]/g, '');

      // Security: verify requester is a participant of this conversation
      if (!(await isParticipant(conversationId, requesterPhone))) {
        return res.status(403).json({ success: false, error: 'Not a participant' });
      }

      let sql = `
        SELECT * FROM messenger_messages
        WHERE conversation_id = $1 AND is_deleted = false
          AND id NOT IN (SELECT message_id FROM messenger_hidden_messages WHERE phone = $2)
          AND sender_phone NOT IN (SELECT blocked_phone FROM messenger_blocks WHERE blocker_phone = $2)
      `;
      const params = [conversationId, requesterPhone];
      let paramIdx = 3;

      if (before) {
        sql += ` AND created_at < $${paramIdx}`;
        params.push(before);
        paramIdx++;
      }

      sql += ` ORDER BY created_at DESC LIMIT $${paramIdx}`;
      params.push(Math.min(parseInt(limit) || 50, 200));

      const result = await db.query(sql, params);

      // Возвращаем в хронологическом порядке (старые → новые)
      const messages = result.rows.reverse();
      res.json({ success: true, messages });
    } catch (error) {
      console.error('[Messenger] GET messages error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/conversations/:id/messages
   * Отправить сообщение
   */
  app.post('/api/messenger/conversations/:id/messages', requireAuth, async (req, res) => {
    try {
      // Rate limit check
      const rateLimitPhone = req.user.phone.replace(/[^\d]/g, '');
      if (!checkMessageRateLimit(rateLimitPhone)) {
        return res.status(429).json({ success: false, error: 'Too many messages. Try again in a minute.' });
      }

      const { type = 'text', content, mediaUrl, voiceDuration, replyToId, fileName, fileSize, mediaGroupId } = req.body;
      // SECURITY: берём телефон из токена авторизации, игнорируем req.body.senderPhone
      let senderName = req.user.name || null;

      // Fallback: если имя не в токене, ищем в профиле мессенджера / сотрудниках / клиентах
      if (!senderName) {
        try {
          const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');
          // 1. messenger_profiles
          const prof = await db.query(
            'SELECT display_name FROM messenger_profiles WHERE phone = $1',
            [normalizedPhone]
          );
          if (prof.rows[0]?.display_name) {
            senderName = prof.rows[0].display_name;
          } else {
            // 2. employees (from cache)
            const employees = dataCache.getEmployees();
            if (employees) {
              const emp = employees.find(e => (e.phone || '').replace(/[^\d]/g, '') === normalizedPhone);
              if (emp?.name) senderName = emp.name;
            }
            // 3. clients table
            if (!senderName) {
              const client = await db.findById('clients', normalizedPhone, 'phone');
              if (client?.name) senderName = client.name;
            }
          }
        } catch (_) { /* name resolution failure is not critical */ }
      }

      const conversationId = req.params.id;
      const normalizedSender = req.user.phone.replace(/[^\d]/g, '');

      // Проверяем что отправитель — участник
      const participant = await db.query(
        'SELECT phone, role FROM messenger_participants WHERE conversation_id = $1 AND phone = $2',
        [conversationId, normalizedSender]
      );
      if (participant.rows.length === 0) {
        return res.status(403).json({ success: false, error: 'Not a participant' });
      }

      // Check block status in private chats
      const conv = await db.findById('messenger_conversations', conversationId);
      if (conv && conv.type === 'private') {
        const otherParticipant = await db.query(
          'SELECT phone FROM messenger_participants WHERE conversation_id = $1 AND phone != $2 LIMIT 1',
          [conversationId, normalizedSender]
        );
        if (otherParticipant.rows.length > 0) {
          const otherPhone = otherParticipant.rows[0].phone;
          const blocked = await db.query(
            'SELECT 1 FROM messenger_blocks WHERE (blocker_phone = $1 AND blocked_phone = $2) OR (blocker_phone = $2 AND blocked_phone = $1) LIMIT 1',
            [normalizedSender, otherPhone]
          );
          if (blocked.rows.length > 0) {
            return res.status(403).json({ success: false, error: 'blocked' });
          }
        }
      }

      // Channel: only admin or writer can post
      if (conv && conv.type === 'channel') {
        const senderRole = participant.rows[0]?.role;
        if (senderRole !== 'admin' && senderRole !== 'creator' && senderRole !== 'writer') {
          return res.status(403).json({ success: false, error: 'Only admin/writers can post in channels' });
        }
      }

      const messageId = generateId('msg');
      const message = {
        id: messageId,
        conversation_id: conversationId,
        sender_phone: normalizedSender,
        sender_name: senderName || null,
        type: type,
        content: content || null,
        media_url: mediaUrl || null,
        voice_duration: voiceDuration || null,
        reply_to_id: replyToId || null,
        reactions: JSON.stringify({}),
        is_deleted: false,
        created_at: new Date().toISOString(),
        file_name: type === 'file' ? (fileName || null) : null,
        file_size: type === 'file' ? (fileSize || null) : null,
        media_group_id: (type === 'image' || type === 'video') ? (mediaGroupId || null) : null,
      };

      await db.insert('messenger_messages', message);

      // Обновляем updated_at разговора
      await db.updateById('messenger_conversations', conversationId, {
        updated_at: new Date().toISOString()
      });

      // Обновляем last_read_at для отправителя + обнуляем его unread
      await db.query(
        'UPDATE messenger_participants SET last_read_at = NOW(), unread_count = 0 WHERE conversation_id = $1 AND phone = $2',
        [conversationId, normalizedSender]
      );

      // Инкрементируем unread_count для остальных участников
      await db.query(
        'UPDATE messenger_participants SET unread_count = unread_count + 1 WHERE conversation_id = $1 AND phone != $2',
        [conversationId, normalizedSender]
      );

      // WebSocket уведомление (targeted)
      const responseMessage = { ...message, reactions: {} };
      if (wsNotify) {
        try {
          await wsNotify.notifyNewMessage(conversationId, responseMessage, normalizedSender);
        } catch (e) {
          console.error('[Messenger] WS notify error:', e.message);
        }
      }

      // Push уведомления остальным участникам
      try {
        const participantsResult = await db.query(
          'SELECT phone, muted_until FROM messenger_participants WHERE conversation_id = $1 AND phone != $2',
          [conversationId, normalizedSender]
        );

        const preview = type === 'text' ? (content || '').substring(0, 100)
          : type === 'voice' ? '🎤 Голосовое сообщение'
          : type === 'image' ? '📷 Фото'
          : type === 'video' ? '🎬 Видео'
          : type === 'video_note' ? '📹 Видео-кружок'
          : type === 'emoji' ? content || '😀'
          : type === 'file' ? `📎 ${fileName || 'Документ'}`
          : type === 'sticker' ? '🎨 Стикер'
          : type === 'gif' ? 'GIF'
          : type === 'poll' ? '📊 Опрос'
          : type === 'contact' ? '👤 Контакт'
          : 'Новое сообщение';

        // Push title: group name for groups/channels, sender name for private
        const senderDisplayName = senderName || normalizedSender;
        const isGroupOrChannel = conv && (conv.type === 'group' || conv.type === 'channel');
        const pushTitle = isGroupOrChannel ? (conv.name || 'Группа') : senderDisplayName;
        const pushPreview = isGroupOrChannel ? `${senderDisplayName}: ${preview}` : preview;

        for (const p of participantsResult.rows) {
          // Не отправляем push онлайн-пользователям
          if (wsNotify && wsNotify.isUserOnline(p.phone)) continue;
          // Не отправляем push замьюченным пользователям
          if (p.muted_until && new Date(p.muted_until) > new Date()) continue;
          pushService.sendPushToPhone(p.phone, pushTitle, pushPreview, {
            type: 'messenger_message',
            conversationId,
            senderPhone: normalizedSender,
            senderName: senderName || '',
          }, 'messenger_channel').catch(() => {});
        }
      } catch (e) {
        // Push ошибки не блокируют ответ
      }

      res.json({ success: true, message: responseMessage });
    } catch (error) {
      console.error('[Messenger] POST message error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * PUT /api/messenger/conversations/:id/messages/:msgId
   * Edit message content (sender only, text only, within 48h)
   */
  app.put('/api/messenger/conversations/:id/messages/:msgId', requireAuth, async (req, res) => {
    try {
      const { content } = req.body;
      if (!content || !content.trim()) {
        return res.status(400).json({ success: false, error: 'content required' });
      }

      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');
      const message = await db.findById('messenger_messages', req.params.msgId);
      if (!message || message.conversation_id !== req.params.id) {
        return res.status(404).json({ success: false, error: 'Message not found' });
      }

      // Only sender can edit
      if (message.sender_phone !== normalizedPhone) {
        return res.status(403).json({ success: false, error: 'Only sender can edit' });
      }

      // Only text messages
      if (message.type !== 'text') {
        return res.status(400).json({ success: false, error: 'Only text messages can be edited' });
      }

      // Not deleted
      if (message.is_deleted) {
        return res.status(400).json({ success: false, error: 'Cannot edit deleted message' });
      }

      // Within 5 minutes
      const createdAt = new Date(message.created_at);
      const minutesAgo = (Date.now() - createdAt.getTime()) / (1000 * 60);
      if (minutesAgo > 5) {
        return res.status(400).json({ success: false, error: 'Cannot edit messages older than 5 minutes' });
      }

      const editedAt = new Date().toISOString();
      await db.updateById('messenger_messages', req.params.msgId, {
        content: content.trim(),
        edited_at: editedAt,
      });

      // Notify via WS
      if (wsNotify) {
        try {
          await wsNotify.notifyMessageEdited(req.params.id, req.params.msgId, content.trim(), editedAt);
        } catch (e) { console.error('WS notifyMessageEdited error:', e.message); }
      }

      res.json({ success: true, editedAt });
    } catch (error) {
      console.error('[Messenger] PUT message edit error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/conversations/:id/messages/:msgId/delivered
   * Fallback delivery confirmation (when WS is unavailable)
   */
  app.post('/api/messenger/conversations/:id/messages/:msgId/delivered', requireAuth, async (req, res) => {
    try {
      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');
      if (!(await isParticipant(req.params.id, normalizedPhone))) {
        return res.status(403).json({ success: false, error: 'Not a participant' });
      }
      const msgId = req.params.msgId;

      await db.query(
        `UPDATE messenger_messages
         SET delivered_to = (
           SELECT jsonb_agg(DISTINCT val)
           FROM jsonb_array_elements_text(COALESCE(delivered_to, '[]'::jsonb) || $2::jsonb) AS val
         )
         WHERE id = $1 AND conversation_id = $3`,
        [msgId, JSON.stringify([normalizedPhone]), req.params.id]
      );

      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] POST delivered error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/messenger/conversations/:id/messages/:msgId?mode=forMe|forAll
   * mode=forMe  — скрыть только у себя (messenger_hidden_messages)
   * mode=forAll — удалить для всех (is_deleted=true), только своё, в течение 1 часа
   */
  app.delete('/api/messenger/conversations/:id/messages/:msgId', requireAuth, async (req, res) => {
    try {
      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');
      const mode = req.query.mode || 'forAll';
      const message = await db.findById('messenger_messages', req.params.msgId);
      if (!message || message.conversation_id !== req.params.id) {
        return res.status(404).json({ success: false, error: 'Message not found' });
      }

      if (mode === 'forMe') {
        // Hide for current user only
        await db.query(
          `INSERT INTO messenger_hidden_messages (phone, message_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
          [normalizedPhone, req.params.msgId]
        );
        return res.json({ success: true, mode: 'forMe' });
      }

      // mode=forAll — delete for everyone
      const isSender = message.sender_phone === normalizedPhone;
      if (!isSender) {
        const conversation = await db.findById('messenger_conversations', req.params.id);
        if (!conversation || conversation.creator_phone !== normalizedPhone) {
          return res.status(403).json({ success: false, error: 'Cannot delete for all — not sender or admin' });
        }
      }

      // Check 1-hour limit for forAll
      const createdAt = new Date(message.created_at);
      const minutesAgo = (Date.now() - createdAt.getTime()) / (1000 * 60);
      if (minutesAgo > 60) {
        return res.status(400).json({ success: false, error: 'Cannot delete for all — older than 1 hour' });
      }

      await db.updateById('messenger_messages', req.params.msgId, { is_deleted: true });

      if (wsNotify) {
        try {
          await wsNotify.notifyMessageDeleted(req.params.id, req.params.msgId);
        } catch (e) { console.error('WS notifyMessageDeleted error:', e.message); }
      }

      res.json({ success: true, mode: 'forAll' });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * GET /api/messenger/conversations/:id/messages/search?query=X&limit=50
   * Поиск сообщений в разговоре
   */
  app.get('/api/messenger/conversations/:id/messages/search', requireAuth, async (req, res) => {
    try {
      const requesterPhone = req.user.phone.replace(/[^\d]/g, '');
      if (!(await isParticipant(req.params.id, requesterPhone))) {
        return res.status(403).json({ success: false, error: 'Not a participant' });
      }

      const { query: searchQuery, limit = 50 } = req.query;
      if (!searchQuery) return res.json({ success: true, messages: [] });

      const result = await db.query(
        `SELECT * FROM messenger_messages
         WHERE conversation_id = $1 AND is_deleted = false
           AND content ILIKE $2
         ORDER BY created_at DESC
         LIMIT $3`,
        [req.params.id, `%${searchQuery}%`, Math.min(parseInt(limit) || 50, 200)]
      );

      res.json({ success: true, messages: result.rows.reverse() });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // READ RECEIPTS
  // ============================================

  /**
   * POST /api/messenger/conversations/:id/read
   * Отметить разговор как прочитанный
   */
  app.post('/api/messenger/conversations/:id/read', requireAuth, async (req, res) => {
    try {
      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');
      const now = new Date().toISOString();

      await db.query(
        'UPDATE messenger_participants SET last_read_at = $1, unread_count = 0 WHERE conversation_id = $2 AND phone = $3',
        [now, req.params.id, normalizedPhone]
      );

      if (wsNotify) {
        try {
          await wsNotify.notifyReadReceipt(req.params.id, normalizedPhone, now);
        } catch (e) { console.error('WS notifyReadReceipt error:', e.message); }
      }

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // REACTIONS
  // ============================================

  /**
   * POST /api/messenger/conversations/:id/messages/:msgId/reactions
   */
  app.post('/api/messenger/conversations/:id/messages/:msgId/reactions', requireAuth, async (req, res) => {
    try {
      const { reaction } = req.body;
      if (!reaction) return res.status(400).json({ success: false, error: 'reaction required' });

      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');

      // Атомарная операция: FOR UPDATE предотвращает потерю реакций при одновременных запросах
      const reactions = await db.transaction(async (client) => {
        const result = await client.query(
          'SELECT reactions FROM messenger_messages WHERE id = $1 AND conversation_id = $2 FOR UPDATE',
          [req.params.msgId, req.params.id]
        );
        if (result.rows.length === 0) throw { status: 404, message: 'Message not found' };

        const reactions = result.rows[0].reactions || {};
        if (!reactions[reaction]) reactions[reaction] = [];
        if (!reactions[reaction].includes(normalizedPhone)) {
          reactions[reaction].push(normalizedPhone);
        }

        await client.query(
          'UPDATE messenger_messages SET reactions = $1 WHERE id = $2',
          [JSON.stringify(reactions), req.params.msgId]
        );
        return reactions;
      });

      if (wsNotify) {
        try {
          await wsNotify.notifyReactionAdded(req.params.id, req.params.msgId, reaction, normalizedPhone);
        } catch (e) { console.error('WS notifyReactionAdded error:', e.message); }
      }

      res.json({ success: true, reactions });
    } catch (error) {
      if (error.status === 404) return res.status(404).json({ success: false, error: error.message });
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/messenger/conversations/:id/messages/:msgId/reactions?phone=X&reaction=Y
   */
  app.delete('/api/messenger/conversations/:id/messages/:msgId/reactions', requireAuth, async (req, res) => {
    try {
      const { reaction } = req.query;
      if (!reaction) return res.status(400).json({ success: false, error: 'reaction required' });

      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');

      // Атомарная операция: FOR UPDATE предотвращает потерю реакций при одновременных запросах
      const reactions = await db.transaction(async (client) => {
        const result = await client.query(
          'SELECT reactions FROM messenger_messages WHERE id = $1 AND conversation_id = $2 FOR UPDATE',
          [req.params.msgId, req.params.id]
        );
        if (result.rows.length === 0) throw { status: 404, message: 'Message not found' };

        const reactions = result.rows[0].reactions || {};
        if (reactions[reaction]) {
          reactions[reaction] = reactions[reaction].filter(p => p !== normalizedPhone);
          if (reactions[reaction].length === 0) delete reactions[reaction];
        }

        await client.query(
          'UPDATE messenger_messages SET reactions = $1 WHERE id = $2',
          [JSON.stringify(reactions), req.params.msgId]
        );
        return reactions;
      });

      if (wsNotify) {
        try {
          await wsNotify.notifyReactionRemoved(req.params.id, req.params.msgId, reaction, normalizedPhone);
        } catch (e) { console.error('WS notifyReactionRemoved error:', e.message); }
      }

      res.json({ success: true, reactions });
    } catch (error) {
      if (error.status === 404) return res.status(404).json({ success: false, error: error.message });
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // PIN MESSAGES
  // ============================================

  /**
   * PUT /api/messenger/conversations/:id/messages/:msgId/pin
   * Pin a message in the conversation
   */
  app.put('/api/messenger/conversations/:id/messages/:msgId/pin', requireAuth, async (req, res) => {
    try {
      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');

      const message = await db.findById('messenger_messages', req.params.msgId);
      if (!message || message.conversation_id !== req.params.id) {
        return res.status(404).json({ success: false, error: 'Message not found' });
      }

      const pinnedAt = new Date().toISOString();
      await db.updateById('messenger_messages', req.params.msgId, {
        is_pinned: true,
        pinned_at: pinnedAt,
        pinned_by: normalizedPhone,
      });

      if (wsNotify) {
        try {
          await wsNotify.broadcastToConversation(req.params.id, {
            type: 'message_pinned',
            conversationId: req.params.id,
            messageId: req.params.msgId,
            pinnedBy: normalizedPhone,
            pinnedAt,
            timestamp: new Date().toISOString(),
          });
        } catch (e) { console.error('WS pin notify error:', e.message); }
      }

      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] PIN error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/messenger/conversations/:id/messages/:msgId/pin
   * Unpin a message
   */
  app.delete('/api/messenger/conversations/:id/messages/:msgId/pin', requireAuth, async (req, res) => {
    try {
      const message = await db.findById('messenger_messages', req.params.msgId);
      if (!message || message.conversation_id !== req.params.id) {
        return res.status(404).json({ success: false, error: 'Message not found' });
      }

      await db.updateById('messenger_messages', req.params.msgId, {
        is_pinned: false,
        pinned_at: null,
        pinned_by: null,
      });

      if (wsNotify) {
        try {
          await wsNotify.broadcastToConversation(req.params.id, {
            type: 'message_unpinned',
            conversationId: req.params.id,
            messageId: req.params.msgId,
            timestamp: new Date().toISOString(),
          });
        } catch (e) { console.error('WS unpin notify error:', e.message); }
      }

      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] UNPIN error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * GET /api/messenger/conversations/:id/pinned
   * Get pinned messages in a conversation
   */
  app.get('/api/messenger/conversations/:id/pinned', requireAuth, async (req, res) => {
    try {
      const result = await db.query(
        `SELECT * FROM messenger_messages WHERE conversation_id = $1 AND is_pinned = true ORDER BY pinned_at DESC`,
        [req.params.id]
      );
      res.json({ success: true, messages: result.rows });
    } catch (error) {
      console.error('[Messenger] GET pinned error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // FORWARD
  // ============================================

  /**
   * POST /api/messenger/forward
   * Переслать сообщение в один или несколько чатов
   * Body: { sourceMessageId, targetConversationIds: string[] }
   */
  app.post('/api/messenger/forward', requireAuth, async (req, res) => {
    try {
      const { sourceMessageId, targetConversationIds } = req.body;
      if (!sourceMessageId || !targetConversationIds || !Array.isArray(targetConversationIds) || targetConversationIds.length === 0) {
        return res.status(400).json({ success: false, error: 'sourceMessageId and targetConversationIds[] required' });
      }

      const senderPhone = req.user.phone.replace(/[^\d]/g, '');
      const senderName = req.user.name || senderPhone;

      // Get source message
      const source = await db.findById('messenger_messages', sourceMessageId);
      if (!source) return res.status(404).json({ success: false, error: 'Source message not found' });

      const forwardedFromName = source.sender_name || source.sender_phone;
      const results = [];

      for (const targetConvId of targetConversationIds.slice(0, 10)) {
        // Check sender is a participant
        const participant = await db.query(
          'SELECT phone FROM messenger_participants WHERE conversation_id = $1 AND phone = $2',
          [targetConvId, senderPhone]
        );
        if (participant.rows.length === 0) continue;

        const msgId = generateId('msg');
        const now = new Date().toISOString();
        const message = {
          id: msgId,
          conversation_id: targetConvId,
          sender_phone: senderPhone,
          sender_name: senderName,
          type: source.type,
          content: source.content || null,
          media_url: source.media_url || null,
          voice_duration: source.voice_duration || null,
          reply_to_id: null,
          reactions: JSON.stringify({}),
          is_deleted: false,
          created_at: now,
          file_name: source.file_name || null,
          file_size: source.file_size || null,
          forwarded_from_id: sourceMessageId,
          forwarded_from_name: forwardedFromName,
        };

        await db.insert('messenger_messages', message);
        await db.updateById('messenger_conversations', targetConvId, { updated_at: now });

        const responseMessage = { ...message, reactions: {} };
        if (wsNotify) {
          try { await wsNotify.notifyNewMessage(targetConvId, responseMessage, senderPhone); }
          catch (e) { console.error('[Messenger] WS forward notify error:', e.message); }
        }
        results.push({ conversationId: targetConvId, messageId: msgId });
      }

      res.json({ success: true, forwarded: results });
    } catch (error) {
      console.error('[Messenger] Forward error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // MEDIA UPLOAD (with rate limiting)
  // ============================================

  // Simple in-memory rate limiter: max 10 uploads per minute per user
  const uploadRateMap = new Map(); // phone → { count, resetAt }
  const UPLOAD_RATE_LIMIT = 10;
  const UPLOAD_RATE_WINDOW_MS = 60 * 1000; // 1 minute

  function checkUploadRateLimit(phone) {
    const now = Date.now();
    const entry = uploadRateMap.get(phone);
    if (!entry || now > entry.resetAt) {
      uploadRateMap.set(phone, { count: 1, resetAt: now + UPLOAD_RATE_WINDOW_MS });
      return true;
    }
    if (entry.count >= UPLOAD_RATE_LIMIT) return false;
    entry.count++;
    return true;
  }

  // Simple in-memory rate limiter: max 30 messages per minute per user
  const messageRateMap = new Map(); // phone → { count, resetAt }
  const MESSAGE_RATE_LIMIT = 30;
  const MESSAGE_RATE_WINDOW_MS = 60 * 1000; // 1 minute

  function checkMessageRateLimit(phone) {
    const now = Date.now();
    const entry = messageRateMap.get(phone);
    if (!entry || now > entry.resetAt) {
      messageRateMap.set(phone, { count: 1, resetAt: now + MESSAGE_RATE_WINDOW_MS });
      return true;
    }
    if (entry.count >= MESSAGE_RATE_LIMIT) return false;
    entry.count++;
    return true;
  }

  // Cleanup stale rate entries every 5 minutes
  setInterval(() => {
    const now = Date.now();
    for (const [phone, entry] of uploadRateMap) {
      if (now > entry.resetAt) uploadRateMap.delete(phone);
    }
    for (const [phone, entry] of messageRateMap) {
      if (now > entry.resetAt) messageRateMap.delete(phone);
    }
  }, 5 * 60 * 1000);

  /**
   * POST /api/messenger/upload
   * Загрузка медиа-файлов (фото, видео, голосовые)
   */
  if (uploadMedia) {
    const { compressUpload } = require('../utils/image_compress');
    const { compressVideo } = require('../utils/video_compress');

    app.post('/api/messenger/upload', requireAuth, (req, res, next) => {
      // Rate limit check before accepting file
      const phone = req.user.phone.replace(/[^\d]/g, '');
      if (!checkUploadRateLimit(phone)) {
        return res.status(429).json({ success: false, error: 'Too many uploads. Try again in a minute.' });
      }
      next();
    }, uploadMedia.single('file'), compressUpload, compressVideo, async (req, res) => {
      try {
        if (!req.file) return res.status(400).json({ success: false, error: 'No file uploaded' });

        // Deduplication: compute hash via streaming (avoids loading entire file into memory)
        let finalFilename = req.file.filename;
        try {
          const crypto = require('crypto');
          const fs = require('fs');
          const hash = await new Promise((resolve, reject) => {
            const h = crypto.createHash('md5');
            const stream = fs.createReadStream(req.file.path);
            stream.on('data', chunk => h.update(chunk));
            stream.on('end', () => resolve(h.digest('hex')));
            stream.on('error', reject);
          });
          const ext = path.extname(req.file.filename);
          const hashFilename = `dedup_${hash}${ext}`;
          const hashPath = path.join(path.dirname(req.file.path), hashFilename);

          try {
            await fsp.access(hashPath);
            // Duplicate exists — remove new upload, use existing
            await fsp.unlink(req.file.path);
            finalFilename = hashFilename;
            console.log(`[Messenger] Dedup: ${req.file.originalname} → existing ${hashFilename}`);
          } catch (_) {
            // No duplicate — rename to hash-based name (handle race condition)
            try {
              await fsp.rename(req.file.path, hashPath);
            } catch (renameErr) {
              if (renameErr.code === 'EEXIST') {
                // Concurrent upload created the same file — use existing
                await fsp.unlink(req.file.path).catch(() => {});
              } else {
                throw renameErr;
              }
            }
            finalFilename = hashFilename;
          }
        } catch (dedupErr) {
          // Dedup failed — use original filename (safe fallback)
          console.error('[Messenger] Dedup error (using original):', dedupErr.message);
        }

        const mediaUrl = `https://arabica26.ru/messenger-media/${finalFilename}`;
        console.log(`[Messenger] Upload: ${finalFilename} (${(req.file.size / 1024).toFixed(1)}KB)`);

        res.json({
          success: true,
          url: mediaUrl,
          filename: finalFilename,
          originalName: req.file.originalname,
          fileSize: req.file.size,
        });
      } catch (error) {
        console.error('[Messenger] Upload error:', error.message);
        res.status(500).json({ success: false, error: error.message });
      }
    });
  }

  // ============================================
  // CONTACT SEARCH
  // ============================================

  /**
   * GET /api/messenger/contacts/search?query=X&limit=20
   * Поиск зарегистрированных пользователей по телефону или имени
   */
  app.get('/api/messenger/contacts/search', requireAuth, async (req, res) => {
    try {
      const { query: searchQuery, limit = 50 } = req.query;
      const parsedLimit = Math.min(parseInt(limit) || 50, 200);

      let employeesResult, clientsResult;

      if (!searchQuery || searchQuery.length < 2) {
        // Без запроса — возвращаем всех (сотрудники первые, потом клиенты)
        employeesResult = await db.query(
          `SELECT phone, name, 'employee' as user_type FROM employees
           WHERE phone IS NOT NULL
           ORDER BY name ASC NULLS LAST
           LIMIT $1`,
          [parsedLimit]
        );
        clientsResult = await db.query(
          `SELECT phone, name, 'client' as user_type FROM clients
           WHERE phone IS NOT NULL
           ORDER BY name ASC NULLS LAST
           LIMIT $1`,
          [parsedLimit]
        );
      } else {
        // С запросом — фильтруем по phone/name
        employeesResult = await db.query(
          `SELECT phone, name, 'employee' as user_type FROM employees
           WHERE (phone ILIKE $1 OR name ILIKE $1)
             AND phone IS NOT NULL
           LIMIT $2`,
          [`%${searchQuery}%`, parsedLimit]
        );
        clientsResult = await db.query(
          `SELECT phone, name, 'client' as user_type FROM clients
           WHERE (phone ILIKE $1 OR name ILIKE $1)
             AND phone IS NOT NULL
           LIMIT $2`,
          [`%${searchQuery}%`, parsedLimit]
        );
      }

      // Объединяем, убираем дубликаты по phone
      const contactsMap = new Map();
      for (const row of [...employeesResult.rows, ...clientsResult.rows]) {
        if (!contactsMap.has(row.phone)) {
          contactsMap.set(row.phone, {
            phone: row.phone,
            name: row.name,
            userType: row.user_type
          });
        }
      }

      const contacts = Array.from(contactsMap.values()).slice(0, parsedLimit);
      res.json({ success: true, contacts });
    } catch (error) {
      console.error('[Messenger] Contact search error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/contacts/by-phones
   * Найти зарегистрированных пользователей по списку телефонов (из телефонной книги)
   */
  app.post('/api/messenger/contacts/by-phones', requireAuth, async (req, res) => {
    try {
      const { phones } = req.body;
      if (!phones || !phones.length) return res.json({ success: true, contacts: [] });

      // Нормализуем телефоны
      const normalizedPhones = phones.map(p => p.toString().replace(/[^\d]/g, '')).filter(p => p.length >= 10);
      if (!normalizedPhones.length) return res.json({ success: true, contacts: [] });

      // Ищем среди employees
      const empResult = await db.query(
        `SELECT phone, name, 'employee' as user_type FROM employees WHERE phone = ANY($1)`,
        [normalizedPhones]
      );

      // Ищем среди clients
      const clientResult = await db.query(
        `SELECT phone, name, 'client' as user_type FROM clients WHERE phone = ANY($1)`,
        [normalizedPhones]
      );

      const contactsMap = new Map();
      for (const row of [...empResult.rows, ...clientResult.rows]) {
        if (!contactsMap.has(row.phone)) {
          contactsMap.set(row.phone, {
            phone: row.phone,
            name: row.name,
            userType: row.user_type
          });
        }
      }

      res.json({ success: true, contacts: Array.from(contactsMap.values()) });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // UNREAD COUNT (для badge в навигации)
  // ============================================

  /**
   * GET /api/messenger/unread?phone=X
   * Общее количество непрочитанных сообщений
   */
  app.get('/api/messenger/unread', requireAuth, async (req, res) => {
    try {
      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');

      // Оптимизировано: SUM по денормализованному unread_count вместо COUNT по всем сообщениям
      const result = await db.query(`
        SELECT COALESCE(SUM(unread_count), 0)::int as total_unread
        FROM messenger_participants
        WHERE phone = $1
      `, [normalizedPhone]);

      res.json({ success: true, unreadCount: result.rows[0].total_unread });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // USER PROFILE
  // ============================================

  /**
   * GET /api/messenger/profile?phone=X
   * Профиль пользователя (display_name, avatar_url)
   */
  app.get('/api/messenger/profile', requireAuth, async (req, res) => {
    try {
      const { phone } = req.query;
      if (!phone) return res.status(400).json({ success: false, error: 'phone required' });

      const normalizedPhone = phone.replace(/[^\d]/g, '');
      const result = await db.query(
        'SELECT phone, display_name, avatar_url, updated_at FROM messenger_profiles WHERE phone = $1',
        [normalizedPhone]
      );

      res.json({
        success: true,
        profile: result.rows.length > 0 ? result.rows[0] : null,
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * PUT /api/messenger/profile
   * Обновить профиль (display_name, avatar_url)
   * Body: { phone, displayName?, avatarUrl? }
   */
  app.put('/api/messenger/profile', requireAuth, async (req, res) => {
    try {
      const { displayName, avatarUrl } = req.body;

      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');

      const result = await db.query(`
        INSERT INTO messenger_profiles (phone, display_name, avatar_url, updated_at)
        VALUES ($1, $2, $3, NOW())
        ON CONFLICT (phone)
        DO UPDATE SET
          display_name = COALESCE($2, messenger_profiles.display_name),
          avatar_url = COALESCE($3, messenger_profiles.avatar_url),
          updated_at = NOW()
        RETURNING phone, display_name, avatar_url, updated_at
      `, [normalizedPhone, displayName || null, avatarUrl || null]);

      res.json({
        success: true,
        profile: result.rows[0],
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // CALL SIGNALING — REST helpers
  // ============================================

  /**
   * POST /api/messenger/call/notify
   * Send FCM push to callee when they are offline (no active WS connection).
   * Body: { callId, callerPhone, targetPhone, callerName, offerSdp }
   */
  app.post('/api/messenger/call/notify', requireAuth, async (req, res) => {
    try {
      const { callId, callerPhone, targetPhone, callerName, offerSdp } = req.body;
      if (!callId || !targetPhone || !offerSdp) {
        return res.status(400).json({ success: false, error: 'callId, targetPhone and offerSdp required' });
      }

      const normalizedTarget = targetPhone.replace(/[^\d]/g, '');
      const normalizedCaller = req.user.phone.replace(/[^\d]/g, '');

      // ALWAYS send FCM for calls — WS may be connected on server but app
      // could be minimized/suspended by Android and unable to process WS messages.
      // FCM with high priority wakes the app and triggers CallKit incoming screen.
      try {
        await pushService.sendPushToPhone(
          normalizedTarget,
          callerName || normalizedCaller,
          'Входящий голосовой звонок',
          {
            type: 'incoming_call',
            callId,
            callerPhone: normalizedCaller,
            callerName: callerName || normalizedCaller,
            offerSdp,
          },
          'call_channel'
        );
        console.log(`📞 Call FCM sent to ${normalizedTarget.replace(/(\d{4})\d+(\d{2})/, '$1***$2')}`);
      } catch (e) {
        console.error('[Messenger] Call FCM error:', e.message);
      }

      const isOnline = wsNotify ? wsNotify.isUserOnline(normalizedTarget) : false;
      res.json({ success: true, calleeOnline: isOnline, fcmSent: true });
    } catch (error) {
      console.error('[Messenger] Call notify error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/call/record
   * Save a call event (completed / missed / rejected) as a message in the conversation.
   * Body: { conversationId, callerPhone, calleePhone, durationSeconds, status }
   * status: 'completed' | 'missed' | 'rejected'
   */
  app.post('/api/messenger/call/record', requireAuth, async (req, res) => {
    try {
      const { conversationId, calleePhone, durationSeconds, status } = req.body;
      if (!conversationId || !calleePhone || !status) {
        return res.status(400).json({ success: false, error: 'conversationId, calleePhone and status required' });
      }

      const callerPhone = req.user.phone.replace(/[^\d]/g, '');
      const callerName  = req.user.name || callerPhone;
      const now = new Date().toISOString();
      const msgId = `call_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;

      const _dur = durationSeconds || 0;
      const _mins = Math.floor(_dur / 60);
      const _secs = _dur % 60;
      const _durStr = _mins > 0
        ? (_secs > 0 ? `${_mins} мин ${_secs} сек` : `${_mins} мин`)
        : `${_secs} сек`;
      const contentMap = {
        completed: `Звонок · ${_durStr}`,
        missed:    'Пропущенный звонок',
        rejected:  'Звонок отклонён',
      };
      const content = contentMap[status] || 'Звонок';

      await db.query(
        `INSERT INTO messenger_messages
           (id, conversation_id, sender_phone, sender_name, type, content, voice_duration, created_at)
         VALUES ($1, $2, $3, $4, 'call', $5, $6, $7)`,
        [msgId, conversationId, callerPhone, callerName, content, durationSeconds || 0, now]
      );

      // Notify participants via WebSocket
      if (wsNotify) {
        const msg = {
          id: msgId,
          conversationId,
          senderPhone: callerPhone,
          senderName: callerName,
          type: 'call',
          content,
          voiceDuration: durationSeconds || 0,
          createdAt: now,
          reactions: {},
          isDeleted: false,
          replyToId: null,
          mediaUrl: null,
        };
        await wsNotify.notifyNewMessage(conversationId, msg, callerPhone);
      }

      res.json({ success: true, messageId: msgId });
    } catch (error) {
      console.error('[Messenger] Call record error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * GET /api/messenger/saved
   * Получить или создать "Избранное" (чат с самим собой)
   */
  app.get('/api/messenger/saved', requireAuth, async (req, res) => {
    try {
      const phone = req.user.phone.replace(/[^\d]/g, '');

      const conversationId = `private_${phone}_${phone}`;

      // Проверяем существование
      let conversation = await db.findById('messenger_conversations', conversationId);
      if (conversation) {
        const parts = await db.query(
          'SELECT phone, name, role FROM messenger_participants WHERE conversation_id = $1',
          [conversationId]
        );
        return res.json({
          success: true,
          conversation: { ...conversation, participants: parts.rows }
        });
      }

      // Создаём
      await db.transaction(async (client) => {
        await client.query(
          `INSERT INTO messenger_conversations (id, type, name, created_at, updated_at)
           VALUES ($1, 'private', 'Избранное', NOW(), NOW())`,
          [conversationId]
        );
        await client.query(
          `INSERT INTO messenger_participants (conversation_id, phone, name, role, joined_at)
           VALUES ($1, $2, NULL, 'member', NOW())`,
          [conversationId, phone]
        );
      });

      conversation = await db.findById('messenger_conversations', conversationId);
      const parts = await db.query(
        'SELECT phone, name, role FROM messenger_participants WHERE conversation_id = $1',
        [conversationId]
      );

      res.json({
        success: true,
        conversation: { ...conversation, participants: parts.rows },
        created: true
      });
    } catch (error) {
      console.error('[Messenger] GET saved error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ==================== CHANNELS ====================

  /**
   * POST /api/messenger/conversations/channel
   * Создать канал (только руководители: developer/manager/supervisor)
   */
  app.post('/api/messenger/conversations/channel', requireAuth, async (req, res) => {
    try {
      const { name, description, avatar_url } = req.body;
      if (!name) return res.status(400).json({ success: false, error: 'name required' });

      const creatorPhone = req.user.phone.replace(/[^\d]/g, '');

      // Check role — only developers can create channels
      const { isDeveloper } = require('./shop_managers_api');
      let creatorName = req.user.name;
      if (!(await isDeveloper(creatorPhone))) {
        return res.status(403).json({ success: false, error: 'Only developers can create channels' });
      }

      const channelId = generateId('channel');

      await db.transaction(async (client) => {
        await client.query(
          `INSERT INTO messenger_conversations (id, type, name, description, avatar_url, creator_phone, creator_name, created_at, updated_at)
           VALUES ($1, 'channel', $2, $3, $4, $5, $6, NOW(), NOW())`,
          [channelId, name, description || null, avatar_url || null, creatorPhone, creatorName || null]
        );
        // Creator is admin
        await client.query(
          `INSERT INTO messenger_participants (conversation_id, phone, name, role, joined_at)
           VALUES ($1, $2, $3, 'admin', NOW())`,
          [channelId, creatorPhone, creatorName || null]
        );
      });

      const conversation = await db.findById('messenger_conversations', channelId);
      const parts = await db.query(
        'SELECT phone, name, role FROM messenger_participants WHERE conversation_id = $1',
        [channelId]
      );

      res.json({
        success: true,
        conversation: { ...conversation, participants: parts.rows }
      });
    } catch (error) {
      console.error('[Messenger] POST channel error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * GET /api/messenger/channels
   * Каталог доступных каналов
   */
  app.get('/api/messenger/channels', requireAuth, async (req, res) => {
    try {
      const result = await db.query(
        `SELECT c.*,
         (SELECT COUNT(*) FROM messenger_participants WHERE conversation_id = c.id) as subscriber_count
         FROM messenger_conversations c
         WHERE c.type = 'channel'
         ORDER BY c.created_at DESC`
      );

      res.json({ success: true, channels: result.rows });
    } catch (error) {
      console.error('[Messenger] GET channels error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/channels/:id/subscribe
   * Подписаться на канал
   */
  app.post('/api/messenger/channels/:id/subscribe', requireAuth, async (req, res) => {
    try {
      const channelId = req.params.id;
      const phone = req.user.phone.replace(/[^\d]/g, '');
      const name = req.user.name || null;

      // Verify it's a channel
      const conv = await db.findById('messenger_conversations', channelId);
      if (!conv || conv.type !== 'channel') {
        return res.status(404).json({ success: false, error: 'Channel not found' });
      }

      await db.query(
        `INSERT INTO messenger_participants (conversation_id, phone, name, role, joined_at)
         VALUES ($1, $2, $3, 'subscriber', NOW()) ON CONFLICT (conversation_id, phone) DO NOTHING`,
        [channelId, phone, name]
      );

      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] POST subscribe error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/channels/:id/unsubscribe
   * Отписаться от канала
   */
  app.post('/api/messenger/channels/:id/unsubscribe', requireAuth, async (req, res) => {
    try {
      const channelId = req.params.id;
      const phone = req.user.phone.replace(/[^\d]/g, '');

      // Don't allow admin to unsubscribe
      const participant = await db.query(
        'SELECT role FROM messenger_participants WHERE conversation_id = $1 AND phone = $2',
        [channelId, phone]
      );
      if (participant.rows[0]?.role === 'admin') {
        return res.status(400).json({ success: false, error: 'Admin cannot unsubscribe' });
      }

      await db.query(
        'DELETE FROM messenger_participants WHERE conversation_id = $1 AND phone = $2',
        [channelId, phone]
      );

      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] POST unsubscribe error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * PUT /api/messenger/channels/:id/role
   * Назначить роль участнику канала (admin → writer/member)
   * Body: { phone, role: 'writer' | 'member' }
   */
  app.put('/api/messenger/channels/:id/role', requireAuth, async (req, res) => {
    try {
      const channelId = req.params.id;
      const requesterPhone = req.user.phone.replace(/[^\d]/g, '');
      const { phone, role } = req.body;

      if (!phone || !role || !['writer', 'member'].includes(role)) {
        return res.status(400).json({ success: false, error: 'phone and role (writer|member) required' });
      }

      // Only channel admin can change roles
      const adminCheck = await db.query(
        'SELECT role FROM messenger_participants WHERE conversation_id = $1 AND phone = $2',
        [channelId, requesterPhone]
      );
      if (adminCheck.rows[0]?.role !== 'admin') {
        return res.status(403).json({ success: false, error: 'Only channel admin can change roles' });
      }

      const targetPhone = phone.replace(/[^\d]/g, '');

      // Cannot change own role
      if (targetPhone === requesterPhone) {
        return res.status(400).json({ success: false, error: 'Cannot change own role' });
      }

      await db.query(
        'UPDATE messenger_participants SET role = $1 WHERE conversation_id = $2 AND phone = $3',
        [role, channelId, targetPhone]
      );

      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] PUT channel role error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ==================== STICKERS ====================

  /**
   * GET /api/messenger/sticker-packs
   * Список пакетов стикеров
   */
  app.get('/api/messenger/sticker-packs', requireAuth, async (req, res) => {
    try {
      const result = await db.query(
        'SELECT * FROM messenger_sticker_packs ORDER BY is_default DESC, created_at ASC'
      );
      res.json({ success: true, packs: result.rows });
    } catch (error) {
      console.error('[Messenger] GET sticker-packs error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * GET /api/messenger/sticker-packs/:id
   * Стикеры из конкретного пакета
   */
  app.get('/api/messenger/sticker-packs/:id', requireAuth, async (req, res) => {
    try {
      const pack = await db.findById('messenger_sticker_packs', req.params.id);
      if (!pack) return res.status(404).json({ success: false, error: 'Pack not found' });
      res.json({ success: true, pack });
    } catch (error) {
      console.error('[Messenger] GET sticker-pack error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ==================== FAVORITE STICKERS ====================

  /**
   * GET /api/messenger/favorite-stickers
   * Get user's favorite stickers
   */
  app.get('/api/messenger/favorite-stickers', requireAuth, async (req, res) => {
    try {
      const phone = req.user.phone.replace(/[^\d]/g, '');
      const result = await db.query(
        "SELECT sticker_url, created_at FROM favorite_stickers WHERE phone = $1 AND (type = 'sticker' OR type IS NULL) ORDER BY created_at DESC",
        [phone]
      );
      res.json({ success: true, stickers: result.rows.map(r => r.sticker_url) });
    } catch (error) {
      console.error('[Messenger] GET favorite-stickers error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/favorite-stickers
   * Add sticker to favorites
   * Body: { stickerUrl }
   */
  app.post('/api/messenger/favorite-stickers', requireAuth, async (req, res) => {
    try {
      const phone = req.user.phone.replace(/[^\d]/g, '');
      const { stickerUrl } = req.body;
      if (!stickerUrl) {
        return res.status(400).json({ success: false, error: 'stickerUrl is required' });
      }

      // Limit to 200 favorites per user (stickers only)
      const countResult = await db.query(
        "SELECT COUNT(*) as cnt FROM favorite_stickers WHERE phone = $1 AND (type = 'sticker' OR type IS NULL)",
        [phone]
      );
      if (parseInt(countResult.rows[0].cnt) >= 200) {
        return res.status(400).json({ success: false, error: 'Достигнут лимит избранных стикеров (200)' });
      }

      await db.query(
        "INSERT INTO favorite_stickers (phone, sticker_url, type) VALUES ($1, $2, 'sticker') ON CONFLICT (phone, sticker_url) DO NOTHING",
        [phone, stickerUrl]
      );
      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] POST favorite-stickers error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/messenger/favorite-stickers?url=...
   * Remove sticker from favorites
   */
  app.delete('/api/messenger/favorite-stickers', requireAuth, async (req, res) => {
    try {
      const phone = req.user.phone.replace(/[^\d]/g, '');
      const stickerUrl = req.query.url;
      if (!stickerUrl) {
        return res.status(400).json({ success: false, error: 'url query param is required' });
      }

      await db.query(
        'DELETE FROM favorite_stickers WHERE phone = $1 AND sticker_url = $2',
        [phone, stickerUrl]
      );
      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] DELETE favorite-stickers error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ==================== CUSTOM STICKER UPLOAD ====================

  // Multer storage for custom stickers — separate directory from messenger-media
  const customStickerStorage = multer.diskStorage({
    destination: async (req, file, cb) => {
      const phone = req.user.phone.replace(/[^\d]/g, '');
      const dir = path.join(DATA_DIR, 'custom-stickers', phone);
      await fsp.mkdir(dir, { recursive: true });
      cb(null, dir);
    },
    filename: (req, file, cb) => {
      const ext = path.extname(file.originalname || '.png').toLowerCase();
      const safeExt = ['.png', '.jpg', '.jpeg', '.webp', '.gif'].includes(ext) ? ext : '.png';
      cb(null, `stk_${Date.now()}_${Math.random().toString(36).substr(2, 6)}${safeExt}`);
    },
  });
  const uploadCustomSticker = multer({
    storage: customStickerStorage,
    limits: { fileSize: 5 * 1024 * 1024 }, // 5MB max
    fileFilter: (req, file, cb) => {
      if (file.mimetype && file.mimetype.startsWith('image/')) cb(null, true);
      else cb(new Error('Only images allowed'), false);
    },
  });

  /**
   * POST /api/messenger/custom-stickers/upload
   * Upload custom sticker from gallery. Resizes to 512px, saves as PNG, adds to favorites.
   */
  app.post('/api/messenger/custom-stickers/upload', requireAuth, (req, res, next) => {
    const phone = req.user.phone.replace(/[^\d]/g, '');
    if (!checkUploadRateLimit(phone)) {
      return res.status(429).json({ success: false, error: 'Слишком много загрузок. Попробуйте через минуту.' });
    }
    next();
  }, uploadCustomSticker.single('file'), async (req, res) => {
    try {
      if (!req.file) return res.status(400).json({ success: false, error: 'No file uploaded' });

      const phone = req.user.phone.replace(/[^\d]/g, '');

      // Check limit: max 100 custom stickers per user
      const countResult = await db.query(
        "SELECT COUNT(*) as cnt FROM favorite_stickers WHERE phone = $1 AND sticker_url LIKE '%/custom-stickers/%'",
        [phone]
      );
      if (parseInt(countResult.rows[0].cnt) >= 100) {
        await fsp.unlink(req.file.path).catch(() => {});
        return res.status(400).json({ success: false, error: 'Лимит: 100 пользовательских стикеров' });
      }

      // Detect if it's a GIF (skip PNG conversion)
      const ext = path.extname(req.file.originalname || req.file.filename || '').toLowerCase();
      const isGif = ext === '.gif' || req.file.mimetype === 'image/gif';
      const favType = isGif ? 'gif' : 'sticker';

      if (isGif) {
        // GIF — keep as-is, no conversion
        const stickerUrl = `/custom-stickers/${phone}/${req.file.filename}`;
        await db.query(
          "INSERT INTO favorite_stickers (phone, sticker_url, type) VALUES ($1, $2, 'gif') ON CONFLICT (phone, sticker_url) DO NOTHING",
          [phone, stickerUrl]
        );
        console.log(`[Messenger] Custom GIF uploaded: ${phone}/${req.file.filename}`);
        res.json({ success: true, stickerUrl });
      } else {
        // Sticker — resize to 512px max and convert to PNG
        let sharp;
        try { sharp = require('sharp'); } catch (_) {}

        if (sharp) {
          const tmpPath = req.file.path + '.tmp.png';
          await sharp(req.file.path)
            .resize(512, 512, { fit: 'inside', withoutEnlargement: true })
            .png({ quality: 90 })
            .toFile(tmpPath);

          await fsp.unlink(req.file.path).catch(() => {});
          const finalPath = req.file.path.replace(path.extname(req.file.path), '.png');
          await fsp.rename(tmpPath, finalPath);

          const finalFilename = path.basename(finalPath);
          const stickerUrl = `/custom-stickers/${phone}/${finalFilename}`;

          await db.query(
            "INSERT INTO favorite_stickers (phone, sticker_url, type) VALUES ($1, $2, 'sticker') ON CONFLICT (phone, sticker_url) DO NOTHING",
            [phone, stickerUrl]
          );

          console.log(`[Messenger] Custom sticker uploaded: ${phone}/${finalFilename}`);
          res.json({ success: true, stickerUrl });
        } else {
          const stickerUrl = `/custom-stickers/${phone}/${req.file.filename}`;
          await db.query(
            "INSERT INTO favorite_stickers (phone, sticker_url, type) VALUES ($1, $2, 'sticker') ON CONFLICT (phone, sticker_url) DO NOTHING",
            [phone, stickerUrl]
          );
          res.json({ success: true, stickerUrl });
        }
      }
    } catch (error) {
      console.error('[Messenger] Custom sticker upload error:', error.message);
      if (req.file) await fsp.unlink(req.file.path).catch(() => {});
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ==================== GIF (Tenor API proxy) ====================

  // In-memory cache for GIF results
  const gifCache = new Map();
  const GIF_CACHE_TTL = 10 * 60 * 1000; // 10 min for search
  const GIF_TRENDING_TTL = 60 * 60 * 1000; // 1 hour for trending

  // Cleanup stale GIF cache entries every 30 minutes
  setInterval(() => {
    const now = Date.now();
    for (const [key, value] of gifCache) {
      const ttl = key.startsWith('trending_') ? GIF_TRENDING_TTL : GIF_CACHE_TTL;
      if (now - value.ts > ttl) gifCache.delete(key);
    }
  }, 30 * 60 * 1000);

  // Helper: parse GIPHY response into unified format
  function parseGiphyResults(data) {
    return (data.data || []).map(r => ({
      id: r.id,
      title: r.title || '',
      url: r.images?.original?.url || r.images?.downsized?.url || '',
      preview: r.images?.fixed_width_small?.url || r.images?.preview_gif?.url || '',
      width: parseInt(r.images?.original?.width) || 200,
      height: parseInt(r.images?.original?.height) || 200,
    })).filter(g => g.url);
  }

  /**
   * GET /api/messenger/gifs/search?query=X&limit=20
   * Search GIFs via GIPHY API
   */
  app.get('/api/messenger/gifs/search', requireAuth, async (req, res) => {
    try {
      const { query, limit = '20' } = req.query;
      if (!query) return res.status(400).json({ success: false, error: 'query required' });

      const giphyKey = process.env.GIPHY_API_KEY;
      if (!giphyKey) return res.json({ success: true, gifs: [] });

      const cacheKey = `search_${query}_${limit}`;
      const cached = gifCache.get(cacheKey);
      if (cached && Date.now() - cached.ts < GIF_CACHE_TTL) {
        return res.json({ success: true, gifs: cached.data });
      }

      const url = `https://api.giphy.com/v1/gifs/search?api_key=${giphyKey}&q=${encodeURIComponent(query)}&limit=${limit}&rating=pg-13&lang=ru`;
      const response = await fetch(url);
      const data = await response.json();

      const gifs = parseGiphyResults(data);
      gifCache.set(cacheKey, { data: gifs, ts: Date.now() });
      res.json({ success: true, gifs });
    } catch (error) {
      console.error('[Messenger] GIF search error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * GET /api/messenger/gifs/trending?limit=20
   * Trending GIFs via GIPHY API
   */
  app.get('/api/messenger/gifs/trending', requireAuth, async (req, res) => {
    try {
      const { limit = '20' } = req.query;
      const giphyKey = process.env.GIPHY_API_KEY;
      if (!giphyKey) return res.json({ success: true, gifs: [] });

      const cacheKey = `trending_${limit}`;
      const cached = gifCache.get(cacheKey);
      if (cached && Date.now() - cached.ts < GIF_TRENDING_TTL) {
        return res.json({ success: true, gifs: cached.data });
      }

      const url = `https://api.giphy.com/v1/gifs/trending?api_key=${giphyKey}&limit=${limit}&rating=pg-13`;
      const response = await fetch(url);
      const data = await response.json();

      const gifs = parseGiphyResults(data);
      gifCache.set(cacheKey, { data: gifs, ts: Date.now() });
      res.json({ success: true, gifs });
    } catch (error) {
      console.error('[Messenger] GIF trending error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ==================== FAVORITE GIFS ====================

  /**
   * GET /api/messenger/favorite-gifs
   * Get user's favorite GIFs
   */
  app.get('/api/messenger/favorite-gifs', requireAuth, async (req, res) => {
    try {
      const phone = req.user.phone.replace(/[^\d]/g, '');
      const result = await db.query(
        "SELECT sticker_url, created_at FROM favorite_stickers WHERE phone = $1 AND type = 'gif' ORDER BY created_at DESC",
        [phone]
      );
      res.json({ success: true, gifs: result.rows.map(r => r.sticker_url) });
    } catch (error) {
      console.error('[Messenger] GET favorite-gifs error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/favorite-gifs
   * Add a GIF to favorites
   */
  app.post('/api/messenger/favorite-gifs', requireAuth, async (req, res) => {
    try {
      const phone = req.user.phone.replace(/[^\d]/g, '');
      const { gifUrl } = req.body;
      if (!gifUrl) {
        return res.status(400).json({ success: false, error: 'gifUrl is required' });
      }

      // Limit to 200 favorite GIFs per user
      const countResult = await db.query(
        "SELECT COUNT(*) as cnt FROM favorite_stickers WHERE phone = $1 AND type = 'gif'",
        [phone]
      );
      if (parseInt(countResult.rows[0].cnt) >= 200) {
        return res.status(400).json({ success: false, error: 'Достигнут лимит избранных GIF (200)' });
      }

      await db.query(
        "INSERT INTO favorite_stickers (phone, sticker_url, type) VALUES ($1, $2, 'gif') ON CONFLICT (phone, sticker_url) DO NOTHING",
        [phone, gifUrl]
      );
      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] POST favorite-gifs error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/messenger/favorite-gifs
   * Remove a GIF from favorites
   */
  app.delete('/api/messenger/favorite-gifs', requireAuth, async (req, res) => {
    try {
      const phone = req.user.phone.replace(/[^\d]/g, '');
      const gifUrl = req.query.url;
      if (!gifUrl) {
        return res.status(400).json({ success: false, error: 'url query param is required' });
      }

      await db.query(
        "DELETE FROM favorite_stickers WHERE phone = $1 AND sticker_url = $2 AND type = 'gif'",
        [phone, gifUrl]
      );
      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] DELETE favorite-gifs error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ==================== GLOBAL SEARCH ====================

  /**
   * GET /api/messenger/search?query=X&limit=20
   * Global fuzzy search across contacts, groups, and messages.
   * Uses pg_trgm for typo-tolerant matching.
   */
  app.get('/api/messenger/search', requireAuth, async (req, res) => {
    try {
      const phone = req.user.phone.replace(/[^\d]/g, '');
      const { query: searchQuery, limit = 20 } = req.query;

      if (!searchQuery || searchQuery.trim().length < 2) {
        return res.json({ success: true, contacts: [], groups: [], messages: [] });
      }

      const q = searchQuery.trim();
      const parsedLimit = Math.min(parseInt(limit) || 20, 50);

      // Find user's conversation IDs (for scoping search to own chats)
      const myConvs = await db.query(
        'SELECT conversation_id FROM messenger_participants WHERE phone = $1',
        [phone]
      );
      const myConvIds = myConvs.rows.map(r => r.conversation_id);

      if (myConvIds.length === 0) {
        return res.json({ success: true, contacts: [], groups: [], messages: [] });
      }

      // Three parallel searches
      const [contactsResult, groupsResult, messagesResult] = await Promise.all([
        // 1. Contacts: people from my conversations whose name matches
        db.query(
          `SELECT DISTINCT ON (p.phone) p.phone, p.name, c.id AS conversation_id, c.type
           FROM messenger_participants p
           JOIN messenger_conversations c ON c.id = p.conversation_id
           WHERE p.conversation_id = ANY($1)
             AND p.phone != $2
             AND p.name IS NOT NULL AND p.name != ''
             AND (p.name ILIKE '%' || $3 || '%' OR p.phone ILIKE '%' || $3 || '%' OR similarity(p.name, $3) > 0.2)
           ORDER BY p.phone, similarity(p.name, $3) DESC
           LIMIT $4`,
          [myConvIds, phone, q, parsedLimit]
        ),

        // 2. Groups: group conversations whose name matches
        db.query(
          `SELECT c.id, c.name, c.avatar_url, c.type
           FROM messenger_conversations c
           JOIN messenger_participants p ON p.conversation_id = c.id AND p.phone = $1
           WHERE c.type = 'group'
             AND c.name IS NOT NULL AND c.name != ''
             AND (c.name ILIKE '%' || $2 || '%' OR similarity(c.name, $2) > 0.2)
           ORDER BY similarity(c.name, $2) DESC
           LIMIT $3`,
          [phone, q, parsedLimit]
        ),

        // 3. Messages: search message content in my conversations
        db.query(
          `SELECT m.id, m.conversation_id, m.sender_phone, m.sender_name, m.content, m.type, m.created_at,
                  c.name AS conversation_name, c.type AS conversation_type
           FROM messenger_messages m
           JOIN messenger_conversations c ON c.id = m.conversation_id
           WHERE m.conversation_id = ANY($1)
             AND m.is_deleted = false
             AND m.content IS NOT NULL AND m.content != ''
             AND (m.content ILIKE '%' || $2 || '%' OR similarity(m.content, $2) > 0.15)
           ORDER BY similarity(m.content, $2) DESC, m.created_at DESC
           LIMIT $3`,
          [myConvIds, q, parsedLimit]
        ),
      ]);

      res.json({
        success: true,
        contacts: contactsResult.rows,
        groups: groupsResult.rows,
        messages: messagesResult.rows,
      });
    } catch (error) {
      console.error('[Messenger] Global search error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ==================== POLLS ====================

  /**
   * POST /api/messenger/conversations/:id/poll
   * Создать опрос
   */
  app.post('/api/messenger/conversations/:id/poll', requireAuth, async (req, res) => {
    try {
      const { question, options, multipleChoice, anonymous } = req.body;
      if (!question || !options || !Array.isArray(options) || options.length < 2) {
        return res.status(400).json({ success: false, error: 'question and at least 2 options required' });
      }

      const conversationId = req.params.id;
      const senderPhone = req.user.phone.replace(/[^\d]/g, '');
      const senderName = req.user.name || null;

      const msgId = generateId('msg');
      const pollId = generateId('poll');

      await db.transaction(async (client) => {
        // Create message of type 'poll'
        await client.query(
          `INSERT INTO messenger_messages (id, conversation_id, sender_phone, sender_name, type, content, created_at)
           VALUES ($1, $2, $3, $4, 'poll', $5, NOW())`,
          [msgId, conversationId, senderPhone, senderName, question]
        );
        // Create poll record
        await client.query(
          `INSERT INTO messenger_polls (id, conversation_id, message_id, question, options, votes, multiple_choice, anonymous, created_at)
           VALUES ($1, $2, $3, $4, $5::jsonb, '{}'::jsonb, $6, $7, NOW())`,
          [pollId, conversationId, msgId, question, JSON.stringify(options), multipleChoice || false, anonymous || false]
        );
        // Update conversation timestamp
        await client.query(
          'UPDATE messenger_conversations SET updated_at = NOW() WHERE id = $1',
          [conversationId]
        );
      });

      const message = await db.findById('messenger_messages', msgId);
      const poll = await db.findById('messenger_polls', pollId);

      // WS notification
      if (wsNotify) {
        await wsNotify.notifyNewMessage(conversationId, { ...message, poll }, senderPhone);
      }

      res.json({ success: true, message, poll });
    } catch (error) {
      console.error('[Messenger] POST poll error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/conversations/:id/poll/:pollId/vote
   * Проголосовать
   */
  app.post('/api/messenger/conversations/:id/poll/:pollId/vote', requireAuth, async (req, res) => {
    try {
      const { optionIndex } = req.body;
      if (optionIndex === undefined || optionIndex === null) {
        return res.status(400).json({ success: false, error: 'optionIndex required' });
      }

      const pollId = req.params.pollId;
      const phone = req.user.phone.replace(/[^\d]/g, '');

      const poll = await db.findById('messenger_polls', pollId);
      if (!poll) return res.status(404).json({ success: false, error: 'Poll not found' });
      if (poll.closed) return res.status(400).json({ success: false, error: 'Poll is closed' });

      const idx = String(optionIndex);
      const votes = poll.votes || {};

      // Check if already voted for this option
      if (votes[idx] && votes[idx].includes(phone)) {
        return res.json({ success: true, votes }); // already voted
      }

      // If not multiple choice — remove previous vote
      if (!poll.multiple_choice) {
        for (const key of Object.keys(votes)) {
          if (votes[key]) {
            votes[key] = votes[key].filter(p => p !== phone);
          }
        }
      }

      // Add vote
      if (!votes[idx]) votes[idx] = [];
      votes[idx].push(phone);

      await db.query(
        'UPDATE messenger_polls SET votes = $1::jsonb WHERE id = $2',
        [JSON.stringify(votes), pollId]
      );

      // Broadcast poll update
      const conversationId = req.params.id;
      if (wsNotify) {
        const sockets = wsNotify.broadcastToConversation || null;
        // Use a simpler approach — send poll_voted event
        try {
          const members = await db.query(
            'SELECT phone FROM messenger_participants WHERE conversation_id = $1',
            [conversationId]
          );
          for (const member of members.rows) {
            wsNotify.sendToPhone(member.phone, {
              type: 'poll_voted',
              conversationId,
              pollId,
              messageId: poll.message_id,
              votes,
              timestamp: new Date().toISOString()
            });
          }
        } catch (_) { /* ws notification not critical */ }
      }

      res.json({ success: true, votes });
    } catch (error) {
      console.error('[Messenger] POST poll vote error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/messenger/conversations/:id/poll/:pollId/vote
   * Отменить голос
   */
  app.delete('/api/messenger/conversations/:id/poll/:pollId/vote', requireAuth, async (req, res) => {
    try {
      const pollId = req.params.pollId;
      const phone = req.user.phone.replace(/[^\d]/g, '');

      const poll = await db.findById('messenger_polls', pollId);
      if (!poll) return res.status(404).json({ success: false, error: 'Poll not found' });
      if (poll.closed) return res.status(400).json({ success: false, error: 'Poll is closed' });

      const votes = poll.votes || {};
      for (const key of Object.keys(votes)) {
        if (votes[key]) {
          votes[key] = votes[key].filter(p => p !== phone);
        }
      }

      await db.query(
        'UPDATE messenger_polls SET votes = $1::jsonb WHERE id = $2',
        [JSON.stringify(votes), pollId]
      );

      res.json({ success: true, votes });
    } catch (error) {
      console.error('[Messenger] DELETE poll vote error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/conversations/:id/poll/:pollId/close
   * Закрыть опрос (только автор)
   */
  app.post('/api/messenger/conversations/:id/poll/:pollId/close', requireAuth, async (req, res) => {
    try {
      const pollId = req.params.pollId;
      const phone = req.user.phone.replace(/[^\d]/g, '');

      const poll = await db.findById('messenger_polls', pollId);
      if (!poll) return res.status(404).json({ success: false, error: 'Poll not found' });

      // Only the author of the message can close
      const msg = await db.findById('messenger_messages', poll.message_id);
      if (!msg || msg.sender_phone !== phone) {
        return res.status(403).json({ success: false, error: 'Only author can close poll' });
      }

      await db.query('UPDATE messenger_polls SET closed = true WHERE id = $1', [pollId]);

      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] POST poll close error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * GET /api/messenger/conversations/:id/poll/:msgId
   * Получить опрос по ID сообщения
   */
  app.get('/api/messenger/conversations/:id/poll/:msgId', requireAuth, async (req, res) => {
    try {
      const result = await db.query(
        'SELECT * FROM messenger_polls WHERE message_id = $1 LIMIT 1',
        [req.params.msgId]
      );
      if (result.rows.length === 0) {
        return res.status(404).json({ success: false, error: 'Poll not found' });
      }
      res.json({ success: true, poll: result.rows[0] });
    } catch (error) {
      console.error('[Messenger] GET poll error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ==================== BLOCK / UNBLOCK ====================

  /**
   * POST /api/messenger/block
   * Заблокировать пользователя
   */
  app.post('/api/messenger/block', requireAuth, async (req, res) => {
    try {
      const blockerPhone = req.user.phone.replace(/[^\d]/g, '');
      const blockedPhone = (req.body.blockedPhone || '').replace(/[^\d]/g, '');
      if (!blockedPhone) return res.status(400).json({ success: false, error: 'blockedPhone required' });
      if (blockerPhone === blockedPhone) return res.status(400).json({ success: false, error: 'Cannot block yourself' });

      await db.query(
        `INSERT INTO messenger_blocks (blocker_phone, blocked_phone, created_at)
         VALUES ($1, $2, NOW()) ON CONFLICT DO NOTHING`,
        [blockerPhone, blockedPhone]
      );

      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] POST block error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/messenger/block
   * Разблокировать пользователя
   */
  app.delete('/api/messenger/block', requireAuth, async (req, res) => {
    try {
      const blockerPhone = req.user.phone.replace(/[^\d]/g, '');
      const blockedPhone = (req.query.blockedPhone || '').replace(/[^\d]/g, '');
      if (!blockedPhone) return res.status(400).json({ success: false, error: 'blockedPhone required' });

      await db.query(
        'DELETE FROM messenger_blocks WHERE blocker_phone = $1 AND blocked_phone = $2',
        [blockerPhone, blockedPhone]
      );

      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] DELETE block error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * GET /api/messenger/blocks
   * Список заблокированных
   */
  app.get('/api/messenger/blocks', requireAuth, async (req, res) => {
    try {
      const phone = req.user.phone.replace(/[^\d]/g, '');

      const result = await db.query(
        'SELECT blocked_phone, created_at FROM messenger_blocks WHERE blocker_phone = $1 ORDER BY created_at DESC',
        [phone]
      );

      res.json({ success: true, blocks: result.rows });
    } catch (error) {
      console.error('[Messenger] GET blocks error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ==================== FOLDERS ====================

  /**
   * GET /api/messenger/folders?phone=X
   * Get all folders for a user
   */
  app.get('/api/messenger/folders', requireAuth, async (req, res) => {
    try {
      const phone = req.user.phone.replace(/[^\d]/g, '');

      const result = await db.query(
        'SELECT * FROM messenger_folders WHERE phone = $1 ORDER BY sort_order, created_at',
        [phone]
      );
      res.json({ success: true, folders: result.rows });
    } catch (error) {
      console.error('[Messenger] GET folders error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/folders
   * Create a folder
   */
  app.post('/api/messenger/folders', requireAuth, async (req, res) => {
    try {
      const { name, filterType = 'manual', sortOrder = 0 } = req.body;
      const cleanPhone = req.user.phone.replace(/[^\d]/g, '');
      if (!name) return res.status(400).json({ success: false, error: 'name required' });

      const id = `folder_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
      await db.query(
        `INSERT INTO messenger_folders (id, phone, name, sort_order, filter_type, conversation_ids, created_at)
         VALUES ($1, $2, $3, $4, $5, '[]', NOW())`,
        [id, cleanPhone, name, sortOrder, filterType]
      );
      const folder = await db.findById('messenger_folders', id);
      res.json({ success: true, folder });
    } catch (error) {
      console.error('[Messenger] POST folder error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * PUT /api/messenger/folders/:id
   * Update folder name or sort_order
   */
  app.put('/api/messenger/folders/:id', requireAuth, async (req, res) => {
    try {
      const { name, sortOrder } = req.body;
      const sets = [];
      const vals = [];
      let idx = 1;
      if (name !== undefined) { sets.push(`name = $${idx++}`); vals.push(name); }
      if (sortOrder !== undefined) { sets.push(`sort_order = $${idx++}`); vals.push(sortOrder); }
      if (sets.length === 0) return res.status(400).json({ success: false, error: 'nothing to update' });

      vals.push(req.params.id);
      await db.query(`UPDATE messenger_folders SET ${sets.join(', ')} WHERE id = $${idx}`, vals);
      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] PUT folder error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/messenger/folders/:id
   * Delete a folder
   */
  app.delete('/api/messenger/folders/:id', requireAuth, async (req, res) => {
    try {
      await db.query('DELETE FROM messenger_folders WHERE id = $1', [req.params.id]);
      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] DELETE folder error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/messenger/folders/:id/conversations
   * Add conversation to folder
   */
  app.post('/api/messenger/folders/:id/conversations', requireAuth, async (req, res) => {
    try {
      const { conversationId } = req.body;
      if (!conversationId) return res.status(400).json({ success: false, error: 'conversationId required' });

      await db.query(
        `UPDATE messenger_folders
         SET conversation_ids = conversation_ids || $1::jsonb
         WHERE id = $2
           AND NOT conversation_ids @> $1::jsonb`,
        [JSON.stringify([conversationId]), req.params.id]
      );
      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] POST folder conversation error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/messenger/folders/:id/conversations/:convId
   * Remove conversation from folder
   */
  app.delete('/api/messenger/folders/:id/conversations/:convId', requireAuth, async (req, res) => {
    try {
      await db.query(
        `UPDATE messenger_folders
         SET conversation_ids = conversation_ids - $1
         WHERE id = $2`,
        [req.params.convId, req.params.id]
      );
      // Note: JSONB - operator removes a string element from an array
      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] DELETE folder conversation error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // MEDIA STATS (developer only)
  // ============================================

  /**
   * GET /api/messenger/media-stats
   * Статистика медиафайлов мессенджера (только для разработчиков)
   */
  app.get('/api/messenger/media-stats', requireAuth, async (req, res) => {
    try {
      const { isDeveloper } = require('./shop_managers_api');
      const isDev = await isDeveloper(req.user.phone);
      if (!isDev) return res.status(403).json({ success: false, error: 'Developer only' });

      let getMediaStats;
      try {
        getMediaStats = require('./messenger_media_cleanup_scheduler').getMediaStats;
      } catch (_) {
        return res.json({ success: true, stats: { error: 'Cleanup scheduler not loaded' } });
      }

      const stats = await getMediaStats();
      res.json({ success: true, stats });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // CONVERSATION MEDIA (shared photos/videos/files)
  // ============================================

  /**
   * GET /api/messenger/conversations/:id/media
   * Returns media messages from a conversation (images, videos, files)
   */
  app.get('/api/messenger/conversations/:id/media', requireAuth, async (req, res) => {
    try {
      const conversationId = req.params.id;
      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');
      const limit = Math.min(parseInt(req.query.limit) || 50, 200);
      const offset = parseInt(req.query.offset) || 0;

      // Verify participant
      const participant = await db.query(
        'SELECT 1 FROM messenger_participants WHERE conversation_id = $1 AND phone = $2',
        [conversationId, normalizedPhone]
      );
      if (participant.rows.length === 0) {
        return res.status(403).json({ success: false, error: 'Not a participant' });
      }

      const result = await db.query(
        `SELECT id, type, media_url, file_name, file_size, sender_phone, sender_name, created_at
         FROM messenger_messages
         WHERE conversation_id = $1 AND type IN ('image', 'video', 'video_note', 'file') AND is_deleted = false
           AND id NOT IN (SELECT message_id FROM messenger_hidden_messages WHERE phone = $4)
         ORDER BY created_at DESC
         LIMIT $2 OFFSET $3`,
        [conversationId, limit, offset, normalizedPhone]
      );

      res.json({ success: true, media: result.rows });
    } catch (error) {
      console.error('[Messenger] GET media error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // HIDE MESSAGES (hide for me — used in media gallery)
  // ============================================

  /**
   * POST /api/messenger/messages/hide
   * Hides messages from the current user's media gallery (does NOT delete for others)
   */
  app.post('/api/messenger/messages/hide', requireAuth, async (req, res) => {
    try {
      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');
      const { messageIds } = req.body;
      if (!Array.isArray(messageIds) || messageIds.length === 0) {
        return res.status(400).json({ success: false, error: 'messageIds array required' });
      }

      // Limit batch size
      const ids = messageIds.slice(0, 100);

      const values = ids.map((id, i) => `($1, $${i + 2})`).join(', ');
      await db.query(
        `INSERT INTO messenger_hidden_messages (phone, message_id) VALUES ${values} ON CONFLICT DO NOTHING`,
        [normalizedPhone, ...ids]
      );

      res.json({ success: true, hidden: ids.length });
    } catch (error) {
      console.error('[Messenger] POST hide messages error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // COMMON GROUPS (groups shared between two users)
  // ============================================

  /**
   * GET /api/messenger/common-groups?phone=TARGET_PHONE
   * Returns groups where both current user and target phone are participants
   */
  app.get('/api/messenger/common-groups', requireAuth, async (req, res) => {
    try {
      const myPhone = req.user.phone.replace(/[^\d]/g, '');
      const targetPhone = (req.query.phone || '').replace(/[^\d]/g, '');
      if (!targetPhone) {
        return res.status(400).json({ success: false, error: 'phone parameter required' });
      }

      const result = await db.query(
        `SELECT c.id, c.name, c.avatar_url,
                (SELECT COUNT(*) FROM messenger_participants WHERE conversation_id = c.id)::int AS participants_count
         FROM messenger_conversations c
         WHERE c.type = 'group'
           AND EXISTS (SELECT 1 FROM messenger_participants WHERE conversation_id = c.id AND phone = $1)
           AND EXISTS (SELECT 1 FROM messenger_participants WHERE conversation_id = c.id AND phone = $2)
         ORDER BY c.updated_at DESC`,
        [myPhone, targetPhone]
      );

      res.json({ success: true, groups: result.rows });
    } catch (error) {
      console.error('[Messenger] GET common-groups error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // MUTE / UNMUTE CONVERSATION
  // ============================================

  /**
   * POST /api/messenger/conversations/:id/mute
   * body: { duration: "1h" | "8h" | "2d" | "forever" }
   */
  app.post('/api/messenger/conversations/:id/mute', requireAuth, async (req, res) => {
    try {
      const conversationId = req.params.id;
      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');
      const { duration } = req.body;

      let mutedUntil;
      const now = new Date();
      switch (duration) {
        case '1h': mutedUntil = new Date(now.getTime() + 60 * 60 * 1000); break;
        case '8h': mutedUntil = new Date(now.getTime() + 8 * 60 * 60 * 1000); break;
        case '2d': mutedUntil = new Date(now.getTime() + 2 * 24 * 60 * 60 * 1000); break;
        case 'forever': mutedUntil = new Date('2099-12-31T23:59:59Z'); break;
        default: return res.status(400).json({ success: false, error: 'Invalid duration' });
      }

      await db.query(
        'UPDATE messenger_participants SET muted_until = $1 WHERE conversation_id = $2 AND phone = $3',
        [mutedUntil.toISOString(), conversationId, normalizedPhone]
      );

      res.json({ success: true, muted_until: mutedUntil.toISOString() });
    } catch (error) {
      console.error('[Messenger] POST mute error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/messenger/conversations/:id/mute
   */
  app.delete('/api/messenger/conversations/:id/mute', requireAuth, async (req, res) => {
    try {
      const conversationId = req.params.id;
      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');

      await db.query(
        'UPDATE messenger_participants SET muted_until = NULL WHERE conversation_id = $1 AND phone = $2',
        [conversationId, normalizedPhone]
      );

      res.json({ success: true });
    } catch (error) {
      console.error('[Messenger] DELETE mute error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * GET /api/messenger/conversations/:id/mute
   */
  app.get('/api/messenger/conversations/:id/mute', requireAuth, async (req, res) => {
    try {
      const conversationId = req.params.id;
      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');

      const result = await db.query(
        'SELECT muted_until FROM messenger_participants WHERE conversation_id = $1 AND phone = $2',
        [conversationId, normalizedPhone]
      );

      const mutedUntil = result.rows[0]?.muted_until;
      const isMuted = mutedUntil && new Date(mutedUntil) > new Date();

      res.json({ success: true, is_muted: !!isMuted, muted_until: mutedUntil || null });
    } catch (error) {
      console.error('[Messenger] GET mute error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // DISAPPEARING MESSAGES (auto-delete timer per conversation)
  // ============================================

  /**
   * PUT /api/messenger/conversations/:id/auto-delete
   * Set auto-delete timer for the conversation
   * body: { seconds: 0 | 86400 | 604800 | 2592000 }
   */
  app.put('/api/messenger/conversations/:id/auto-delete', requireAuth, async (req, res) => {
    try {
      const normalizedPhone = req.user.phone.replace(/[^\d]/g, '');
      const conversationId = req.params.id;
      const { seconds = 0 } = req.body;

      // Validate
      const allowed = [0, 86400, 604800, 2592000];
      if (!allowed.includes(seconds)) {
        return res.status(400).json({ success: false, error: 'Invalid timer value' });
      }

      // Verify participant
      const participant = await db.query(
        'SELECT 1 FROM messenger_participants WHERE conversation_id = $1 AND phone = $2',
        [conversationId, normalizedPhone]
      );
      if (participant.rows.length === 0) {
        return res.status(403).json({ success: false, error: 'Not a participant' });
      }

      await db.updateById('messenger_conversations', conversationId, {
        auto_delete_seconds: seconds,
      });

      // Send system message about the change
      const labels = { 0: 'выключены', 86400: '1 день', 604800: '1 неделя', 2592000: '1 месяц' };
      const label = labels[seconds] || `${seconds}с`;
      const senderName = req.user.name || normalizedPhone;
      const systemContent = seconds === 0
        ? `${senderName} выключил(а) исчезающие сообщения`
        : `${senderName} включил(а) исчезающие сообщения: ${label}`;

      const msgId = generateId('msg');
      const systemMsg = {
        id: msgId,
        conversation_id: conversationId,
        sender_phone: 'system',
        sender_name: null,
        type: 'system',
        content: systemContent,
        is_deleted: false,
        created_at: new Date().toISOString(),
      };
      await db.upsert('messenger_messages', systemMsg);

      // WS notify
      if (wsNotify) {
        try {
          await wsNotify.notifyNewMessage(conversationId, systemMsg);
          // Also notify about setting change
          await wsNotify.broadcastToConversation(conversationId, {
            type: 'auto_delete_changed',
            conversationId,
            autoDeleteSeconds: seconds,
          });
        } catch (e) { console.error('WS auto-delete notify error:', e.message); }
      }

      res.json({ success: true, autoDeleteSeconds: seconds });
    } catch (error) {
      console.error('[Messenger] PUT auto-delete error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // AUTO-DELETE SCHEDULER (runs every 5 minutes)
  // ============================================
  const { getMoscowTime } = require('../utils/moscow_time');

  setInterval(async () => {
    try {
      // Find conversations with auto-delete enabled
      const convs = await db.query(
        `SELECT id, auto_delete_seconds FROM messenger_conversations WHERE auto_delete_seconds > 0`
      );
      if (convs.rows.length === 0) return;

      for (const conv of convs.rows) {
        const cutoff = new Date(Date.now() - conv.auto_delete_seconds * 1000).toISOString();
        const deleted = await db.query(
          `UPDATE messenger_messages SET is_deleted = true
           WHERE conversation_id = $1 AND is_deleted = false AND created_at < $2 AND type != 'system'
           RETURNING id`,
          [conv.id, cutoff]
        );

        if (deleted.rows.length > 0 && wsNotify) {
          for (const row of deleted.rows) {
            try {
              await wsNotify.notifyMessageDeleted(conv.id, row.id);
            } catch (_) { /* non-critical */ }
          }
          console.log(`[AutoDelete] Deleted ${deleted.rows.length} messages from ${conv.id}`);
        }
      }
    } catch (error) {
      console.error('[AutoDelete] Scheduler error:', error.message);
    }
  }, 5 * 60 * 1000); // Every 5 minutes

  console.log('✅ Messenger API initialized');
}

module.exports = { setupMessengerAPI };

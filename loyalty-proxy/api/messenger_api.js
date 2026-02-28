/**
 * Messenger API — полностью изолированный модуль мессенджера
 *
 * Таблицы: messenger_conversations, messenger_participants, messenger_messages
 * WebSocket: /ws/messenger (отдельный от /ws/employee-chat)
 * Медиа: /var/www/messenger-media/
 *
 * Ни один import не зависит от employee_chat модулей.
 */

const db = require('../utils/db');
const { requireAuth } = require('../utils/session_middleware');
const pushService = require('../utils/push_service');

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
      const { phone, limit = 50, offset = 0 } = req.query;
      if (!phone) return res.status(400).json({ success: false, error: 'phone required' });

      const normalizedPhone = phone.replace(/[^\d]/g, '');

      // Получаем все conversation_id в которых участвует пользователь
      const result = await db.query(`
        SELECT
          c.*,
          p.last_read_at,
          (
            SELECT row_to_json(lm.*)
            FROM (
              SELECT id, sender_phone, sender_name, type, content, media_url, voice_duration, is_deleted, created_at
              FROM messenger_messages
              WHERE conversation_id = c.id AND is_deleted = false
              ORDER BY created_at DESC
              LIMIT 1
            ) lm
          ) as last_message,
          (
            SELECT COUNT(*)::int
            FROM messenger_messages m
            WHERE m.conversation_id = c.id
              AND m.sender_phone != $1
              AND m.is_deleted = false
              AND m.created_at > COALESCE(p.last_read_at, '1970-01-01'::timestamptz)
          ) as unread_count,
          (
            SELECT json_agg(json_build_object('phone', pp.phone, 'name', pp.name, 'role', pp.role))
            FROM messenger_participants pp
            WHERE pp.conversation_id = c.id
          ) as participants
        FROM messenger_conversations c
        JOIN messenger_participants p ON p.conversation_id = c.id AND p.phone = $1
        ORDER BY COALESCE(
          (SELECT created_at FROM messenger_messages WHERE conversation_id = c.id AND is_deleted = false ORDER BY created_at DESC LIMIT 1),
          c.created_at
        ) DESC
        LIMIT $2 OFFSET $3
      `, [normalizedPhone, Math.min(parseInt(limit) || 50, 100), parseInt(offset)]);

      res.json({ success: true, conversations: result.rows });
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
      const { phone1, phone2, name1, name2 } = req.body;
      if (!phone1 || !phone2) return res.status(400).json({ success: false, error: 'phone1 and phone2 required' });

      const p1 = phone1.replace(/[^\d]/g, '');
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
      await db.transaction(async (client) => {
        await client.query(
          `INSERT INTO messenger_conversations (id, type, created_at, updated_at)
           VALUES ($1, 'private', NOW(), NOW())`,
          [conversationId]
        );
        await client.query(
          `INSERT INTO messenger_participants (conversation_id, phone, name, role, joined_at)
           VALUES ($1, $2, $3, 'member', NOW()), ($1, $4, $5, 'member', NOW())`,
          [conversationId, p1, name1 || null, p2, name2 || null]
        );
      });

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
      const { creatorPhone, creatorName, name, participants } = req.body;
      if (!creatorPhone || !name || !participants || participants.length < 1) {
        return res.status(400).json({ success: false, error: 'creatorPhone, name, participants required (min 1 participant)' });
      }

      if (participants.length > 100) {
        return res.status(400).json({ success: false, error: 'Maximum 100 participants' });
      }

      const normalizedCreator = creatorPhone.replace(/[^\d]/g, '');
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
      const conversation = await db.findById('messenger_conversations', req.params.id);
      if (!conversation) return res.status(404).json({ success: false, error: 'Conversation not found' });

      const parts = await db.query(
        'SELECT phone, name, role, joined_at, last_read_at FROM messenger_participants WHERE conversation_id = $1',
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
      const { phone, name, avatarUrl } = req.body;
      if (!phone) return res.status(400).json({ success: false, error: 'phone required' });

      const conversation = await db.findById('messenger_conversations', req.params.id);
      if (!conversation) return res.status(404).json({ success: false, error: 'Not found' });
      if (conversation.type !== 'group') return res.status(400).json({ success: false, error: 'Only groups can be updated' });

      const normalizedPhone = phone.replace(/[^\d]/g, '');
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
      const { phone } = req.query;
      if (!phone) return res.status(400).json({ success: false, error: 'phone required' });

      const conversation = await db.findById('messenger_conversations', req.params.id);
      if (!conversation) return res.status(404).json({ success: false, error: 'Not found' });

      const normalizedPhone = phone.replace(/[^\d]/g, '');
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
      const { requesterPhone, phones } = req.body;
      if (!requesterPhone || !phones || !phones.length) {
        return res.status(400).json({ success: false, error: 'requesterPhone and phones[] required' });
      }

      const conversation = await db.findById('messenger_conversations', req.params.id);
      if (!conversation || conversation.type !== 'group') {
        return res.status(400).json({ success: false, error: 'Group not found' });
      }

      const normalizedRequester = requesterPhone.replace(/[^\d]/g, '');
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
      const { requesterPhone } = req.query;
      if (!requesterPhone) return res.status(400).json({ success: false, error: 'requesterPhone required' });

      const conversation = await db.findById('messenger_conversations', req.params.id);
      if (!conversation || conversation.type !== 'group') {
        return res.status(400).json({ success: false, error: 'Group not found' });
      }

      const normalizedRequester = requesterPhone.replace(/[^\d]/g, '');
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
      const { phone } = req.body;
      if (!phone) return res.status(400).json({ success: false, error: 'phone required' });

      const normalizedPhone = phone.replace(/[^\d]/g, '');
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

      let sql = `
        SELECT * FROM messenger_messages
        WHERE conversation_id = $1 AND is_deleted = false
      `;
      const params = [conversationId];
      let paramIdx = 2;

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
      const { type = 'text', content, mediaUrl, voiceDuration, replyToId } = req.body;
      // SECURITY: берём телефон из токена авторизации, игнорируем req.body.senderPhone
      const senderName = req.user.name || null;

      const conversationId = req.params.id;
      const normalizedSender = req.user.phone.replace(/[^\d]/g, '');

      // Проверяем что отправитель — участник
      const participant = await db.query(
        'SELECT phone FROM messenger_participants WHERE conversation_id = $1 AND phone = $2',
        [conversationId, normalizedSender]
      );
      if (participant.rows.length === 0) {
        return res.status(403).json({ success: false, error: 'Not a participant' });
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
        created_at: new Date().toISOString()
      };

      await db.insert('messenger_messages', message);

      // Обновляем updated_at разговора
      await db.updateById('messenger_conversations', conversationId, {
        updated_at: new Date().toISOString()
      });

      // Обновляем last_read_at для отправителя
      await db.query(
        'UPDATE messenger_participants SET last_read_at = NOW() WHERE conversation_id = $1 AND phone = $2',
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
          'SELECT phone FROM messenger_participants WHERE conversation_id = $1 AND phone != $2',
          [conversationId, normalizedSender]
        );

        const preview = type === 'text' ? (content || '').substring(0, 100)
          : type === 'voice' ? '🎤 Голосовое сообщение'
          : type === 'image' ? '📷 Фото'
          : type === 'video' ? '🎬 Видео'
          : type === 'emoji' ? content || '😀'
          : 'Новое сообщение';

        const pushTitle = senderName || normalizedSender;

        for (const p of participantsResult.rows) {
          // Не отправляем push онлайн-пользователям
          if (wsNotify && wsNotify.isUserOnline(p.phone)) continue;
          pushService.sendPushToPhone(p.phone, pushTitle, preview, {
            type: 'messenger_message',
            conversationId
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
   * DELETE /api/messenger/conversations/:id/messages/:msgId
   * Soft-delete сообщения (отправитель или admin группы)
   */
  app.delete('/api/messenger/conversations/:id/messages/:msgId', requireAuth, async (req, res) => {
    try {
      const { phone } = req.query;
      if (!phone) return res.status(400).json({ success: false, error: 'phone required' });

      const normalizedPhone = phone.replace(/[^\d]/g, '');
      const message = await db.findById('messenger_messages', req.params.msgId);
      if (!message || message.conversation_id !== req.params.id) {
        return res.status(404).json({ success: false, error: 'Message not found' });
      }

      // Разрешаем удалять: автору ИЛИ создателю группы
      if (message.sender_phone !== normalizedPhone) {
        const conversation = await db.findById('messenger_conversations', req.params.id);
        if (!conversation || conversation.creator_phone !== normalizedPhone) {
          return res.status(403).json({ success: false, error: 'Cannot delete this message' });
        }
      }

      await db.updateById('messenger_messages', req.params.msgId, { is_deleted: true });

      if (wsNotify) {
        try {
          await wsNotify.notifyMessageDeleted(req.params.id, req.params.msgId);
        } catch (e) {}
      }

      res.json({ success: true });
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
      const { phone } = req.body;
      if (!phone) return res.status(400).json({ success: false, error: 'phone required' });

      const normalizedPhone = phone.replace(/[^\d]/g, '');
      const now = new Date().toISOString();

      await db.query(
        'UPDATE messenger_participants SET last_read_at = $1 WHERE conversation_id = $2 AND phone = $3',
        [now, req.params.id, normalizedPhone]
      );

      if (wsNotify) {
        try {
          await wsNotify.notifyReadReceipt(req.params.id, normalizedPhone, now);
        } catch (e) {}
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
      const { phone, reaction } = req.body;
      if (!phone || !reaction) return res.status(400).json({ success: false, error: 'phone and reaction required' });

      const normalizedPhone = phone.replace(/[^\d]/g, '');
      const message = await db.findById('messenger_messages', req.params.msgId);
      if (!message || message.conversation_id !== req.params.id) {
        return res.status(404).json({ success: false, error: 'Message not found' });
      }

      const reactions = message.reactions || {};
      if (!reactions[reaction]) reactions[reaction] = [];
      if (!reactions[reaction].includes(normalizedPhone)) {
        reactions[reaction].push(normalizedPhone);
      }

      await db.updateById('messenger_messages', req.params.msgId, {
        reactions: JSON.stringify(reactions)
      });

      if (wsNotify) {
        try {
          await wsNotify.notifyReactionAdded(req.params.id, req.params.msgId, reaction, normalizedPhone);
        } catch (e) {}
      }

      res.json({ success: true, reactions });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/messenger/conversations/:id/messages/:msgId/reactions?phone=X&reaction=Y
   */
  app.delete('/api/messenger/conversations/:id/messages/:msgId/reactions', requireAuth, async (req, res) => {
    try {
      const { phone, reaction } = req.query;
      if (!phone || !reaction) return res.status(400).json({ success: false, error: 'phone and reaction required' });

      const normalizedPhone = phone.replace(/[^\d]/g, '');
      const message = await db.findById('messenger_messages', req.params.msgId);
      if (!message || message.conversation_id !== req.params.id) {
        return res.status(404).json({ success: false, error: 'Message not found' });
      }

      const reactions = message.reactions || {};
      if (reactions[reaction]) {
        reactions[reaction] = reactions[reaction].filter(p => p !== normalizedPhone);
        if (reactions[reaction].length === 0) delete reactions[reaction];
      }

      await db.updateById('messenger_messages', req.params.msgId, {
        reactions: JSON.stringify(reactions)
      });

      if (wsNotify) {
        try {
          await wsNotify.notifyReactionRemoved(req.params.id, req.params.msgId, reaction, normalizedPhone);
        } catch (e) {}
      }

      res.json({ success: true, reactions });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============================================
  // MEDIA UPLOAD
  // ============================================

  /**
   * POST /api/messenger/upload
   * Загрузка медиа-файлов (фото, видео, голосовые)
   */
  if (uploadMedia) {
    const { compressUpload } = require('../utils/image_compress');

    app.post('/api/messenger/upload', requireAuth, uploadMedia.single('file'), compressUpload, async (req, res) => {
      try {
        if (!req.file) return res.status(400).json({ success: false, error: 'No file uploaded' });

        const mediaUrl = `https://arabica26.ru/messenger-media/${req.file.filename}`;
        console.log(`[Messenger] Upload: ${req.file.filename} (${(req.file.size / 1024).toFixed(1)}KB)`);

        res.json({
          success: true,
          url: mediaUrl,
          filename: req.file.filename
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
      const { phone } = req.query;
      if (!phone) return res.status(400).json({ success: false, error: 'phone required' });

      const normalizedPhone = phone.replace(/[^\d]/g, '');

      const result = await db.query(`
        SELECT COALESCE(SUM(unread), 0)::int as total_unread
        FROM (
          SELECT COUNT(*)::int as unread
          FROM messenger_messages m
          JOIN messenger_participants p ON p.conversation_id = m.conversation_id AND p.phone = $1
          WHERE m.sender_phone != $1
            AND m.is_deleted = false
            AND m.created_at > COALESCE(p.last_read_at, '1970-01-01'::timestamptz)
        ) sub
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
      const { phone, displayName, avatarUrl } = req.body;
      if (!phone) return res.status(400).json({ success: false, error: 'phone required' });

      const normalizedPhone = phone.replace(/[^\d]/g, '');

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

  console.log('✅ Messenger API initialized');
}

module.exports = { setupMessengerAPI };

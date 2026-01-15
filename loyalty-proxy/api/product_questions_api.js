const fs = require('fs');
const path = require('path');

// Push-уведомления
const {
  notifyQuestionCreated,
  notifyQuestionAnswered
} = require('./product_questions_notifications');

const PRODUCT_QUESTIONS_DIR = '/var/www/product-questions';
const PRODUCT_QUESTION_DIALOGS_DIR = '/var/www/product-question-dialogs';
const PRODUCT_QUESTION_PHOTOS_DIR = '/var/www/product-question-photos';

[PRODUCT_QUESTIONS_DIR, PRODUCT_QUESTION_DIALOGS_DIR, PRODUCT_QUESTION_PHOTOS_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

function setupProductQuestionsAPI(app, uploadProductQuestionPhoto) {
  // ===== PRODUCT QUESTIONS =====

  app.get('/api/product-questions', async (req, res) => {
    try {
      console.log('GET /api/product-questions');
      const { shopAddress } = req.query;
      const questions = [];

      if (fs.existsSync(PRODUCT_QUESTIONS_DIR)) {
        const files = fs.readdirSync(PRODUCT_QUESTIONS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(PRODUCT_QUESTIONS_DIR, file), 'utf8');
            const question = JSON.parse(content);

            // Фильтр по магазину - проверяем shops[] массив или старый формат
            if (shopAddress) {
              let matchesShop = false;

              // Новый формат - проверяем shops[]
              if (question.shops && Array.isArray(question.shops)) {
                matchesShop = question.shops.some(shop => shop.shopAddress === shopAddress);
              }
              // Старый формат - проверяем shopAddress напрямую
              else if (question.shopAddress === shopAddress) {
                matchesShop = true;
              }

              if (!matchesShop) continue;
            }

            questions.push(question);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      // Сортировка по timestamp или createdAt (для совместимости со старым форматом)
      questions.sort((a, b) => {
        const timeA = new Date(a.timestamp || a.createdAt || 0);
        const timeB = new Date(b.timestamp || b.createdAt || 0);
        return timeB - timeA;
      });

      console.log(`✅ Found ${questions.length} product questions`);
      res.json({ success: true, questions });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/product-questions', async (req, res) => {
    try {
      console.log('POST /api/product-questions - req.body:', JSON.stringify(req.body));
      const { clientPhone, clientName, shopAddress, questionText, questionImageUrl } = req.body;
      console.log('POST /api/product-questions:', questionText?.substring(0, 50));

      if (!clientPhone || !clientName || !shopAddress || !questionText) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: clientPhone, clientName, shopAddress, questionText'
        });
      }

      const questionId = `pq_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      const timestamp = new Date().toISOString();
      const messageId = `msg_${Date.now()}`;

      // Определяем, это вопрос для всей сети или для конкретного магазина
      const isNetworkWide = shopAddress === 'Вся сеть';

      // Создаем структуру вопроса с поддержкой множественных магазинов
      const question = {
        id: questionId,
        clientPhone,
        clientName,
        originalShopAddress: shopAddress,
        isNetworkWide,
        questionText,
        questionImageUrl: questionImageUrl || null,
        timestamp,
        shops: [
          {
            shopAddress,
            shopName: shopAddress,
            isAnswered: false,
            answeredBy: null,
            answeredByName: null,
            lastAnswerTime: null
          }
        ],
        messages: [
          {
            id: messageId,
            senderType: 'client',
            senderPhone: clientPhone,
            senderName: clientName,
            shopAddress: null,
            text: questionText,
            imageUrl: questionImageUrl || null,
            timestamp
          }
        ]
      };

      const filePath = path.join(PRODUCT_QUESTIONS_DIR, `${questionId}.json`);
      fs.writeFileSync(filePath, JSON.stringify(question, null, 2), 'utf8');

      console.log('✅ Question created:', questionId);

      // ✅ Отправка уведомлений всем сотрудникам
      try {
        await notifyQuestionCreated(question);
      } catch (e) {
        console.error('❌ Ошибка отправки уведомлений:', e);
      }

      res.json({ success: true, questionId, question });
    } catch (error) {
      console.error('Error creating product question:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/product-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      console.log('GET /api/product-questions/:questionId', questionId);

      const filePath = path.join(PRODUCT_QUESTIONS_DIR, `${questionId}.json`);

      if (fs.existsSync(filePath)) {
        const question = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        res.json({ success: true, question });
      } else {
        res.status(404).json({ success: false, error: 'Question not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/product-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const updates = req.body;
      console.log('PUT /api/product-questions/:questionId', questionId);

      const filePath = path.join(PRODUCT_QUESTIONS_DIR, `${questionId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      const question = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const updated = { ...question, ...updates, updatedAt: new Date().toISOString() };

      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, question: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/product-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      console.log('DELETE /api/product-questions/:questionId', questionId);

      const filePath = path.join(PRODUCT_QUESTIONS_DIR, `${questionId}.json`);

      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Question not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== PRODUCT QUESTION MESSAGES (для ответов сотрудников) =====

  app.post('/api/product-questions/:questionId/messages', async (req, res) => {
    try {
      const { questionId } = req.params;
      const { shopAddress, text, senderPhone, senderName, imageUrl } = req.body;
      console.log('POST /api/product-questions/:questionId/messages', questionId, 'shop:', shopAddress);

      if (!shopAddress || !text) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: shopAddress, text'
        });
      }

      const filePath = path.join(PRODUCT_QUESTIONS_DIR, `${questionId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      const question = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const timestamp = new Date().toISOString();
      const messageId = `msg_${Date.now()}`;

      // Создаем новое сообщение от сотрудника
      const newMessage = {
        id: messageId,
        senderType: 'employee',
        senderPhone: senderPhone || null,
        senderName: senderName || 'Сотрудник',
        shopAddress: shopAddress,
        text: text,
        imageUrl: imageUrl || null,
        timestamp
      };

      // Инициализируем массивы если они отсутствуют (для старых вопросов)
      if (!question.messages) {
        question.messages = [];
      }
      if (!question.shops) {
        question.shops = [];
      }

      // Добавляем сообщение в массив messages
      question.messages.push(newMessage);

      // Обновляем статус в массиве shops для конкретного магазина
      const shopIndex = question.shops.findIndex(s => s.shopAddress === shopAddress);
      if (shopIndex !== -1) {
        // Магазин уже есть в списке - обновляем его статус
        question.shops[shopIndex].isAnswered = true;
        question.shops[shopIndex].answeredBy = senderPhone;
        question.shops[shopIndex].answeredByName = senderName || 'Сотрудник';
        question.shops[shopIndex].lastAnswerTime = timestamp;
      } else {
        // Магазина нет в списке - добавляем его (для случая когда сотрудник отвечает из другого магазина)
        question.shops.push({
          shopAddress: shopAddress,
          shopName: shopAddress,
          isAnswered: true,
          answeredBy: senderPhone,
          answeredByName: senderName || 'Сотрудник',
          lastAnswerTime: timestamp
        });
      }

      fs.writeFileSync(filePath, JSON.stringify(question, null, 2), 'utf8');

      console.log('✅ Answer added to question:', questionId, 'by shop:', shopAddress);

      // ✅ Отправка уведомления клиенту
      try {
        await notifyQuestionAnswered(question, newMessage);
      } catch (e) {
        console.error('❌ Ошибка отправки уведомления клиенту:', e);
      }

      res.json({ success: true, message: newMessage });
    } catch (error) {
      console.error('Error adding answer to product question:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/product-questions/:questionId/mark-read - Пометить сообщения вопроса как прочитанные
  app.post('/api/product-questions/:questionId/mark-read', (req, res) => {
    try {
      const { questionId } = req.params;
      const { readerType } = req.body; // 'client' or 'employee'
      console.log('POST /api/product-questions/:questionId/mark-read', questionId, readerType);

      const filePath = path.join(PRODUCT_QUESTIONS_DIR, `${questionId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Question not found' });
      }

      const question = JSON.parse(fs.readFileSync(filePath, 'utf8'));

      // Помечаем сообщения как прочитанные
      if (question.messages && question.messages.length > 0) {
        question.messages.forEach(msg => {
          if (readerType === 'client' && msg.senderType === 'employee') {
            msg.isRead = true;
          } else if (readerType === 'employee' && msg.senderType === 'client') {
            msg.isRead = true;
          }
        });
      }

      fs.writeFileSync(filePath, JSON.stringify(question, null, 2), 'utf8');
      console.log('✅ Messages marked as read for question:', questionId);

      res.json({ success: true });
    } catch (error) {
      console.error('Error marking question messages as read:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/product-questions/client/:phone/mark-all-read - Пометить все сообщения клиента как прочитанные
  app.post('/api/product-questions/client/:phone/mark-all-read', (req, res) => {
    try {
      const { phone } = req.params;
      console.log('POST /api/product-questions/client/:phone/mark-all-read', phone);

      let markedCount = 0;

      if (fs.existsSync(PRODUCT_QUESTIONS_DIR)) {
        const files = fs.readdirSync(PRODUCT_QUESTIONS_DIR).filter(f => f.endsWith('.json'));

        files.forEach(file => {
          try {
            const filePath = path.join(PRODUCT_QUESTIONS_DIR, file);
            const question = JSON.parse(fs.readFileSync(filePath, 'utf8'));

            if (question.clientPhone === phone) {
              let hasChanges = false;

              if (question.messages && question.messages.length > 0) {
                question.messages.forEach(msg => {
                  if (msg.senderType === 'employee' && !msg.isRead) {
                    msg.isRead = true;
                    hasChanges = true;
                  }
                });
              }

              if (hasChanges) {
                fs.writeFileSync(filePath, JSON.stringify(question, null, 2), 'utf8');
                markedCount++;
              }
            }
          } catch (e) {
            console.error(`Error processing ${file}:`, e);
          }
        });
      }

      console.log(`✅ Marked ${markedCount} questions as read for client ${phone}`);
      res.json({ success: true, markedCount });
    } catch (error) {
      console.error('Error marking all questions as read:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== PRODUCT QUESTION DIALOGS =====

  app.get('/api/product-questions/:questionId/dialog', async (req, res) => {
    try {
      const { questionId } = req.params;
      console.log('GET /api/product-questions/:questionId/dialog', questionId);

      const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, `${questionId}.json`);

      if (fs.existsSync(filePath)) {
        const dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        res.json({ success: true, dialog });
      } else {
        res.json({ success: true, dialog: { questionId, messages: [] } });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/product-questions/:questionId/dialog', async (req, res) => {
    try {
      const { questionId } = req.params;
      const message = req.body;
      console.log('POST /api/product-questions/:questionId/dialog', questionId);

      const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, `${questionId}.json`);

      let dialog = { questionId, messages: [] };
      if (fs.existsSync(filePath)) {
        dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      }

      message.timestamp = message.timestamp || new Date().toISOString();
      message.id = message.id || `msg_${Date.now()}`;
      dialog.messages.push(message);

      fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      res.json({ success: true, message });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== PERSONAL PRODUCT DIALOGS (6 endpoints) =====

  // 1. POST /api/product-question-dialogs - Создать персональный диалог
  app.post('/api/product-question-dialogs', async (req, res) => {
    try {
      const { clientPhone, clientName, shopAddress, originalQuestionId, messageText, initialMessage, imageUrl, initialImageUrl } = req.body;
      console.log('POST /api/product-question-dialogs');

      // Поддержка обоих вариантов названия поля
      const text = messageText || initialMessage;
      const image = imageUrl || initialImageUrl;

      if (!clientPhone || !clientName || !shopAddress) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: clientPhone, clientName, shopAddress'
        });
      }

      const dialogId = 'dialog_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
      const timestamp = new Date().toISOString();

      const dialog = {
        id: dialogId,
        clientPhone,
        clientName,
        shopAddress,
        originalQuestionId: originalQuestionId || null,
        createdAt: timestamp,
        hasUnreadFromClient: text ? true : false,
        hasUnreadFromEmployee: false,
        lastMessageTime: text ? timestamp : null,
        messages: []
      };

      // Добавляем начальное сообщение если оно есть
      if (text) {
        const messageId = 'msg_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
        dialog.messages.push({
          id: messageId,
          senderType: 'client',
          senderPhone: clientPhone,
          senderName: clientName,
          shopAddress: null,
          text: text,
          imageUrl: image || null,
          timestamp,
          isRead: false
        });
      }

      const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, `${dialogId}.json`);
      fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2));

      // Отправить push сотрудникам только если есть сообщение
      if (text && dialog.messages.length > 0) {
        try {
          await notifyQuestionCreated(dialog.messages[0]);
        } catch (e) {
          console.error('❌ Ошибка отправки уведомлений:', e);
        }
      }

      console.log('✅ Personal dialog created:', dialogId);
      res.json({ success: true, dialog });
    } catch (error) {
      console.error('Error creating personal dialog:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // 2. GET /api/product-question-dialogs/client/:phone - Получить диалоги клиента
  app.get('/api/product-question-dialogs/client/:phone', (req, res) => {
    try {
      const { phone } = req.params;
      console.log('GET /api/product-question-dialogs/client/:phone', phone);

      const dialogs = [];

      if (fs.existsSync(PRODUCT_QUESTION_DIALOGS_DIR)) {
        const files = fs.readdirSync(PRODUCT_QUESTION_DIALOGS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const data = fs.readFileSync(path.join(PRODUCT_QUESTION_DIALOGS_DIR, file), 'utf8');
            const dialog = JSON.parse(data);

            if (dialog.clientPhone === phone) {
              dialogs.push(dialog);
            }
          } catch (e) {
            console.error(`Error reading dialog ${file}:`, e);
          }
        }
      }

      // Сортировать по lastMessageTime
      dialogs.sort((a, b) => new Date(b.lastMessageTime) - new Date(a.lastMessageTime));

      console.log(`✅ Found ${dialogs.length} dialogs for client ${phone}`);
      res.json({ success: true, dialogs });
    } catch (error) {
      console.error('Error getting client dialogs:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // 3. GET /api/product-question-dialogs/shop/:shopAddress - Получить диалоги магазина
  app.get('/api/product-question-dialogs/shop/:shopAddress', (req, res) => {
    try {
      const { shopAddress } = req.params;
      console.log('GET /api/product-question-dialogs/shop/:shopAddress', shopAddress);

      const dialogs = [];

      if (fs.existsSync(PRODUCT_QUESTION_DIALOGS_DIR)) {
        const files = fs.readdirSync(PRODUCT_QUESTION_DIALOGS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const data = fs.readFileSync(path.join(PRODUCT_QUESTION_DIALOGS_DIR, file), 'utf8');
            const dialog = JSON.parse(data);

            if (dialog.shopAddress === shopAddress) {
              dialogs.push(dialog);
            }
          } catch (e) {
            console.error(`Error reading dialog ${file}:`, e);
          }
        }
      }

      dialogs.sort((a, b) => new Date(b.lastMessageTime) - new Date(a.lastMessageTime));

      console.log(`✅ Found ${dialogs.length} dialogs for shop ${shopAddress}`);
      res.json({ success: true, dialogs });
    } catch (error) {
      console.error('Error getting shop dialogs:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // 4. GET /api/product-question-dialogs/:dialogId - Получить конкретный диалог
  app.get('/api/product-question-dialogs/:dialogId', (req, res) => {
    try {
      const { dialogId } = req.params;
      console.log('GET /api/product-question-dialogs/:dialogId', dialogId);

      const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, `${dialogId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Dialog not found' });
      }

      const data = fs.readFileSync(filePath, 'utf8');
      const dialog = JSON.parse(data);

      res.json({ success: true, dialog });
    } catch (error) {
      console.error('Error getting dialog:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // 5. POST /api/product-question-dialogs/:dialogId/messages - Добавить сообщение в диалог
  app.post('/api/product-question-dialogs/:dialogId/messages', async (req, res) => {
    try {
      const { dialogId } = req.params;
      const { senderType, senderPhone, senderName, shopAddress, text, imageUrl } = req.body;
      console.log('POST /api/product-question-dialogs/:dialogId/messages', dialogId);

      const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, `${dialogId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Dialog not found' });
      }

      const data = fs.readFileSync(filePath, 'utf8');
      const dialog = JSON.parse(data);

      const messageId = 'msg_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
      const timestamp = new Date().toISOString();

      const newMessage = {
        id: messageId,
        senderType,
        senderPhone,
        senderName,
        shopAddress: senderType === 'employee' ? shopAddress : null,
        text,
        imageUrl: imageUrl || null,
        timestamp,
        isRead: false
      };

      dialog.messages.push(newMessage);
      dialog.lastMessageTime = timestamp;

      if (senderType === 'client') {
        dialog.hasUnreadFromClient = true;
      } else {
        dialog.hasUnreadFromEmployee = true;
      }

      fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2));

      // Отправить push
      try {
        if (senderType === 'employee') {
          await notifyQuestionAnswered(dialog, newMessage);
        } else {
          await notifyQuestionCreated(newMessage);
        }
      } catch (e) {
        console.error('❌ Ошибка отправки уведомлений:', e);
      }

      console.log('✅ Message added to dialog:', dialogId);
      res.json({ success: true, message: newMessage });
    } catch (error) {
      console.error('Error adding message to dialog:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // 6. POST /api/product-question-dialogs/:dialogId/mark-read - Пометить диалог как прочитанный
  app.post('/api/product-question-dialogs/:dialogId/mark-read', (req, res) => {
    try {
      const { dialogId } = req.params;
      const { readerType } = req.body; // 'client' or 'employee'
      console.log('POST /api/product-question-dialogs/:dialogId/mark-read', dialogId, readerType);

      const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, `${dialogId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Dialog not found' });
      }

      const data = fs.readFileSync(filePath, 'utf8');
      const dialog = JSON.parse(data);

      if (readerType === 'client') {
        dialog.hasUnreadFromEmployee = false;
        // Пометить сообщения от сотрудников как прочитанные
        dialog.messages.forEach(msg => {
          if (msg.senderType === 'employee') {
            msg.isRead = true;
          }
        });
      } else if (readerType === 'employee') {
        dialog.hasUnreadFromClient = false;
        // Пометить сообщения от клиента как прочитанные
        dialog.messages.forEach(msg => {
          if (msg.senderType === 'client') {
            msg.isRead = true;
          }
        });
      }

      fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2));

      console.log('✅ Dialog marked as read:', dialogId, 'by', readerType);
      res.json({ success: true, dialog });
    } catch (error) {
      console.error('Error marking dialog as read:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CLIENT ENDPOINTS =====

  // GET /api/product-questions/client/:phone - Получить все вопросы клиента (для "Мои диалоги")
  app.get('/api/product-questions/client/:phone', (req, res) => {
    try {
      const { phone } = req.params;
      console.log('GET /api/product-questions/client/:phone', phone);

      const questions = [];
      if (fs.existsSync(PRODUCT_QUESTIONS_DIR)) {
        const files = fs.readdirSync(PRODUCT_QUESTIONS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const data = fs.readFileSync(path.join(PRODUCT_QUESTIONS_DIR, file), 'utf8');
            const question = JSON.parse(data);

            if (question.clientPhone === phone) {
              questions.push(question);
            }
          } catch (e) {
            console.error(`Error reading question ${file}:`, e);
          }
        }
      }

      // Собираем все сообщения в единый массив
      const allMessages = [];
      let unreadCount = 0;
      let lastMessage = null;

      questions.forEach(question => {
        if (question.messages && question.messages.length > 0) {
          question.messages.forEach(msg => {
            allMessages.push(msg);
            // Последнее сообщение - самое новое по timestamp
            if (!lastMessage || new Date(msg.timestamp) > new Date(lastMessage.timestamp)) {
              lastMessage = msg;
            }
            // Подсчитываем непрочитанные от сотрудников
            if (msg.senderType === 'employee' && (!msg.isRead || msg.isRead === false)) {
              unreadCount++;
            }
          });
        }
      });

      // Сортируем сообщения по timestamp
      allMessages.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));

      const response = {
        success: true,
        hasQuestions: questions.length > 0,
        messages: allMessages,
        unreadCount: unreadCount,
        lastMessage: lastMessage
      };

      console.log(`✅ Found ${questions.length} questions with ${allMessages.length} messages for client ${phone}, unread: ${unreadCount}`);
      res.json(response);
    } catch (error) {
      console.error('Error getting client questions:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GROUPING ENDPOINT (1 endpoint) =====

  // GET /api/product-questions/client/:phone/grouped - Группировка диалогов по магазинам
  app.get('/api/product-questions/client/:phone/grouped', (req, res) => {
    try {
      const { phone } = req.params;
      console.log('GET /api/product-questions/client/:phone/grouped', phone);

      // Получить все вопросы клиента
      const questions = [];
      if (fs.existsSync(PRODUCT_QUESTIONS_DIR)) {
        const files = fs.readdirSync(PRODUCT_QUESTIONS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const data = fs.readFileSync(path.join(PRODUCT_QUESTIONS_DIR, file), 'utf8');
            const question = JSON.parse(data);

            if (question.clientPhone === phone) {
              questions.push(question);
            }
          } catch (e) {
            console.error(`Error reading question ${file}:`, e);
          }
        }
      }

      // Получить все персональные диалоги
      const dialogs = [];
      if (fs.existsSync(PRODUCT_QUESTION_DIALOGS_DIR)) {
        const dialogFiles = fs.readdirSync(PRODUCT_QUESTION_DIALOGS_DIR).filter(f => f.endsWith('.json'));

        for (const file of dialogFiles) {
          try {
            const data = fs.readFileSync(path.join(PRODUCT_QUESTION_DIALOGS_DIR, file), 'utf8');
            const dialog = JSON.parse(data);

            if (dialog.clientPhone === phone) {
              dialogs.push(dialog);
            }
          } catch (e) {
            console.error(`Error reading dialog ${file}:`, e);
          }
        }
      }

      // Группировать по магазинам
      const grouped = {};
      const networkWide = [];

      questions.forEach(question => {
        if (question.isNetworkWide) {
          networkWide.push(question);
        } else {
          const shop = question.shops ? question.shops[0].shopAddress : question.shopAddress;
          if (!grouped[shop]) {
            grouped[shop] = {
              shopAddress: shop,
              questions: [],
              dialogs: [],
              unreadCount: 0
            };
          }
          grouped[shop].questions.push(question);

          // Подсчитать непрочитанные
          if (question.messages && question.messages.length > 0) {
            const lastMsg = question.messages[question.messages.length - 1];
            if (lastMsg.senderType === 'employee' && !lastMsg.isRead) {
              grouped[shop].unreadCount++;
            }
          }
        }
      });

      dialogs.forEach(dialog => {
        const shop = dialog.shopAddress;
        if (!grouped[shop]) {
          grouped[shop] = {
            shopAddress: shop,
            questions: [],
            dialogs: [],
            unreadCount: 0
          };
        }
        grouped[shop].dialogs.push(dialog);

        if (dialog.hasUnreadFromEmployee) {
          grouped[shop].unreadCount++;
        }
      });

      // Подсчитать общий счетчик
      const totalUnread = Object.values(grouped).reduce((sum, group) => sum + group.unreadCount, 0) +
        networkWide.filter(q => {
          if (!q.messages || q.messages.length === 0) return false;
          const lastMsg = q.messages[q.messages.length - 1];
          return lastMsg && lastMsg.senderType === 'employee' && !lastMsg.isRead;
        }).length;

      console.log(`✅ Grouped ${questions.length} questions + ${dialogs.length} dialogs for client ${phone}`);
      res.json({
        success: true,
        totalUnread,
        networkWide: {
          questions: networkWide,
          unreadCount: networkWide.filter(q => {
            if (!q.messages || q.messages.length === 0) return false;
            const lastMsg = q.messages[q.messages.length - 1];
            return lastMsg && lastMsg.senderType === 'employee' && !lastMsg.isRead;
          }).length
        },
        byShop: grouped
      });
    } catch (error) {
      console.error('Error grouping client questions:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== PRODUCT QUESTION PHOTOS =====

  if (uploadProductQuestionPhoto) {
    app.post('/api/product-questions/upload-photo', uploadProductQuestionPhoto.single('photo'), async (req, res) => {
      try {
        console.log('POST /api/product-questions/upload-photo');

        if (!req.file) {
          return res.status(400).json({ success: false, error: 'No file uploaded' });
        }

        const photoUrl = `/product-question-photos/${req.file.filename}`;
        console.log('✅ Photo uploaded:', photoUrl);
        res.json({ success: true, photoUrl });
      } catch (error) {
        console.error('Error uploading product question photo:', error);
        res.status(500).json({ success: false, error: error.message });
      }
    });
  }

  console.log('✅ Product Questions API initialized');
}

module.exports = { setupProductQuestionsAPI };

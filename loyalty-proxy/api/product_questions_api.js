const fs = require('fs');
const path = require('path');

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
      const { status, shopAddress } = req.query;
      const questions = [];

      if (fs.existsSync(PRODUCT_QUESTIONS_DIR)) {
        const files = fs.readdirSync(PRODUCT_QUESTIONS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(PRODUCT_QUESTIONS_DIR, file), 'utf8');
            const question = JSON.parse(content);

            if (status && question.status !== status) continue;
            if (shopAddress && question.shopAddress !== shopAddress) continue;

            questions.push(question);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      questions.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
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
      res.json({ success: true, message: newMessage });
    } catch (error) {
      console.error('Error adding answer to product question:', error);
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

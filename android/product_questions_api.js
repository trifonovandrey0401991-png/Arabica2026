// ========== Product Questions API ==========
const PRODUCT_QUESTIONS_DIR = '/var/www/product-questions';
const PRODUCT_QUESTIONS_PHOTOS_DIR = '/var/www/product-question-photos';
const SHOPS_DIR = '/var/www/shops';

// Ensure directories exist
if (!fs.existsSync(PRODUCT_QUESTIONS_DIR)) {
  fs.mkdirSync(PRODUCT_QUESTIONS_DIR, { recursive: true });
}
if (!fs.existsSync(PRODUCT_QUESTIONS_PHOTOS_DIR)) {
  fs.mkdirSync(PRODUCT_QUESTIONS_PHOTOS_DIR, { recursive: true });
}

// Helper: Load all shops
function loadAllShopsForQuestions() {
  try {
    if (!fs.existsSync(SHOPS_DIR)) return [];
    const files = fs.readdirSync(SHOPS_DIR).filter(f => f.endsWith('.json'));
    return files.map(f => {
      const content = fs.readFileSync(path.join(SHOPS_DIR, f), 'utf8');
      return JSON.parse(content);
    });
  } catch (e) {
    console.error('Error loading shops:', e);
    return [];
  }
}

// Helper: Generate UUID
function generateQuestionId() {
  return 'pq_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
}

// POST /api/product-questions - Create a new question
app.post('/api/product-questions', async (req, res) => {
  try {
    const { clientPhone, clientName, shopAddress, questionText, questionImageUrl } = req.body;
    console.log('POST /api/product-questions', { clientPhone, clientName, shopAddress });

    if (!clientPhone || !questionText) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }

    const questionId = generateQuestionId();
    const timestamp = new Date().toISOString();

    // Determine shops for this question
    let shops = [];
    const isNetworkWide = shopAddress === 'Вся сеть' || !shopAddress;

    if (isNetworkWide) {
      // Load all shops and create entry for each
      const allShops = loadAllShopsForQuestions();
      shops = allShops.map(shop => ({
        shopAddress: shop.address,
        shopName: shop.name,
        isAnswered: false,
        answeredBy: null,
        answeredByName: null,
        lastAnswerTime: null
      }));
    } else {
      // Single shop
      shops = [{
        shopAddress: shopAddress,
        shopName: shopAddress,
        isAnswered: false,
        answeredBy: null,
        answeredByName: null,
        lastAnswerTime: null
      }];
    }

    const question = {
      id: questionId,
      clientPhone,
      clientName: clientName || 'Клиент',
      originalShopAddress: shopAddress || 'Вся сеть',
      isNetworkWide,
      questionText,
      questionImageUrl: questionImageUrl || null,
      timestamp,
      shops,
      messages: [{
        id: 'msg_' + Date.now(),
        senderType: 'client',
        senderPhone: clientPhone,
        senderName: clientName || 'Клиент',
        shopAddress: null,
        text: questionText,
        imageUrl: questionImageUrl || null,
        timestamp
      }]
    };

    // Save question
    const filePath = path.join(PRODUCT_QUESTIONS_DIR, questionId + '.json');
    fs.writeFileSync(filePath, JSON.stringify(question, null, 2), 'utf8');

    console.log('Product question created: ' + questionId + ', shops: ' + shops.length);
    res.json({ success: true, questionId });
  } catch (err) {
    console.error('Error creating product question:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/product-questions - Get all questions (with filters)
app.get('/api/product-questions', async (req, res) => {
  try {
    const { shopAddress, isAnswered } = req.query;
    console.log('GET /api/product-questions', { shopAddress, isAnswered });

    if (!fs.existsSync(PRODUCT_QUESTIONS_DIR)) {
      return res.json({ success: true, questions: [] });
    }

    const files = fs.readdirSync(PRODUCT_QUESTIONS_DIR).filter(f => f.endsWith('.json'));
    let questions = [];

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(PRODUCT_QUESTIONS_DIR, file), 'utf8');
        const question = JSON.parse(content);

        // Expand network-wide questions into separate entries per shop
        if (question.isNetworkWide && question.shops) {
          for (const shop of question.shops) {
            // Apply filters
            if (shopAddress && shop.shopAddress !== shopAddress) continue;
            if (isAnswered !== undefined) {
              const filterAnswered = isAnswered === 'true';
              if (shop.isAnswered !== filterAnswered) continue;
            }

            questions.push({
              id: question.id,
              clientPhone: question.clientPhone,
              clientName: question.clientName,
              shopAddress: shop.shopAddress,
              shopName: shop.shopName,
              questionText: question.questionText,
              questionImageUrl: question.questionImageUrl,
              timestamp: question.timestamp,
              isAnswered: shop.isAnswered,
              answeredBy: shop.answeredBy,
              answeredByName: shop.answeredByName,
              lastAnswerTime: shop.lastAnswerTime,
              isNetworkWide: true,
              messages: question.messages
            });
          }
        } else {
          // Single shop question
          const shop = question.shops && question.shops[0] ? question.shops[0] : {};

          // Apply filters
          if (shopAddress && shop.shopAddress !== shopAddress) continue;
          if (isAnswered !== undefined) {
            const filterAnswered = isAnswered === 'true';
            if (shop.isAnswered !== filterAnswered) continue;
          }

          questions.push({
            id: question.id,
            clientPhone: question.clientPhone,
            clientName: question.clientName,
            shopAddress: shop.shopAddress || question.originalShopAddress,
            shopName: shop.shopName || question.originalShopAddress,
            questionText: question.questionText,
            questionImageUrl: question.questionImageUrl,
            timestamp: question.timestamp,
            isAnswered: shop.isAnswered || false,
            answeredBy: shop.answeredBy,
            answeredByName: shop.answeredByName,
            lastAnswerTime: shop.lastAnswerTime,
            isNetworkWide: false,
            messages: question.messages
          });
        }
      } catch (e) {
        console.error('Error parsing question file:', file, e.message);
      }
    }

    // Sort by timestamp (newest first)
    questions.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

    console.log('Loaded ' + questions.length + ' product questions');
    res.json({ success: true, questions });
  } catch (err) {
    console.error('Error loading product questions:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/product-questions/:id - Get single question
app.get('/api/product-questions/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('GET /api/product-questions/:id', id);

    const filePath = path.join(PRODUCT_QUESTIONS_DIR, id + '.json');
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, error: 'Question not found' });
    }

    const content = fs.readFileSync(filePath, 'utf8');
    const question = JSON.parse(content);

    res.json({ success: true, question });
  } catch (err) {
    console.error('Error loading product question:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /api/product-questions/:id/messages - Add message (answer) to question
app.post('/api/product-questions/:id/messages', async (req, res) => {
  try {
    const { id } = req.params;
    const { shopAddress, text, senderPhone, senderName, imageUrl } = req.body;
    console.log('POST /api/product-questions/:id/messages', { id, shopAddress, senderName });

    if (!text || !shopAddress) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }

    const filePath = path.join(PRODUCT_QUESTIONS_DIR, id + '.json');
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, error: 'Question not found' });
    }

    const content = fs.readFileSync(filePath, 'utf8');
    const question = JSON.parse(content);

    const timestamp = new Date().toISOString();
    const message = {
      id: 'msg_' + Date.now(),
      senderType: 'employee',
      senderPhone: senderPhone || null,
      senderName: senderName || 'Сотрудник',
      shopAddress,
      text,
      imageUrl: imageUrl || null,
      timestamp
    };

    // Add message
    question.messages.push(message);

    // Update shop status
    if (question.shops) {
      const shopEntry = question.shops.find(s => s.shopAddress === shopAddress);
      if (shopEntry && !shopEntry.isAnswered) {
        shopEntry.isAnswered = true;
        shopEntry.answeredBy = senderPhone;
        shopEntry.answeredByName = senderName || 'Сотрудник';
        shopEntry.lastAnswerTime = timestamp;
      }
    }

    // Save
    fs.writeFileSync(filePath, JSON.stringify(question, null, 2), 'utf8');

    console.log('Message added to question ' + id + ' from shop ' + shopAddress);
    res.json({ success: true, message });
  } catch (err) {
    console.error('Error adding message:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/product-questions/client/:phone - Get all questions/dialogs for a client
app.get('/api/product-questions/client/:phone', async (req, res) => {
  try {
    const { phone } = req.params;
    const normalizedPhone = phone.replace(/[\s+]/g, '');
    console.log('GET /api/product-questions/client/:phone', normalizedPhone);

    if (!fs.existsSync(PRODUCT_QUESTIONS_DIR)) {
      return res.json({ success: true, dialogs: [], messages: [], hasQuestions: false });
    }

    const files = fs.readdirSync(PRODUCT_QUESTIONS_DIR).filter(f => f.endsWith('.json'));
    let allMessages = [];
    let hasQuestions = false;
    let unreadCount = 0;

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(PRODUCT_QUESTIONS_DIR, file), 'utf8');
        const question = JSON.parse(content);

        // Check if this question belongs to this client
        if (question.clientPhone.replace(/[\s+]/g, '') === normalizedPhone) {
          hasQuestions = true;

          // Add all messages with question context
          for (const msg of question.messages) {
            allMessages.push({
              id: msg.id,
              senderType: msg.senderType,
              senderPhone: msg.senderPhone,
              senderName: msg.senderName,
              shopAddress: msg.shopAddress,
              text: msg.text,
              imageUrl: msg.imageUrl,
              timestamp: msg.timestamp,
              questionId: question.id,
              originalShopAddress: question.originalShopAddress,
              isNetworkWide: question.isNetworkWide
            });

            // Count unread (employee messages not read by client)
            if (msg.senderType === 'employee' && !msg.readByClient) {
              unreadCount++;
            }
          }
        }
      } catch (e) {
        console.error('Error parsing question file:', file, e.message);
      }
    }

    // Sort messages by timestamp
    allMessages.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));

    // Get last message for preview
    const lastMessage = allMessages.length > 0 ? allMessages[allMessages.length - 1] : null;

    console.log('Loaded ' + allMessages.length + ' messages for client ' + normalizedPhone);
    res.json({
      success: true,
      hasQuestions,
      messages: allMessages,
      unreadCount,
      lastMessage: lastMessage ? {
        text: lastMessage.text,
        timestamp: lastMessage.timestamp,
        shopAddress: lastMessage.shopAddress,
        senderName: lastMessage.senderName,
        senderType: lastMessage.senderType
      } : null
    });
  } catch (err) {
    console.error('Error loading client questions:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /api/product-questions/client/:phone/reply - Client sends a follow-up message
app.post('/api/product-questions/client/:phone/reply', async (req, res) => {
  try {
    const { phone } = req.params;
    const { text, imageUrl, questionId } = req.body;
    const normalizedPhone = phone.replace(/[\s+]/g, '');
    console.log('POST /api/product-questions/client/:phone/reply', { normalizedPhone, questionId });

    if (!text) {
      return res.status(400).json({ success: false, error: 'Text is required' });
    }

    // If questionId provided, add to that question; otherwise find the latest
    let targetQuestionId = questionId;

    if (!targetQuestionId) {
      // Find latest question from this client
      const files = fs.readdirSync(PRODUCT_QUESTIONS_DIR).filter(f => f.endsWith('.json'));
      let latestQuestion = null;
      let latestTime = null;

      for (const file of files) {
        try {
          const content = fs.readFileSync(path.join(PRODUCT_QUESTIONS_DIR, file), 'utf8');
          const question = JSON.parse(content);
          if (question.clientPhone.replace(/[\s+]/g, '') === normalizedPhone) {
            const qTime = new Date(question.timestamp);
            if (!latestTime || qTime > latestTime) {
              latestTime = qTime;
              latestQuestion = question;
            }
          }
        } catch (e) {}
      }

      if (latestQuestion) {
        targetQuestionId = latestQuestion.id;
      }
    }

    if (!targetQuestionId) {
      return res.status(404).json({ success: false, error: 'No question found' });
    }

    const filePath = path.join(PRODUCT_QUESTIONS_DIR, targetQuestionId + '.json');
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, error: 'Question not found' });
    }

    const content = fs.readFileSync(filePath, 'utf8');
    const question = JSON.parse(content);

    const timestamp = new Date().toISOString();
    const message = {
      id: 'msg_' + Date.now(),
      senderType: 'client',
      senderPhone: normalizedPhone,
      senderName: question.clientName,
      shopAddress: null,
      text,
      imageUrl: imageUrl || null,
      timestamp
    };

    question.messages.push(message);
    fs.writeFileSync(filePath, JSON.stringify(question, null, 2), 'utf8');

    console.log('Client reply added to question ' + targetQuestionId);
    res.json({ success: true, message });
  } catch (err) {
    console.error('Error adding client reply:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ========== Personal Product Question Dialogs API ==========
const PRODUCT_QUESTION_DIALOGS_DIR = '/var/www/product-question-dialogs';

// Ensure directory exists
if (!fs.existsSync(PRODUCT_QUESTION_DIALOGS_DIR)) {
  fs.mkdirSync(PRODUCT_QUESTION_DIALOGS_DIR, { recursive: true });
}

// Helper: Generate dialog ID
function generateDialogId() {
  return 'dialog_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
}

// POST /api/product-question-dialogs - Create a new personal dialog
app.post('/api/product-question-dialogs', async (req, res) => {
  try {
    const { clientPhone, clientName, shopAddress, originalQuestionId, initialMessage, imageUrl } = req.body;
    console.log('POST /api/product-question-dialogs', { clientPhone, shopAddress, originalQuestionId });

    if (!clientPhone || !shopAddress) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }

    const dialogId = generateDialogId();
    const timestamp = new Date().toISOString();

    const dialog = {
      id: dialogId,
      clientPhone,
      clientName: clientName || 'Клиент',
      shopAddress,
      originalQuestionId: originalQuestionId || null,
      createdAt: timestamp,
      hasUnreadFromClient: false,
      hasUnreadFromEmployee: false,
      lastMessageTime: timestamp,
      messages: []
    };

    // Add initial message if provided
    if (initialMessage) {
      dialog.messages.push({
        id: 'msg_' + Date.now(),
        senderType: 'client',
        senderPhone: clientPhone,
        senderName: clientName || 'Клиент',
        text: initialMessage,
        imageUrl: imageUrl || null,
        timestamp
      });
      dialog.hasUnreadFromClient = true;
    }

    // Save dialog
    const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, dialogId + '.json');
    fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');

    console.log('Personal dialog created: ' + dialogId);
    res.json({ success: true, dialogId, dialog });
  } catch (err) {
    console.error('Error creating personal dialog:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/product-question-dialogs/client/:phone - Get all dialogs for a client
app.get('/api/product-question-dialogs/client/:phone', async (req, res) => {
  try {
    const { phone } = req.params;
    const normalizedPhone = phone.replace(/[\s+]/g, '');
    console.log('GET /api/product-question-dialogs/client/:phone', normalizedPhone);

    if (!fs.existsSync(PRODUCT_QUESTION_DIALOGS_DIR)) {
      return res.json({ success: true, dialogs: [] });
    }

    const files = fs.readdirSync(PRODUCT_QUESTION_DIALOGS_DIR).filter(f => f.endsWith('.json'));
    let dialogs = [];

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(PRODUCT_QUESTION_DIALOGS_DIR, file), 'utf8');
        const dialog = JSON.parse(content);

        if (dialog.clientPhone.replace(/[\s+]/g, '') === normalizedPhone) {
          const lastMsg = dialog.messages.length > 0 ? dialog.messages[dialog.messages.length - 1] : null;
          dialogs.push({
            id: dialog.id,
            shopAddress: dialog.shopAddress,
            createdAt: dialog.createdAt,
            lastMessageTime: dialog.lastMessageTime,
            hasUnreadFromEmployee: dialog.hasUnreadFromEmployee || false,
            lastMessage: lastMsg ? {
              text: lastMsg.text,
              timestamp: lastMsg.timestamp,
              senderType: lastMsg.senderType
            } : null
          });
        }
      } catch (e) {
        console.error('Error parsing dialog file:', file, e.message);
      }
    }

    // Sort by last message time (newest first)
    dialogs.sort((a, b) => new Date(b.lastMessageTime) - new Date(a.lastMessageTime));

    console.log('Loaded ' + dialogs.length + ' dialogs for client ' + normalizedPhone);
    res.json({ success: true, dialogs });
  } catch (err) {
    console.error('Error loading client dialogs:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/product-question-dialogs/shop/:shopAddress - Get all dialogs for a shop (for employees)
app.get('/api/product-question-dialogs/shop/:shopAddress', async (req, res) => {
  try {
    const { shopAddress } = req.params;
    const decodedAddress = decodeURIComponent(shopAddress);
    console.log('GET /api/product-question-dialogs/shop/:shopAddress', decodedAddress);

    if (!fs.existsSync(PRODUCT_QUESTION_DIALOGS_DIR)) {
      return res.json({ success: true, dialogs: [] });
    }

    const files = fs.readdirSync(PRODUCT_QUESTION_DIALOGS_DIR).filter(f => f.endsWith('.json'));
    let dialogs = [];

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(PRODUCT_QUESTION_DIALOGS_DIR, file), 'utf8');
        const dialog = JSON.parse(content);

        if (dialog.shopAddress === decodedAddress) {
          const lastMsg = dialog.messages.length > 0 ? dialog.messages[dialog.messages.length - 1] : null;
          dialogs.push({
            id: dialog.id,
            clientPhone: dialog.clientPhone,
            clientName: dialog.clientName,
            shopAddress: dialog.shopAddress,
            createdAt: dialog.createdAt,
            lastMessageTime: dialog.lastMessageTime,
            hasUnreadFromClient: dialog.hasUnreadFromClient || false,
            lastMessage: lastMsg ? {
              text: lastMsg.text,
              timestamp: lastMsg.timestamp,
              senderType: lastMsg.senderType
            } : null
          });
        }
      } catch (e) {
        console.error('Error parsing dialog file:', file, e.message);
      }
    }

    // Sort by last message time (newest first)
    dialogs.sort((a, b) => new Date(b.lastMessageTime) - new Date(a.lastMessageTime));

    console.log('Loaded ' + dialogs.length + ' dialogs for shop ' + decodedAddress);
    res.json({ success: true, dialogs });
  } catch (err) {
    console.error('Error loading shop dialogs:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/product-question-dialogs/all - Get all dialogs (for employees viewing all)
app.get('/api/product-question-dialogs/all', async (req, res) => {
  try {
    console.log('GET /api/product-question-dialogs/all');

    if (!fs.existsSync(PRODUCT_QUESTION_DIALOGS_DIR)) {
      return res.json({ success: true, dialogs: [] });
    }

    const files = fs.readdirSync(PRODUCT_QUESTION_DIALOGS_DIR).filter(f => f.endsWith('.json'));
    let dialogs = [];

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(PRODUCT_QUESTION_DIALOGS_DIR, file), 'utf8');
        const dialog = JSON.parse(content);

        const lastMsg = dialog.messages.length > 0 ? dialog.messages[dialog.messages.length - 1] : null;
        dialogs.push({
          id: dialog.id,
          clientPhone: dialog.clientPhone,
          clientName: dialog.clientName,
          shopAddress: dialog.shopAddress,
          createdAt: dialog.createdAt,
          lastMessageTime: dialog.lastMessageTime,
          hasUnreadFromClient: dialog.hasUnreadFromClient || false,
          lastMessage: lastMsg ? {
            text: lastMsg.text,
            timestamp: lastMsg.timestamp,
            senderType: lastMsg.senderType
          } : null
        });
      } catch (e) {
        console.error('Error parsing dialog file:', file, e.message);
      }
    }

    // Sort by last message time (newest first)
    dialogs.sort((a, b) => new Date(b.lastMessageTime) - new Date(a.lastMessageTime));

    console.log('Loaded ' + dialogs.length + ' total dialogs');
    res.json({ success: true, dialogs });
  } catch (err) {
    console.error('Error loading all dialogs:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/product-question-dialogs/:id - Get a single dialog
app.get('/api/product-question-dialogs/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('GET /api/product-question-dialogs/:id', id);

    const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, id + '.json');
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, error: 'Dialog not found' });
    }

    const content = fs.readFileSync(filePath, 'utf8');
    const dialog = JSON.parse(content);

    res.json({ success: true, dialog });
  } catch (err) {
    console.error('Error loading dialog:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /api/product-question-dialogs/:id/messages - Send message in dialog
app.post('/api/product-question-dialogs/:id/messages', async (req, res) => {
  try {
    const { id } = req.params;
    const { senderType, senderPhone, senderName, text, imageUrl } = req.body;
    console.log('POST /api/product-question-dialogs/:id/messages', { id, senderType, senderName });

    if (!text || !senderType) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }

    const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, id + '.json');
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, error: 'Dialog not found' });
    }

    const content = fs.readFileSync(filePath, 'utf8');
    const dialog = JSON.parse(content);

    const timestamp = new Date().toISOString();
    const message = {
      id: 'msg_' + Date.now(),
      senderType,
      senderPhone: senderPhone || null,
      senderName: senderName || (senderType === 'client' ? 'Клиент' : 'Сотрудник'),
      text,
      imageUrl: imageUrl || null,
      timestamp
    };

    dialog.messages.push(message);
    dialog.lastMessageTime = timestamp;

    // Update unread flags
    if (senderType === 'client') {
      dialog.hasUnreadFromClient = true;
      dialog.hasUnreadFromEmployee = false;
    } else {
      dialog.hasUnreadFromEmployee = true;
      dialog.hasUnreadFromClient = false;
    }

    fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');

    console.log('Message added to dialog ' + id);
    res.json({ success: true, message });
  } catch (err) {
    console.error('Error adding message to dialog:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /api/product-question-dialogs/:id/mark-read - Mark as read
app.post('/api/product-question-dialogs/:id/mark-read', async (req, res) => {
  try {
    const { id } = req.params;
    const { readerType } = req.body; // 'client' or 'employee'
    console.log('POST /api/product-question-dialogs/:id/mark-read', { id, readerType });

    const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, id + '.json');
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, error: 'Dialog not found' });
    }

    const content = fs.readFileSync(filePath, 'utf8');
    const dialog = JSON.parse(content);

    if (readerType === 'client') {
      dialog.hasUnreadFromEmployee = false;
    } else if (readerType === 'employee') {
      dialog.hasUnreadFromClient = false;
    }

    fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');

    console.log('Dialog ' + id + ' marked as read by ' + readerType);
    res.json({ success: true });
  } catch (err) {
    console.error('Error marking dialog as read:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /api/product-questions/upload-photo - Upload photo for question
app.post('/api/product-questions/upload-photo', upload.single('photo'), async (req, res) => {
  try {
    console.log('POST /api/product-questions/upload-photo');

    if (!req.file) {
      return res.status(400).json({ success: false, error: 'No photo uploaded' });
    }

    const filename = 'pq_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9) + '.jpg';
    const destPath = path.join(PRODUCT_QUESTIONS_PHOTOS_DIR, filename);

    fs.renameSync(req.file.path, destPath);

    const photoUrl = 'https://arabica26.ru/product-question-photos/' + filename;

    console.log('Photo uploaded: ' + photoUrl);
    res.json({ success: true, photoUrl });
  } catch (err) {
    console.error('Error uploading photo:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

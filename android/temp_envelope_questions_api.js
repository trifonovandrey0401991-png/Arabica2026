
// =========== ENVELOPE QUESTIONS (ВОПРОСЫ ФОРМИРОВАНИЯ КОНВЕРТА) ===========
const ENVELOPE_QUESTIONS_DIR = '/var/www/envelope-questions';

// Инициализация директории
if (!fs.existsSync(ENVELOPE_QUESTIONS_DIR)) {
  fs.mkdirSync(ENVELOPE_QUESTIONS_DIR, { recursive: true });
}

// Дефолтные вопросы
const defaultEnvelopeQuestions = [
  { id: 'envelope_q_1', title: 'Выбор смены', description: 'Выберите тип смены', type: 'shift_select', section: 'general', order: 1, isRequired: true, isActive: true },
  { id: 'envelope_q_2', title: 'ООО: Z-отчет', description: 'Сфотографируйте Z-отчет ООО', type: 'photo', section: 'ooo', order: 2, isRequired: true, isActive: true },
  { id: 'envelope_q_3', title: 'ООО: Выручка и наличные', description: 'Введите данные ООО', type: 'numbers', section: 'ooo', order: 3, isRequired: true, isActive: true },
  { id: 'envelope_q_4', title: 'ООО: Фото конверта', description: 'Сфотографируйте сформированный конверт ООО', type: 'photo', section: 'ooo', order: 4, isRequired: true, isActive: true },
  { id: 'envelope_q_5', title: 'ИП: Z-отчет', description: 'Сфотографируйте Z-отчет ИП', type: 'photo', section: 'ip', order: 5, isRequired: true, isActive: true },
  { id: 'envelope_q_6', title: 'ИП: Выручка и наличные', description: 'Введите данные ИП', type: 'numbers', section: 'ip', order: 6, isRequired: true, isActive: true },
  { id: 'envelope_q_7', title: 'ИП: Расходы', description: 'Добавьте расходы', type: 'expenses', section: 'ip', order: 7, isRequired: true, isActive: true },
  { id: 'envelope_q_8', title: 'ИП: Фото конверта', description: 'Сфотографируйте сформированный конверт ИП', type: 'photo', section: 'ip', order: 8, isRequired: true, isActive: true },
  { id: 'envelope_q_9', title: 'Итог', description: 'Проверьте данные и отправьте отчет', type: 'summary', section: 'general', order: 9, isRequired: true, isActive: true },
];

// Инициализация дефолтных вопросов если директория пустая
function initEnvelopeQuestions() {
  const files = fs.readdirSync(ENVELOPE_QUESTIONS_DIR);
  if (files.filter(f => f.endsWith('.json')).length === 0) {
    console.log('📝 Инициализация дефолтных вопросов конверта...');
    for (const q of defaultEnvelopeQuestions) {
      fs.writeFileSync(path.join(ENVELOPE_QUESTIONS_DIR, q.id + '.json'), JSON.stringify(q, null, 2));
    }
    console.log('✅ Дефолтные вопросы конверта созданы');
  }
}

initEnvelopeQuestions();

// GET /api/envelope-questions - получить все вопросы
app.get('/api/envelope-questions', async (req, res) => {
  try {
    console.log('GET /api/envelope-questions');
    const files = fs.readdirSync(ENVELOPE_QUESTIONS_DIR);
    const questions = [];

    for (const file of files) {
      if (file.endsWith('.json')) {
        const data = JSON.parse(fs.readFileSync(path.join(ENVELOPE_QUESTIONS_DIR, file), 'utf8'));
        questions.push(data);
      }
    }

    // Сортировка по order
    questions.sort((a, b) => (a.order || 0) - (b.order || 0));

    res.json({ success: true, questions });
  } catch (error) {
    console.error('Error getting envelope questions:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/envelope-questions/:id - получить один вопрос
app.get('/api/envelope-questions/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('GET /api/envelope-questions/:id', id);

    const filePath = path.join(ENVELOPE_QUESTIONS_DIR, id + '.json');

    if (fs.existsSync(filePath)) {
      const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      res.json({ success: true, question: data });
    } else {
      res.json({ success: false, error: 'Question not found' });
    }
  } catch (error) {
    console.error('Error getting envelope question:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/envelope-questions - создать вопрос
app.post('/api/envelope-questions', async (req, res) => {
  try {
    const question = req.body;
    console.log('POST /api/envelope-questions', question.id);

    if (!question.id) {
      question.id = 'envelope_q_' + Date.now();
    }

    const filePath = path.join(ENVELOPE_QUESTIONS_DIR, question.id + '.json');
    fs.writeFileSync(filePath, JSON.stringify(question, null, 2));

    res.json({ success: true, question });
  } catch (error) {
    console.error('Error creating envelope question:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/envelope-questions/:id - обновить вопрос
app.put('/api/envelope-questions/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const updateData = req.body;
    console.log('PUT /api/envelope-questions/:id', id);

    const filePath = path.join(ENVELOPE_QUESTIONS_DIR, id + '.json');

    if (!fs.existsSync(filePath)) {
      return res.json({ success: false, error: 'Question not found' });
    }

    const existing = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const updated = { ...existing, ...updateData, id: id };
    fs.writeFileSync(filePath, JSON.stringify(updated, null, 2));

    res.json({ success: true, question: updated });
  } catch (error) {
    console.error('Error updating envelope question:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/envelope-questions/:id - удалить вопрос
app.delete('/api/envelope-questions/:id', async (req, res) => {
  try {
    const { id } = req.params;
    console.log('DELETE /api/envelope-questions/:id', id);

    const filePath = path.join(ENVELOPE_QUESTIONS_DIR, id + '.json');

    if (!fs.existsSync(filePath)) {
      return res.json({ success: false, error: 'Question not found' });
    }

    fs.unlinkSync(filePath);
    res.json({ success: true });
  } catch (error) {
    console.error('Error deleting envelope question:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

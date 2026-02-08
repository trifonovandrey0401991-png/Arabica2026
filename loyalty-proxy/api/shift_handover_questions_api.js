/**
 * Shift Handover Questions API
 * Вопросы сдачи смены
 *
 * EXTRACTED from index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SHIFT_HANDOVER_QUESTIONS_DIR = `${DATA_DIR}/shift-handover-questions`;

// Создаем директорию, если её нет
(async () => {
  if (!await fileExists(SHIFT_HANDOVER_QUESTIONS_DIR)) {
    await fsp.mkdir(SHIFT_HANDOVER_QUESTIONS_DIR, { recursive: true });
  }
})();

function setupShiftHandoverQuestionsAPI(app, { uploadShiftHandoverPhoto } = {}) {
  // Получить все вопросы
  app.get('/api/shift-handover-questions', async (req, res) => {
    try {
      console.log('GET /api/shift-handover-questions:', req.query);

      const files = await fsp.readdir(SHIFT_HANDOVER_QUESTIONS_DIR);
      const questions = [];

      for (const file of files) {
        if (file.endsWith('.json')) {
          const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, file);
          const data = await fsp.readFile(filePath, 'utf8');
          const question = JSON.parse(data);

          // Фильтр по магазину, если указан
          if (req.query.shopAddress) {
            // Вопрос показывается если:
            // 1. У него shops == null (для всех магазинов)
            // 2. Или shops содержит указанный магазин
            if (!question.shops || question.shops.length === 0 || question.shops.includes(req.query.shopAddress)) {
              questions.push(question);
            }
          } else {
            questions.push(question);
          }
        }
      }

      // Сортировка по дате создания (новые в начале)
      questions.sort((a, b) => {
        const dateA = new Date(a.createdAt || 0);
        const dateB = new Date(b.createdAt || 0);
        return dateB - dateA;
      });

      res.json({
        success: true,
        questions: questions
      });
    } catch (error) {
      console.error('Ошибка получения вопросов сдачи смены:', error);
      res.status(500).json({
        success: false,
        error: error.message,
        questions: []
      });
    }
  });

  // Получить один вопрос по ID
  app.get('/api/shift-handover-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({
          success: false,
          error: 'Вопрос не найден'
        });
      }

      const data = await fsp.readFile(filePath, 'utf8');
      const question = JSON.parse(data);

      res.json({
        success: true,
        question: question
      });
    } catch (error) {
      console.error('Ошибка получения вопроса сдачи смены:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // Создать новый вопрос
  app.post('/api/shift-handover-questions', async (req, res) => {
    try {
      console.log('POST /api/shift-handover-questions:', JSON.stringify(req.body).substring(0, 200));

      const questionId = req.body.id || `shift_handover_question_${Date.now()}`;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

      const question = {
        id: questionId,
        question: req.body.question,
        answerFormatB: req.body.answerFormatB || null,
        answerFormatC: req.body.answerFormatC || null,
        shops: req.body.shops || [],
        referencePhotos: req.body.referencePhotos || {},
        targetRole: req.body.targetRole || null,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };

      await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
      console.log('Вопрос сдачи смены создан:', filePath);

      res.json({
        success: true,
        question: question
      });
    } catch (error) {
      console.error('Ошибка создания вопроса сдачи смены:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // Обновить вопрос
  app.put('/api/shift-handover-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({
          success: false,
          error: 'Вопрос не найден'
        });
      }

      const existingData = await fsp.readFile(filePath, 'utf8');
      const question = JSON.parse(existingData);

      // Обновляем только переданные поля
      if (req.body.question !== undefined) question.question = req.body.question;
      if (req.body.answerFormatB !== undefined) question.answerFormatB = req.body.answerFormatB;
      if (req.body.answerFormatC !== undefined) question.answerFormatC = req.body.answerFormatC;
      if (req.body.shops !== undefined) question.shops = req.body.shops;
      if (req.body.referencePhotos !== undefined) question.referencePhotos = req.body.referencePhotos;
      if (req.body.targetRole !== undefined) question.targetRole = req.body.targetRole;
      question.updatedAt = new Date().toISOString();

      await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
      console.log('Вопрос сдачи смены обновлен:', filePath);

      res.json({
        success: true,
        question: question
      });
    } catch (error) {
      console.error('Ошибка обновления вопроса сдачи смены:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // Загрузить эталонное фото для вопроса
  if (uploadShiftHandoverPhoto) {
    app.post('/api/shift-handover-questions/:questionId/reference-photo', uploadShiftHandoverPhoto.single('photo'), async (req, res) => {
      try {
        const { questionId } = req.params;
        const { shopAddress } = req.body;

        if (!req.file) {
          return res.status(400).json({
            success: false,
            error: 'Файл не загружен'
          });
        }

        if (!shopAddress) {
          return res.status(400).json({
            success: false,
            error: 'Не указан адрес магазина'
          });
        }

        const photoUrl = `https://arabica26.ru/shift-handover-question-photos/${req.file.filename}`;
        console.log('Эталонное фото загружено:', req.file.filename, 'для магазина:', shopAddress);

        // Обновляем вопрос, добавляя URL эталонного фото
        const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
        const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

        if (await fileExists(filePath)) {
          const existingData = await fsp.readFile(filePath, 'utf8');
          const question = JSON.parse(existingData);

          // Добавляем или обновляем эталонное фото для данного магазина
          if (!question.referencePhotos) {
            question.referencePhotos = {};
          }
          question.referencePhotos[shopAddress] = photoUrl;
          question.updatedAt = new Date().toISOString();

          await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
          console.log('Эталонное фото добавлено в вопрос:', questionId);
        }

        res.json({
          success: true,
          photoUrl: photoUrl,
          shopAddress: shopAddress
        });
      } catch (error) {
        console.error('Ошибка загрузки эталонного фото:', error);
        res.status(500).json({
          success: false,
          error: error.message
        });
      }
    });
  }

  // Удалить вопрос
  app.delete('/api/shift-handover-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({
          success: false,
          error: 'Вопрос не найден'
        });
      }

      await fsp.unlink(filePath);
      console.log('Вопрос сдачи смены удален:', filePath);

      res.json({
        success: true,
        message: 'Вопрос успешно удален'
      });
    } catch (error) {
      console.error('Ошибка удаления вопроса сдачи смены:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  console.log('✅ Shift Handover Questions API initialized');
}

module.exports = { setupShiftHandoverQuestionsAPI };

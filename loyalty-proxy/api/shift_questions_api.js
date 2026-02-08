/**
 * Shift Questions API
 * Вопросы пересменки
 *
 * EXTRACTED from index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SHIFT_QUESTIONS_DIR = `${DATA_DIR}/shift-questions`;

// Создаем директорию, если её нет
(async () => {
  if (!await fileExists(SHIFT_QUESTIONS_DIR)) {
    await fsp.mkdir(SHIFT_QUESTIONS_DIR, { recursive: true });
  }
})();

function setupShiftQuestionsAPI(app, { upload } = {}) {
  // Получить все вопросы
  app.get('/api/shift-questions', async (req, res) => {
    try {
      console.log('GET /api/shift-questions:', req.query);

      const files = await fsp.readdir(SHIFT_QUESTIONS_DIR);
      const questions = [];

      for (const file of files) {
        if (file.endsWith('.json')) {
          try {
            const filePath = path.join(SHIFT_QUESTIONS_DIR, file);
            const data = await fsp.readFile(filePath, 'utf8');
            const question = JSON.parse(data);
            questions.push(question);
          } catch (error) {
            console.error(`Ошибка чтения вопроса ${file}:`, error);
          }
        }
      }

      // Фильтр по магазину (если указан)
      let filteredQuestions = questions;
      if (req.query.shopAddress) {
        filteredQuestions = questions.filter(q => {
          // Если shops === null, вопрос для всех магазинов
          if (!q.shops || q.shops.length === 0) return true;
          // Иначе проверяем, есть ли магазин в списке
          return q.shops.includes(req.query.shopAddress);
        });
      }

      res.json({
        success: true,
        questions: filteredQuestions
      });
    } catch (error) {
      console.error('Ошибка получения вопросов:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // Получить один вопрос по ID
  app.get('/api/shift-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

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
        question
      });
    } catch (error) {
      console.error('Ошибка получения вопроса:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // Создать новый вопрос
  app.post('/api/shift-questions', async (req, res) => {
    try {
      console.log('POST /api/shift-questions:', JSON.stringify(req.body).substring(0, 200));

      const questionId = req.body.id || `shift_question_${Date.now()}`;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

      const questionData = {
        id: questionId,
        question: req.body.question,
        answerFormatB: req.body.answerFormatB || null,
        answerFormatC: req.body.answerFormatC || null,
        shops: req.body.shops || null,
        referencePhotos: req.body.referencePhotos || {},
        isAiCheck: req.body.isAiCheck || false,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };

      await fsp.writeFile(filePath, JSON.stringify(questionData, null, 2), 'utf8');
      console.log('Вопрос сохранен:', filePath);

      res.json({
        success: true,
        message: 'Вопрос успешно создан',
        question: questionData
      });
    } catch (error) {
      console.error('Ошибка создания вопроса:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // Обновить вопрос
  app.put('/api/shift-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({
          success: false,
          error: 'Вопрос не найден'
        });
      }

      // Читаем существующий вопрос
      const existingData = await fsp.readFile(filePath, 'utf8');
      const existingQuestion = JSON.parse(existingData);

      // Обновляем только переданные поля
      const updatedQuestion = {
        ...existingQuestion,
        ...(req.body.question !== undefined && { question: req.body.question }),
        ...(req.body.answerFormatB !== undefined && { answerFormatB: req.body.answerFormatB }),
        ...(req.body.answerFormatC !== undefined && { answerFormatC: req.body.answerFormatC }),
        ...(req.body.shops !== undefined && { shops: req.body.shops }),
        ...(req.body.referencePhotos !== undefined && { referencePhotos: req.body.referencePhotos }),
        ...(req.body.isAiCheck !== undefined && { isAiCheck: req.body.isAiCheck }),
        updatedAt: new Date().toISOString()
      };

      await fsp.writeFile(filePath, JSON.stringify(updatedQuestion, null, 2), 'utf8');
      console.log('Вопрос обновлен:', filePath);

      res.json({
        success: true,
        message: 'Вопрос успешно обновлен',
        question: updatedQuestion
      });
    } catch (error) {
      console.error('Ошибка обновления вопроса:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // Загрузить эталонное фото для вопроса
  if (upload) {
    app.post('/api/shift-questions/:questionId/reference-photo', upload.single('photo'), async (req, res) => {
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

        const photoUrl = `https://arabica26.ru/shift-photos/${req.file.filename}`;
        console.log('Эталонное фото загружено:', req.file.filename, 'для магазина:', shopAddress);

        // Обновляем вопрос, добавляя URL эталонного фото
        const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
        const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

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
  app.delete('/api/shift-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(SHIFT_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({
          success: false,
          error: 'Вопрос не найден'
        });
      }

      await fsp.unlink(filePath);
      console.log('Вопрос удален:', filePath);

      res.json({
        success: true,
        message: 'Вопрос успешно удален'
      });
    } catch (error) {
      console.error('Ошибка удаления вопроса:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  console.log('✅ Shift Questions API initialized');
}

module.exports = { setupShiftQuestionsAPI };

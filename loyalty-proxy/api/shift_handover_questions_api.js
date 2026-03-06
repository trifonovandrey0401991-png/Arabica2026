/**
 * Shift Handover Questions API
 * Вопросы сдачи смены
 *
 * Feature flag: USE_DB_SHIFT_HANDOVER_QUESTIONS=true -> PostgreSQL, false -> JSON files
 * EXTRACTED from index.js inline code (2026-02-08)
 * MIGRATED to PostgreSQL dual-write (2026-03-06)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, sanitizeId } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const { invalidateShiftHandoverQuestions } = require('../utils/data_cache');
const { compressUpload } = require('../utils/image_compress');
const { requireAuth } = require('../utils/session_middleware');
const { generateId } = require('../utils/id_generator');
const db = require('../utils/db');

const USE_DB = process.env.USE_DB_SHIFT_HANDOVER_QUESTIONS === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SHIFT_HANDOVER_QUESTIONS_DIR = `${DATA_DIR}/shift-handover-questions`;

// Ensure directory exists (async)
(async () => {
  if (!await fileExists(SHIFT_HANDOVER_QUESTIONS_DIR)) {
    await fsp.mkdir(SHIFT_HANDOVER_QUESTIONS_DIR, { recursive: true });
  }
})();

// Convert DB row (id + data JSONB) to question object
function dbRowToQuestion(row) {
  if (!row) return null;
  return { id: row.id, ...row.data };
}

function setupShiftHandoverQuestionsAPI(app, { uploadShiftHandoverPhoto } = {}) {
  // GET all questions
  app.get('/api/shift-handover-questions', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/shift-handover-questions:', req.query);

      let questions = [];

      if (USE_DB) {
        const rows = await db.findAll('shift_handover_questions', { orderBy: 'created_at', orderDir: 'DESC' });
        questions = rows.map(dbRowToQuestion);
      } else {
        const files = await fsp.readdir(SHIFT_HANDOVER_QUESTIONS_DIR);
        for (const file of files) {
          if (file.endsWith('.json')) {
            const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, file);
            const data = await fsp.readFile(filePath, 'utf8');
            questions.push(JSON.parse(data));
          }
        }
        // Sort by date (newest first) — DB already sorted via orderBy
        questions.sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
      }

      // Filter by shop if requested
      if (req.query.shopAddress) {
        questions = questions.filter(q =>
          !q.shops || q.shops.length === 0 || q.shops.includes(req.query.shopAddress)
        );
      }

      res.json({ success: true, questions });
    } catch (error) {
      console.error('Ошибка получения вопросов сдачи смены:', error);
      res.status(500).json({ success: false, error: error.message, questions: [] });
    }
  });

  // GET one question by ID
  app.get('/api/shift-handover-questions/:questionId', requireAuth, async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = sanitizeId(questionId);
      let question = null;

      if (USE_DB) {
        const row = await db.findById('shift_handover_questions', sanitizedId);
        question = dbRowToQuestion(row);
      } else {
        const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);
        if (await fileExists(filePath)) {
          question = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        }
      }

      if (!question) {
        return res.status(404).json({ success: false, error: 'Вопрос не найден' });
      }

      res.json({ success: true, question });
    } catch (error) {
      console.error('Ошибка получения вопроса сдачи смены:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST create question
  app.post('/api/shift-handover-questions', requireAuth, async (req, res) => {
    try {
      console.log('POST /api/shift-handover-questions:', JSON.stringify(req.body).substring(0, 200));

      const questionId = req.body.id || generateId('shift_handover_question');
      const sanitizedId = sanitizeId(questionId);

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

      // Dual-write: JSON first, then DB
      const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);
      await writeJsonFile(filePath, question);
      try { await db.upsert('shift_handover_questions', { id: questionId, data: question }); }
      catch (e) { console.error('[ShiftHandoverQuestions] DB write error:', e.message); }

      invalidateShiftHandoverQuestions();
      console.log('Вопрос сдачи смены создан:', questionId);

      res.json({ success: true, question });
    } catch (error) {
      console.error('Ошибка создания вопроса сдачи смены:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT update question
  app.put('/api/shift-handover-questions/:questionId', requireAuth, async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = sanitizeId(questionId);
      let question = null;

      if (USE_DB) {
        const row = await db.findById('shift_handover_questions', sanitizedId);
        question = dbRowToQuestion(row);
      } else {
        const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);
        if (await fileExists(filePath)) {
          question = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        }
      }

      if (!question) {
        return res.status(404).json({ success: false, error: 'Вопрос не найден' });
      }

      // Update only provided fields
      if (req.body.question !== undefined) question.question = req.body.question;
      if (req.body.answerFormatB !== undefined) question.answerFormatB = req.body.answerFormatB;
      if (req.body.answerFormatC !== undefined) question.answerFormatC = req.body.answerFormatC;
      if (req.body.shops !== undefined) question.shops = req.body.shops;
      if (req.body.referencePhotos !== undefined) question.referencePhotos = req.body.referencePhotos;
      if (req.body.targetRole !== undefined) question.targetRole = req.body.targetRole;
      question.updatedAt = new Date().toISOString();

      // Dual-write: JSON first, then DB
      const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);
      await writeJsonFile(filePath, question);
      try { await db.upsert('shift_handover_questions', { id: question.id, data: question }); }
      catch (e) { console.error('[ShiftHandoverQuestions] DB write error:', e.message); }

      invalidateShiftHandoverQuestions();
      console.log('Вопрос сдачи смены обновлен:', questionId);

      res.json({ success: true, question });
    } catch (error) {
      console.error('Ошибка обновления вопроса сдачи смены:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Upload reference photo
  if (uploadShiftHandoverPhoto) {
    app.post('/api/shift-handover-questions/:questionId/reference-photo', requireAuth, uploadShiftHandoverPhoto.single('photo'), compressUpload, async (req, res) => {
      try {
        const { questionId } = req.params;
        const { shopAddress } = req.body;

        if (!req.file) {
          return res.status(400).json({ success: false, error: 'Файл не загружен' });
        }

        if (!shopAddress) {
          return res.status(400).json({ success: false, error: 'Не указан адрес магазина' });
        }

        const photoUrl = `https://arabica26.ru/shift-handover-question-photos/${req.file.filename}`;
        console.log('Эталонное фото загружено:', req.file.filename, 'для магазина:', shopAddress);

        // Load question, update referencePhotos, dual-write
        const sanitizedId = sanitizeId(questionId);
        let question = null;

        if (USE_DB) {
          const row = await db.findById('shift_handover_questions', sanitizedId);
          question = dbRowToQuestion(row);
        } else {
          const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);
          if (await fileExists(filePath)) {
            question = JSON.parse(await fsp.readFile(filePath, 'utf8'));
          }
        }

        if (question) {
          if (!question.referencePhotos) question.referencePhotos = {};
          question.referencePhotos[shopAddress] = photoUrl;
          question.updatedAt = new Date().toISOString();

          // Dual-write
          const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);
          await writeJsonFile(filePath, question);
          try { await db.upsert('shift_handover_questions', { id: question.id, data: question }); }
          catch (e) { console.error('[ShiftHandoverQuestions] DB write error:', e.message); }

          invalidateShiftHandoverQuestions();
          console.log('Эталонное фото добавлено в вопрос:', questionId);
        }

        res.json({ success: true, photoUrl, shopAddress });
      } catch (error) {
        console.error('Ошибка загрузки эталонного фото:', error);
        res.status(500).json({ success: false, error: error.message });
      }
    });
  }

  // DELETE question
  app.delete('/api/shift-handover-questions/:questionId', requireAuth, async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = sanitizeId(questionId);

      // Check existence
      let exists = false;
      if (USE_DB) {
        const row = await db.findById('shift_handover_questions', sanitizedId);
        exists = !!row;
      } else {
        const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);
        exists = await fileExists(filePath);
      }

      if (!exists) {
        return res.status(404).json({ success: false, error: 'Вопрос не найден' });
      }

      // Delete from both
      const filePath = path.join(SHIFT_HANDOVER_QUESTIONS_DIR, `${sanitizedId}.json`);
      if (await fileExists(filePath)) {
        await fsp.unlink(filePath);
      }
      try { await db.deleteById('shift_handover_questions', sanitizedId); }
      catch (e) { console.error('[ShiftHandoverQuestions] DB delete error:', e.message); }

      invalidateShiftHandoverQuestions();
      console.log('Вопрос сдачи смены удален:', questionId);

      res.json({ success: true, message: 'Вопрос успешно удален' });
    } catch (error) {
      console.error('Ошибка удаления вопроса сдачи смены:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Shift Handover Questions API initialized (storage: ${USE_DB ? 'PostgreSQL' : 'JSON files'})`);
}

module.exports = { setupShiftHandoverQuestionsAPI };

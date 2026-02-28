/**
 * Tests API (Questions + Results + Point Assignment)
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { sanitizeId, isPathSafe, fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const { isPaginationRequested, createPaginatedResponse, createDbPaginatedResponse } = require('../utils/pagination');
const { dbInsertPenalty } = require('./efficiency_penalties_api');
const db = require('../utils/db');
const { requireAuth, requireAdmin } = require('../utils/session_middleware');
const { generateId } = require('../utils/id_generator');

const USE_DB = process.env.USE_DB_TESTS === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const TEST_QUESTIONS_DIR = `${DATA_DIR}/test-questions`;
const TEST_RESULTS_DIR = `${DATA_DIR}/test-results`;
const TEST_SETTINGS_FILE = `${DATA_DIR}/test-settings.json`;

// Ensure directories exist
(async () => {
  for (const dir of [TEST_QUESTIONS_DIR, TEST_RESULTS_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

/**
 * Начисление баллов за прохождение теста
 * Использует линейную интерполяцию для расчета баллов
 */
async function assignTestPoints(result) {
  try {
    const now = new Date(result.completedAt || Date.now());
    const today = now.toISOString().split('T')[0];
    const monthKey = today.substring(0, 7); // YYYY-MM

    // Загрузка настроек баллов
    const settingsFile = `${DATA_DIR}/points-settings/test_points_settings.json`;
    let settings = {
      maxPoints: 5,
      minPoints: -2,
      zeroThreshold: 12
    };

    if (await fileExists(settingsFile)) {
      try {
        const settingsData = await fsp.readFile(settingsFile, 'utf8');
        settings = JSON.parse(settingsData);
      } catch (e) {
        console.error('Error loading test settings:', e);
      }
    }

    // Расчет баллов через линейную интерполяцию
    const { score, totalQuestions } = result;
    let points = 0;

    if (totalQuestions === 0) {
      points = 0;
    } else if (score <= 0) {
      points = settings.minPoints;
    } else if (score >= totalQuestions) {
      points = settings.maxPoints;
    } else if (score <= settings.zeroThreshold) {
      // Интерполяция от minPoints до 0
      points = settings.minPoints + (0 - settings.minPoints) * (score / settings.zeroThreshold);
    } else {
      // Интерполяция от 0 до maxPoints
      const range = totalQuestions - settings.zeroThreshold;
      points = (settings.maxPoints - 0) * ((score - settings.zeroThreshold) / range);
    }

    // Округление до 2 знаков
    points = Math.round(points * 100) / 100;

    // Дедупликация
    const sourceId = `test_${result.id}`;
    const PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;
    if (!await fileExists(PENALTIES_DIR)) {
      await fsp.mkdir(PENALTIES_DIR, { recursive: true });
    }

    const penaltiesFile = path.join(PENALTIES_DIR, `${monthKey}.json`);
    let penalties = [];

    if (await fileExists(penaltiesFile)) {
      try {
        penalties = JSON.parse(await fsp.readFile(penaltiesFile, 'utf8'));
        if (!Array.isArray(penalties)) penalties = (penalties && penalties.penalties) || [];
      } catch (e) {
        console.error('Error reading penalties file:', e);
      }
    }

    const exists = penalties.some(p => p.sourceId === sourceId);
    if (exists) {
      console.log(`Points already assigned for test ${result.id}, skipping`);
      return { success: true, skipped: true };
    }

    // Создание записи
    const entry = {
      id: `test_pts_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type: 'employee',
      entityId: result.employeePhone,
      entityName: result.employeeName,
      shopAddress: result.shopAddress || '',
      employeeName: result.employeeName,
      category: points >= 0 ? 'test_bonus' : 'test_penalty',
      categoryName: 'Прохождение теста',
      date: today,
      points: points,
      reason: `Тест: ${score}/${totalQuestions} правильных (${Math.round((score/totalQuestions)*100)}%)`,
      sourceId: sourceId,
      sourceType: 'test_result',
      createdAt: now.toISOString()
    };

    penalties.push(entry);
    await writeJsonFile(penaltiesFile, penalties);
    // DB dual-write
    await dbInsertPenalty(entry);

    console.log(`✅ Test points assigned: ${result.employeeName} (${points >= 0 ? '+' : ''}${points} points)`);
    return { success: true, points: points };
  } catch (error) {
    console.error('Error assigning test points:', error);
    return { success: false, error: error.message };
  }
}

function setupTestsAPI(app) {
  // ===== TEST QUESTIONS =====

  app.get('/api/test-questions', requireAuth, async (req, res) => {
    try {
      if (USE_DB) {
        if (isPaginationRequested(req.query)) {
          const result = await db.findAllPaginated('test_questions', {
            orderBy: 'created_at', orderDir: 'ASC',
            page: parseInt(req.query.page) || 1,
            pageSize: Math.min(parseInt(req.query.limit) || 50, 200),
          });
          return res.json(createDbPaginatedResponse(result, 'questions', r => r.data));
        }
        const rows = await db.findAll('test_questions', { orderBy: 'created_at', orderDir: 'ASC' });
        const questions = rows.map(r => r.data);
        return res.json({ success: true, questions });
      }

      const questions = [];
      if (await fileExists(TEST_QUESTIONS_DIR)) {
        const files = (await fsp.readdir(TEST_QUESTIONS_DIR)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(TEST_QUESTIONS_DIR, file), 'utf8');
            const q = JSON.parse(content);
            // Migrate old answerA/B/C format to options array
            if (!q.options && (q.answerA || q.answerB || q.answerC)) {
              q.options = [q.answerA, q.answerB, q.answerC].filter(Boolean);
              delete q.answerA;
              delete q.answerB;
              delete q.answerC;
            }
            questions.push(q);
          } catch (e) {
            console.error(`Ошибка чтения ${file}:`, e);
          }
        }
      }
      if (isPaginationRequested(req.query)) {
        return res.json(createPaginatedResponse(questions, req.query, 'questions'));
      }
      res.json({ success: true, questions });
    } catch (error) {
      console.error('Ошибка получения вопросов тестирования:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/test-questions', requireAdmin, async (req, res) => {
    try {
      const question = {
        id: generateId('test_question'),
        question: req.body.question,
        options: req.body.options || [],
        correctAnswer: req.body.correctAnswer,
        createdAt: new Date().toISOString(),
      };
      const questionFile = path.join(TEST_QUESTIONS_DIR, `${question.id}.json`);
      await writeJsonFile(questionFile, question);

      if (USE_DB) {
        try { await db.upsert('test_questions', { id: question.id, data: question, created_at: question.createdAt }); }
        catch (dbErr) { console.error('DB save test_question error:', dbErr.message); }
      }

      res.json({ success: true, question });
    } catch (error) {
      console.error('Ошибка создания вопроса тестирования:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/test-questions/:id', requireAdmin, async (req, res) => {
    try {
      const safeId = sanitizeId(req.params.id);
      const questionFile = path.join(TEST_QUESTIONS_DIR, `${safeId}.json`);
      if (!isPathSafe(TEST_QUESTIONS_DIR, questionFile)) {
        return res.status(400).json({ success: false, error: 'Invalid question ID' });
      }
      if (!await fileExists(questionFile)) {
        return res.status(404).json({ success: false, error: 'Вопрос не найден' });
      }
      const question = JSON.parse(await fsp.readFile(questionFile, 'utf8'));
      if (req.body.question) question.question = req.body.question;
      if (req.body.options) question.options = req.body.options;
      if (req.body.correctAnswer) question.correctAnswer = req.body.correctAnswer;
      // Remove old answerA/B/C fields if migrating
      delete question.answerA;
      delete question.answerB;
      delete question.answerC;
      question.updatedAt = new Date().toISOString();
      await writeJsonFile(questionFile, question);

      if (USE_DB) {
        try { await db.upsert('test_questions', { id: question.id, data: question, updated_at: question.updatedAt }); }
        catch (dbErr) { console.error('DB update test_question error:', dbErr.message); }
      }

      res.json({ success: true, question });
    } catch (error) {
      console.error('Ошибка обновления вопроса тестирования:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/test-questions/:id', requireAdmin, async (req, res) => {
    try {
      const safeId = sanitizeId(req.params.id);
      const questionFile = path.join(TEST_QUESTIONS_DIR, `${safeId}.json`);
      if (!isPathSafe(TEST_QUESTIONS_DIR, questionFile)) {
        return res.status(400).json({ success: false, error: 'Invalid question ID' });
      }
      if (!await fileExists(questionFile)) {
        return res.status(404).json({ success: false, error: 'Вопрос не найден' });
      }
      await fsp.unlink(questionFile);

      if (USE_DB) {
        try { await db.deleteById('test_questions', safeId); }
        catch (dbErr) { console.error('DB delete test_question error:', dbErr.message); }
      }

      res.json({ success: true });
    } catch (error) {
      console.error('Ошибка удаления вопроса тестирования:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== TEST RESULTS =====

  app.get('/api/test-results', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/test-results');

      if (USE_DB) {
        const rows = await db.findAll('test_results', { orderBy: 'created_at', orderDir: 'DESC' });
        const results = rows.map(r => r.data);
        console.log(`✅ Найдено результатов тестов: ${results.length}`);
        if (isPaginationRequested(req.query)) {
          return res.json(createPaginatedResponse(results, req.query, 'results'));
        }
        return res.json({ success: true, results });
      }

      const results = [];
      if (await fileExists(TEST_RESULTS_DIR)) {
        const files = (await fsp.readdir(TEST_RESULTS_DIR)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(TEST_RESULTS_DIR, file), 'utf8');
            const result = JSON.parse(content);
            results.push(result);
          } catch (e) {
            console.error(`Ошибка чтения ${file}:`, e);
          }
        }
      }
      // Сортировка по дате (новые сначала)
      results.sort((a, b) => new Date(b.completedAt) - new Date(a.completedAt));
      console.log(`✅ Найдено результатов тестов: ${results.length}`);
      if (isPaginationRequested(req.query)) {
        return res.json(createPaginatedResponse(results, req.query, 'results'));
      }
      res.json({ success: true, results });
    } catch (error) {
      console.error('Ошибка получения результатов тестов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/test-results', requireAuth, async (req, res) => {
    try {
      console.log('POST /api/test-results employee:', req.body?.employeeName, 'test:', req.body?.testId);
      const result = {
        id: req.body.id || generateId('test_result'),
        employeeName: req.body.employeeName,
        employeePhone: req.body.employeePhone,
        score: req.body.score,
        totalQuestions: req.body.totalQuestions,
        timeSpent: req.body.timeSpent,
        completedAt: req.body.completedAt || new Date().toISOString(),
        shopAddress: req.body.shopAddress,
      };

      const resultFile = path.join(TEST_RESULTS_DIR, `${result.id}.json`);
      await writeJsonFile(resultFile, result);

      if (USE_DB) {
        try { await db.upsert('test_results', { id: result.id, data: result, created_at: result.completedAt }); }
        catch (dbErr) { console.error('DB save test_result error:', dbErr.message); }
      }

      console.log(`✅ Результат теста сохранен: ${result.employeeName} - ${result.score}/${result.totalQuestions}`);

      // Начисление баллов за тест
      const pointsResult = await assignTestPoints(result);

      res.json({
        success: true,
        result,
        pointsAssigned: pointsResult.success,
        points: pointsResult.points
      });
    } catch (error) {
      console.error('Ошибка сохранения результата теста:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== TEST SETTINGS (duration etc.) =====

  app.get('/api/test-settings', requireAuth, async (req, res) => {
    try {
      let settings = { durationMinutes: 7, minimumScore: 0 };

      if (USE_DB) {
        const row = await db.findById('app_settings', 'test_settings', 'key');
        if (row) settings = row.data;
        return res.json({ success: true, settings });
      }

      if (await fileExists(TEST_SETTINGS_FILE)) {
        try {
          const data = await fsp.readFile(TEST_SETTINGS_FILE, 'utf8');
          settings = JSON.parse(data);
        } catch (e) {
          console.error('Error reading test settings:', e);
        }
      }
      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting test settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/test-settings', requireAdmin, async (req, res) => {
    try {
      const durationMinutes = parseInt(req.body.durationMinutes);
      if (!durationMinutes || durationMinutes < 1 || durationMinutes > 120) {
        return res.status(400).json({ success: false, error: 'durationMinutes must be between 1 and 120' });
      }

      // minimumScore: 0-20 (0 = проверка отключена)
      const rawMinScore = parseInt(req.body.minimumScore);
      const minimumScore = (!isNaN(rawMinScore) && rawMinScore >= 0 && rawMinScore <= 20)
        ? rawMinScore : 0;

      const settings = {
        durationMinutes,
        minimumScore,
        updatedAt: new Date().toISOString(),
      };
      await writeJsonFile(TEST_SETTINGS_FILE, settings);

      if (USE_DB) {
        try { await db.upsert('app_settings', { key: 'test_settings', data: settings, updated_at: settings.updatedAt }, 'key'); }
        catch (dbErr) { console.error('DB save test_settings error:', dbErr.message); }
      }

      console.log(`✅ Test settings updated: ${durationMinutes} min, minimumScore: ${minimumScore}`);
      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving test settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Tests API initialized ${USE_DB ? '(DB mode)' : '(file mode)'}`);
}

module.exports = { setupTestsAPI };

/**
 * Tests API (Questions + Results + Point Assignment)
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { sanitizeId, isPathSafe, fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const TEST_QUESTIONS_DIR = `${DATA_DIR}/test-questions`;
const TEST_RESULTS_DIR = `${DATA_DIR}/test-results`;

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
    await fsp.writeFile(penaltiesFile, JSON.stringify(penalties, null, 2), 'utf8');

    console.log(`✅ Test points assigned: ${result.employeeName} (${points >= 0 ? '+' : ''}${points} points)`);
    return { success: true, points: points };
  } catch (error) {
    console.error('Error assigning test points:', error);
    return { success: false, error: error.message };
  }
}

function setupTestsAPI(app) {
  // ===== TEST QUESTIONS =====

  app.get('/api/test-questions', async (req, res) => {
    try {
      const questions = [];
      if (await fileExists(TEST_QUESTIONS_DIR)) {
        const files = (await fsp.readdir(TEST_QUESTIONS_DIR)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(TEST_QUESTIONS_DIR, file), 'utf8');
            questions.push(JSON.parse(content));
          } catch (e) {
            console.error(`Ошибка чтения ${file}:`, e);
          }
        }
      }
      res.json({ success: true, questions });
    } catch (error) {
      console.error('Ошибка получения вопросов тестирования:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/test-questions', async (req, res) => {
    try {
      const question = {
        id: `test_question_${Date.now()}`,
        question: req.body.question,
        answerA: req.body.answerA,
        answerB: req.body.answerB,
        answerC: req.body.answerC,
        correctAnswer: req.body.correctAnswer,
        createdAt: new Date().toISOString(),
      };
      const questionFile = path.join(TEST_QUESTIONS_DIR, `${question.id}.json`);
      await fsp.writeFile(questionFile, JSON.stringify(question, null, 2), 'utf8');
      res.json({ success: true, question });
    } catch (error) {
      console.error('Ошибка создания вопроса тестирования:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/test-questions/:id', async (req, res) => {
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
      if (req.body.answerA) question.answerA = req.body.answerA;
      if (req.body.answerB) question.answerB = req.body.answerB;
      if (req.body.answerC) question.answerC = req.body.answerC;
      if (req.body.correctAnswer) question.correctAnswer = req.body.correctAnswer;
      question.updatedAt = new Date().toISOString();
      await fsp.writeFile(questionFile, JSON.stringify(question, null, 2), 'utf8');
      res.json({ success: true, question });
    } catch (error) {
      console.error('Ошибка обновления вопроса тестирования:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/test-questions/:id', async (req, res) => {
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
      res.json({ success: true });
    } catch (error) {
      console.error('Ошибка удаления вопроса тестирования:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== TEST RESULTS =====

  app.get('/api/test-results', async (req, res) => {
    try {
      console.log('GET /api/test-results');
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
      res.json({ success: true, results });
    } catch (error) {
      console.error('Ошибка получения результатов тестов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/test-results', async (req, res) => {
    try {
      console.log('POST /api/test-results', req.body);
      const result = {
        id: req.body.id || `test_result_${Date.now()}`,
        employeeName: req.body.employeeName,
        employeePhone: req.body.employeePhone,
        score: req.body.score,
        totalQuestions: req.body.totalQuestions,
        timeSpent: req.body.timeSpent,
        completedAt: req.body.completedAt || new Date().toISOString(),
        shopAddress: req.body.shopAddress,
      };

      const resultFile = path.join(TEST_RESULTS_DIR, `${result.id}.json`);
      await fsp.writeFile(resultFile, JSON.stringify(result, null, 2), 'utf8');

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

  console.log('✅ Tests API initialized');
}

module.exports = { setupTestsAPI };

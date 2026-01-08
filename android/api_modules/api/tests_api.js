const fs = require('fs');
const path = require('path');

const TEST_QUESTIONS_DIR = '/var/www/test-questions';
const TEST_RESULTS_DIR = '/var/www/test-results';

[TEST_QUESTIONS_DIR, TEST_RESULTS_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

function setupTestsAPI(app) {
  // ===== TEST QUESTIONS =====

  app.get('/api/test-questions', async (req, res) => {
    try {
      console.log('GET /api/test-questions');
      const questions = [];

      if (fs.existsSync(TEST_QUESTIONS_DIR)) {
        const files = fs.readdirSync(TEST_QUESTIONS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(TEST_QUESTIONS_DIR, file), 'utf8');
            questions.push(JSON.parse(content));
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      questions.sort((a, b) => (a.order || 0) - (b.order || 0));
      res.json({ success: true, questions });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/test-questions', async (req, res) => {
    try {
      const question = req.body;
      console.log('POST /api/test-questions:', question.text?.substring(0, 50));

      if (!question.id) {
        question.id = `testq_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      question.createdAt = question.createdAt || new Date().toISOString();
      question.updatedAt = new Date().toISOString();

      const filePath = path.join(TEST_QUESTIONS_DIR, `${question.id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(question, null, 2), 'utf8');

      res.json({ success: true, question });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/test-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      const updates = req.body;
      console.log('PUT /api/test-questions:', questionId);

      const filePath = path.join(TEST_QUESTIONS_DIR, `${questionId}.json`);

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

  app.delete('/api/test-questions/:questionId', async (req, res) => {
    try {
      const { questionId } = req.params;
      console.log('DELETE /api/test-questions:', questionId);

      const filePath = path.join(TEST_QUESTIONS_DIR, `${questionId}.json`);

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

  // ===== TEST RESULTS =====

  app.get('/api/test-results', async (req, res) => {
    try {
      console.log('GET /api/test-results');
      const { phone, shopAddress } = req.query;
      const results = [];

      if (fs.existsSync(TEST_RESULTS_DIR)) {
        const files = fs.readdirSync(TEST_RESULTS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(TEST_RESULTS_DIR, file), 'utf8');
            const result = JSON.parse(content);

            if (phone && result.phone !== phone) continue;
            if (shopAddress && result.shopAddress !== shopAddress) continue;

            results.push(result);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      results.sort((a, b) => new Date(b.completedAt) - new Date(a.completedAt));
      res.json({ success: true, results });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/test-results', async (req, res) => {
    try {
      const result = req.body;
      console.log('POST /api/test-results:', result.employeeName);

      if (!result.id) {
        result.id = `testres_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      result.completedAt = result.completedAt || new Date().toISOString();

      const filePath = path.join(TEST_RESULTS_DIR, `${result.id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(result, null, 2), 'utf8');

      res.json({ success: true, result });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/test-results/:resultId', async (req, res) => {
    try {
      const { resultId } = req.params;
      console.log('GET /api/test-results/:resultId', resultId);

      const filePath = path.join(TEST_RESULTS_DIR, `${resultId}.json`);

      if (fs.existsSync(filePath)) {
        const result = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        res.json({ success: true, result });
      } else {
        res.status(404).json({ success: false, error: 'Result not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Tests API initialized');
}

module.exports = { setupTestsAPI };

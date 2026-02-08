/**
 * Training API
 * Статьи обучения для сотрудников
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const TRAINING_ARTICLES_DIR = `${DATA_DIR}/training-articles`;

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Initialize directory on module load
(async () => {
  try {
    await fsp.mkdir(TRAINING_ARTICLES_DIR, { recursive: true });
  } catch (e) {
    console.error('Failed to create training-articles directory:', e);
  }
})();

function setupTrainingAPI(app) {
  // ===== TRAINING ARTICLES =====

  app.get('/api/training-articles', async (req, res) => {
    try {
      console.log('GET /api/training-articles');
      const articles = [];

      if (await fileExists(TRAINING_ARTICLES_DIR)) {
        const allFiles = await fsp.readdir(TRAINING_ARTICLES_DIR);
        const files = allFiles.filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(TRAINING_ARTICLES_DIR, file), 'utf8');
            articles.push(JSON.parse(content));
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      articles.sort((a, b) => (a.order || 0) - (b.order || 0));
      res.json({ success: true, articles });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/training-articles', async (req, res) => {
    try {
      const article = req.body;
      console.log('POST /api/training-articles:', article.title);

      if (!article.id) {
        article.id = `article_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      article.createdAt = article.createdAt || new Date().toISOString();
      article.updatedAt = new Date().toISOString();

      await fsp.mkdir(TRAINING_ARTICLES_DIR, { recursive: true });

      const filePath = path.join(TRAINING_ARTICLES_DIR, `${article.id}.json`);
      await fsp.writeFile(filePath, JSON.stringify(article, null, 2), 'utf8');

      res.json({ success: true, article });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/training-articles/:articleId', async (req, res) => {
    try {
      const { articleId } = req.params;
      const updates = req.body;
      console.log('PUT /api/training-articles:', articleId);

      const filePath = path.join(TRAINING_ARTICLES_DIR, `${articleId}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Article not found' });
      }

      const content = await fsp.readFile(filePath, 'utf8');
      const article = JSON.parse(content);
      const updated = { ...article, ...updates, updatedAt: new Date().toISOString() };

      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, article: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/training-articles/:articleId', async (req, res) => {
    try {
      const { articleId } = req.params;
      console.log('DELETE /api/training-articles:', articleId);

      const filePath = path.join(TRAINING_ARTICLES_DIR, `${articleId}.json`);

      if (await fileExists(filePath)) {
        await fsp.unlink(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Article not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Training API initialized');
}

module.exports = { setupTrainingAPI };

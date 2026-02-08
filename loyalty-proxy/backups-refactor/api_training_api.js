const fs = require('fs');
const path = require('path');

const TRAINING_ARTICLES_DIR = '/var/www/training-articles';

if (!fs.existsSync(TRAINING_ARTICLES_DIR)) {
  fs.mkdirSync(TRAINING_ARTICLES_DIR, { recursive: true });
}

function setupTrainingAPI(app) {
  // ===== TRAINING ARTICLES =====

  app.get('/api/training-articles', async (req, res) => {
    try {
      console.log('GET /api/training-articles');
      const articles = [];

      if (fs.existsSync(TRAINING_ARTICLES_DIR)) {
        const files = fs.readdirSync(TRAINING_ARTICLES_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(TRAINING_ARTICLES_DIR, file), 'utf8');
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

      const filePath = path.join(TRAINING_ARTICLES_DIR, `${article.id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(article, null, 2), 'utf8');

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

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Article not found' });
      }

      const article = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const updated = { ...article, ...updates, updatedAt: new Date().toISOString() };

      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
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

      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
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

const fs = require('fs');
const path = require('path');

const RECIPES_DIR = '/var/www/recipes';
const RECIPE_PHOTOS_DIR = '/var/www/recipe-photos';

[RECIPES_DIR, RECIPE_PHOTOS_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

function setupRecipesAPI(app, uploadRecipePhoto) {
  // ===== RECIPES =====

  app.get('/api/recipes', async (req, res) => {
    try {
      console.log('GET /api/recipes');
      const recipes = [];

      if (fs.existsSync(RECIPES_DIR)) {
        const files = fs.readdirSync(RECIPES_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(RECIPES_DIR, file), 'utf8');
            recipes.push(JSON.parse(content));
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      recipes.sort((a, b) => (a.order || 0) - (b.order || 0));
      res.json({ success: true, recipes });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/recipes', async (req, res) => {
    try {
      const recipe = req.body;
      console.log('POST /api/recipes:', recipe.name);

      if (!recipe.id) {
        recipe.id = `recipe_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      recipe.createdAt = recipe.createdAt || new Date().toISOString();
      recipe.updatedAt = new Date().toISOString();

      const filePath = path.join(RECIPES_DIR, `${recipe.id}.json`);
      fs.writeFileSync(filePath, JSON.stringify(recipe, null, 2), 'utf8');

      res.json({ success: true, recipe });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/recipes/:recipeId', async (req, res) => {
    try {
      const { recipeId } = req.params;
      const updates = req.body;
      console.log('PUT /api/recipes:', recipeId);

      const filePath = path.join(RECIPES_DIR, `${recipeId}.json`);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Recipe not found' });
      }

      const recipe = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const updated = { ...recipe, ...updates, updatedAt: new Date().toISOString() };

      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, recipe: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/recipes/:recipeId', async (req, res) => {
    try {
      const { recipeId } = req.params;
      console.log('DELETE /api/recipes:', recipeId);

      const filePath = path.join(RECIPES_DIR, `${recipeId}.json`);

      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Recipe not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== RECIPE PHOTOS =====

  if (uploadRecipePhoto) {
    app.post('/upload-recipe-photo', uploadRecipePhoto.single('photo'), async (req, res) => {
      try {
        console.log('POST /upload-recipe-photo');

        if (!req.file) {
          return res.status(400).json({ success: false, error: 'No file uploaded' });
        }

        const photoUrl = `/recipe-photos/${req.file.filename}`;
        res.json({ success: true, photoUrl });
      } catch (error) {
        res.status(500).json({ success: false, error: error.message });
      }
    });
  }

  console.log('✅ Recipes API initialized');
}

module.exports = { setupRecipesAPI };

/**
 * Recipes API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const RECIPES_DIR = `${DATA_DIR}/recipes`;
const RECIPE_PHOTOS_DIR = `${DATA_DIR}/recipe-photos`;

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Ensure directories exist at startup
(async () => {
  try {
    for (const dir of [RECIPES_DIR, RECIPE_PHOTOS_DIR]) {
      if (!(await fileExists(dir))) {
        await fsp.mkdir(dir, { recursive: true });
      }
    }
  } catch (e) {
    console.error('Error creating recipes directories:', e.message);
  }
})();

function setupRecipesAPI(app, uploadRecipePhoto) {
  // ===== RECIPES =====

  app.get('/api/recipes', async (req, res) => {
    try {
      console.log('GET /api/recipes');
      const recipes = [];

      if (await fileExists(RECIPES_DIR)) {
        const files = (await fsp.readdir(RECIPES_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(RECIPES_DIR, file), 'utf8');
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
      await fsp.writeFile(filePath, JSON.stringify(recipe, null, 2), 'utf8');

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

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Recipe not found' });
      }

      const content = await fsp.readFile(filePath, 'utf8');
      const recipe = JSON.parse(content);
      const updated = { ...recipe, ...updates, updatedAt: new Date().toISOString() };

      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2), 'utf8');
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

      if (await fileExists(filePath)) {
        await fsp.unlink(filePath);
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

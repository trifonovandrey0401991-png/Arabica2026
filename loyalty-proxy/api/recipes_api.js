/**
 * Recipes API
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { sanitizeId, isPathSafe, fileExists } = require('../utils/file_helpers');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const RECIPES_DIR = `${DATA_DIR}/recipes`;
const RECIPE_PHOTOS_DIR = `${DATA_DIR}/recipe-photos`;

// Ensure directories exist at startup
(async () => {
  try {
    if (!(await fileExists(RECIPES_DIR))) {
      await fsp.mkdir(RECIPES_DIR, { recursive: true });
    }
    if (!(await fileExists(RECIPE_PHOTOS_DIR))) {
      await fsp.mkdir(RECIPE_PHOTOS_DIR, { recursive: true });
    }
  } catch (e) {
    console.error('Error creating recipes directories:', e.message);
  }
})();

function setupRecipesAPI(app) {
  // GET /api/recipes - получить все рецепты
  app.get('/api/recipes', async (req, res) => {
    try {
      console.log('GET /api/recipes');
      const recipes = [];

      if (await fileExists(RECIPES_DIR)) {
        const files = (await fsp.readdir(RECIPES_DIR)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(RECIPES_DIR, file), 'utf8');
            const recipe = JSON.parse(content);
            recipes.push(recipe);
          } catch (e) {
            console.error(`Ошибка чтения ${file}:`, e);
          }
        }
      }

      console.log(`✅ Найдено рецептов: ${recipes.length}`);
      if (isPaginationRequested(req.query)) {
        res.json(createPaginatedResponse(recipes, req.query, 'recipes'));
      } else {
        res.json({ success: true, recipes });
      }
    } catch (error) {
      console.error('Ошибка получения рецептов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/recipes/:id - получить рецепт по ID
  app.get('/api/recipes/:id', async (req, res) => {
    try {
      const safeId = sanitizeId(req.params.id);
      const recipeFile = path.join(RECIPES_DIR, `${safeId}.json`);
      if (!isPathSafe(RECIPES_DIR, recipeFile)) {
        return res.status(400).json({ success: false, error: 'Invalid recipe ID' });
      }
      if (!await fileExists(recipeFile)) {
        return res.status(404).json({ success: false, error: 'Рецепт не найден' });
      }

      const recipe = JSON.parse(await fsp.readFile(recipeFile, 'utf8'));
      res.json({ success: true, recipe });
    } catch (error) {
      console.error('Ошибка получения рецепта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/recipes/photo/:recipeId - получить фото рецепта
  app.get('/api/recipes/photo/:recipeId', async (req, res) => {
    try {
      const safeRecipeId = sanitizeId(req.params.recipeId);
      const photoPath = path.join(RECIPE_PHOTOS_DIR, `${safeRecipeId}.jpg`);
      if (!isPathSafe(RECIPE_PHOTOS_DIR, photoPath)) {
        return res.status(400).json({ success: false, error: 'Invalid recipe ID' });
      }
      if (await fileExists(photoPath)) {
        res.sendFile(photoPath);
      } else {
        res.status(404).json({ success: false, error: 'Фото не найдено' });
      }
    } catch (error) {
      console.error('Ошибка получения фото рецепта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/recipes - создать новый рецепт
  app.post('/api/recipes', async (req, res) => {
    try {
      const { name, category, price, ingredients, steps } = req.body;
      console.log('POST /api/recipes:', name);

      if (!name || !category) {
        return res.status(400).json({ success: false, error: 'Название и категория обязательны' });
      }

      const id = `recipe_${Date.now()}`;
      const recipe = {
        id,
        name,
        category,
        price: price || '',
        ingredients: ingredients || '',
        steps: steps || '',
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };

      const recipeFile = path.join(RECIPES_DIR, `${id}.json`);
      await fsp.writeFile(recipeFile, JSON.stringify(recipe, null, 2), 'utf8');

      res.json({ success: true, recipe });
    } catch (error) {
      console.error('Ошибка создания рецепта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/recipes/:id - обновить рецепт
  app.put('/api/recipes/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const updates = req.body;
      console.log('PUT /api/recipes:', id);

      const recipeFile = path.join(RECIPES_DIR, `${id}.json`);

      if (!await fileExists(recipeFile)) {
        return res.status(404).json({ success: false, error: 'Рецепт не найден' });
      }

      const content = await fsp.readFile(recipeFile, 'utf8');
      const recipe = JSON.parse(content);

      // Обновляем поля
      if (updates.name) recipe.name = updates.name;
      if (updates.category) recipe.category = updates.category;
      if (updates.price !== undefined) recipe.price = updates.price;
      if (updates.ingredients !== undefined) recipe.ingredients = updates.ingredients;
      if (updates.steps !== undefined) recipe.steps = updates.steps;
      if (updates.photoUrl !== undefined) recipe.photoUrl = updates.photoUrl;
      recipe.updatedAt = new Date().toISOString();

      await fsp.writeFile(recipeFile, JSON.stringify(recipe, null, 2), 'utf8');

      res.json({ success: true, recipe });
    } catch (error) {
      console.error('Ошибка обновления рецепта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/recipes/:id - удалить рецепт
  app.delete('/api/recipes/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('DELETE /api/recipes:', id);

      const recipeFile = path.join(RECIPES_DIR, `${id}.json`);

      if (!await fileExists(recipeFile)) {
        return res.status(404).json({ success: false, error: 'Рецепт не найден' });
      }

      // Удаляем файл рецепта
      await fsp.unlink(recipeFile);

      // Удаляем фото рецепта, если есть
      const photoPath = path.join(RECIPE_PHOTOS_DIR, `${id}.jpg`);
      if (await fileExists(photoPath)) {
        await fsp.unlink(photoPath);
      }

      res.json({ success: true, message: 'Рецепт успешно удален' });
    } catch (error) {
      console.error('Ошибка удаления рецепта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Recipes API initialized');
}

module.exports = { setupRecipesAPI };

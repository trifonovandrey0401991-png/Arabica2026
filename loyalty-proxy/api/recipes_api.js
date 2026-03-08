/**
 * Recipes API
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const multer = require('multer');
const { sanitizeId, isPathSafe, fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const { isPaginationRequested, createPaginatedResponse, createDbPaginatedResponse } = require('../utils/pagination');
const db = require('../utils/db');
const { requireEmployee } = require('../utils/session_middleware');
const { compressUpload } = require('../utils/image_compress');
const { generateId } = require('../utils/id_generator');

const USE_DB = process.env.USE_DB_RECIPES === 'true';

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

// Настройка multer для загрузки фото рецептов
const recipePhotoStorage = multer.diskStorage({
  destination: async function (req, file, cb) {
    if (!await fileExists(RECIPE_PHOTOS_DIR)) {
      await fsp.mkdir(RECIPE_PHOTOS_DIR, { recursive: true });
    }
    cb(null, RECIPE_PHOTOS_DIR);
  },
  filename: function (req, file, cb) {
    const safeId = sanitizeId(req.body.recipeId || generateId('recipe'));
    cb(null, `${safeId}.jpg`);
  }
});

const uploadRecipePhoto = multer({
  storage: recipePhotoStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: function (req, file, cb) {
    const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
    if (allowedTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Разрешены только изображения (JPEG, PNG, GIF, WebP)'));
    }
  }
});

function setupRecipesAPI(app) {
  // POST /api/recipes/upload-photo - загрузить фото рецепта
  // ВАЖНО: этот route должен быть ПЕРЕД /api/recipes/:id
  app.post('/api/recipes/upload-photo', requireEmployee, uploadRecipePhoto.single('photo'), compressUpload, async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ success: false, error: 'Файл не загружен' });
      }

      const recipeId = sanitizeId(req.body.recipeId || '');
      if (!recipeId) {
        return res.status(400).json({ success: false, error: 'recipeId обязателен' });
      }

      const photoUrl = `/recipe-photos/${recipeId}.jpg`;
      console.log(`✅ Фото рецепта загружено: ${recipeId} (${req.file.size} bytes)`);

      res.json({ success: true, photoUrl });
    } catch (error) {
      console.error('Ошибка загрузки фото рецепта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/recipes - получить все рецепты
  app.get('/api/recipes', requireEmployee, async (req, res) => {
    try {
      console.log('GET /api/recipes');

      if (USE_DB) {
        if (isPaginationRequested(req.query)) {
          const result = await db.findAllPaginated('recipes', {
            orderBy: 'created_at', orderDir: 'DESC',
            page: parseInt(req.query.page) || 1,
            pageSize: Math.min(parseInt(req.query.limit) || 50, 200),
          });
          console.log(`✅ Найдено рецептов: ${result.total} (DB paginated)`);
          return res.json(createDbPaginatedResponse(result, 'recipes', r => r.data));
        }
        const rows = await db.findAll('recipes', { orderBy: 'created_at', orderDir: 'DESC' });
        const recipes = rows.map(r => r.data);
        console.log(`✅ Найдено рецептов: ${recipes.length} (DB)`);
        return res.json({ success: true, recipes });
      }

      const recipes = [];

      if (await fileExists(RECIPES_DIR)) {
        const files = (await fsp.readdir(RECIPES_DIR)).filter(f => f.endsWith('.json'));
        const results = await Promise.allSettled(
          files.map(async (file) => {
            const content = await fsp.readFile(path.join(RECIPES_DIR, file), 'utf8');
            return JSON.parse(content);
          })
        );
        for (const r of results) {
          if (r.status === 'fulfilled') recipes.push(r.value);
          else console.error('Ошибка чтения рецепта:', r.reason?.message);
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
  app.get('/api/recipes/:id', requireEmployee, async (req, res) => {
    try {
      const safeId = sanitizeId(req.params.id);

      if (USE_DB) {
        const row = await db.findById('recipes', safeId);
        if (!row) return res.status(404).json({ success: false, error: 'Рецепт не найден' });
        return res.json({ success: true, recipe: row.data });
      }

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
  app.get('/api/recipes/photo/:recipeId', requireEmployee, async (req, res) => {
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
  app.post('/api/recipes', requireEmployee, async (req, res) => {
    try {
      const { name, category, price, pointsPrice, ingredients, steps } = req.body;
      console.log('POST /api/recipes:', name);

      if (!name || !category) {
        return res.status(400).json({ success: false, error: 'Название и категория обязательны' });
      }

      const id = generateId('recipe');
      const recipe = {
        id,
        name,
        category,
        price: price || '',
        pointsPrice: pointsPrice != null ? parseInt(pointsPrice, 10) || 0 : null,
        ingredients: ingredients || '',
        steps: steps || '',
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };

      const recipeFile = path.join(RECIPES_DIR, `${id}.json`);
      await writeJsonFile(recipeFile, recipe);

      if (USE_DB) {
        try { await db.upsert('recipes', { id, data: recipe, created_at: recipe.createdAt, updated_at: recipe.updatedAt }); }
        catch (dbErr) { console.error('DB save recipe error:', dbErr.message); }
      }

      res.json({ success: true, recipe });
    } catch (error) {
      console.error('Ошибка создания рецепта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/recipes/:id - обновить рецепт
  app.put('/api/recipes/:id', requireEmployee, async (req, res) => {
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
      if (updates.pointsPrice !== undefined) recipe.pointsPrice = updates.pointsPrice != null ? parseInt(updates.pointsPrice, 10) || 0 : null;
      if (updates.photoUrl !== undefined) recipe.photoUrl = updates.photoUrl;
      recipe.updatedAt = new Date().toISOString();

      await writeJsonFile(recipeFile, recipe);

      if (USE_DB) {
        try { await db.upsert('recipes', { id, data: recipe, updated_at: recipe.updatedAt }); }
        catch (dbErr) { console.error('DB update recipe error:', dbErr.message); }
      }

      res.json({ success: true, recipe });
    } catch (error) {
      console.error('Ошибка обновления рецепта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/recipes/:id - удалить рецепт
  app.delete('/api/recipes/:id', requireEmployee, async (req, res) => {
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

      if (USE_DB) {
        try { await db.deleteById('recipes', id); }
        catch (dbErr) { console.error('DB delete recipe error:', dbErr.message); }
      }

      res.json({ success: true, message: 'Рецепт успешно удален' });
    } catch (error) {
      console.error('Ошибка удаления рецепта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Recipes API initialized ${USE_DB ? '(DB mode)' : '(file mode)'}`);
}

module.exports = { setupRecipesAPI };

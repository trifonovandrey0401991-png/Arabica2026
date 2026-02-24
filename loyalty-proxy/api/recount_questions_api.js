/**
 * Recount Questions API
 * Вопросы/товары для пересчета
 *
 * EXTRACTED from index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const { requireAuth, requireAdmin } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_RECOUNT_QUESTIONS === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const RECOUNT_QUESTIONS_DIR = `${DATA_DIR}/recount-questions`;

// Создаем директорию, если её нет
(async () => {
  if (!await fileExists(RECOUNT_QUESTIONS_DIR)) {
    await fsp.mkdir(RECOUNT_QUESTIONS_DIR, { recursive: true });
  }
})();

function setupRecountQuestionsAPI(app, { upload } = {}) {
  // Получить все вопросы пересчета
  app.get('/api/recount-questions', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/recount-questions:', req.query);

      if (USE_DB) {
        const rows = await db.findAll('recount_questions', { orderBy: 'created_at', orderDir: 'ASC' });
        const questions = rows.map(r => r.data);
        if (isPaginationRequested(req.query)) {
          return res.json(createPaginatedResponse(questions, req.query, 'questions'));
        }
        return res.json({ success: true, questions });
      }

      const files = await fsp.readdir(RECOUNT_QUESTIONS_DIR);
      const questions = [];

      for (const file of files) {
        if (file.endsWith('.json')) {
          try {
            const filePath = path.join(RECOUNT_QUESTIONS_DIR, file);
            const data = await fsp.readFile(filePath, 'utf8');
            const question = JSON.parse(data);
            questions.push(question);
          } catch (error) {
            console.error(`Ошибка чтения вопроса ${file}:`, error);
          }
        }
      }

      if (isPaginationRequested(req.query)) {
        return res.json(createPaginatedResponse(questions, req.query, 'questions'));
      }
      res.json({
        success: true,
        questions: questions
      });
    } catch (error) {
      console.error('Ошибка получения вопросов пересчета:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // Создать вопрос пересчета
  app.post('/api/recount-questions', requireAuth, async (req, res) => {
    try {
      console.log('POST /api/recount-questions:', JSON.stringify(req.body).substring(0, 200));

      const questionId = req.body.id || `recount_question_${Date.now()}`;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

      const questionData = {
        id: questionId,
        question: req.body.question,
        grade: req.body.grade || 1,
        referencePhotos: req.body.referencePhotos || {},
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };

      await writeJsonFile(filePath, questionData);

      if (USE_DB) {
        try { await db.upsert('recount_questions', { id: questionId, data: questionData, created_at: questionData.createdAt }); }
        catch (dbErr) { console.error('DB save recount_question error:', dbErr.message); }
      }

      console.log('Вопрос пересчета сохранен:', filePath);

      res.json({
        success: true,
        message: 'Вопрос успешно создан',
        question: questionData
      });
    } catch (error) {
      console.error('Ошибка создания вопроса пересчета:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // Обновить вопрос пересчета
  app.put('/api/recount-questions/:questionId', requireAuth, async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({
          success: false,
          error: 'Вопрос не найден'
        });
      }

      const existingData = await fsp.readFile(filePath, 'utf8');
      const existingQuestion = JSON.parse(existingData);

      const updatedQuestion = {
        ...existingQuestion,
        ...(req.body.question !== undefined && { question: req.body.question }),
        ...(req.body.grade !== undefined && { grade: req.body.grade }),
        ...(req.body.referencePhotos !== undefined && { referencePhotos: req.body.referencePhotos }),
        updatedAt: new Date().toISOString()
      };

      await writeJsonFile(filePath, updatedQuestion);

      if (USE_DB) {
        try { await db.upsert('recount_questions', { id: questionId, data: updatedQuestion, created_at: updatedQuestion.createdAt || existingQuestion.createdAt }); }
        catch (dbErr) { console.error('DB update recount_question error:', dbErr.message); }
      }

      console.log('Вопрос пересчета обновлен:', filePath);

      res.json({
        success: true,
        message: 'Вопрос успешно обновлен',
        question: updatedQuestion
      });
    } catch (error) {
      console.error('Ошибка обновления вопроса пересчета:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // Загрузить эталонное фото для вопроса пересчета
  if (upload) {
    app.post('/api/recount-questions/:questionId/reference-photo', requireAuth, upload.single('photo'), async (req, res) => {
      try {
        const { questionId } = req.params;
        const { shopAddress } = req.body;

        if (!req.file) {
          return res.status(400).json({
            success: false,
            error: 'Файл не загружен'
          });
        }

        if (!shopAddress) {
          return res.status(400).json({
            success: false,
            error: 'Не указан адрес магазина'
          });
        }

        const photoUrl = `https://arabica26.ru/shift-photos/${req.file.filename}`;
        console.log('Эталонное фото загружено:', req.file.filename, 'для магазина:', shopAddress);

        const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
        const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

        if (await fileExists(filePath)) {
          const existingData = await fsp.readFile(filePath, 'utf8');
          const question = JSON.parse(existingData);

          if (!question.referencePhotos) {
            question.referencePhotos = {};
          }
          question.referencePhotos[shopAddress] = photoUrl;
          question.updatedAt = new Date().toISOString();

          await writeJsonFile(filePath, question);

          if (USE_DB) {
            try { await db.upsert('recount_questions', { id: questionId, data: question, created_at: question.createdAt }); }
            catch (dbErr) { console.error('DB update recount_question photo error:', dbErr.message); }
          }

          console.log('Эталонное фото добавлено в вопрос пересчета:', questionId);
        }

        res.json({
          success: true,
          photoUrl: photoUrl,
          shopAddress: shopAddress
        });
      } catch (error) {
        console.error('Ошибка загрузки эталонного фото:', error);
        res.status(500).json({
          success: false,
          error: error.message
        });
      }
    });
  }

  // Удалить вопрос пересчета
  app.delete('/api/recount-questions/:questionId', requireAdmin, async (req, res) => {
    try {
      const { questionId } = req.params;
      const sanitizedId = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({
          success: false,
          error: 'Вопрос не найден'
        });
      }

      await fsp.unlink(filePath);

      if (USE_DB) {
        try { await db.deleteById('recount_questions', questionId); }
        catch (dbErr) { console.error('DB delete recount_question error:', dbErr.message); }
      }

      console.log('Вопрос пересчета удален:', filePath);

      res.json({
        success: true,
        message: 'Вопрос успешно удален'
      });
    } catch (error) {
      console.error('Ошибка удаления вопроса пересчета:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // Массовая загрузка товаров пересчета (ЗАМЕНИТЬ ВСЕ)
  app.post('/api/recount-questions/bulk-upload', requireAdmin, async (req, res) => {
    try {
      console.log('POST /api/recount-questions/bulk-upload:', req.body?.products?.length, 'товаров');

      const { products } = req.body;
      if (!products || !Array.isArray(products)) {
        return res.status(400).json({
          success: false,
          error: 'Необходим массив products'
        });
      }

      // === АТОМАРНЫЙ ПОРЯДОК: файлы первыми, удаление сирот, потом DB ===
      //
      // Старый порядок: delete all files → delete DB → write new files  — ОПАСНО:
      //   если запись новых файлов упала, оба источника пусты.
      //
      // Новый порядок:
      //   1. Пишем новые файлы (overwrite если barcode совпадает)
      //   2. Удаляем старые файлы которых нет в новом наборе
      //   3. DB: DELETE + INSERT в транзакции (try-catch: файлы уже консистентны)

      // ШАГ 1: Создаём новые файлы, запоминаем их имена
      const createdProducts = [];
      const newFileNames = new Set();

      for (const product of products) {
        const barcode = product.barcode?.toString().trim();
        if (!barcode) continue;

        const productId = `product_${barcode}`;
        const sanitizedId = productId.replace(/[^a-zA-Z0-9_\-]/g, '_');
        const fileName = `${sanitizedId}.json`;
        const filePath = path.join(RECOUNT_QUESTIONS_DIR, fileName);

        const productData = {
          id: productId,
          barcode: barcode,
          productGroup: product.productGroup || '',
          productName: product.productName || '',
          grade: product.grade || 1,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString()
        };

        await writeJsonFile(filePath, productData);
        newFileNames.add(fileName);
        createdProducts.push(productData);
      }

      // ШАГ 2: Удаляем старые файлы, которых нет в новом наборе (сироты)
      let deletedCount = 0;
      const existingFiles = await fsp.readdir(RECOUNT_QUESTIONS_DIR);
      for (const file of existingFiles) {
        if (file.endsWith('.json') && !newFileNames.has(file)) {
          try {
            await fsp.unlink(path.join(RECOUNT_QUESTIONS_DIR, file));
            deletedCount++;
          } catch (e) {
            console.error(`bulk-upload: не удалось удалить сирота-файл ${file}:`, e.message);
          }
        }
      }
      console.log(`bulk-upload: создано ${createdProducts.length} файлов, удалено ${deletedCount} сирот`);

      // ШАГ 3: DB — DELETE всех старых + INSERT всех новых в одной транзакции
      // Файлы уже консистентны, поэтому ошибка DB — только логируется
      if (USE_DB) {
        try {
          await db.transaction(async (client) => {
            await client.query('DELETE FROM "recount_questions"');
            for (const p of createdProducts) {
              await client.query(
                `INSERT INTO recount_questions (id, data, created_at)
                 VALUES ($1, $2::jsonb, $3)
                 ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data`,
                [p.id, JSON.stringify(p), p.createdAt]
              );
            }
          });
          console.log(`bulk-upload: DB транзакция завершена (${createdProducts.length} записей)`);
        } catch (dbErr) {
          console.error('bulk-upload: DB транзакция не прошла (файлы сохранены):', dbErr.message);
        }
      }

      console.log(`Создано ${createdProducts.length} товаров`);

      res.json({
        success: true,
        message: `Загружено ${createdProducts.length} товаров`,
        questions: createdProducts
      });
    } catch (error) {
      console.error('Ошибка массовой загрузки товаров:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // Массовое добавление НОВЫХ товаров (только с новыми баркодами)
  app.post('/api/recount-questions/bulk-add-new', requireAdmin, async (req, res) => {
    try {
      console.log('POST /api/recount-questions/bulk-add-new:', req.body?.products?.length, 'товаров');

      const { products } = req.body;
      if (!products || !Array.isArray(products)) {
        return res.status(400).json({
          success: false,
          error: 'Необходим массив products'
        });
      }

      // Читаем существующие баркоды
      const existingBarcodes = new Set();
      const existingFiles = await fsp.readdir(RECOUNT_QUESTIONS_DIR);
      for (const file of existingFiles) {
        if (file.endsWith('.json')) {
          try {
            const data = await fsp.readFile(path.join(RECOUNT_QUESTIONS_DIR, file), 'utf8');
            const product = JSON.parse(data);
            if (product.barcode) {
              existingBarcodes.add(product.barcode.toString());
            }
          } catch (e) {
            console.error(`Ошибка чтения файла ${file}:`, e);
          }
        }
      }
      console.log(`Существующих товаров: ${existingBarcodes.size}`);

      // Добавляем только новые
      const addedProducts = [];
      let skipped = 0;
      for (const product of products) {
        const barcode = product.barcode?.toString().trim();
        if (!barcode) {
          skipped++;
          continue;
        }

        if (existingBarcodes.has(barcode)) {
          skipped++;
          continue;
        }

        const productId = `product_${barcode}`;
        const sanitizedId = productId.replace(/[^a-zA-Z0-9_\-]/g, '_');
        const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

        const productData = {
          id: productId,
          barcode: barcode,
          productGroup: product.productGroup || '',
          productName: product.productName || '',
          grade: product.grade || 1,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString()
        };

        await writeJsonFile(filePath, productData);

        if (USE_DB) {
          try { await db.upsert('recount_questions', { id: productId, data: productData, created_at: productData.createdAt }); }
          catch (dbErr) { /* bulk - skip errors */ }
        }

        addedProducts.push(productData);
        existingBarcodes.add(barcode);
      }

      console.log(`Добавлено ${addedProducts.length} новых товаров, пропущено ${skipped}`);

      res.json({
        success: true,
        message: `Добавлено ${addedProducts.length} новых товаров`,
        added: addedProducts.length,
        skipped: skipped,
        total: existingBarcodes.size,
        questions: addedProducts
      });
    } catch (error) {
      console.error('Ошибка добавления новых товаров:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // Включить/выключить ИИ для товара по баркоду
  // Обновляет и question-файл, и мастер-каталог
  app.patch('/api/recount-questions/by-barcode/:barcode/ai-status', requireAdmin, async (req, res) => {
    try {
      const { barcode } = req.params;
      const { isAiActive } = req.body;

      if (typeof isAiActive !== 'boolean') {
        return res.status(400).json({ success: false, error: 'isAiActive должен быть boolean' });
      }

      // 1. Обновляем question-файл (для отображения в management-странице)
      const sanitizedBarcode = barcode.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(RECOUNT_QUESTIONS_DIR, `product_${sanitizedBarcode}.json`);
      let updatedQuestion = null;

      if (await fileExists(filePath)) {
        const existingData = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        updatedQuestion = { ...existingData, isAiActive, updatedAt: new Date().toISOString() };
        await writeJsonFile(filePath, updatedQuestion);

        if (USE_DB) {
          try { await db.upsert('recount_questions', { id: existingData.id, data: updatedQuestion, created_at: existingData.createdAt }); }
          catch (dbErr) { console.error('DB update recount_question isAiActive error:', dbErr.message); }
        }
      }

      // 2. Обновляем мастер-каталог (для реального пересчёта)
      let masterUpdated = false;
      try {
        const { loadProducts, saveProducts } = require('./master_catalog_api');
        const products = await loadProducts();
        const masterProduct = products.find((p) => p.barcode === barcode);
        if (masterProduct) {
          masterProduct.isAiActive = isAiActive;
          masterProduct.updatedAt = new Date().toISOString();
          await saveProducts(products);
          masterUpdated = true;
        }
      } catch (mcErr) {
        console.error('[Recount Questions] Ошибка обновления мастер-каталога:', mcErr.message);
      }

      console.log(`[Recount Questions] AI статус для barcode=${barcode}: ${isAiActive}, master=${masterUpdated}`);

      res.json({
        success: true,
        barcode,
        isAiActive,
        questionUpdated: updatedQuestion !== null,
        masterCatalogUpdated: masterUpdated,
      });
    } catch (error) {
      console.error('[Recount Questions] Ошибка обновления AI статуса:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Recount Questions API initialized ${USE_DB ? '(DB mode)' : '(file mode)'}`);
}

/**
 * D2: Удалить вопрос пересчёта по barcode.
 * Вызывается при удалении товара из мастер-каталога.
 */
async function deleteQuestionsByBarcode(barcode) {
  if (!barcode) return;
  const productId = `product_${barcode}`;
  const sanitizedId = productId.replace(/[^a-zA-Z0-9_\-]/g, '_');
  const filePath = path.join(RECOUNT_QUESTIONS_DIR, `${sanitizedId}.json`);

  // Удаляем файл (игнорируем ENOENT)
  try {
    await fsp.unlink(filePath);
    console.log(`[Recount Questions] Удалён вопрос для barcode ${barcode}`);
  } catch (e) {
    if (e.code !== 'ENOENT') console.error('[Recount Questions] Ошибка удаления файла:', e.message);
  }

  // Удаляем из DB
  if (USE_DB) {
    try {
      await db.deleteById('recount_questions', productId);
    } catch (e) {
      console.error('[Recount Questions] Ошибка удаления из DB:', e.message);
    }
  }
}

module.exports = { setupRecountQuestionsAPI, deleteQuestionsByBarcode };

/**
 * Envelope API
 * Вопросы конверта + Отчёты конвертов + Pending/Failed
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fs = require('fs');
const fsp = require('fs').promises;
const path = require('path');
const { sanitizeId, fileExists } = require('../utils/file_helpers');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const ENVELOPE_QUESTIONS_DIR = `${DATA_DIR}/envelope-questions`;
const ENVELOPE_REPORTS_DIR = `${DATA_DIR}/envelope-reports`;

// Создаем директории, если их нет
(async () => {
  if (!await fileExists(ENVELOPE_QUESTIONS_DIR)) {
    await fsp.mkdir(ENVELOPE_QUESTIONS_DIR, { recursive: true });
  }
  if (!await fileExists(ENVELOPE_REPORTS_DIR)) {
    await fsp.mkdir(ENVELOPE_REPORTS_DIR, { recursive: true });
  }
})();

// Дефолтные вопросы конверта для инициализации
const defaultEnvelopeQuestions = [
  { id: 'envelope_q_1', title: 'Выбор смены', description: 'Выберите тип смены', type: 'shift_select', section: 'general', order: 1, isRequired: true, isActive: true },
  { id: 'envelope_q_2', title: 'ООО: Z-отчет', description: 'Сфотографируйте Z-отчет ООО', type: 'photo', section: 'ooo', order: 2, isRequired: true, isActive: true },
  { id: 'envelope_q_3', title: 'ООО: Выручка и наличные', description: 'Введите данные ООО', type: 'numbers', section: 'ooo', order: 3, isRequired: true, isActive: true },
  { id: 'envelope_q_4', title: 'ООО: Фото конверта', description: 'Сфотографируйте сформированный конверт ООО', type: 'photo', section: 'ooo', order: 4, isRequired: true, isActive: true },
  { id: 'envelope_q_5', title: 'ИП: Z-отчет', description: 'Сфотографируйте Z-отчет ИП', type: 'photo', section: 'ip', order: 5, isRequired: true, isActive: true },
  { id: 'envelope_q_6', title: 'ИП: Выручка и наличные', description: 'Введите данные ИП', type: 'numbers', section: 'ip', order: 6, isRequired: true, isActive: true },
  { id: 'envelope_q_7', title: 'ИП: Расходы', description: 'Добавьте расходы', type: 'expenses', section: 'ip', order: 7, isRequired: true, isActive: true },
  { id: 'envelope_q_8', title: 'ИП: Фото конверта', description: 'Сфотографируйте сформированный конверт ИП', type: 'photo', section: 'ip', order: 8, isRequired: true, isActive: true },
  { id: 'envelope_q_9', title: 'Итог', description: 'Проверьте данные и отправьте отчет', type: 'summary', section: 'general', order: 9, isRequired: true, isActive: true },
];

// Инициализация дефолтных вопросов при старте
(async function initEnvelopeQuestions() {
  try {
    const files = await fsp.readdir(ENVELOPE_QUESTIONS_DIR);
    if (files.filter(f => f.endsWith('.json')).length === 0) {
      console.log('Инициализация дефолтных вопросов конверта...');
      for (const q of defaultEnvelopeQuestions) {
        const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${q.id}.json`);
        await fsp.writeFile(filePath, JSON.stringify({ ...q, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() }, null, 2));
      }
      console.log('✅ Дефолтные вопросы конверта созданы');
    }
  } catch (e) {
    console.error('Ошибка инициализации вопросов конверта:', e);
  }
})();

function setupEnvelopeAPI(app) {
  // ========== ENVELOPE QUESTIONS ==========

  // GET /api/envelope-questions - получить все вопросы
  app.get('/api/envelope-questions', async (req, res) => {
    try {
      console.log('GET /api/envelope-questions');
      const files = await fsp.readdir(ENVELOPE_QUESTIONS_DIR);
      const questions = [];

      for (const file of files) {
        if (file.endsWith('.json')) {
          const filePath = path.join(ENVELOPE_QUESTIONS_DIR, file);
          const data = await fsp.readFile(filePath, 'utf8');
          const question = JSON.parse(data);
          questions.push(question);
        }
      }

      // Сортировка по order
      questions.sort((a, b) => (a.order || 0) - (b.order || 0));

      res.json({ success: true, questions });
    } catch (error) {
      console.error('Ошибка получения вопросов конверта:', error);
      res.status(500).json({ success: false, error: error.message, questions: [] });
    }
  });

  // GET /api/envelope-questions/:id - получить один вопрос
  app.get('/api/envelope-questions/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const sanitizedId2 = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${sanitizedId2}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({ success: false, error: 'Вопрос не найден' });
      }

      const data = await fsp.readFile(filePath, 'utf8');
      const question = JSON.parse(data);

      res.json({ success: true, question });
    } catch (error) {
      console.error('Ошибка получения вопроса конверта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/envelope-questions - создать вопрос
  app.post('/api/envelope-questions', async (req, res) => {
    try {
      console.log('POST /api/envelope-questions:', JSON.stringify(req.body).substring(0, 200));

      const questionId = req.body.id || `envelope_q_${Date.now()}`;
      const sanitizedId2 = questionId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${sanitizedId2}.json`);

      const question = {
        id: questionId,
        title: req.body.title || '',
        description: req.body.description || '',
        type: req.body.type || 'photo',
        section: req.body.section || 'general',
        order: req.body.order || 1,
        isRequired: req.body.isRequired !== false,
        isActive: req.body.isActive !== false,
        referencePhotoUrl: req.body.referencePhotoUrl || null,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };

      await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
      console.log('Вопрос конверта создан:', filePath);

      res.json({ success: true, question });
    } catch (error) {
      console.error('Ошибка создания вопроса конверта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/envelope-questions/:id - обновить вопрос
  app.put('/api/envelope-questions/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('PUT /api/envelope-questions:', id);

      const sanitizedId2 = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${sanitizedId2}.json`);

      // Если файл не существует, создаем новый
      let question = {};
      if (await fileExists(filePath)) {
        const existingData = await fsp.readFile(filePath, 'utf8');
        question = JSON.parse(existingData);
      }

      // Обновляем поля
      if (req.body.title !== undefined) question.title = req.body.title;
      if (req.body.description !== undefined) question.description = req.body.description;
      if (req.body.type !== undefined) question.type = req.body.type;
      if (req.body.section !== undefined) question.section = req.body.section;
      if (req.body.order !== undefined) question.order = req.body.order;
      if (req.body.isRequired !== undefined) question.isRequired = req.body.isRequired;
      if (req.body.isActive !== undefined) question.isActive = req.body.isActive;
      if (req.body.referencePhotoUrl !== undefined) question.referencePhotoUrl = req.body.referencePhotoUrl;

      question.id = id;
      question.updatedAt = new Date().toISOString();
      if (!question.createdAt) question.createdAt = new Date().toISOString();

      await fsp.writeFile(filePath, JSON.stringify(question, null, 2), 'utf8');
      console.log('Вопрос конверта обновлен:', filePath);

      res.json({ success: true, question });
    } catch (error) {
      console.error('Ошибка обновления вопроса конверта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/envelope-questions/:id - удалить вопрос
  app.delete('/api/envelope-questions/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('DELETE /api/envelope-questions:', id);

      const sanitizedId2 = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_QUESTIONS_DIR, `${sanitizedId2}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({ success: false, error: 'Вопрос не найден' });
      }

      await fsp.unlink(filePath);
      console.log('Вопрос конверта удален:', filePath);

      res.json({ success: true, message: 'Вопрос успешно удален' });
    } catch (error) {
      console.error('Ошибка удаления вопроса конверта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ========== ENVELOPE REPORTS ==========

  // GET /api/envelope-reports - получить все отчеты
  app.get('/api/envelope-reports', async (req, res) => {
    try {
      console.log('GET /api/envelope-reports:', req.query);
      let { shopAddress, status, fromDate, toDate } = req.query;

      // Декодируем shop address если он URL-encoded
      if (shopAddress && shopAddress.includes('%')) {
        try {
          shopAddress = decodeURIComponent(shopAddress);
          console.log(`  📋 Декодирован shop address: "${shopAddress}"`);
        } catch (e) {
          console.error('  ⚠️ Ошибка декодирования shopAddress:', e);
        }
      }

      // Нормализуем адрес магазина для сравнения (убираем лишние пробелы)
      const normalizedShopAddress = shopAddress ? shopAddress.trim() : null;
      if (normalizedShopAddress) {
        console.log(`  📋 Фильтр по магазину: "${normalizedShopAddress}" (длина: ${normalizedShopAddress.length})`);
      }

      const reports = [];
      if (await fileExists(ENVELOPE_REPORTS_DIR)) {
        const files = await fs.promises.readdir(ENVELOPE_REPORTS_DIR);
        const jsonFiles = files.filter(f => f.endsWith('.json'));
        console.log(`  📋 Найдено файлов конвертов: ${jsonFiles.length}`);

        for (const file of jsonFiles) {
          try {
            const content = await fs.promises.readFile(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8');
            const report = JSON.parse(content);

            // Применяем фильтры (с нормализацией адреса)
            if (normalizedShopAddress) {
              const reportShopTrimmed = report.shopAddress.trim();
              console.log(`  📋 Сравнение: "${reportShopTrimmed}" (длина: ${reportShopTrimmed.length}) === "${normalizedShopAddress}" (длина: ${normalizedShopAddress.length}) => ${reportShopTrimmed === normalizedShopAddress}`);
              if (reportShopTrimmed !== normalizedShopAddress) continue;
            }
            if (status && report.status !== status) continue;
            if (fromDate && new Date(report.createdAt) < new Date(fromDate)) continue;
            if (toDate && new Date(report.createdAt) > new Date(toDate)) continue;

            reports.push(report);
          } catch (e) {
            console.error(`Ошибка чтения ${file}:`, e);
          }
        }
      }

      // Сортируем по дате создания (новые первыми)
      reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      if (isPaginationRequested(req.query)) {
        res.json(createPaginatedResponse(reports, req.query, 'reports'));
      } else {
        res.json({ success: true, reports });
      }
    } catch (error) {
      console.error('Ошибка получения отчетов конвертов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/envelope-reports/expired - получить просроченные отчеты
  app.get('/api/envelope-reports/expired', async (req, res) => {
    try {
      console.log('GET /api/envelope-reports/expired');

      const reports = [];
      if (await fileExists(ENVELOPE_REPORTS_DIR)) {
        const files = await fs.promises.readdir(ENVELOPE_REPORTS_DIR);
        const jsonFiles = files.filter(f => f.endsWith('.json'));

        for (const file of jsonFiles) {
          try {
            const content = await fs.promises.readFile(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8');
            const report = JSON.parse(content);

            // Проверяем: не подтверждён И прошло более 24 часов
            if (report.status === 'pending') {
              const createdAt = new Date(report.createdAt);
              const now = new Date();
              const diffHours = (now - createdAt) / (1000 * 60 * 60);

              if (diffHours >= 24) {
                reports.push(report);
              }
            }
          } catch (e) {
            console.error(`Ошибка чтения ${file}:`, e);
          }
        }
      }

      // Сортируем по дате создания (старые первыми)
      reports.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));

      res.json({ success: true, reports });
    } catch (error) {
      console.error('Ошибка получения просроченных отчетов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/envelope-reports/:id - получить один отчет
  app.get('/api/envelope-reports/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('GET /api/envelope-reports/:id', id);

      const sanitizedId2 = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_REPORTS_DIR, `${sanitizedId2}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({ success: false, error: 'Отчет не найден' });
      }

      const content = await fs.promises.readFile(filePath, 'utf8');
      const report = JSON.parse(content);

      res.json({ success: true, report });
    } catch (error) {
      console.error('Ошибка получения отчета:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/envelope-reports - создать новый отчет
  app.post('/api/envelope-reports', async (req, res) => {
    try {
      console.log('POST /api/envelope-reports:', JSON.stringify(req.body).substring(0, 300));

      const reportId = req.body.id || `envelope_report_${Date.now()}`;
      const report = {
        ...req.body,
        id: reportId,
        createdAt: new Date().toISOString(),
        status: req.body.status || 'pending',
      };

      const sanitizedId2 = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_REPORTS_DIR, `${sanitizedId2}.json`);

      await fs.promises.writeFile(filePath, JSON.stringify(report, null, 2), 'utf8');
      console.log('Отчет конверта создан:', filePath);

      res.json({ success: true, report });
    } catch (error) {
      console.error('Ошибка создания отчета конверта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/envelope-reports/:id - обновить отчет
  app.put('/api/envelope-reports/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('PUT /api/envelope-reports/:id', id);

      const sanitizedId2 = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_REPORTS_DIR, `${sanitizedId2}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({ success: false, error: 'Отчет не найден' });
      }

      const content = await fs.promises.readFile(filePath, 'utf8');
      const existingReport = JSON.parse(content);

      const updatedReport = {
        ...existingReport,
        ...req.body,
        id: existingReport.id, // Не меняем ID
        createdAt: existingReport.createdAt, // Не меняем дату создания
      };

      await fs.promises.writeFile(filePath, JSON.stringify(updatedReport, null, 2), 'utf8');
      console.log('Отчет конверта обновлён:', filePath);

      res.json({ success: true, report: updatedReport });
    } catch (error) {
      console.error('Ошибка обновления отчета:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/envelope-reports/:id/confirm - подтвердить отчет с оценкой
  app.put('/api/envelope-reports/:id/confirm', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const { confirmedByAdmin, rating } = req.body;
      console.log('PUT /api/envelope-reports/:id/confirm', id, confirmedByAdmin, rating);

      const sanitizedId2 = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_REPORTS_DIR, `${sanitizedId2}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({ success: false, error: 'Отчет не найден' });
      }

      const content = await fs.promises.readFile(filePath, 'utf8');
      const report = JSON.parse(content);

      report.status = 'confirmed';
      report.confirmedAt = new Date().toISOString();
      report.confirmedByAdmin = confirmedByAdmin;
      report.rating = rating;

      await fs.promises.writeFile(filePath, JSON.stringify(report, null, 2), 'utf8');
      console.log('Отчет конверта подтверждён:', filePath);

      res.json({ success: true, report });
    } catch (error) {
      console.error('Ошибка подтверждения отчета:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/envelope-reports/:id - удалить отчет
  app.delete('/api/envelope-reports/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('DELETE /api/envelope-reports/:id', id);

      const sanitizedId2 = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(ENVELOPE_REPORTS_DIR, `${sanitizedId2}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({ success: false, error: 'Отчет не найден' });
      }

      await fs.promises.unlink(filePath);
      console.log('Отчет конверта удалён:', filePath);

      res.json({ success: true, message: 'Отчет успешно удален' });
    } catch (error) {
      console.error('Ошибка удаления отчета:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ========== ENVELOPE PENDING/FAILED ==========

  // GET /api/envelope-pending - получить pending отчеты
  app.get('/api/envelope-pending', async (req, res) => {
    try {
      console.log('GET /api/envelope-pending');
      const pendingDir = `${DATA_DIR}/envelope-pending`;
      const reports = [];

      if (await fileExists(pendingDir)) {
        const files = await fs.promises.readdir(pendingDir);

        for (const file of files) {
          if (file.startsWith('pending_env_')) {
            try {
              const content = await fs.promises.readFile(path.join(pendingDir, file), 'utf8');
              const data = JSON.parse(content);
              if (data.status === 'pending') {
                reports.push(data);
              }
            } catch (e) {
              console.error(`Ошибка чтения ${file}:`, e);
            }
          }
        }
      }

      // Сортируем по дате создания (новые первыми)
      reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      res.json(reports);
    } catch (error) {
      console.error('Ошибка получения pending отчетов:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // GET /api/envelope-failed - получить failed отчеты
  app.get('/api/envelope-failed', async (req, res) => {
    try {
      console.log('GET /api/envelope-failed');
      const pendingDir = `${DATA_DIR}/envelope-pending`;
      const reports = [];

      if (await fileExists(pendingDir)) {
        const files = await fs.promises.readdir(pendingDir);

        for (const file of files) {
          if (file.startsWith('pending_env_')) {
            try {
              const content = await fs.promises.readFile(path.join(pendingDir, file), 'utf8');
              const data = JSON.parse(content);
              if (data.status === 'failed') {
                reports.push(data);
              }
            } catch (e) {
              console.error(`Ошибка чтения ${file}:`, e);
            }
          }
        }
      }

      // Сортируем по дате создания (новые первыми)
      reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      res.json(reports);
    } catch (error) {
      console.error('Ошибка получения failed отчетов:', error);
      res.status(500).json({ error: error.message });
    }
  });

  console.log('✅ Envelope API initialized');
}

module.exports = { setupEnvelopeAPI };

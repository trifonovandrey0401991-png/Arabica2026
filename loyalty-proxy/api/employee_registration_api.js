/**
 * Employee Registration API
 * Регистрация и верификация сотрудников
 *
 * EXTRACTED from index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, maskPhone } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const { requireAuth } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_EMPLOYEE_REGISTRATION === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';

function setupEmployeeRegistrationAPI(app, { sendPushToPhone } = {}) {
  const registrationDir = `${DATA_DIR}/employee-registrations`;

  // Эндпоинт для сохранения регистрации сотрудника
  app.post('/api/employee-registration', async (req, res) => {
    try {
      console.log('POST /api/employee-registration:', JSON.stringify(req.body).substring(0, 200));

      if (!await fileExists(registrationDir)) {
        await fsp.mkdir(registrationDir, { recursive: true });
      }

      const phone = req.body.phone;
      if (!phone) {
        return res.status(400).json({ success: false, error: 'Телефон не указан' });
      }

      // Санитизируем телефон для имени файла
      const sanitizedPhone = phone.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const registrationFile = path.join(registrationDir, `${sanitizedPhone}.json`);

      // Сохраняем регистрацию
      const registrationData = {
        ...req.body,
        updatedAt: new Date().toISOString(),
      };

      // Если файл существует, сохраняем createdAt из старого файла
      if (await fileExists(registrationFile)) {
        try {
          const oldContent = await fsp.readFile(registrationFile, 'utf8');
          const oldData = JSON.parse(oldContent);
          if (oldData.createdAt) {
            registrationData.createdAt = oldData.createdAt;
          }
        } catch (e) {
          console.error('Ошибка чтения старого файла:', e);
        }
      } else {
        registrationData.createdAt = new Date().toISOString();
      }

      await writeJsonFile(registrationFile, registrationData);

      if (USE_DB) {
        try { await db.upsert('employee_registrations', { id: sanitizedPhone, data: registrationData, created_at: registrationData.createdAt }); }
        catch (dbErr) { console.error('DB save employee_registration error:', dbErr.message); }
      }

      console.log('Регистрация сохранена:', registrationFile);

      res.json({
        success: true,
        message: 'Регистрация успешно сохранена'
      });
    } catch (error) {
      console.error('Ошибка сохранения регистрации:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при сохранении регистрации'
      });
    }
  });

  // Эндпоинт для получения регистрации по телефону
  app.get('/api/employee-registration/:phone', requireAuth, async (req, res) => {
    try {
      const phone = decodeURIComponent(req.params.phone);
      console.log('GET /api/employee-registration:', maskPhone(phone));

      if (USE_DB) {
        const sanitizedPhone = phone.replace(/[^a-zA-Z0-9_\-]/g, '_');
        const row = await db.findById('employee_registrations', sanitizedPhone);
        return res.json({ success: true, registration: row ? row.data : null });
      }

      const sanitizedPhone = phone.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const registrationFile = path.join(registrationDir, `${sanitizedPhone}.json`);

      if (!await fileExists(registrationFile)) {
        return res.json({ success: true, registration: null });
      }

      const content = await fsp.readFile(registrationFile, 'utf8');
      const registration = JSON.parse(content);

      res.json({ success: true, registration });
    } catch (error) {
      console.error('Ошибка получения регистрации:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при получении регистрации'
      });
    }
  });

  // Эндпоинт для верификации/снятия верификации сотрудника
  app.post('/api/employee-registration/:phone/verify', requireAuth, async (req, res) => {
    try {
      const phone = decodeURIComponent(req.params.phone);
      const { isVerified, verifiedBy } = req.body;
      console.log('POST /api/employee-registration/:phone/verify:', maskPhone(phone), isVerified);

      const sanitizedPhone = phone.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const registrationFile = path.join(registrationDir, `${sanitizedPhone}.json`);

      if (!await fileExists(registrationFile)) {
        return res.status(404).json({
          success: false,
          error: 'Регистрация не найдена'
        });
      }

      const content = await fsp.readFile(registrationFile, 'utf8');
      const registration = JSON.parse(content);

      registration.isVerified = isVerified === true;
      // Сохраняем дату первой верификации, даже если верификация снята
      // Это нужно для отображения в списке "Не верифицированных сотрудников"
      if (isVerified) {
        // Верификация - устанавливаем дату, если её еще нет
        if (!registration.verifiedAt) {
          registration.verifiedAt = new Date().toISOString();
        }
        registration.verifiedBy = verifiedBy;
      } else {
        // Снятие верификации - устанавливаем дату, если её еще нет
        // Это нужно для отображения в списке "Не верифицированных сотрудников"
        if (!registration.verifiedAt) {
          registration.verifiedAt = new Date().toISOString();
        }
        // verifiedAt остается с датой (первой верификации или текущей датой при снятии)
        registration.verifiedBy = null;
      }
      registration.updatedAt = new Date().toISOString();

      await writeJsonFile(registrationFile, registration);

      if (USE_DB) {
        try { await db.upsert('employee_registrations', { id: sanitizedPhone, data: registration, created_at: registration.createdAt }); }
        catch (dbErr) { console.error('DB update employee_registration verify error:', dbErr.message); }
      }

      console.log('Статус верификации обновлен:', registrationFile);

      // Если верификация снята - отправляем push уведомление сотруднику
      // чтобы приложение заблокировалось и потребовало перезапуск
      if (!isVerified) {
        try {
          if (sendPushToPhone) {
            await sendPushToPhone(
              phone,
              'Верификация отозвана',
              'Ваша верификация была отозвана администратором. Пожалуйста, перезапустите приложение.',
              { type: 'verification_revoked' }
            );
            console.log('Push-уведомление о снятии верификации отправлено:', maskPhone(phone));
          }
        } catch (pushError) {
          console.error('Ошибка отправки push при снятии верификации:', pushError);
          // Не блокируем основную операцию из-за ошибки push
        }
      }

      res.json({
        success: true,
        message: isVerified ? 'Сотрудник верифицирован' : 'Верификация снята'
      });
    } catch (error) {
      console.error('Ошибка верификации:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при верификации'
      });
    }
  });

  // Эндпоинт для получения всех регистраций (для админа)
  app.get('/api/employee-registrations', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/employee-registrations');

      if (USE_DB) {
        const rows = await db.findAll('employee_registrations', { orderBy: 'created_at', orderDir: 'DESC' });
        const dbRegistrations = rows.map(r => r.data);
        if (isPaginationRequested(req.query)) {
          return res.json(createPaginatedResponse(dbRegistrations, req.query, 'registrations'));
        }
        return res.json({ success: true, registrations: dbRegistrations });
      }

      const registrations = [];

      if (await fileExists(registrationDir)) {
        const files = (await fsp.readdir(registrationDir)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const filePath = path.join(registrationDir, file);
            const content = await fsp.readFile(filePath, 'utf8');
            const registration = JSON.parse(content);
            registrations.push(registration);
          } catch (e) {
            console.error(`Ошибка чтения файла ${file}:`, e);
          }
        }

        registrations.sort((a, b) => {
          const dateA = new Date(a.createdAt || 0);
          const dateB = new Date(b.createdAt || 0);
          return dateB - dateA;
        });
      }

      if (isPaginationRequested(req.query)) {
        return res.json(createPaginatedResponse(registrations, req.query, 'registrations'));
      }
      res.json({ success: true, registrations });
    } catch (error) {
      console.error('Ошибка получения регистраций:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при получении регистраций'
      });
    }
  });

  console.log(`✅ Employee Registration API initialized ${USE_DB ? '(DB mode)' : '(file mode)'}`);
}

module.exports = { setupEmployeeRegistrationAPI };

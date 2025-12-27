const express = require('express');
const fetch = require('node-fetch');
const bodyParser = require('body-parser');
const cors = require('cors');
const multer = require('multer');
const fs = require('fs');
const path = require('path');
const { exec, execFile } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);
const execFilePromise = util.promisify(execFile);

const app = express();
app.use(bodyParser.json());
app.use(cors());

// Статические файлы для редактора координат
app.use('/static', express.static('/var/www/html'));

// Настройка multer для загрузки фото
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = '/var/www/shift-photos';
    // Создаем директорию, если её нет
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    // Используем оригинальное имя файла
    const safeName = Buffer.from(file.originalname, 'latin1').toString('utf8');
    cb(null, safeName);
  }
});

const upload = multer({ 
  storage: storage,
  limits: { fileSize: 10 * 1024 * 1024 } // 10MB
});

// URL Google Apps Script для регистрации, лояльности и ролей
const SCRIPT_URL = process.env.SCRIPT_URL || "https://script.google.com/macros/s/AKfycbzaH6AqH8j9E93Tf4SFCie35oeESGfBL6p51cTHl9EvKq0Y5bfzg4UbmsDKB1B82yPS/exec";

app.post('/', async (req, res) => {
  try {
    console.log("POST request to script:", SCRIPT_URL);
    console.log("Request body:", JSON.stringify(req.body));
    
    const response = await fetch(SCRIPT_URL, {
      method: 'post',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body),
    });

    const contentType = response.headers.get('content-type');
    console.log("Response status:", response.status);
    console.log("Response content-type:", contentType);

    if (!contentType || !contentType.includes('application/json')) {
      const text = await response.text();
      console.error("Non-JSON response received:", text.substring(0, 200));
      throw new Error(`Сервер вернул HTML вместо JSON. Проверьте URL сервера: ${SCRIPT_URL}`);
    }

    const data = await response.json();
    res.json(data);
  } catch (error) {
    console.error("POST error:", error);
    res.status(500).json({ 
      success: false, 
      error: error.message || 'Ошибка при обращении к серверу'
    });
  }
});

app.get('/', async (req, res) => {
  try {
    console.log("GET request:", req.query);
    const queryString = new URLSearchParams(req.query).toString();
    const url = `${SCRIPT_URL}?${queryString}`;

    const response = await fetch(url);
    
    const contentType = response.headers.get('content-type');
    console.log("Response status:", response.status);
    console.log("Response content-type:", contentType);

    if (!contentType || !contentType.includes('application/json')) {
      const text = await response.text();
      console.error("Non-JSON response received:", text.substring(0, 200));
      throw new Error(`Сервер вернул HTML вместо JSON. Проверьте URL сервера: ${SCRIPT_URL}`);
    }

    const data = await response.json();
    res.json(data);
  } catch (error) {
    console.error("GET error:", error);
    res.status(500).json({ 
      success: false, 
      error: error.message || 'Ошибка при обращении к серверу'
    });
  }
});

// Эндпоинт для загрузки фото
app.post('/upload-photo', upload.single('file'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'Файл не загружен' });
    }

    const fileUrl = `https://arabica26.ru/shift-photos/${req.file.filename}`;
    console.log('Фото загружено:', req.file.filename);
    
    res.json({
      success: true,
      url: fileUrl,
      filePath: fileUrl, // Для совместимости с Flutter кодом
      filename: req.file.filename
    });
  } catch (error) {
    console.error('Ошибка загрузки фото:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Эндпоинт для создания отчета пересчета
app.post('/api/recount-reports', async (req, res) => {
  try {
    console.log('POST /api/recount-reports:', JSON.stringify(req.body).substring(0, 200));
    
    // Сохраняем отчет локально в файл
    const reportsDir = '/var/www/recount-reports';
    if (!fs.existsSync(reportsDir)) {
      fs.mkdirSync(reportsDir, { recursive: true });
    }
    
    const reportId = req.body.id || `report_${Date.now()}`;
    // Санитизируем имя файла: заменяем недопустимые символы на подчеркивания
    const sanitizedId = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const reportFile = path.join(reportsDir, `${sanitizedId}.json`);
    
    // Сохраняем отчет с временной меткой
    const reportData = {
      ...req.body,
      createdAt: new Date().toISOString(),
      savedAt: new Date().toISOString()
    };
    
    try {
      fs.writeFileSync(reportFile, JSON.stringify(reportData, null, 2), 'utf8');
      console.log('Отчет сохранен:', reportFile);
    } catch (writeError) {
      console.error('Ошибка записи файла:', writeError);
      throw writeError;
    }
    
    // Пытаемся также отправить в Google Apps Script (опционально)
    try {
      const response = await fetch(SCRIPT_URL, {
        method: 'post',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          action: 'createRecountReport',
          ...req.body
        }),
      });

      const contentType = response.headers.get('content-type');
      if (contentType && contentType.includes('application/json')) {
        const data = await response.json();
        if (data.success) {
          console.log('Отчет также отправлен в Google Apps Script');
        }
      }
    } catch (scriptError) {
      console.log('Google Apps Script не поддерживает это действие, отчет сохранен локально');
    }
    
    res.json({ 
      success: true, 
      message: 'Отчет успешно сохранен',
      reportId: reportId
    });
  } catch (error) {
    console.error('Ошибка создания отчета:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message || 'Ошибка при сохранении отчета' 
    });
  }
});

// Эндпоинт для получения отчетов пересчета
app.get('/api/recount-reports', async (req, res) => {
  try {
    console.log('GET /api/recount-reports:', req.query);
    
    const reportsDir = '/var/www/recount-reports';
    const reports = [];
    
    // Читаем отчеты из локальной директории асинхронно
    if (fs.existsSync(reportsDir)) {
      const files = await fs.promises.readdir(reportsDir);
      const jsonFiles = files.filter(f => f.endsWith('.json'));

      const readPromises = jsonFiles.map(async (file) => {
        try {
          const filePath = path.join(reportsDir, file);
          const content = await fs.promises.readFile(filePath, 'utf8');
          return JSON.parse(content);
        } catch (e) {
          console.error(`Ошибка чтения файла ${file}:`, e);
          return null;
        }
      });

      const results = await Promise.all(readPromises);
      reports.push(...results.filter(r => r !== null));
    }
      
      // Сортируем по дате создания (новые первыми)
      reports.sort((a, b) => {
        const dateA = new Date(a.createdAt || a.savedAt || 0);
        const dateB = new Date(b.createdAt || b.savedAt || 0);
        return dateB - dateA;
      });
      
      // Применяем фильтры из query параметров
      let filteredReports = reports;
      if (req.query.shopAddress) {
        filteredReports = filteredReports.filter(r => 
          r.shopAddress && r.shopAddress.includes(req.query.shopAddress)
        );
      }
      if (req.query.employeeName) {
        filteredReports = filteredReports.filter(r => 
          r.employeeName && r.employeeName.includes(req.query.employeeName)
        );
      }
      if (req.query.date) {
        const filterDate = new Date(req.query.date);
        filteredReports = filteredReports.filter(r => {
          const reportDate = new Date(r.completedAt || r.createdAt || r.savedAt);
          return reportDate.toDateString() === filterDate.toDateString();
        });
      }
      
      return res.json({ success: true, reports: filteredReports });
    }
    
    // Если директории нет, возвращаем пустой список
    res.json({ success: true, reports: [] });
  } catch (error) {
    console.error('Ошибка получения отчетов:', error);
    res.json({ success: true, reports: [] });
  }
});

// Эндпоинт для оценки отчета
app.post('/api/recount-reports/:reportId/rating', async (req, res) => {
  try {
    let { reportId } = req.params;

    // SECURITY: Validate format BEFORE any processing
    if (!/^[a-zA-Z0-9_\-]+$/.test(reportId)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid reportId format'
      });
    }

    console.log(`POST /api/recount-reports/${reportId}/rating:`, req.body);

    const reportsDir = '/var/www/recount-reports';
    const reportFile = path.join(reportsDir, `${reportId}.json`);

    // SECURITY: Verify the resolved path is within reportsDir
    const resolvedPath = path.resolve(reportFile);
    const resolvedDir = path.resolve(reportsDir);
    if (!resolvedPath.startsWith(resolvedDir + path.sep)) {
      return res.status(403).json({
        success: false,
        error: 'Access denied'
      });
    }

    if (!fs.existsSync(reportFile)) {
      console.error(`Файл не найден: ${reportFile}`);
      // SECURITY: Use exact match instead of substring
      const files = fs.readdirSync(reportsDir).filter(f => f.endsWith('.json'));
      const matchingFile = files.find(f => f === `${reportId}.json`);
      if (matchingFile) {
        console.log(`Найден файл по частичному совпадению: ${matchingFile}`);
        const actualFile = path.join(reportsDir, matchingFile);
        const content = fs.readFileSync(actualFile, 'utf8');
        const report = JSON.parse(content);
        
        // Обновляем оценку
        report.adminRating = req.body.rating;
        report.adminName = req.body.adminName;
        report.ratedAt = new Date().toISOString();
        
        // Сохраняем обновленный отчет
        fs.writeFileSync(actualFile, JSON.stringify(report, null, 2), 'utf8');
        console.log('Оценка сохранена для отчета:', matchingFile);
        
        return res.json({ success: true, message: 'Оценка успешно сохранена' });
      }
      return res.status(404).json({ success: false, error: 'Отчет не найден' });
    }
    
    // Читаем отчет
    const content = fs.readFileSync(reportFile, 'utf8');
    const report = JSON.parse(content);
    
    // Обновляем оценку
    report.adminRating = req.body.rating;
    report.adminName = req.body.adminName;
    report.ratedAt = new Date().toISOString();
    
    // Сохраняем обновленный отчет
    fs.writeFileSync(reportFile, JSON.stringify(report, null, 2), 'utf8');
    console.log('Оценка сохранена для отчета:', reportId);
    
    res.json({ success: true, message: 'Оценка успешно сохранена' });
  } catch (error) {
    console.error('Ошибка оценки отчета:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Эндпоинт для отправки push-уведомления
app.post('/api/recount-reports/:reportId/notify', async (req, res) => {
  try {
    const { reportId } = req.params;
    console.log(`POST /api/recount-reports/${reportId}/notify`);
    
    // Здесь можно добавить логику отправки push-уведомлений
    res.json({ success: true, message: 'Уведомление отправлено' });
  } catch (error) {
    console.error('Ошибка отправки уведомления:', error);
    res.json({ success: true, message: 'Уведомление обработано' });
  }
});

// Статическая раздача фото
app.use('/shift-photos', express.static('/var/www/shift-photos'));

// Эндпоинт для отметки прихода
app.post('/api/attendance', async (req, res) => {
  try {
    console.log('POST /api/attendance:', JSON.stringify(req.body).substring(0, 200));
    
    const attendanceDir = '/var/www/attendance';
    if (!fs.existsSync(attendanceDir)) {
      fs.mkdirSync(attendanceDir, { recursive: true });
    }
    
    const recordId = req.body.id || `attendance_${Date.now()}`;
    const sanitizedId = recordId.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const recordFile = path.join(attendanceDir, `${sanitizedId}.json`);
    
    const recordData = {
      ...req.body,
      createdAt: new Date().toISOString(),
    };
    
    fs.writeFileSync(recordFile, JSON.stringify(recordData, null, 2), 'utf8');
    console.log('Отметка сохранена:', recordFile);
    
    // Отправляем push-уведомление админу
    try {
      // TODO: Реализовать отправку push-уведомления админу
      console.log('Push-уведомление отправлено админу');
    } catch (notifyError) {
      console.log('Ошибка отправки уведомления:', notifyError);
    }
    
    res.json({ 
      success: true, 
      message: 'Отметка успешно сохранена',
      recordId: sanitizedId
    });
  } catch (error) {
    console.error('Ошибка сохранения отметки:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message || 'Ошибка при сохранении отметки' 
    });
  }
});

// Эндпоинт для проверки отметки сегодня
app.get('/api/attendance/check', async (req, res) => {
  try {
    const employeeName = req.query.employeeName;
    if (!employeeName) {
      return res.json({ success: true, hasAttendance: false });
    }
    
    const attendanceDir = '/var/www/attendance';
    if (!fs.existsSync(attendanceDir)) {
      return res.json({ success: true, hasAttendance: false });
    }
    
    const today = new Date();
    const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

    const files = await fs.promises.readdir(attendanceDir);
    const jsonFiles = files.filter(f => f.endsWith('.json'));

    const readPromises = jsonFiles.map(async (file) => {
      try {
        const filePath = path.join(attendanceDir, file);
        const content = await fs.promises.readFile(filePath, 'utf8');
        return JSON.parse(content);
      } catch (e) {
        console.error(`Ошибка чтения файла ${file}:`, e);
        return null;
      }
    });

    const records = (await Promise.all(readPromises)).filter(r => r !== null);

    for (const record of records) {
      if (record.employeeName === employeeName) {
        const recordDate = new Date(record.timestamp);
        const recordDateStr = `${recordDate.getFullYear()}-${String(recordDate.getMonth() + 1).padStart(2, '0')}-${String(recordDate.getDate()).padStart(2, '0')}`;

        if (recordDateStr === todayStr) {
          return res.json({ success: true, hasAttendance: true });
        }
      }
    }
    
    res.json({ success: true, hasAttendance: false });
  } catch (error) {
    console.error('Ошибка проверки отметки:', error);
    res.json({ success: true, hasAttendance: false });
  }
});

// Эндпоинт для получения списка отметок
app.get('/api/attendance', async (req, res) => {
  try {
    console.log('GET /api/attendance:', req.query);
    
    const attendanceDir = '/var/www/attendance';
    const records = [];
    
    if (fs.existsSync(attendanceDir)) {
      const files = await fs.promises.readdir(attendanceDir);
      const jsonFiles = files.filter(f => f.endsWith('.json'));

      const readPromises = jsonFiles.map(async (file) => {
        try {
          const filePath = path.join(attendanceDir, file);
          const content = await fs.promises.readFile(filePath, 'utf8');
          return JSON.parse(content);
        } catch (e) {
          console.error(`Ошибка чтения файла ${file}:`, e);
          return null;
        }
      });

      const results = await Promise.all(readPromises);
      records.push(...results.filter(r => r !== null));
    }
      
      // Сортируем по дате (новые первыми)
      records.sort((a, b) => {
        const dateA = new Date(a.timestamp || a.createdAt || 0);
        const dateB = new Date(b.timestamp || b.createdAt || 0);
        return dateB - dateA;
      });
      
      // Применяем фильтры
      let filteredRecords = records;
      if (req.query.employeeName) {
        filteredRecords = filteredRecords.filter(r => 
          r.employeeName && r.employeeName.includes(req.query.employeeName)
        );
      }
      if (req.query.shopAddress) {
        filteredRecords = filteredRecords.filter(r => 
          r.shopAddress && r.shopAddress.includes(req.query.shopAddress)
        );
      }
      if (req.query.date) {
        const filterDate = new Date(req.query.date);
        filteredRecords = filteredRecords.filter(r => {
          const recordDate = new Date(r.timestamp || r.createdAt);
          return recordDate.toDateString() === filterDate.toDateString();
        });
      }
      
      return res.json({ success: true, records: filteredRecords });
    }
    
    res.json({ success: true, records: [] });
  } catch (error) {
    console.error('Ошибка получения отметок:', error);
    res.json({ success: true, records: [] });
  }
});

// Настройка multer для загрузки фото сотрудников
const employeePhotoStorage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = '/var/www/employee-photos';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    const phone = req.body.phone || 'unknown';
    const photoType = req.body.photoType || 'photo';
    const safeName = `${phone}_${photoType}.jpg`;
    cb(null, safeName);
  }
});

const uploadEmployeePhoto = multer({ 
  storage: employeePhotoStorage,
  limits: { fileSize: 10 * 1024 * 1024 } // 10MB
});

// Эндпоинт для загрузки фото сотрудника
app.post('/upload-employee-photo', uploadEmployeePhoto.single('file'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'Файл не загружен' });
    }

    const fileUrl = `https://arabica26.ru/employee-photos/${req.file.filename}`;
    console.log('Фото сотрудника загружено:', req.file.filename);
    
    res.json({
      success: true,
      url: fileUrl,
      filename: req.file.filename
    });
  } catch (error) {
    console.error('Ошибка загрузки фото сотрудника:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Эндпоинт для сохранения регистрации сотрудника
app.post('/api/employee-registration', async (req, res) => {
  try {
    console.log('POST /api/employee-registration:', JSON.stringify(req.body).substring(0, 200));
    
    const registrationDir = '/var/www/employee-registrations';
    if (!fs.existsSync(registrationDir)) {
      fs.mkdirSync(registrationDir, { recursive: true });
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
    if (fs.existsSync(registrationFile)) {
      try {
        const oldContent = fs.readFileSync(registrationFile, 'utf8');
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
    
    fs.writeFileSync(registrationFile, JSON.stringify(registrationData, null, 2), 'utf8');
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
app.get('/api/employee-registration/:phone', async (req, res) => {
  try {
    const phone = decodeURIComponent(req.params.phone);
    console.log('GET /api/employee-registration:', phone);
    
    const registrationDir = '/var/www/employee-registrations';
    const sanitizedPhone = phone.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const registrationFile = path.join(registrationDir, `${sanitizedPhone}.json`);
    
    if (!fs.existsSync(registrationFile)) {
      return res.json({ success: true, registration: null });
    }
    
    const content = fs.readFileSync(registrationFile, 'utf8');
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
app.post('/api/employee-registration/:phone/verify', async (req, res) => {
  try {
    const phone = decodeURIComponent(req.params.phone);
    const { isVerified, verifiedBy } = req.body;
    console.log('POST /api/employee-registration/:phone/verify:', phone, isVerified);
    
    const registrationDir = '/var/www/employee-registrations';
    const sanitizedPhone = phone.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const registrationFile = path.join(registrationDir, `${sanitizedPhone}.json`);
    
    if (!fs.existsSync(registrationFile)) {
      return res.status(404).json({
        success: false,
        error: 'Регистрация не найдена'
      });
    }
    
    const content = fs.readFileSync(registrationFile, 'utf8');
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
    
    fs.writeFileSync(registrationFile, JSON.stringify(registration, null, 2), 'utf8');
    console.log('Статус верификации обновлен:', registrationFile);
    
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
app.get('/api/employee-registrations', async (req, res) => {
  try {
    console.log('GET /api/employee-registrations');
    
    const registrationDir = '/var/www/employee-registrations';
    const registrations = [];
    
    if (fs.existsSync(registrationDir)) {
      const files = await fs.promises.readdir(registrationDir);
      const jsonFiles = files.filter(f => f.endsWith('.json'));

      const readPromises = jsonFiles.map(async (file) => {
        try {
          const filePath = path.join(registrationDir, file);
          const content = await fs.promises.readFile(filePath, 'utf8');
          return JSON.parse(content);
        } catch (e) {
          console.error(`Ошибка чтения файла ${file}:`, e);
          return null;
        }
      });

      const results = await Promise.all(readPromises);
      registrations.push(...results.filter(r => r !== null));

      // Сортируем по дате создания (новые первыми)
      registrations.sort((a, b) => {
        const dateA = new Date(a.createdAt || 0);
        const dateB = new Date(b.createdAt || 0);
        return dateB - dateA;
      });
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

// ========== API для настроек магазинов (РКО) ==========

// Получить настройки магазина
app.get('/api/shop-settings/:shopAddress', async (req, res) => {
  try {
    const shopAddress = decodeURIComponent(req.params.shopAddress);
    console.log('GET /api/shop-settings:', shopAddress);
    
    const settingsDir = '/var/www/shop-settings';
    if (!fs.existsSync(settingsDir)) {
      fs.mkdirSync(settingsDir, { recursive: true });
    }
    
    const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const settingsFile = path.join(settingsDir, `${sanitizedAddress}.json`);
    
    if (!fs.existsSync(settingsFile)) {
      return res.json({ 
        success: true, 
        settings: null 
      });
    }
    
    const content = fs.readFileSync(settingsFile, 'utf8');
    const settings = JSON.parse(content);
    
    res.json({ success: true, settings });
  } catch (error) {
    console.error('Ошибка получения настроек магазина:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении настроек магазина'
    });
  }
});

// Сохранить настройки магазина
app.post('/api/shop-settings', async (req, res) => {
  try {
    console.log('📝 POST /api/shop-settings');
    console.log('   Тело запроса:', JSON.stringify(req.body, null, 2));
    
    const settingsDir = '/var/www/shop-settings';
    console.log('   Проверка директории:', settingsDir);
    
    if (!fs.existsSync(settingsDir)) {
      console.log('   Создание директории:', settingsDir);
      fs.mkdirSync(settingsDir, { recursive: true });
      console.log('   ✅ Директория создана');
    } else {
      console.log('   ✅ Директория существует');
    }
    
    const shopAddress = req.body.shopAddress;
    if (!shopAddress) {
      console.log('   ❌ Адрес магазина не указан');
      return res.status(400).json({ 
        success: false, 
        error: 'Адрес магазина не указан' 
      });
    }
    
    console.log('   Адрес магазина:', shopAddress);
    const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
    console.log('   Очищенный адрес:', sanitizedAddress);
    
    const settingsFile = path.join(settingsDir, `${sanitizedAddress}.json`);
    console.log('   Файл настроек:', settingsFile);
    
    // Если файл существует, сохраняем lastDocumentNumber из старого файла
    let lastDocumentNumber = req.body.lastDocumentNumber || 0;
    if (fs.existsSync(settingsFile)) {
      try {
        console.log('   Чтение существующего файла...');
        const oldContent = fs.readFileSync(settingsFile, 'utf8');
        const oldSettings = JSON.parse(oldContent);
        if (oldSettings.lastDocumentNumber !== undefined) {
          lastDocumentNumber = oldSettings.lastDocumentNumber;
          console.log('   Сохранен lastDocumentNumber:', lastDocumentNumber);
        }
      } catch (e) {
        console.error('   ⚠️ Ошибка чтения старого файла:', e);
      }
    } else {
      console.log('   Файл не существует, будет создан новый');
    }
    
    const settings = {
      shopAddress: shopAddress,
      address: req.body.address || '',
      inn: req.body.inn || '',
      directorName: req.body.directorName || '',
      lastDocumentNumber: lastDocumentNumber,
      updatedAt: new Date().toISOString(),
    };
    
    if (fs.existsSync(settingsFile)) {
      try {
        const oldContent = fs.readFileSync(settingsFile, 'utf8');
        const oldSettings = JSON.parse(oldContent);
        if (oldSettings.createdAt) {
          settings.createdAt = oldSettings.createdAt;
          console.log('   Сохранена дата создания:', settings.createdAt);
        }
      } catch (e) {
        console.error('   ⚠️ Ошибка при чтении createdAt:', e);
      }
    } else {
      settings.createdAt = new Date().toISOString();
      console.log('   Установлена новая дата создания:', settings.createdAt);
    }
    
    console.log('   Сохранение настроек:', JSON.stringify(settings, null, 2));
    
    try {
      fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2), 'utf8');
      console.log('   ✅ Настройки магазина сохранены:', settingsFile);
      
      res.json({
        success: true,
        message: 'Настройки успешно сохранены'
      });
    } catch (writeError) {
      console.error('   ❌ Ошибка записи файла:', writeError);
      throw writeError;
    }
  } catch (error) {
    console.error('❌ Ошибка сохранения настроек магазина:', error);
    console.error('   Stack:', error.stack);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при сохранении настроек'
    });
  }
});

// Получить следующий номер документа для магазина
app.get('/api/shop-settings/:shopAddress/document-number', async (req, res) => {
  try {
    const shopAddress = decodeURIComponent(req.params.shopAddress);
    console.log('GET /api/shop-settings/:shopAddress/document-number:', shopAddress);
    
    const settingsDir = '/var/www/shop-settings';
    const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const settingsFile = path.join(settingsDir, `${sanitizedAddress}.json`);
    
    if (!fs.existsSync(settingsFile)) {
      return res.json({ 
        success: true, 
        documentNumber: 1 
      });
    }
    
    const content = fs.readFileSync(settingsFile, 'utf8');
    const settings = JSON.parse(content);
    
    let nextNumber = (settings.lastDocumentNumber || 0) + 1;
    if (nextNumber > 50000) {
      nextNumber = 1;
    }
    
    res.json({ 
      success: true, 
      documentNumber: nextNumber 
    });
  } catch (error) {
    console.error('Ошибка получения номера документа:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении номера документа'
    });
  }
});

// Обновить номер документа для магазина
app.post('/api/shop-settings/:shopAddress/document-number', async (req, res) => {
  try {
    const shopAddress = decodeURIComponent(req.params.shopAddress);
    const { documentNumber } = req.body;
    console.log('POST /api/shop-settings/:shopAddress/document-number:', shopAddress, documentNumber);
    
    const settingsDir = '/var/www/shop-settings';
    if (!fs.existsSync(settingsDir)) {
      fs.mkdirSync(settingsDir, { recursive: true });
    }
    
    const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const settingsFile = path.join(settingsDir, `${sanitizedAddress}.json`);
    
    let settings = {};
    if (fs.existsSync(settingsFile)) {
      const content = fs.readFileSync(settingsFile, 'utf8');
      settings = JSON.parse(content);
    } else {
      settings.shopAddress = shopAddress;
      settings.createdAt = new Date().toISOString();
    }
    
    settings.lastDocumentNumber = documentNumber || 0;
    settings.updatedAt = new Date().toISOString();
    
    fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2), 'utf8');
    console.log('Номер документа обновлен:', settingsFile);
    
    res.json({
      success: true,
      message: 'Номер документа успешно обновлен'
    });
  } catch (error) {
    console.error('Ошибка обновления номера документа:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при обновлении номера документа'
    });
  }
});

// ========== API для РКО отчетов ==========

const rkoReportsDir = '/var/www/rko-reports';
const rkoMetadataFile = path.join(rkoReportsDir, 'rko_metadata.json');

// Инициализация директорий для РКО
if (!fs.existsSync(rkoReportsDir)) {
  fs.mkdirSync(rkoReportsDir, { recursive: true });
}

// Загрузить метаданные РКО
function loadRKOMetadata() {
  try {
    if (fs.existsSync(rkoMetadataFile)) {
      const content = fs.readFileSync(rkoMetadataFile, 'utf8');
      return JSON.parse(content);
    }
    return { items: [] };
  } catch (e) {
    console.error('Ошибка загрузки метаданных РКО:', e);
    return { items: [] };
  }
}

// Сохранить метаданные РКО
function saveRKOMetadata(metadata) {
  try {
    fs.writeFileSync(rkoMetadataFile, JSON.stringify(metadata, null, 2), 'utf8');
  } catch (e) {
    console.error('Ошибка сохранения метаданных РКО:', e);
    throw e;
  }
}

// Очистка старых РКО для сотрудника (максимум 150)
function cleanupEmployeeRKOs(employeeName) {
  const metadata = loadRKOMetadata();
  const employeeRKOs = metadata.items.filter(rko => rko.employeeName === employeeName);
  
  if (employeeRKOs.length > 150) {
    // Сортируем по дате (старые первыми)
    employeeRKOs.sort((a, b) => new Date(a.date) - new Date(b.date));
    
    // Удаляем старые
    const toDelete = employeeRKOs.slice(0, employeeRKOs.length - 150);
    
    for (const rko of toDelete) {
      // Удаляем файл
      const monthKey = new Date(rko.date).toISOString().substring(0, 7); // YYYY-MM
      const sanitizedEmployee = employeeName.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const filePath = path.join(rkoReportsDir, 'employee', sanitizedEmployee, monthKey, rko.fileName);
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        console.log('Удален старый РКО:', filePath);
      }
      
      // Удаляем из метаданных
      metadata.items = metadata.items.filter(item => 
        !(item.employeeName === employeeName && item.fileName === rko.fileName)
      );
    }
    
    saveRKOMetadata(metadata);
  }
}

// Очистка старых РКО для магазина (максимум 6 месяцев)
function cleanupShopRKOs(shopAddress) {
  const metadata = loadRKOMetadata();
  const shopRKOs = metadata.items.filter(rko => rko.shopAddress === shopAddress);
  
  if (shopRKOs.length === 0) return;
  
  // Получаем уникальные месяцы
  const months = [...new Set(shopRKOs.map(rko => new Date(rko.date).toISOString().substring(0, 7)))];
  months.sort((a, b) => b.localeCompare(a)); // Новые первыми
  
  if (months.length > 6) {
    const monthsToDelete = months.slice(6);
    
    for (const monthKey of monthsToDelete) {
      const monthRKOs = shopRKOs.filter(rko => 
        new Date(rko.date).toISOString().substring(0, 7) === monthKey
      );
      
      for (const rko of monthRKOs) {
        // Удаляем файл
        const sanitizedEmployee = rko.employeeName.replace(/[^a-zA-Z0-9_\-]/g, '_');
        const filePath = path.join(rkoReportsDir, 'employee', sanitizedEmployee, monthKey, rko.fileName);
        if (fs.existsSync(filePath)) {
          fs.unlinkSync(filePath);
          console.log('Удален старый РКО магазина:', filePath);
        }
        
        // Удаляем из метаданных
        metadata.items = metadata.items.filter(item => 
          !(item.shopAddress === shopAddress && item.fileName === rko.fileName)
        );
      }
    }
    
    saveRKOMetadata(metadata);
  }
}

// Загрузка РКО на сервер
app.post('/api/rko/upload', upload.single('docx'), async (req, res) => {
  try {
    console.log('📤 POST /api/rko/upload');
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'DOCX файл не загружен'
      });
    }
    
    const { fileName, employeeName, shopAddress, date, amount, rkoType } = req.body;

    // SECURITY: Validate all required fields are present
    if (!fileName || !employeeName || !shopAddress || !date) {
      return res.status(400).json({
        success: false,
        error: 'Не все обязательные поля указаны'
      });
    }

    // SECURITY: Validate date format (ISO 8601)
    const dateRegex = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/;
    if (!dateRegex.test(date)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid date format. Expected ISO 8601'
      });
    }

    // SECURITY: Validate amount is a valid number
    const numAmount = parseFloat(amount);
    if (amount !== undefined && (isNaN(numAmount) || numAmount < 0)) {
      return res.status(400).json({
        success: false,
        error: 'Amount must be a valid non-negative number'
      });
    }

    // SECURITY: Validate fileName doesn't contain path traversal
    if (fileName.includes('..') || fileName.includes('/') || fileName.includes('\\')) {
      return res.status(400).json({
        success: false,
        error: 'Invalid fileName: path traversal detected'
      });
    }
    
    // Создаем структуру директорий
    const monthKey = new Date(date).toISOString().substring(0, 7); // YYYY-MM
    const sanitizedEmployee = employeeName.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const employeeDir = path.join(rkoReportsDir, 'employee', sanitizedEmployee, monthKey);
    
    if (!fs.existsSync(employeeDir)) {
      fs.mkdirSync(employeeDir, { recursive: true });
    }
    
    // Сохраняем файл
    const filePath = path.join(employeeDir, fileName);
    fs.renameSync(req.file.path, filePath);
    console.log('РКО сохранен:', filePath);
    
    // Добавляем метаданные
    const metadata = loadRKOMetadata();
    const newRKO = {
      fileName: fileName,
      employeeName: employeeName,
      shopAddress: shopAddress,
      date: date,
      amount: parseFloat(amount) || 0,
      rkoType: rkoType || '',
      createdAt: new Date().toISOString(),
    };
    
    // Удаляем старую запись, если существует
    metadata.items = metadata.items.filter(item => item.fileName !== fileName);
    metadata.items.push(newRKO);
    
    saveRKOMetadata(metadata);
    
    // Очистка старых РКО
    cleanupEmployeeRKOs(employeeName);
    cleanupShopRKOs(shopAddress);
    
    res.json({
      success: true,
      message: 'РКО успешно загружен'
    });
  } catch (error) {
    console.error('Ошибка загрузки РКО:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при загрузке РКО'
    });
  }
});

// Получить список РКО сотрудника
app.get('/api/rko/list/employee/:employeeName', async (req, res) => {
  try {
    const employeeName = decodeURIComponent(req.params.employeeName);
    console.log('📋 GET /api/rko/list/employee:', employeeName);
    
    const metadata = loadRKOMetadata();
    // Нормализуем имена для сравнения (приводим к нижнему регистру и убираем лишние пробелы)
    const normalizedSearchName = employeeName.toLowerCase().trim().replace(/\s+/g, ' ');
    const employeeRKOs = metadata.items
      .filter(rko => {
        const normalizedRkoName = (rko.employeeName || '').toLowerCase().trim().replace(/\s+/g, ' ');
        return normalizedRkoName === normalizedSearchName;
      })
      .sort((a, b) => new Date(b.date) - new Date(a.date));
    
    // Последние 25
    const latest = employeeRKOs.slice(0, 25);
    
    // Группировка по месяцам
    const monthsMap = {};
    employeeRKOs.forEach(rko => {
      const monthKey = new Date(rko.date).toISOString().substring(0, 7);
      if (!monthsMap[monthKey]) {
        monthsMap[monthKey] = [];
      }
      monthsMap[monthKey].push(rko);
    });
    
    const months = Object.keys(monthsMap).sort((a, b) => b.localeCompare(a));
    
    res.json({
      success: true,
      latest: latest,
      months: months.map(monthKey => ({
        monthKey: monthKey,
        items: monthsMap[monthKey],
      })),
    });
  } catch (error) {
    console.error('Ошибка получения списка РКО сотрудника:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении списка РКО'
    });
  }
});

// Получить список РКО магазина
app.get('/api/rko/list/shop/:shopAddress', async (req, res) => {
  try {
    const shopAddress = decodeURIComponent(req.params.shopAddress);
    console.log('📋 GET /api/rko/list/shop:', shopAddress);
    
    const metadata = loadRKOMetadata();
    const now = new Date();
    const currentMonth = now.toISOString().substring(0, 7); // YYYY-MM
    
    // РКО за текущий месяц
    const currentMonthRKOs = metadata.items
      .filter(rko => {
        const rkoMonth = new Date(rko.date).toISOString().substring(0, 7);
        return rko.shopAddress === shopAddress && rkoMonth === currentMonth;
      })
      .sort((a, b) => new Date(b.date) - new Date(a.date));
    
    // Группировка по месяцам
    const monthsMap = {};
    metadata.items
      .filter(rko => rko.shopAddress === shopAddress)
      .forEach(rko => {
        const monthKey = new Date(rko.date).toISOString().substring(0, 7);
        if (!monthsMap[monthKey]) {
          monthsMap[monthKey] = [];
        }
        monthsMap[monthKey].push(rko);
      });
    
    const months = Object.keys(monthsMap).sort((a, b) => b.localeCompare(a));
    
    res.json({
      success: true,
      currentMonth: currentMonthRKOs,
      months: months.map(monthKey => ({
        monthKey: monthKey,
        items: monthsMap[monthKey],
      })),
    });
  } catch (error) {
    console.error('Ошибка получения списка РКО магазина:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении списка РКО'
    });
  }
});

// Получить DOCX файл РКО
app.get('/api/rko/file/:fileName', async (req, res) => {
  try {
    // Декодируем имя файла, обрабатывая возможные проблемы с кодировкой
    let fileName;
    try {
      fileName = decodeURIComponent(req.params.fileName);
    } catch (e) {
      // Если декодирование не удалось, используем оригинальное имя
      fileName = req.params.fileName;
    }
    console.log('📄 GET /api/rko/file:', fileName);
    console.log('📄 Оригинальный параметр:', req.params.fileName);
    
    const metadata = loadRKOMetadata();
    const rko = metadata.items.find(item => item.fileName === fileName);
    
    if (!rko) {
      console.error('РКО не найден в метаданных для файла:', fileName);
      return res.status(404).json({
        success: false,
        error: 'РКО не найден'
      });
    }
    
    const monthKey = new Date(rko.date).toISOString().substring(0, 7);
    const sanitizedEmployee = rko.employeeName.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const filePath = path.join(rkoReportsDir, 'employee', sanitizedEmployee, monthKey, fileName);
    
    console.log('Ищем файл по пути:', filePath);
    
    if (!fs.existsSync(filePath)) {
      console.error('Файл не найден по пути:', filePath);
      // Попробуем найти файл в других местах
      const allFiles = [];
      function findFiles(dir, pattern) {
        try {
          const files = fs.readdirSync(dir);
          for (const file of files) {
            const filePath = path.join(dir, file);
            const stat = fs.statSync(filePath);
            if (stat.isDirectory()) {
              findFiles(filePath, pattern);
            } else if (file.includes(pattern) || file === pattern) {
              allFiles.push(filePath);
            }
          }
        } catch (e) {
          // Игнорируем ошибки
        }
      }
      findFiles(rkoReportsDir, fileName);
      if (allFiles.length > 0) {
        console.log('Найден файл в альтернативном месте:', allFiles[0]);
        res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
        // Правильно кодируем имя файла для заголовка (RFC 5987)
        const encodedFileName = encodeURIComponent(fileName);
        res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodedFileName}`);
        return res.sendFile(allFiles[0]);
      }
      return res.status(404).json({
        success: false,
        error: 'Файл РКО не найден'
      });
    }
    
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    // Правильно кодируем имя файла для заголовка (RFC 5987)
    const encodedFileName = encodeURIComponent(fileName);
    res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodedFileName}`);
    res.sendFile(filePath);
  } catch (error) {
    console.error('Ошибка получения файла РКО:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при получении файла РКО'
    });
  }
});

// Генерация РКО из .docx шаблона
app.post('/api/rko/generate-from-docx', async (req, res) => {
  try {
    const {
      shopAddress,
      shopSettings,
      documentNumber,
      employeeData,
      amount,
      rkoType
    } = req.body;
    
    console.log('📝 POST /api/rko/generate-from-docx');
    console.log('Данные:', {
      shopAddress,
      documentNumber,
      employeeName: employeeData?.fullName,
      amount,
      rkoType
    });
    
    // Путь к Word шаблону
    let templateDocxPath = path.join(__dirname, '..', '.cursor', 'rko_template_new.docx');
    console.log('🔍 Ищем Word шаблон по пути:', templateDocxPath);
    if (!fs.existsSync(templateDocxPath)) {
      console.error('❌ Word шаблон не найден по пути:', templateDocxPath);
      // Пробуем альтернативный путь
      const altPath = '/root/.cursor/rko_template_new.docx';
      if (fs.existsSync(altPath)) {
        console.log('✅ Найден альтернативный путь:', altPath);
        templateDocxPath = altPath;
      } else {
        return res.status(404).json({
          success: false,
          error: `Word шаблон rko_template_new.docx не найден. Проверенные пути: ${templateDocxPath}, ${altPath}`
        });
      }
    }
    
    // Создаем временную директорию для работы
    const tempDir = '/tmp/rko_generation';
    if (!fs.existsSync(tempDir)) {
      fs.mkdirSync(tempDir, { recursive: true });
    }
    
    const tempDocxPath = path.join(tempDir, `rko_${Date.now()}.docx`);
    
    // Форматируем данные для замены
    const now = new Date();
    const dateStr = `${now.getDate().toString().padStart(2, '0')}.${(now.getMonth() + 1).toString().padStart(2, '0')}.${now.getFullYear()}`;
    
    // Форматируем имя директора
    let directorDisplayName = shopSettings.directorName;
    if (!directorDisplayName.toUpperCase().startsWith('ИП ')) {
      const nameWithoutIP = directorDisplayName.replace(/^ИП\s*/i, '');
      directorDisplayName = `ИП ${nameWithoutIP}`;
    }
    
    // Создаем короткое имя директора (первые буквы инициалов)
    function shortenName(fullName) {
      const parts = fullName.replace(/^ИП\s*/i, '').trim().split(/\s+/);
      if (parts.length >= 2) {
        const lastName = parts[0];
        const initials = parts.slice(1).map(p => p.charAt(0).toUpperCase() + '.').join(' ');
        return `${lastName} ${initials}`;
      }
      return fullName;
    }
    
    const directorShortName = shortenName(directorDisplayName);
    
    // Форматируем дату в слова (например, "2 декабря 2025 г.")
    function formatDateWords(date) {
      const months = [
        'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
        'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
      ];
      const day = date.getDate();
      const month = months[date.getMonth()];
      const year = date.getFullYear();
      return `${day} ${month} ${year} г.`;
    }
    
    const dateWords = formatDateWords(now);
    
    // Конвертируем сумму в пропись (упрощенная версия)
    const amountWords = convertAmountToWords(amount);
    
    // Подготавливаем данные для Python скрипта (формат плейсхолдеров)
    // Извлекаем адрес без префикса "Фактический адрес:" для плейсхолдера {SHOP}
    const shopAddressClean = shopSettings.address.replace(/^Фактический адрес:\s*/i, '').trim();
    
    // Формируем паспортные данные в новом формате
    const passportFormatted = `Серия ${employeeData.passportSeries} Номер ${employeeData.passportNumber} Кем Выдан: ${employeeData.issuedBy} Дата Выдачи: ${employeeData.issueDate}`;
    
    const data = {
      org_name: `${directorDisplayName} ИНН: ${shopSettings.inn}`,
      org_address: `Фактический адрес: ${shopSettings.address}`,
      shop_address: shopAddressClean, // Адрес без префикса для {SHOP}
      inn: shopSettings.inn, // Отдельное поле для плейсхолдера {INN}
      doc_number: documentNumber.toString(),
      doc_date: dateStr,
      amount_numeric: amount.toString().split('.')[0],
      fio_receiver: employeeData.fullName,
      basis: 'Зароботная плата', // Всегда "Зароботная плата" для {BASIS}
      amount_text: amountWords,
      attachment: '', // Опционально
      head_position: 'ИП',
      head_name: directorShortName,
      receiver_amount_text: amountWords,
      date_text: dateWords,
      passport_info: passportFormatted, // Новый формат: "Серия ... Номер ... Кем Выдан: ... Дата Выдачи: ..."
      passport_issuer: `${employeeData.issuedBy} Дата выдачи: ${employeeData.issueDate}`,
      cashier_name: directorShortName
    };

    // Вызываем Python скрипт для обработки Word шаблона (БЕЗОПАСНО - без shell)
    const scriptPath = path.join(__dirname, 'rko_docx_processor.py');

    try {
      // Обработка Word шаблона через python-docx (использует execFile вместо exec для безопасности)
      console.log(`Выполняем обработку Word шаблона`);
      const { stdout: processOutput } = await execFilePromise(
        'python3',
        [scriptPath, 'process', templateDocxPath, tempDocxPath, JSON.stringify(data)]
      );

      const processResult = JSON.parse(processOutput);
      if (!processResult.success) {
        throw new Error(processResult.error || 'Ошибка обработки Word шаблона');
      }

      console.log('✅ Word документ успешно обработан');

      // Конвертируем DOCX в PDF
      const tempPdfPath = tempDocxPath.replace('.docx', '.pdf');
      console.log(`Конвертируем DOCX в PDF: ${tempDocxPath} -> ${tempPdfPath}`);

      try {
        const { stdout: convertOutput } = await execFilePromise(
          'python3',
          [scriptPath, 'convert', tempDocxPath, tempPdfPath]
        );
        
        const convertResult = JSON.parse(convertOutput);
        if (!convertResult.success) {
          throw new Error(convertResult.error || 'Ошибка конвертации в PDF');
        }
        
        console.log('✅ DOCX успешно сконвертирован в PDF');
        
        // Читаем PDF файл и отправляем
        const pdfBuffer = fs.readFileSync(tempPdfPath);
        
        // Очищаем временные файлы
        try {
          if (fs.existsSync(tempDocxPath)) fs.unlinkSync(tempDocxPath);
          if (fs.existsSync(tempPdfPath)) fs.unlinkSync(tempPdfPath);
        } catch (e) {
          console.error('Ошибка очистки временных файлов:', e);
        }
        
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', `attachment; filename="rko_${documentNumber}.pdf"`);
        res.send(pdfBuffer);
      } catch (convertError) {
        console.error('Ошибка конвертации в PDF:', convertError);
        // Если конвертация не удалась, отправляем DOCX
        console.log('Отправляем DOCX вместо PDF');
        const docxBuffer = fs.readFileSync(tempDocxPath);
        
        try {
          if (fs.existsSync(tempDocxPath)) fs.unlinkSync(tempDocxPath);
        } catch (e) {
          console.error('Ошибка очистки временных файлов:', e);
        }
        
        res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
        res.setHeader('Content-Disposition', `attachment; filename="rko_${documentNumber}.docx"`);
        res.send(docxBuffer);
      }
      
      } catch (error) {
      console.error('Ошибка выполнения Python скрипта:', error);
      // Очищаем временные файлы при ошибке
      try {
        if (fs.existsSync(tempDocxPath)) fs.unlinkSync(tempDocxPath);
      } catch (e) {}
      
      return res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при генерации РКО'
      });
    }
    
  } catch (error) {
    console.error('Ошибка генерации РКО PDF:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Ошибка при генерации РКО'
    });
  }
});

// Вспомогательная функция для конвертации суммы в пропись
function convertAmountToWords(amount) {
  const rubles = Math.floor(amount);
  const kopecks = Math.round((amount - rubles) * 100);
  
  const ones = ['', 'один', 'два', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'];
  const tens = ['', '', 'двадцать', 'тридцать', 'сорок', 'пятьдесят', 'шестьдесят', 'семьдесят', 'восемьдесят', 'девяносто'];
  const hundreds = ['', 'сто', 'двести', 'триста', 'четыреста', 'пятьсот', 'шестьсот', 'семьсот', 'восемьсот', 'девятьсот'];
  const teens = ['десять', 'одиннадцать', 'двенадцать', 'тринадцать', 'четырнадцать', 'пятнадцать', 'шестнадцать', 'семнадцать', 'восемнадцать', 'девятнадцать'];
  
  function numberToWords(n) {
    if (n === 0) return 'ноль';
    if (n < 10) return ones[n];
    if (n < 20) return teens[n - 10];
    if (n < 100) {
      const ten = Math.floor(n / 10);
      const one = n % 10;
      return tens[ten] + (one > 0 ? ' ' + ones[one] : '');
    }
    if (n < 1000) {
      const hundred = Math.floor(n / 100);
      const remainder = n % 100;
      return hundreds[hundred] + (remainder > 0 ? ' ' + numberToWords(remainder) : '');
    }
    if (n < 1000000) {
      const thousand = Math.floor(n / 1000);
      const remainder = n % 1000;
      let thousandWord = 'тысяч';
      if (thousand % 10 === 1 && thousand % 100 !== 11) thousandWord = 'тысяча';
      else if ([2, 3, 4].includes(thousand % 10) && ![12, 13, 14].includes(thousand % 100)) thousandWord = 'тысячи';
      return numberToWords(thousand) + ' ' + thousandWord + (remainder > 0 ? ' ' + numberToWords(remainder) : '');
    }
    return n.toString();
  }
  
  const rublesWord = numberToWords(rubles);
  let rubleWord = 'рублей';
  if (rubles % 10 === 1 && rubles % 100 !== 11) rubleWord = 'рубль';
  else if ([2, 3, 4].includes(rubles % 10) && ![12, 13, 14].includes(rubles % 100)) rubleWord = 'рубля';
  
  const kopecksStr = kopecks.toString().padStart(2, '0');
  return `${rublesWord} ${rubleWord} ${kopecksStr} копеек`;
}

// Endpoint для редактора координат
app.get('/rko_coordinates_editor.html', (req, res) => {
  res.sendFile('/var/www/html/rko_coordinates_editor.html');
});

// Endpoint для координат HTML
app.get('/coordinates.html', (req, res) => {
  res.sendFile('/var/www/html/coordinates.html');
});

// Endpoint для тестового PDF
app.get('/test_rko_corrected.pdf', (req, res) => {
  res.sendFile('/var/www/html/test_rko_corrected.pdf');
});

// Endpoint для изображения шаблона
app.get('/rko_template.jpg', (req, res) => {
  res.sendFile('/var/www/html/rko_template.jpg');
});

// Endpoint для финального тестового PDF
app.get('/test_rko_final.pdf', (req, res) => {
  res.setHeader('Content-Type', 'application/pdf');
  res.sendFile('/var/www/html/test_rko_final.pdf');
});

// Endpoint для нового тестового PDF с исправленными координатами
app.get('/test_rko_new_coords.pdf', (req, res) => {
  res.setHeader('Content-Type', 'application/pdf');
  res.sendFile('/var/www/html/test_rko_new_coords.pdf');
});

// Endpoint для тестового РКО КО-2 с фиксированными высотами
app.get('/test_rko_ko2_fixed.docx', (req, res) => {
  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
  res.setHeader('Content-Disposition', 'inline; filename="test_rko_ko2_fixed.docx"');
  res.sendFile('/var/www/html/test_rko_ko2_fixed.docx');
});

// ==================== API для графика работы ====================

const WORK_SCHEDULES_DIR = '/var/www/work-schedules';
const WORK_SCHEDULE_TEMPLATES_DIR = '/var/www/work-schedule-templates';

// Создаем директории, если их нет
if (!fs.existsSync(WORK_SCHEDULES_DIR)) {
  fs.mkdirSync(WORK_SCHEDULES_DIR, { recursive: true });
}
if (!fs.existsSync(WORK_SCHEDULE_TEMPLATES_DIR)) {
  fs.mkdirSync(WORK_SCHEDULE_TEMPLATES_DIR, { recursive: true });
}

// Вспомогательная функция для получения файла графика
function getScheduleFilePath(month) {
  return path.join(WORK_SCHEDULES_DIR, `${month}.json`);
}

// Вспомогательная функция для загрузки графика
function loadSchedule(month) {
  const filePath = getScheduleFilePath(month);
  if (fs.existsSync(filePath)) {
    try {
      const data = fs.readFileSync(filePath, 'utf8');
      return JSON.parse(data);
    } catch (error) {
      console.error('Ошибка чтения графика:', error);
      return { month, entries: [] };
    }
  }
  return { month, entries: [] };
}

// Вспомогательная функция для сохранения графика
function saveSchedule(schedule) {
  const filePath = getScheduleFilePath(schedule.month);
  try {
    fs.writeFileSync(filePath, JSON.stringify(schedule, null, 2), 'utf8');
    return true;
  } catch (error) {
    console.error('Ошибка сохранения графика:', error);
    return false;
  }
}

// GET /api/work-schedule?month=YYYY-MM - получить график на месяц
app.get('/api/work-schedule', (req, res) => {
  try {
    const month = req.query.month;
    if (!month) {
      return res.status(400).json({ success: false, error: 'Не указан месяц (month)' });
    }

    const schedule = loadSchedule(month);
    console.log(`📥 Загружен график для ${month}: ${schedule.entries.length} записей`);
    res.json({ success: true, schedule });
  } catch (error) {
    console.error('Ошибка получения графика:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/work-schedule/employee/:employeeId?month=YYYY-MM - график сотрудника
app.get('/api/work-schedule/employee/:employeeId', (req, res) => {
  try {
    const employeeId = req.params.employeeId;
    const month = req.query.month;
    if (!month) {
      return res.status(400).json({ success: false, error: 'Не указан месяц (month)' });
    }

    const schedule = loadSchedule(month);
    const employeeEntries = schedule.entries.filter(e => e.employeeId === employeeId);
    const employeeSchedule = { month, entries: employeeEntries };
    
    res.json({ success: true, schedule: employeeSchedule });
  } catch (error) {
    console.error('Ошибка получения графика сотрудника:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/work-schedule - создать/обновить смену
app.post('/api/work-schedule', (req, res) => {
  try {
    const entry = req.body;
    if (!entry.month || !entry.employeeId || !entry.date || !entry.shiftType) {
      return res.status(400).json({ 
        success: false, 
        error: 'Не указаны обязательные поля: month, employeeId, date, shiftType' 
      });
    }

    const month = entry.month;
    const schedule = loadSchedule(month);
    
    // Генерируем ID, если его нет
    if (!entry.id) {
      entry.id = `entry_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }

    // Удаляем старую запись для этого сотрудника, даты и типа смены, если есть
    schedule.entries = schedule.entries.filter(e => 
      !(e.employeeId === entry.employeeId && 
        e.date === entry.date && 
        e.shiftType === entry.shiftType)
    );

    // Добавляем новую запись
    schedule.entries.push(entry);
    schedule.month = month;

    if (saveSchedule(schedule)) {
      res.json({ success: true, entry });
    } else {
      res.status(500).json({ success: false, error: 'Ошибка сохранения графика' });
    }
  } catch (error) {
    console.error('Ошибка сохранения смены:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/work-schedule/:entryId - удалить смену
app.delete('/api/work-schedule/:entryId', (req, res) => {
  try {
    const entryId = req.params.entryId;
    const month = req.query.month;
    
    if (!month) {
      return res.status(400).json({ success: false, error: 'Не указан месяц (month)' });
    }

    const schedule = loadSchedule(month);
    const initialLength = schedule.entries.length;
    schedule.entries = schedule.entries.filter(e => e.id !== entryId);

    if (schedule.entries.length < initialLength) {
      if (saveSchedule(schedule)) {
        res.json({ success: true, message: 'Смена удалена' });
      } else {
        res.status(500).json({ success: false, error: 'Ошибка сохранения графика' });
      }
    } else {
      res.status(404).json({ success: false, error: 'Смена не найдена' });
    }
  } catch (error) {
    console.error('Ошибка удаления смены:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/work-schedule/bulk - массовое создание смен
app.post('/api/work-schedule/bulk', (req, res) => {
  try {
    const entries = req.body.entries;
    if (!Array.isArray(entries) || entries.length === 0) {
      return res.status(400).json({ 
        success: false, 
        error: 'Не указаны записи (entries)' 
      });
    }

    // Группируем по месяцам
    const schedulesByMonth = {};
    entries.forEach((entry, index) => {
      if (!entry.month) {
        // Извлекаем месяц из даты
        const date = new Date(entry.date);
        entry.month = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
      }

      if (!schedulesByMonth[entry.month]) {
        schedulesByMonth[entry.month] = loadSchedule(entry.month);
      }

      // Генерируем уникальный ID, если его нет
      if (!entry.id) {
        entry.id = `entry_${Date.now()}_${index}_${Math.random().toString(36).substr(2, 9)}`;
      }

      // Удаляем старую запись для этого сотрудника, даты и типа смены, если есть
      schedulesByMonth[entry.month].entries = schedulesByMonth[entry.month].entries.filter(e => 
        !(e.employeeId === entry.employeeId && 
          e.date === entry.date && 
          e.shiftType === entry.shiftType)
      );

      // Добавляем новую запись
      schedulesByMonth[entry.month].entries.push(entry);
    });
    
    console.log(`📊 Массовое создание: обработано ${entries.length} записей, сохранено в ${Object.keys(schedulesByMonth).length} месяцах`);

    // Сохраняем все графики
    let allSaved = true;
    let totalSaved = 0;
    for (const month in schedulesByMonth) {
      const schedule = schedulesByMonth[month];
      if (saveSchedule(schedule)) {
        totalSaved += schedule.entries.length;
        console.log(`✅ Сохранен график для ${month}: ${schedule.entries.length} записей`);
      } else {
        allSaved = false;
        console.error(`❌ Ошибка сохранения графика для ${month}`);
      }
    }

    if (allSaved) {
      console.log(`✅ Всего сохранено записей в графиках: ${totalSaved}`);
      res.json({ success: true, message: `Создано ${entries.length} смен, всего в графиках: ${totalSaved}` });
    } else {
      res.status(500).json({ success: false, error: 'Ошибка сохранения некоторых графиков' });
    }
  } catch (error) {
    console.error('Ошибка массового создания смен:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/work-schedule/template - сохранить/применить шаблон
app.post('/api/work-schedule/template', (req, res) => {
  try {
    const action = req.body.action; // 'save' или 'apply'
    const template = req.body.template;

    if (action === 'save') {
      if (!template || !template.name) {
        return res.status(400).json({ 
          success: false, 
          error: 'Не указан шаблон или его название' 
        });
      }

      // Генерируем ID, если его нет
      if (!template.id) {
        template.id = `template_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      const templateFile = path.join(WORK_SCHEDULE_TEMPLATES_DIR, `${template.id}.json`);
      fs.writeFileSync(templateFile, JSON.stringify(template, null, 2), 'utf8');
      
      res.json({ success: true, template });
    } else if (action === 'apply') {
      // Применение шаблона обрабатывается на клиенте
      res.json({ success: true, message: 'Шаблон применен' });
    } else {
      res.status(400).json({ success: false, error: 'Неизвестное действие' });
    }
  } catch (error) {
    console.error('Ошибка работы с шаблоном:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/work-schedule/template - получить список шаблонов
app.get('/api/work-schedule/template', (req, res) => {
  try {
    const templates = [];
    
    if (fs.existsSync(WORK_SCHEDULE_TEMPLATES_DIR)) {
      const files = fs.readdirSync(WORK_SCHEDULE_TEMPLATES_DIR);
      files.forEach(file => {
        if (file.endsWith('.json')) {
          try {
            const filePath = path.join(WORK_SCHEDULE_TEMPLATES_DIR, file);
            const data = fs.readFileSync(filePath, 'utf8');
            const template = JSON.parse(data);
            templates.push(template);
          } catch (error) {
            console.error(`Ошибка чтения шаблона ${file}:`, error);
          }
        }
      });
    }

    res.json({ success: true, templates });
  } catch (error) {
    console.error('Ошибка получения шаблонов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ========== API для поставщиков ==========

const SUPPLIERS_DIR = '/var/www/suppliers';

// GET /api/suppliers - получить всех поставщиков
app.get('/api/suppliers', async (req, res) => {
  try {
    console.log('GET /api/suppliers');

    const suppliers = [];

    if (!fs.existsSync(SUPPLIERS_DIR)) {
      fs.mkdirSync(SUPPLIERS_DIR, { recursive: true });
    }

    const files = await fs.promises.readdir(SUPPLIERS_DIR);
    const jsonFiles = files.filter(f => f.endsWith('.json'));

    const readPromises = jsonFiles.map(async (file) => {
      try {
        const filePath = path.join(SUPPLIERS_DIR, file);
        const content = await fs.promises.readFile(filePath, 'utf8');
        return JSON.parse(content);
      } catch (e) {
        console.error(`Ошибка чтения файла ${file}:`, e);
        return null;
      }
    });

    const results = await Promise.all(readPromises);
    suppliers.push(...results.filter(r => r !== null));

    // Сортируем по дате создания (новые первыми)
    suppliers.sort((a, b) => {
      const dateA = new Date(a.createdAt || 0);
      const dateB = new Date(b.createdAt || 0);
      return dateB - dateA;
    });
    
    res.json({ success: true, suppliers });
  } catch (error) {
    console.error('Ошибка получения поставщиков:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/suppliers/:id - получить поставщика по ID
app.get('/api/suppliers/:id', (req, res) => {
  try {
    const id = req.params.id;
    console.log('GET /api/suppliers:', id);
    
    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const supplierFile = path.join(SUPPLIERS_DIR, `${sanitizedId}.json`);
    
    if (!fs.existsSync(supplierFile)) {
      return res.status(404).json({
        success: false,
        error: 'Поставщик не найден'
      });
    }
    
    const content = fs.readFileSync(supplierFile, 'utf8');
    const supplier = JSON.parse(content);
    
    res.json({ success: true, supplier });
  } catch (error) {
    console.error('Ошибка получения поставщика:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/suppliers - создать нового поставщика
app.post('/api/suppliers', async (req, res) => {
  try {
    console.log('POST /api/suppliers:', JSON.stringify(req.body).substring(0, 200));
    
    if (!fs.existsSync(SUPPLIERS_DIR)) {
      fs.mkdirSync(SUPPLIERS_DIR, { recursive: true });
    }
    
    // Валидация обязательных полей
    if (!req.body.name || req.body.name.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Наименование поставщика обязательно'
      });
    }
    
    if (!req.body.legalType || (req.body.legalType !== 'ООО' && req.body.legalType !== 'ИП')) {
      return res.status(400).json({
        success: false,
        error: 'Тип организации должен быть "ООО" или "ИП"'
      });
    }
    
    if (!req.body.paymentType || (req.body.paymentType !== 'Нал' && req.body.paymentType !== 'БезНал')) {
      return res.status(400).json({
        success: false,
        error: 'Тип оплаты должен быть "Нал" или "БезНал"'
      });
    }
    
    // Генерируем ID если не указан
    const id = req.body.id || `supplier_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const supplierFile = path.join(SUPPLIERS_DIR, `${sanitizedId}.json`);
    
    const supplier = {
      id: sanitizedId,
      name: req.body.name.trim(),
      inn: req.body.inn ? req.body.inn.trim() : null,
      legalType: req.body.legalType,
      deliveryDays: req.body.deliveryDays || [],
      phone: req.body.phone ? req.body.phone.trim() : null,
      paymentType: req.body.paymentType,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    
    fs.writeFileSync(supplierFile, JSON.stringify(supplier, null, 2), 'utf8');
    console.log('Поставщик создан:', supplierFile);
    
    res.json({ success: true, supplier });
  } catch (error) {
    console.error('Ошибка создания поставщика:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/suppliers/:id - обновить поставщика
app.put('/api/suppliers/:id', async (req, res) => {
  try {
    const id = req.params.id;
    console.log('PUT /api/suppliers:', id);
    
    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const supplierFile = path.join(SUPPLIERS_DIR, `${sanitizedId}.json`);
    
    if (!fs.existsSync(supplierFile)) {
      return res.status(404).json({
        success: false,
        error: 'Поставщик не найден'
      });
    }
    
    // Валидация обязательных полей
    if (!req.body.name || req.body.name.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Наименование поставщика обязательно'
      });
    }
    
    if (!req.body.legalType || (req.body.legalType !== 'ООО' && req.body.legalType !== 'ИП')) {
      return res.status(400).json({
        success: false,
        error: 'Тип организации должен быть "ООО" или "ИП"'
      });
    }
    
    if (!req.body.paymentType || (req.body.paymentType !== 'Нал' && req.body.paymentType !== 'БезНал')) {
      return res.status(400).json({
        success: false,
        error: 'Тип оплаты должен быть "Нал" или "БезНал"'
      });
    }
    
    // Читаем существующие данные для сохранения createdAt
    const oldContent = fs.readFileSync(supplierFile, 'utf8');
    const oldSupplier = JSON.parse(oldContent);
    
    const supplier = {
      id: sanitizedId,
      name: req.body.name.trim(),
      inn: req.body.inn ? req.body.inn.trim() : null,
      legalType: req.body.legalType,
      deliveryDays: req.body.deliveryDays || [],
      phone: req.body.phone ? req.body.phone.trim() : null,
      paymentType: req.body.paymentType,
      createdAt: oldSupplier.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    
    fs.writeFileSync(supplierFile, JSON.stringify(supplier, null, 2), 'utf8');
    console.log('Поставщик обновлен:', supplierFile);
    
    res.json({ success: true, supplier });
  } catch (error) {
    console.error('Ошибка обновления поставщика:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/suppliers/:id - удалить поставщика
app.delete('/api/suppliers/:id', (req, res) => {
  try {
    const id = req.params.id;
    console.log('DELETE /api/suppliers:', id);
    
    const sanitizedId = id.replace(/[^a-zA-Z0-9_\-]/g, '_');
    const supplierFile = path.join(SUPPLIERS_DIR, `${sanitizedId}.json`);
    
    if (!fs.existsSync(supplierFile)) {
      return res.status(404).json({
        success: false,
        error: 'Поставщик не найден'
      });
    }
    
    fs.unlinkSync(supplierFile);
    console.log('Поставщик удален:', supplierFile);
    
    res.json({ success: true, message: 'Поставщик удален' });
  } catch (error) {
    console.error('Ошибка удаления поставщика:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Директория для хранения клиентов
const CLIENTS_DIR = '/var/www/clients';
if (!fs.existsSync(CLIENTS_DIR)) {
  fs.mkdirSync(CLIENTS_DIR, { recursive: true });
}

// GET /api/clients - получить всех клиентов
app.get('/api/clients', async (req, res) => {
  try {
    const clients = [];
    if (fs.existsSync(CLIENTS_DIR)) {
      const files = await fs.promises.readdir(CLIENTS_DIR);
      const jsonFiles = files.filter(f => f.endsWith('.json'));

      const readPromises = jsonFiles.map(async (file) => {
        try {
          const content = await fs.promises.readFile(path.join(CLIENTS_DIR, file), 'utf8');
          return JSON.parse(content);
        } catch (e) {
          console.error(`Ошибка чтения файла ${file}:`, e);
          return null;
        }
      });

      const results = await Promise.all(readPromises);
      clients.push(...results.filter(r => r !== null));
    }
    res.json({ success: true, clients });
  } catch (error) {
    console.error('Ошибка получения клиентов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/clients - создать/обновить клиента
app.post('/api/clients', async (req, res) => {
  try {
    console.log('POST /api/clients:', JSON.stringify(req.body).substring(0, 200));
    
    if (!req.body.phone) {
      return res.status(400).json({
        success: false,
        error: 'Номер телефона обязателен'
      });
    }
    
    // Нормализуем номер телефона
    const normalizedPhone = req.body.phone.replace(/[\s\+]/g, '');
    const sanitizedPhone = normalizedPhone.replace(/[^0-9]/g, '_');
    const clientFile = path.join(CLIENTS_DIR, `${sanitizedPhone}.json`);
    
    const client = {
      phone: normalizedPhone,
      name: req.body.name || '',
      clientName: req.body.clientName || req.body.name || '',
      isAdmin: req.body.isAdmin || false,
      employeeName: req.body.employeeName || '',
      fcmToken: req.body.fcmToken || null,
      createdAt: fs.existsSync(clientFile) ? JSON.parse(fs.readFileSync(clientFile, 'utf8')).createdAt : new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    
    fs.writeFileSync(clientFile, JSON.stringify(client, null, 2), 'utf8');
    console.log('Клиент сохранен:', clientFile);
    
    res.json({ success: true, client });
  } catch (error) {
    console.error('Ошибка сохранения клиента:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.listen(3000, () => console.log("Proxy listening on port 3000"));

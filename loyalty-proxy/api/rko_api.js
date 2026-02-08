/**
 * RKO API
 * РКО отчеты - генерация, загрузка, просмотр
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fs = require('fs');
const fsp = require('fs').promises;
const path = require('path');
const { fileExists, isPathSafe } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const rkoReportsDir = `${DATA_DIR}/rko-reports`;
const rkoMetadataFile = path.join(rkoReportsDir, 'rko_metadata.json');

// Инициализация директорий для РКО
(async () => {
  if (!await fileExists(rkoReportsDir)) {
    await fsp.mkdir(rkoReportsDir, { recursive: true });
  }
})();

// Загрузить метаданные РКО
async function loadRKOMetadata() {
  try {
    if (await fileExists(rkoMetadataFile)) {
      const content = await fsp.readFile(rkoMetadataFile, 'utf8');
      return JSON.parse(content);
    }
    return { items: [] };
  } catch (e) {
    console.error('Ошибка загрузки метаданных РКО:', e);
    return { items: [] };
  }
}

// Сохранить метаданные РКО
async function saveRKOMetadata(metadata) {
  try {
    await fsp.writeFile(rkoMetadataFile, JSON.stringify(metadata, null, 2), 'utf8');
  } catch (e) {
    console.error('Ошибка сохранения метаданных РКО:', e);
    throw e;
  }
}

// Очистка старых РКО для сотрудника (максимум 150)
async function cleanupEmployeeRKOs(employeeName) {
  const metadata = await loadRKOMetadata();
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
      if (await fileExists(filePath)) {
        await fsp.unlink(filePath);
        console.log('Удален старый РКО:', filePath);
      }

      // Удаляем из метаданных
      metadata.items = metadata.items.filter(item =>
        !(item.employeeName === employeeName && item.fileName === rko.fileName)
      );
    }

    await saveRKOMetadata(metadata);
  }
}

// Очистка старых РКО для магазина (максимум 6 месяцев)
async function cleanupShopRKOs(shopAddress) {
  const metadata = await loadRKOMetadata();
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
        if (await fileExists(filePath)) {
          await fsp.unlink(filePath);
          console.log('Удален старый РКО магазина:', filePath);
        }

        // Удаляем из метаданных
        metadata.items = metadata.items.filter(item =>
          !(item.shopAddress === shopAddress && item.fileName === rko.fileName)
        );
      }
    }

    await saveRKOMetadata(metadata);
  }
}

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

function setupRkoAPI(app, { uploadRKO, spawnPython, getPendingRkoReports, getFailedRkoReports } = {}) {
  // Загрузка РКО на сервер
  app.post('/api/rko/upload', uploadRKO ? uploadRKO.single('docx') : (req, res, next) => next(), async (req, res) => {
    try {
      console.log('📤 POST /api/rko/upload');

      if (!req.file) {
        return res.status(400).json({
          success: false,
          error: 'DOCX файл не загружен'
        });
      }

      const { fileName, employeeName, shopAddress, date, amount, rkoType } = req.body;

      if (!fileName || !employeeName || !shopAddress || !date) {
        return res.status(400).json({
          success: false,
          error: 'Не все обязательные поля указаны'
        });
      }

      // Создаем структуру директорий
      const monthKey = new Date(date).toISOString().substring(0, 7); // YYYY-MM
      const sanitizedEmployee = employeeName.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const employeeDir = path.join(rkoReportsDir, 'employee', sanitizedEmployee, monthKey);

      if (!await fileExists(employeeDir)) {
        await fsp.mkdir(employeeDir, { recursive: true });
      }

      // SECURITY: Sanitize fileName для предотвращения path traversal
      const safeFileName = path.basename(fileName).replace(/[^a-zA-Z0-9_\-\.а-яА-ЯёЁ]/g, '_');
      const filePath = path.join(employeeDir, safeFileName);
      if (!isPathSafe(employeeDir, filePath)) {
        return res.status(400).json({ success: false, error: 'Invalid file name' });
      }
      fs.renameSync(req.file.path, filePath);
      console.log('РКО сохранен:', filePath);

      // Добавляем метаданные
      const metadata = await loadRKOMetadata();
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

      await saveRKOMetadata(metadata);

      // Очистка старых РКО
      await cleanupEmployeeRKOs(employeeName);
      await cleanupShopRKOs(shopAddress);

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

      const metadata = await loadRKOMetadata();
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

      const metadata = await loadRKOMetadata();
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

  // Получить все РКО за месяц (для эффективности)
  app.get('/api/rko/all', async (req, res) => {
    try {
      const { month } = req.query; // YYYY-MM
      console.log('📋 GET /api/rko/all, month:', month);

      const metadata = await loadRKOMetadata();

      let items = metadata.items || [];

      // Фильтруем по месяцу если указан
      if (month) {
        items = items.filter(rko => {
          const rkoMonth = new Date(rko.date).toISOString().substring(0, 7);
          return rkoMonth === month;
        });
      }

      // Сортируем по дате (новые первыми)
      items.sort((a, b) => new Date(b.date) - new Date(a.date));

      console.log(`✅ Найдено ${items.length} РКО${month ? ` за ${month}` : ''}`);

      res.json({
        success: true,
        items: items,
        count: items.length,
      });
    } catch (error) {
      console.error('Ошибка получения всех РКО:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при получении РКО'
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

      const metadata = await loadRKOMetadata();
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

      if (!await fileExists(filePath)) {
        console.error('Файл не найден по пути:', filePath);
        // Попробуем найти файл в других местах
        const allFiles = [];
        async function findFiles(dir, pattern) {
          try {
            const files = await fsp.readdir(dir);
            for (const file of files) {
              const filePath = path.join(dir, file);
              const stat = await fsp.stat(filePath);
              if (stat.isDirectory()) {
                await findFiles(filePath, pattern);
              } else if (file.includes(pattern) || file === pattern) {
                allFiles.push(filePath);
              }
            }
          } catch (e) {
            // Игнорируем ошибки
          }
        }
        await findFiles(rkoReportsDir, fileName);
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
      if (!await fileExists(templateDocxPath)) {
        console.error('❌ Word шаблон не найден по пути:', templateDocxPath);
        // Пробуем альтернативный путь
        const altPath = '/root/.cursor/rko_template_new.docx';
        if (await fileExists(altPath)) {
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
      if (!await fileExists(tempDir)) {
        await fsp.mkdir(tempDir, { recursive: true });
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

      // Вызываем Python скрипт для обработки Word шаблона
      const scriptPath = path.join(__dirname, 'rko_docx_processor.py');
      const dataJson = JSON.stringify(data); // Без экранирования - spawn передаёт аргументы безопасно

      try {
        // Обработка Word шаблона через python-docx (используем spawn для защиты от Command Injection)
        console.log(`Выполняем обработку Word шаблона: ${scriptPath} process`);
        const { stdout: processOutput } = await spawnPython([
          scriptPath, 'process', templateDocxPath, tempDocxPath, dataJson
        ]);

        const processResult = JSON.parse(processOutput);
        if (!processResult.success) {
          throw new Error(processResult.error || 'Ошибка обработки Word шаблона');
        }

        console.log('✅ Word документ успешно обработан');

        // Конвертируем DOCX в PDF
        const tempPdfPath = tempDocxPath.replace('.docx', '.pdf');
        console.log(`Конвертируем DOCX в PDF: ${tempDocxPath} -> ${tempPdfPath}`);

        try {
          // Конвертация DOCX в PDF (используем spawn для защиты от Command Injection)
          const { stdout: convertOutput } = await spawnPython([
            scriptPath, 'convert', tempDocxPath, tempPdfPath
          ]);

          const convertResult = JSON.parse(convertOutput);
          if (!convertResult.success) {
            throw new Error(convertResult.error || 'Ошибка конвертации в PDF');
          }

          console.log('✅ DOCX успешно сконвертирован в PDF');

          // Читаем PDF файл и отправляем
          const pdfBuffer = await fsp.readFile(tempPdfPath);

          // Очищаем временные файлы
          try {
            if (await fileExists(tempDocxPath)) await fsp.unlink(tempDocxPath);
            if (await fileExists(tempPdfPath)) await fsp.unlink(tempPdfPath);
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
          const docxBuffer = await fsp.readFile(tempDocxPath);

          try {
            if (await fileExists(tempDocxPath)) await fsp.unlink(tempDocxPath);
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
          if (await fileExists(tempDocxPath)) await fsp.unlink(tempDocxPath);
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

  // ========== API для pending/failed РКО отчетов ==========

  // Получить pending РКО отчеты
  app.get('/api/rko/pending', async (req, res) => {
    try {
      console.log('📋 GET /api/rko/pending');
      const reports = getPendingRkoReports ? getPendingRkoReports() : [];
      res.json({
        success: true,
        items: reports,
        count: reports.length
      });
    } catch (error) {
      console.error('Ошибка получения pending РКО:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при получении pending РКО'
      });
    }
  });

  // Получить failed РКО отчеты
  app.get('/api/rko/failed', async (req, res) => {
    try {
      console.log('📋 GET /api/rko/failed');
      const reports = getFailedRkoReports ? getFailedRkoReports() : [];
      res.json({
        success: true,
        items: reports,
        count: reports.length
      });
    } catch (error) {
      console.error('Ошибка получения failed РКО:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при получении failed РКО'
      });
    }
  });

  console.log('✅ RKO API initialized');
}

module.exports = { setupRkoAPI };

const fs = require('fs');
const path = require('path');

const ATTENDANCE_DIR = '/var/www/attendance';

if (!fs.existsSync(ATTENDANCE_DIR)) {
  fs.mkdirSync(ATTENDANCE_DIR, { recursive: true });
}

function setupAttendanceAPI(app) {
  // POST /api/attendance - поддерживает оба формата:
  // 1. Старый: { phone, action, shopAddress, timestamp, coordinates }
  // 2. Flutter: { id, employeeName, shopAddress, timestamp, latitude, longitude, distance }
  app.post('/api/attendance', async (req, res) => {
    try {
      const {
        // Старый формат
        phone, action, coordinates, photoPath,
        // Flutter формат
        id, employeeName, latitude, longitude, distance,
        // Общие поля
        shopAddress, timestamp
      } = req.body;

      // Определяем идентификатор (phone или employeeName)
      const identifier = phone || employeeName;
      console.log('POST /api/attendance:', identifier, shopAddress);

      if (!identifier) {
        return res.status(400).json({
          success: false,
          error: 'Требуется phone или employeeName'
        });
      }

      // Нормализуем идентификатор для имени файла
      const normalizedId = identifier.replace(/[\s+]/g, '_').replace(/[^a-zA-Zа-яА-Я0-9_]/g, '');
      const today = new Date().toISOString().split('T')[0];
      const filePath = path.join(ATTENDANCE_DIR, `${normalizedId}_${today}.json`);

      let attendance = {
        identifier: identifier,
        date: today,
        records: []
      };

      if (fs.existsSync(filePath)) {
        attendance = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      }

      // Создаем запись в унифицированном формате
      const record = {
        id: id || `att_${Date.now()}`,
        action: action || 'check-in',
        shopAddress,
        timestamp: timestamp || new Date().toISOString(),
        employeeName: employeeName || null,
        latitude: latitude || (coordinates ? coordinates.latitude : null),
        longitude: longitude || (coordinates ? coordinates.longitude : null),
        distance: distance || null,
        photoPath: photoPath || null
      };

      attendance.records.push(record);

      fs.writeFileSync(filePath, JSON.stringify(attendance, null, 2), 'utf8');

      // Возвращаем результат с информацией о времени
      res.json({
        success: true,
        attendance,
        isOnTime: true, // TODO: проверять по графику смен
        message: `Отметка сохранена: ${shopAddress}`
      });
    } catch (error) {
      console.error('Error saving attendance:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/attendance/check - проверка отметки (поддерживает phone или employeeName)
  app.get('/api/attendance/check', async (req, res) => {
    try {
      const { phone, employeeName, date } = req.query;
      const identifier = phone || employeeName;
      console.log('GET /api/attendance/check:', identifier, date);

      if (!identifier) {
        return res.json({ success: true, hasAttendance: false, lastAction: null, records: [] });
      }

      const normalizedId = identifier.replace(/[\s+]/g, '_').replace(/[^a-zA-Zа-яА-Я0-9_]/g, '');
      const checkDate = date || new Date().toISOString().split('T')[0];
      const filePath = path.join(ATTENDANCE_DIR, `${normalizedId}_${checkDate}.json`);

      if (fs.existsSync(filePath)) {
        const attendance = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        const lastRecord = attendance.records[attendance.records.length - 1];
        res.json({
          success: true,
          hasAttendance: true,
          lastAction: lastRecord ? lastRecord.action : null,
          records: attendance.records
        });
      } else {
        res.json({ success: true, hasAttendance: false, lastAction: null, records: [] });
      }
    } catch (error) {
      console.error('Error checking attendance:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/attendance', async (req, res) => {
    try {
      const { phone, employeeName, fromDate, toDate, shopAddress, date } = req.query;
      console.log('GET /api/attendance', { phone, employeeName, shopAddress, date });

      const flatRecords = [];

      if (fs.existsSync(ATTENDANCE_DIR)) {
        const files = fs.readdirSync(ATTENDANCE_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(ATTENDANCE_DIR, file), 'utf8');
            const attendance = JSON.parse(content);

            // Проверяем, это новый формат (с вложенными records) или старый (плоский)
            if (attendance.records && Array.isArray(attendance.records)) {
              // Новый формат: разворачиваем записи
              for (const record of attendance.records) {
                // Фильтрация по employeeName
                if (employeeName && record.employeeName !== employeeName) continue;
                // Фильтрация по phone
                if (phone) {
                  const normalizedPhone = phone.replace(/[\s+]/g, '');
                  if (attendance.identifier !== normalizedPhone && attendance.phone !== normalizedPhone) continue;
                }
                // Фильтрация по магазину
                if (shopAddress && record.shopAddress !== shopAddress) continue;
                // Фильтрация по дате
                if (date) {
                  const recordDate = record.timestamp ? record.timestamp.split('T')[0] : attendance.date;
                  if (recordDate !== date.split('T')[0]) continue;
                }
                if (fromDate && attendance.date < fromDate) continue;
                if (toDate && attendance.date > toDate) continue;

                flatRecords.push({
                  id: record.id || `attendance_${attendance.identifier}_${attendance.date}`,
                  employeeName: record.employeeName || attendance.identifier,
                  shopAddress: record.shopAddress,
                  timestamp: record.timestamp,
                  latitude: record.latitude,
                  longitude: record.longitude,
                  distance: record.distance,
                  action: record.action,
                  isOnTime: record.isOnTime,
                  shiftType: record.shiftType,
                  lateMinutes: record.lateMinutes,
                  createdAt: record.createdAt
                });
              }
            } else if (attendance.id || attendance.employeeName) {
              // Старый плоский формат - добавляем напрямую
              // Фильтрация по employeeName
              if (employeeName && attendance.employeeName !== employeeName) continue;
              // Фильтрация по магазину
              if (shopAddress && attendance.shopAddress !== shopAddress) continue;
              // Фильтрация по дате
              if (date) {
                const recordDate = attendance.timestamp ? attendance.timestamp.split('T')[0] : '';
                if (recordDate !== date.split('T')[0]) continue;
              }
              if (fromDate) {
                const recordDate = attendance.timestamp ? attendance.timestamp.split('T')[0] : '';
                if (recordDate < fromDate) continue;
              }
              if (toDate) {
                const recordDate = attendance.timestamp ? attendance.timestamp.split('T')[0] : '';
                if (recordDate > toDate) continue;
              }

              flatRecords.push(attendance);
            }
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      // Сортируем по timestamp (новые первыми)
      flatRecords.sort((a, b) => new Date(b.timestamp || 0) - new Date(a.timestamp || 0));
      console.log(`  Returning ${flatRecords.length} attendance records`);
      res.json({ success: true, records: flatRecords });
    } catch (error) {
      console.error('Error getting attendance:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Attendance API initialized');
}

module.exports = { setupAttendanceAPI };

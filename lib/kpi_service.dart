import 'dart:convert';
import 'kpi_models.dart';
import 'attendance_service.dart';
import 'attendance_model.dart';
import 'shift_report_model.dart';
import 'recount_service.dart';
import 'recount_report_model.dart';
import 'rko_reports_service.dart';
import 'rko_report_model.dart';
import 'employee_registration_service.dart';
import 'utils/logger.dart';
import 'utils/cache_manager.dart';

/// Сервис для получения и агрегации KPI данных
class KPIService {
  static const String serverUrl = 'https://arabica26.ru';
  static const Duration cacheDuration = Duration(minutes: 5);

  /// Получить данные по магазину за день
  static Future<KPIShopDayData> getShopDayData(
    String shopAddress,
    DateTime date,
  ) async {
    try {
      // Нормализуем дату (убираем время)
      final normalizedDate = DateTime(date.year, date.month, date.day);
      
      // Для всех дат проверяем кэш, но для недавних дат (последние 7 дней) всегда очищаем кэш перед загрузкой
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final daysDiff = normalizedDate.difference(today).inDays;
      
      final cacheKey = 'kpi_shop_day_${shopAddress}_${normalizedDate.year}_${normalizedDate.month}_${normalizedDate.day}';
      
      // Для недавних дат (последние 7 дней) всегда очищаем кэш, чтобы видеть свежие данные
      if (daysDiff >= -7 && daysDiff <= 0) {
        CacheManager.remove(cacheKey);
        Logger.debug('🔄 Кэш очищен для недавней даты: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day} (разница: $daysDiff дней)');
      } else {
        // Для старых дат используем кэш, если он есть
        final cached = CacheManager.get<KPIShopDayData>(cacheKey);
        if (cached != null) {
          Logger.debug('KPI данные магазина загружены из кэша для даты: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
          return cached;
        }
      }

      Logger.debug('═══════════════════════════════════════════════════════');
      Logger.debug('🔄 НАЧАЛО ЗАГРУЗКИ KPI данных для магазина "$shopAddress" за ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
      Logger.debug('═══════════════════════════════════════════════════════');

      // Получаем отметки прихода за день
      // Создаем дату с временем 00:00:00 для правильной фильтрации на сервере
      final dateForQuery = DateTime(normalizedDate.year, normalizedDate.month, normalizedDate.day, 0, 0, 0);
      Logger.debug('📥 Запрос отметок прихода для $shopAddress за ${dateForQuery.toIso8601String()}');
      final attendanceRecords = await AttendanceService.getAttendanceRecords(
        shopAddress: shopAddress,
        date: dateForQuery,
      );
      
      Logger.debug('📊 Загружено отметок прихода: ${attendanceRecords.length}');
      if (attendanceRecords.isNotEmpty) {
        Logger.debug('   📋 Список всех отметок:');
        for (var record in attendanceRecords) {
          final recordDate = DateTime(record.timestamp.year, record.timestamp.month, record.timestamp.day);
          final isSameDate = recordDate == normalizedDate;
          Logger.debug('   ✅ Отметка: ${record.employeeName} в ${record.timestamp} (${record.timestamp.hour}:${record.timestamp.minute.toString().padLeft(2, '0')}), дата записи: ${recordDate.year}-${recordDate.month}-${recordDate.day}, совпадает с запрошенной: $isSameDate, магазин: ${record.shopAddress}');
        }
      } else {
        Logger.debug('   ⚠️ Отметок прихода не найдено для этой даты');
      }

      // Фильтруем отметки по дате и магазину (на случай, если API вернул лишние данные)
      // Нормализуем адрес магазина для сравнения (убираем лишние пробелы, приводим к нижнему регистру)
      final normalizedShopAddress = shopAddress.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
      Logger.debug('   🔍 Нормализованный адрес магазина для фильтрации: "$normalizedShopAddress"');
      Logger.debug('   🔍 Запрошенная дата: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
      
      final filteredAttendanceRecords = attendanceRecords.where((record) {
        // Нормализуем дату отметки (убираем время)
        final recordDate = DateTime(record.timestamp.year, record.timestamp.month, record.timestamp.day);
        final isSameDate = recordDate.year == normalizedDate.year && 
                          recordDate.month == normalizedDate.month && 
                          recordDate.day == normalizedDate.day;
        final normalizedRecordAddress = record.shopAddress.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
        final isSameShop = normalizedRecordAddress == normalizedShopAddress;
        
        if (!isSameDate || !isSameShop) {
          Logger.debug('   ⚠️ Отметка отфильтрована: ${record.employeeName}, дата отметки: ${recordDate.year}-${recordDate.month}-${recordDate.day}, запрошенная дата: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day} (совпадает: $isSameDate), магазин: "${record.shopAddress}" (нормализован: "$normalizedRecordAddress", совпадает: $isSameShop)');
        } else {
          Logger.debug('   ✅ Отметка прошла фильтрацию: ${record.employeeName}, дата: ${recordDate.year}-${recordDate.month}-${recordDate.day}, магазин: "${record.shopAddress}", время: ${record.timestamp.hour}:${record.timestamp.minute.toString().padLeft(2, '0')}');
        }
        return isSameDate && isSameShop;
      }).toList();
      
      Logger.debug('📊 После фильтрации осталось отметок: ${filteredAttendanceRecords.length}');

      // Получаем пересменки за день (из локальных данных)
      // Пересменки хранятся локально, но нужно проверить, есть ли API endpoint
      // Пока используем локальные данные
      final allShifts = await ShiftReport.loadAllReports();
      final dayShifts = allShifts.where((shift) {
        final shiftDate = DateTime(
          shift.createdAt.year,
          shift.createdAt.month,
          shift.createdAt.day,
        );
        return shiftDate == normalizedDate && 
               shift.shopAddress.toLowerCase() == shopAddress.toLowerCase();
      }).toList();

      // Получаем пересчеты за день
      final recounts = await RecountService.getReports(
        shopAddress: shopAddress,
        date: normalizedDate,
      );

      // Получаем РКО за день (нужно получить список и отфильтровать)
      Logger.debug('📋 Загрузка РКО для магазина: "$shopAddress"');
      Logger.debug('📋 Запрошенная дата для РКО: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
      final shopRKOs = await RKOReportsService.getShopRKOs(shopAddress);
      Logger.debug('📋 Ответ API getShopRKOs: ${shopRKOs != null ? "успешно" : "null"}');
      if (shopRKOs != null) {
        Logger.debug('📋 Структура ответа: keys=${shopRKOs.keys.toList()}');
        Logger.debug('📋 success=${shopRKOs['success']}, items=${shopRKOs['items'] != null ? (shopRKOs['items'] as List?)?.length ?? 0 : "null"}');
      }
      final dayRKOs = <RKOMetadata>[];
      if (shopRKOs != null && shopRKOs['items'] != null) {
        final rkoList = RKOMetadataList.fromJson(shopRKOs);
        Logger.debug('📋 Всего РКО загружено: ${rkoList.items.length}');
        if (rkoList.items.isNotEmpty) {
          Logger.debug('   📋 Первые 5 РКО:');
          for (var i = 0; i < (rkoList.items.length > 5 ? 5 : rkoList.items.length); i++) {
            final rko = rkoList.items[i];
            Logger.debug('      ${i + 1}. ${rko.employeeName}, дата: ${rko.date.year}-${rko.date.month}-${rko.date.day}, магазин: "${rko.shopAddress}"');
          }
        }
        
        // Нормализуем адрес магазина для сравнения
        final normalizedShopAddress = shopAddress.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
        Logger.debug('   🔍 Нормализованный адрес магазина для фильтрации РКО: "$normalizedShopAddress"');
        
        dayRKOs.addAll(rkoList.items.where((rko) {
          final rkoDate = DateTime(
            rko.date.year,
            rko.date.month,
            rko.date.day,
          );
          final rkoShopAddress = rko.shopAddress.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
          final isDateMatch = rkoDate == normalizedDate;
          final isShopMatch = rkoShopAddress == normalizedShopAddress;
          
          // Логируем для всех РКО, не только для 12.12.2025
          Logger.debug('   🔍 РКО: "${rko.employeeName}", дата: ${rkoDate.year}-${rkoDate.month}-${rkoDate.day}, магазин: "${rko.shopAddress}" (нормализован: "$rkoShopAddress"), дата совпадает: $isDateMatch, магазин совпадает: $isShopMatch');
          
          return isDateMatch && isShopMatch;
        }));
        Logger.debug('📋 РКО после фильтрации по дате и магазину: ${dayRKOs.length}');
        if (dayRKOs.isEmpty && rkoList.items.isNotEmpty) {
          Logger.debug('   ⚠️ ВНИМАНИЕ: РКО загружены, но ни одно не прошло фильтрацию!');
          Logger.debug('   🔍 Проверка: запрошенная дата=${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}, нормализованный адрес="$normalizedShopAddress"');
        }
      } else {
        Logger.debug('⚠️ РКО не загружены: shopRKOs=${shopRKOs != null}, items=${shopRKOs?['items'] != null}');
        if (shopRKOs != null && shopRKOs['success'] == false) {
          Logger.debug('   ⚠️ API вернул success=false');
        }
      }

      // Агрегируем данные по сотрудникам
      final Map<String, KPIDayData> employeesDataMap = {};
      
      // Функция для нормализации имени сотрудника (приводим к нижнему регистру и убираем лишние пробелы)
      String normalizeEmployeeName(String name) {
        return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      }
      
      // Константа для границы между утром и вечером (15:00)
      const int eveningBoundaryHour = 15;

      // Добавляем данные из отметок прихода
      for (var record in filteredAttendanceRecords) {
        final key = normalizeEmployeeName(record.employeeName); // Нормализуем имя
        final recordTime = record.timestamp;
        final isMorning = recordTime.hour < eveningBoundaryHour;
        final isEvening = recordTime.hour >= eveningBoundaryHour;
        
        Logger.debug('   Обработка отметки: "$key" в ${recordTime.hour}:${recordTime.minute.toString().padLeft(2, '0')} (${isMorning ? "утро" : "вечер"})');
        
        if (!employeesDataMap.containsKey(key)) {
          // Создаем новую запись
          final earliestTime = recordTime;
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: record.employeeName,
            shopAddress: shopAddress,
            attendanceTime: earliestTime,
            hasMorningAttendance: isMorning,
            hasEveningAttendance: isEvening,
          );
          Logger.debug('   ✅ Создана новая запись для "$key" с временем прихода: ${earliestTime.hour}:${earliestTime.minute.toString().padLeft(2, '0')}');
        } else {
          // Обновляем существующую запись
          final existing = employeesDataMap[key]!;
          final earliestTime = existing.attendanceTime == null || recordTime.isBefore(existing.attendanceTime!)
              ? recordTime
              : existing.attendanceTime!;
          
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: record.employeeName,
            shopAddress: shopAddress,
            attendanceTime: earliestTime,
            hasMorningAttendance: existing.hasMorningAttendance || isMorning,
            hasEveningAttendance: existing.hasEveningAttendance || isEvening,
            hasShift: existing.hasShift,
            hasRecount: existing.hasRecount,
            hasRKO: existing.hasRKO,
          );
          Logger.debug('   ✅ Обновлена запись для "$key": утро=${existing.hasMorningAttendance || isMorning}, вечер=${existing.hasEveningAttendance || isEvening}');
        }
      }
      
      Logger.debug('📊 Всего уникальных сотрудников после обработки прихода: ${employeesDataMap.length}');
      Logger.debug('   Список сотрудников: ${employeesDataMap.keys.toList()}');

      // Добавляем данные из пересменок
      Logger.debug('📋 Обработка пересменок: найдено ${dayShifts.length}');
      for (var shift in dayShifts) {
        final key = normalizeEmployeeName(shift.employeeName); // Нормализуем имя
        Logger.debug('   🔍 Обработка пересменки: "${shift.employeeName}" -> ключ: "$key"');
        final existing = employeesDataMap[key];
        if (existing != null) {
          Logger.debug('   ✅ Найдена существующая запись для "$key", обновляем hasShift=true');
        } else {
          Logger.debug('   ⚠️ Запись для "$key" не найдена, создаем новую');
        }
        if (existing == null) {
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: shift.employeeName,
            shopAddress: shopAddress,
            hasShift: true,
          );
        } else {
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: shift.employeeName,
            shopAddress: shopAddress,
            attendanceTime: existing.attendanceTime,
            hasMorningAttendance: existing.hasMorningAttendance,
            hasEveningAttendance: existing.hasEveningAttendance,
            hasShift: true,
            hasRecount: existing.hasRecount,
            hasRKO: existing.hasRKO,
          );
        }
      }

      // Добавляем данные из пересчетов
      Logger.debug('📋 Обработка пересчетов: найдено ${recounts.length}');
      for (var recount in recounts) {
        final key = normalizeEmployeeName(recount.employeeName); // Нормализуем имя
        Logger.debug('   🔍 Обработка пересчета: "${recount.employeeName}" -> ключ: "$key"');
        final existing = employeesDataMap[key];
        if (existing != null) {
          Logger.debug('   ✅ Найдена существующая запись для "$key", обновляем hasRecount=true');
        } else {
          Logger.debug('   ⚠️ Запись для "$key" не найдена, создаем новую');
        }
        if (existing == null) {
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: recount.employeeName,
            shopAddress: shopAddress,
            hasRecount: true,
          );
        } else {
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: recount.employeeName,
            shopAddress: shopAddress,
            attendanceTime: existing.attendanceTime,
            hasMorningAttendance: existing.hasMorningAttendance,
            hasEveningAttendance: existing.hasEveningAttendance,
            hasShift: existing.hasShift,
            hasRecount: true,
            hasRKO: existing.hasRKO,
          );
        }
      }

      // Добавляем данные из РКО
      Logger.debug('📋 Обработка РКО: найдено ${dayRKOs.length}');
      if (dayRKOs.isEmpty) {
        Logger.debug('   ⚠️ РКО не найдено для даты ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
      } else {
        Logger.debug('   📋 Список всех РКО:');
        for (var rko in dayRKOs) {
          Logger.debug('      - ${rko.employeeName}, дата: ${rko.date.year}-${rko.date.month}-${rko.date.day}, магазин: "${rko.shopAddress}"');
        }
      }
      for (var rko in dayRKOs) {
        final key = normalizeEmployeeName(rko.employeeName); // Нормализуем имя
        Logger.debug('   🔍 Обработка РКО: "${rko.employeeName}" -> ключ: "$key"');
        Logger.debug('   📋 Доступные ключи в employeesDataMap: ${employeesDataMap.keys.toList()}');
        final existing = employeesDataMap[key];
        if (existing != null) {
          Logger.debug('   ✅ Найдена существующая запись для "$key", обновляем hasRKO=true');
        } else {
          Logger.debug('   ⚠️ Запись для "$key" не найдена, создаем новую');
          Logger.debug('   📋 Попытка найти похожие ключи...');
          for (var existingKey in employeesDataMap.keys) {
            if (existingKey.toLowerCase().contains(key.toLowerCase()) || key.toLowerCase().contains(existingKey.toLowerCase())) {
              Logger.debug('      - Найден похожий ключ: "$existingKey" (искомый: "$key")');
            }
          }
        }
        if (existing == null) {
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: rko.employeeName,
            shopAddress: shopAddress,
            hasRKO: true,
          );
          Logger.debug('   ✅ Создана новая запись для РКО: "$key"');
        } else {
          // Используем имя из существующей записи, чтобы сохранить оригинальное имя
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: existing.employeeName, // Используем имя из существующей записи
            shopAddress: shopAddress,
            attendanceTime: existing.attendanceTime,
            hasMorningAttendance: existing.hasMorningAttendance,
            hasEveningAttendance: existing.hasEveningAttendance,
            hasShift: existing.hasShift,
            hasRecount: existing.hasRecount,
            hasRKO: true,
          );
          Logger.debug('   ✅ Обновлена запись для РКО: "$key", hasRKO=true');
        }
      }

      final result = KPIShopDayData(
        date: normalizedDate,
        shopAddress: shopAddress,
        employeesData: employeesDataMap.values.toList(),
      );

      // Логирование для отладки
      final isTargetDate = normalizedDate.year == 2025 && normalizedDate.month == 12 && normalizedDate.day == 12;
      if (isTargetDate) {
        Logger.debug('🔍 === СПЕЦИАЛЬНАЯ ПРОВЕРКА ДЛЯ 12.12.2025 ===');
        Logger.debug('   📋 Загружено отметок прихода: ${attendanceRecords.length}');
        Logger.debug('   📋 После фильтрации: ${filteredAttendanceRecords.length}');
        Logger.debug('   📋 Пересменок: ${dayShifts.length}');
        Logger.debug('   📋 Пересчетов: ${recounts.length}');
        Logger.debug('   📋 РКО: ${dayRKOs.length}');
        Logger.debug('   📋 Всего записей сотрудников в employeesDataMap: ${employeesDataMap.length}');
        for (var entry in employeesDataMap.entries) {
          Logger.debug('      - ${entry.key}: утро=${entry.value.hasMorningAttendance}, вечер=${entry.value.hasEveningAttendance}, время=${entry.value.attendanceTime?.hour}:${entry.value.attendanceTime?.minute.toString().padLeft(2, '0')}');
        }
      }
      
      Logger.debug('═══════════════════════════════════════════════════════');
      Logger.debug('📊 KPIShopDayData создан: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
      Logger.debug('   Сотрудников: ${result.employeesWorkedCount}');
      Logger.debug('   Утренние отметки: ${result.hasMorningAttendance}');
      Logger.debug('   Вечерние отметки: ${result.hasEveningAttendance}');
      Logger.debug('   Всего записей сотрудников: ${result.employeesData.length}');
      Logger.debug('   📋 Загружено РКО: ${dayRKOs.length}');
      if (result.employeesData.isEmpty) {
        Logger.debug('   ⚠️ ВНИМАНИЕ: Список сотрудников пуст!');
        Logger.debug('   📋 Обработано отметок прихода: ${filteredAttendanceRecords.length}');
        if (filteredAttendanceRecords.isNotEmpty) {
          Logger.debug('   📋 Детали отметок:');
          for (var record in filteredAttendanceRecords) {
            Logger.debug('      - ${record.employeeName} в ${record.timestamp.hour}:${record.timestamp.minute.toString().padLeft(2, '0')}');
          }
        }
      } else {
        Logger.debug('   📋 Детали по сотрудникам:');
        for (var emp in result.employeesData) {
          Logger.debug('      - ${emp.employeeName}: приход=${emp.attendanceTime != null}, пересменка=${emp.hasShift}, пересчет=${emp.hasRecount}, РКО=${emp.hasRKO}, время=${emp.attendanceTime?.hour}:${emp.attendanceTime?.minute.toString().padLeft(2, '0')}');
        }
      }
      Logger.debug('═══════════════════════════════════════════════════════');
      
      if (isTargetDate) {
        Logger.debug('🔍 === КОНЕЦ ПРОВЕРКИ ДЛЯ 12.12.2025 ===');
        Logger.debug('   ✅ ИТОГОВЫЕ ФЛАГИ: утро=${result.hasMorningAttendance}, вечер=${result.hasEveningAttendance}');
      }

      // Сохраняем в кэш
      CacheManager.set(cacheKey, result, duration: cacheDuration);

      return result;
    } catch (e) {
      Logger.error('Ошибка получения KPI данных магазина за день', e);
      return KPIShopDayData(
        date: date,
        shopAddress: shopAddress,
        employeesData: [],
      );
    }
  }

  /// Получить данные по сотруднику за период (текущий и предыдущий месяц)
  static Future<KPIEmployeeData> getEmployeeData(
    String employeeName,
  ) async {
    try {
      // Проверяем кэш
      final cacheKey = 'kpi_employee_$employeeName';
      final cached = CacheManager.get<KPIEmployeeData>(cacheKey);
      if (cached != null) {
        Logger.debug('KPI данные сотрудника загружены из кэша');
        return cached;
      }

      Logger.debug('Загрузка KPI данных для сотрудника $employeeName');

      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month, 1);
      DateTime previousMonth;
      if (now.month == 1) {
        previousMonth = DateTime(now.year - 1, 12, 1);
      } else {
        previousMonth = DateTime(now.year, now.month - 1, 1);
      }

      // Получаем отметки прихода за период
      final attendanceRecords = await AttendanceService.getAttendanceRecords(
        employeeName: employeeName,
      );

      // Фильтруем по текущему и предыдущему месяцу
      final filteredAttendance = attendanceRecords.where((record) {
        final recordMonth = DateTime(record.timestamp.year, record.timestamp.month, 1);
        return recordMonth == currentMonth || recordMonth == previousMonth;
      }).toList();

      // Получаем пересменки за период (из локальных данных)
      final allShifts = await ShiftReport.loadAllReports();
      final employeeShifts = allShifts.where((shift) {
        if (shift.employeeName.toLowerCase() != employeeName.toLowerCase()) {
          return false;
        }
        final shiftMonth = DateTime(shift.createdAt.year, shift.createdAt.month, 1);
        final prevMonth = previousMonth;
        return shiftMonth == currentMonth || shiftMonth == prevMonth;
      }).toList();

      // Получаем пересчеты за период
      final allRecounts = await RecountService.getReports(
        employeeName: employeeName,
      );
      final filteredRecounts = allRecounts.where((recount) {
        final recountMonth = DateTime(recount.completedAt.year, recount.completedAt.month, 1);
        return recountMonth == currentMonth || recountMonth == previousMonth;
      }).toList();

      // Получаем РКО за период
      final employeeRKOs = await RKOReportsService.getEmployeeRKOs(employeeName);
      final filteredRKOs = <RKOMetadata>[];
      if (employeeRKOs != null && employeeRKOs['items'] != null) {
        final rkoList = RKOMetadataList.fromJson(employeeRKOs);
        filteredRKOs.addAll(rkoList.items.where((rko) {
          final rkoMonth = DateTime(rko.date.year, rko.date.month, 1);
          return rkoMonth == currentMonth || rkoMonth == previousMonth;
        }));
      }

      // Агрегируем данные по дням
      final Map<String, KPIDayData> daysDataMap = {};

      // Добавляем данные из отметок прихода
      for (var record in filteredAttendance) {
        final date = DateTime(
          record.timestamp.year,
          record.timestamp.month,
          record.timestamp.day,
        );
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        
        if (!daysDataMap.containsKey(key)) {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: record.shopAddress,
            attendanceTime: record.timestamp,
          );
        } else {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: daysDataMap[key]!.shopAddress,
            attendanceTime: record.timestamp,
            hasShift: daysDataMap[key]!.hasShift,
            hasRecount: daysDataMap[key]!.hasRecount,
            hasRKO: daysDataMap[key]!.hasRKO,
          );
        }
      }

      // Добавляем данные из пересменок
      for (var shift in employeeShifts) {
        final date = DateTime(
          shift.createdAt.year,
          shift.createdAt.month,
          shift.createdAt.day,
        );
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        
        if (!daysDataMap.containsKey(key)) {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: shift.shopAddress,
            hasShift: true,
          );
        } else {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: daysDataMap[key]!.shopAddress,
            attendanceTime: daysDataMap[key]!.attendanceTime,
            hasShift: true,
            hasRecount: daysDataMap[key]!.hasRecount,
            hasRKO: daysDataMap[key]!.hasRKO,
          );
        }
      }

      // Добавляем данные из пересчетов
      for (var recount in filteredRecounts) {
        final date = DateTime(
          recount.completedAt.year,
          recount.completedAt.month,
          recount.completedAt.day,
        );
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        
        if (!daysDataMap.containsKey(key)) {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: recount.shopAddress,
            hasRecount: true,
          );
        } else {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: daysDataMap[key]!.shopAddress,
            attendanceTime: daysDataMap[key]!.attendanceTime,
            hasShift: daysDataMap[key]!.hasShift,
            hasRecount: true,
            hasRKO: daysDataMap[key]!.hasRKO,
          );
        }
      }

      // Добавляем данные из РКО
      for (var rko in filteredRKOs) {
        final date = DateTime(
          rko.date.year,
          rko.date.month,
          rko.date.day,
        );
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        
        if (!daysDataMap.containsKey(key)) {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: rko.shopAddress,
            hasRKO: true,
          );
        } else {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: daysDataMap[key]!.shopAddress,
            attendanceTime: daysDataMap[key]!.attendanceTime,
            hasShift: daysDataMap[key]!.hasShift,
            hasRecount: daysDataMap[key]!.hasRecount,
            hasRKO: true,
          );
        }
      }

      // Подсчитываем статистику
      final totalDaysWorked = daysDataMap.values.where((day) => day.workedToday).length;
      final totalShifts = daysDataMap.values.where((day) => day.hasShift).length;
      final totalRecounts = daysDataMap.values.where((day) => day.hasRecount).length;
      final totalRKOs = daysDataMap.values.where((day) => day.hasRKO).length;

      final result = KPIEmployeeData(
        employeeName: employeeName,
        daysData: daysDataMap,
        totalDaysWorked: totalDaysWorked,
        totalShifts: totalShifts,
        totalRecounts: totalRecounts,
        totalRKOs: totalRKOs,
      );

      // Сохраняем в кэш
      CacheManager.set(cacheKey, result, duration: cacheDuration);

      return result;
    } catch (e) {
      Logger.error('Ошибка получения KPI данных сотрудника', e);
      return KPIEmployeeData(
        employeeName: employeeName,
        daysData: {},
        totalDaysWorked: 0,
        totalShifts: 0,
        totalRecounts: 0,
        totalRKOs: 0,
      );
    }
  }

  /// Получить список всех сотрудников (из регистрации)
  static Future<List<String>> getAllEmployees() async {
    try {
      // Проверяем кэш
      const cacheKey = 'kpi_all_employees';
      final cached = CacheManager.get<List<String>>(cacheKey);
      if (cached != null) {
        Logger.debug('Список сотрудников загружен из кэша');
        return cached;
      }

      Logger.debug('Загрузка списка всех сотрудников');

      // Получаем всех сотрудников из регистрации
      // Используем метод из EmployeeRegistrationService или Google Sheets
      // Пока используем упрощенный подход - получаем из отметок прихода
      final attendanceRecords = await AttendanceService.getAttendanceRecords();
      
      final employeesSet = <String>{};
      for (var record in attendanceRecords) {
        if (record.employeeName.isNotEmpty) {
          employeesSet.add(record.employeeName);
        }
      }

      final employees = employeesSet.toList()..sort();
      
      // Сохраняем в кэш
      CacheManager.set(cacheKey, employees, duration: cacheDuration);

      return employees;
    } catch (e) {
      Logger.error('Ошибка получения списка сотрудников', e);
      return [];
    }
  }

  /// Очистить кэш KPI данных
  static void clearCache() {
    CacheManager.clear();
    Logger.debug('Кэш KPI данных очищен');
  }
  
  /// Очистить кэш для конкретной даты и магазина
  static void clearCacheForDate(String shopAddress, DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final cacheKey = 'kpi_shop_day_${shopAddress}_${normalizedDate.year}_${normalizedDate.month}_${normalizedDate.day}';
    CacheManager.remove(cacheKey);
    Logger.debug('Кэш KPI данных очищен для $shopAddress за ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
  }
  
  /// Очистить весь кэш KPI для магазина
  static void clearCacheForShop(String shopAddress) {
    CacheManager.clearByPattern('kpi_shop_day_${shopAddress}_');
    Logger.debug('Кэш KPI данных очищен для магазина $shopAddress');
  }
}


import 'dart:convert';
import 'kpi_models.dart';
import 'attendance_service.dart';
import 'attendance_model.dart';
import 'shift_report_model.dart';
import 'shift_report_service.dart';
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
      Logger.debug('═══════════════════════════════════════════════════════');
      Logger.debug('🔍 ФИЛЬТРАЦИЯ ОТМЕТОК ПРИХОДА');
      Logger.debug('   Запрошенный магазин: "$shopAddress"');
      Logger.debug('   Нормализованный адрес: "$normalizedShopAddress"');
      Logger.debug('   Запрошенная дата: ${normalizedDate.year}-${normalizedDate.month.toString().padLeft(2, '0')}-${normalizedDate.day.toString().padLeft(2, '0')}');
      Logger.debug('   Всего отметок до фильтрации: ${attendanceRecords.length}');
      Logger.debug('═══════════════════════════════════════════════════════');
      
      final filteredAttendanceRecords = attendanceRecords.where((record) {
        // Нормализуем дату отметки (убираем время)
        final recordDate = DateTime(record.timestamp.year, record.timestamp.month, record.timestamp.day);
        final isSameDate = recordDate.year == normalizedDate.year && 
                          recordDate.month == normalizedDate.month && 
                          recordDate.day == normalizedDate.day;
        final normalizedRecordAddress = record.shopAddress.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
        final isSameShop = normalizedRecordAddress == normalizedShopAddress;
        
        // Детальное логирование для каждой отметки
        Logger.debug('   🔍 Проверка отметки:');
        Logger.debug('      - Сотрудник: "${record.employeeName}"');
        Logger.debug('      - Время: ${record.timestamp.hour}:${record.timestamp.minute.toString().padLeft(2, '0')}');
        Logger.debug('      - Дата отметки: ${recordDate.year}-${recordDate.month.toString().padLeft(2, '0')}-${recordDate.day.toString().padLeft(2, '0')}');
        Logger.debug('      - Запрошенная дата: ${normalizedDate.year}-${normalizedDate.month.toString().padLeft(2, '0')}-${normalizedDate.day.toString().padLeft(2, '0')}');
        Logger.debug('      - Даты совпадают: $isSameDate (год: ${recordDate.year == normalizedDate.year}, месяц: ${recordDate.month == normalizedDate.month}, день: ${recordDate.day == normalizedDate.day})');
        Logger.debug('      - Магазин (оригинал): "${record.shopAddress}"');
        Logger.debug('      - Магазин (нормализован): "$normalizedRecordAddress"');
        Logger.debug('      - Запрошенный магазин (нормализован): "$normalizedShopAddress"');
        Logger.debug('      - Магазины совпадают: $isSameShop');
        
        if (!isSameDate || !isSameShop) {
          final reasons = <String>[];
          if (!isSameDate) {
            reasons.add('дата не совпадает');
          }
          if (!isSameShop) {
            reasons.add('магазин не совпадает');
          }
          Logger.debug('      ⚠️ ОТМЕТКА ОТФИЛЬТРОВАНА: ${reasons.join(', ')}');
        } else {
          Logger.debug('      ✅ ОТМЕТКА ПРОШЛА ФИЛЬТРАЦИЮ');
        }
        
        return isSameDate && isSameShop;
      }).toList();
      
      Logger.debug('📊 После фильтрации осталось отметок: ${filteredAttendanceRecords.length}');

      // Получаем пересменки за день с сервера
      final allShifts = await ShiftReportService.getReports(
        shopAddress: shopAddress,
        date: normalizedDate,
      );
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
      final isTargetDate = normalizedDate.year == 2025 && normalizedDate.month == 12 && normalizedDate.day == 12;
      if (isTargetDate) {
        Logger.debug('═══════════════════════════════════════════════════════');
        Logger.debug('🔍 СПЕЦИАЛЬНЫЙ АНАЛИЗ ДЛЯ 12.12.2025');
        Logger.debug('═══════════════════════════════════════════════════════');
      }
      Logger.debug('📋 Загрузка РКО для магазина: "$shopAddress"');
      Logger.debug('📋 Запрошенная дата для РКО: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
      Logger.debug('📋 normalizedDate объект: ${normalizedDate.toIso8601String()}');
      final shopRKOs = await RKOReportsService.getShopRKOs(shopAddress);
      Logger.debug('📋 Ответ API getShopRKOs: ${shopRKOs != null ? "успешно" : "null"}');
      if (shopRKOs != null) {
        Logger.debug('📋 Структура ответа: keys=${shopRKOs.keys.toList()}');
        Logger.debug('📋 success=${shopRKOs['success']}, currentMonth=${(shopRKOs['currentMonth'] as List?)?.length ?? 0}, months=${(shopRKOs['months'] as List?)?.length ?? 0}');
      }
      final dayRKOs = <RKOMetadata>[];
      if (shopRKOs != null && shopRKOs['success'] == true) {
        // API возвращает данные в формате: {success: true, currentMonth: [...], months: [{month: "...", items: [...]}, ...]}
        // Нужно собрать все РКО из currentMonth и из всех months
        final allRKOs = <RKOMetadata>[];
        
        // Добавляем РКО из currentMonth
        if (shopRKOs['currentMonth'] != null) {
          final currentMonthList = shopRKOs['currentMonth'] as List<dynamic>;
          Logger.debug('📋 РКО в currentMonth: ${currentMonthList.length}');
          for (var rkoJson in currentMonthList) {
            try {
              final rko = RKOMetadata.fromJson(rkoJson as Map<String, dynamic>);
              allRKOs.add(rko);
            } catch (e) {
              Logger.debug('⚠️ Ошибка парсинга РКО из currentMonth: $e');
            }
          }
        }
        
        // Добавляем РКО из всех months
        if (shopRKOs['months'] != null) {
          final monthsList = shopRKOs['months'] as List<dynamic>;
          Logger.debug('📋 Месяцев с РКО: ${monthsList.length}');
          for (var monthData in monthsList) {
            if (monthData is Map<String, dynamic> && monthData['items'] != null) {
              final itemsList = monthData['items'] as List<dynamic>;
              Logger.debug('   📋 РКО в месяце ${monthData['month'] ?? 'unknown'}: ${itemsList.length}');
              for (var rkoJson in itemsList) {
                try {
                  final rko = RKOMetadata.fromJson(rkoJson as Map<String, dynamic>);
                  allRKOs.add(rko);
                } catch (e) {
                  Logger.debug('⚠️ Ошибка парсинга РКО из months: $e');
                }
              }
            }
          }
        }
        
        Logger.debug('📋 Всего РКО собрано из всех источников: ${allRKOs.length}');
        if (allRKOs.isNotEmpty) {
          Logger.debug('   📋 Первые 10 РКО (для анализа):');
          for (var i = 0; i < (allRKOs.length > 10 ? 10 : allRKOs.length); i++) {
            final rko = allRKOs[i];
            final rkoDateNormalized = DateTime(rko.date.year, rko.date.month, rko.date.day);
            Logger.debug('      ${i + 1}. ${rko.employeeName}');
            Logger.debug('         - date (оригинал из API): ${rko.date.toIso8601String()}');
            Logger.debug('         - date (нормализован): ${rkoDateNormalized.year}-${rkoDateNormalized.month.toString().padLeft(2, '0')}-${rkoDateNormalized.day.toString().padLeft(2, '0')}');
            Logger.debug('         - магазин: "${rko.shopAddress}"');
          }
        }
        
        // Нормализуем адрес магазина для сравнения
        final normalizedShopAddress = shopAddress.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
        Logger.debug('   🔍 Нормализованный адрес магазина для фильтрации РКО: "$normalizedShopAddress"');
        
        dayRKOs.addAll(allRKOs.where((rko) {
          final rkoDate = DateTime(
            rko.date.year,
            rko.date.month,
            rko.date.day,
          );
          final rkoShopAddress = rko.shopAddress.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
          final rkoEmployeeName = rko.employeeName.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
          final isDateMatch = rkoDate == normalizedDate;
          final isShopMatch = rkoShopAddress == normalizedShopAddress;
          
          // Логируем для всех РКО, но более детально для целевой даты
          final shouldLogDetail = isTargetDate || isDateMatch;
          if (shouldLogDetail) {
            Logger.debug('   🔍 РКО:');
            Logger.debug('      - employeeName (оригинал): "${rko.employeeName}"');
            Logger.debug('      - employeeName (нормализован): "$rkoEmployeeName"');
            Logger.debug('      - date (оригинал из объекта): ${rko.date.toIso8601String()}');
            Logger.debug('      - date (год/месяц/день): ${rko.date.year}/${rko.date.month}/${rko.date.day}');
            Logger.debug('      - date (нормализован): ${rkoDate.year}-${rkoDate.month.toString().padLeft(2, '0')}-${rkoDate.day.toString().padLeft(2, '0')}');
            Logger.debug('      - rkoDate объект: ${rkoDate.toIso8601String()}');
            Logger.debug('      - shopAddress (оригинал): "${rko.shopAddress}"');
            Logger.debug('      - shopAddress (нормализован): "$rkoShopAddress"');
            Logger.debug('      - Запрошенная дата: ${normalizedDate.year}-${normalizedDate.month.toString().padLeft(2, '0')}-${normalizedDate.day.toString().padLeft(2, '0')}');
            Logger.debug('      - normalizedDate объект: ${normalizedDate.toIso8601String()}');
            Logger.debug('      - Запрошенный магазин (нормализован): "$normalizedShopAddress"');
            Logger.debug('      - Сравнение дат: rkoDate == normalizedDate: ${rkoDate == normalizedDate}');
            Logger.debug('      - Сравнение по компонентам: год=${rkoDate.year == normalizedDate.year}, месяц=${rkoDate.month == normalizedDate.month}, день=${rkoDate.day == normalizedDate.day}');
            Logger.debug('      - Дата совпадает: $isDateMatch');
            Logger.debug('      - Магазин совпадает: $isShopMatch');
            Logger.debug('      - ПРОЙДЕТ ФИЛЬТРАЦИЮ: ${isDateMatch && isShopMatch}');
          }
          
          return isDateMatch && isShopMatch;
        }));
        Logger.debug('📋 РКО после фильтрации по дате и магазину: ${dayRKOs.length}');
        if (dayRKOs.isEmpty && allRKOs.isNotEmpty) {
          Logger.debug('   ⚠️ ВНИМАНИЕ: РКО загружены, но ни одно не прошло фильтрацию!');
          Logger.debug('   🔍 Проверка: запрошенная дата=${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}, нормализованный адрес="$normalizedShopAddress"');
        }
      } else {
        Logger.debug('⚠️ РКО не загружены: shopRKOs=${shopRKOs != null}, success=${shopRKOs?['success']}');
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
      Logger.debug('📋 НАЧАЛО ОБРАБОТКИ ОТМЕТОК ПРИХОДА: ${filteredAttendanceRecords.length} записей');
      for (var record in filteredAttendanceRecords) {
        final key = normalizeEmployeeName(record.employeeName); // Нормализуем имя
        final recordTime = record.timestamp;
        final isMorning = recordTime.hour < eveningBoundaryHour;
        final isEvening = recordTime.hour >= eveningBoundaryHour;
        
        Logger.debug('   🔍 Обработка отметки: "$key" (${record.employeeName})');
        Logger.debug('      timestamp: ${recordTime.toIso8601String()}');
        Logger.debug('      час: ${recordTime.hour}, минута: ${recordTime.minute}');
        Logger.debug('      UTC: ${recordTime.isUtc}, локальное: ${recordTime.toLocal().toIso8601String()}');
        Logger.debug('      время: ${recordTime.hour}:${recordTime.minute.toString().padLeft(2, '0')} (${isMorning ? "утро" : "вечер"})');
        
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
          Logger.debug('      attendanceTime в KPIDayData: ${employeesDataMap[key]!.attendanceTime?.toIso8601String() ?? "null"}');
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
      Logger.debug('   📋 Детали записей после обработки прихода:');
      for (var entry in employeesDataMap.entries) {
        final timeStr = entry.value.attendanceTime != null 
            ? '${entry.value.attendanceTime!.hour.toString().padLeft(2, '0')}:${entry.value.attendanceTime!.minute.toString().padLeft(2, '0')}'
            : 'null';
        Logger.debug('      - ключ: "${entry.key}", имя: "${entry.value.employeeName}", время: $timeStr (${entry.value.attendanceTime?.toIso8601String() ?? "null"})');
      }

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
      Logger.debug('═══════════════════════════════════════════════════════');
      Logger.debug('📋 ОБРАБОТКА РКО: найдено ${dayRKOs.length}');
      Logger.debug('═══════════════════════════════════════════════════════');
      if (dayRKOs.isEmpty) {
        Logger.debug('   ⚠️ РКО не найдено для даты ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
      } else {
        Logger.debug('   📋 Список всех РКО для обработки:');
        for (var rko in dayRKOs) {
          Logger.debug('      - employeeName: "${rko.employeeName}"');
          Logger.debug('        date: ${rko.date.year}-${rko.date.month}-${rko.date.day}');
          Logger.debug('        shopAddress: "${rko.shopAddress}"');
        }
      }
      Logger.debug('   📋 Доступные ключи в employeesDataMap: ${employeesDataMap.keys.toList()}');
      Logger.debug('   📋 Детали записей в employeesDataMap:');
      for (var entry in employeesDataMap.entries) {
        Logger.debug('      - ключ: "$entry.key", имя: "${entry.value.employeeName}"');
      }
      
      for (var rko in dayRKOs) {
        final key = normalizeEmployeeName(rko.employeeName); // Нормализуем имя
        Logger.debug('   🔍 Обработка РКО:');
        Logger.debug('      - Оригинальное имя: "${rko.employeeName}"');
        Logger.debug('      - Нормализованный ключ: "$key"');
        final existing = employeesDataMap[key];
        if (existing != null) {
          Logger.debug('      ✅ Найдена существующая запись для "$key"');
          Logger.debug('         Имя в записи: "${existing.employeeName}"');
          Logger.debug('         Обновляем hasRKO=true');
        } else {
          Logger.debug('      ⚠️ Запись для "$key" не найдена, создаем новую');
          Logger.debug('      📋 Попытка найти похожие ключи...');
          bool foundSimilar = false;
          for (var existingKey in employeesDataMap.keys) {
            if (existingKey.toLowerCase().contains(key.toLowerCase()) || key.toLowerCase().contains(existingKey.toLowerCase())) {
              Logger.debug('         - Найден похожий ключ: "$existingKey" (искомый: "$key")');
              foundSimilar = true;
            }
          }
          if (!foundSimilar) {
            Logger.debug('         - Похожих ключей не найдено');
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
      // isTargetDate уже объявлена выше
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
          final timeStr = emp.attendanceTime != null 
              ? '${emp.attendanceTime!.hour.toString().padLeft(2, '0')}:${emp.attendanceTime!.minute.toString().padLeft(2, '0')}'
              : 'null';
          Logger.debug('      - ${emp.employeeName}: приход=${emp.attendanceTime != null}, пересменка=${emp.hasShift}, пересчет=${emp.hasRecount}, РКО=${emp.hasRKO}, время=$timeStr');
          Logger.debug('         attendanceTime объект: ${emp.attendanceTime?.toIso8601String() ?? "null"}');
          Logger.debug('         attendanceTime is null: ${emp.attendanceTime == null}');
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

      // Получаем пересменки за период (с сервера)
      final allShifts = await ShiftReportService.getReports(
        employeeName: employeeName,
      );
      final employeeShifts = allShifts.where((shift) {
        final shiftMonth = DateTime(shift.createdAt.year, shift.createdAt.month, 1);
        return shiftMonth == currentMonth || shiftMonth == previousMonth;
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

      // Получаем всех сотрудников из отметок прихода
      final attendanceRecords = await AttendanceService.getAttendanceRecords();
      
      Logger.debug('Загружено записей прихода: ${attendanceRecords.length}');
      
      final employeesSet = <String>{};
      for (var record in attendanceRecords) {
        if (record.employeeName.isNotEmpty) {
          // Нормализуем имя (убираем лишние пробелы, приводим к единому формату)
          final normalizedName = record.employeeName.trim();
          if (normalizedName.isNotEmpty) {
            employeesSet.add(normalizedName);
            Logger.debug('Добавлен сотрудник: "$normalizedName"');
          }
        }
      }

      Logger.debug('Всего уникальных сотрудников: ${employeesSet.length}');
      final employees = employeesSet.toList()..sort();
      Logger.debug('Список сотрудников: $employees');
      
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

  /// Получить данные по сотруднику, сгруппированные по магазинам и датам
  static Future<List<KPIEmployeeShopDayData>> getEmployeeShopDaysData(
    String employeeName,
  ) async {
    try {
      // Проверяем кэш
      final cacheKey = 'kpi_employee_shop_days_$employeeName';
      final cached = CacheManager.get<List<KPIEmployeeShopDayData>>(cacheKey);
      if (cached != null) {
        Logger.debug('KPI данные сотрудника (по магазинам) загружены из кэша');
        return cached;
      }

      Logger.debug('Загрузка KPI данных для сотрудника $employeeName (по магазинам)');

      // Получаем данные за последние 2 месяца (текущий и предыдущий)
      // Это нужно для отображения актуальных данных
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month, 1);
      DateTime previousMonth;
      if (now.month == 1) {
        previousMonth = DateTime(now.year - 1, 12, 1);
      } else {
        previousMonth = DateTime(now.year, now.month - 1, 1);
      }
      
      Logger.debug('Фильтрация по месяцам: текущий=${currentMonth.year}-${currentMonth.month}, предыдущий=${previousMonth.year}-${previousMonth.month}');

      // Получаем отметки прихода за период
      final attendanceRecords = await AttendanceService.getAttendanceRecords(
        employeeName: employeeName,
      );

      // Фильтруем по текущему и предыдущему месяцу
      final filteredAttendance = attendanceRecords.where((record) {
        final recordMonth = DateTime(record.timestamp.year, record.timestamp.month, 1);
        return recordMonth == currentMonth || recordMonth == previousMonth;
      }).toList();

      // Получаем пересменки за период (с сервера)
      final allShifts = await ShiftReportService.getReports(
        employeeName: employeeName,
      );
      final employeeShifts = allShifts.where((shift) {
        final shiftMonth = DateTime(shift.createdAt.year, shift.createdAt.month, 1);
        return shiftMonth == currentMonth || shiftMonth == previousMonth;
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
        Logger.debug('📋 Загружено РКО для $employeeName: ${rkoList.items.length}');
        filteredRKOs.addAll(rkoList.items.where((rko) {
          final rkoMonth = DateTime(rko.date.year, rko.date.month, 1);
          final matches = rkoMonth == currentMonth || rkoMonth == previousMonth;
          if (!matches) {
            Logger.debug('   РКО отфильтровано: дата=${rko.date.year}-${rko.date.month}-${rko.date.day}, месяц=${rkoMonth.year}-${rkoMonth.month}');
          } else {
            Logger.debug('   ✅ РКО прошло фильтр: дата=${rko.date.year}-${rko.date.month}-${rko.date.day}, магазин=${rko.shopAddress}');
          }
          return matches;
        }));
        Logger.debug('📋 РКО после фильтрации: ${filteredRKOs.length}');
      } else {
        Logger.debug('⚠️ РКО не загружены для $employeeName');
      }

      // Агрегируем данные по магазинам и датам (ключ: shopAddress_dateKey)
      final Map<String, KPIEmployeeShopDayData> shopDaysMap = {};

      // Функция для создания ключа магазин+дата
      String createShopDayKey(String shopAddress, DateTime date) {
        final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        return '$shopAddress|$dateKey';
      }

      // Добавляем данные из отметок прихода
      for (var record in filteredAttendance) {
        final date = DateTime(
          record.timestamp.year,
          record.timestamp.month,
          record.timestamp.day,
        );
        final key = createShopDayKey(record.shopAddress, date);
        
        if (!shopDaysMap.containsKey(key)) {
          shopDaysMap[key] = KPIEmployeeShopDayData(
            date: date,
            shopAddress: record.shopAddress,
            employeeName: employeeName,
            attendanceTime: record.timestamp.isUtc ? record.timestamp.toLocal() : record.timestamp,
          );
        } else {
          // Обновляем время прихода, если текущее раньше
          final existing = shopDaysMap[key]!;
          final recordTime = record.timestamp.isUtc ? record.timestamp.toLocal() : record.timestamp;
          final earliestTime = existing.attendanceTime == null || 
              (recordTime.isBefore(existing.attendanceTime!)) 
              ? recordTime 
              : existing.attendanceTime!;
          
          shopDaysMap[key] = KPIEmployeeShopDayData(
            date: date,
            shopAddress: record.shopAddress,
            employeeName: employeeName,
            attendanceTime: earliestTime,
            hasShift: existing.hasShift,
            hasRecount: existing.hasRecount,
            hasRKO: existing.hasRKO,
            rkoFileName: existing.rkoFileName,
            recountReportId: existing.recountReportId,
            shiftReportId: existing.shiftReportId,
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
        final key = createShopDayKey(shift.shopAddress, date);
        
        if (!shopDaysMap.containsKey(key)) {
          shopDaysMap[key] = KPIEmployeeShopDayData(
            date: date,
            shopAddress: shift.shopAddress,
            employeeName: employeeName,
            hasShift: true,
            shiftReportId: shift.id,
          );
        } else {
          final existing = shopDaysMap[key]!;
          shopDaysMap[key] = KPIEmployeeShopDayData(
            date: date,
            shopAddress: shift.shopAddress,
            employeeName: employeeName,
            attendanceTime: existing.attendanceTime,
            hasShift: true,
            hasRecount: existing.hasRecount,
            hasRKO: existing.hasRKO,
            rkoFileName: existing.rkoFileName,
            recountReportId: existing.recountReportId,
            shiftReportId: shift.id,
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
        final key = createShopDayKey(recount.shopAddress, date);
        
        if (!shopDaysMap.containsKey(key)) {
          shopDaysMap[key] = KPIEmployeeShopDayData(
            date: date,
            shopAddress: recount.shopAddress,
            employeeName: employeeName,
            hasRecount: true,
            recountReportId: recount.id,
          );
        } else {
          final existing = shopDaysMap[key]!;
          shopDaysMap[key] = KPIEmployeeShopDayData(
            date: date,
            shopAddress: recount.shopAddress,
            employeeName: employeeName,
            attendanceTime: existing.attendanceTime,
            hasShift: existing.hasShift,
            hasRecount: true,
            hasRKO: existing.hasRKO,
            rkoFileName: existing.rkoFileName,
            recountReportId: recount.id,
            shiftReportId: existing.shiftReportId,
          );
        }
      }

      // Добавляем данные из РКО
      Logger.debug('📋 Обработка РКО: всего ${filteredRKOs.length} записей');
      for (var rko in filteredRKOs) {
        final date = DateTime(
          rko.date.year,
          rko.date.month,
          rko.date.day,
        );
        final key = createShopDayKey(rko.shopAddress, date);
        Logger.debug('   РКО: дата=${date.year}-${date.month}-${date.day}, магазин="${rko.shopAddress}", ключ="$key"');
        
        if (!shopDaysMap.containsKey(key)) {
          Logger.debug('   Создана новая запись для РКО');
          shopDaysMap[key] = KPIEmployeeShopDayData(
            date: date,
            shopAddress: rko.shopAddress,
            employeeName: employeeName,
            hasRKO: true,
            rkoFileName: rko.fileName,
          );
        } else {
          Logger.debug('   Обновлена существующая запись: добавлено РКО');
          final existing = shopDaysMap[key]!;
          shopDaysMap[key] = KPIEmployeeShopDayData(
            date: date,
            shopAddress: rko.shopAddress,
            employeeName: employeeName,
            attendanceTime: existing.attendanceTime,
            hasShift: existing.hasShift,
            hasRecount: existing.hasRecount,
            hasRKO: true,
            rkoFileName: rko.fileName,
            recountReportId: existing.recountReportId,
            shiftReportId: existing.shiftReportId,
          );
        }
      }

      // Сортируем по дате (новые первыми)
      final result = shopDaysMap.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      // Сохраняем в кэш
      CacheManager.set(cacheKey, result, duration: cacheDuration);

      return result;
    } catch (e) {
      Logger.error('Ошибка получения KPI данных сотрудника (по магазинам)', e);
      return [];
    }
  }
}


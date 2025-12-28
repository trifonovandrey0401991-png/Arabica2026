import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/work_schedule_model.dart';
import '../../../core/utils/logger.dart';

class WorkScheduleService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/work-schedule';

  /// Получить график на месяц
  static Future<WorkSchedule> getSchedule(DateTime month) async {
    try {
      final monthStr = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      final uri = Uri.parse('$baseUrl?month=$monthStr');
      
      Logger.debug('📅 Загрузка графика на месяц: $monthStr');
      
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final schedule = WorkSchedule.fromJson(data['schedule']);
          Logger.debug('✅ Загружен график: ${schedule.entries.length} записей');
          return schedule;
        } else {
          throw Exception(data['error'] ?? 'Ошибка загрузки графика');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки графика', e);
      // Возвращаем пустой график при ошибке
      return WorkSchedule(month: month, entries: []);
    }
  }

  /// Получить график конкретного сотрудника
  static Future<WorkSchedule> getEmployeeSchedule(String employeeId, DateTime month) async {
    try {
      final monthStr = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      final uri = Uri.parse('$baseUrl/employee/$employeeId?month=$monthStr');
      
      Logger.debug('📅 Загрузка графика сотрудника: $employeeId, месяц: $monthStr');
      
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final schedule = WorkSchedule.fromJson(data['schedule']);
          Logger.debug('✅ Загружен график сотрудника: ${schedule.entries.length} записей');
          return schedule;
        } else {
          throw Exception(data['error'] ?? 'Ошибка загрузки графика');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки графика сотрудника', e);
      return WorkSchedule(month: month, entries: []);
    }
  }

  /// Сохранить смену (создать или обновить)
  static Future<bool> saveShift(WorkScheduleEntry entry) async {
    try {
      Logger.debug('💾 Сохранение смены: ${entry.employeeName}, ${entry.date.toIso8601String().split('T')[0]}, ${entry.shiftType.label}');
      
      // Добавляем месяц в формат YYYY-MM
      final monthStr = '${entry.date.year}-${entry.date.month.toString().padLeft(2, '0')}';
      final entryJson = entry.toJson();
      entryJson['month'] = monthStr;
      
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(entryJson),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('✅ Смена сохранена');
          return true;
        } else {
          throw Exception(data['error'] ?? 'Ошибка сохранения смены');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('❌ Ошибка сохранения смены', e);
      return false;
    }
  }

  /// Удалить смену
  static Future<bool> deleteShift(String entryId) async {
    try {
      Logger.debug('🗑️ Удаление смены: $entryId');
      
      final response = await http.delete(
        Uri.parse('$baseUrl/$entryId'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('✅ Смена удалена');
          return true;
        } else {
          throw Exception(data['error'] ?? 'Ошибка удаления смены');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('❌ Ошибка удаления смены', e);
      return false;
    }
  }

  /// Массовое создание смен
  static Future<bool> bulkCreateShifts(List<WorkScheduleEntry> entries) async {
    try {
      Logger.debug('📦 Массовое создание смен: ${entries.length} записей');
      
      final response = await http.post(
        Uri.parse('$baseUrl/bulk'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'entries': entries.map((e) => e.toJson()).toList(),
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('✅ Массовое создание завершено');
          return true;
        } else {
          throw Exception(data['error'] ?? 'Ошибка массового создания');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('❌ Ошибка массового создания смен', e);
      return false;
    }
  }

  /// Копировать неделю
  static Future<bool> copyWeek({
    required DateTime sourceWeekStart,
    required DateTime targetWeekStart,
    required List<String> employeeIds,
  }) async {
    try {
      // Получаем график на месяц источника
      final sourceMonth = DateTime(sourceWeekStart.year, sourceWeekStart.month);
      final sourceSchedule = await getSchedule(sourceMonth);
      
      // Фильтруем записи за неделю источника
      final sourceEntries = sourceSchedule.entries.where((entry) {
        final entryDate = DateTime(entry.date.year, entry.date.month, entry.date.day);
        final weekStart = sourceWeekStart;
        final weekEnd = weekStart.add(const Duration(days: 6));
        return entryDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
               entryDate.isBefore(weekEnd.add(const Duration(days: 1))) &&
               employeeIds.contains(entry.employeeId);
      }).toList();
      
      // Создаем новые записи для целевой недели
      final daysDiff = targetWeekStart.difference(sourceWeekStart).inDays;
      final targetEntries = sourceEntries.map((entry) {
        final newDate = entry.date.add(Duration(days: daysDiff));
        return entry.copyWith(
          id: '', // Новый ID будет создан на сервере
          date: newDate,
        );
      }).toList();
      
      // Сохраняем массово
      return await bulkCreateShifts(targetEntries);
    } catch (e) {
      Logger.error('❌ Ошибка копирования недели', e);
      return false;
    }
  }

  /// Сохранить шаблон
  static Future<bool> saveTemplate(ScheduleTemplate template) async {
    try {
      Logger.debug('💾 Сохранение шаблона: ${template.name}');
      
      final response = await http.post(
        Uri.parse('$baseUrl/template'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'save',
          'template': template.toJson(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('✅ Шаблон сохранен');
          return true;
        } else {
          throw Exception(data['error'] ?? 'Ошибка сохранения шаблона');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('❌ Ошибка сохранения шаблона', e);
      return false;
    }
  }

  /// Получить список шаблонов
  static Future<List<ScheduleTemplate>> getTemplates() async {
    try {
      Logger.debug('📋 Загрузка шаблонов');
      
      final response = await http.get(
        Uri.parse('$baseUrl/template'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final templates = (data['templates'] as List<dynamic>)
              .map((t) => ScheduleTemplate.fromJson(t as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено шаблонов: ${templates.length}');
          return templates;
        } else {
          throw Exception(data['error'] ?? 'Ошибка загрузки шаблонов');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки шаблонов', e);
      return [];
    }
  }

  /// Применить шаблон
  static Future<bool> applyTemplate(ScheduleTemplate template, DateTime targetWeekStart) async {
    try {
      Logger.debug('📋 Применение шаблона: ${template.name}');
      
      // Создаем записи на основе шаблона, начиная с targetWeekStart
      final targetEntries = <WorkScheduleEntry>[];
      final templateDays = template.entries.map((e) => e.date.day).toSet().toList()..sort();
      final firstTemplateDay = templateDays.isNotEmpty ? templateDays.first : 1;
      
      for (var entry in template.entries) {
        final daysOffset = entry.date.day - firstTemplateDay;
        final newDate = targetWeekStart.add(Duration(days: daysOffset));
        targetEntries.add(entry.copyWith(
          id: '',
          date: newDate,
        ));
      }
      
      return await bulkCreateShifts(targetEntries);
    } catch (e) {
      Logger.error('❌ Ошибка применения шаблона', e);
      return false;
    }
  }
}


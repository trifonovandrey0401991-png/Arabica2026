import '../../models/efficiency_data_model.dart';
import '../efficiency_calculation_service.dart';
import '../../../shifts/services/shift_report_service.dart';
import '../../../recount/services/recount_service.dart';
import '../../../shift_handover/services/shift_handover_report_service.dart';
import '../../../attendance/services/attendance_service.dart';
import '../../../tasks/services/task_service.dart';
import '../../../tasks/models/task_model.dart';
import '../../../reviews/services/review_service.dart';
import '../../../../core/services/base_http_service.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/logger.dart';

/// Загрузчики данных эффективности из разных источников
///
/// Эти функции загружают данные из отдельных сервисов и преобразуют в EfficiencyRecord.
/// Извлечены из efficiency_data_service.dart для лучшей организации кода.

/// Загрузить записи пересменки
Future<List<EfficiencyRecord>> loadShiftRecords(
  DateTime start,
  DateTime end,
) async {
  try {
    Logger.debug('Loading shift reports...');
    final reports = await ShiftReportService.getReports();

    final records = <EfficiencyRecord>[];
    for (final report in reports) {
      // Проверяем период и наличие оценки
      if (report.createdAt.isBefore(start) || report.createdAt.isAfter(end)) {
        continue;
      }

      if (report.rating == null || report.rating! < 1) {
        continue; // Пропускаем неоцененные отчеты
      }

      final record = await EfficiencyCalculationService.createShiftRecord(
        id: report.id,
        shopAddress: report.shopAddress,
        employeeName: report.employeeName,
        date: report.confirmedAt ?? report.createdAt,
        rating: report.rating!,
      );

      if (record != null) {
        records.add(record);
      }
    }

    Logger.debug('Loaded ${records.length} shift efficiency records');
    return records;
  } catch (e) {
    Logger.error('Error loading shift records', e);
    return [];
  }
}

/// Загрузить записи пересчета
Future<List<EfficiencyRecord>> loadRecountRecords(
  DateTime start,
  DateTime end,
) async {
  try {
    Logger.debug('Loading recount reports...');
    final reports = await RecountService.getReports();

    final records = <EfficiencyRecord>[];
    for (final report in reports) {
      // Проверяем период и наличие оценки
      if (report.completedAt.isBefore(start) || report.completedAt.isAfter(end)) {
        continue;
      }

      if (report.adminRating == null || report.adminRating! < 1) {
        continue; // Пропускаем неоцененные отчеты
      }

      final record = await EfficiencyCalculationService.createRecountRecord(
        id: report.id,
        shopAddress: report.shopAddress,
        employeeName: report.employeeName,
        date: report.ratedAt ?? report.completedAt,
        adminRating: report.adminRating,
      );

      if (record != null) {
        records.add(record);
      }
    }

    Logger.debug('Loaded ${records.length} recount efficiency records');
    return records;
  } catch (e) {
    Logger.error('Error loading recount records', e);
    return [];
  }
}

/// Загрузить записи сдачи смены
Future<List<EfficiencyRecord>> loadShiftHandoverRecords(
  DateTime start,
  DateTime end,
) async {
  try {
    Logger.debug('Loading shift handover reports...');
    final reports = await ShiftHandoverReportService.getReports();

    final records = <EfficiencyRecord>[];
    for (final report in reports) {
      // Проверяем период и наличие оценки
      if (report.createdAt.isBefore(start) || report.createdAt.isAfter(end)) {
        continue;
      }

      if (report.rating == null || report.rating! < 1) {
        continue; // Пропускаем неоцененные отчеты
      }

      final record = await EfficiencyCalculationService.createShiftHandoverRecord(
        id: report.id,
        shopAddress: report.shopAddress,
        employeeName: report.employeeName,
        date: report.confirmedAt ?? report.createdAt,
        rating: report.rating,
      );

      if (record != null) {
        records.add(record);
      }
    }

    Logger.debug('Loaded ${records.length} shift handover efficiency records');
    return records;
  } catch (e) {
    Logger.error('Error loading shift handover records', e);
    return [];
  }
}

/// Загрузить записи посещаемости
Future<List<EfficiencyRecord>> loadAttendanceRecords(
  DateTime start,
  DateTime end,
) async {
  try {
    Logger.debug('Loading attendance records...');
    final attendanceRecords = await AttendanceService.getAttendanceRecords();

    final records = <EfficiencyRecord>[];
    for (final attendance in attendanceRecords) {
      // Проверяем период
      if (attendance.timestamp.isBefore(start) || attendance.timestamp.isAfter(end)) {
        continue;
      }

      // isOnTime может быть null если сотрудник отметился вне смены
      if (attendance.isOnTime == null) {
        continue;
      }

      final record = await EfficiencyCalculationService.createAttendanceRecord(
        id: attendance.id,
        shopAddress: attendance.shopAddress,
        employeeName: attendance.employeeName,
        date: attendance.timestamp,
        isOnTime: attendance.isOnTime!,
      );

      records.add(record);
    }

    Logger.debug('Loaded ${records.length} attendance efficiency records');
    return records;
  } catch (e) {
    Logger.error('Error loading attendance records', e);
    return [];
  }
}

/// Загрузить штрафы с сервера
Future<List<EfficiencyRecord>> loadPenaltyRecords(
  DateTime start,
  DateTime end,
) async {
  try {
    Logger.debug('Loading penalty records from server...');

    // Формируем месяц для запроса (YYYY-MM)
    final monthKey = '${start.year}-${start.month.toString().padLeft(2, '0')}';

    final result = await BaseHttpService.getRaw(
      endpoint: '${ApiConstants.efficiencyPenaltiesEndpoint}?month=$monthKey',
    );

    if (result != null) {
      final penalties = (result['penalties'] as List<dynamic>)
          .map((json) => EfficiencyPenalty.fromJson(json as Map<String, dynamic>))
          .toList();

      Logger.debug('Loaded ${penalties.length} penalties from server');

      // Преобразуем штрафы в записи эффективности
      final records = <EfficiencyRecord>[];
      for (final penalty in penalties) {
        records.add(penalty.toRecord());
      }

      return records;
    }

    return [];
  } catch (e) {
    Logger.error('Error loading penalty records', e);
    return [];
  }
}

/// Загрузить записи по задачам
Future<List<EfficiencyRecord>> loadTaskRecords(
  DateTime start,
  DateTime end,
) async {
  try {
    Logger.debug('Loading task assignments...');
    final assignments = await TaskService.getAllAssignments();

    final records = <EfficiencyRecord>[];
    for (final assignment in assignments) {
      // Проверяем период (по времени ответа или проверки)
      DateTime? recordDate;
      if (assignment.status == TaskStatus.approved ||
          assignment.status == TaskStatus.rejected) {
        recordDate = assignment.reviewedAt;
      } else if (assignment.status == TaskStatus.declined) {
        recordDate = assignment.respondedAt ?? assignment.deadline;
      } else if (assignment.status == TaskStatus.expired) {
        recordDate = assignment.deadline;
      }

      if (recordDate == null) continue;
      if (recordDate.isBefore(start) || recordDate.isAfter(end)) continue;

      // Определяем баллы по статусу
      double points;
      switch (assignment.status) {
        case TaskStatus.approved:
          points = 1.0; // +1 за выполненную задачу
          break;
        case TaskStatus.rejected:
          points = -3.0; // -3 за отклоненную админом
          break;
        case TaskStatus.expired:
          points = -3.0; // -3 за просроченную
          break;
        case TaskStatus.declined:
          points = -3.0; // -3 за отказ
          break;
        default:
          continue; // Пропускаем pending/submitted
      }

      records.add(EfficiencyRecord(
        id: assignment.id,
        category: EfficiencyCategory.tasks,
        shopAddress: '', // Задачи не привязаны к магазинам
        employeeName: assignment.assigneeName,
        date: recordDate,
        points: points,
        rawValue: {
          'status': assignment.status.name,
          'taskTitle': assignment.task?.title ?? 'Задача',
        },
        sourceId: assignment.taskId,
      ));
    }

    Logger.debug('Loaded ${records.length} task efficiency records');
    return records;
  } catch (e) {
    Logger.error('Error loading task records', e);
    return [];
  }
}

/// Загрузить записи по отзывам
Future<List<EfficiencyRecord>> loadReviewRecords(
  DateTime start,
  DateTime end,
) async {
  try {
    Logger.debug('Loading review records...');
    final reviews = await ReviewService.getAllReviews();

    final records = <EfficiencyRecord>[];
    for (final review in reviews) {
      // Проверяем период
      if (review.createdAt.isBefore(start) || review.createdAt.isAfter(end)) {
        continue;
      }

      final isPositive = review.reviewType == 'positive';
      final record = await EfficiencyCalculationService.createReviewRecord(
        id: review.id,
        shopAddress: review.shopAddress,
        date: review.createdAt,
        isPositive: isPositive,
      );

      records.add(record);
    }

    Logger.debug('Loaded ${records.length} review efficiency records');
    return records;
  } catch (e) {
    Logger.error('Error loading review records', e);
    return [];
  }
}

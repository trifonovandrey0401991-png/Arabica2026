import '../../models/efficiency_data_model.dart';
import '../efficiency_calculation_service.dart';
import '../../../shifts/services/shift_report_service.dart';
import '../../../recount/services/recount_service.dart';
import '../../../shift_handover/services/shift_handover_report_service.dart';
import '../../../attendance/services/attendance_service.dart';
import '../../../tasks/services/task_service.dart';
import '../../../tasks/models/task_model.dart';
import '../../../reviews/services/review_service.dart';
import '../../../product_questions/services/product_question_service.dart';
import '../../../orders/services/order_service.dart';
import '../../../rko/services/rko_reports_service.dart';
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

/// Загрузить записи по поиску товара (ответы на вопросы клиентов)
///
/// Баллы начисляются сотруднику, который ответил на вопрос.
/// Неотвеченные вопросы не учитываются (нет конкретного виновного).
Future<List<EfficiencyRecord>> loadProductSearchRecords(
  DateTime start,
  DateTime end,
) async {
  try {
    Logger.debug('Loading product search records...');
    // Загружаем все вопросы
    final questions = await ProductQuestionService.getQuestions();

    final records = <EfficiencyRecord>[];
    for (final question in questions) {
      // Парсим дату вопроса
      final questionDate = DateTime.tryParse(question.timestamp);
      if (questionDate == null) continue;

      // Проверяем период
      if (questionDate.isBefore(start) || questionDate.isAfter(end)) continue;

      // Если вопрос отвечен - создаём запись для ответившего сотрудника
      if (question.isAnswered &&
          question.answeredByName != null &&
          question.answeredByName!.isNotEmpty) {
        // Используем время ответа если есть, иначе время вопроса
        final answerDate = question.lastAnswerTime != null
            ? DateTime.tryParse(question.lastAnswerTime!)
            : questionDate;

        final record = await EfficiencyCalculationService.createProductSearchRecord(
          id: question.id,
          shopAddress: question.shopAddress,
          employeeName: question.answeredByName!,
          date: answerDate ?? questionDate,
          answered: true,
        );

        records.add(record);
      }
      // Примечание: неотвеченные вопросы не учитываем,
      // т.к. нет конкретного сотрудника для начисления штрафа
    }

    Logger.debug('Loaded ${records.length} product search efficiency records');
    return records;
  } catch (e) {
    Logger.error('Error loading product search records', e);
    return [];
  }
}

/// Загрузить записи по заказам клиентов
///
/// Баллы начисляются:
/// - За принятый заказ: сотруднику из поля acceptedBy
/// - За отклонённый заказ: сотруднику из поля rejectedBy
Future<List<EfficiencyRecord>> loadOrderRecords(
  DateTime start,
  DateTime end,
) async {
  try {
    Logger.debug('Loading order records...');
    // Загружаем все заказы
    final orders = await OrderService.getAllOrders();

    final records = <EfficiencyRecord>[];
    for (final order in orders) {
      // Парсим дату создания заказа
      final createdAtStr = order['createdAt'] as String?;
      if (createdAtStr == null) continue;

      final orderDate = DateTime.tryParse(createdAtStr);
      if (orderDate == null) continue;

      // Проверяем период
      if (orderDate.isBefore(start) || orderDate.isAfter(end)) continue;

      final status = order['status'] as String? ?? 'pending';
      final shopAddress = order['shopAddress'] as String? ?? '';
      final orderId = order['id'] as String? ?? '';

      // Принятые заказы (accepted, confirmed, delivered)
      if (status == 'accepted' || status == 'confirmed' || status == 'delivered') {
        final acceptedBy = order['acceptedBy'] as String?;
        if (acceptedBy != null && acceptedBy.isNotEmpty) {
          final record = await EfficiencyCalculationService.createOrderRecord(
            id: orderId,
            shopAddress: shopAddress,
            employeeName: acceptedBy,
            date: orderDate,
            accepted: true,
          );
          records.add(record);
        }
      }
      // Отклонённые заказы
      else if (status == 'rejected') {
        final rejectedBy = order['rejectedBy'] as String?;
        if (rejectedBy != null && rejectedBy.isNotEmpty) {
          final record = await EfficiencyCalculationService.createOrderRecord(
            id: orderId,
            shopAddress: shopAddress,
            employeeName: rejectedBy,
            date: orderDate,
            accepted: false,
          );
          records.add(record);
        }
      }
      // pending и cancelled заказы не учитываем
    }

    Logger.debug('Loaded ${records.length} order efficiency records');
    return records;
  } catch (e) {
    Logger.error('Error loading order records', e);
    return [];
  }
}

/// Загрузить записи по РКО (расходные кассовые ордера)
///
/// Баллы начисляются сотруднику, который создал РКО.
/// Каждый РКО = положительные баллы за наличие.
Future<List<EfficiencyRecord>> loadRkoRecords(
  DateTime start,
  DateTime end,
) async {
  try {
    Logger.debug('Loading RKO records...');

    // Формируем месяц для запроса (YYYY-MM)
    final monthKey = '${start.year}-${start.month.toString().padLeft(2, '0')}';

    // Загружаем все РКО за месяц
    final rkos = await RKOReportsService.getAllRKOs(month: monthKey);

    final records = <EfficiencyRecord>[];
    for (final rko in rkos) {
      // Парсим дату РКО
      final dateStr = rko['date'] as String?;
      if (dateStr == null) continue;

      final rkoDate = DateTime.tryParse(dateStr);
      if (rkoDate == null) continue;

      // Проверяем период
      if (rkoDate.isBefore(start) || rkoDate.isAfter(end)) continue;

      final employeeName = rko['employeeName'] as String? ?? '';
      final shopAddress = rko['shopAddress'] as String? ?? '';
      final fileName = rko['fileName'] as String? ?? '';

      if (employeeName.isEmpty) continue;

      // Создаём запись с положительными баллами (РКО есть)
      final record = await EfficiencyCalculationService.createRkoRecord(
        id: fileName,
        shopAddress: shopAddress,
        employeeName: employeeName,
        date: rkoDate,
        hasRko: true,
      );

      records.add(record);
    }

    Logger.debug('Loaded ${records.length} RKO efficiency records');
    return records;
  } catch (e) {
    Logger.error('Error loading RKO records', e);
    return [];
  }
}

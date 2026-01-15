import '../services/base_http_service.dart';
import '../constants/api_constants.dart';
import '../utils/logger.dart';

/// Типы отчётов для уведомлений
enum ReportType {
  shiftHandover, // Пересменка
  recount,       // Пересчёт товара
  test,          // Тестирование
  shiftReport,   // Сдать смену
  attendance,    // Я на работе
  rko,           // РКО
}

extension ReportTypeExtension on ReportType {
  String get code {
    switch (this) {
      case ReportType.shiftHandover:
        return 'shift_handover';
      case ReportType.recount:
        return 'recount';
      case ReportType.test:
        return 'test';
      case ReportType.shiftReport:
        return 'shift_report';
      case ReportType.attendance:
        return 'attendance';
      case ReportType.rko:
        return 'rko';
    }
  }

  String get displayName {
    switch (this) {
      case ReportType.shiftHandover:
        return 'Пересменка';
      case ReportType.recount:
        return 'Пересчёт товара';
      case ReportType.test:
        return 'Тестирование';
      case ReportType.shiftReport:
        return 'Сдать смену';
      case ReportType.attendance:
        return 'Я на работе';
      case ReportType.rko:
        return 'РКО';
    }
  }

  static ReportType? fromCode(String code) {
    switch (code) {
      case 'shift_handover':
        return ReportType.shiftHandover;
      case 'recount':
        return ReportType.recount;
      case 'test':
        return ReportType.test;
      case 'shift_report':
        return ReportType.shiftReport;
      case 'attendance':
        return ReportType.attendance;
      case 'rko':
        return ReportType.rko;
      default:
        return null;
    }
  }
}

/// Модель счётчиков непросмотренных отчётов
class UnviewedCounts {
  final int shiftHandover;
  final int recount;
  final int test;
  final int shiftReport;
  final int attendance;
  final int rko;
  final int total;

  UnviewedCounts({
    this.shiftHandover = 0,
    this.recount = 0,
    this.test = 0,
    this.shiftReport = 0,
    this.attendance = 0,
    this.rko = 0,
    this.total = 0,
  });

  factory UnviewedCounts.fromJson(Map<String, dynamic> json) {
    return UnviewedCounts(
      shiftHandover: json['shift_handover'] as int? ?? 0,
      recount: json['recount'] as int? ?? 0,
      test: json['test'] as int? ?? 0,
      shiftReport: json['shift_report'] as int? ?? 0,
      attendance: json['attendance'] as int? ?? 0,
      rko: json['rko'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
    );
  }

  int getByType(ReportType type) {
    switch (type) {
      case ReportType.shiftHandover:
        return shiftHandover;
      case ReportType.recount:
        return recount;
      case ReportType.test:
        return test;
      case ReportType.shiftReport:
        return shiftReport;
      case ReportType.attendance:
        return attendance;
      case ReportType.rko:
        return rko;
    }
  }
}

/// Сервис для работы с уведомлениями о новых отчётах
class ReportNotificationService {
  static const String _baseEndpoint = '/api/report-notifications';

  /// Создать уведомление о новом отчёте (вызывается при формировании отчёта)
  static Future<bool> createNotification({
    required ReportType reportType,
    required String reportId,
    required String employeeName,
    String? shopName,
    String? description,
  }) async {
    try {
      Logger.debug('Создание уведомления об отчёте: ${reportType.displayName}');

      final result = await BaseHttpService.postRaw(
        endpoint: _baseEndpoint,
        body: {
          'reportType': reportType.code,
          'reportId': reportId,
          'employeeName': employeeName,
          'shopName': shopName,
          'description': description,
        },
      );

      if (result != null && result['success'] == true) {
        Logger.info('Уведомление создано: ${reportType.displayName} от $employeeName');
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('Ошибка создания уведомления', e);
      return false;
    }
  }

  /// Получить количество непросмотренных отчётов по типам
  static Future<UnviewedCounts> getUnviewedCounts() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/unviewed-counts',
      );

      if (result != null && result['counts'] != null) {
        return UnviewedCounts.fromJson(result['counts'] as Map<String, dynamic>);
      }
      return UnviewedCounts();
    } catch (e) {
      Logger.error('Ошибка получения счётчиков уведомлений', e);
      return UnviewedCounts();
    }
  }

  /// Отметить уведомление как просмотренное по ID отчёта
  static Future<bool> markAsViewed({
    required ReportType reportType,
    required String reportId,
    String? adminName,
  }) async {
    try {
      Logger.debug('Отметка просмотра: ${reportType.code}/$reportId');

      final result = await BaseHttpService.patchRaw(
        endpoint: '$_baseEndpoint/view-by-report',
        body: {
          'reportType': reportType.code,
          'reportId': reportId,
          'adminName': adminName ?? 'admin',
        },
      );

      return result != null && result['success'] == true;
    } catch (e) {
      Logger.error('Ошибка отметки просмотра', e);
      return false;
    }
  }

  /// Отметить все уведомления типа как просмотренные
  static Future<int> markAllAsViewed({
    ReportType? reportType,
    String? adminName,
  }) async {
    try {
      Logger.debug('Отметка всех как просмотренных: ${reportType?.code ?? "все"}');

      final result = await BaseHttpService.postRaw(
        endpoint: '$_baseEndpoint/mark-all-viewed',
        body: {
          'reportType': reportType?.code,
          'adminName': adminName ?? 'admin',
        },
      );

      if (result != null && result['success'] == true) {
        return result['markedCount'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      Logger.error('Ошибка массовой отметки просмотра', e);
      return 0;
    }
  }
}

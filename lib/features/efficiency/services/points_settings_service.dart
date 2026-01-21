import '../models/points_settings_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class PointsSettingsService {
  static const String baseEndpoint = ApiConstants.pointsSettingsEndpoint;

  /// Get test points settings
  static Future<TestPointsSettings> getTestPointsSettings() async {
    Logger.debug('Fetching test points settings...');

    final result = await BaseHttpService.get<TestPointsSettings>(
      endpoint: '$baseEndpoint/test',
      fromJson: (json) => TestPointsSettings.fromJson(json),
      itemKey: 'settings',
    );

    return result ?? TestPointsSettings.defaults();
  }

  /// Save test points settings
  static Future<TestPointsSettings?> saveTestPointsSettings({
    required double minPoints,
    required int zeroThreshold,
    required double maxPoints,
  }) async {
    Logger.debug('Saving test points settings: min=$minPoints, zero=$zeroThreshold, max=$maxPoints');

    return await BaseHttpService.post<TestPointsSettings>(
      endpoint: '$baseEndpoint/test',
      body: {
        'minPoints': minPoints,
        'zeroThreshold': zeroThreshold,
        'maxPoints': maxPoints,
      },
      fromJson: (json) => TestPointsSettings.fromJson(json),
      itemKey: 'settings',
    );
  }

  // ===== ATTENDANCE POINTS =====

  /// Get attendance points settings
  static Future<AttendancePointsSettings> getAttendancePointsSettings() async {
    Logger.debug('Fetching attendance points settings...');

    final result = await BaseHttpService.get<AttendancePointsSettings>(
      endpoint: '$baseEndpoint/attendance',
      fromJson: (json) => AttendancePointsSettings.fromJson(json),
      itemKey: 'settings',
    );

    return result ?? AttendancePointsSettings.defaults();
  }

  /// Save attendance points settings
  static Future<AttendancePointsSettings?> saveAttendancePointsSettings({
    required double onTimePoints,
    required double latePoints,
  }) async {
    Logger.debug('Saving attendance points settings: onTime=$onTimePoints, late=$latePoints');

    return await BaseHttpService.post<AttendancePointsSettings>(
      endpoint: '$baseEndpoint/attendance',
      body: {
        'onTimePoints': onTimePoints,
        'latePoints': latePoints,
      },
      fromJson: (json) => AttendancePointsSettings.fromJson(json),
      itemKey: 'settings',
    );
  }

  // ===== SHIFT POINTS (Пересменка) =====

  /// Get shift points settings
  static Future<ShiftPointsSettings> getShiftPointsSettings() async {
    Logger.debug('Fetching shift points settings...');

    final result = await BaseHttpService.get<ShiftPointsSettings>(
      endpoint: '$baseEndpoint/shift',
      fromJson: (json) => ShiftPointsSettings.fromJson(json),
      itemKey: 'settings',
    );

    return result ?? ShiftPointsSettings.defaults();
  }

  /// Save shift points settings
  static Future<ShiftPointsSettings?> saveShiftPointsSettings({
    required double minPoints,
    required int zeroThreshold,
    required double maxPoints,
    String? morningStartTime,
    String? morningEndTime,
    String? eveningStartTime,
    String? eveningEndTime,
    double? missedPenalty,
  }) async {
    Logger.debug('Saving shift points settings: min=$minPoints, zero=$zeroThreshold, max=$maxPoints');

    final body = <String, dynamic>{
      'minPoints': minPoints,
      'zeroThreshold': zeroThreshold,
      'maxPoints': maxPoints,
    };

    // Add time window settings if provided
    if (morningStartTime != null) body['morningStartTime'] = morningStartTime;
    if (morningEndTime != null) body['morningEndTime'] = morningEndTime;
    if (eveningStartTime != null) body['eveningStartTime'] = eveningStartTime;
    if (eveningEndTime != null) body['eveningEndTime'] = eveningEndTime;
    if (missedPenalty != null) body['missedPenalty'] = missedPenalty;

    return await BaseHttpService.post<ShiftPointsSettings>(
      endpoint: '$baseEndpoint/shift',
      body: body,
      fromJson: (json) => ShiftPointsSettings.fromJson(json),
      itemKey: 'settings',
    );
  }

  // ===== RECOUNT POINTS (Пересчет) =====

  /// Get recount points settings
  static Future<RecountPointsSettings> getRecountPointsSettings() async {
    Logger.debug('Fetching recount points settings...');

    final result = await BaseHttpService.get<RecountPointsSettings>(
      endpoint: '$baseEndpoint/recount',
      fromJson: (json) => RecountPointsSettings.fromJson(json),
      itemKey: 'settings',
    );

    return result ?? RecountPointsSettings.defaults();
  }

  /// Save recount points settings
  static Future<RecountPointsSettings?> saveRecountPointsSettings({
    required double minPoints,
    required int zeroThreshold,
    required double maxPoints,
  }) async {
    Logger.debug('Saving recount points settings: min=$minPoints, zero=$zeroThreshold, max=$maxPoints');

    return await BaseHttpService.post<RecountPointsSettings>(
      endpoint: '$baseEndpoint/recount',
      body: {
        'minPoints': minPoints,
        'zeroThreshold': zeroThreshold,
        'maxPoints': maxPoints,
      },
      fromJson: (json) => RecountPointsSettings.fromJson(json),
      itemKey: 'settings',
    );
  }

  // ===== RKO POINTS (РКО) =====

  /// Get RKO points settings
  static Future<RkoPointsSettings> getRkoPointsSettings() async {
    Logger.debug('Fetching RKO points settings...');

    final result = await BaseHttpService.get<RkoPointsSettings>(
      endpoint: '$baseEndpoint/rko',
      fromJson: (json) => RkoPointsSettings.fromJson(json),
      itemKey: 'settings',
    );

    return result ?? RkoPointsSettings.defaults();
  }

  /// Save RKO points settings
  static Future<RkoPointsSettings?> saveRkoPointsSettings({
    required double hasRkoPoints,
    required double noRkoPoints,
  }) async {
    Logger.debug('Saving RKO points settings: hasRko=$hasRkoPoints, noRko=$noRkoPoints');

    return await BaseHttpService.post<RkoPointsSettings>(
      endpoint: '$baseEndpoint/rko',
      body: {
        'hasRkoPoints': hasRkoPoints,
        'noRkoPoints': noRkoPoints,
      },
      fromJson: (json) => RkoPointsSettings.fromJson(json),
      itemKey: 'settings',
    );
  }

  // ===== SHIFT HANDOVER POINTS (Сдать смену) =====

  /// Get shift handover points settings
  static Future<ShiftHandoverPointsSettings> getShiftHandoverPointsSettings() async {
    Logger.debug('Fetching shift handover points settings...');

    final result = await BaseHttpService.get<ShiftHandoverPointsSettings>(
      endpoint: '$baseEndpoint/shift-handover',
      fromJson: (json) => ShiftHandoverPointsSettings.fromJson(json),
      itemKey: 'settings',
    );

    return result ?? ShiftHandoverPointsSettings.defaults();
  }

  /// Save shift handover points settings
  static Future<ShiftHandoverPointsSettings?> saveShiftHandoverPointsSettings({
    required double minPoints,
    required int zeroThreshold,
    required double maxPoints,
    String? morningStartTime,
    String? morningEndTime,
    String? eveningStartTime,
    String? eveningEndTime,
    double? missedPenalty,
  }) async {
    Logger.debug('Saving shift handover points settings: min=$minPoints, zero=$zeroThreshold, max=$maxPoints');

    final body = <String, dynamic>{
      'minPoints': minPoints,
      'zeroThreshold': zeroThreshold,
      'maxPoints': maxPoints,
    };

    // Add time window settings if provided
    if (morningStartTime != null) body['morningStartTime'] = morningStartTime;
    if (morningEndTime != null) body['morningEndTime'] = morningEndTime;
    if (eveningStartTime != null) body['eveningStartTime'] = eveningStartTime;
    if (eveningEndTime != null) body['eveningEndTime'] = eveningEndTime;
    if (missedPenalty != null) body['missedPenalty'] = missedPenalty;

    return await BaseHttpService.post<ShiftHandoverPointsSettings>(
      endpoint: '$baseEndpoint/shift-handover',
      body: body,
      fromJson: (json) => ShiftHandoverPointsSettings.fromJson(json),
      itemKey: 'settings',
    );
  }

  // ===== REVIEWS POINTS (Отзывы) =====

  /// Get reviews points settings
  static Future<ReviewsPointsSettings> getReviewsPointsSettings() async {
    Logger.debug('Fetching reviews points settings...');

    final result = await BaseHttpService.get<ReviewsPointsSettings>(
      endpoint: '$baseEndpoint/reviews',
      fromJson: (json) => ReviewsPointsSettings.fromJson(json),
      itemKey: 'settings',
    );

    return result ?? ReviewsPointsSettings.defaults();
  }

  /// Save reviews points settings
  static Future<ReviewsPointsSettings?> saveReviewsPointsSettings({
    required double positivePoints,
    required double negativePoints,
  }) async {
    Logger.debug('Saving reviews points settings: positive=$positivePoints, negative=$negativePoints');

    return await BaseHttpService.post<ReviewsPointsSettings>(
      endpoint: '$baseEndpoint/reviews',
      body: {
        'positivePoints': positivePoints,
        'negativePoints': negativePoints,
      },
      fromJson: (json) => ReviewsPointsSettings.fromJson(json),
      itemKey: 'settings',
    );
  }

  // ===== PRODUCT SEARCH POINTS (Поиск товара) =====

  /// Get product search points settings
  static Future<ProductSearchPointsSettings> getProductSearchPointsSettings() async {
    Logger.debug('Fetching product search points settings...');

    final result = await BaseHttpService.get<ProductSearchPointsSettings>(
      endpoint: '$baseEndpoint/product-search',
      fromJson: (json) => ProductSearchPointsSettings.fromJson(json),
      itemKey: 'settings',
    );

    return result ?? ProductSearchPointsSettings.defaults();
  }

  /// Save product search points settings
  static Future<ProductSearchPointsSettings?> saveProductSearchPointsSettings({
    required double answeredPoints,
    required double notAnsweredPoints,
  }) async {
    Logger.debug('Saving product search points settings: answered=$answeredPoints, notAnswered=$notAnsweredPoints');

    return await BaseHttpService.post<ProductSearchPointsSettings>(
      endpoint: '$baseEndpoint/product-search',
      body: {
        'answeredPoints': answeredPoints,
        'notAnsweredPoints': notAnsweredPoints,
      },
      fromJson: (json) => ProductSearchPointsSettings.fromJson(json),
      itemKey: 'settings',
    );
  }

  // ===== ORDERS POINTS (Заказы клиентов) =====

  /// Get orders points settings
  static Future<OrdersPointsSettings> getOrdersPointsSettings() async {
    Logger.debug('Fetching orders points settings...');

    final result = await BaseHttpService.get<OrdersPointsSettings>(
      endpoint: '$baseEndpoint/orders',
      fromJson: (json) => OrdersPointsSettings.fromJson(json),
      itemKey: 'settings',
    );

    return result ?? OrdersPointsSettings.defaults();
  }

  /// Save orders points settings
  static Future<OrdersPointsSettings?> saveOrdersPointsSettings({
    required double acceptedPoints,
    required double rejectedPoints,
  }) async {
    Logger.debug('Saving orders points settings: accepted=$acceptedPoints, rejected=$rejectedPoints');

    return await BaseHttpService.post<OrdersPointsSettings>(
      endpoint: '$baseEndpoint/orders',
      body: {
        'acceptedPoints': acceptedPoints,
        'rejectedPoints': rejectedPoints,
      },
      fromJson: (json) => OrdersPointsSettings.fromJson(json),
      itemKey: 'settings',
    );
  }

  // ===== REGULAR TASK POINTS (Обычные задачи) =====

  /// Get regular task points settings
  static Future<RegularTaskPointsSettings> getRegularTaskPointsSettings() async {
    Logger.debug('Fetching regular task points settings...');

    final result = await BaseHttpService.get<RegularTaskPointsSettings>(
      endpoint: '$baseEndpoint/regular-tasks',
      fromJson: (json) => RegularTaskPointsSettings.fromJson(json),
      itemKey: 'settings',
    );

    return result ?? RegularTaskPointsSettings.defaults();
  }

  /// Save regular task points settings
  static Future<RegularTaskPointsSettings?> saveRegularTaskPointsSettings({
    required double completionPoints,
    required double penaltyPoints,
  }) async {
    Logger.debug('Saving regular task points settings: completion=$completionPoints, penalty=$penaltyPoints');

    return await BaseHttpService.post<RegularTaskPointsSettings>(
      endpoint: '$baseEndpoint/regular-tasks',
      body: {
        'completionPoints': completionPoints,
        'penaltyPoints': penaltyPoints,
      },
      fromJson: (json) => RegularTaskPointsSettings.fromJson(json),
      itemKey: 'settings',
    );
  }

  // ===== RECURRING TASK POINTS (Циклические задачи) =====

  /// Get recurring task points settings
  static Future<RecurringTaskPointsSettings> getRecurringTaskPointsSettings() async {
    Logger.debug('Fetching recurring task points settings...');

    final result = await BaseHttpService.get<RecurringTaskPointsSettings>(
      endpoint: '$baseEndpoint/recurring-tasks',
      fromJson: (json) => RecurringTaskPointsSettings.fromJson(json),
      itemKey: 'settings',
    );

    return result ?? RecurringTaskPointsSettings.defaults();
  }

  /// Save recurring task points settings
  static Future<RecurringTaskPointsSettings?> saveRecurringTaskPointsSettings({
    required double completionPoints,
    required double penaltyPoints,
  }) async {
    Logger.debug('Saving recurring task points settings: completion=$completionPoints, penalty=$penaltyPoints');

    return await BaseHttpService.post<RecurringTaskPointsSettings>(
      endpoint: '$baseEndpoint/recurring-tasks',
      body: {
        'completionPoints': completionPoints,
        'penaltyPoints': penaltyPoints,
      },
      fromJson: (json) => RecurringTaskPointsSettings.fromJson(json),
      itemKey: 'settings',
    );
  }

  // ===== ENVELOPE POINTS (Конверт) =====

  /// Get envelope points settings
  static Future<EnvelopePointsSettings> getEnvelopePointsSettings() async {
    Logger.debug('Fetching envelope points settings...');

    final result = await BaseHttpService.get<EnvelopePointsSettings>(
      endpoint: '$baseEndpoint/envelope',
      fromJson: (json) => EnvelopePointsSettings.fromJson(json),
      itemKey: 'settings',
    );

    return result ?? EnvelopePointsSettings.defaults();
  }

  /// Save envelope points settings
  static Future<EnvelopePointsSettings?> saveEnvelopePointsSettings({
    required double submittedPoints,
    required double notSubmittedPoints,
  }) async {
    Logger.debug('Saving envelope points settings: submitted=$submittedPoints, notSubmitted=$notSubmittedPoints');

    return await BaseHttpService.post<EnvelopePointsSettings>(
      endpoint: '$baseEndpoint/envelope',
      body: {
        'submittedPoints': submittedPoints,
        'notSubmittedPoints': notSubmittedPoints,
      },
      fromJson: (json) => EnvelopePointsSettings.fromJson(json),
      itemKey: 'settings',
    );
  }
}

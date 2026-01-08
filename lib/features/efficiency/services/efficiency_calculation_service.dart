import '../models/efficiency_data_model.dart';
import '../models/points_settings_model.dart';
import 'points_settings_service.dart';
import '../../../core/utils/logger.dart';

/// Сервис расчета баллов эффективности
class EfficiencyCalculationService {
  // Кэш настроек для оптимизации
  static TestPointsSettings? _testSettings;
  static AttendancePointsSettings? _attendanceSettings;
  static ShiftPointsSettings? _shiftSettings;
  static RecountPointsSettings? _recountSettings;
  static RkoPointsSettings? _rkoSettings;
  static ShiftHandoverPointsSettings? _shiftHandoverSettings;
  static ReviewsPointsSettings? _reviewsSettings;
  static ProductSearchPointsSettings? _productSearchSettings;
  static OrdersPointsSettings? _ordersSettings;

  /// Загрузить все настройки баллов
  static Future<void> loadAllSettings() async {
    Logger.debug('Loading all points settings...');

    try {
      final futures = await Future.wait([
        PointsSettingsService.getTestPointsSettings(),
        PointsSettingsService.getAttendancePointsSettings(),
        PointsSettingsService.getShiftPointsSettings(),
        PointsSettingsService.getRecountPointsSettings(),
        PointsSettingsService.getRkoPointsSettings(),
        PointsSettingsService.getShiftHandoverPointsSettings(),
        PointsSettingsService.getReviewsPointsSettings(),
        PointsSettingsService.getProductSearchPointsSettings(),
        PointsSettingsService.getOrdersPointsSettings(),
      ]);

      _testSettings = futures[0] as TestPointsSettings;
      _attendanceSettings = futures[1] as AttendancePointsSettings;
      _shiftSettings = futures[2] as ShiftPointsSettings;
      _recountSettings = futures[3] as RecountPointsSettings;
      _rkoSettings = futures[4] as RkoPointsSettings;
      _shiftHandoverSettings = futures[5] as ShiftHandoverPointsSettings;
      _reviewsSettings = futures[6] as ReviewsPointsSettings;
      _productSearchSettings = futures[7] as ProductSearchPointsSettings;
      _ordersSettings = futures[8] as OrdersPointsSettings;

      Logger.debug('All points settings loaded successfully');
    } catch (e) {
      Logger.error('Error loading points settings: $e');
      // Используем дефолтные значения
      _testSettings = TestPointsSettings.defaults();
      _attendanceSettings = AttendancePointsSettings.defaults();
      _shiftSettings = ShiftPointsSettings.defaults();
      _recountSettings = RecountPointsSettings.defaults();
      _rkoSettings = RkoPointsSettings.defaults();
      _shiftHandoverSettings = ShiftHandoverPointsSettings.defaults();
      _reviewsSettings = ReviewsPointsSettings.defaults();
      _productSearchSettings = ProductSearchPointsSettings.defaults();
      _ordersSettings = OrdersPointsSettings.defaults();
    }
  }

  /// Очистить кэш настроек
  static void clearCache() {
    _testSettings = null;
    _attendanceSettings = null;
    _shiftSettings = null;
    _recountSettings = null;
    _rkoSettings = null;
    _shiftHandoverSettings = null;
    _reviewsSettings = null;
    _productSearchSettings = null;
    _ordersSettings = null;
  }

  /// Получить настройки (с автозагрузкой)
  static Future<TestPointsSettings> get testSettings async {
    if (_testSettings == null) await loadAllSettings();
    return _testSettings!;
  }

  static Future<AttendancePointsSettings> get attendanceSettings async {
    if (_attendanceSettings == null) await loadAllSettings();
    return _attendanceSettings!;
  }

  static Future<ShiftPointsSettings> get shiftSettings async {
    if (_shiftSettings == null) await loadAllSettings();
    return _shiftSettings!;
  }

  static Future<RecountPointsSettings> get recountSettings async {
    if (_recountSettings == null) await loadAllSettings();
    return _recountSettings!;
  }

  static Future<RkoPointsSettings> get rkoSettings async {
    if (_rkoSettings == null) await loadAllSettings();
    return _rkoSettings!;
  }

  static Future<ShiftHandoverPointsSettings> get shiftHandoverSettings async {
    if (_shiftHandoverSettings == null) await loadAllSettings();
    return _shiftHandoverSettings!;
  }

  static Future<ReviewsPointsSettings> get reviewsSettings async {
    if (_reviewsSettings == null) await loadAllSettings();
    return _reviewsSettings!;
  }

  static Future<ProductSearchPointsSettings> get productSearchSettings async {
    if (_productSearchSettings == null) await loadAllSettings();
    return _productSearchSettings!;
  }

  static Future<OrdersPointsSettings> get ordersSettings async {
    if (_ordersSettings == null) await loadAllSettings();
    return _ordersSettings!;
  }

  // ===== МЕТОДЫ РАСЧЕТА БАЛЛОВ =====

  /// Рассчитать баллы за пересменку (rating 1-10)
  static Future<double> calculateShiftPoints(int rating) async {
    final settings = await shiftSettings;
    return settings.calculatePoints(rating);
  }

  /// Рассчитать баллы за пересчет (rating 1-10)
  static Future<double> calculateRecountPoints(int rating) async {
    final settings = await recountSettings;
    return settings.calculatePoints(rating);
  }

  /// Рассчитать баллы за сдачу смены (rating 1-10)
  static Future<double> calculateShiftHandoverPoints(int rating) async {
    final settings = await shiftHandoverSettings;
    return settings.calculatePoints(rating);
  }

  /// Рассчитать баллы за посещаемость
  static Future<double> calculateAttendancePoints(bool isOnTime) async {
    final settings = await attendanceSettings;
    return settings.calculatePoints(isOnTime);
  }

  /// Рассчитать баллы за тест (score - количество правильных ответов из 20)
  static Future<double> calculateTestPoints(int score) async {
    final settings = await testSettings;
    return settings.calculatePoints(score);
  }

  /// Рассчитать баллы за отзыв
  static Future<double> calculateReviewsPoints(bool isPositive) async {
    final settings = await reviewsSettings;
    return settings.calculatePoints(isPositive);
  }

  /// Рассчитать баллы за поиск товара
  static Future<double> calculateProductSearchPoints(bool answered) async {
    final settings = await productSearchSettings;
    return settings.calculatePoints(answered);
  }

  /// Рассчитать баллы за РКО
  static Future<double> calculateRkoPoints(bool hasRko) async {
    final settings = await rkoSettings;
    return settings.calculatePoints(hasRko);
  }

  /// Рассчитать баллы за заказ
  static Future<double> calculateOrdersPoints(bool accepted) async {
    final settings = await ordersSettings;
    return settings.calculatePoints(accepted);
  }

  // ===== СОЗДАНИЕ ЗАПИСЕЙ ЭФФЕКТИВНОСТИ =====

  /// Создать запись эффективности для пересменки
  static Future<EfficiencyRecord?> createShiftRecord({
    required String id,
    required String shopAddress,
    required String employeeName,
    required DateTime date,
    required int rating,
  }) async {
    if (rating < 1) return null; // Нет оценки

    final points = await calculateShiftPoints(rating);
    return EfficiencyRecord(
      id: 'eff_shift_$id',
      category: EfficiencyCategory.shift,
      shopAddress: shopAddress,
      employeeName: employeeName,
      date: date,
      points: points,
      rawValue: rating,
      sourceId: id,
    );
  }

  /// Создать запись эффективности для пересчета
  static Future<EfficiencyRecord?> createRecountRecord({
    required String id,
    required String shopAddress,
    required String employeeName,
    required DateTime date,
    required int? adminRating,
  }) async {
    if (adminRating == null || adminRating < 1) return null;

    final points = await calculateRecountPoints(adminRating);
    return EfficiencyRecord(
      id: 'eff_recount_$id',
      category: EfficiencyCategory.recount,
      shopAddress: shopAddress,
      employeeName: employeeName,
      date: date,
      points: points,
      rawValue: adminRating,
      sourceId: id,
    );
  }

  /// Создать запись эффективности для сдачи смены
  static Future<EfficiencyRecord?> createShiftHandoverRecord({
    required String id,
    required String shopAddress,
    required String employeeName,
    required DateTime date,
    required int? rating,
  }) async {
    if (rating == null || rating < 1) return null;

    final points = await calculateShiftHandoverPoints(rating);
    return EfficiencyRecord(
      id: 'eff_handover_$id',
      category: EfficiencyCategory.shiftHandover,
      shopAddress: shopAddress,
      employeeName: employeeName,
      date: date,
      points: points,
      rawValue: rating,
      sourceId: id,
    );
  }

  /// Создать запись эффективности для посещаемости
  static Future<EfficiencyRecord> createAttendanceRecord({
    required String id,
    required String shopAddress,
    required String employeeName,
    required DateTime date,
    required bool isOnTime,
  }) async {
    final points = await calculateAttendancePoints(isOnTime);
    return EfficiencyRecord(
      id: 'eff_attendance_$id',
      category: EfficiencyCategory.attendance,
      shopAddress: shopAddress,
      employeeName: employeeName,
      date: date,
      points: points,
      rawValue: isOnTime,
      sourceId: id,
    );
  }

  /// Создать запись эффективности для теста
  static Future<EfficiencyRecord> createTestRecord({
    required String id,
    required String employeeName,
    required DateTime date,
    required int score,
    String shopAddress = '',
  }) async {
    final points = await calculateTestPoints(score);
    return EfficiencyRecord(
      id: 'eff_test_$id',
      category: EfficiencyCategory.test,
      shopAddress: shopAddress,
      employeeName: employeeName,
      date: date,
      points: points,
      rawValue: score,
      sourceId: id,
    );
  }

  /// Создать запись эффективности для отзыва
  static Future<EfficiencyRecord> createReviewRecord({
    required String id,
    required String shopAddress,
    required DateTime date,
    required bool isPositive,
    String employeeName = '',
  }) async {
    final points = await calculateReviewsPoints(isPositive);
    return EfficiencyRecord(
      id: 'eff_review_$id',
      category: EfficiencyCategory.reviews,
      shopAddress: shopAddress,
      employeeName: employeeName,
      date: date,
      points: points,
      rawValue: isPositive,
      sourceId: id,
    );
  }

  /// Создать запись эффективности для поиска товара
  static Future<EfficiencyRecord> createProductSearchRecord({
    required String id,
    required String shopAddress,
    required String employeeName,
    required DateTime date,
    required bool answered,
  }) async {
    final points = await calculateProductSearchPoints(answered);
    return EfficiencyRecord(
      id: 'eff_product_$id',
      category: EfficiencyCategory.productSearch,
      shopAddress: shopAddress,
      employeeName: employeeName,
      date: date,
      points: points,
      rawValue: answered,
      sourceId: id,
    );
  }

  /// Создать запись эффективности для РКО
  static Future<EfficiencyRecord> createRkoRecord({
    required String id,
    required String shopAddress,
    required String employeeName,
    required DateTime date,
    required bool hasRko,
  }) async {
    final points = await calculateRkoPoints(hasRko);
    return EfficiencyRecord(
      id: 'eff_rko_$id',
      category: EfficiencyCategory.rko,
      shopAddress: shopAddress,
      employeeName: employeeName,
      date: date,
      points: points,
      rawValue: hasRko,
      sourceId: id,
    );
  }

  /// Создать запись эффективности для заказа
  static Future<EfficiencyRecord> createOrderRecord({
    required String id,
    required String shopAddress,
    required String employeeName,
    required DateTime date,
    required bool accepted,
  }) async {
    final points = await calculateOrdersPoints(accepted);
    return EfficiencyRecord(
      id: 'eff_order_$id',
      category: EfficiencyCategory.orders,
      shopAddress: shopAddress,
      employeeName: employeeName,
      date: date,
      points: points,
      rawValue: accepted,
      sourceId: id,
    );
  }
}

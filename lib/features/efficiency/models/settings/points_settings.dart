/// Настройки баллов эффективности
///
/// Этот файл экспортирует все классы настроек баллов.
/// Для обратной совместимости также экспортируется из points_settings_model.dart

// Базовые классы и миксины
export 'points_settings_base.dart';

// Настройки с рейтингом 1-10 (интерполяция)
export 'shift_points_settings.dart';
export 'recount_points_settings.dart';
export 'shift_handover_points_settings.dart';

// Настройки с временными окнами
export 'attendance_points_settings.dart';
export 'rko_points_settings.dart';

// Простые настройки (положительный/отрицательный)
export 'test_points_settings.dart';
export 'reviews_points_settings.dart';
export 'product_search_points_settings.dart';
export 'orders_points_settings.dart';
export 'envelope_points_settings.dart';

// Настройки задач
export 'task_points_settings.dart';

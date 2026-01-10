import '../../../core/services/base_http_service.dart';
import '../../../core/utils/logger.dart';

/// Модель настроек таймаута заказов
class OrderTimeoutSettings {
  final int timeoutMinutes;
  final int missedOrderPenalty;

  OrderTimeoutSettings({
    required this.timeoutMinutes,
    required this.missedOrderPenalty,
  });

  factory OrderTimeoutSettings.fromJson(Map<String, dynamic> json) {
    return OrderTimeoutSettings(
      timeoutMinutes: json['timeoutMinutes'] as int? ?? 15,
      missedOrderPenalty: json['missedOrderPenalty'] as int? ?? -2,
    );
  }

  Map<String, dynamic> toJson() => {
    'timeoutMinutes': timeoutMinutes,
    'missedOrderPenalty': missedOrderPenalty,
  };
}

/// Сервис для работы с настройками таймаута заказов
class OrderTimeoutSettingsService {
  static const String _endpoint = '/api/points-settings/orders';

  /// Получить настройки таймаута заказов
  static Future<OrderTimeoutSettings> getSettings() async {
    Logger.debug('📥 Загрузка настроек таймаута заказов');

    try {
      final result = await BaseHttpService.getRaw(endpoint: _endpoint);

      if (result != null && result['settings'] != null) {
        Logger.debug('✅ Настройки таймаута загружены');
        return OrderTimeoutSettings.fromJson(result['settings']);
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки настроек таймаута: $e');
    }

    // Возвращаем значения по умолчанию
    return OrderTimeoutSettings(timeoutMinutes: 15, missedOrderPenalty: -2);
  }

  /// Сохранить настройки таймаута заказов
  static Future<bool> saveSettings({
    required int timeoutMinutes,
    required int missedOrderPenalty,
  }) async {
    Logger.debug('📤 Сохранение настроек таймаута: timeout=$timeoutMinutes, penalty=$missedOrderPenalty');

    try {
      final result = await BaseHttpService.simplePut(
        endpoint: _endpoint,
        body: {
          'timeoutMinutes': timeoutMinutes,
          'missedOrderPenalty': missedOrderPenalty,
        },
      );

      if (result) {
        Logger.debug('✅ Настройки таймаута сохранены');
        return true;
      }
    } catch (e) {
      Logger.error('❌ Ошибка сохранения настроек таймаута: $e');
    }

    return false;
  }
}

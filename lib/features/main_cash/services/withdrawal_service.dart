import '../models/withdrawal_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class WithdrawalService {
  static const String baseEndpoint = ApiConstants.withdrawalsEndpoint;

  /// Получить все выемки (с опциональными фильтрами)
  static Future<List<Withdrawal>> getWithdrawals({
    String? shopAddress,
    String? type,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    Logger.debug('Загрузка выемок...');

    final queryParams = <String, String>{};
    if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
    if (type != null) queryParams['type'] = type;
    if (fromDate != null) queryParams['fromDate'] = fromDate.toIso8601String();
    if (toDate != null) queryParams['toDate'] = toDate.toIso8601String();

    try {
      final result = await BaseHttpService.getList<Withdrawal>(
        endpoint: baseEndpoint,
        fromJson: (json) {
          Logger.debug('Парсинг выемки: ${json['id']}');
          try {
            final withdrawal = Withdrawal.fromJson(json);
            Logger.debug('✅ Выемка распарсена: ${withdrawal.id}, магазин: ${withdrawal.shopAddress}');
            return withdrawal;
          } catch (e, stackTrace) {
            Logger.error('❌ Ошибка парсинга выемки ${json['id']}', e);
            Logger.debug('JSON выемки: $json');
            Logger.debug('Stack trace: $stackTrace');
            rethrow;
          }
        },
        listKey: 'withdrawals',
        queryParams: queryParams.isNotEmpty ? queryParams : null,
      );
      Logger.debug('✅ Всего загружено выемок: ${result.length}');
      return result;
    } catch (e, stackTrace) {
      Logger.error('❌ КРИТИЧЕСКАЯ ОШИБКА загрузки выемок', e);
      Logger.debug('Stack trace: $stackTrace');
      return []; // Вернуть пустой список вместо исключения
    }
  }

  /// Создать новую выемку (с валидацией)
  static Future<Withdrawal?> createWithdrawal(Withdrawal withdrawal) async {
    Logger.debug('Создание выемки: ${withdrawal.shopAddress}, ${withdrawal.type}, ${withdrawal.totalAmount}');

    // Валидация перед отправкой
    final validationError = withdrawal.validate();
    if (validationError != null) {
      Logger.error('❌ Ошибка валидации выемки: $validationError', null);
      throw Exception(validationError);
    }

    return await BaseHttpService.post<Withdrawal>(
      endpoint: baseEndpoint,
      body: withdrawal.toJson(),
      fromJson: (json) => Withdrawal.fromJson(json),
      itemKey: 'withdrawal',
    );
  }

  /// Удалить выемку
  static Future<bool> deleteWithdrawal(String id) async {
    Logger.debug('Удаление выемки: $id');
    return await BaseHttpService.delete(endpoint: '$baseEndpoint/$id');
  }

  /// Получить сумму выемок по магазину и типу (только активных)
  static Future<Map<String, double>> getWithdrawalTotals(String shopAddress) async {
    try {
      final withdrawals = await getWithdrawals(shopAddress: shopAddress);

      double oooTotal = 0;
      double ipTotal = 0;

      for (final w in withdrawals) {
        // Учитываем только активные (не отмененные) выемки
        if (w.isActive) {
          if (w.type == 'ooo') {
            oooTotal += w.totalAmount;
          } else if (w.type == 'ip') {
            ipTotal += w.totalAmount;
          }
        }
      }

      return {
        'ooo': oooTotal,
        'ip': ipTotal,
      };
    } catch (e) {
      Logger.error('Ошибка расчета сумм выемок', e);
      return {'ooo': 0, 'ip': 0};
    }
  }

  /// Подтвердить выемку
  static Future<bool> confirmWithdrawal(String id) async {
    Logger.debug('Подтверждение выемки: $id');
    return await BaseHttpService.simplePatch(
      endpoint: '$baseEndpoint/$id/confirm',
      body: {'confirmed': true},
    );
  }

  /// Отменить выемку (undo)
  static Future<Withdrawal?> cancelWithdrawal({
    required String id,
    required String cancelledBy,
    String? cancelReason,
  }) async {
    Logger.debug('Отмена выемки: $id, причина: $cancelReason');

    return await BaseHttpService.patch<Withdrawal>(
      endpoint: '$baseEndpoint/$id/cancel',
      body: {
        'cancelledBy': cancelledBy,
        'cancelReason': cancelReason ?? 'Отменено пользователем',
      },
      fromJson: (json) => Withdrawal.fromJson(json),
      itemKey: 'withdrawal',
    );
  }
}

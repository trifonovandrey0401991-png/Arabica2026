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

    return await BaseHttpService.getList<Withdrawal>(
      endpoint: baseEndpoint,
      fromJson: (json) => Withdrawal.fromJson(json),
      listKey: 'withdrawals',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
  }

  /// Создать новую выемку
  static Future<Withdrawal?> createWithdrawal(Withdrawal withdrawal) async {
    Logger.debug('Создание выемки: ${withdrawal.shopAddress}, ${withdrawal.type}, ${withdrawal.amount}');
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

  /// Получить сумму выемок по магазину и типу
  static Future<Map<String, double>> getWithdrawalTotals(String shopAddress) async {
    try {
      final withdrawals = await getWithdrawals(shopAddress: shopAddress);

      double oooTotal = 0;
      double ipTotal = 0;

      for (final w in withdrawals) {
        if (w.type == 'ooo') {
          oooTotal += w.amount;
        } else if (w.type == 'ip') {
          ipTotal += w.amount;
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
}

import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/withdrawal_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class WithdrawalService {
  static const String baseEndpoint = '/api/withdrawals';

  /// Получить все выемки (с опциональными фильтрами)
  static Future<List<Withdrawal>> getWithdrawals({
    String? shopAddress,
    String? type,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      Logger.debug('Загрузка выемок...');

      final queryParams = <String, String>{};
      if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
      if (type != null) queryParams['type'] = type;
      if (fromDate != null) queryParams['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) queryParams['toDate'] = toDate.toIso8601String();

      final uri = Uri.parse('${ApiConstants.serverUrl}$baseEndpoint')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final withdrawalsJson = result['withdrawals'] as List<dynamic>;
          final withdrawals = withdrawalsJson
              .map((json) => Withdrawal.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('Загружено выемок: ${withdrawals.length}');
          return withdrawals;
        } else {
          Logger.error('Ошибка загрузки выемок: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('Ошибка API: statusCode=${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('Ошибка загрузки выемок', e);
      return [];
    }
  }

  /// Создать новую выемку
  static Future<Withdrawal?> createWithdrawal(Withdrawal withdrawal) async {
    try {
      Logger.debug('Создание выемки: ${withdrawal.shopAddress}, ${withdrawal.type}, ${withdrawal.amount}');

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(withdrawal.toJson()),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('Выемка создана');
          return Withdrawal.fromJson(result['withdrawal']);
        } else {
          Logger.error('Ошибка создания выемки: ${result['error']}');
          return null;
        }
      } else {
        Logger.error('Ошибка API: statusCode=${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('Ошибка создания выемки', e);
      return null;
    }
  }

  /// Удалить выемку
  static Future<bool> deleteWithdrawal(String id) async {
    try {
      Logger.debug('Удаление выемки: $id');

      final response = await http.delete(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$id'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('Выемка удалена');
          return true;
        } else {
          Logger.error('Ошибка удаления выемки: ${result['error']}');
          return false;
        }
      } else {
        Logger.error('Ошибка API: statusCode=${response.statusCode}');
        return false;
      }
    } catch (e) {
      Logger.error('Ошибка удаления выемки', e);
      return false;
    }
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

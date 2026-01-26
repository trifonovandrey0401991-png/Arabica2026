import '../models/shop_cash_balance_model.dart';
import 'withdrawal_service.dart';
import '../../envelope/services/envelope_report_service.dart';
import '../../shops/services/shop_service.dart';
import '../../../core/utils/logger.dart';

class MainCashService {
  /// Получить балансы всех магазинов
  static Future<List<ShopCashBalance>> getShopBalances() async {
    try {
      Logger.debug('Загрузка балансов всех магазинов...');

      // Загружаем список магазинов
      final shops = await ShopService.getShops();
      if (shops.isEmpty) {
        Logger.debug('Магазины не найдены');
        return [];
      }

      // Загружаем все отчеты конвертов
      final envelopeReports = await EnvelopeReportService.getReports();
      Logger.debug('Загружено отчетов конвертов: ${envelopeReports.length}');

      // Загружаем все выемки
      final withdrawals = await WithdrawalService.getWithdrawals();
      Logger.debug('Загружено выемок: ${withdrawals.length}');

      // Группируем данные по магазинам
      final balances = <ShopCashBalance>[];

      for (final shop in shops) {
        // Суммируем поступления из отчетов конвертов для этого магазина
        double oooIncome = 0;
        double ipIncome = 0;

        for (final report in envelopeReports) {
          if (report.shopAddress == shop.address) {
            oooIncome += report.oooCash;
            ipIncome += report.ipCash;
          }
        }

        // Суммируем операции для этого магазина (только активные, не отмененные)
        double oooWithdrawals = 0;
        double ipWithdrawals = 0;
        double oooDeposits = 0;
        double ipDeposits = 0;

        for (final withdrawal in withdrawals) {
          if (withdrawal.shopAddress == shop.address && withdrawal.isActive) {
            if (withdrawal.category == 'deposit') {
              // Внесение — добавляем к балансу
              if (withdrawal.type == 'ooo') {
                oooDeposits += withdrawal.totalAmount;
              } else if (withdrawal.type == 'ip') {
                ipDeposits += withdrawal.totalAmount;
              }
            } else if (withdrawal.category == 'transfer') {
              // Перенос — вычитаем из источника, добавляем к получателю
              if (withdrawal.transferDirection == 'ooo_to_ip') {
                oooWithdrawals += withdrawal.totalAmount;
                ipDeposits += withdrawal.totalAmount;
              } else if (withdrawal.transferDirection == 'ip_to_ooo') {
                ipWithdrawals += withdrawal.totalAmount;
                oooDeposits += withdrawal.totalAmount;
              }
            } else {
              // Выемка — вычитаем из баланса
              if (withdrawal.type == 'ooo') {
                oooWithdrawals += withdrawal.totalAmount;
              } else if (withdrawal.type == 'ip') {
                ipWithdrawals += withdrawal.totalAmount;
              }
            }
          }
        }

        // Рассчитываем баланс: доход + внесения - выемки
        final oooBalance = oooIncome + oooDeposits - oooWithdrawals;
        final ipBalance = ipIncome + ipDeposits - ipWithdrawals;

        // Добавляем только если были какие-то движения
        if (oooIncome > 0 || ipIncome > 0 || oooWithdrawals > 0 || ipWithdrawals > 0 || oooDeposits > 0 || ipDeposits > 0) {
          Logger.debug('Магазин: ${shop.address}');
          Logger.debug('  ООО: доход=$oooIncome, внесения=$oooDeposits, выемки=$oooWithdrawals, баланс=$oooBalance');
          Logger.debug('  ИП: доход=$ipIncome, внесения=$ipDeposits, выемки=$ipWithdrawals, баланс=$ipBalance');
          Logger.debug('  Итого: ${oooBalance + ipBalance}');
          balances.add(ShopCashBalance(
            shopAddress: shop.address,
            oooBalance: oooBalance,
            ipBalance: ipBalance,
            oooTotalIncome: oooIncome,
            ipTotalIncome: ipIncome,
            oooTotalWithdrawals: oooWithdrawals,
            ipTotalWithdrawals: ipWithdrawals,
          ));
        }
      }

      // Сортируем по адресу
      balances.sort((a, b) => a.shopAddress.compareTo(b.shopAddress));

      Logger.debug('Сформировано балансов: ${balances.length}');
      return balances;
    } catch (e) {
      Logger.error('Ошибка загрузки балансов магазинов', e);
      return [];
    }
  }

  /// Получить баланс конкретного магазина
  static Future<ShopCashBalance?> getShopBalance(String shopAddress) async {
    try {
      Logger.debug('Загрузка баланса магазина: $shopAddress');

      // Загружаем отчеты конвертов для этого магазина
      final envelopeReports = await EnvelopeReportService.getReports(
        shopAddress: shopAddress,
      );

      // Загружаем выемки для этого магазина
      final withdrawals = await WithdrawalService.getWithdrawals(
        shopAddress: shopAddress,
      );

      // Суммируем поступления
      double oooIncome = 0;
      double ipIncome = 0;

      for (final report in envelopeReports) {
        oooIncome += report.oooCash;
        ipIncome += report.ipCash;
      }

      // Суммируем операции (только активные, не отмененные)
      double oooWithdrawals = 0;
      double ipWithdrawals = 0;
      double oooDeposits = 0;
      double ipDeposits = 0;

      for (final withdrawal in withdrawals) {
        if (withdrawal.isActive) {
          if (withdrawal.category == 'deposit') {
            // Внесение — добавляем к балансу
            if (withdrawal.type == 'ooo') {
              oooDeposits += withdrawal.totalAmount;
            } else if (withdrawal.type == 'ip') {
              ipDeposits += withdrawal.totalAmount;
            }
          } else if (withdrawal.category == 'transfer') {
            // Перенос — вычитаем из источника, добавляем к получателю
            if (withdrawal.transferDirection == 'ooo_to_ip') {
              oooWithdrawals += withdrawal.totalAmount;
              ipDeposits += withdrawal.totalAmount;
            } else if (withdrawal.transferDirection == 'ip_to_ooo') {
              ipWithdrawals += withdrawal.totalAmount;
              oooDeposits += withdrawal.totalAmount;
            }
          } else {
            // Выемка — вычитаем из баланса
            if (withdrawal.type == 'ooo') {
              oooWithdrawals += withdrawal.totalAmount;
            } else if (withdrawal.type == 'ip') {
              ipWithdrawals += withdrawal.totalAmount;
            }
          }
        }
      }

      return ShopCashBalance(
        shopAddress: shopAddress,
        oooBalance: oooIncome + oooDeposits - oooWithdrawals,
        ipBalance: ipIncome + ipDeposits - ipWithdrawals,
        oooTotalIncome: oooIncome,
        ipTotalIncome: ipIncome,
        oooTotalWithdrawals: oooWithdrawals,
        ipTotalWithdrawals: ipWithdrawals,
      );
    } catch (e) {
      Logger.error('Ошибка загрузки баланса магазина', e);
      return null;
    }
  }

  /// Получить список всех уникальных адресов магазинов из отчетов
  static Future<List<String>> getShopAddressesWithData() async {
    try {
      final envelopeReports = await EnvelopeReportService.getReports();
      final addresses = <String>{};

      for (final report in envelopeReports) {
        addresses.add(report.shopAddress);
      }

      final list = addresses.toList()..sort();
      return list;
    } catch (e) {
      Logger.error('Ошибка загрузки адресов магазинов', e);
      return [];
    }
  }
}

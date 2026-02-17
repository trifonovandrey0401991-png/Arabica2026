import 'package:flutter/material.dart';
import '../../shops/services/shop_service.dart';
import 'withdrawal_employee_selection_page.dart';
import '../../../shared/widgets/shop_selection_scaffold.dart';

/// Страница выбора магазина для выемки из главной кассы
class WithdrawalShopSelectionPage extends StatelessWidget {
  final String currentUserName;

  const WithdrawalShopSelectionPage({
    super.key,
    required this.currentUserName,
  });

  @override
  Widget build(BuildContext context) {
    return ShopSelectionScaffold(
      title: 'Выберите магазин',
      loadShops: () => ShopService.getShopsForCurrentUser(),
      onShopTap: (context, shop) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WithdrawalEmployeeSelectionPage(
              shopAddress: shop.address,
              currentUserName: currentUserName,
            ),
          ),
        );
      },
    );
  }
}

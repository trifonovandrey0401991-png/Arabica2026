import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../../shops/services/shop_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../employees/services/employee_service.dart';
import 'shift_handover_role_selection_page.dart';
import '../../../shared/widgets/shop_selection_scaffold.dart';

/// Страница выбора магазина для сдачи смены
class ShiftHandoverShopSelectionPage extends StatefulWidget {
  final String employeeName;

  const ShiftHandoverShopSelectionPage({
    super.key,
    required this.employeeName,
  });

  @override
  State<ShiftHandoverShopSelectionPage> createState() =>
      _ShiftHandoverShopSelectionPageState();
}

class _ShiftHandoverShopSelectionPageState
    extends State<ShiftHandoverShopSelectionPage> {
  bool _isManager = false;

  Future<void> _loadManagerStatus() async {
    try {
      final employeeId = await EmployeesPage.getCurrentEmployeeId();
      if (employeeId != null) {
        final employees = await EmployeeService.getEmployees();
        final employee = employees.firstWhere(
          (e) => e.id == employeeId,
          orElse: () => throw StateError('Employee not found'),
        );
        _isManager = employee.isManager == true;
      }
    } catch (e) {
      Logger.warning('Failed to load manager status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShopSelectionScaffold(
      title: 'Выберите магазин',
      loadShops: () => ShopService.getShopsForCurrentUser(),
      onExtraLoad: _loadManagerStatus,
      onShopTap: (context, shop) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShiftHandoverRoleSelectionPage(
              employeeName: widget.employeeName,
              shopAddress: shop.address,
              isCurrentUserManager: _isManager,
            ),
          ),
        );
      },
    );
  }
}

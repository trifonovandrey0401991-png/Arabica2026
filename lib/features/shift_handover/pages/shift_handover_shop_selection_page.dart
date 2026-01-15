import 'package:flutter/material.dart';
import '../../../core/widgets/shop_icon.dart';
import '../../shops/models/shop_model.dart';
import '../../employees/pages/employees_page.dart';
import '../../employees/services/employee_service.dart';
import 'shift_handover_role_selection_page.dart';

/// Страница выбора магазина для сдачи смены
class ShiftHandoverShopSelectionPage extends StatefulWidget {
  final String employeeName;

  const ShiftHandoverShopSelectionPage({
    super.key,
    required this.employeeName,
  });

  @override
  State<ShiftHandoverShopSelectionPage> createState() => _ShiftHandoverShopSelectionPageState();
}

class _ShiftHandoverShopSelectionPageState extends State<ShiftHandoverShopSelectionPage> {
  bool _isManager = false;
  bool _isLoadingManager = true;

  @override
  void initState() {
    super.initState();
    _loadManagerStatus();
  }

  Future<void> _loadManagerStatus() async {
    try {
      final employeeId = await EmployeesPage.getCurrentEmployeeId();
      if (employeeId != null) {
        final employees = await EmployeeService.getEmployees();
        final employee = employees.firstWhere(
          (e) => e.id == employeeId,
          orElse: () => throw StateError('Employee not found'),
        );
        if (mounted) {
          setState(() {
            _isManager = employee.isManager == true;
            _isLoadingManager = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoadingManager = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingManager = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Выберите магазин'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: FutureBuilder<List<Shop>>(
          future: Shop.loadShopsFromGoogleSheets(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting || _isLoadingManager) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.white),
                    const SizedBox(height: 16),
                    const Text(
                      'Что-то пошло не так, попробуйте позже',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF004D40),
                      ),
                      child: const Text('Назад'),
                    ),
                  ],
                ),
              );
            }

            final shops = snapshot.data ?? [];
            if (shops.isEmpty) {
              return const Center(
                child: Text(
                  'Магазины не найдены',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: shops.length,
              itemBuilder: (context, index) {
                final shop = shops[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
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
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.5),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            const ShopIcon(size: 56),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                shop.address,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: Colors.white70,
                              size: 28,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

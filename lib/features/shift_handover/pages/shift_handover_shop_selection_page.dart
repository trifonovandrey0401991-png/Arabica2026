import 'package:flutter/material.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../employees/services/employee_service.dart';
import 'shift_handover_role_selection_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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

  // Единая палитра приложения
  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);
  static final Color _gold = Color(0xFFD4AF37);

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
      backgroundColor: _night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 4.h),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Выберите магазин',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 3.h),
                  child: Text(
                    'Сдача смены',
                    style: TextStyle(
                      color: _gold.withOpacity(0.7),
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Иконка пересменки
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: _gold.withOpacity(0.3)),
            ),
            child: Icon(
              Icons.swap_horiz_rounded,
              color: _gold,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return FutureBuilder<List<Shop>>(
      future: ShopService.getShopsForCurrentUser(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || _isLoadingManager) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: _gold.withOpacity(0.7),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Загрузка магазинов...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14.sp,
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(32.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.error_outline, size: 36, color: Colors.red.withOpacity(0.7)),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Что-то пошло не так',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Попробуйте позже',
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14.sp),
                  ),
                  SizedBox(height: 24),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 14.h),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                      ),
                      child: Text(
                        'Назад',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final shops = snapshot.data ?? [];
        if (shops.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.store_outlined, size: 36, color: Colors.white.withOpacity(0.3)),
                ),
                SizedBox(height: 16),
                Text(
                  'Магазины не найдены',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16.sp),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
          itemCount: shops.length,
          itemBuilder: (context, index) {
            final shop = shops[index];
            return _buildShopCard(shop, index);
          },
        );
      },
    );
  }

  Widget _buildShopCard(Shop shop, int index) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
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
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                // Номер магазина
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: _gold.withOpacity(0.3)),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: _gold,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    shop.address,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.85),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.3),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

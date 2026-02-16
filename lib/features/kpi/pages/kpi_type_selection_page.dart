import 'package:flutter/material.dart';
import 'kpi_shop_calendar_page.dart';
import 'kpi_employees_list_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница выбора типа KPI: Сотрудники / Магазины
class KPITypeSelectionPage extends StatelessWidget {
  const KPITypeSelectionPage({super.key});

  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);

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
              // Custom AppBar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    SizedBox(width: 16),
                    Text(
                      'KPI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0.w),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Выберите тип отчета',
                          style: TextStyle(
                            fontSize: 24.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 48),
                        SizedBox(
                          width: double.infinity,
                          height: 80,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => KPIEmployeesListPage(),
                                ),
                              );
                            },
                            icon: Icon(Icons.person, size: 32),
                            label: Text(
                              'Сотрудники',
                              style: TextStyle(fontSize: 20.sp),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _emerald,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 80,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => KPIShopCalendarPage(),
                                ),
                              );
                            },
                            icon: Icon(Icons.store, size: 32),
                            label: Text(
                              'Магазины',
                              style: TextStyle(fontSize: 20.sp),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _emerald,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

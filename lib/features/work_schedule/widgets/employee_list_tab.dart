import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../employees/pages/employees_page.dart' show Employee;
import '../models/work_schedule_model.dart';

/// Вкладка "По сотрудникам" на странице графика работы
class EmployeeListTab extends StatelessWidget {
  final List<Employee> employees;
  final WorkSchedule? schedule;
  final DateTime selectedMonth;
  final void Function(Employee employee) onEmployeeTap;

  const EmployeeListTab({
    super.key,
    required this.employees,
    required this.schedule,
    required this.selectedMonth,
    required this.onEmployeeTap,
  });

  static String getMonthName(int month) {
    const months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (employees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24.w),
              decoration: BoxDecoration(
                color: AppColors.emerald.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.people_outline, size: 64, color: Colors.white.withOpacity(0.4)),
            ),
            SizedBox(height: 24),
            Text(
              'Нет сотрудников',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Добавьте сотрудников для управления графиком',
              style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }

    // Подсчёт статистики смен для каждого сотрудника
    final Map<String, int> employeeShiftCount = {};
    if (schedule != null) {
      for (var entry in schedule!.entries) {
        employeeShiftCount[entry.employeeId] =
            (employeeShiftCount[entry.employeeId] ?? 0) + 1;
      }
    }

    return Column(
      children: [
        // Заголовок с информацией
        Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.emerald, AppColors.emeraldDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(Icons.people, color: AppColors.gold, size: 28),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Сотрудники',
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.95),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${employees.length} человек • ${getMonthName(selectedMonth.month)} ${selectedMonth.year}',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Список сотрудников
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(16.w),
            itemCount: employees.length,
            itemBuilder: (context, index) {
              final employee = employees[index];
              final shiftCount = employeeShiftCount[employee.id] ?? 0;

              return Container(
                margin: EdgeInsets.only(bottom: 12.h),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16.r),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16.r),
                    onTap: () => onEmployeeTap(employee),
                    child: Padding(
                      padding: EdgeInsets.all(16.w),
                      child: Row(
                        children: [
                          // Аватар с градиентом
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.emerald, AppColors.emeraldLight],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16.r),
                            ),
                            child: Center(
                              child: Text(
                                employee.name.isNotEmpty
                                    ? employee.name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 16),
                          // Информация о сотруднике
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  employee.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16.sp,
                                    color: Colors.white.withOpacity(0.95),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 6),
                                Row(
                                  children: [
                                    // Количество смен
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10.w,
                                        vertical: 4.h,
                                      ),
                                      decoration: BoxDecoration(
                                        color: shiftCount > 0
                                            ? AppColors.emerald.withOpacity(0.3)
                                            : Colors.white.withOpacity(0.04),
                                        borderRadius: BorderRadius.circular(8.r),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.calendar_today,
                                            size: 14,
                                            color: shiftCount > 0
                                                ? AppColors.gold
                                                : Colors.white.withOpacity(0.3),
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            '$shiftCount смен',
                                            style: TextStyle(
                                              fontSize: 12.sp,
                                              fontWeight: FontWeight.w500,
                                              color: shiftCount > 0
                                                  ? Colors.white.withOpacity(0.8)
                                                  : Colors.white.withOpacity(0.3),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (employee.phone != null) ...[
                                      SizedBox(width: 8),
                                      Icon(
                                        Icons.phone_outlined,
                                        size: 14,
                                        color: Colors.white.withOpacity(0.4),
                                      ),
                                      SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          employee.phone!,
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            color: Colors.white.withOpacity(0.4),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Стрелка
                          Container(
                            padding: EdgeInsets.all(8.w),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(10.r),
                            ),
                            child: Icon(
                              Icons.arrow_forward_ios,
                              size: 14,
                              color: Colors.white.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

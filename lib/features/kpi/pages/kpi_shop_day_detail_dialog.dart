import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/kpi_models.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Диалог с сотрудниками и их показателями за день
class KPIShopDayDetailDialog extends StatelessWidget {
  final KPIShopDayData dayData;

  const KPIShopDayDetailDialog({
    super.key,
    required this.dayData,
  });

  @override
  Widget build(BuildContext context) {
    final tableRows = dayData.employeesData
        .map((data) => KPIDayTableRow.fromKPIDayData(data))
        .toList()
      ..sort((a, b) => a.employeeName.compareTo(b.employeeName));

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Container(
        constraints: BoxConstraints(maxWidth: 600, maxHeight: 600),
        padding: EdgeInsets.all(16.0.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${dayData.date.day}.${dayData.date.month.toString().padLeft(2, '0')}.${dayData.date.year}',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryGreen,
              ),
            ),
            SizedBox(height: 8),
            Text(
              dayData.shopAddress,
              style: TextStyle(
                fontSize: 16.sp,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            if (tableRows.isEmpty)
              Padding(
                padding: EdgeInsets.all(32.0.w),
                child: Text(
                  'Нет данных за этот день',
                  style: TextStyle(fontSize: 16.sp, color: Colors.grey),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 12,
                      headingRowHeight: 80,
                      dataRowMinHeight: 36,
                      dataRowMaxHeight: 36,
                      headingRowColor: MaterialStateColor.resolveWith(
                        (states) => AppColors.primaryGreen.withOpacity(0.1),
                      ),
                      columns: [
                        DataColumn(
                          label: Text(
                            'ФИО',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.sp,
                            ),
                          ),
                        ),
                        DataColumn(
                          label: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              'Приход',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11.sp,
                              ),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              'Смена',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11.sp,
                              ),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              'Пересчет',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11.sp,
                              ),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              'РКО',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11.sp,
                              ),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              'Конверт',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11.sp,
                              ),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              'Сдача',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11.sp,
                              ),
                            ),
                          ),
                        ),
                      ],
                      rows: tableRows.map((row) {
                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                row.employeeName,
                                style: TextStyle(fontSize: 12.sp),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DataCell(
                              Text(
                                row.attendanceTime ?? '-',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: row.attendanceTime != null 
                                      ? Colors.green 
                                      : Colors.grey,
                                  fontWeight: row.attendanceTime != null 
                                      ? FontWeight.bold 
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            DataCell(
                              Icon(
                                row.hasShift ? Icons.check : Icons.close,
                                color: row.hasShift ? Colors.green : Colors.red,
                                size: 18,
                              ),
                            ),
                            DataCell(
                              Icon(
                                row.hasRecount ? Icons.check : Icons.close,
                                color: row.hasRecount ? Colors.green : Colors.red,
                                size: 18,
                              ),
                            ),
                            DataCell(
                              Icon(
                                row.hasRKO ? Icons.check : Icons.close,
                                color: row.hasRKO ? Colors.green : Colors.red,
                                size: 18,
                              ),
                            ),
                            DataCell(
                              Icon(
                                row.hasEnvelope ? Icons.check : Icons.close,
                                color: row.hasEnvelope ? Colors.green : Colors.red,
                                size: 18,
                              ),
                            ),
                            DataCell(
                              Icon(
                                row.hasShiftHandover ? Icons.check : Icons.close,
                                color: row.hasShiftHandover ? Colors.green : Colors.red,
                                size: 18,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Закрыть'),
            ),
          ],
        ),
      ),
    );
  }
}







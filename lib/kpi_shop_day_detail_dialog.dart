import 'package:flutter/material.dart';
import 'kpi_models.dart';

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
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${dayData.date.day}.${dayData.date.month.toString().padLeft(2, '0')}.${dayData.date.year}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              dayData.shopAddress,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (tableRows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Text(
                  'Нет данных за этот день',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 12,
                      headingRowHeight: 40,
                      dataRowMinHeight: 36,
                      dataRowMaxHeight: 36,
                      headingRowColor: MaterialStateColor.resolveWith(
                        (states) => const Color(0xFF004D40).withOpacity(0.1),
                      ),
                      columns: const [
                        DataColumn(
                          label: Text(
                            'ФИО',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Приход',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Смена',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Пересчет',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'РКО',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
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
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DataCell(
                              Text(
                                row.attendanceTime ?? '-',
                                style: TextStyle(
                                  fontSize: 12,
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
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      ),
    );
  }
}







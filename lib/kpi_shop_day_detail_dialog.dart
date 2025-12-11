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
                      columnSpacing: 20,
                      headingRowColor: MaterialStateColor.resolveWith(
                        (states) => const Color(0xFF004D40).withOpacity(0.1),
                      ),
                      columns: const [
                        DataColumn(
                          label: Text(
                            'ФИО',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Приход',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Пересменка',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Пересчет',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'РКО',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                      rows: tableRows.map((row) {
                        return DataRow(
                          cells: [
                            DataCell(Text(row.employeeName)),
                            DataCell(Text(row.attendanceTime ?? '-')),
                            DataCell(
                              Icon(
                                row.hasShift ? Icons.check : Icons.close,
                                color: row.hasShift ? Colors.green : Colors.red,
                                size: 20,
                              ),
                            ),
                            DataCell(
                              Icon(
                                row.hasRecount ? Icons.check : Icons.close,
                                color: row.hasRecount ? Colors.green : Colors.red,
                                size: 20,
                              ),
                            ),
                            DataCell(
                              Icon(
                                row.hasRKO ? Icons.check : Icons.close,
                                color: row.hasRKO ? Colors.green : Colors.red,
                                size: 20,
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


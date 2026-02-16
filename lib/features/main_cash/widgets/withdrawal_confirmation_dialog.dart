import 'package:flutter/material.dart';
import '../models/withdrawal_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Диалог подтверждения выемки
class WithdrawalConfirmationDialog extends StatelessWidget {
  final Withdrawal withdrawal;

  const WithdrawalConfirmationDialog({
    super.key,
    required this.withdrawal,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Подтверждение выемки',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Магазин и сотрудник
            _buildInfoRow('Магазин:', withdrawal.shopAddress),
            _buildInfoRow('Сотрудник:', withdrawal.employeeName),
            _buildInfoRow('Тип:', withdrawal.typeDisplayName),
            SizedBox(height: 16),
            Divider(),
            SizedBox(height: 8),

            // Заголовок расходов
            Text(
              'Расходы:',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),

            // Список расходов
            ...withdrawal.expenses.asMap().entries.map((entry) {
              final index = entry.key;
              final expense = entry.value;
              return Card(
                margin: EdgeInsets.only(bottom: 8.h),
                color: Colors.grey[50],
                child: Padding(
                  padding: EdgeInsets.all(12.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}. ${expense.displayName}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.sp,
                        ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Сумма:',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          Text(
                            '${expense.amount.toStringAsFixed(0)} руб',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16.sp,
                            ),
                          ),
                        ],
                      ),
                      if (expense.comment.isNotEmpty) ...[
                        SizedBox(height: 4),
                        Text(
                          'Комментарий: ${expense.comment}',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12.sp,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),

            SizedBox(height: 12),
            Divider(),
            SizedBox(height: 12),

            // Общая сумма
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.blue[300]!, width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Итого:',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${withdrawal.totalAmount.toStringAsFixed(0)} руб',
                    style: TextStyle(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF004D40),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Предупреждение
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.red[300]!, width: 2),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.red, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Проверьте все.\nДействие будет невозвратно.',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[700],
            foregroundColor: Colors.white,
          ),
          child: Text('Подтвердить'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

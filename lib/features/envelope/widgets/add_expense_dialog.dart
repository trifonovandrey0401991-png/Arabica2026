import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/envelope_report_model.dart';
import '../../suppliers/models/supplier_model.dart';

class AddExpenseDialog extends StatefulWidget {
  final List<Supplier> suppliers;

  const AddExpenseDialog({
    super.key,
    required this.suppliers,
  });

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  Supplier? _selectedSupplier;
  final _amountController = TextEditingController();
  final _commentController = TextEditingController();

  static const _primaryColor = Color(0xFF004D40);

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Выберите поставщика'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите корректную сумму'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final expense = ExpenseItem(
      supplierId: _selectedSupplier!.id,
      supplierName: _selectedSupplier!.name,
      amount: amount,
      comment: _commentController.text.isNotEmpty ? _commentController.text : null,
    );

    Navigator.of(context).pop(expense);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить расход'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Поставщик:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (widget.suppliers.isEmpty)
              const Text(
                'Нет доступных поставщиков',
                style: TextStyle(color: Colors.grey),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Column(
                    children: widget.suppliers.map((supplier) {
                      final isSelected = _selectedSupplier?.id == supplier.id;
                      return InkWell(
                        onTap: () => setState(() => _selectedSupplier = supplier),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isSelected ? _primaryColor : Colors.grey[300]!,
                              width: isSelected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: isSelected ? _primaryColor.withOpacity(0.1) : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color: isSelected ? _primaryColor : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      supplier.name,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    if (supplier.legalType != null)
                                      Text(
                                        supplier.legalType!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Сумма:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: 'Введите сумму',
                suffixText: '₽',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Комментарий (необязательно):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Например: оплата за товар',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}

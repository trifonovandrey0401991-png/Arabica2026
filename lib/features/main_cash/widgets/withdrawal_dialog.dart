import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/withdrawal_model.dart';
import '../services/withdrawal_service.dart';

/// Диалог создания выемки
class WithdrawalDialog extends StatefulWidget {
  final List<String> shopAddresses;

  const WithdrawalDialog({
    super.key,
    required this.shopAddresses,
  });

  @override
  State<WithdrawalDialog> createState() => _WithdrawalDialogState();
}

class _WithdrawalDialogState extends State<WithdrawalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _commentController = TextEditingController();

  String? _selectedShop;
  String _selectedType = 'ooo';
  bool _isSaving = false;
  String? _adminName;

  @override
  void initState() {
    super.initState();
    _loadAdminName();
    if (widget.shopAddresses.isNotEmpty) {
      _selectedShop = widget.shopAddresses.first;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _adminName = prefs.getString('userName') ??
                   prefs.getString('user_name') ??
                   'Администратор';
    });
  }

  Future<void> _saveWithdrawal() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedShop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите магазин')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final withdrawal = Withdrawal(
        shopAddress: _selectedShop!,
        type: _selectedType,
        amount: double.parse(_amountController.text.replaceAll(' ', '')),
        comment: _commentController.text.trim(),
        adminName: _adminName ?? 'Администратор',
      );

      final result = await WithdrawalService.createWithdrawal(withdrawal);

      if (result != null) {
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Выемка успешно создана'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка создания выемки'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Ошибка сохранения выемки: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новая выемка'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Выбор магазина
              DropdownButtonFormField<String>(
                value: _selectedShop,
                decoration: const InputDecoration(
                  labelText: 'Магазин',
                  border: OutlineInputBorder(),
                ),
                items: widget.shopAddresses.map((address) {
                  return DropdownMenuItem(
                    value: address,
                    child: SizedBox(
                      width: 200,
                      child: Text(
                        address,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedShop = value);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Выберите магазин';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Выбор типа (ООО/ИП)
              const Text(
                'Тип:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('ООО'),
                      value: 'ooo',
                      groupValue: _selectedType,
                      onChanged: (value) {
                        setState(() => _selectedType = value!);
                      },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('ИП'),
                      value: 'ip',
                      groupValue: _selectedType,
                      onChanged: (value) {
                        setState(() => _selectedType = value!);
                      },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Сумма
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Сумма',
                  border: OutlineInputBorder(),
                  suffixText: '\u20bd',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введите сумму';
                  }
                  final amount = double.tryParse(value);
                  if (amount == null || amount <= 0) {
                    return 'Введите корректную сумму';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Комментарий
              TextFormField(
                controller: _commentController,
                decoration: const InputDecoration(
                  labelText: 'Комментарий (необязательно)',
                  border: OutlineInputBorder(),
                  hintText: 'Например: Инкассация',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveWithdrawal,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF004D40),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}

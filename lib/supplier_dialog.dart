import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'supplier_model.dart';

/// Диалог для добавления/редактирования поставщика
class SupplierDialog extends StatefulWidget {
  final Supplier? supplier; // Если null - создание, иначе - редактирование

  const SupplierDialog({
    super.key,
    this.supplier,
  });

  @override
  State<SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<SupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _innController = TextEditingController();
  final _phoneController = TextEditingController();
  
  String? _legalType; // "ООО" или "ИП"
  List<String> _selectedDeliveryDays = [];
  String? _paymentType; // "Нал" или "БезНал"

  final List<String> _weekDays = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.supplier != null) {
      // Редактирование существующего поставщика
      _nameController.text = widget.supplier!.name;
      _innController.text = widget.supplier!.inn ?? '';
      _phoneController.text = widget.supplier!.phone ?? '';
      _legalType = widget.supplier!.legalType;
      _selectedDeliveryDays = List<String>.from(widget.supplier!.deliveryDays);
      _paymentType = widget.supplier!.paymentType;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _innController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _toggleDeliveryDay(String day) {
    setState(() {
      if (_selectedDeliveryDays.contains(day)) {
        _selectedDeliveryDays.remove(day);
      } else {
        _selectedDeliveryDays.add(day);
      }
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_legalType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Выберите тип организации'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_paymentType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Выберите тип оплаты'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final supplier = Supplier(
      id: widget.supplier?.id ?? '',
      name: _nameController.text.trim(),
      inn: _innController.text.trim().isEmpty ? null : _innController.text.trim(),
      legalType: _legalType!,
      deliveryDays: _selectedDeliveryDays,
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      paymentType: _paymentType!,
      createdAt: widget.supplier?.createdAt,
      updatedAt: null,
    );

    Navigator.of(context).pop(supplier);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 800),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.supplier == null ? 'Добавить поставщика' : 'Редактировать поставщика',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF004D40),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Наименование поставщика
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Наименование поставщика *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Обязательное поле';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // ИНН поставщика
                  TextFormField(
                    controller: _innController,
                    decoration: const InputDecoration(
                      labelText: 'ИНН поставщика',
                      border: OutlineInputBorder(),
                      helperText: 'Необязательное поле',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        if (!Supplier.isValidInn(value)) {
                          return 'ИНН должен содержать 10 или 12 цифр';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Тип организации
                  const Text(
                    'К кому относится *',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('ООО'),
                          value: 'ООО',
                          groupValue: _legalType,
                          onChanged: (value) {
                            setState(() {
                              _legalType = value;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('ИП'),
                          value: 'ИП',
                          groupValue: _legalType,
                          onChanged: (value) {
                            setState(() {
                              _legalType = value;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Дата привоза (дни недели)
                  const Text(
                    'Дата привоза',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _weekDays.map((day) {
                      final isSelected = _selectedDeliveryDays.contains(day);
                      return FilterChip(
                        label: Text(day),
                        selected: isSelected,
                        onSelected: (_) => _toggleDeliveryDay(day),
                        selectedColor: const Color(0xFF004D40).withOpacity(0.3),
                        checkmarkColor: const Color(0xFF004D40),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  
                  // Номер телефона
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Номер телефона',
                      border: OutlineInputBorder(),
                      helperText: 'Необязательное поле',
                    ),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d\+\-\(\)\s]')),
                    ],
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        if (!Supplier.isValidPhone(value)) {
                          return 'Некорректный номер телефона';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Работа с оплатой
                  const Text(
                    'Работа с оплатой *',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Нал'),
                          value: 'Нал',
                          groupValue: _paymentType,
                          onChanged: (value) {
                            setState(() {
                              _paymentType = value;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('БезНал'),
                          value: 'БезНал',
                          groupValue: _paymentType,
                          onChanged: (value) {
                            setState(() {
                              _paymentType = value;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Кнопки
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Отмена'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF004D40),
                        ),
                        child: const Text('Сохранить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


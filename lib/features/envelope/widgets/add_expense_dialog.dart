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
  final _amountFocusNode = FocusNode();
  final _commentFocusNode = FocusNode();

  static const _primaryColor = Color(0xFF004D40);
  static const _primaryColorLight = Color(0xFF00695C);
  static const _backgroundColor = Color(0xFFF5F7FA);

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    _amountFocusNode.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedSupplier == null) {
      _showError('Выберите поставщика');
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      _showError('Введите корректную сумму');
      _amountFocusNode.requestFocus();
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          title: const Text(
            'Добавить расход',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.close_rounded, size: 22),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Column(
          children: [
            // Основной контент
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Секция выбора поставщика
                      _buildSectionHeader(
                        icon: Icons.business_rounded,
                        title: 'Поставщик',
                        subtitle: 'Выберите из списка',
                      ),
                      const SizedBox(height: 16),

                      if (widget.suppliers.isEmpty)
                        _buildEmptySuppliers()
                      else
                        _buildSuppliersList(),

                      const SizedBox(height: 28),

                      // Секция суммы
                      _buildSectionHeader(
                        icon: Icons.payments_rounded,
                        title: 'Сумма расхода',
                        subtitle: 'Укажите сумму в рублях',
                      ),
                      const SizedBox(height: 16),
                      _buildAmountInput(),

                      const SizedBox(height: 28),

                      // Секция комментария
                      _buildSectionHeader(
                        icon: Icons.comment_rounded,
                        title: 'Комментарий',
                        subtitle: 'Необязательно',
                      ),
                      const SizedBox(height: 16),
                      _buildCommentInput(),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),

            // Нижняя кнопка
            _buildBottomButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryColor.withOpacity(0.15), _primaryColorLight.withOpacity(0.1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _primaryColor, size: 22),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D3748),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptySuppliers() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.inventory_2_outlined, size: 32, color: Colors.orange.shade400),
          ),
          const SizedBox(height: 16),
          Text(
            'Нет поставщиков',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Добавьте поставщиков в разделе\n"Поставщики"',
            style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.4),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSuppliersList() {
    return Column(
      children: widget.suppliers.map((supplier) {
        final isSelected = _selectedSupplier?.id == supplier.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _selectedSupplier = supplier),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? _primaryColor : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected
                          ? _primaryColor.withOpacity(0.15)
                          : Colors.black.withOpacity(0.04),
                      blurRadius: isSelected ? 12 : 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Анимированный чекбокс
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [_primaryColor, _primaryColorLight],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isSelected ? null : Colors.grey[200],
                        border: isSelected
                            ? null
                            : Border.all(color: Colors.grey[300]!, width: 2),
                      ),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: isSelected ? 1.0 : 0.0,
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Информация о поставщике
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            supplier.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: isSelected ? _primaryColor : const Color(0xFF2D3748),
                            ),
                          ),
                          if (supplier.legalType != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _primaryColor.withOpacity(0.1)
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                supplier.legalType!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isSelected ? _primaryColor : Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                          if (supplier.phone != null && supplier.phone!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.phone_outlined,
                                  size: 14,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  supplier.phone!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Стрелка или галочка
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: isSelected
                          ? Container(
                              key: const ValueKey('check'),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.check_circle_rounded,
                                color: _primaryColor,
                                size: 22,
                              ),
                            )
                          : Icon(
                              key: const ValueKey('arrow'),
                              Icons.chevron_right_rounded,
                              color: Colors.grey[300],
                              size: 24,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAmountInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _amountController,
        focusNode: _amountFocusNode,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: _primaryColor,
          letterSpacing: 1,
        ),
        decoration: InputDecoration(
          hintText: '0',
          hintStyle: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.grey[300],
          ),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'RUB',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _primaryColor, width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildCommentInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _commentController,
        focusNode: _commentFocusNode,
        maxLines: 3,
        style: const TextStyle(fontSize: 16, height: 1.5),
        decoration: InputDecoration(
          hintText: 'Например: оплата за товар, закупка продуктов...',
          hintStyle: TextStyle(
            color: Colors.grey[400],
            fontSize: 15,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 12, bottom: 40),
            child: Icon(Icons.edit_note_rounded, color: Colors.grey[400], size: 24),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _primaryColor, width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.all(20),
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    final isValid = _selectedSupplier != null && _amountController.text.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _submit,
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: isValid
                      ? const LinearGradient(
                          colors: [_primaryColor, _primaryColorLight],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : null,
                  color: isValid ? null : Colors.grey[300],
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isValid
                      ? [
                          BoxShadow(
                            color: _primaryColor.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      color: isValid ? Colors.white : Colors.grey[500],
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Добавить расход',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: isValid ? Colors.white : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

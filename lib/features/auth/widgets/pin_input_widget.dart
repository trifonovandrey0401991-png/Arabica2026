import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Виджет для ввода PIN-кода
///
/// Особенности:
/// - 4-6 цифр
/// - Скрытый ввод (точки вместо цифр)
/// - Анимация при ошибке
/// - Цифровая клавиатура
class PinInputWidget extends StatefulWidget {
  /// Длина PIN-кода (от 4 до 6)
  final int pinLength;

  /// Вызывается когда PIN полностью введён
  final Function(String pin) onCompleted;

  /// Вызывается при изменении PIN
  final Function(String pin)? onChanged;

  /// Показывать ли ошибку
  final bool showError;

  /// Сообщение об ошибке
  final String? errorMessage;

  /// Заголовок над полем ввода
  final String? title;

  /// Описание под заголовком
  final String? subtitle;

  /// Очистить поле
  final bool clear;

  const PinInputWidget({
    super.key,
    this.pinLength = 4,
    required this.onCompleted,
    this.onChanged,
    this.showError = false,
    this.errorMessage,
    this.title,
    this.subtitle,
    this.clear = false,
  });

  @override
  State<PinInputWidget> createState() => _PinInputWidgetState();
}

class _PinInputWidgetState extends State<PinInputWidget>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void didUpdateWidget(PinInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clear && !oldWidget.clear) {
      _clearPin();
    }
    if (widget.showError && !oldWidget.showError) {
      _shake();
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _shake() {
    _shakeController.forward().then((_) {
      _shakeController.reverse();
    });
  }

  void _clearPin() {
    setState(() {
      _pin = '';
    });
  }

  void _addDigit(String digit) {
    if (_pin.length >= widget.pinLength) return;

    setState(() {
      _pin += digit;
    });

    widget.onChanged?.call(_pin);

    // Вибрация при нажатии
    HapticFeedback.lightImpact();

    if (_pin.length == widget.pinLength) {
      widget.onCompleted(_pin);
    }
  }

  void _removeDigit() {
    if (_pin.isEmpty) return;

    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
    });

    widget.onChanged?.call(_pin);
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Заголовок
        if (widget.title != null) ...[
          Text(
            widget.title!,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],

        // Описание
        if (widget.subtitle != null) ...[
          Text(
            widget.subtitle!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
        ],

        // Индикаторы PIN
        AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_shakeAnimation.value, 0),
              child: child,
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.pinLength,
              (index) => _buildPinDot(index < _pin.length),
            ),
          ),
        ),

        // Ошибка
        if (widget.showError && widget.errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(
            widget.errorMessage!,
            style: const TextStyle(
              color: Colors.red,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],

        const SizedBox(height: 48),

        // Цифровая клавиатура
        _buildKeypad(),
      ],
    );
  }

  Widget _buildPinDot(bool filled) {
    return Container(
      width: 20,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled
            ? (widget.showError ? Colors.red : Theme.of(context).primaryColor)
            : Colors.transparent,
        border: Border.all(
          color: widget.showError
              ? Colors.red
              : Theme.of(context).primaryColor,
          width: 2,
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        // 1, 2, 3
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKeypadButton('1'),
            _buildKeypadButton('2'),
            _buildKeypadButton('3'),
          ],
        ),
        // 4, 5, 6
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKeypadButton('4'),
            _buildKeypadButton('5'),
            _buildKeypadButton('6'),
          ],
        ),
        // 7, 8, 9
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKeypadButton('7'),
            _buildKeypadButton('8'),
            _buildKeypadButton('9'),
          ],
        ),
        // Пустая, 0, Удалить
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildEmptyButton(),
            _buildKeypadButton('0'),
            _buildBackspaceButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildKeypadButton(String digit) {
    return Container(
      width: 80,
      height: 80,
      margin: const EdgeInsets.all(8),
      child: Material(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(40),
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: () => _addDigit(digit),
          child: Center(
            child: Text(
              digit,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return Container(
      width: 80,
      height: 80,
      margin: const EdgeInsets.all(8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(40),
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: _removeDigit,
          child: const Center(
            child: Icon(
              Icons.backspace_outlined,
              size: 28,
              color: Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyButton() {
    return Container(
      width: 80,
      height: 80,
      margin: const EdgeInsets.all(8),
    );
  }
}

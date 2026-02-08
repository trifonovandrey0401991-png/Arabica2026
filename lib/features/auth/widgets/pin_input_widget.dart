import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Виджет для ввода PIN-кода в стиле Arabica
///
/// Особенности:
/// - 4-6 цифр
/// - Скрытый ввод (точки вместо цифр)
/// - Анимация при ошибке
/// - Цифровая клавиатура
/// - Поддержка светлой и тёмной темы
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

  /// Использовать светлую тему (белый текст на тёмном фоне)
  final bool lightTheme;

  /// Цвет акцента (для точек и кнопок)
  final Color? accentColor;

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
    this.lightTheme = false,
    this.accentColor,
  });

  @override
  State<PinInputWidget> createState() => _PinInputWidgetState();
}

class _PinInputWidgetState extends State<PinInputWidget>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // Брендовые цвета Arabica
  static const Color _primaryColor = Color(0xFF1A4D4D);
  static const Color _accentGold = Color(0xFFD4AF37);

  Color get _activeColor => widget.accentColor ?? (widget.lightTheme ? _accentGold : _primaryColor);
  Color get _textColor => widget.lightTheme ? Colors.white : Colors.black87;
  Color get _subtitleColor => widget.lightTheme ? Colors.white70 : Colors.grey[600]!;

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
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],

        // Описание
        if (widget.subtitle != null) ...[
          Text(
            widget.subtitle!,
            style: TextStyle(
              fontSize: 14,
              color: _subtitleColor,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.errorMessage!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],

        const SizedBox(height: 40),

        // Цифровая клавиатура
        _buildKeypad(),
      ],
    );
  }

  Widget _buildPinDot(bool filled) {
    final dotColor = widget.showError ? Colors.redAccent : _activeColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: filled ? 18 : 16,
      height: filled ? 18 : 16,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? dotColor : Colors.transparent,
        border: Border.all(
          color: dotColor,
          width: 2,
        ),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: dotColor.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
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
      width: 72,
      height: 72,
      margin: const EdgeInsets.all(6),
      child: Material(
        color: widget.lightTheme
            ? Colors.white.withOpacity(0.15)
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(36),
        child: InkWell(
          borderRadius: BorderRadius.circular(36),
          splashColor: _activeColor.withOpacity(0.3),
          highlightColor: _activeColor.withOpacity(0.1),
          onTap: () => _addDigit(digit),
          child: Center(
            child: Text(
              digit,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w500,
                color: _textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return Container(
      width: 72,
      height: 72,
      margin: const EdgeInsets.all(6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(36),
        child: InkWell(
          borderRadius: BorderRadius.circular(36),
          splashColor: _activeColor.withOpacity(0.3),
          onTap: _removeDigit,
          child: Center(
            child: Icon(
              Icons.backspace_outlined,
              size: 26,
              color: widget.lightTheme ? Colors.white70 : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyButton() {
    return Container(
      width: 72,
      height: 72,
      margin: const EdgeInsets.all(6),
    );
  }
}

import 'package:flutter/material.dart';

/// Виджет иконки магазина Арабика
/// Использует картинку shop_icon.jpg вместо стандартных иконок
class ShopIcon extends StatelessWidget {
  final double size;
  final Color? backgroundColor;
  final BoxFit fit;

  const ShopIcon({
    super.key,
    this.size = 40,
    this.backgroundColor,
    this.fit = BoxFit.cover,
  });

  /// Путь к ассету иконки магазина
  static const String assetPath = 'assets/images/shop_icon.jpg';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.transparent,
          borderRadius: BorderRadius.circular(size / 4),
        ),
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            // Fallback на стандартную иконку при ошибке
            return Icon(
              Icons.store,
              size: size * 0.7,
              color: const Color(0xFF004D40),
            );
          },
        ),
      ),
    );
  }

  /// Создать CircleAvatar с иконкой магазина
  static Widget circleAvatar({
    double radius = 20,
    Color? backgroundColor,
  }) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? Colors.grey[200],
      backgroundImage: const AssetImage(assetPath),
      onBackgroundImageError: (exception, stackTrace) {},
      child: null,
    );
  }

  /// Виджет для использования в leading ListTile
  static Widget leading({double size = 40}) {
    return ShopIcon(size: size);
  }
}

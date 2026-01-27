import 'package:flutter/material.dart';

/// Кнопка сохранения для страниц настроек
///
/// Переиспользуемая кнопка с градиентом и индикатором загрузки.
/// Используется во всех settings pages.
class SettingsSaveButton extends StatelessWidget {
  final bool isSaving;
  final VoidCallback? onPressed;
  final List<Color> gradientColors;
  final String text;
  final IconData icon;

  const SettingsSaveButton({
    super.key,
    required this.isSaving,
    required this.onPressed,
    this.gradientColors = const [Color(0xFFf46b45), Color(0xFFeea849)],
    this.text = 'Сохранить настройки',
    this.icon = Icons.save_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isSaving ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isSaving
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    text,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Заголовок секции для страниц настроек
///
/// Полоска с градиентом и текстом заголовка.
class SettingsSectionTitle extends StatelessWidget {
  final String title;
  final List<Color> gradientColors;

  const SettingsSectionTitle({
    super.key,
    required this.title,
    this.gradientColors = const [Color(0xFFf46b45), Color(0xFFeea849)],
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: gradientColors,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3436),
          ),
        ),
      ],
    );
  }
}

/// Информационная карточка для заголовка страницы настроек
///
/// Отображает иконку, заголовок и подзаголовок на градиентном фоне.
class SettingsHeaderCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;

  const SettingsHeaderCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.gradientColors = const [Color(0xFFf46b45), Color(0xFFeea849)],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Информационный блок с иконкой и текстом
///
/// Используется для отображения предупреждений и информации.
class SettingsInfoBox extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const SettingsInfoBox({
    super.key,
    required this.text,
    this.color = Colors.amber,
    this.icon = Icons.info_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: color.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension on Color {
  Color get shade900 {
    // Создаём более тёмный оттенок цвета
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness * 0.3).clamp(0.0, 1.0)).toColor();
  }
}

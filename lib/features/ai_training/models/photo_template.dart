/// Модель шаблона для фотографирования
/// Используется для обучения ИИ — 10 обязательных шаблонов для "Крупного плана"

/// Тип overlay для отображения на камере
enum OverlayType {
  center,    // 1 пачка по центру
  angled,    // 1 пачка под углом 45°
  row,       // Несколько пачек в ряд горизонтально
  stack,     // Пачки стопкой вертикально
  hand,      // Пачка в руке
  shelf,     // Пачка на полке
  side,      // Боковая грань пачки
  large,     // Крупный план (70% кадра)
  small,     // Средний план (30% кадра)
}

class PhotoTemplate {
  final int id;
  final String name;
  final String description;
  final String hint;

  // Параметры для overlay
  final int packCount;
  final double packScale;      // 0.0-1.0 от ширины кадра
  final double packAngle;      // Угол поворота в градусах
  final OverlayType overlayType;

  const PhotoTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.hint,
    required this.packCount,
    required this.packScale,
    required this.packAngle,
    required this.overlayType,
  });

  /// 10 обязательных шаблонов для "Крупного плана"
  /// ВАЖНО: Все пачки должны быть ОДИНАКОВЫЕ (один и тот же товар)!
  static List<PhotoTemplate> get recountTemplates => const [
    PhotoTemplate(
      id: 1,
      name: 'Фронтально сверху',
      description: '1 пачка лежит на столе, фото сверху',
      hint: 'Положите пачку на стол лицевой стороной вверх. Снимайте СВЕРХУ, держа телефон параллельно столу',
      packCount: 1,
      packScale: 0.4,
      packAngle: 0,
      overlayType: OverlayType.center,
    ),
    PhotoTemplate(
      id: 2,
      name: 'Под углом 45°',
      description: '1 пачка повёрнута, фото сверху',
      hint: 'Положите пачку на стол и поверните её на 45°. Снимайте СВЕРХУ',
      packCount: 1,
      packScale: 0.4,
      packAngle: 45,
      overlayType: OverlayType.angled,
    ),
    PhotoTemplate(
      id: 3,
      name: 'Две пачки рядом',
      description: '2 ОДИНАКОВЫЕ пачки рядом, фото сверху',
      hint: 'Положите 2 ОДИНАКОВЫЕ пачки рядом на стол. Снимайте СВЕРХУ. Пачки должны быть одного товара!',
      packCount: 2,
      packScale: 0.35,
      packAngle: 0,
      overlayType: OverlayType.row,
    ),
    PhotoTemplate(
      id: 4,
      name: 'Три пачки в ряд',
      description: '3 ОДИНАКОВЫЕ пачки в ряд, фото сверху',
      hint: 'Положите 3 ОДИНАКОВЫЕ пачки в ряд на стол. Снимайте СВЕРХУ. Все пачки одного товара!',
      packCount: 3,
      packScale: 0.28,
      packAngle: 0,
      overlayType: OverlayType.row,
    ),
    PhotoTemplate(
      id: 5,
      name: 'Очень крупно',
      description: '1 пачка занимает 70% кадра',
      hint: 'Приблизьте телефон к пачке — она должна занять почти весь экран. Фото СВЕРХУ или СПЕРЕДИ',
      packCount: 1,
      packScale: 0.7,
      packAngle: 0,
      overlayType: OverlayType.large,
    ),
    PhotoTemplate(
      id: 6,
      name: 'Издалека',
      description: '1 пачка мелко (30% кадра)',
      hint: 'Отодвиньте телефон — пачка должна быть небольшой в кадре. Фото СВЕРХУ',
      packCount: 1,
      packScale: 0.3,
      packAngle: 0,
      overlayType: OverlayType.small,
    ),
    PhotoTemplate(
      id: 7,
      name: 'На полке магазина',
      description: 'Пачка стоит на полке, фото спереди',
      hint: 'Поставьте пачку на полку в магазине. Снимайте СПЕРЕДИ (как покупатель видит)',
      packCount: 1,
      packScale: 0.35,
      packAngle: 0,
      overlayType: OverlayType.shelf,
    ),
    PhotoTemplate(
      id: 8,
      name: 'В руке',
      description: 'Пачка в руке, фото спереди',
      hint: 'Держите пачку в руке лицевой стороной к камере. Второй рукой снимайте СПЕРЕДИ',
      packCount: 1,
      packScale: 0.4,
      packAngle: 0,
      overlayType: OverlayType.hand,
    ),
    PhotoTemplate(
      id: 9,
      name: 'Боковая сторона',
      description: 'Видна узкая боковая грань',
      hint: 'Поставьте пачку боком — должна быть видна УЗКАЯ сторона (торец). Фото СПЕРЕДИ',
      packCount: 1,
      packScale: 0.15,
      packAngle: 90,
      overlayType: OverlayType.side,
    ),
    PhotoTemplate(
      id: 10,
      name: 'Стопка из 3 пачек',
      description: '3 ОДИНАКОВЫЕ пачки друг на друге',
      hint: 'Положите 3 ОДИНАКОВЫЕ пачки стопкой друг на друга. Снимайте СБОКУ. Все пачки одного товара!',
      packCount: 3,
      packScale: 0.35,
      packAngle: 0,
      overlayType: OverlayType.stack,
    ),
  ];

  /// Получить шаблон по ID
  static PhotoTemplate? getById(int id) {
    try {
      return recountTemplates.firstWhere((t) => t.id == id);
    } catch (e) {
      return null;
    }
  }
}

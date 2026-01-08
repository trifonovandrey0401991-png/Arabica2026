/// Модель вопроса/шага формирования конверта
class EnvelopeQuestion {
  final String id;
  final String title;
  final String description;
  final String type; // "photo", "numbers", "expenses", "shift_select", "summary"
  final String section; // "ooo", "ip", "general"
  final int order;
  final bool isRequired;
  final bool isActive;
  final String? referencePhotoUrl; // Эталонное фото (для типа photo)

  EnvelopeQuestion({
    required this.id,
    required this.title,
    this.description = '',
    required this.type,
    required this.section,
    required this.order,
    this.isRequired = true,
    this.isActive = true,
    this.referencePhotoUrl,
  });

  factory EnvelopeQuestion.fromJson(Map<String, dynamic> json) {
    return EnvelopeQuestion(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      type: json['type'] ?? 'photo',
      section: json['section'] ?? 'general',
      order: json['order'] ?? 0,
      isRequired: json['isRequired'] ?? true,
      isActive: json['isActive'] ?? true,
      referencePhotoUrl: json['referencePhotoUrl'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'type': type,
    'section': section,
    'order': order,
    'isRequired': isRequired,
    'isActive': isActive,
    'referencePhotoUrl': referencePhotoUrl,
  };

  EnvelopeQuestion copyWith({
    String? id,
    String? title,
    String? description,
    String? type,
    String? section,
    int? order,
    bool? isRequired,
    bool? isActive,
    String? referencePhotoUrl,
  }) {
    return EnvelopeQuestion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      section: section ?? this.section,
      order: order ?? this.order,
      isRequired: isRequired ?? this.isRequired,
      isActive: isActive ?? this.isActive,
      referencePhotoUrl: referencePhotoUrl ?? this.referencePhotoUrl,
    );
  }

  /// Название типа на русском
  String get typeText {
    switch (type) {
      case 'photo':
        return 'Фото';
      case 'numbers':
        return 'Числа';
      case 'expenses':
        return 'Расходы';
      case 'shift_select':
        return 'Выбор смены';
      case 'summary':
        return 'Итог';
      default:
        return type;
    }
  }

  /// Название секции на русском
  String get sectionText {
    switch (section) {
      case 'ooo':
        return 'ООО';
      case 'ip':
        return 'ИП';
      case 'general':
        return 'Общее';
      default:
        return section;
    }
  }

  /// Дефолтные вопросы для инициализации
  static List<EnvelopeQuestion> get defaultQuestions => [
    EnvelopeQuestion(
      id: 'envelope_q_1',
      title: 'Выбор смены',
      description: 'Выберите тип смены',
      type: 'shift_select',
      section: 'general',
      order: 1,
    ),
    EnvelopeQuestion(
      id: 'envelope_q_2',
      title: 'ООО: Z-отчет',
      description: 'Сфотографируйте Z-отчет ООО',
      type: 'photo',
      section: 'ooo',
      order: 2,
    ),
    EnvelopeQuestion(
      id: 'envelope_q_3',
      title: 'ООО: Выручка и наличные',
      description: 'Введите данные ООО',
      type: 'numbers',
      section: 'ooo',
      order: 3,
    ),
    EnvelopeQuestion(
      id: 'envelope_q_4',
      title: 'ООО: Фото конверта',
      description: 'Сфотографируйте сформированный конверт ООО',
      type: 'photo',
      section: 'ooo',
      order: 4,
    ),
    EnvelopeQuestion(
      id: 'envelope_q_5',
      title: 'ИП: Z-отчет',
      description: 'Сфотографируйте Z-отчет ИП',
      type: 'photo',
      section: 'ip',
      order: 5,
    ),
    EnvelopeQuestion(
      id: 'envelope_q_6',
      title: 'ИП: Выручка и наличные',
      description: 'Введите данные ИП',
      type: 'numbers',
      section: 'ip',
      order: 6,
    ),
    EnvelopeQuestion(
      id: 'envelope_q_7',
      title: 'ИП: Расходы',
      description: 'Добавьте расходы',
      type: 'expenses',
      section: 'ip',
      order: 7,
    ),
    EnvelopeQuestion(
      id: 'envelope_q_8',
      title: 'ИП: Фото конверта',
      description: 'Сфотографируйте сформированный конверт ИП',
      type: 'photo',
      section: 'ip',
      order: 8,
    ),
    EnvelopeQuestion(
      id: 'envelope_q_9',
      title: 'Итог',
      description: 'Проверьте данные и отправьте отчет',
      type: 'summary',
      section: 'general',
      order: 9,
    ),
  ];
}

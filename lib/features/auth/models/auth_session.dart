/// Модель сессии авторизации
///
/// Хранит информацию о текущей сессии пользователя:
/// - токен сессии (уникальный идентификатор)
/// - телефон пользователя
/// - имя пользователя
/// - ID устройства
/// - время создания и истечения
/// - статус верификации
class AuthSession {
  final String sessionToken;
  final String phone;
  final String? name;
  final String deviceId;
  final String? deviceName;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? lastActivity;
  final bool isVerified;
  final String role; // client, employee, admin, developer

  AuthSession({
    required this.sessionToken,
    required this.phone,
    this.name,
    required this.deviceId,
    this.deviceName,
    required this.createdAt,
    required this.expiresAt,
    this.lastActivity,
    this.isVerified = false,
    this.role = 'client',
  });

  /// Проверяет, истекла ли сессия
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Проверяет, активна ли сессия (не истекла и верифицирована)
  bool get isActive => !isExpired && isVerified;

  /// Парсит дату из JSON (поддерживает timestamp и ISO строку)
  static DateTime _parseDate(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    } else if (value is String) {
      return DateTime.parse(value).toLocal();
    }
    throw FormatException('Invalid date format: $value');
  }

  /// Создаёт сессию из JSON (для загрузки с сервера)
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      sessionToken: json['sessionToken'] as String,
      phone: json['phone'] as String,
      name: json['name'] as String?,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String?,
      createdAt: _parseDate(json['createdAt']),
      expiresAt: _parseDate(json['expiresAt']),
      lastActivity: json['lastActivity'] != null
          ? _parseDate(json['lastActivity'])
          : null,
      isVerified: json['isVerified'] as bool? ?? false,
      role: json['role'] as String? ?? 'client',
    );
  }

  /// Преобразует сессию в JSON (для сохранения/отправки)
  Map<String, dynamic> toJson() {
    return {
      'sessionToken': sessionToken,
      'phone': phone,
      'name': name,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'lastActivity': lastActivity?.toIso8601String(),
      'isVerified': isVerified,
      'role': role,
    };
  }

  /// Создаёт копию сессии с обновлёнными полями
  AuthSession copyWith({
    String? sessionToken,
    String? phone,
    String? name,
    String? deviceId,
    String? deviceName,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? lastActivity,
    bool? isVerified,
    String? role,
  }) {
    return AuthSession(
      sessionToken: sessionToken ?? this.sessionToken,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastActivity: lastActivity ?? this.lastActivity,
      isVerified: isVerified ?? this.isVerified,
      role: role ?? this.role,
    );
  }

  @override
  String toString() {
    return 'AuthSession(phone: $phone, name: $name, role: $role, isActive: $isActive, expiresAt: $expiresAt)';
  }
}

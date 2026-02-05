/// Модель сессии авторизации
///
/// Хранит информацию о текущей сессии пользователя:
/// - токен сессии (уникальный идентификатор)
/// - телефон пользователя
/// - ID устройства
/// - время создания и истечения
/// - статус верификации
class AuthSession {
  final String sessionToken;
  final String phone;
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

  /// Создаёт сессию из JSON (для загрузки с сервера)
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      sessionToken: json['sessionToken'] as String,
      phone: json['phone'] as String,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      lastActivity: json['lastActivity'] != null
          ? DateTime.parse(json['lastActivity'] as String)
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
    return 'AuthSession(phone: $phone, role: $role, isActive: $isActive, expiresAt: $expiresAt)';
  }
}

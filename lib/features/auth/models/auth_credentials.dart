/// Модель учётных данных авторизации (PIN-код)
///
/// Хранит информацию о PIN-коде пользователя:
/// - хеш PIN-кода (не сам PIN!)
/// - соль для хеширования
/// - статус биометрии
/// - счётчик неудачных попыток
/// - время блокировки
class AuthCredentials {
  final String pinHash;
  final String salt;
  final bool biometricEnabled;
  final DateTime createdAt;
  final int failedAttempts;
  final DateTime? lockedUntil;

  /// Максимальное количество попыток перед блокировкой
  static const int maxFailedAttempts = 5;

  /// Длительность блокировки (15 минут)
  static const Duration lockoutDuration = Duration(minutes: 15);

  AuthCredentials({
    required this.pinHash,
    required this.salt,
    this.biometricEnabled = false,
    required this.createdAt,
    this.failedAttempts = 0,
    this.lockedUntil,
  });

  /// Проверяет, заблокирован ли аккаунт
  bool get isLocked {
    if (lockedUntil == null) return false;
    return DateTime.now().isBefore(lockedUntil!);
  }

  /// Возвращает оставшееся время блокировки
  Duration? get remainingLockTime {
    if (!isLocked) return null;
    return lockedUntil!.difference(DateTime.now());
  }

  /// Создаёт credentials из JSON
  factory AuthCredentials.fromJson(Map<String, dynamic> json) {
    return AuthCredentials(
      pinHash: json['pinHash'] as String,
      salt: json['salt'] as String,
      biometricEnabled: json['biometricEnabled'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      failedAttempts: json['failedAttempts'] as int? ?? 0,
      lockedUntil: json['lockedUntil'] != null
          ? DateTime.parse(json['lockedUntil'] as String)
          : null,
    );
  }

  /// Преобразует credentials в JSON
  Map<String, dynamic> toJson() {
    return {
      'pinHash': pinHash,
      'salt': salt,
      'biometricEnabled': biometricEnabled,
      'createdAt': createdAt.toIso8601String(),
      'failedAttempts': failedAttempts,
      'lockedUntil': lockedUntil?.toIso8601String(),
    };
  }

  /// Создаёт копию с обновлёнными полями
  AuthCredentials copyWith({
    String? pinHash,
    String? salt,
    bool? biometricEnabled,
    DateTime? createdAt,
    int? failedAttempts,
    DateTime? lockedUntil,
  }) {
    return AuthCredentials(
      pinHash: pinHash ?? this.pinHash,
      salt: salt ?? this.salt,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      createdAt: createdAt ?? this.createdAt,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockedUntil: lockedUntil ?? this.lockedUntil,
    );
  }

  @override
  String toString() {
    return 'AuthCredentials(biometricEnabled: $biometricEnabled, failedAttempts: $failedAttempts, isLocked: $isLocked)';
  }
}


/// Модель OTP-кода (одноразовый код подтверждения)
class OtpCode {
  final String phone;
  final String code;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int attempts;
  final bool verified;

  /// Время жизни OTP-кода (5 минут)
  static const Duration otpLifetime = Duration(minutes: 5);

  /// Максимальное количество попыток ввода кода
  static const int maxAttempts = 3;

  OtpCode({
    required this.phone,
    required this.code,
    required this.createdAt,
    required this.expiresAt,
    this.attempts = 0,
    this.verified = false,
  });

  /// Проверяет, истёк ли код
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Проверяет, можно ли ещё вводить код
  bool get canAttempt => !isExpired && attempts < maxAttempts && !verified;

  /// Создаёт OTP из JSON
  factory OtpCode.fromJson(Map<String, dynamic> json) {
    return OtpCode(
      phone: json['phone'] as String,
      code: json['code'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      attempts: json['attempts'] as int? ?? 0,
      verified: json['verified'] as bool? ?? false,
    );
  }

  /// Преобразует OTP в JSON
  Map<String, dynamic> toJson() {
    return {
      'phone': phone,
      'code': code,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'attempts': attempts,
      'verified': verified,
    };
  }
}

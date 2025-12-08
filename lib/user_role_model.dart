/// Роль пользователя в системе
enum UserRole {
  admin,    // Админ - видит весь функционал
  employee, // Сотрудник - видит функционал для сотрудников
  client,   // Клиент - видит базовый функционал
}

/// Модель данных пользователя с ролью
class UserRoleData {
  final UserRole role;
  final String displayName; // Имя для отображения (из столбца A или G)
  final String phone;
  final String? employeeName; // Имя из столбца G (если сотрудник/админ)

  UserRoleData({
    required this.role,
    required this.displayName,
    required this.phone,
    this.employeeName,
  });

  /// Проверить, является ли пользователь админом
  bool get isAdmin => role == UserRole.admin;

  /// Проверить, является ли пользователь сотрудником
  bool get isEmployee => role == UserRole.employee;

  /// Проверить, является ли пользователь клиентом
  bool get isClient => role == UserRole.client;

  /// Проверить, является ли пользователь сотрудником или админом
  bool get isEmployeeOrAdmin => role == UserRole.employee || role == UserRole.admin;

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'displayName': displayName,
    'phone': phone,
    'employeeName': employeeName,
  };

  factory UserRoleData.fromJson(Map<String, dynamic> json) {
    UserRole role;
    switch (json['role'] as String) {
      case 'admin':
        role = UserRole.admin;
        break;
      case 'employee':
        role = UserRole.employee;
        break;
      default:
        role = UserRole.client;
    }

    return UserRoleData(
      role: role,
      displayName: json['displayName'] ?? '',
      phone: json['phone'] ?? '',
      employeeName: json['employeeName'],
    );
  }

  /// Создать копию с обновленными полями
  UserRoleData copyWith({
    UserRole? role,
    String? displayName,
    String? phone,
    String? employeeName,
  }) {
    return UserRoleData(
      role: role ?? this.role,
      displayName: displayName ?? this.displayName,
      phone: phone ?? this.phone,
      employeeName: employeeName ?? this.employeeName,
    );
  }
}



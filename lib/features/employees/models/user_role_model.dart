/// Роль пользователя в системе
///
/// Иерархия ролей (от высшей к низшей):
/// - developer: разработчик - видит ВСЕ магазины и данные, доступ к управлению сетью
/// - admin: управляющий (региональный менеджер) - видит ТОЛЬКО свои магазины и сотрудников
/// - manager: заведующая магазина - видит свой магазин (или все магазины управляющего по настройке)
/// - employee: сотрудник - видит функционал для сотрудников
/// - client: клиент - видит базовый функционал
enum UserRole {
  developer, // Разработчик - видит ВСЕ магазины, управление сетью
  admin,     // Управляющий - видит ТОЛЬКО свои магазины и сотрудников
  manager,   // Заведующая магазина - видит свой магазин
  employee,  // Сотрудник - видит функционал для сотрудников
  client,    // Клиент - видит базовый функционал
}

/// Модель данных пользователя с ролью
class UserRoleData {
  final UserRole role;
  final String displayName; // Имя для отображения (из столбца A или G)
  final String phone;
  final String? employeeName; // Имя из столбца G (если сотрудник/админ)

  // Поля для мультитенантности
  final List<String> managedShopIds;     // Для admin: ID магазинов под управлением
  final List<String> managedEmployees;   // Для admin: телефоны сотрудников под управлением
  final String? primaryShopId;           // Основной магазин сотрудника
  final bool canSeeAllManagerShops;      // Для manager: видит все магазины управляющего

  UserRoleData({
    required this.role,
    required this.displayName,
    required this.phone,
    this.employeeName,
    this.managedShopIds = const [],
    this.managedEmployees = const [],
    this.primaryShopId,
    this.canSeeAllManagerShops = false,
  });

  /// Проверить, является ли пользователь разработчиком (видит ВСЕ)
  bool get isDeveloper => role == UserRole.developer;

  /// Проверить, является ли пользователь админом (управляющим)
  bool get isAdmin => role == UserRole.admin;

  /// Проверить, является ли пользователь заведующей магазина
  bool get isManager => role == UserRole.manager;

  /// Проверить, является ли пользователь сотрудником
  bool get isEmployee => role == UserRole.employee;

  /// Проверить, является ли пользователь клиентом
  bool get isClient => role == UserRole.client;

  /// Проверить, является ли пользователь сотрудником или выше
  bool get isEmployeeOrAdmin =>
      role == UserRole.employee ||
      role == UserRole.manager ||
      role == UserRole.admin ||
      role == UserRole.developer;

  /// Проверить, является ли пользователь админом или выше (developer/admin)
  bool get isAdminOrAbove => role == UserRole.admin || role == UserRole.developer;

  /// Проверить, имеет ли пользователь доступ к управлению сетью (только developer)
  bool get canManageNetwork => role == UserRole.developer;

  /// Проверить, имеет ли пользователь доступ к конкретному магазину
  bool hasAccessToShop(String shopId) {
    // Developer видит все магазины
    if (isDeveloper) return true;

    // Admin (управляющий) видит только свои магазины
    if (isAdmin) return managedShopIds.contains(shopId);

    // Manager видит свой магазин или все магазины управляющего (по настройке)
    if (isManager) {
      if (canSeeAllManagerShops) return true; // Видит все магазины управляющего
      return primaryShopId == shopId; // Только свой магазин
    }

    // Employee видит только свой магазин
    if (isEmployee) return primaryShopId == shopId;

    return false;
  }

  /// Проверить, имеет ли пользователь доступ к сотруднику
  bool hasAccessToEmployee(String employeePhone) {
    // Developer видит всех сотрудников
    if (isDeveloper) return true;

    // Admin видит только своих сотрудников
    if (isAdmin) return managedEmployees.contains(employeePhone);

    // Остальные видят только себя
    return phone == employeePhone;
  }

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'displayName': displayName,
    'phone': phone,
    'employeeName': employeeName,
    'managedShopIds': managedShopIds,
    'managedEmployees': managedEmployees,
    'primaryShopId': primaryShopId,
    'canSeeAllManagerShops': canSeeAllManagerShops,
  };

  factory UserRoleData.fromJson(Map<String, dynamic> json) {
    UserRole role;
    switch (json['role'] as String?) {
      case 'developer':
        role = UserRole.developer;
        break;
      case 'admin':
        role = UserRole.admin;
        break;
      case 'manager':
        role = UserRole.manager;
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
      managedShopIds: (json['managedShopIds'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
      managedEmployees: (json['managedEmployees'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
      primaryShopId: json['primaryShopId'],
      canSeeAllManagerShops: json['canSeeAllManagerShops'] == true,
    );
  }

  /// Создать копию с обновленными полями
  UserRoleData copyWith({
    UserRole? role,
    String? displayName,
    String? phone,
    String? employeeName,
    List<String>? managedShopIds,
    List<String>? managedEmployees,
    String? primaryShopId,
    bool? canSeeAllManagerShops,
  }) {
    return UserRoleData(
      role: role ?? this.role,
      displayName: displayName ?? this.displayName,
      phone: phone ?? this.phone,
      employeeName: employeeName ?? this.employeeName,
      managedShopIds: managedShopIds ?? this.managedShopIds,
      managedEmployees: managedEmployees ?? this.managedEmployees,
      primaryShopId: primaryShopId ?? this.primaryShopId,
      canSeeAllManagerShops: canSeeAllManagerShops ?? this.canSeeAllManagerShops,
    );
  }

  @override
  String toString() {
    return 'UserRoleData(role: ${role.name}, displayName: $displayName, phone: $phone, '
        'managedShops: ${managedShopIds.length}, managedEmployees: ${managedEmployees.length})';
  }
}













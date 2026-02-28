/// Central registry of all SharedPreferences keys used in the app.
///
/// Use these constants instead of hardcoded strings to prevent typos
/// and key drift between read and write locations.
abstract class PrefsKeys {
  // ── Auth & user identity ──────────────────────────────────────────────────
  /// Phone number of the currently logged-in user (written by auth/registration flow)
  static const String userPhone = 'user_phone';

  /// Session token for API requests
  static const String sessionToken = 'session_token';

  // ── Display names (3 keys used historically — read in priority order) ─────
  /// Primary display name (written by auth, registration and role service)
  static const String userName = 'user_name';

  /// Employee name from the employees list (written by employees_page + role service)
  static const String currentEmployeeName = 'currentEmployeeName';

  /// Employee name from role data (written by user_role_service)
  static const String userEmployeeName = 'user_employee_name';

  // ── Role & access ─────────────────────────────────────────────────────────
  /// Serialized UserRoleData JSON
  static const String userRole = 'user_role';

  /// Whether the user is an admin
  static const String isAdmin = 'is_admin';

  /// Cached role string for fast access
  static const String roleName = 'role_name';

  // ── UI preferences ────────────────────────────────────────────────────────
  /// Last seen app version (for update prompts)
  static const String lastSeenVersion = 'last_seen_version';

  /// Whether push notifications were requested
  static const String pushNotificationsRequested = 'push_notifications_requested';

  // ── Wholesale orders ──────────────────────────────────────────────────────
  /// Whether the current user has wholesale order access
  static const String wholesaleAuthorized = 'wholesale_authorized';
}

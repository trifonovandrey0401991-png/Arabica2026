import '../../../core/services/base_http_service.dart';
import '../../../core/utils/logger.dart';

/// Service for AI feature toggles (on/off per system).
/// Settings are stored on the server in app_settings table.
/// Cached in memory for fast access during workflows.
class AiToggleService {
  static Map<String, bool>? _cached;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 5);

  /// Get all AI toggles. Returns cached if fresh, otherwise fetches from server.
  static Future<Map<String, bool>> getToggles({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null && _cacheTime != null) {
      final age = DateTime.now().difference(_cacheTime!);
      if (age < _cacheDuration) return _cached!;
    }

    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/ai-dashboard/ai-toggles',
      );
      if (result != null && result['success'] == true && result['toggles'] != null) {
        final toggles = Map<String, dynamic>.from(result['toggles']);
        _cached = toggles.map((k, v) => MapEntry(k, v == true));
        _cacheTime = DateTime.now();
        return _cached!;
      }
    } catch (e) {
      Logger.error('Failed to load AI toggles', e);
    }

    // Default: all enabled
    return _defaults;
  }

  /// Update one or more toggles on the server.
  static Future<bool> updateToggles(Map<String, bool> changes) async {
    try {
      final result = await BaseHttpService.putRaw(
        endpoint: '/api/ai-dashboard/ai-toggles',
        body: {'toggles': changes},
      );
      if (result != null && result['success'] == true) {
        // Update local cache
        _cached = (_cached ?? {..._defaults})..addAll(changes);
        _cacheTime = DateTime.now();
        return true;
      }
    } catch (e) {
      Logger.error('Failed to update AI toggles', e);
    }
    return false;
  }

  /// Check if a specific AI system is enabled.
  static Future<bool> isEnabled(String systemKey) async {
    final toggles = await getToggles();
    return toggles[systemKey] ?? true;
  }

  /// Invalidate cache (e.g. after manual toggle).
  static void invalidateCache() {
    _cached = null;
    _cacheTime = null;
  }

  static const _defaults = {
    'zReport': true,
    'coffeeMachine': true,
    'cigaretteVision': true,
    'shiftAi': true,
  };
}

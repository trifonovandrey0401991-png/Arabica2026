import 'dart:async';

/// Менеджер кэширования данных
class CacheManager {
  static final Map<String, CacheEntry> _memoryCache = {};
  static const Duration defaultCacheDuration = Duration(minutes: 5);
  
  /// Получить данные из кэша
  static T? get<T>(String key) {
    final entry = _memoryCache[key];
    if (entry == null) return null;
    
    if (entry.expiresAt.isBefore(DateTime.now())) {
      _memoryCache.remove(key);
      return null;
    }
    
    return entry.data as T?;
  }
  
  /// Сохранить данные в кэш
  static void set<T>(String key, T data, {Duration? duration}) {
    _memoryCache[key] = CacheEntry(
      data: data,
      expiresAt: DateTime.now().add(duration ?? defaultCacheDuration),
    );
  }
  
  /// Очистить кэш
  static void clear() {
    _memoryCache.clear();
  }
  
  /// Удалить конкретную запись из кэша
  static void remove(String key) {
    _memoryCache.remove(key);
  }
  
  /// Очистить кэш по паттерну ключа
  static void clearByPattern(String pattern) {
    _memoryCache.removeWhere((key, entry) => key.contains(pattern));
  }
  
  /// Очистить устаревшие записи
  static void clearExpired() {
    final now = DateTime.now();
    _memoryCache.removeWhere((key, entry) => entry.expiresAt.isBefore(now));
  }
  
  /// Получить данные из кэша или выполнить функцию
  static Future<T> getOrFetch<T>(
    String key,
    Future<T> Function() fetchFunction, {
    Duration? duration,
  }) async {
    final cached = get<T>(key);
    if (cached != null) {
      return cached;
    }
    
    final data = await fetchFunction();
    set(key, data, duration: duration);
    return data;
  }
}

class CacheEntry {
  final dynamic data;
  final DateTime expiresAt;
  
  CacheEntry({required this.data, required this.expiresAt});
}







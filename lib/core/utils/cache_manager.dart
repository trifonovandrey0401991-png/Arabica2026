import 'dart:async';

/// Менеджер кэширования данных с лимитом памяти
class CacheManager {
  static final Map<String, CacheEntry> _memoryCache = {};
  static const Duration defaultCacheDuration = Duration(minutes: 5);

  /// Максимальное количество записей в кэше (защита от memory leak)
  static const int maxEntries = 200;

  /// Текущее количество записей в кэше
  static int get size => _memoryCache.length;

  /// Получить данные из кэша
  static T? get<T>(String key) {
    final entry = _memoryCache[key];
    if (entry == null) return null;

    if (entry.expiresAt.isBefore(DateTime.now())) {
      _memoryCache.remove(key);
      return null;
    }

    // Обновляем время последнего доступа (LRU)
    entry.lastAccessedAt = DateTime.now();

    return entry.data as T?;
  }

  /// Сохранить данные в кэш
  static void set<T>(String key, T data, {Duration? duration}) {
    // Проверяем лимит перед добавлением
    if (!_memoryCache.containsKey(key) && _memoryCache.length >= maxEntries) {
      _evictOldEntries();
    }

    _memoryCache[key] = CacheEntry(
      data: data,
      expiresAt: DateTime.now().add(duration ?? defaultCacheDuration),
    );
  }

  /// Удалить старые записи при достижении лимита (LRU)
  static void _evictOldEntries() {
    // Сначала удаляем все истёкшие записи
    clearExpired();

    // Если всё ещё превышен лимит - удаляем 20% самых старых (по последнему доступу)
    if (_memoryCache.length >= maxEntries) {
      final entries = _memoryCache.entries.toList()
        ..sort((a, b) => a.value.lastAccessedAt.compareTo(b.value.lastAccessedAt));

      final toRemove = (_memoryCache.length * 0.2).ceil();
      for (int i = 0; i < toRemove && i < entries.length; i++) {
        _memoryCache.remove(entries[i].key);
      }
    }
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
  final DateTime createdAt;
  DateTime lastAccessedAt;

  CacheEntry({required this.data, required this.expiresAt})
      : createdAt = DateTime.now(),
        lastAccessedAt = DateTime.now();
}







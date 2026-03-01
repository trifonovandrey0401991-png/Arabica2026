import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'logger.dart';

/// Persistent disk cache for data that changes rarely (e.g., work schedule).
/// Survives app restarts, no expiration — overwritten on each server fetch.
class DiskCache {
  static String? _cacheDir;

  static Future<String> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/app_cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    _cacheDir = cacheDir.path;
    return _cacheDir!;
  }

  /// Read cached JSON from disk. Returns null if not found or corrupted.
  static Future<Map<String, dynamic>?> read(String key) async {
    try {
      final dir = await _getCacheDir();
      final file = File('$dir/$key.json');
      if (!file.existsSync()) return null;
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      Logger.error('DiskCache read error ($key)', e);
      return null;
    }
  }

  /// Write JSON data to disk cache.
  static Future<void> write(String key, Map<String, dynamic> data) async {
    try {
      final dir = await _getCacheDir();
      final file = File('$dir/$key.json');
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      Logger.error('DiskCache write error ($key)', e);
    }
  }

  /// Delete a specific cache entry.
  static Future<void> remove(String key) async {
    try {
      final dir = await _getCacheDir();
      final file = File('$dir/$key.json');
      if (file.existsSync()) await file.delete();
    } catch (e) {
      Logger.error('DiskCache remove error ($key)', e);
    }
  }
}

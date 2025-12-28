import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants/api_constants.dart';
import '../utils/logger.dart';

class BaseHttpService {
  /// Generic GET list request
  static Future<List<T>> getList<T>({
    required String endpoint,
    required T Function(Map<String, dynamic>) fromJson,
    required String listKey,
    Map<String, String>? queryParams,
    Duration? timeout,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.serverUrl}$endpoint')
          .replace(queryParameters: queryParams);

      Logger.debug('📥 GET $endpoint');

      final response = await http
          .get(uri)
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final items = result[listKey] as List<dynamic>;
          final list = items
              .map((json) => fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Loaded ${list.length} items from $endpoint');
          return list;
        } else {
          Logger.error('❌ API error: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode} on $endpoint');
      }
      return [];
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return [];
    }
  }

  /// Generic GET single item request
  static Future<T?> get<T>({
    required String endpoint,
    required T Function(Map<String, dynamic>) fromJson,
    required String itemKey,
    Duration? timeout,
  }) async {
    try {
      Logger.debug('📥 GET $endpoint');

      final response = await http
          .get(Uri.parse('${ApiConstants.serverUrl}$endpoint'))
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Loaded item from $endpoint');
          return fromJson(result[itemKey] as Map<String, dynamic>);
        } else {
          Logger.error('❌ API error: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode} on $endpoint');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return null;
    }
  }

  /// Generic POST request
  static Future<T?> post<T>({
    required String endpoint,
    required Map<String, dynamic> body,
    required T Function(Map<String, dynamic>) fromJson,
    required String itemKey,
    Duration? timeout,
  }) async {
    try {
      Logger.debug('📤 POST $endpoint');

      final response = await http
          .post(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.jsonHeaders,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Created item at $endpoint');
          return fromJson(result[itemKey] as Map<String, dynamic>);
        } else {
          Logger.error('❌ API error: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode} on $endpoint');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return null;
    }
  }

  /// Generic PUT request
  static Future<T?> put<T>({
    required String endpoint,
    required Map<String, dynamic> body,
    required T Function(Map<String, dynamic>) fromJson,
    required String itemKey,
    Duration? timeout,
  }) async {
    try {
      Logger.debug('📤 PUT $endpoint');

      final response = await http
          .put(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.jsonHeaders,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Updated item at $endpoint');
          return fromJson(result[itemKey] as Map<String, dynamic>);
        } else {
          Logger.error('❌ API error: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode} on $endpoint');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return null;
    }
  }

  /// Generic DELETE request
  static Future<bool> delete({
    required String endpoint,
    Duration? timeout,
  }) async {
    try {
      Logger.debug('🗑️ DELETE $endpoint');

      final response = await http
          .delete(Uri.parse('${ApiConstants.serverUrl}$endpoint'))
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Deleted item at $endpoint');
          return true;
        } else {
          Logger.error('❌ API error: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode} on $endpoint');
      }
      return false;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return false;
    }
  }

  /// Simple POST request that returns success boolean
  static Future<bool> simplePost({
    required String endpoint,
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    try {
      Logger.debug('📤 POST $endpoint');

      final response = await http
          .post(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.jsonHeaders,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return false;
    }
  }

  /// Simple GET request that returns success boolean
  static Future<bool> simpleGet({
    required String endpoint,
    Duration? timeout,
  }) async {
    try {
      Logger.debug('📥 GET $endpoint');

      final response = await http
          .get(Uri.parse('${ApiConstants.serverUrl}$endpoint'))
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return false;
    }
  }
}

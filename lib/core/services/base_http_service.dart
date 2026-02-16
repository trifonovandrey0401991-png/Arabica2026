import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import '../constants/api_constants.dart';
import '../utils/logger.dart';

/// Базовый HTTP-сервис для работы с API.
///
/// Предоставляет унифицированные методы для HTTP-запросов с:
/// - Автоматической сериализацией/десериализацией JSON
/// - Обработкой ошибок и логированием
/// - Настраиваемыми таймаутами
/// - Поддержкой query-параметров
/// - Глобальным лимитом параллельных запросов (семафор)
///
/// Все feature-сервисы должны использовать этот класс для API-запросов.
///
/// При получении 401 логирует предупреждение о необходимости авторизации.
///
/// Пример использования:
/// ```dart
/// // Получить список
/// final items = await BaseHttpService.getList<Task>(
///   endpoint: '/api/tasks',
///   fromJson: Task.fromJson,
///   listKey: 'tasks',
/// );
///
/// // Создать элемент
/// final task = await BaseHttpService.post<Task>(
///   endpoint: '/api/tasks',
///   body: {'title': 'New Task'},
///   fromJson: Task.fromJson,
///   itemKey: 'task',
/// );
/// ```
class BaseHttpService {
  // ==================== Семафор (лимит параллельных запросов) ====================

  /// Максимум одновременных HTTP-запросов к серверу.
  /// 6 — стандартный лимит браузеров на один хост.
  /// Предотвращает перегрузку сервера при массовой загрузке данных.
  static const int _maxConcurrent = 6;
  static int _activeRequests = 0;
  static final List<Completer<void>> _waitQueue = [];

  /// Занять слот перед HTTP-запросом. Если все слоты заняты — ждать в очереди.
  static Future<void> _acquireSlot() async {
    if (_activeRequests < _maxConcurrent) {
      _activeRequests++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  /// Освободить слот после завершения HTTP-запроса.
  static void _releaseSlot() {
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeAt(0);
      next.complete();
    } else {
      _activeRequests--;
    }
  }

  // ==================== Логирование ====================

  /// Логирование ошибок HTTP с детальной диагностикой 401/403
  static void _logHttpError(int statusCode, String endpoint, String body) {
    if (statusCode == 401) {
      Logger.error('🔒 Требуется авторизация: $endpoint (токен: ${ApiConstants.sessionToken != null ? "есть" : "НЕТ"})');
    } else if (statusCode == 403) {
      Logger.error('🚫 Недостаточно прав: $endpoint');
    } else {
      Logger.error('❌ HTTP $statusCode on $endpoint');
    }
  }

  // ==================== GET ====================

  /// Получить список элементов с сервера.
  ///
  /// [endpoint] - путь API (например, '/api/tasks')
  /// [fromJson] - функция десериализации элемента
  /// [listKey] - ключ массива в ответе (например, 'tasks')
  /// [queryParams] - опциональные query-параметры
  /// [timeout] - таймаут запроса (по умолчанию 15 сек)
  static Future<List<T>> getList<T>({
    required String endpoint,
    required T Function(Map<String, dynamic>) fromJson,
    required String listKey,
    Map<String, String>? queryParams,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      final uri = Uri.parse('${ApiConstants.serverUrl}$endpoint')
          .replace(queryParameters: queryParams);

      Logger.debug('📥 GET $endpoint');

      final response = await http
          .get(uri, headers: ApiConstants.headersWithApiKey)
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final rawItems = result[listKey];
          if (rawItems == null || rawItems is! List) {
            Logger.error('❌ Missing or invalid "$listKey" in response from $endpoint');
            return [];
          }
          final list = rawItems
              .map((json) => fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Loaded ${list.length} items from $endpoint');
          return list;
        } else {
          Logger.error('❌ API error: ${result['error']}');
        }
      } else {
        _logHttpError(response.statusCode, endpoint, response.body);
      }
      return [];
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return [];
    } finally {
      _releaseSlot();
    }
  }

  /// Получить один элемент с сервера.
  ///
  /// [endpoint] - путь API с ID (например, '/api/tasks/123')
  /// [fromJson] - функция десериализации элемента
  /// [itemKey] - ключ объекта в ответе (например, 'task')
  /// [timeout] - таймаут запроса
  static Future<T?> get<T>({
    required String endpoint,
    required T Function(Map<String, dynamic>) fromJson,
    required String itemKey,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('📥 GET $endpoint');

      final response = await http
          .get(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final rawItem = result[itemKey];
          if (rawItem == null || rawItem is! Map<String, dynamic>) {
            Logger.error('❌ Missing or invalid "$itemKey" in response from $endpoint');
            return null;
          }
          Logger.debug('✅ Loaded item from $endpoint');
          return fromJson(rawItem);
        } else {
          Logger.error('❌ API error: ${result['error']}');
        }
      } else {
        _logHttpError(response.statusCode, endpoint, response.body);
      }
      return null;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return null;
    } finally {
      _releaseSlot();
    }
  }

  /// Простой GET-запрос для проверки статуса.
  ///
  /// Возвращает true при success: true в ответе.
  static Future<bool> simpleGet({
    required String endpoint,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('📥 GET $endpoint');

      final response = await http
          .get(Uri.parse('${ApiConstants.serverUrl}$endpoint'), headers: ApiConstants.headersWithApiKey)
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return false;
    } finally {
      _releaseSlot();
    }
  }

  /// GET-запрос с возвратом сырого Map.
  ///
  /// Используется когда нужен доступ к нескольким полям ответа.
  /// Возвращает весь JSON-ответ при success: true.
  static Future<Map<String, dynamic>?> getRaw({
    required String endpoint,
    Map<String, String>? queryParams,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      var uri = Uri.parse('${ApiConstants.serverUrl}$endpoint');
      if (queryParams != null && queryParams.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParams);
      }

      Logger.debug('📥 GET $endpoint');

      final response = await http
          .get(uri, headers: ApiConstants.headersWithApiKey)
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return null;
    } finally {
      _releaseSlot();
    }
  }

  // ==================== POST ====================

  /// Создать элемент на сервере (POST).
  ///
  /// [endpoint] - путь API
  /// [body] - данные для отправки
  /// [fromJson] - функция десериализации созданного элемента
  /// [itemKey] - ключ объекта в ответе
  static Future<T?> post<T>({
    required String endpoint,
    required Map<String, dynamic> body,
    required T Function(Map<String, dynamic>) fromJson,
    required String itemKey,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('📤 POST $endpoint');

      final response = await http
          .post(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final rawItem = result[itemKey];
          if (rawItem == null || rawItem is! Map<String, dynamic>) {
            Logger.error('❌ Missing or invalid "$itemKey" in response from $endpoint');
            return null;
          }
          Logger.debug('✅ Created item at $endpoint');
          return fromJson(rawItem);
        } else {
          Logger.error('❌ API error: ${result['error']}');
        }
      } else {
        _logHttpError(response.statusCode, endpoint, response.body);
      }
      return null;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return null;
    } finally {
      _releaseSlot();
    }
  }

  /// Простой POST-запрос без десериализации ответа.
  ///
  /// Используется когда не нужен возвращаемый объект.
  /// Возвращает true при success: true в ответе.
  static Future<bool> simplePost({
    required String endpoint,
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('📤 POST $endpoint');

      final response = await http
          .post(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        if (result['success'] != true) {
          Logger.error('❌ API error on POST $endpoint: ${result['error']}');
        }
        return result['success'] == true;
      }
      _logHttpError(response.statusCode, endpoint, response.body);
      return false;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return false;
    } finally {
      _releaseSlot();
    }
  }

  /// POST-запрос с возвратом сырого Map.
  ///
  /// Используется когда нужен доступ к нескольким полям ответа.
  static Future<Map<String, dynamic>?> postRaw({
    required String endpoint,
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('📤 POST $endpoint');

      final response = await http
          .post(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return null;
    } finally {
      _releaseSlot();
    }
  }

  /// POST-запрос с возвратом сырого Map включая ошибки от сервера.
  ///
  /// В отличие от postRaw, этот метод возвращает ответ даже при 400 ошибках,
  /// чтобы можно было получить сообщение об ошибке от сервера.
  static Future<HttpResult> postRawWithError({
    required String endpoint,
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('📤 POST $endpoint');

      final response = await http
          .post(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return HttpResult(success: false, error: 'Invalid response format');
      }
      final result = decoded;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (result['success'] == true) {
          return HttpResult(success: true, data: result);
        }
        return HttpResult(
          success: false,
          error: result['error'] as String? ?? 'Неизвестная ошибка',
          data: result,
        );
      }

      // Для 400 и других ошибок - возвращаем сообщение от сервера
      Logger.debug('❌ HTTP ${response.statusCode} on $endpoint: ${result['error']}');
      return HttpResult(
        success: false,
        error: result['error'] as String? ?? 'HTTP ${response.statusCode}',
        data: result,
      );
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return HttpResult(success: false, error: e.toString());
    } finally {
      _releaseSlot();
    }
  }

  // ==================== PUT ====================

  /// Обновить элемент на сервере (PUT).
  ///
  /// [endpoint] - путь API с ID
  /// [body] - обновленные данные
  /// [fromJson] - функция десериализации
  /// [itemKey] - ключ объекта в ответе
  static Future<T?> put<T>({
    required String endpoint,
    required Map<String, dynamic> body,
    required T Function(Map<String, dynamic>) fromJson,
    required String itemKey,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('📤 PUT $endpoint');

      final response = await http
          .put(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final rawItem = result[itemKey];
          if (rawItem == null || rawItem is! Map<String, dynamic>) {
            Logger.error('❌ Missing or invalid "$itemKey" in response from $endpoint');
            return null;
          }
          Logger.debug('✅ Updated item at $endpoint');
          return fromJson(rawItem);
        } else {
          Logger.error('❌ API error: ${result['error']}');
        }
      } else {
        _logHttpError(response.statusCode, endpoint, response.body);
      }
      return null;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return null;
    } finally {
      _releaseSlot();
    }
  }

  /// Простой PUT-запрос без десериализации.
  ///
  /// Возвращает true при success: true в ответе.
  static Future<bool> simplePut({
    required String endpoint,
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('📤 PUT $endpoint');

      final response = await http
          .put(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] != true) {
          Logger.error('❌ API error on PUT $endpoint: ${result['error']}');
        }
        return result['success'] == true;
      }
      _logHttpError(response.statusCode, endpoint, response.body);
      return false;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return false;
    } finally {
      _releaseSlot();
    }
  }

  /// PUT-запрос с возвратом сырого Map.
  ///
  /// Используется когда нужен доступ к нескольким полям ответа.
  static Future<Map<String, dynamic>?> putRaw({
    required String endpoint,
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('📤 PUT $endpoint');

      final response = await http
          .put(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return null;
    } finally {
      _releaseSlot();
    }
  }

  // ==================== PATCH ====================

  /// Частичное обновление элемента (PATCH).
  ///
  /// [endpoint] - путь API с ID
  /// [body] - частичные данные для обновления
  /// [fromJson] - функция десериализации
  /// [itemKey] - ключ объекта в ответе
  static Future<T?> patch<T>({
    required String endpoint,
    required Map<String, dynamic> body,
    required T Function(Map<String, dynamic>) fromJson,
    required String itemKey,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('📤 PATCH $endpoint');

      final response = await http
          .patch(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final rawItem = result[itemKey];
          if (rawItem == null || rawItem is! Map<String, dynamic>) {
            Logger.error('❌ Missing or invalid "$itemKey" in response from $endpoint');
            return null;
          }
          Logger.debug('✅ Patched item at $endpoint');
          return fromJson(rawItem);
        }
      }
      return null;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return null;
    } finally {
      _releaseSlot();
    }
  }

  /// PATCH-запрос возвращающий сырой JSON.
  ///
  /// Используется когда нужен доступ к нескольким полям ответа.
  static Future<Map<String, dynamic>?> patchRaw({
    required String endpoint,
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('📤 PATCH $endpoint');

      final response = await http
          .patch(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return null;
    } finally {
      _releaseSlot();
    }
  }

  /// Простой PATCH-запрос без десериализации.
  ///
  /// Возвращает true при success: true в ответе.
  static Future<bool> simplePatch({
    required String endpoint,
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('📤 PATCH $endpoint');

      final response = await http
          .patch(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] != true) {
          Logger.error('❌ API error on PATCH $endpoint: ${result['error']}');
        }
        return result['success'] == true;
      }
      _logHttpError(response.statusCode, endpoint, response.body);
      return false;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return false;
    } finally {
      _releaseSlot();
    }
  }

  // ==================== DELETE ====================

  /// Удалить элемент на сервере.
  ///
  /// [endpoint] - путь API с ID (например, '/api/tasks/123')
  /// Возвращает true при успешном удалении.
  static Future<bool> delete({
    required String endpoint,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('🗑️ DELETE $endpoint');

      final response = await http
          .delete(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
          )
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
        _logHttpError(response.statusCode, endpoint, response.body);
      }
      return false;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return false;
    } finally {
      _releaseSlot();
    }
  }

  /// Удалить элемент на сервере с возвратом полного ответа.
  ///
  /// [endpoint] - путь API с ID (например, '/api/tasks/123')
  /// Возвращает Map с данными ответа или null при ошибке.
  static Future<Map<String, dynamic>?> deleteWithResponse({
    required String endpoint,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('🗑️ DELETE $endpoint');

      final response = await http
          .delete(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Deleted item at $endpoint');
          return result;
        } else {
          Logger.error('❌ API error: ${result['error']}');
          return result;
        }
      } else {
        _logHttpError(response.statusCode, endpoint, response.body);
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return {
        'success': false,
        'error': e.toString(),
      };
    } finally {
      _releaseSlot();
    }
  }

  /// DELETE-запрос с возвратом сырого Map.
  ///
  /// Используется когда нужен доступ к полям ответа после удаления.
  static Future<Map<String, dynamic>?> deleteRaw({
    required String endpoint,
    Duration? timeout,
  }) async {
    await _acquireSlot();
    try {
      Logger.debug('🗑️ DELETE $endpoint');

      final response = await http
          .delete(
            Uri.parse('${ApiConstants.serverUrl}$endpoint'),
            headers: ApiConstants.headersWithApiKey,
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      Logger.error('❌ Request failed for $endpoint', e);
      return null;
    } finally {
      _releaseSlot();
    }
  }
}

/// Результат HTTP-запроса с поддержкой ошибок от сервера.
class HttpResult {
  final bool success;
  final String? error;
  final Map<String, dynamic>? data;

  HttpResult({
    required this.success,
    this.error,
    this.data,
  });
}

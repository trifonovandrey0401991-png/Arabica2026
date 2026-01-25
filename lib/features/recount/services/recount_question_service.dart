import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../models/recount_question_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../shops/services/shop_products_service.dart';

// http и dart:convert оставлены для multipart загрузки эталонных фото и bulk операций

class RecountQuestionService {
  static const String baseEndpoint = ApiConstants.recountQuestionsEndpoint;

  /// Загрузить статусы isAiActive из мастер-каталога
  /// Возвращает Map<barcode, isAiActive>
  static Future<Map<String, bool>> _loadMasterCatalogAiStatus() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/master-catalog'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final products = data['products'] as List? ?? [];

        final Map<String, bool> result = {};
        for (final p in products) {
          final barcode = p['barcode']?.toString();
          if (barcode != null && barcode.isNotEmpty) {
            result[barcode] = p['isAiActive'] ?? false;
          }
        }
        return result;
      }
    } catch (e) {
      Logger.error('Ошибка загрузки мастер-каталога для isAiActive', e);
    }
    return {};
  }

  /// Получить все вопросы
  static Future<List<RecountQuestion>> getQuestions() async {
    Logger.debug('📥 Загрузка вопросов пересчета с сервера...');

    return await BaseHttpService.getList<RecountQuestion>(
      endpoint: baseEndpoint,
      fromJson: (json) => RecountQuestion.fromJson(json),
      listKey: 'questions',
    );
  }

  /// Получить вопросы из DBF каталога магазина (реальные товары с остатками)
  /// [shopId] - ID магазина
  /// [onlyWithStock] - если true, возвращает только товары с остатком > 0
  static Future<List<RecountQuestion>> getQuestionsFromShopProducts({
    required String shopId,
    bool onlyWithStock = false,
  }) async {
    Logger.debug('📥 Загрузка товаров из DBF для магазина: $shopId');

    // Загружаем товары магазина из DBF
    final products = await ShopProductsService.getShopProducts(shopId);
    Logger.debug('📦 Загружено товаров из DBF: ${products.length}');

    // Статистика по грейдам
    int grade1Count = 0;
    int grade2Count = 0;
    int grade3Count = 0;

    // Загружаем данные из мастер-каталога для получения isAiActive
    final masterCatalogMap = await _loadMasterCatalogAiStatus();
    Logger.info('📊 [AI-DEBUG] Загружено ${masterCatalogMap.length} товаров из мастер-каталога');

    // Debug: показать сколько товаров с AI активным
    final aiActiveCount = masterCatalogMap.values.where((v) => v).length;
    Logger.info('🤖 [AI-DEBUG] Товаров с AI активным: $aiActiveCount');

    // Debug: показать примеры баркодов из мастер-каталога
    if (masterCatalogMap.isNotEmpty) {
      final sampleBarcodes = masterCatalogMap.keys.take(5).toList();
      Logger.info('🏷️ [AI-DEBUG] Примеры баркодов мастер-каталога: $sampleBarcodes');
    }

    // Debug: показать примеры kod из DBF
    if (products.isNotEmpty) {
      final sampleKods = products.take(5).map((p) => p.kod).toList();
      Logger.info('🏷️ [AI-DEBUG] Примеры kod из DBF: $sampleKods');
    }

    // Подсчёт сколько совпало и сколько из них с AI
    int matchedCount = 0;
    int matchedWithAiCount = 0;
    for (final p in products) {
      if (masterCatalogMap.containsKey(p.kod)) {
        matchedCount++;
        if (masterCatalogMap[p.kod] == true) {
          matchedWithAiCount++;
        }
      }
    }
    Logger.info('🔗 [AI-DEBUG] Совпавших баркодов: $matchedCount из ${products.length}');
    Logger.info('🤖 [AI-DEBUG] Из них с AI активным: $matchedWithAiCount');

    // Конвертируем ShopProduct в RecountQuestion
    // Грейд рассчитывается динамически на основе продаж и остатков
    List<RecountQuestion> questions = products.map((p) {
      final grade = p.calculateGrade();

      // Считаем статистику
      if (grade == 1) grade1Count++;
      else if (grade == 2) grade2Count++;
      else grade3Count++;

      // Получаем isAiActive из мастер-каталога
      final isAiActive = masterCatalogMap[p.kod] ?? false;

      return RecountQuestion(
        id: 'dbf_${p.kod}',
        barcode: p.kod,
        productGroup: p.group,
        productName: p.name,
        grade: grade, // Грейд рассчитывается по продажам и остаткам
        stock: p.stock,
        isAiActive: isAiActive,
      );
    }).toList();

    Logger.debug('📊 Распределение грейдов: G1=$grade1Count, G2=$grade2Count, G3=$grade3Count');

    // Фильтруем по остатку если нужно
    if (onlyWithStock) {
      questions = questions.where((q) => q.hasStock).toList();
      Logger.debug('📦 После фильтрации (stock > 0): ${questions.length}');
    }

    return questions;
  }

  /// Проверить есть ли синхронизированные товары для магазина
  static Future<bool> hasShopProducts(String shopId) async {
    final shops = await ShopProductsService.getShopsWithProducts();
    return shops.any((s) => s.shopId == shopId);
  }

  /// Создать новый вопрос
  static Future<RecountQuestion?> createQuestion({
    required String question,
    required int grade,
    Map<String, String>? referencePhotos,
  }) async {
    Logger.debug('📤 Создание вопроса пересчета: $question');

    final requestBody = <String, dynamic>{
      'question': question,
      'grade': grade,
    };
    if (referencePhotos != null) requestBody['referencePhotos'] = referencePhotos;

    return await BaseHttpService.post<RecountQuestion>(
      endpoint: baseEndpoint,
      body: requestBody,
      fromJson: (json) => RecountQuestion.fromJson(json),
      itemKey: 'question',
    );
  }

  /// Обновить вопрос
  static Future<RecountQuestion?> updateQuestion({
    required String id,
    String? question,
    int? grade,
    Map<String, String>? referencePhotos,
  }) async {
    Logger.debug('📤 Обновление вопроса пересчета: $id');

    final body = <String, dynamic>{};
    if (question != null) body['question'] = question;
    if (grade != null) body['grade'] = grade;
    if (referencePhotos != null) body['referencePhotos'] = referencePhotos;

    return await BaseHttpService.put<RecountQuestion>(
      endpoint: '$baseEndpoint/$id',
      body: body,
      fromJson: (json) => RecountQuestion.fromJson(json),
      itemKey: 'question',
    );
  }

  /// Загрузить эталонное фото для вопроса
  static Future<String?> uploadReferencePhoto({
    required String questionId,
    required String shopAddress,
    required File photoFile,
  }) async {
    try {
      Logger.debug('📤 Загрузка эталонного фото для вопроса: $questionId, магазин: $shopAddress');

      final url = '${ApiConstants.serverUrl}$baseEndpoint/$questionId/reference-photo';
      final request = http.MultipartRequest('POST', Uri.parse(url));

      // Добавляем файл - читаем байты для поддержки веб и мобильных платформ
      final bytes = await photoFile.readAsBytes();

      // Генерируем безопасное имя файла с timestamp
      final filename = 'recount_ref_${questionId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: filename,
        ),
      );

      // Добавляем адрес магазина
      request.fields['shopAddress'] = shopAddress;

      final streamedResponse = await request.send().timeout(ApiConstants.longTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final photoUrl = result['photoUrl'] as String;
          Logger.debug('✅ Эталонное фото загружено: $photoUrl');
          return photoUrl;
        } else {
          Logger.error('❌ Ошибка загрузки эталонного фото: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки эталонного фото', e);
      return null;
    }
  }

  /// Удалить вопрос
  static Future<bool> deleteQuestion(String id) async {
    Logger.debug('📤 Удаление вопроса пересчета: $id');

    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/$id',
    );
  }

  /// Массовая загрузка товаров (ЗАМЕНЯЕТ ВСЕ существующие)
  /// products: [{ barcode, productGroup, productName, grade }]
  static Future<List<RecountQuestion>?> bulkUploadProducts(
    List<Map<String, dynamic>> products,
  ) async {
    try {
      Logger.debug('📤 Массовая загрузка товаров (замена всех): ${products.length} товаров');

      final requestBody = <String, dynamic>{
        'products': products,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/bulk-upload'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(requestBody),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (!contentType.contains('application/json')) {
          Logger.error('❌ Сервер вернул не JSON: ${response.body.substring(0, 200)}');
          return null;
        }

        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final questionsJson = result['questions'] as List<dynamic>;
          final createdProducts = questionsJson
              .map((json) => RecountQuestion.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено товаров: ${createdProducts.length}');
          return createdProducts;
        } else {
          Logger.error('❌ Ошибка массовой загрузки: ${result['error']}');
        }
      } else {
        try {
          final errorBody = jsonDecode(response.body);
          Logger.error('❌ Ошибка API: statusCode=${response.statusCode}, error=${errorBody['error']}');
        } catch (e) {
          Logger.error('❌ Ошибка API: statusCode=${response.statusCode}, body=${response.body.substring(0, 200)}');
        }
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка массовой загрузки товаров', e);
      return null;
    }
  }

  /// Массовое добавление НОВЫХ товаров (только с новыми баркодами)
  /// products: [{ barcode, productGroup, productName, grade }]
  /// Возвращает: { added, skipped, total, products }
  static Future<BulkAddResult?> bulkAddNewProducts(
    List<Map<String, dynamic>> products,
  ) async {
    try {
      Logger.debug('📤 Добавление новых товаров: ${products.length} товаров');

      final requestBody = <String, dynamic>{
        'products': products,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/bulk-add-new'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(requestBody),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (!contentType.contains('application/json')) {
          Logger.error('❌ Сервер вернул не JSON: ${response.body.substring(0, 200)}');
          return null;
        }

        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final questionsJson = result['questions'] as List<dynamic>? ?? [];
          final addedProducts = questionsJson
              .map((json) => RecountQuestion.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Добавлено ${result['added']} товаров, пропущено ${result['skipped']}');
          return BulkAddResult(
            added: result['added'] ?? 0,
            skipped: result['skipped'] ?? 0,
            total: result['total'] ?? 0,
            products: addedProducts,
          );
        } else {
          Logger.error('❌ Ошибка добавления новых: ${result['error']}');
        }
      } else {
        try {
          final errorBody = jsonDecode(response.body);
          Logger.error('❌ Ошибка API: statusCode=${response.statusCode}, error=${errorBody['error']}');
        } catch (e) {
          Logger.error('❌ Ошибка API: statusCode=${response.statusCode}, body=${response.body.substring(0, 200)}');
        }
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка добавления новых товаров', e);
      return null;
    }
  }
}

/// Результат операции bulk-add-new
class BulkAddResult {
  final int added;
  final int skipped;
  final int total;
  final List<RecountQuestion> products;

  BulkAddResult({
    required this.added,
    required this.skipped,
    required this.total,
    required this.products,
  });
}


import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/recount_report_model.dart';
import '../models/recount_answer_model.dart';
import '../models/recount_pivot_model.dart';
import '../../../core/services/photo_upload_service.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/multitenancy_filter_service.dart';
// Условный импорт: по умолчанию stub, на веб - dart:html
import '../../../core/services/html_stub.dart' as html if (dart.library.html) 'dart:html';

// http и dart:convert оставлены для веб-специфичных запросов (dart:html HttpRequest)

/// Результат отправки отчёта пересчёта (аналог ShiftSubmitResult)
class RecountSubmitResult {
  final bool success;
  final String? errorType; // 'TIME_EXPIRED' или другие
  final String? message;
  final RecountReport? report;

  RecountSubmitResult({
    required this.success,
    this.errorType,
    this.message,
    this.report,
  });

  bool get isTimeExpired => errorType == 'TIME_EXPIRED';
}

/// Сервис для работы с пересчетом товаров
class RecountService {
  static const String baseEndpoint = ApiConstants.recountReportsEndpoint;

  /// Создать отчет пересчета
  static Future<bool> createReport(RecountReport report) async {
    try {
      Logger.debug('📤 Создание отчета пересчета...');

      // Загружаем фото на сервер, если есть
      final List<RecountAnswer> answersWithPhotos = [];
      for (var answer in report.answers) {
        if (answer.photoPath != null && answer.photoRequired) {
          try {
            final fileName = 'recount_${report.id}_${report.answers.indexOf(answer)}.jpg';
            final photoUrl = await PhotoUploadService.uploadPhoto(
              answer.photoPath!,
              fileName,
            );

            if (photoUrl != null) {
              answersWithPhotos.add(RecountAnswer(
                question: answer.question,
                grade: answer.grade,
                answer: answer.answer,
                quantity: answer.quantity,
                programBalance: answer.programBalance,
                actualBalance: answer.actualBalance,
                difference: answer.difference,
                photoPath: answer.photoPath,
                photoUrl: photoUrl,
                photoRequired: answer.photoRequired,
              ));
            } else {
              // Если не удалось загрузить, продолжаем без фото
              answersWithPhotos.add(answer);
            }
          } catch (e) {
            Logger.error('⚠️ Ошибка загрузки фото', e);
            // Продолжаем без фото
            answersWithPhotos.add(answer);
          }
        } else {
          answersWithPhotos.add(answer);
        }
      }

      // Создаем отчет с загруженными фото
      final reportWithPhotos = RecountReport(
        id: report.id,
        employeeName: report.employeeName,
        shopAddress: report.shopAddress,
        employeePhone: report.employeePhone,
        startedAt: report.startedAt,
        completedAt: report.completedAt,
        duration: report.duration,
        answers: answersWithPhotos,
      );

      // Отправляем на сервер
      final url = '${ApiConstants.serverUrl}$baseEndpoint';
      final body = reportWithPhotos.toJson();

      Logger.debug('   URL: $url');
      Logger.debug('   Отчет ID: ${report.id}');
      Logger.debug('   Сотрудник: ${report.employeeName}');
      Logger.debug('   Магазин: ${report.shopAddress}');
      Logger.debug('   Длительность: ${report.formattedDuration}');
      Logger.debug('   Ответов: ${report.answers.length}');

      http.Response response;

      if (kIsWeb) {
        // Для веб используем альтернативный способ
        try {
          // ignore: avoid_web_libraries_in_flutter
          final httpRequest = html.HttpRequest();
          httpRequest.open('POST', url, true);
          httpRequest.setRequestHeader('Content-Type', 'application/json');
          httpRequest.setRequestHeader('Accept', 'application/json');

          final completer = Completer<void>();
          httpRequest.onLoad.listen((_) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          });
          httpRequest.onError.listen((error) {
            if (!completer.isCompleted) {
              completer.completeError(error);
            }
          });

          httpRequest.send(jsonEncode(body));
          await completer.future;

          final status = httpRequest.status;
          final responseBody = httpRequest.responseText;

          if (status != null && status >= 200 && status < 300) {
            if (responseBody != null && responseBody.isNotEmpty) {
              final result = jsonDecode(responseBody);
              if (result['success'] == true) {
                Logger.debug('✅ Отчет успешно создан');
                // Отправляем push-уведомление
                await _sendPushNotification(report);
                return true;
              }
            }
          }
          return false;
        } catch (e) {
          Logger.error('⚠️ Ошибка веб-запроса', e);
          // Пробуем обычный способ как fallback
        }
      }

      // Обычный способ для мобильных платформ или fallback для веб
      {
        response = await http.post(
          Uri.parse(url),
          headers: ApiConstants.jsonHeaders,
          body: jsonEncode(body),
        ).timeout(
          ApiConstants.longTimeout,
          onTimeout: () {
            throw Exception('Таймаут при создании отчета');
          },
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final result = jsonDecode(response.body);
          if (result['success'] == true) {
            Logger.debug('✅ Отчет успешно создан');
            // Отправляем push-уведомление
            await _sendPushNotification(report);
            return true;
          }
        }

        Logger.error('❌ Ошибка создания отчета: ${response.statusCode}');
        Logger.error('   Ответ: ${response.body}');
        return false;
      }
    } catch (e) {
      Logger.error('❌ Ошибка создания отчета', e);
      return false;
    }
  }

  /// Отправить отчет пересчёта на сервер с обработкой TIME_EXPIRED
  /// Аналог ShiftReportService.submitReport()
  static Future<RecountSubmitResult> submitReport(RecountReport report) async {
    Logger.debug('📤 Отправка отчета пересчёта: ${report.id}');

    try {
      // Загружаем фото на сервер, если есть
      final List<RecountAnswer> answersWithPhotos = [];
      for (var answer in report.answers) {
        if (answer.photoPath != null && answer.photoRequired) {
          try {
            final fileName = 'recount_${report.id}_${report.answers.indexOf(answer)}.jpg';
            final photoUrl = await PhotoUploadService.uploadPhoto(
              answer.photoPath!,
              fileName,
            );

            if (photoUrl != null) {
              answersWithPhotos.add(RecountAnswer(
                question: answer.question,
                grade: answer.grade,
                answer: answer.answer,
                quantity: answer.quantity,
                programBalance: answer.programBalance,
                actualBalance: answer.actualBalance,
                difference: answer.difference,
                photoPath: answer.photoPath,
                photoUrl: photoUrl,
                photoRequired: answer.photoRequired,
              ));
            } else {
              answersWithPhotos.add(answer);
            }
          } catch (e) {
            Logger.error('⚠️ Ошибка загрузки фото', e);
            answersWithPhotos.add(answer);
          }
        } else {
          answersWithPhotos.add(answer);
        }
      }

      // Создаем отчет с загруженными фото
      final reportWithPhotos = RecountReport(
        id: report.id,
        employeeName: report.employeeName,
        shopAddress: report.shopAddress,
        employeePhone: report.employeePhone,
        startedAt: report.startedAt,
        completedAt: report.completedAt,
        duration: report.duration,
        answers: answersWithPhotos,
        shiftType: report.shiftType,
        submittedAt: DateTime.now(),
      );

      final response = await http
          .post(
            Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
            headers: ApiConstants.jsonHeaders,
            body: jsonEncode(reportWithPhotos.toJson()),
          )
          .timeout(ApiConstants.longTimeout);

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (result['success'] == true) {
          Logger.debug('✅ Отчёт пересчёта успешно отправлен');
          // Отправляем push-уведомление
          await _sendPushNotification(report);
          return RecountSubmitResult(
            success: true,
            report: result['report'] != null
                ? RecountReport.fromJson(result['report'])
                : null,
          );
        }
      }

      // Обработка ошибок
      final errorType = result['error']?.toString();
      final message = result['message']?.toString();

      Logger.warning('⚠️ Ошибка отправки: $errorType - $message');
      return RecountSubmitResult(
        success: false,
        errorType: errorType,
        message: message ?? 'Ошибка сохранения отчёта',
      );
    } catch (e) {
      Logger.error('❌ Ошибка сети при отправке отчёта', e);
      return RecountSubmitResult(
        success: false,
        errorType: 'NETWORK_ERROR',
        message: 'Ошибка сети: $e',
      );
    }
  }

  /// Получить список отчетов
  static Future<List<RecountReport>> getReports({
    String? shopAddress,
    String? employeeName,
    DateTime? date,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (shopAddress != null) queryParams['shop'] = shopAddress;
      if (employeeName != null) queryParams['employee'] = employeeName;
      if (date != null) queryParams['date'] = date.toIso8601String();

      Logger.debug('📥 Загрузка отчетов пересчета...');

      return await BaseHttpService.getList<RecountReport>(
        endpoint: baseEndpoint,
        fromJson: (json) => RecountReport.fromJson(json),
        listKey: 'reports',
        queryParams: queryParams.isNotEmpty ? queryParams : null,
        timeout: ApiConstants.longTimeout,
      );
    } catch (e) {
      Logger.error('❌ Ошибка загрузки отчетов', e);
      return [];
    }
  }

  /// Получить отчеты пересчёта с фильтрацией по мультитенантности
  ///
  /// Developer видит все, Admin видит только свои магазины
  static Future<List<RecountReport>> getReportsForCurrentUser({
    String? shopAddress,
    String? employeeName,
    DateTime? date,
  }) async {
    final reports = await getReports(
      shopAddress: shopAddress,
      employeeName: employeeName,
      date: date,
    );

    return await MultitenancyFilterService.filterByShopAddress(
      reports,
      (report) => report.shopAddress,
    );
  }

  /// Поставить оценку отчету
  static Future<bool> rateReport(String reportId, int rating, String adminName) async {
    try {
      // URL-кодируем reportId для безопасной передачи в URL
      final encodedReportId = Uri.encodeComponent(reportId);

      Logger.debug('📤 Постановка оценки отчету...');
      Logger.debug('   Оценка: $rating');
      Logger.debug('   Админ: $adminName');

      return await BaseHttpService.simplePost(
        endpoint: '$baseEndpoint/$encodedReportId/rating',
        body: {
          'rating': rating,
          'adminName': adminName,
        },
        timeout: ApiConstants.longTimeout,
      );
    } catch (e) {
      Logger.error('❌ Ошибка постановки оценки', e);
      return false;
    }
  }

  /// Отправить push-уведомление о новом отчете
  static Future<void> _sendPushNotification(RecountReport report) async {
    try {
      // Отправляем через сервер (сервер сам отправит всем админам)
      await BaseHttpService.simplePost(
        endpoint: '$baseEndpoint/${report.id}/notify',
        body: {},
        timeout: ApiConstants.shortTimeout,
      );
    } catch (e) {
      Logger.error('⚠️ Ошибка отправки уведомления', e);
      // Не критично, продолжаем
    }
  }

  /// Получить просроченные отчёты пересчёта с сервера
  static Future<List<RecountReport>> getExpiredReports() async {
    try {
      Logger.debug('📥 Загрузка просроченных отчётов пересчёта...');

      return await BaseHttpService.getList<RecountReport>(
        endpoint: '$baseEndpoint/expired',
        fromJson: (json) => RecountReport.fromJson(json),
        listKey: 'reports',
      );
    } catch (e) {
      Logger.error('❌ Ошибка загрузки просроченных пересчётов', e);
      return [];
    }
  }

  /// Получить pivot-таблицу отчётов за указанную дату
  /// Возвращает таблицу: строки = товары, столбцы = магазины, значения = разница (факт - программа)
  static Future<RecountPivotTable> getPivotTableForDate(DateTime date) async {
    try {
      Logger.debug('📊 Загрузка pivot-таблицы за ${date.day}.${date.month}.${date.year}...');

      // Загружаем все отчёты за указанную дату
      final allReports = await getReports(date: date);

      // Фильтруем только завершённые отчёты (review, confirmed, failed)
      // Не берём pending (ещё не пройден) и rejected (отклонён без данных)
      final completedReports = allReports.where((r) {
        final status = r.statusEnum;
        return status == RecountReportStatus.review ||
               status == RecountReportStatus.confirmed ||
               status == RecountReportStatus.failed;
      }).toList();

      Logger.debug('   Найдено отчётов: ${completedReports.length}');

      if (completedReports.isEmpty) {
        return RecountPivotTable.empty(date);
      }

      // Собираем уникальные магазины
      final shopsMap = <String, RecountPivotShop>{};
      for (final report in completedReports) {
        final shopId = report.shopAddress;
        if (!shopsMap.containsKey(shopId)) {
          shopsMap[shopId] = RecountPivotShop(
            shopId: shopId,
            shopName: _extractShopName(shopId),
            shopAddress: shopId,
          );
        }
      }
      final shops = shopsMap.values.toList()
        ..sort((a, b) => a.shopName.compareTo(b.shopName));

      // Собираем данные: Map<productName, Map<shopId, difference>>
      final pivotData = <String, Map<String, int?>>{};
      final productBarcodes = <String, String>{}; // productName -> barcode (если есть)

      for (final report in completedReports) {
        final shopId = report.shopAddress;

        for (final answer in report.answers) {
          final productName = answer.question;

          // Инициализируем строку если нужно
          if (!pivotData.containsKey(productName)) {
            pivotData[productName] = {};
          }

          // Записываем разницу
          // difference: положительная = недостача, отрицательная = излишек
          // Но пользователь хочет видеть (факт - программа), то есть:
          // если lessBy=3, то факт = программа - 3, разница = -3
          // если moreBy=2, то факт = программа + 2, разница = +2
          int? diff;
          if (answer.isMatching) {
            diff = 0; // Сходится = разница 0
          } else if (answer.moreBy != null && answer.moreBy! > 0) {
            diff = answer.moreBy; // Больше на X = +X
          } else if (answer.lessBy != null && answer.lessBy! > 0) {
            diff = -(answer.lessBy!); // Меньше на X = -X
          } else if (answer.difference != null) {
            // Старый формат - инвертируем знак
            diff = -(answer.difference!);
          }

          pivotData[productName]![shopId] = diff;
        }
      }

      // Строим строки таблицы
      final rows = <RecountPivotRow>[];
      final sortedProducts = pivotData.keys.toList()..sort();

      for (final productName in sortedProducts) {
        final shopDifferences = <String, int?>{};

        // Для каждого магазина заполняем значение
        for (final shop in shops) {
          shopDifferences[shop.shopId] = pivotData[productName]?[shop.shopId];
        }

        rows.add(RecountPivotRow(
          productName: productName,
          productBarcode: productBarcodes[productName] ?? '',
          shopDifferences: shopDifferences,
        ));
      }

      Logger.debug('   Товаров: ${rows.length}, Магазинов: ${shops.length}');

      return RecountPivotTable(
        date: date,
        shops: shops,
        rows: rows,
      );
    } catch (e) {
      Logger.error('❌ Ошибка загрузки pivot-таблицы', e);
      return RecountPivotTable.empty(date);
    }
  }

  /// Извлечь короткое название магазина из адреса
  static String _extractShopName(String shopAddress) {
    // Если адрес длинный, берём первые слова
    final parts = shopAddress.split(',');
    if (parts.isNotEmpty) {
      final firstPart = parts.first.trim();
      // Ограничиваем длину
      if (firstPart.length > 20) {
        return '${firstPart.substring(0, 17)}...';
      }
      return firstPart;
    }
    return shopAddress.length > 20
        ? '${shopAddress.substring(0, 17)}...'
        : shopAddress;
  }
}

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/recount_report_model.dart';
import '../models/recount_answer_model.dart';
import '../models/recount_pivot_model.dart';
import '../../../core/services/photo_upload_service.dart';
import '../../../core/services/base_report_service.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
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

  static final _base = BaseReportService<RecountReport>(
    endpoint: baseEndpoint,
    fromJson: (json) => RecountReport.fromJson(json),
    getShopAddress: (r) => r.shopAddress,
    reportType: 'recount',
  );

  /// Создать отчет пересчета
  static Future<bool> createReport(RecountReport report) async {
    try {
      Logger.debug('📤 Создание отчета пересчета...');

      // Загрузка фото пакетами (по 3 одновременно, не перегружая сеть)
      final photoTasks = <int, List<String>>{};
      for (var i = 0; i < report.answers.length; i++) {
        final answer = report.answers[i];
        if (answer.photoPath != null && answer.photoRequired) {
          photoTasks[i] = [answer.photoPath!, 'recount_${report.id}_$i.jpg'];
        }
      }
      final uploadResults = await PhotoUploadService.uploadInBatches(photoTasks);

      // Собираем ответы с результатами загрузок
      final List<RecountAnswer> answersWithPhotos = [];
      for (var i = 0; i < report.answers.length; i++) {
        final answer = report.answers[i];
        if (uploadResults.containsKey(i)) {
          final photoUrl = uploadResults[i];
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
              try {
                final result = jsonDecode(responseBody);
                if (result['success'] == true) {
                  Logger.debug('✅ Отчет успешно создан');
                  // Отправляем push-уведомление
                  await _sendPushNotification(report);
                  return true;
                }
              } catch (parseError) {
                // Сервер ответил, но JSON невалидный — не отправляем повторно
                Logger.error('⚠️ Неверный JSON от сервера (веб)', parseError);
                return false;
              }
            }
          }
          return false;
        } catch (e) {
          Logger.error('⚠️ Ошибка веб-запроса (сетевая)', e);
          // Пробуем обычный способ как fallback — сетевая ошибка до сервера
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

        // Обработка специфических ошибок сервера
        if (response.statusCode == 400) {
          try {
            final errBody = jsonDecode(response.body);
            final errorType = errBody['error']?.toString() ?? '';
            final message = errBody['message']?.toString() ?? '';
            if (errorType == 'PRODUCT_NOT_FOUND') {
              throw Exception('Товар не найден в каталоге: $message\nОбратитесь к администратору.');
            }
            if (errorType == 'TIME_EXPIRED') {
              throw Exception('Время пересчёта истекло. Отчёт не принят.');
            }
            if (message.isNotEmpty) throw Exception(message);
          } catch (parseErr) {
            if (parseErr is Exception) rethrow;
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
      // Загрузка фото пакетами (по 3 одновременно, не перегружая сеть)
      final photoTasks2 = <int, List<String>>{};
      for (var i = 0; i < report.answers.length; i++) {
        final answer = report.answers[i];
        if (answer.photoPath != null && answer.photoRequired) {
          photoTasks2[i] = [answer.photoPath!, 'recount_${report.id}_$i.jpg'];
        }
      }
      final uploadResults2 = await PhotoUploadService.uploadInBatches(photoTasks2);

      final List<RecountAnswer> answersWithPhotos = [];
      for (var i = 0; i < report.answers.length; i++) {
        final answer = report.answers[i];
        if (uploadResults2.containsKey(i)) {
          final photoUrl = uploadResults2[i];
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

      // Проверяем statusCode ДО jsonDecode: если сервер вернул HTML (502/nginx) — не упадём с FormatException
      if (response.statusCode == 200 || response.statusCode == 201) {
        Map<String, dynamic> result;
        try {
          result = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {
          Logger.error('❌ Сервер вернул не-JSON при успешном статусе: ${response.body.substring(0, 200)}');
          return RecountSubmitResult(
            success: false,
            errorType: 'PARSE_ERROR',
            message: 'Некорректный ответ сервера',
          );
        }
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

      // Обработка ошибок — пытаемся распарсить тело, но не падаем если не JSON
      Map<String, dynamic>? errorResult;
      try {
        errorResult = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      final errorType = errorResult?['error']?.toString();
      final message = errorResult?['message']?.toString();

      Logger.warning('⚠️ Ошибка отправки [${response.statusCode}]: $errorType - $message');
      return RecountSubmitResult(
        success: false,
        errorType: errorType ?? 'HTTP_${response.statusCode}',
        message: message ?? 'Ошибка сохранения отчёта (статус ${response.statusCode})',
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
  }) => _base.getReports(
    queryParams: BaseReportService.buildQueryParams({
      'shopAddress': shopAddress,
      'employeeName': employeeName,
      'date': date?.toIso8601String(),
    }),
    timeout: ApiConstants.longTimeout,
  );

  /// Получить отчеты пересчёта с фильтрацией по мультитенантности
  ///
  /// Developer видит все, Admin видит только свои магазины
  static Future<List<RecountReport>> getReportsForCurrentUser({
    String? shopAddress,
    String? employeeName,
    DateTime? date,
  }) => _base.getReportsForCurrentUser(
    queryParams: BaseReportService.buildQueryParams({
      'shopAddress': shopAddress,
      'employeeName': employeeName,
      'date': date?.toIso8601String(),
    }),
    timeout: ApiConstants.longTimeout,
  );

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

  /// Подтвердить отчет пересчёта с оценкой и отправить push сотруднику
  ///
  /// [reportId] - ID отчёта
  /// [rating] - оценка (1-5)
  /// [adminName] - имя админа
  /// [employeePhone] - телефон сотрудника для push
  /// [reportDate] - дата отчёта для отображения в push
  static Future<bool> confirmReportWithPush({
    required String reportId,
    required int rating,
    required String adminName,
    required String employeePhone,
    String? reportDate,
  }) async {
    final success = await rateReport(reportId, rating, adminName);
    if (success) {
      await _base.sendStatusPush(
        employeePhone: employeePhone,
        status: 'confirmed',
        reportDate: reportDate,
        rating: rating,
      );
      Logger.debug('✅ Пересчёт подтверждён и push отправлен');
    }
    return success;
  }

  /// Отклонить отчет пересчёта и отправить push сотруднику
  ///
  /// [reportId] - ID отчёта
  /// [adminName] - имя админа
  /// [employeePhone] - телефон сотрудника для push
  /// [comment] - причина отклонения
  /// [reportDate] - дата отчёта для отображения в push
  static Future<bool> rejectReportWithPush({
    required String reportId,
    required String adminName,
    required String employeePhone,
    String? comment,
    String? reportDate,
  }) async {
    // Для отклонения используем тот же endpoint с rating=0 или отдельный
    final success = await rateReport(reportId, 0, adminName);
    if (success) {
      await _base.sendStatusPush(
        employeePhone: employeePhone,
        status: 'rejected',
        reportDate: reportDate,
        comment: comment,
      );
      Logger.debug('✅ Пересчёт отклонён и push отправлен');
    }
    return success;
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
  static Future<List<RecountReport>> getExpiredReports() => _base.getExpiredReports();

  /// Получить просроченные отчёты с фильтрацией по мультитенантности
  static Future<List<RecountReport>> getExpiredReportsForCurrentUser() => _base.getExpiredReportsForCurrentUser();

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

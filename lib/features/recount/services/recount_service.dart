import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/recount_report_model.dart';
import '../models/recount_answer_model.dart';
import '../../../core/services/photo_upload_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
// Условный импорт: по умолчанию stub, на веб - dart:html
import '../../../core/services/html_stub.dart' as html if (dart.library.html) 'dart:html';

/// Сервис для работы с пересчетом товаров
class RecountService {
  static const String baseEndpoint = '/api/recount-reports';

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

      final uri = Uri.parse('${ApiConstants.serverUrl}$baseEndpoint')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      Logger.debug('📥 Загрузка отчетов пересчета...');
      Logger.debug('   URL: $uri');

      final response = await http.get(uri).timeout(
        ApiConstants.longTimeout,
        onTimeout: () {
          throw Exception('Таймаут при загрузке отчетов');
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final reportsJson = result['reports'] as List<dynamic>;
          final reports = reportsJson
              .map((json) => RecountReport.fromJson(json))
              .toList();
          Logger.debug('✅ Загружено отчетов: ${reports.length}');
          return reports;
        }
      }

      Logger.error('❌ Ошибка загрузки отчетов: ${response.statusCode}');
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка загрузки отчетов', e);
      return [];
    }
  }

  /// Поставить оценку отчету
  static Future<bool> rateReport(String reportId, int rating, String adminName) async {
    try {
      // URL-кодируем reportId для безопасной передачи в URL
      final encodedReportId = Uri.encodeComponent(reportId);
      final url = '${ApiConstants.serverUrl}$baseEndpoint/$encodedReportId/rating';
      final body = {
        'rating': rating,
        'adminName': adminName,
      };

      Logger.debug('📤 Постановка оценки отчету...');
      Logger.debug('   URL: $url');
      Logger.debug('   Оценка: $rating');
      Logger.debug('   Админ: $adminName');

      final response = await http.post(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(body),
      ).timeout(
        ApiConstants.longTimeout,
        onTimeout: () {
          throw Exception('Таймаут при постановке оценки');
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Оценка успешно поставлена');
          return true;
        }
      }

      Logger.error('❌ Ошибка постановки оценки: ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка постановки оценки', e);
      return false;
    }
  }

  /// Отправить push-уведомление о новом отчете
  static Future<void> _sendPushNotification(RecountReport report) async {
    try {
      // Отправляем через сервер (сервер сам отправит всем админам)
      final url = '${ApiConstants.serverUrl}$baseEndpoint/${report.id}/notify';
      await http.post(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.shortTimeout);
    } catch (e) {
      Logger.error('⚠️ Ошибка отправки уведомления', e);
      // Не критично, продолжаем
    }
  }
}

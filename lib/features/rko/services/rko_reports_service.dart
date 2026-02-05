import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/multitenancy_filter_service.dart';
import '../../../core/services/employee_push_service.dart';

// http и dart:convert оставлены для multipart загрузки файлов и binary скачивания

/// Сервис для работы с РКО документами
class RKOReportsService {
  static const String baseEndpoint = '/api/rko';

  /// Загрузить РКО на сервер
  static Future<bool> uploadRKO({
    required File pdfFile,
    required String fileName,
    required String employeeName,
    required String shopAddress,
    required DateTime date,
    required double amount,
    required String rkoType,
  }) async {
    try {
      // Нормализуем дату (убираем время, оставляем только дату)
      final normalizedDate = DateTime(date.year, date.month, date.day);

      Logger.debug('Загрузка РКО на сервер: $fileName');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/upload'),
      );

      // Добавляем файл (.docx)
      // Для веб используем fromBytes, для мобильных fromPath
      if (kIsWeb) {
        // Читаем байты из файла (работает с _MemoryFile)
        final bytes = await pdfFile.readAsBytes();
        request.files.add(
          http.MultipartFile.fromBytes(
            'docx',
            bytes,
            filename: fileName,
          ),
        );
      } else {
        // Для мобильных используем путь к файлу
        request.files.add(
          await http.MultipartFile.fromPath('docx', pdfFile.path),
        );
      }

      // Добавляем метаданные (используем нормализованную дату)
      request.fields['fileName'] = fileName;
      request.fields['employeeName'] = employeeName;
      request.fields['shopAddress'] = shopAddress;
      request.fields['date'] = normalizedDate.toIso8601String();
      request.fields['amount'] = amount.toString();
      request.fields['rkoType'] = rkoType;

      final response = await request.send().timeout(ApiConstants.longTimeout);

      final responseBody = await response.stream.bytesToString();
      final result = jsonDecode(responseBody);

      if (response.statusCode == 200 && result['success'] == true) {
        Logger.debug('РКО успешно загружен на сервер');
        return true;
      } else {
        Logger.error('Ошибка загрузки РКО: ${result['error'] ?? 'Неизвестная ошибка'}');
        return false;
      }
    } catch (e) {
      Logger.error('Ошибка загрузки РКО на сервер', e);
      return false;
    }
  }

  /// Получить список РКО сотрудника
  static Future<Map<String, dynamic>?> getEmployeeRKOs(String employeeName) async {
    try {
      final url = '${ApiConstants.serverUrl}$baseEndpoint/list/employee/${Uri.encodeComponent(employeeName)}';
      final response = await http.get(Uri.parse(url)).timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result;
        }
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка получения списка РКО сотрудника', e);
      return null;
    }
  }

  /// Получить список РКО магазина
  static Future<Map<String, dynamic>?> getShopRKOs(String shopAddress) async {
    try {
      final encodedAddress = Uri.encodeComponent(shopAddress);
      final url = '${ApiConstants.serverUrl}$baseEndpoint/list/shop/$encodedAddress';
      Logger.debug('Запрос РКО для магазина: "$shopAddress"');
      final response = await http.get(Uri.parse(url)).timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result;
        }
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка получения списка РКО магазина', e);
      return null;
    }
  }

  /// Получить URL для просмотра PDF/DOCX
  static String getPDFUrl(String fileName) {
    final encodedFileName = Uri.encodeComponent(fileName);
    return '${ApiConstants.serverUrl}$baseEndpoint/file/$encodedFileName';
  }

  /// Получить список всех сотрудников, у которых есть РКО
  static Future<List<String>> getEmployeesWithRKO() async {
    try {
      return [];
    } catch (e) {
      Logger.error('Ошибка получения списка сотрудников с РКО', e);
      return [];
    }
  }

  /// Получить список pending (ожидающих) РКО
  static Future<List<dynamic>> getPendingRKOs() async {
    try {
      final url = '${ApiConstants.serverUrl}$baseEndpoint/pending';
      Logger.debug('Запрос pending РКО: $url');
      final response = await http.get(Uri.parse(url)).timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('Получено pending РКО: ${result['count']}');
          return result['items'] ?? [];
        }
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка получения pending РКО', e);
      return [];
    }
  }

  /// Получить список failed (не прошедших) РКО
  static Future<List<dynamic>> getFailedRKOs() async {
    try {
      final url = '${ApiConstants.serverUrl}$baseEndpoint/failed';
      Logger.debug('Запрос failed РКО: $url');
      final response = await http.get(Uri.parse(url)).timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('Получено failed РКО: ${result['count']}');
          return result['items'] ?? [];
        }
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка получения failed РКО', e);
      return [];
    }
  }

  /// Получить все РКО за месяц (для эффективности)
  ///
  /// [month] - месяц в формате YYYY-MM (опционально)
  static Future<List<Map<String, dynamic>>> getAllRKOs({String? month}) async {
    try {
      var url = '${ApiConstants.serverUrl}$baseEndpoint/all';
      if (month != null) {
        url += '?month=$month';
      }
      Logger.debug('Запрос всех РКО: $url');
      final response = await http.get(Uri.parse(url)).timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('Получено РКО: ${result['count']}');
          final items = result['items'] as List<dynamic>? ?? [];
          return items.map((item) => item as Map<String, dynamic>).toList();
        }
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка получения всех РКО', e);
      return [];
    }
  }

  /// Получить все РКО с фильтрацией по мультитенантности
  ///
  /// Developer видит все, Admin видит только свои магазины
  static Future<List<Map<String, dynamic>>> getAllRKOsForCurrentUser({String? month}) async {
    final rkos = await getAllRKOs(month: month);

    return await MultitenancyFilterService.filterByShopAddress(
      rkos,
      (rko) => rko['shopAddress']?.toString() ?? '',
    );
  }

  /// Получить pending РКО с фильтрацией по мультитенантности
  static Future<List<dynamic>> getPendingRKOsForCurrentUser() async {
    final rkos = await getPendingRKOs();

    return await MultitenancyFilterService.filterByShopAddress(
      rkos.map((item) => item as Map<String, dynamic>).toList(),
      (rko) => rko['shopAddress']?.toString() ?? '',
    );
  }

  /// Получить failed РКО с фильтрацией по мультитенантности
  static Future<List<dynamic>> getFailedRKOsForCurrentUser() async {
    final rkos = await getFailedRKOs();

    return await MultitenancyFilterService.filterByShopAddress(
      rkos.map((item) => item as Map<String, dynamic>).toList(),
      (rko) => rko['shopAddress']?.toString() ?? '',
    );
  }

  /// Подтвердить РКО с push уведомлением сотруднику
  ///
  /// [reportId] - ID отчёта
  /// [rating] - оценка (1-5)
  /// [adminName] - имя админа, подтвердившего отчёт
  /// [employeePhone] - телефон сотрудника для push
  /// [reportDate] - дата отчёта для отображения в push
  static Future<bool> confirmReportWithPush({
    required String reportId,
    required int rating,
    required String adminName,
    required String employeePhone,
    String? reportDate,
  }) async {
    try {
      final url = '${ApiConstants.serverUrl}$baseEndpoint-reports/$reportId';
      Logger.debug('Подтверждение РКО: $reportId');

      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': 'confirmed',
          'rating': rating,
          'confirmedBy': adminName,
          'confirmedAt': DateTime.now().toIso8601String(),
        }),
      ).timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('РКО подтверждён, отправка push сотруднику');

          // Отправляем push уведомление сотруднику
          await EmployeePushService.sendReportStatusPush(
            employeePhone: employeePhone,
            reportType: 'rko',
            status: 'confirmed',
            reportDate: reportDate,
            rating: rating,
          );

          return true;
        }
      }
      return false;
    } catch (e) {
      Logger.error('Ошибка подтверждения РКО', e);
      return false;
    }
  }

  /// Отклонить РКО с push уведомлением сотруднику
  ///
  /// [reportId] - ID отчёта
  /// [adminName] - имя админа, отклонившего отчёт
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
    try {
      final url = '${ApiConstants.serverUrl}$baseEndpoint-reports/$reportId';
      Logger.debug('Отклонение РКО: $reportId');

      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': 'rejected',
          'rejectedBy': adminName,
          'rejectedAt': DateTime.now().toIso8601String(),
          'rejectReason': comment,
        }),
      ).timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('РКО отклонён, отправка push сотруднику');

          // Отправляем push уведомление сотруднику
          await EmployeePushService.sendReportStatusPush(
            employeePhone: employeePhone,
            reportType: 'rko',
            status: 'rejected',
            reportDate: reportDate,
            comment: comment,
          );

          return true;
        }
      }
      return false;
    } catch (e) {
      Logger.error('Ошибка отклонения РКО', e);
      return false;
    }
  }
}

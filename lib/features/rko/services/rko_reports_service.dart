import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

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
      
      Logger.debug('═══════════════════════════════════════════════════════');
      Logger.debug('📤 ЗАГРУЗКА РКО НА СЕРВЕР');
      Logger.debug('   fileName: $fileName');
      Logger.debug('   employeeName: "$employeeName"');
      Logger.debug('   shopAddress: "$shopAddress"');
      Logger.debug('   date (оригинал): ${date.toIso8601String()}');
      Logger.debug('   date (нормализован): ${normalizedDate.toIso8601String()}');
      Logger.debug('   date (для отображения): ${normalizedDate.year}-${normalizedDate.month.toString().padLeft(2, '0')}-${normalizedDate.day.toString().padLeft(2, '0')}');
      Logger.debug('   amount: $amount');
      Logger.debug('   rkoType: $rkoType');
      Logger.debug('═══════════════════════════════════════════════════════');

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
      
      Logger.debug('📤 Ответ сервера: statusCode=${response.statusCode}');
      Logger.debug('📤 Результат: success=${result['success']}, error=${result['error'] ?? 'нет'}');
      
      if (response.statusCode == 200 && result['success'] == true) {
        Logger.debug('✅ РКО успешно загружен на сервер');
        return true;
      } else {
        Logger.debug('❌ Ошибка загрузки РКО: ${result['error'] ?? 'Неизвестная ошибка'}');
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
      // Используем новый endpoint с query параметром для правильной обработки кириллицы
      final uri = Uri.parse('${ApiConstants.serverUrl}/api/rko/list-by-shop').replace(
        queryParameters: {'shopAddress': shopAddress},
      );
      Logger.debug('📋 Запрос РКО для магазина: "$shopAddress"');
      Logger.debug('📋 URL: $uri');
      final response = await http.get(uri).timeout(ApiConstants.shortTimeout);

      Logger.debug('📋 Ответ API: statusCode=${response.statusCode}');
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final currentMonth = (result['currentMonth'] as List?)?.length ?? 0;
        final totalMonths = (result['months'] as List?)?.length ?? 0;
        Logger.debug('📋 Результат: success=${result['success']}, currentMonth=$currentMonth, totalMonths=$totalMonths');
        if (result['success'] == true) {
          return result;
        } else {
          Logger.debug('⚠️ API вернул success=false: ${result['error'] ?? 'неизвестная ошибка'}');
        }
      } else {
        Logger.debug('⚠️ HTTP статус не 200: ${response.statusCode}, body: ${response.body}');
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка получения списка РКО магазина', e);
      return null;
    }
  }

  /// Получить URL для просмотра PDF/DOCX
  static String getPDFUrl(String fileName) {
    // Используем новый endpoint с query параметром для правильной обработки кириллицы
    final uri = Uri.parse('${ApiConstants.serverUrl}/api/rko/download').replace(
      queryParameters: {'fileName': fileName},
    );
    return uri.toString();
  }

  /// Получить список всех сотрудников, у которых есть РКО
  static Future<List<String>> getEmployeesWithRKO() async {
    try {
      // Получаем всех сотрудников из метаданных
      // Для этого нужно добавить endpoint на сервере или использовать существующий
      // Пока возвращаем пустой список, будет реализовано через endpoint
      return [];
    } catch (e) {
      Logger.error('Ошибка получения списка сотрудников с РКО', e);
      return [];
    }
  }
}




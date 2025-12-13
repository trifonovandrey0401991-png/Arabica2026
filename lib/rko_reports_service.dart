import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'rko_report_model.dart';
import 'utils/logger.dart';

class RKOReportsService {
  static const String serverUrl = 'https://arabica26.ru';

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
      print('📤 Загрузка РКО на сервер: $fileName');
      
      final url = '$serverUrl/api/rko/upload';
      final request = http.MultipartRequest('POST', Uri.parse(url));
      
      // Добавляем файл (.docx)
      request.files.add(
        await http.MultipartFile.fromPath('docx', pdfFile.path),
      );
      
      // Добавляем метаданные
      request.fields['fileName'] = fileName;
      request.fields['employeeName'] = employeeName;
      request.fields['shopAddress'] = shopAddress;
      request.fields['date'] = date.toIso8601String();
      request.fields['amount'] = amount.toString();
      request.fields['rkoType'] = rkoType;
      
      final response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      
      final responseBody = await response.stream.bytesToString();
      final result = jsonDecode(responseBody);
      
      if (response.statusCode == 200 && result['success'] == true) {
        print('✅ РКО успешно загружен на сервер');
        return true;
      } else {
        print('❌ Ошибка загрузки РКО: ${result['error'] ?? 'Неизвестная ошибка'}');
        return false;
      }
    } catch (e) {
      print('❌ Ошибка загрузки РКО на сервер: $e');
      return false;
    }
  }

  /// Получить список РКО сотрудника
  static Future<Map<String, dynamic>?> getEmployeeRKOs(String employeeName) async {
    try {
      final url = '$serverUrl/api/rko/list/employee/${Uri.encodeComponent(employeeName)}';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result;
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка получения списка РКО сотрудника: $e');
      return null;
    }
  }

  /// Получить список РКО магазина
  static Future<Map<String, dynamic>?> getShopRKOs(String shopAddress) async {
    try {
      final url = '$serverUrl/api/rko/list/shop/${Uri.encodeComponent(shopAddress)}';
      Logger.debug('📋 Запрос РКО для магазина: "$shopAddress"');
      Logger.debug('📋 URL: $url');
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      Logger.debug('📋 Ответ API: statusCode=${response.statusCode}');
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        Logger.debug('📋 Результат: success=${result['success']}, items count=${(result['items'] as List?)?.length ?? 0}');
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

  /// Получить URL для просмотра DOCX
  static String getPDFUrl(String fileName) {
    return '$serverUrl/api/rko/file/${Uri.encodeComponent(fileName)}';
  }

  /// Получить список всех сотрудников, у которых есть РКО
  static Future<List<String>> getEmployeesWithRKO() async {
    try {
      // Получаем всех сотрудников из метаданных
      // Для этого нужно добавить endpoint на сервере или использовать существующий
      // Пока возвращаем пустой список, будет реализовано через endpoint
      return [];
    } catch (e) {
      print('❌ Ошибка получения списка сотрудников с РКО: $e');
      return [];
    }
  }
}




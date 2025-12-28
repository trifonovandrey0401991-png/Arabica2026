import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/employee_registration_model.dart';

class EmployeeRegistrationService {
  static const String serverUrl = 'https://arabica26.ru';

  /// Валидация серии паспорта (4 цифры)
  static bool isValidPassportSeries(String series) {
    return RegExp(r'^\d{4}$').hasMatch(series);
  }

  /// Валидация номера паспорта (6 цифр)
  static bool isValidPassportNumber(String number) {
    return RegExp(r'^\d{6}$').hasMatch(number);
  }

  /// Валидация даты в формате ДД.ММ.ГГГГ
  static bool isValidDate(String date) {
    final regex = RegExp(r'^\d{2}\.\d{2}\.\d{4}$');
    if (!regex.hasMatch(date)) return false;

    try {
      final parts = date.split('.');
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      if (month < 1 || month > 12) return false;
      if (day < 1 || day > 31) return false;
      if (year < 1900 || year > DateTime.now().year) return false;

      final dateTime = DateTime(year, month, day);
      // Проверяем, что дата не в будущем
      if (dateTime.isAfter(DateTime.now())) return false;
      // Проверяем, что дата не слишком старая (например, не раньше 1950 года)
      if (dateTime.isBefore(DateTime(1950))) return false;

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Загрузить фото на сервер
  static Future<String?> uploadPhoto(
    String photoPath,
    String phone,
    String photoType, // 'front', 'registration', 'additional'
  ) async {
    try {
      List<int> bytes;
      
      if (kIsWeb) {
        // Для веб - base64
        if (photoPath.startsWith('data:image/')) {
          final base64Index = photoPath.indexOf(',');
          if (base64Index != -1) {
            final base64Image = photoPath.substring(base64Index + 1);
            bytes = base64Decode(base64Image);
          } else {
            return null;
          }
        } else {
          return null;
        }
      } else {
        // Для мобильных - файл
        final file = File(photoPath);
        if (!await file.exists()) {
          print('⚠️ Файл не найден: $photoPath');
          return null;
        }
        bytes = await file.readAsBytes();
      }

      // Нормализуем телефон
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      
      final uri = Uri.parse('$serverUrl/upload-employee-photo');
      final request = http.MultipartRequest('POST', uri);
      
      final fileName = '${normalizedPhone}_$photoType.jpg';
      print('📤 Загрузка фото: $fileName');
      print('   Размер: ${bytes.length} байт');
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );
      request.fields['phone'] = normalizedPhone;
      request.fields['photoType'] = photoType;

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );

      final response = await http.Response.fromStream(streamedResponse);

      print('   Статус ответа: ${response.statusCode}');
      final responseBody = response.body;
      print('   Тело ответа: ${responseBody.length > 200 ? responseBody.substring(0, 200) + "..." : responseBody}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final url = result['url'] as String?;
          print('   ✅ Фото загружено, URL: $url');
          return url;
        } else {
          print('   ❌ Ошибка загрузки: ${result['error']}');
        }
      }

      return null;
    } catch (e) {
      print('❌ Ошибка загрузки фото: $e');
      return null;
    }
  }

  /// Сохранить регистрацию сотрудника
  static Future<bool> saveRegistration(EmployeeRegistration registration) async {
    try {
      // Нормализуем телефон перед сохранением
      final normalizedPhone = registration.phone.replaceAll(RegExp(r'[\s\+]'), '');
      final registrationToSave = registration.copyWith(phone: normalizedPhone);
      
      final url = '$serverUrl/api/employee-registration';
      final jsonData = jsonEncode(registrationToSave.toJson());
      print('💾 Сохранение регистрации для телефона: $normalizedPhone');
      print('   URL: $url');
      print('   Данные: ${jsonData.length > 200 ? jsonData.substring(0, 200) + "..." : jsonData}');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(registrationToSave.toJson()),
      ).timeout(
        const Duration(seconds: 30),
      );

      print('   Статус ответа: ${response.statusCode}');
      final responseBody = response.body;
      print('   Тело ответа: ${responseBody.length > 200 ? responseBody.substring(0, 200) + "..." : responseBody}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final success = result['success'] == true;
        if (success) {
          print('   ✅ Регистрация успешно сохранена');
        } else {
          print('   ❌ Ошибка сохранения: ${result['error']}');
        }
        return success;
      }

      print('   ❌ HTTP ошибка: ${response.statusCode}');
      return false;
    } catch (e) {
      print('❌ Ошибка сохранения регистрации: $e');
      return false;
    }
  }

  /// Получить регистрацию по телефону
  static Future<EmployeeRegistration?> getRegistration(String phone) async {
    try {
      // Нормализуем телефон (убираем пробелы и +)
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      final url = '$serverUrl/api/employee-registration/${Uri.encodeComponent(normalizedPhone)}';
      
      print('🔍 Запрос регистрации для телефона: $normalizedPhone');
      print('   URL: $url');
      
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      print('   Статус ответа: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final resultJson = jsonEncode(result);
        print('   Ответ сервера: ${resultJson.length > 200 ? resultJson.substring(0, 200) + "..." : resultJson}');
        
        if (result['success'] == true && result['registration'] != null) {
          final registration = EmployeeRegistration.fromJson(result['registration']);
          print('   ✅ Регистрация найдена, isVerified: ${registration.isVerified}');
          return registration;
        } else {
          print('   ⚠️ Регистрация не найдена или success=false');
        }
      } else {
        print('   ❌ Ошибка HTTP: ${response.statusCode}');
        print('   Тело ответа: ${response.body.substring(0, 200)}');
      }

      return null;
    } catch (e) {
      print('❌ Ошибка загрузки регистрации: $e');
      return null;
    }
  }

  /// Верифицировать/снять верификацию сотрудника
  static Future<bool> verifyEmployee(
    String phone,
    bool isVerified,
    String adminName,
  ) async {
    try {
      // Нормализуем телефон
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      final url = '$serverUrl/api/employee-registration/${Uri.encodeComponent(normalizedPhone)}/verify';
      
      print('🔐 Верификация сотрудника:');
      print('   Телефон: $normalizedPhone');
      print('   Статус: $isVerified');
      print('   Админ: $adminName');
      print('   URL: $url');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'isVerified': isVerified,
          'verifiedBy': adminName,
        }),
      ).timeout(
        const Duration(seconds: 10),
      );

      print('   Статус ответа: ${response.statusCode}');
      final responseBody = response.body;
      print('   Тело ответа: ${responseBody.length > 200 ? responseBody.substring(0, 200) + "..." : responseBody}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final success = result['success'] == true;
        if (success) {
          print('   ✅ Статус верификации успешно обновлен');
        } else {
          print('   ❌ Ошибка обновления статуса: ${result['error']}');
        }
        return success;
      }

      print('   ❌ HTTP ошибка: ${response.statusCode}');
      return false;
    } catch (e) {
      print('❌ Ошибка верификации сотрудника: $e');
      return false;
    }
  }

  /// Получить список всех регистраций (для админа)
  static Future<List<EmployeeRegistration>> getAllRegistrations() async {
    try {
      final url = '$serverUrl/api/employee-registrations';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final registrationsJson = result['registrations'] as List<dynamic>;
          return registrationsJson
              .map((json) => EmployeeRegistration.fromJson(json))
              .toList();
        }
      }

      return [];
    } catch (e) {
      print('❌ Ошибка загрузки регистраций: $e');
      return [];
    }
  }
}


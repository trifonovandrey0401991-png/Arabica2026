import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/employee_registration_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

// http и dart:convert оставлены для multipart загрузки фото

class EmployeeRegistrationService {

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
      if (dateTime.isAfter(DateTime.now())) return false;
      if (dateTime.isBefore(DateTime(1950))) return false;

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Загрузить фото на сервер (multipart upload)
  static Future<String?> uploadPhoto(
    String photoPath,
    String phone,
    String photoType,
  ) async {
    try {
      List<int> bytes;

      if (kIsWeb) {
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
        final file = File(photoPath);
        if (!await file.exists()) {
          Logger.warning('⚠️ Файл не найден: $photoPath');
          return null;
        }
        bytes = await file.readAsBytes();
      }

      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');

      final uri = Uri.parse('${ApiConstants.serverUrl}/upload-employee-photo');
      final request = http.MultipartRequest('POST', uri);

      final fileName = '${normalizedPhone}_$photoType.jpg';
      Logger.debug('📤 Загрузка фото: $fileName');

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );
      request.fields['phone'] = normalizedPhone;
      request.fields['photoType'] = photoType;

      final streamedResponse = await request.send().timeout(ApiConstants.uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final url = result['url'] as String?;
          Logger.debug('   ✅ Фото загружено, URL: $url');
          return url;
        } else {
          Logger.error('   ❌ Ошибка загрузки: ${result['error']}');
        }
      }

      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки фото', e);
      return null;
    }
  }

  /// Сохранить регистрацию сотрудника
  static Future<bool> saveRegistration(EmployeeRegistration registration) async {
    final normalizedPhone = registration.phone.replaceAll(RegExp(r'[\s\+]'), '');
    final registrationToSave = registration.copyWith(phone: normalizedPhone);

    Logger.debug('💾 Сохранение регистрации для телефона: $normalizedPhone');

    return await BaseHttpService.simplePost(
      endpoint: '/api/employee-registration',
      body: registrationToSave.toJson(),
      timeout: ApiConstants.longTimeout,
    );
  }

  /// Получить регистрацию по телефону
  static Future<EmployeeRegistration?> getRegistration(String phone) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
    Logger.debug('🔍 Запрос регистрации для телефона: $normalizedPhone');

    return await BaseHttpService.get<EmployeeRegistration>(
      endpoint: '/api/employee-registration/${Uri.encodeComponent(normalizedPhone)}',
      fromJson: (json) => EmployeeRegistration.fromJson(json),
      itemKey: 'registration',
      timeout: ApiConstants.shortTimeout,
    );
  }

  /// Верифицировать/снять верификацию сотрудника
  static Future<bool> verifyEmployee(
    String phone,
    bool isVerified,
    String adminName,
  ) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
    Logger.debug('🔐 Верификация сотрудника: $normalizedPhone, статус: $isVerified');

    return await BaseHttpService.simplePost(
      endpoint: '/api/employee-registration/${Uri.encodeComponent(normalizedPhone)}/verify',
      body: {
        'isVerified': isVerified,
        'verifiedBy': adminName,
      },
      timeout: ApiConstants.shortTimeout,
    );
  }

  /// Получить список всех регистраций (для админа)
  static Future<List<EmployeeRegistration>> getAllRegistrations() async {
    return await BaseHttpService.getList<EmployeeRegistration>(
      endpoint: '/api/employee-registrations',
      fromJson: (json) => EmployeeRegistration.fromJson(json),
      listKey: 'registrations',
      timeout: ApiConstants.longTimeout,
    );
  }
}


import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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

  /// Результат загрузки фото с детальной ошибкой
  static String? _lastUploadError;
  static String? get lastUploadError => _lastUploadError;

  /// Загрузить фото из байтов (более надежно для Android content:// URI)
  static Future<String?> uploadPhotoFromBytes(
    Uint8List bytes,
    String phone,
    String photoType,
  ) async {
    _lastUploadError = null;

    try {
      Logger.debug('📤 Загрузка фото из байтов: type=$photoType, phone=${Logger.maskPhone(phone)}, размер=${bytes.length}');

      if (bytes.isEmpty) {
        _lastUploadError = 'Файл пустой (0 байт)';
        Logger.warning('⚠️ $_lastUploadError');
        return null;
      }

      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      if (normalizedPhone.isEmpty) {
        _lastUploadError = 'Некорректный номер телефона';
        return null;
      }
      final uri = Uri.parse('${ApiConstants.serverUrl}/upload-employee-photo');
      Logger.debug('   URI: $uri');

      final request = http.MultipartRequest('POST', uri);

      // Добавляем заголовки авторизации
      if (ApiConstants.apiKey != null && ApiConstants.apiKey!.isNotEmpty) {
        request.headers['X-API-Key'] = ApiConstants.apiKey!;
      }
      if (ApiConstants.sessionToken != null && ApiConstants.sessionToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${ApiConstants.sessionToken}';
      }

      final fileName = '${normalizedPhone}_$photoType.jpg';
      Logger.debug('📤 Загрузка фото: $fileName (${bytes.length} байт)');

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );
      request.fields['phone'] = normalizedPhone;
      request.fields['photoType'] = photoType;

      Logger.debug('   Отправка запроса...');

      try {
        final streamedResponse = await request.send().timeout(ApiConstants.uploadTimeout);
        final response = await http.Response.fromStream(streamedResponse);

        Logger.debug('   Статус ответа: ${response.statusCode}');

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          if (result['success'] == true) {
            final url = result['url'] as String?;
            Logger.debug('   ✅ Фото загружено, URL: $url');
            return url;
          } else {
            _lastUploadError = 'Сервер вернул ошибку: ${result['error']}';
            Logger.error('   ❌ $_lastUploadError');
          }
        } else {
          _lastUploadError = 'HTTP ${response.statusCode}: ${response.body}';
          Logger.error('   ❌ $_lastUploadError');
        }
      } catch (networkError) {
        _lastUploadError = 'Сетевая ошибка: $networkError';
        Logger.error('❌ $_lastUploadError');
      }

      return null;
    } catch (e, stackTrace) {
      _lastUploadError = 'Неожиданная ошибка: $e';
      Logger.error('❌ Ошибка загрузки фото: $e');
      Logger.debug('   Stack trace: $stackTrace');
      return null;
    }
  }

  /// Загрузить фото на сервер (multipart upload)
  static Future<String?> uploadPhoto(
    String photoPath,
    String phone,
    String photoType,
  ) async {
    _lastUploadError = null;

    try {
      Logger.debug('📤 Начало загрузки фото: type=$photoType, phone=${Logger.maskPhone(phone)}');
      Logger.debug('   Путь к файлу: $photoPath');

      List<int> bytes;

      if (kIsWeb) {
        if (photoPath.startsWith('data:image/')) {
          final base64Index = photoPath.indexOf(',');
          if (base64Index != -1) {
            final base64Image = photoPath.substring(base64Index + 1);
            bytes = base64Decode(base64Image);
          } else {
            _lastUploadError = 'Web: неверный формат base64 изображения';
            return null;
          }
        } else {
          _lastUploadError = 'Web: путь не является base64 изображением';
          return null;
        }
      } else {
        final file = File(photoPath);
        Logger.debug('   Проверка существования файла...');

        final exists = await file.exists();
        Logger.debug('   Файл существует: $exists');

        if (!exists) {
          _lastUploadError = 'Файл не найден: $photoPath';
          Logger.warning('⚠️ $_lastUploadError');
          return null;
        }

        try {
          bytes = await file.readAsBytes();
          Logger.debug('   Файл прочитан, размер: ${bytes.length} байт');
        } catch (readError) {
          _lastUploadError = 'Ошибка чтения файла: $readError';
          Logger.error('❌ $_lastUploadError');
          return null;
        }

        if (bytes.isEmpty) {
          _lastUploadError = 'Файл пустой (0 байт)';
          Logger.warning('⚠️ $_lastUploadError');
          return null;
        }
      }

      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      if (normalizedPhone.isEmpty) {
        _lastUploadError = 'Некорректный номер телефона';
        return null;
      }

      final uri = Uri.parse('${ApiConstants.serverUrl}/upload-employee-photo');
      Logger.debug('   URI: $uri');

      final request = http.MultipartRequest('POST', uri);

      // Добавляем заголовки авторизации
      if (ApiConstants.apiKey != null && ApiConstants.apiKey!.isNotEmpty) {
        request.headers['X-API-Key'] = ApiConstants.apiKey!;
      }
      if (ApiConstants.sessionToken != null && ApiConstants.sessionToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${ApiConstants.sessionToken}';
      }

      final fileName = '${normalizedPhone}_$photoType.jpg';
      Logger.debug('📤 Загрузка фото: $fileName (${bytes.length} байт)');

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );
      request.fields['phone'] = normalizedPhone;
      request.fields['photoType'] = photoType;

      Logger.debug('   Отправка запроса на ${uri.toString()}...');

      try {
        final streamedResponse = await request.send().timeout(ApiConstants.uploadTimeout);
        final response = await http.Response.fromStream(streamedResponse);

        Logger.debug('   Статус ответа: ${response.statusCode}');

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          if (result['success'] == true) {
            final url = result['url'] as String?;
            Logger.debug('   ✅ Фото загружено, URL: $url');
            return url;
          } else {
            _lastUploadError = 'Сервер вернул ошибку: ${result['error']}';
            Logger.error('   ❌ $_lastUploadError');
          }
        } else {
          _lastUploadError = 'HTTP ${response.statusCode}: ${response.body}';
          Logger.error('   ❌ $_lastUploadError');
        }
      } catch (networkError) {
        _lastUploadError = 'Сетевая ошибка: $networkError';
        Logger.error('❌ $_lastUploadError');
      }

      return null;
    } catch (e, stackTrace) {
      _lastUploadError = 'Неожиданная ошибка: $e';
      Logger.error('❌ Ошибка загрузки фото: $e');
      Logger.debug('   Stack trace: $stackTrace');
      return null;
    }
  }

  /// Сохранить регистрацию сотрудника
  static Future<bool> saveRegistration(EmployeeRegistration registration) async {
    final normalizedPhone = registration.phone.replaceAll(RegExp(r'[\s\+]'), '');
    if (normalizedPhone.isEmpty) return false;
    final registrationToSave = registration.copyWith(phone: normalizedPhone);

    Logger.debug('💾 Сохранение регистрации для телефона: ${Logger.maskPhone(normalizedPhone)}');

    return await BaseHttpService.simplePost(
      endpoint: '/api/employee-registration',
      body: registrationToSave.toJson(),
      timeout: ApiConstants.longTimeout,
    );
  }

  /// Получить регистрацию по телефону
  static Future<EmployeeRegistration?> getRegistration(String phone) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
    if (normalizedPhone.isEmpty) return null;
    Logger.debug('🔍 Запрос регистрации для телефона: ${Logger.maskPhone(normalizedPhone)}');

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
    if (normalizedPhone.isEmpty) return false;
    Logger.debug('🔐 Верификация сотрудника: ${Logger.maskPhone(normalizedPhone)}, статус: $isVerified');

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


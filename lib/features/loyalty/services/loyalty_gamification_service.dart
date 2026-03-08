import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/loyalty_gamification_model.dart';
import 'loyalty_storage.dart';

/// Выбрасывается когда у клиента есть невыданный приз и нельзя крутить снова
class PendingPrizeException implements Exception {
  const PendingPrizeException();
}

/// Сервис для работы с геймификацией программы лояльности
class LoyaltyGamificationService {
  /// Кэш настроек геймификации
  static GamificationSettings? _cachedSettings;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 5);

  /// Очистить кэш настроек
  static void clearSettingsCache() {
    _cachedSettings = null;
    _cacheTime = null;
  }

  /// Загрузить настройки геймификации
  static Future<GamificationSettings> fetchSettings() async {
    // Проверяем кэш
    if (_cachedSettings != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _cachedSettings!;
      }
    }

    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/loyalty-gamification/settings',
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        final settingsJson = result['settings'] ?? {};
        _cachedSettings = GamificationSettings.fromJson(settingsJson);
        _cacheTime = DateTime.now();
        // Persist to SharedPreferences for instant load on next app open
        await LoyaltyStorage.saveGamificationSettings(Map<String, dynamic>.from(settingsJson));
        Logger.debug('✅ Настройки геймификации загружены: ${_cachedSettings!.levels.length} уровней');
        return _cachedSettings!;
      }

      return _getDefaultSettings();
    } catch (e) {
      Logger.error('Ошибка загрузки настроек геймификации', e);
      return _getDefaultSettings();
    }
  }

  /// Сохранить настройки геймификации (только для админа)
  static Future<bool> saveSettings({
    required GamificationSettings settings,
    required String employeePhone,
  }) async {
    try {
      final normalizedPhone = employeePhone.replaceAll(RegExp(r'[\s\+]'), '');
      // Сервер ожидает levels и wheel напрямую, не вложенные в settings
      final settingsJson = settings.toJson();
      final success = await BaseHttpService.simplePost(
        endpoint: '/api/loyalty-gamification/settings',
        body: {
          'levels': settingsJson['levels'],
          'wheel': settingsJson['wheel'],
          'employeePhone': normalizedPhone,
        },
      );

      if (success) {
        clearSettingsCache();
        Logger.debug('✅ Настройки геймификации сохранены');
      }
      return success;
    } catch (e) {
      Logger.error('Ошибка сохранения настроек геймификации', e);
      return false;
    }
  }

  /// Загрузить данные геймификации клиента
  static Future<ClientGamificationData?> fetchClientData(String phone) async {
    try {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/loyalty-gamification/client/$normalizedPhone',
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        final settings = await fetchSettings();
        final clientJson = Map<String, dynamic>.from(result['client'] ?? result);
        // Persist to SharedPreferences for instant load on next app open
        await LoyaltyStorage.saveClientGamificationData(normalizedPhone, clientJson);
        return ClientGamificationData.fromJson(clientJson, settings);
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка загрузки данных геймификации клиента', e);
      return null;
    }
  }

  /// Крутить колесо удачи
  static Future<WheelSpinResult?> spinWheel(String phone) async {
    try {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      final result = await BaseHttpService.postRaw(
        endpoint: '/api/loyalty-gamification/spin',
        body: {'phone': normalizedPhone},
        timeout: ApiConstants.longTimeout,
      );

      if (result != null && result['success'] == true && result['spin'] != null) {
        Logger.debug('🎡 Колесо прокручено: ${result['spin']['prize']}');
        return WheelSpinResult.fromJson(result['spin']);
      }
      if (result != null && result['hasPendingPrize'] == true) {
        throw const PendingPrizeException();
      }
      return null;
    } catch (e) {
      if (e is PendingPrizeException) rethrow;
      Logger.error('Ошибка прокрутки колеса', e);
      return null;
    }
  }

  /// Получить историю прокруток колеса
  static Future<List<WheelSpinResult>> fetchWheelHistory({
    String? phone,
    int limit = 50,
  }) async {
    try {
      String endpoint = '/api/loyalty-gamification/wheel-history?limit=$limit';
      if (phone != null) {
        final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
        endpoint += '&phone=$normalizedPhone';
      }

      final result = await BaseHttpService.getRaw(
        endpoint: endpoint,
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        final history = (result['history'] as List<dynamic>?)
            ?.map((h) => WheelSpinResult.fromJson(h))
            .toList() ?? [];
        return history;
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка загрузки истории колеса', e);
      return [];
    }
  }

  /// Загрузить картинку значка
  static Future<String?> uploadBadgeImage(File imageFile, int levelId) async {
    try {
      if (!await imageFile.exists()) {
        Logger.debug('Файл не найден: ${imageFile.path}');
        return null;
      }

      final bytes = await imageFile.readAsBytes();
      final extension = imageFile.path.split('.').last.toLowerCase();
      final fileName = 'badge_${levelId}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      // Определяем MIME-тип по расширению
      String mimeType = 'image/jpeg';
      if (extension == 'png') {
        mimeType = 'image/png';
      } else if (extension == 'gif') {
        mimeType = 'image/gif';
      } else if (extension == 'webp') {
        mimeType = 'image/webp';
      }

      Logger.debug('📤 Загружаем значок: $fileName (тип: $mimeType)');

      final uri = Uri.parse('${ApiConstants.serverUrl}/api/loyalty-gamification/upload-badge');
      final request = http.MultipartRequest('POST', uri);

      // Добавляем заголовки авторизации
      if (ApiConstants.apiKey != null && ApiConstants.apiKey!.isNotEmpty) {
        request.headers['X-API-Key'] = ApiConstants.apiKey!;
      }
      if (ApiConstants.sessionToken != null && ApiConstants.sessionToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${ApiConstants.sessionToken}';
      }

      // Передаём телефон админа для проверки прав на сервере
      final prefs = await SharedPreferences.getInstance();
      final adminPhone = prefs.getString('user_phone') ?? '';
      request.fields['employeePhone'] = adminPhone.replaceAll(RegExp(r'[\s\+]'), '');

      request.files.add(
        http.MultipartFile.fromBytes(
          'badge',
          bytes,
          filename: fileName,
          contentType: MediaType.parse(mimeType),
        ),
      );
      request.fields['levelId'] = levelId.toString();

      final streamedResponse = await request.send().timeout(
        ApiConstants.uploadTimeout,
        onTimeout: () {
          throw Exception('Таймаут при загрузке значка');
        },
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['url'] != null) {
          Logger.debug('✅ Картинка значка загружена: ${result['url']}');
          return result['url'];
        }
      }

      Logger.debug('⚠️ Ошибка загрузки значка: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('Ошибка загрузки картинки значка', e);
      return null;
    }
  }

  // ========== CLIENT PRIZES (Призы клиентов) ==========

  /// Получить pending приз клиента
  static Future<ClientPrize?> fetchPendingPrize(String phone) async {
    try {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/loyalty-gamification/client/$normalizedPhone/pending-prize',
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true && result['hasPendingPrize'] == true) {
        final prizeJson = Map<String, dynamic>.from(result['prize']);
        await LoyaltyStorage.saveClientPrize(normalizedPhone, prizeJson);
        return ClientPrize.fromJson(prizeJson);
      }
      // No prize — clear cached prize
      await LoyaltyStorage.saveClientPrize(normalizedPhone, null);
      return null;
    } catch (e) {
      Logger.error('Ошибка загрузки pending приза', e);
      return null;
    }
  }

  /// Сгенерировать новый QR-токен для приза
  static Future<String?> generateNewQrToken(String prizeId) async {
    try {
      final result = await BaseHttpService.postRaw(
        endpoint: '/api/loyalty-gamification/generate-qr',
        body: {'prizeId': prizeId},
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        return result['qrToken'];
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка генерации QR', e);
      return null;
    }
  }

  /// Сканировать QR-код приза (для сотрудников)
  static Future<Map<String, dynamic>?> scanPrizeQr(String qrToken) async {
    try {
      final result = await BaseHttpService.postRaw(
        endpoint: '/api/loyalty-gamification/scan-prize',
        body: {'qrToken': qrToken},
        timeout: ApiConstants.defaultTimeout,
      );

      return result;
    } catch (e) {
      Logger.error('Ошибка сканирования QR приза', e);
      return null;
    }
  }

  /// Выдать приз клиенту
  static Future<bool> issuePrize({
    required String prizeId,
    required String employeePhone,
    required String employeeName,
  }) async {
    try {
      final success = await BaseHttpService.simplePost(
        endpoint: '/api/loyalty-gamification/issue-prize',
        body: {
          'prizeId': prizeId,
          'employeePhone': employeePhone.replaceAll(RegExp(r'[\s\+]'), ''),
          'employeeName': employeeName,
        },
      );

      if (success) {
        Logger.debug('✅ Приз выдан: $prizeId');
      }
      return success;
    } catch (e) {
      Logger.error('Ошибка выдачи приза', e);
      return false;
    }
  }

  /// Отложить приз (сгенерировать новый QR)
  static Future<String?> postponePrize(String prizeId) async {
    try {
      final result = await BaseHttpService.postRaw(
        endpoint: '/api/loyalty-gamification/postpone-prize',
        body: {'prizeId': prizeId},
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        Logger.debug('⏸️ Приз отложен: $prizeId');
        return result['qrToken'];
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка отложения приза', e);
      return null;
    }
  }

  /// Получить отчёт по призам клиентов
  static Future<List<ClientPrize>> fetchClientPrizesReport({
    String? status,
    String? month,
    int limit = 100,
  }) async {
    try {
      String endpoint = '/api/loyalty-gamification/client-prizes-report?limit=$limit';
      if (status != null) {
        endpoint += '&status=$status';
      }
      if (month != null) {
        endpoint += '&month=$month';
      }

      final result = await BaseHttpService.getRaw(
        endpoint: endpoint,
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        final prizes = (result['prizes'] as List<dynamic>?)
            ?.map((p) => ClientPrize.fromJson(p))
            .toList() ?? [];
        return prizes;
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка загрузки отчёта по призам клиентов', e);
      return [];
    }
  }

  /// Настройки по умолчанию
  static GamificationSettings _getDefaultSettings() {
    return GamificationSettings(
      levels: [
        const LoyaltyLevel(
          id: 1,
          name: 'Новичок',
          minFreeDrinks: 0,
          badge: LevelBadge(type: 'icon', value: 'coffee'),
          colorHex: '#78909C',
        ),
        const LoyaltyLevel(
          id: 2,
          name: 'Любитель',
          minFreeDrinks: 2,
          badge: LevelBadge(type: 'icon', value: 'favorite'),
          colorHex: '#4CAF50',
        ),
        const LoyaltyLevel(
          id: 3,
          name: 'Ценитель',
          minFreeDrinks: 5,
          badge: LevelBadge(type: 'icon', value: 'star'),
          colorHex: '#2196F3',
        ),
        const LoyaltyLevel(
          id: 4,
          name: 'Знаток',
          minFreeDrinks: 10,
          badge: LevelBadge(type: 'icon', value: 'workspace_premium'),
          colorHex: '#9C27B0',
        ),
        const LoyaltyLevel(
          id: 5,
          name: 'Гурман',
          minFreeDrinks: 20,
          badge: LevelBadge(type: 'icon', value: 'military_tech'),
          colorHex: '#FF9800',
        ),
        const LoyaltyLevel(
          id: 6,
          name: 'Эксперт',
          minFreeDrinks: 35,
          badge: LevelBadge(type: 'icon', value: 'emoji_events'),
          colorHex: '#F44336',
        ),
        const LoyaltyLevel(
          id: 7,
          name: 'Мастер',
          minFreeDrinks: 50,
          badge: LevelBadge(type: 'icon', value: 'diamond'),
          colorHex: '#00BCD4',
        ),
        const LoyaltyLevel(
          id: 8,
          name: 'Легенда',
          minFreeDrinks: 75,
          badge: LevelBadge(type: 'icon', value: 'verified'),
          colorHex: '#E91E63',
        ),
        const LoyaltyLevel(
          id: 9,
          name: 'Чемпион',
          minFreeDrinks: 100,
          badge: LevelBadge(type: 'icon', value: 'whatshot'),
          colorHex: '#FF5722',
        ),
        const LoyaltyLevel(
          id: 10,
          name: 'Император',
          minFreeDrinks: 150,
          badge: LevelBadge(type: 'icon', value: 'auto_awesome'),
          colorHex: '#FFD700',
        ),
      ],
      wheel: WheelSettings(
        enabled: true,
        freeDrinksPerSpin: 5,
        pointsPerSpin: 50,
        sectors: [
          const WheelSector(index: 0, text: '+5 баллов', probability: 0.25, colorHex: '#4CAF50', prizeType: 'bonus_points', prizeValue: 5),
          const WheelSector(index: 1, text: 'Скидка 10%', probability: 0.20, colorHex: '#2196F3', prizeType: 'discount', prizeValue: 10),
          const WheelSector(index: 2, text: '+10 баллов', probability: 0.15, colorHex: '#FF9800', prizeType: 'bonus_points', prizeValue: 10),
          const WheelSector(index: 3, text: 'Скидка 15%', probability: 0.10, colorHex: '#9C27B0', prizeType: 'discount', prizeValue: 15),
          const WheelSector(index: 4, text: '+1 напиток', probability: 0.05, colorHex: '#F44336', prizeType: 'free_drink', prizeValue: 1),
          const WheelSector(index: 5, text: '+3 балла', probability: 0.25, colorHex: '#795548', prizeType: 'bonus_points', prizeValue: 3),
        ],
      ),
    );
  }
}

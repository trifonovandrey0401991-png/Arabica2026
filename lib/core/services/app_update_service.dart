import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/api_constants.dart';
import '../utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Информация о версии приложения с сервера
class AppVersionInfo {
  final String latestVersion;
  final int latestVersionCode;
  final String minVersion;
  final int minVersionCode;
  final bool forceUpdate;
  final String updateMessage;
  final String playStoreUrl;

  AppVersionInfo({
    required this.latestVersion,
    required this.latestVersionCode,
    required this.minVersion,
    required this.minVersionCode,
    required this.forceUpdate,
    required this.updateMessage,
    required this.playStoreUrl,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      latestVersion: json['latestVersion'] ?? '1.0.0',
      latestVersionCode: json['latestVersionCode'] ?? 1,
      minVersion: json['minVersion'] ?? '1.0.0',
      minVersionCode: json['minVersionCode'] ?? 1,
      forceUpdate: json['forceUpdate'] ?? false,
      updateMessage: json['updateMessage'] ?? 'Доступна новая версия приложения',
      playStoreUrl: json['playStoreUrl'] ?? '',
    );
  }
}

/// Сервис для проверки и установки обновлений приложения
class AppUpdateService {
  static AppUpdateInfo? _updateInfo;
  static bool _isUpdateAvailable = false;
  static AppVersionInfo? _serverVersionInfo;

  /// Проверить, доступно ли обновление (для badge в UI)
  static bool get isUpdateAvailable => _isUpdateAvailable;

  /// Получить информацию о версии с сервера
  static AppVersionInfo? get serverVersionInfo => _serverVersionInfo;

  /// Проверить наличие обновлений (без показа диалогов) и вернуть результат
  static Future<bool> checkUpdateAvailability() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      // Получаем текущую версию
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 1;

      // Проверяем версию на сервере
      _serverVersionInfo = await _fetchServerVersionInfo();

      if (_serverVersionInfo != null) {
        // Есть обновление на сервере?
        if (currentVersionCode < _serverVersionInfo!.latestVersionCode) {
          _isUpdateAvailable = true;
          return true;
        }
      }

      // Проверяем Play Store
      try {
        _updateInfo = await InAppUpdate.checkForUpdate();
        if (_updateInfo?.updateAvailability == UpdateAvailability.updateAvailable) {
          _isUpdateAvailable = true;
          return true;
        }
      } catch (e) {
        Logger.debug('Play Store check failed: $e');
      }

      _isUpdateAvailable = false;
      return false;
    } catch (e) {
      Logger.warning('Ошибка проверки обновлений: $e');
      return false;
    }
  }

  /// Запустить обновление вручную (для кнопки в UI)
  static Future<void> performUpdate(BuildContext context) async {
    if (!Platform.isAndroid) return;

    try {
      // Если есть принудительное обновление
      if (_serverVersionInfo != null && _serverVersionInfo!.forceUpdate) {
        if (context.mounted) {
          await _showForceUpdateDialog(context, _serverVersionInfo!);
        }
        return;
      }

      // Пробуем Immediate Update
      if (_updateInfo?.immediateUpdateAllowed ?? false) {
        await _performImmediateUpdate();
        return;
      }

      // Пробуем Flexible Update
      if (_updateInfo?.flexibleUpdateAllowed ?? false) {
        await _performFlexibleUpdate(context);
        return;
      }

      // Если ничего не сработало, открываем Play Store
      if (_serverVersionInfo?.playStoreUrl.isNotEmpty ?? false) {
        final uri = Uri.parse(_serverVersionInfo!.playStoreUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      Logger.error('Ошибка установки обновления', e);
    }
  }

  /// Проверить наличие обновлений при запуске приложения
  static Future<void> checkForUpdate(BuildContext context) async {
    // In-App Update работает только на Android
    if (!Platform.isAndroid) {
      Logger.debug('In-App Update доступен только на Android');
      return;
    }

    try {
      Logger.debug('🔄 Проверка обновлений приложения...');

      // 1. Получаем текущую версию приложения
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 1;
      Logger.debug('Текущая версия: ${packageInfo.version} (code: $currentVersionCode)');

      // 2. Проверяем минимальную версию на сервере
      _serverVersionInfo = await _fetchServerVersionInfo();

      if (_serverVersionInfo != null) {
        Logger.debug('Версия с сервера: min=${_serverVersionInfo!.minVersionCode}, force=${_serverVersionInfo!.forceUpdate}');

        // Обновляем флаг доступности
        if (currentVersionCode < _serverVersionInfo!.latestVersionCode) {
          _isUpdateAvailable = true;
        }

        // Если текущая версия < минимальной или forceUpdate = true
        if (currentVersionCode < _serverVersionInfo!.minVersionCode || _serverVersionInfo!.forceUpdate) {
          Logger.warning('⚠️ Требуется обязательное обновление!');
          if (context.mounted) {
            await _showForceUpdateDialog(context, _serverVersionInfo!);
          }
          return;
        }
      }

      // 3. Проверяем Play Store через in_app_update
      await _checkPlayStoreUpdate(context);

    } catch (e) {
      Logger.warning('Ошибка проверки обновлений: $e');
      // Не блокируем работу приложения при ошибке
    }
  }

  /// Получить информацию о версии с сервера
  static Future<AppVersionInfo?> _fetchServerVersionInfo() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/app-version'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AppVersionInfo.fromJson(data);
      }
      return null;
    } catch (e) {
      Logger.warning('Не удалось получить версию с сервера: $e');
      return null;
    }
  }

  /// Проверить обновления в Play Store
  static Future<void> _checkPlayStoreUpdate(BuildContext context) async {
    try {
      // Проверяем доступность обновления
      _updateInfo = await InAppUpdate.checkForUpdate();

      Logger.debug('Play Store: available=${_updateInfo?.updateAvailability}, '
          'immediate=${_updateInfo?.immediateUpdateAllowed}, '
          'flexible=${_updateInfo?.flexibleUpdateAllowed}');

      if (_updateInfo?.updateAvailability == UpdateAvailability.updateAvailable) {
        // Если обновление доступно, запускаем Flexible Update
        if (_updateInfo?.flexibleUpdateAllowed ?? false) {
          Logger.info('🔄 Запуск фонового обновления...');
          await _performFlexibleUpdate(context);
        } else if (_updateInfo?.immediateUpdateAllowed ?? false) {
          Logger.info('🔄 Запуск немедленного обновления...');
          await _performImmediateUpdate();
        }
      } else {
        Logger.debug('✅ Приложение актуально');
      }
    } catch (e) {
      Logger.warning('Ошибка проверки Play Store: $e');
    }
  }

  /// Немедленное обновление (блокирует приложение)
  static Future<void> _performImmediateUpdate() async {
    try {
      await InAppUpdate.performImmediateUpdate();
    } catch (e) {
      Logger.error('Ошибка немедленного обновления', e);
    }
  }

  /// Фоновое обновление (не блокирует)
  static Future<void> _performFlexibleUpdate(BuildContext context) async {
    try {
      // Запускаем скачивание в фоне
      await InAppUpdate.startFlexibleUpdate();

      // Слушаем статус скачивания
      InAppUpdate.installUpdateListener.listen((status) {
        if (status == InstallStatus.downloaded) {
          // Обновление скачано, показываем snackbar
          if (context.mounted) {
            _showUpdateDownloadedSnackbar(context);
          }
        }
      });
    } catch (e) {
      Logger.warning('Ошибка фонового обновления: $e');
    }
  }

  /// Показать snackbar о скачанном обновлении
  static void _showUpdateDownloadedSnackbar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Обновление загружено'),
        duration: Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Установить',
          onPressed: () async {
            try {
              await InAppUpdate.completeFlexibleUpdate();
            } catch (e) {
              Logger.error('Ошибка установки обновления', e);
            }
          },
        ),
      ),
    );
  }

  /// Показать диалог принудительного обновления
  static Future<void> _showForceUpdateDialog(BuildContext context, AppVersionInfo versionInfo) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false, // Запрещаем закрытие кнопкой "Назад"
        child: AlertDialog(
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  Icons.system_update,
                  color: AppColors.primaryGreen,
                  size: 28,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Требуется обновление',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                versionInfo.updateMessage,
                style: TextStyle(fontSize: 15.sp),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Для продолжения работы необходимо обновить приложение',
                        style: TextStyle(fontSize: 13.sp),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  // Сначала пробуем In-App Update
                  try {
                    if (_updateInfo?.immediateUpdateAllowed ?? false) {
                      await InAppUpdate.performImmediateUpdate();
                      return;
                    }
                  } catch (e) {
                    Logger.warning('In-App Update не сработал: $e');
                  }

                  // Если не сработало, открываем Play Store
                  if (versionInfo.playStoreUrl.isNotEmpty) {
                    final uri = Uri.parse(versionInfo.playStoreUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                },
                icon: Icon(Icons.download),
                label: Text('Обновить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Завершить установку обновления (вызывается при возобновлении приложения)
  static Future<void> completeUpdateIfDownloaded() async {
    if (!Platform.isAndroid) return;

    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.installStatus == InstallStatus.downloaded) {
        await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (e) {
      Logger.warning('Ошибка завершения обновления: $e');
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/logger.dart';

/// Permission onboarding page shown after login/registration.
/// Requests geolocation, contacts, microphone and camera permissions sequentially.
/// Saves completion flag — shows only once per installation.
class PermissionOnboardingPage extends StatefulWidget {
  final VoidCallback onComplete;

  const PermissionOnboardingPage({super.key, required this.onComplete});

  @override
  State<PermissionOnboardingPage> createState() =>
      _PermissionOnboardingPageState();
}

class _PermissionOnboardingPageState extends State<PermissionOnboardingPage> {
  final List<_PermissionStep> _pendingSteps = [];
  int _currentIndex = 0;
  bool _isRequesting = false;
  bool _initialized = false;

  static const _onboardingCompleteKey = 'permission_onboarding_complete';

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    try {
      // Если онбординг уже пройден — сразу пропускаем
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_onboardingCompleteKey) == true) {
        Logger.debug('[Onboarding] Already completed, skipping');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onComplete();
        });
        return;
      }

      // 1. Геолокация — проверяем через Geolocator (тот же пакет что и запрашивает)
      final geoStatus = await Geolocator.checkPermission();
      final geoGranted = geoStatus == LocationPermission.always ||
          geoStatus == LocationPermission.whileInUse;

      // 2. Контакты — проверяем через FlutterContacts (тот же пакет что и запрашивает)
      final contactsGranted = await FlutterContacts.requestPermission(readonly: true);

      // 3. Микрофон — проверяем через permission_handler
      final micStatus = await Permission.microphone.status;
      final micGranted = micStatus.isGranted;

      // 4. Камера — проверяем через permission_handler
      final cameraStatus = await Permission.camera.status;
      final cameraGranted = cameraStatus.isGranted;

      Logger.debug('[Onboarding] Permissions: geo=$geoGranted, contacts=$contactsGranted, mic=$micGranted, camera=$cameraGranted');

      if (!geoGranted) {
        _pendingSteps.add(_PermissionStep.geolocation);
      }
      if (!contactsGranted) {
        _pendingSteps.add(_PermissionStep.contacts);
      }
      if (!micGranted) {
        _pendingSteps.add(_PermissionStep.microphone);
      }
      if (!cameraGranted) {
        _pendingSteps.add(_PermissionStep.camera);
      }

      if (_pendingSteps.isEmpty) {
        // All already granted — mark complete and skip
        await prefs.setBool(_onboardingCompleteKey, true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onComplete();
        });
        return;
      }

      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      Logger.warning('Error checking permissions: $e');
      // On error, skip onboarding
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onComplete();
      });
    }
  }

  Future<void> _onAllow() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);

    try {
      final step = _pendingSteps[_currentIndex];

      if (step == _PermissionStep.geolocation) {
        final result = await Geolocator.requestPermission();
        final granted = result == LocationPermission.always ||
            result == LocationPermission.whileInUse;
        Logger.debug(
            '[Onboarding] Geo permission result: $result, granted: $granted');
      } else if (step == _PermissionStep.contacts) {
        final granted = await FlutterContacts.requestPermission();
        Logger.debug(
            '[Onboarding] Contacts permission result: granted=$granted');
      } else if (step == _PermissionStep.microphone) {
        final recorder = AudioRecorder();
        final granted = await recorder.hasPermission();
        recorder.dispose();
        Logger.debug(
            '[Onboarding] Microphone permission result: granted=$granted');
      } else if (step == _PermissionStep.camera) {
        final status = await Permission.camera.request();
        Logger.debug(
            '[Onboarding] Camera permission result: $status');
      }
    } catch (e) {
      Logger.warning('[Onboarding] Permission request error: $e');
    }

    if (!mounted) return;
    setState(() => _isRequesting = false);
    _goToNextOrFinish();
  }

  void _onSkip() {
    _goToNextOrFinish();
  }

  Future<void> _goToNextOrFinish() async {
    if (_currentIndex < _pendingSteps.length - 1) {
      setState(() => _currentIndex++);
    } else {
      // Сохраняем флаг что онбординг пройден (независимо от результата)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardingCompleteKey, true);
      Logger.debug('[Onboarding] Completed, saved flag');
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return _buildLoading();
    }

    final step = _pendingSteps[_currentIndex];
    return _buildPermissionScreen(step);
  }

  Widget _buildLoading() {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.deepEmerald],
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildPermissionScreen(_PermissionStep step) {
    final icon = switch (step) {
      _PermissionStep.geolocation => Icons.location_on_rounded,
      _PermissionStep.contacts => Icons.contacts_rounded,
      _PermissionStep.microphone => Icons.mic_rounded,
      _PermissionStep.camera => Icons.camera_alt_rounded,
    };

    final title = switch (step) {
      _PermissionStep.geolocation => 'Разрешите доступ\nк геолокации',
      _PermissionStep.contacts => 'Разрешите доступ\nк контактам',
      _PermissionStep.microphone => 'Разрешите доступ\nк микрофону',
      _PermissionStep.camera => 'Разрешите доступ\nк камере',
    };

    final description = switch (step) {
      _PermissionStep.geolocation =>
        'Мы сможем напоминать вам о накопленных '
            'баллах и специальных акциях, когда вы '
            'рядом с нашей кофейней.\n\n'
            'Если вы откажетесь, некоторые акции '
            'и персональные предложения будут недоступны.',
      _PermissionStep.contacts =>
        'Мы покажем в мессенджере только тех людей '
            'из вашей телефонной книги, которые тоже '
            'пользуются приложением.\n\n'
            'Ваши контакты не хранятся на сервере.\n\n'
            'Если вы откажетесь, мессенджер будет '
            'работать, но без привязки к вашей '
            'телефонной книге.',
      _PermissionStep.microphone =>
        'Микрофон нужен для записи голосовых '
            'сообщений и звонков в мессенджере.\n\n'
            'Если вы откажетесь, вы не сможете '
            'отправлять голосовые сообщения и '
            'совершать звонки.',
      _PermissionStep.camera =>
        'Камера нужна для отправки фото и видео '
            'в мессенджере, а также для сканирования '
            'QR-кодов программы лояльности.\n\n'
            'Если вы откажетесь, вы не сможете '
            'делать фото и снимать видео в приложении.',
    };

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.deepEmerald],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Icon
                Container(
                  width: 100.w,
                  height: 100.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.turquoise, AppColors.emerald],
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 48.sp,
                  ),
                ),
                SizedBox(height: 32.h),

                // Title
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20.h),

                // Description
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: Text(
                    description,
                    style: TextStyle(
                      fontSize: 15.sp,
                      color: Colors.white.withOpacity(0.65),
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const Spacer(flex: 3),

                // "Продолжить" button
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.turquoise, AppColors.emerald],
                      ),
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: ElevatedButton(
                      onPressed: _isRequesting ? null : _onAllow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        padding: EdgeInsets.symmetric(vertical: 16.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                      ),
                      child: _isRequesting
                          ? SizedBox(
                              width: 22.w,
                              height: 22.w,
                              child: const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Продолжить',
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
                SizedBox(height: 12.h),

                // "Не сейчас" button
                TextButton(
                  onPressed: _isRequesting ? null : _onSkip,
                  child: Text(
                    'Не сейчас',
                    style: TextStyle(
                      fontSize: 15.sp,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ),
                SizedBox(height: 24.h),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _PermissionStep { geolocation, contacts, microphone, camera }

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/logger.dart';

/// Permission onboarding page shown after login/registration.
/// Requests geolocation and contacts permissions sequentially.
/// Skips already-granted permissions. Shows again on next login if denied.
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

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    try {
      // Check geolocation
      final geoStatus = await Geolocator.checkPermission();
      final geoGranted = geoStatus == LocationPermission.always ||
          geoStatus == LocationPermission.whileInUse;

      // Check contacts
      final contactsStatus = await Permission.contacts.status;
      final contactsGranted = contactsStatus.isGranted;

      if (!geoGranted) {
        _pendingSteps.add(_PermissionStep.geolocation);
      }
      if (!contactsGranted) {
        _pendingSteps.add(_PermissionStep.contacts);
      }

      if (_pendingSteps.isEmpty) {
        // All already granted — skip onboarding
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
      } else {
        final result = await Permission.contacts.request();
        Logger.debug(
            '[Onboarding] Contacts permission result: $result, granted: ${result.isGranted}');
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

  void _goToNextOrFinish() {
    if (_currentIndex < _pendingSteps.length - 1) {
      setState(() => _currentIndex++);
    } else {
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
    final isGeo = step == _PermissionStep.geolocation;

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
                    isGeo
                        ? Icons.location_on_rounded
                        : Icons.contacts_rounded,
                    color: Colors.white,
                    size: 48.sp,
                  ),
                ),
                SizedBox(height: 32.h),

                // Title
                Text(
                  isGeo
                      ? 'Разрешите доступ\nк геолокации'
                      : 'Разрешите доступ\nк контактам',
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
                    isGeo
                        ? 'Мы сможем напоминать вам о накопленных '
                            'баллах и специальных акциях, когда вы '
                            'рядом с нашей кофейней.\n\n'
                            'Если вы откажетесь, некоторые акции '
                            'и персональные предложения будут недоступны.'
                        : 'Мы покажем в мессенджере только тех людей '
                            'из вашей телефонной книги, которые тоже '
                            'пользуются приложением.\n\n'
                            'Ваши контакты не хранятся на сервере.\n\n'
                            'Если вы откажетесь, мессенджер будет '
                            'работать, но без привязки к вашей '
                            'телефонной книге.',
                    style: TextStyle(
                      fontSize: 15.sp,
                      color: Colors.white.withOpacity(0.65),
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const Spacer(flex: 3),

                // "Разрешить" button
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
                              'Разрешить',
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

enum _PermissionStep { geolocation, contacts }

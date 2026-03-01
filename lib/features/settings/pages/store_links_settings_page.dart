import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';

/// Settings page for configuring App Store / Google Play links
class StoreLinksSettingsPage extends StatefulWidget {
  const StoreLinksSettingsPage({super.key});

  @override
  State<StoreLinksSettingsPage> createState() => _StoreLinksSettingsPageState();
}

class _StoreLinksSettingsPageState extends State<StoreLinksSettingsPage> {
  final _androidController = TextEditingController();
  final _iosController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _androidController.dispose();
    _iosController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/app-settings/store-links',
        timeout: ApiConstants.defaultTimeout,
      );
      if (result != null && mounted) {
        _androidController.text = result['android_url'] ?? '';
        _iosController.text = result['ios_url'] ?? '';
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final success = await BaseHttpService.simplePost(
        endpoint: '/api/app-settings/store-links',
        body: {
          'android_url': _androidController.text.trim(),
          'ios_url': _iosController.text.trim(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Сохранено' : 'Ошибка сохранения'),
            backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения'), backgroundColor: Colors.red.shade700),
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: const [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : SingleChildScrollView(
                        padding: EdgeInsets.all(16.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 8.h),
                            Text(
                              'Укажите ссылки на приложение в магазинах. '
                              'Они используются для генерации QR-кодов в диалоге «Код приглашения».',
                              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13.sp),
                            ),
                            SizedBox(height: 24.h),
                            _buildField(
                              label: 'Google Play (Android)',
                              controller: _androidController,
                              hint: 'https://play.google.com/store/apps/details?id=...',
                              icon: Icons.android,
                            ),
                            SizedBox(height: 20.h),
                            _buildField(
                              label: 'App Store (iOS)',
                              controller: _iosController,
                              hint: 'https://apps.apple.com/app/...',
                              icon: Icons.apple,
                            ),
                            SizedBox(height: 32.h),
                            SizedBox(
                              width: double.infinity,
                              height: 48.h,
                              child: ElevatedButton(
                                onPressed: _isSaving ? null : _saveSettings,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.gold,
                                  foregroundColor: AppColors.night,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                ),
                                child: _isSaving
                                    ? SizedBox(
                                        width: 20.w,
                                        height: 20.w,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.night,
                                        ),
                                      )
                                    : Text(
                                        'Сохранить',
                                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          SizedBox(width: 8.w),
          Text(
            'Ссылки на магазины',
            style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.8), size: 20.sp),
            SizedBox(width: 8.w),
            Text(label, style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w600)),
          ],
        ),
        SizedBox(height: 8.h),
        TextField(
          controller: controller,
          style: TextStyle(color: Colors.white, fontSize: 14.sp),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13.sp),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide: BorderSide(color: AppColors.gold),
            ),
          ),
        ),
      ],
    );
  }
}

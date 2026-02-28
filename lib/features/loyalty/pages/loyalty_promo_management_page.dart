import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/logger.dart';
import '../services/loyalty_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница управления условиями акций для админа
class LoyaltyPromoManagementPage extends StatefulWidget {
  const LoyaltyPromoManagementPage({super.key});

  @override
  State<LoyaltyPromoManagementPage> createState() => _LoyaltyPromoManagementPageState();
}

class _LoyaltyPromoManagementPageState extends State<LoyaltyPromoManagementPage> {
  final TextEditingController _promoTextController = TextEditingController();
  final TextEditingController _pointsPerScanController = TextEditingController(text: '1');
  // Сохраняем значения формулы со стороны сервера, но не показываем их в UI
  int _pointsRequired = 10;
  int _drinksToGive = 1;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPromoSettings();
  }

  @override
  void dispose() {
    _promoTextController.dispose();
    _pointsPerScanController.dispose();
    super.dispose();
  }

  Future<void> _loadPromoSettings() async {
    if (mounted) setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final settings = await LoyaltyService.fetchPromoSettings();
      _promoTextController.text = settings.promoText;
      _pointsRequired = settings.pointsRequired > 0 ? settings.pointsRequired : 10;
      _drinksToGive = settings.drinksToGive > 0 ? settings.drinksToGive : 1;
      _pointsPerScanController.text = settings.pointsPerScan.toString();
      Logger.debug('✅ Настройки акции загружены');
    } catch (e) {
      Logger.error('Ошибка загрузки настроек акции', e);
      _error = 'Ошибка загрузки: ${e.toString()}';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _savePromoSettings() async {
    if (mounted) setState(() { _isSaving = true; _error = null; });

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeePhone = prefs.getString('userPhone') ?? prefs.getString('user_phone') ?? '';

      final success = await LoyaltyService.savePromoSettings(
        promoText: _promoTextController.text.trim(),
        pointsRequired: _pointsRequired,
        drinksToGive: _drinksToGive,
        pointsPerScan: int.tryParse(_pointsPerScanController.text) ?? 1,
        employeePhone: employeePhone,
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Условия акции сохранены'),
              backgroundColor: AppColors.primaryGreen,
            ),
          );
        }
      } else {
        if (mounted) setState(() => _error = 'Не удалось сохранить');
      }
    } catch (e) {
      Logger.error('Ошибка сохранения настроек акции', e);
      if (mounted) setState(() => _error = 'Ошибка: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          'Управление акцией',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.emerald.withOpacity(0.4),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: AppColors.turquoise),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Карточка с текстом условий акции
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.emeraldDark.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(
                        color: AppColors.emerald.withOpacity(0.3),
                      ),
                    ),
                    padding: EdgeInsets.all(20.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(8.w),
                              decoration: BoxDecoration(
                                color: AppColors.emerald.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Icon(
                                Icons.local_offer_outlined,
                                color: AppColors.turquoise,
                                size: 22.sp,
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Условия акции',
                                    style: TextStyle(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Текст отображается клиенту в карте лояльности',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: Colors.white.withOpacity(0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 20.h),
                        TextField(
                          controller: _promoTextController,
                          maxLines: 8,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14.sp,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Например: Накапливайте баллы за каждую покупку и обменивайте их на напитки...',
                            hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 13.sp,
                            ),
                            filled: true,
                            fillColor: AppColors.night.withOpacity(0.6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(
                                color: AppColors.emerald.withOpacity(0.3),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(
                                color: AppColors.emerald.withOpacity(0.3),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(
                                color: AppColors.turquoise,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: EdgeInsets.all(14.w),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 16.h),

                  // Карточка: баллов за сканирование
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.emeraldDark.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(
                        color: AppColors.emerald.withOpacity(0.3),
                      ),
                    ),
                    padding: EdgeInsets.all(20.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(8.w),
                              decoration: BoxDecoration(
                                color: AppColors.emerald.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Icon(
                                Icons.qr_code_scanner_outlined,
                                color: AppColors.turquoise,
                                size: 22.sp,
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Баллов за сканирование',
                                    style: TextStyle(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Сколько баллов получает клиент при каждом сканировании QR',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: Colors.white.withOpacity(0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16.h),
                        TextField(
                          controller: _pointsPerScanController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14.sp,
                          ),
                          decoration: InputDecoration(
                            hintText: '1',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                            prefixIcon: Icon(Icons.star_outline, color: AppColors.turquoise),
                            suffixText: 'балл(а)',
                            suffixStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
                            filled: true,
                            fillColor: AppColors.night.withOpacity(0.6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.3)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: AppColors.turquoise, width: 1.5),
                            ),
                            contentPadding: EdgeInsets.all(14.w),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_error != null) ...[
                    SizedBox(height: 12.h),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: AppColors.error.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: AppColors.error, size: 18.sp),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: AppColors.error, fontSize: 13.sp),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  SizedBox(height: 24.h),

                  SizedBox(
                    width: double.infinity,
                    height: 52.h,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _savePromoSettings,
                      icon: _isSaving
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(Icons.save_outlined, size: 20.sp),
                      label: Text(
                        _isSaving ? 'Сохранение...' : 'Сохранить условия',
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.emerald.withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

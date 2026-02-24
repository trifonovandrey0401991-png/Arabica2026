import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../models/cigarette_training_model.dart';
import '../services/cigarette_vision_service.dart';

/// Диалог управления фотографиями товара (крупный план + выкладка)
class CigarettePhotosManagementDialog {
  // Градиенты (те же что в основном файле)
  static final _purpleGradient = [AppColors.indigo, AppColors.purple];

  /// Показывает диалог управления фотографиями товара
  ///
  /// [context] — BuildContext для показа диалога
  /// [product] — товар, для которого показываются фото
  /// [photosGridBuilder] — колбэк для построения грида фотографий
  ///   (принимает список сэмплов, товар и флаг isRecount)
  static void show({
    required BuildContext context,
    required CigaretteProduct product,
    required Widget Function(List<TrainingSample> samples, CigaretteProduct product, {required bool isRecount}) photosGridBuilder,
  }) async {
    final navigator = Navigator.of(context);

    // Показать индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    // Загрузить samples
    final samples = await CigaretteVisionService.getSamplesForProduct(product.id);

    // Закрыть индикатор (всегда, даже если context unmounted)
    try { navigator.pop(); } catch (_) {}

    if (!context.mounted) return;

    // Разделить на типы
    final recountSamples = samples
        .where((s) => s.type == TrainingSampleType.recount)
        .toList()
      ..sort((a, b) => (a.templateId ?? 0).compareTo(b.templateId ?? 0));

    final displaySamples = samples
        .where((s) => s.type == TrainingSampleType.display)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.darkNavy, AppColors.navy],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          ),
          child: Column(
            children: [
              // Заголовок
              Padding(
                padding: EdgeInsets.all(16.w),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2.r),
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10.w),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: _purpleGradient),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Icon(Icons.photo_library, color: Colors.white, size: 24),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Фотографии',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                product.productName,
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: Colors.white.withOpacity(0.6),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Контент
              Expanded(
                child: samples.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_library_outlined,
                                size: 64, color: Colors.white.withOpacity(0.3)),
                            SizedBox(height: 16),
                            Text(
                              'Нет загруженных фото',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 16.sp,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        children: [
                          // Секция "Крупный план"
                          if (recountSamples.isNotEmpty) ...[
                            _buildSectionHeader(
                              icon: Icons.crop_free,
                              title: 'Крупный план',
                              count: recountSamples.length,
                              total: product.requiredRecountPhotos,
                            ),
                            SizedBox(height: 12),
                            photosGridBuilder(recountSamples, product, isRecount: true),
                            SizedBox(height: 24),
                          ],

                          // Секция "Выкладка"
                          if (displaySamples.isNotEmpty) ...[
                            _buildSectionHeader(
                              icon: Icons.grid_view,
                              title: 'Выкладка',
                              count: displaySamples.length,
                              total: null, // общее количество не ограничено
                            ),
                            SizedBox(height: 12),
                            photosGridBuilder(displaySamples, product, isRecount: false),
                            SizedBox(height: 24),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Заголовок секции (крупный план / выкладка)
  static Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required int count,
    int? total,
  }) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        Spacer(),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Text(
            total != null ? '$count/$total' : '$count фото',
            style: TextStyle(
              fontSize: 13.sp,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ),
      ],
    );
  }
}

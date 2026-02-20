import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:image_picker/image_picker.dart';
import '../models/shift_ai_verification_model.dart';
import '../services/shift_ai_verification_service.dart';
import '../../shifts/models/shift_shortage_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница ИИ проверки товаров при пересменке
class ShiftAiVerificationPage extends StatefulWidget {
  final List<Uint8List> photos; // Фото с вопросов с isAiCheck
  final String shopAddress;
  final String employeeName;

  const ShiftAiVerificationPage({
    super.key,
    required this.photos,
    required this.shopAddress,
    required this.employeeName,
  });

  @override
  State<ShiftAiVerificationPage> createState() => _ShiftAiVerificationPageState();
}

class _ShiftAiVerificationPageState extends State<ShiftAiVerificationPage> {
  bool _isLoading = true;
  ShiftAiVerificationResult? _result;
  final List<ShiftShortage> _confirmedShortages = [];
  // annotationId для продуктов, верифицированных через BBox (для обучения админом)
  final Map<String, String> _bboxAnnotations = {}; // productId -> annotationId

  @override
  void initState() {
    super.initState();
    _runVerification();
  }

  @override
  void dispose() {
    // Освобождаем ссылки на тяжёлые данные (фото в _result, список недостач)
    _result = null;
    _confirmedShortages.clear();
    super.dispose();
  }

  Future<void> _runVerification() async {
    if (mounted) setState(() => _isLoading = true);

    final result = await ShiftAiVerificationService.verifyShiftPhotos(
      photos: widget.photos,
      shopAddress: widget.shopAddress,
    );

    if (mounted) {
      setState(() {
        _result = result;
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmProductPresent(MissingProductInfo product) async {
    // Показать диалог выбора фото и рисования BBox
    final result = await showDialog<BBoxDialogResult>(
      context: context,
      builder: (context) => _BoundingBoxDialog(
        photos: widget.photos,
        product: product,
        shopAddress: widget.shopAddress,
        employeeName: widget.employeeName,
        currentAttempts: product.verificationAttempts,
      ),
    );

    if (result == null) return; // Диалог отменён

    if (result.detected) {
      // ИИ нашёл товар - УСПЕХ
      if (mounted) {
        setState(() {
          product.status = ConfirmationStatus.confirmedPresent;
          // Сохраняем annotationId для обучения админом
          if (result.annotationId != null) {
            _bboxAnnotations[product.productId] = result.annotationId!;
          }
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Товар распознан! (${result.confidencePercent}%)'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } else {
      // ИИ не нашёл - попытка неудачна
      if (mounted) {
        setState(() {
          product.verificationAttempts++;
        });
      }

      final remaining = product.remainingAttempts;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(remaining > 0
                ? 'ИИ не распознал товар. Осталось попыток: $remaining'
                : 'ИИ не распознал товар. Можете пропустить проверку.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }
  }

  /// Пропустить ИИ проверку для товара
  void _skipAiVerification(MissingProductInfo product) {
    if (mounted) setState(() {
      product.aiVerificationSkipped = true;
      product.status = ConfirmationStatus.confirmedPresent;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Проверка ИИ пропущена'),
        backgroundColor: AppColors.emeraldDark,
      ),
    );
  }

  Future<void> _confirmProductMissing(MissingProductInfo product) async {
    // Проверяем остатки
    final stockQuantity = await ShiftAiVerificationService.getProductStock(
      widget.shopAddress,
      product.barcode,
    );

    if (!mounted) return;

    if (stockQuantity != null && stockQuantity > 0) {
      // Показать предупреждение об остатках
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.emeraldDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          title: Text('Подтверждение недостачи', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.productName,
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: AppColors.warning),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'На остатках: $stockQuantity шт.\nВы уверены, что товар отсутствует?',
                        style: TextStyle(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.6))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: Text('Да, отсутствует'),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        if (mounted) setState(() {
          product.status = ConfirmationStatus.confirmedMissing;
          _confirmedShortages.add(ShiftShortage(
            productId: product.productId,
            barcode: product.barcode,
            productName: product.productName,
            stockQuantity: stockQuantity,
            confirmedAt: DateTime.now(),
            employeeName: widget.employeeName,
          ));
        });
      }
    } else {
      // Нет на остатках — просто отметить как отсутствующий
      if (mounted) {
        setState(() {
          product.status = ConfirmationStatus.confirmedMissing;
        });
      }
    }
  }

  void _finishVerification() {
    // Проверяем что реальная проверка была проведена
    if (_result == null || _result!.noVerificationPerformed) {
      _skipVerification();
      return;
    }

    // Определяем прошла ли проверка
    final allConfirmed = _result?.missingProducts.every(
          (p) => p.status != ConfirmationStatus.notConfirmed,
        ) ??
        true;

    if (!allConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Подтвердите все товары перед сохранением'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // aiVerificationPassed = true ТОЛЬКО если:
    // 1. Есть найденные товары (реальная проверка была)
    // 2. И нет подтверждённых недостач
    final passed = _result!.detectedProducts.isNotEmpty && _confirmedShortages.isEmpty;

    // Возвращаем результат
    Navigator.pop(context, {
      'aiVerificationPassed': passed,
      'shortages': _confirmedShortages,
      'bboxAnnotations': _bboxAnnotations, // productId -> annotationId для обучения
    });
  }

  void _skipVerification() {
    Navigator.pop(context, null); // Пропустить ИИ проверку
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 4.h),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'ИИ Проверка товаров',
              style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: _skipVerification,
            child: Text(
              'Пропустить',
              style: TextStyle(color: AppColors.gold.withOpacity(0.8), fontSize: 14.sp),
            ),
          ),
        ],
      ),
    );
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
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: AppColors.gold),
                            SizedBox(height: 20),
                            Text(
                              'Анализируем фотографии...',
                              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16.sp),
                            ),
                          ],
                        ),
                      )
                    : _buildContent(),
              ),
              if (!_isLoading &&
                  _result != null &&
                  _result!.modelTrained &&
                  !_result!.noVerificationPerformed)
                Container(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
                  child: ElevatedButton(
                    onPressed: _finishVerification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.night,
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                    ),
                    child: Text(
                      _confirmedShortages.isEmpty
                          ? 'Завершить проверку'
                          : 'Сохранить с недостачами (${_confirmedShortages.length})',
                      style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_result == null) {
      return Center(
        child: Text('Ошибка загрузки', style: TextStyle(color: Colors.white.withOpacity(0.7))),
      );
    }

    if (!_result!.modelTrained) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.gold.withOpacity(0.3), width: 2),
                ),
                child: Icon(Icons.model_training, size: 50, color: AppColors.gold),
              ),
              SizedBox(height: 24),
              Text(
                'Модель ИИ ещё не обучена',
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Продолжите загрузку образцов для обучения модели. ИИ проверка станет доступна позже.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.sp,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              SizedBox(height: 32),
              ElevatedButton(
                onPressed: _skipVerification,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.night,
                  padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                ),
                child: Text('Пропустить проверку', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    // Нет проверенных товаров - все пропущены (ИИ не готов для магазина)
    if (_result!.noVerificationPerformed) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.warning.withOpacity(0.3), width: 2),
                ),
                child: Icon(Icons.hourglass_empty, size: 50, color: AppColors.warning),
              ),
              SizedBox(height: 24),
              Text(
                'ИИ не готов для этого магазина',
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                'Необходимо добавить фото выкладки для ${_result!.skippedProducts.length} товаров',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.sp,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              SizedBox(height: 16),
              Container(
                constraints: BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.symmetric(vertical: 4.h),
                  itemCount: _result!.skippedProducts.length,
                  itemBuilder: (context, index) {
                    final product = _result!.skippedProducts[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.warning, color: AppColors.warning, size: 20),
                      title: Text(product.productName, style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.9))),
                      subtitle: Text(product.reason, style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5))),
                    );
                  },
                ),
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: _skipVerification,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.night,
                  padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                ),
                child: Text('Пропустить проверку', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    if (_result!.allProductsFound) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.success.withOpacity(0.3), width: 2),
                ),
                child: Icon(Icons.check_circle, size: 60, color: AppColors.success),
              ),
              SizedBox(height: 24),
              Text(
                'Все товары найдены!',
                style: TextStyle(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'ИИ обнаружил все ${_result!.detectedProducts.length} товаров на фотографиях',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.sp,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              if (_result!.hasSkippedProducts) ...[
                SizedBox(height: 16),
                Text(
                  'Пропущено ${_result!.skippedProducts.length} товаров (ИИ не готов)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.sp, color: AppColors.warning),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        // Найденные товары
        if (_result!.detectedProducts.isNotEmpty) ...[
          _buildSectionHeader(
            icon: Icons.check_circle,
            title: 'Найденные товары',
            color: AppColors.success,
            count: _result!.detectedProducts.length,
          ),
          SizedBox(height: 8),
          ..._result!.detectedProducts.map(_buildDetectedProductCard),
          SizedBox(height: 24),
        ],

        // Отсутствующие товары
        if (_result!.missingProducts.isNotEmpty) ...[
          _buildSectionHeader(
            icon: Icons.warning,
            title: 'Требуют подтверждения',
            color: AppColors.warning,
            count: _result!.missingProducts.length,
          ),
          SizedBox(height: 8),
          ..._result!.missingProducts.map(_buildMissingProductCard),
          SizedBox(height: 24),
        ],

        // Пропущенные товары (ИИ не готов)
        if (_result!.hasSkippedProducts) ...[
          _buildSectionHeader(
            icon: Icons.hourglass_empty,
            title: 'Пропущены (ИИ не готов)',
            color: AppColors.neutral,
            count: _result!.skippedProducts.length,
          ),
          SizedBox(height: 8),
          ..._result!.skippedProducts.map(_buildSkippedProductCard),
        ],
      ],
    );
  }

  Widget _buildSkippedProductCard(SkippedProductInfo product) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.neutral.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(Icons.hourglass_empty, color: AppColors.neutral, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.productName,
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w500, fontSize: 14.sp),
                ),
                Text(product.barcode, style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.3))),
                SizedBox(height: 4),
                Text(
                  product.reason,
                  style: TextStyle(fontSize: 11.sp, color: AppColors.warning),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required Color color,
    required int count,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          Spacer(),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 12.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectedProductCard(DetectedProductInfo product) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.success.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(Icons.check, color: AppColors.success, size: 22),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.productName,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14.sp),
                ),
                Text(
                  product.barcode,
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.sp),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Text(
              '${product.confidencePercent}%',
              style: TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.bold,
                fontSize: 12.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMissingProductCard(MissingProductInfo product) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (product.status) {
      case ConfirmationStatus.confirmedPresent:
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        statusText = 'Присутствует';
        break;
      case ConfirmationStatus.confirmedMissing:
        statusColor = AppColors.error;
        statusIcon = Icons.cancel;
        statusText = 'Недостача';
        break;
      default:
        statusColor = AppColors.warning;
        statusIcon = Icons.help_outline;
        statusText = 'Не подтверждён';
    }

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: statusColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(statusIcon, color: statusColor),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.productName,
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    Text(
                      product.barcode,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (product.status == ConfirmationStatus.notConfirmed) ...[
            SizedBox(height: 12),
            // Показываем счётчик попыток если были неудачные попытки
            if (product.verificationAttempts > 0) ...[
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                margin: EdgeInsets.only(bottom: 8.h),
                decoration: BoxDecoration(
                  color: (product.canRetry ? AppColors.warning : AppColors.error).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6.r),
                  border: Border.all(
                    color: (product.canRetry ? AppColors.warning : AppColors.error).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      product.canRetry ? Icons.refresh : Icons.warning,
                      size: 14,
                      color: product.canRetry ? AppColors.warning : AppColors.error,
                    ),
                    SizedBox(width: 4),
                    Text(
                      product.canRetry
                          ? 'Попыток: ${product.verificationAttempts}/${MissingProductInfo.maxVerificationAttempts}'
                          : 'Лимит попыток исчерпан',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: product.canRetry ? AppColors.warning : AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmProductPresent(product),
                    icon: Icon(Icons.photo_camera, size: 18),
                    label: Text(product.verificationAttempts > 0 ? 'Повторить' : 'Присутствует'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: BorderSide(color: AppColors.success.withOpacity(0.5)),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmProductMissing(product),
                    icon: Icon(Icons.cancel, size: 18),
                    label: Text('Отсутствует'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error.withOpacity(0.5)),
                    ),
                  ),
                ),
              ],
            ),
            // Кнопка "Пропустить проверку ИИ" после 3 неудачных попыток
            if (product.canSkip) ...[
              SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _skipAiVerification(product),
                  icon: Icon(Icons.skip_next, size: 18),
                  label: Text('Пропустить проверку ИИ'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white.withOpacity(0.5),
                    side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Диалог для выбора фото и рисования BBox
class _BoundingBoxDialog extends StatefulWidget {
  final List<Uint8List> photos;
  final MissingProductInfo product;
  final String shopAddress;
  final String employeeName;
  final int currentAttempts;

  _BoundingBoxDialog({
    required this.photos,
    required this.product,
    required this.shopAddress,
    required this.employeeName,
    this.currentAttempts = 0,
  });

  @override
  State<_BoundingBoxDialog> createState() => _BoundingBoxDialogState();
}

class _BoundingBoxDialogState extends State<_BoundingBoxDialog> {
  int _selectedPhotoIndex = 0;
  Rect? _boundingBox;
  Offset? _startPoint;
  bool _isVerifying = false;
  Uint8List? _newPhoto; // Новое фото с камеры
  Size? _imageSize; // Размеры отображаемого изображения
  final GlobalKey _imageKey = GlobalKey();

  /// Получить текущее изображение (новое или из списка)
  Uint8List get _currentImage => _newPhoto ?? widget.photos[_selectedPhotoIndex];

  /// Используется новое фото?
  bool get _isNewPhoto => _newPhoto != null;

  Future<void> _takeNewPhoto() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );

    if (image != null) {
      final bytes = await image.readAsBytes();
      if (mounted) {
        setState(() {
          _newPhoto = bytes;
          _selectedPhotoIndex = -1; // -1 означает новое фото
          _boundingBox = null;
        });
      }
    }
  }

  void _selectExistingPhoto(int index) {
    if (mounted) setState(() {
      _selectedPhotoIndex = index;
      _newPhoto = null;
      _boundingBox = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = MissingProductInfo.maxVerificationAttempts - widget.currentAttempts;

    return Dialog(
      backgroundColor: AppColors.night,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Container(
        constraints: BoxConstraints(maxWidth: 500, maxHeight: 750),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16.r),
                  topRight: Radius.circular(16.r),
                ),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Row(
                children: [
                  Icon(Icons.crop_free, color: AppColors.gold),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Выделите товар на фото',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16.sp,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          widget.product.productName,
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                        if (widget.currentAttempts > 0)
                          Text(
                            'Попытка ${widget.currentAttempts + 1} из ${MissingProductInfo.maxVerificationAttempts}',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: remaining > 0 ? AppColors.warning : AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Кнопка камеры
                  IconButton(
                    onPressed: _takeNewPhoto,
                    icon: Icon(Icons.camera_alt, color: AppColors.gold),
                    tooltip: 'Сделать новое фото',
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, null),
                    icon: Icon(Icons.close, color: Colors.white.withOpacity(0.6)),
                  ),
                ],
              ),
            ),

            // Выбор фото (включая новое)
            Container(
              height: 80,
              padding: EdgeInsets.all(8.w),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // Новое фото (если есть)
                  if (_newPhoto != null)
                    GestureDetector(
                      onTap: () => _selectExistingPhoto(-1),
                      child: Container(
                        width: 64,
                        height: 64,
                        margin: EdgeInsets.only(right: 8.w),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _isNewPhoto ? AppColors.gold : Colors.white.withOpacity(0.2),
                            width: _isNewPhoto ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6.r),
                              child: Image.memory(_newPhoto!, fit: BoxFit.cover, width: 64, height: 64),
                            ),
                            Positioned(
                              bottom: 2.h,
                              right: 2.w,
                              child: Container(
                                padding: EdgeInsets.all(2.w),
                                decoration: BoxDecoration(
                                  color: AppColors.gold,
                                  borderRadius: BorderRadius.circular(4.r),
                                ),
                                child: Icon(Icons.camera_alt, size: 10, color: AppColors.night),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Существующие фото
                  ...widget.photos.asMap().entries.map((entry) {
                    final index = entry.key;
                    final photo = entry.value;
                    final isSelected = !_isNewPhoto && index == _selectedPhotoIndex;
                    return GestureDetector(
                      onTap: () => _selectExistingPhoto(index),
                      child: Container(
                        width: 64,
                        height: 64,
                        margin: EdgeInsets.only(right: 8.w),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.2),
                            width: isSelected ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6.r),
                          child: Image.memory(photo, fit: BoxFit.cover),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),

            // Фото с возможностью выделения
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onPanStart: (details) {
                      if (mounted) setState(() {
                        _startPoint = details.localPosition;
                        _boundingBox = Rect.fromPoints(_startPoint!, _startPoint!);
                      });
                    },
                    onPanUpdate: (details) {
                      if (_startPoint != null) {
                        if (mounted) setState(() {
                          _boundingBox = Rect.fromPoints(
                            _startPoint!,
                            details.localPosition,
                          );
                        });
                      }
                    },
                    onPanEnd: (_) {
                      _startPoint = null;
                      // Запоминаем размеры изображения
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final context = _imageKey.currentContext;
                        if (context != null) {
                          final RenderBox box = context.findRenderObject() as RenderBox;
                          if (mounted) setState(() {
                            _imageSize = box.size;
                          });
                        }
                      });
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          _currentImage,
                          key: _imageKey,
                          fit: BoxFit.contain,
                        ),
                        if (_boundingBox != null)
                          CustomPaint(
                            painter: _BoundingBoxPainter(boundingBox: _boundingBox!),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Кнопки
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        if (mounted) setState(() => _boundingBox = null);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white.withOpacity(0.7),
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Text('Очистить'),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _boundingBox != null && !_isVerifying ? _verifyAndSave : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.night,
                        disabledBackgroundColor: Colors.white.withOpacity(0.1),
                        disabledForegroundColor: Colors.white.withOpacity(0.3),
                      ),
                      child: _isVerifying
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.night,
                              ),
                            )
                          : Text('Проверить', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verifyAndSave() async {
    if (_boundingBox == null) return;

    if (mounted) setState(() => _isVerifying = true);

    // Получаем размеры виджета для пересчёта координат рисования → реальных
    final imageContext = _imageKey.currentContext;
    Size displaySize;
    if (imageContext != null) {
      final RenderBox box = imageContext.findRenderObject() as RenderBox;
      displaySize = box.size;
    } else {
      displaySize = _imageSize ?? const Size(300, 300);
    }

    // Нормализуем координаты BBox к размерам ИЗОБРАЖЕНИЯ (не виджета)
    // Декодируем реальные размеры изображения
    final codec = await ui.instantiateImageCodec(_currentImage);
    final frame = await codec.getNextFrame();
    final realWidth = frame.image.width.toDouble();
    final realHeight = frame.image.height.toDouble();
    frame.image.dispose();

    // Пересчитываем: координаты рисования (в пространстве виджета) → нормализованные (0-1 от изображения)
    // Учитываем соотношение сторон виджета и изображения (BoxFit.contain)
    final scaleX = realWidth / displaySize.width;
    final scaleY = realHeight / displaySize.height;
    final scale = scaleX > scaleY ? scaleX : scaleY;
    final offsetX = (displaySize.width - realWidth / scale) / 2;
    final offsetY = (displaySize.height - realHeight / scale) / 2;

    final normalizedBox = {
      'x': ((_boundingBox!.left - offsetX) / (displaySize.width - 2 * offsetX)).clamp(0.0, 1.0),
      'y': ((_boundingBox!.top - offsetY) / (displaySize.height - 2 * offsetY)).clamp(0.0, 1.0),
      'width': (_boundingBox!.width / (displaySize.width - 2 * offsetX)).clamp(0.0, 1.0),
      'height': (_boundingBox!.height / (displaySize.height - 2 * offsetY)).clamp(0.0, 1.0),
    };

    final result = await ShiftAiVerificationService.verifyBoundingBox(
      imageData: _currentImage,
      boundingBox: normalizedBox,
      productId: widget.product.productId,
      barcode: widget.product.barcode,
      productName: widget.product.productName,
      shopAddress: widget.shopAddress,
      employeeName: widget.employeeName,
    );

    if (mounted) setState(() => _isVerifying = false);

    if (mounted) {
      // Возвращаем результат проверки с annotationId для обучения
      Navigator.pop(context, BBoxDialogResult(
        detected: result.detected,
        imageData: _currentImage,
        boundingBox: normalizedBox,
        confidence: result.confidence,
        annotationId: result.annotationId,
      ));
    }
  }
}

/// Painter для отрисовки BBox
class _BoundingBoxPainter extends CustomPainter {
  final Rect boundingBox;

  _BoundingBoxPainter({required this.boundingBox});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final fillPaint = Paint()
      ..color = AppColors.gold.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    canvas.drawRect(boundingBox, fillPaint);
    canvas.drawRect(boundingBox, paint);
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) {
    return oldDelegate.boundingBox != boundingBox;
  }
}

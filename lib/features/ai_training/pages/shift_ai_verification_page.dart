import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/shift_ai_verification_model.dart';
import '../services/shift_ai_verification_service.dart';
import '../../shifts/models/shift_shortage_model.dart';

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
  List<ShiftShortage> _confirmedShortages = [];

  @override
  void initState() {
    super.initState();
    _runVerification();
  }

  Future<void> _runVerification() async {
    setState(() => _isLoading = true);

    final result = await ShiftAiVerificationService.verifyShiftPhotos(
      photos: widget.photos,
      shopAddress: widget.shopAddress,
    );

    setState(() {
      _result = result;
      _isLoading = false;
    });
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
      setState(() {
        product.status = ConfirmationStatus.confirmedPresent;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Товар распознан! (${result.confidencePercent}%)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      // ИИ не нашёл - попытка неудачна
      setState(() {
        product.verificationAttempts++;
      });

      final remaining = product.remainingAttempts;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(remaining > 0
                ? 'ИИ не распознал товар. Осталось попыток: $remaining'
                : 'ИИ не распознал товар. Можете пропустить проверку.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Пропустить ИИ проверку для товара
  void _skipAiVerification(MissingProductInfo product) {
    setState(() {
      product.aiVerificationSkipped = true;
      product.status = ConfirmationStatus.confirmedPresent;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Проверка ИИ пропущена'),
        backgroundColor: Colors.grey,
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
          title: const Text('Подтверждение недостачи'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.productName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'На остатках: $stockQuantity шт.\nВы уверены, что товар отсутствует?',
                        style: TextStyle(color: Colors.orange.shade900),
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
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Да, отсутствует'),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        setState(() {
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
      setState(() {
        product.status = ConfirmationStatus.confirmedMissing;
      });
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
        const SnackBar(
          content: Text('Подтвердите все товары перед сохранением'),
          backgroundColor: Colors.orange,
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
    });
  }

  void _skipVerification() {
    Navigator.pop(context, null); // Пропустить ИИ проверку
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ИИ Проверка товаров'),
        backgroundColor: const Color(0xFF004D40),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _skipVerification,
            child: const Text(
              'Пропустить',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Анализируем фотографии...'),
                ],
              ),
            )
          : _buildContent(),
      bottomNavigationBar: !_isLoading &&
              _result != null &&
              _result!.modelTrained &&
              !_result!.noVerificationPerformed
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _finishVerification,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _confirmedShortages.isEmpty
                      ? 'Завершить проверку'
                      : 'Сохранить с недостачами (${_confirmedShortages.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildContent() {
    if (_result == null) {
      return const Center(child: Text('Ошибка загрузки'));
    }

    if (!_result!.modelTrained) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.model_training,
                size: 80,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 24),
              const Text(
                'Модель ИИ ещё не обучена',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Продолжите загрузку образцов для обучения модели. ИИ проверка станет доступна позже.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: _skipVerification,
                child: const Text('Пропустить проверку'),
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
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.hourglass_empty,
                size: 80,
                color: Colors.orange[400],
              ),
              const SizedBox(height: 24),
              const Text(
                'ИИ не готов для этого магазина',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Необходимо добавить фото выкладки для ${_result!.skippedProducts.length} товаров',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              // Список пропущенных товаров
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _result!.skippedProducts.length,
                  itemBuilder: (context, index) {
                    final product = _result!.skippedProducts[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.warning, color: Colors.orange[700], size: 20),
                      title: Text(product.productName, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(product.reason, style: const TextStyle(fontSize: 11)),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: _skipVerification,
                child: const Text('Пропустить проверку'),
              ),
            ],
          ),
        ),
      );
    }

    if (_result!.allProductsFound) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  size: 60,
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Все товары найдены!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'ИИ обнаружил все ${_result!.detectedProducts.length} товаров на фотографиях',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                ),
              ),
              if (_result!.hasSkippedProducts) ...[
                const SizedBox(height: 16),
                Text(
                  'Пропущено ${_result!.skippedProducts.length} товаров (ИИ не готов)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.orange[700],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Найденные товары
        if (_result!.detectedProducts.isNotEmpty) ...[
          _buildSectionHeader(
            icon: Icons.check_circle,
            title: 'Найденные товары',
            color: Colors.green,
            count: _result!.detectedProducts.length,
          ),
          const SizedBox(height: 8),
          ..._result!.detectedProducts.map(_buildDetectedProductCard),
          const SizedBox(height: 24),
        ],

        // Отсутствующие товары
        if (_result!.missingProducts.isNotEmpty) ...[
          _buildSectionHeader(
            icon: Icons.warning,
            title: 'Требуют подтверждения',
            color: Colors.orange,
            count: _result!.missingProducts.length,
          ),
          const SizedBox(height: 8),
          ..._result!.missingProducts.map(_buildMissingProductCard),
          const SizedBox(height: 24),
        ],

        // Пропущенные товары (ИИ не готов)
        if (_result!.hasSkippedProducts) ...[
          _buildSectionHeader(
            icon: Icons.hourglass_empty,
            title: 'Пропущены (ИИ не готов)',
            color: Colors.grey,
            count: _result!.skippedProducts.length,
          ),
          const SizedBox(height: 8),
          ..._result!.skippedProducts.map(_buildSkippedProductCard),
        ],
      ],
    );
  }

  Widget _buildSkippedProductCard(SkippedProductInfo product) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey.shade50,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.hourglass_empty, color: Colors.grey.shade600),
        ),
        title: Text(product.productName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.barcode, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(
              product.reason,
              style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
            ),
          ],
        ),
        isThreeLine: true,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectedProductCard(DetectedProductInfo product) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.check, color: Colors.green.shade700),
        ),
        title: Text(product.productName),
        subtitle: Text(product.barcode),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${product.confidencePercent}%',
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMissingProductCard(MissingProductInfo product) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (product.status) {
      case ConfirmationStatus.confirmedPresent:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Присутствует';
        break;
      case ConfirmationStatus.confirmedMissing:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Недостача';
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.help_outline;
        statusText = 'Не подтверждён';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(statusIcon, color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        product.barcode,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (product.status == ConfirmationStatus.notConfirmed) ...[
              const SizedBox(height: 12),
              // Показываем счётчик попыток если были неудачные попытки
              if (product.verificationAttempts > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: product.canRetry ? Colors.orange.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: product.canRetry ? Colors.orange.shade200 : Colors.red.shade200,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        product.canRetry ? Icons.refresh : Icons.warning,
                        size: 14,
                        color: product.canRetry ? Colors.orange.shade700 : Colors.red.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        product.canRetry
                            ? 'Попыток: ${product.verificationAttempts}/${MissingProductInfo.maxVerificationAttempts}'
                            : 'Лимит попыток исчерпан',
                        style: TextStyle(
                          fontSize: 11,
                          color: product.canRetry ? Colors.orange.shade800 : Colors.red.shade800,
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
                      icon: const Icon(Icons.photo_camera, size: 18),
                      label: Text(product.verificationAttempts > 0 ? 'Повторить' : 'Присутствует'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmProductMissing(product),
                      icon: const Icon(Icons.cancel, size: 18),
                      label: const Text('Отсутствует'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              ),
              // Кнопка "Пропустить проверку ИИ" после 3 неудачных попыток
              if (product.canSkip) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _skipAiVerification(product),
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: const Text('Пропустить проверку ИИ'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                      side: BorderSide(color: Colors.grey.shade400),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
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

  const _BoundingBoxDialog({
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
      setState(() {
        _newPhoto = bytes;
        _selectedPhotoIndex = -1; // -1 означает новое фото
        _boundingBox = null;
      });
    }
  }

  void _selectExistingPhoto(int index) {
    setState(() {
      _selectedPhotoIndex = index;
      _newPhoto = null;
      _boundingBox = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = MissingProductInfo.maxVerificationAttempts - widget.currentAttempts;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 750),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.crop_free, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Выделите товар на фото',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          widget.product.productName,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (widget.currentAttempts > 0)
                          Text(
                            'Попытка ${widget.currentAttempts + 1} из ${MissingProductInfo.maxVerificationAttempts}',
                            style: TextStyle(
                              fontSize: 11,
                              color: remaining > 0 ? Colors.orange.shade700 : Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Кнопка камеры
                  IconButton(
                    onPressed: _takeNewPhoto,
                    icon: Icon(Icons.camera_alt, color: Colors.red.shade700),
                    tooltip: 'Сделать новое фото',
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Выбор фото (включая новое)
            Container(
              height: 80,
              padding: const EdgeInsets.all(8),
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
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _isNewPhoto ? Colors.red : Colors.grey.shade300,
                            width: _isNewPhoto ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(_newPhoto!, fit: BoxFit.cover, width: 64, height: 64),
                            ),
                            Positioned(
                              bottom: 2,
                              right: 2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.camera_alt, size: 10, color: Colors.white),
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
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected ? Colors.red : Colors.grey.shade300,
                            width: isSelected ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
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
                      setState(() {
                        _startPoint = details.localPosition;
                        _boundingBox = Rect.fromPoints(_startPoint!, _startPoint!);
                      });
                    },
                    onPanUpdate: (details) {
                      if (_startPoint != null) {
                        setState(() {
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
                          setState(() {
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
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() => _boundingBox = null);
                      },
                      child: const Text('Очистить'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _boundingBox != null && !_isVerifying ? _verifyAndSave : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Проверить'),
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

    setState(() => _isVerifying = true);

    // Получаем размеры контейнера для нормализации
    final imageContext = _imageKey.currentContext;
    Size imageDisplaySize;
    if (imageContext != null) {
      final RenderBox box = imageContext.findRenderObject() as RenderBox;
      imageDisplaySize = box.size;
    } else {
      imageDisplaySize = _imageSize ?? const Size(300, 300);
    }

    // Нормализуем координаты BBox (0-1)
    final normalizedBox = {
      'x': (_boundingBox!.left / imageDisplaySize.width).clamp(0.0, 1.0),
      'y': (_boundingBox!.top / imageDisplaySize.height).clamp(0.0, 1.0),
      'width': (_boundingBox!.width / imageDisplaySize.width).clamp(0.0, 1.0),
      'height': (_boundingBox!.height / imageDisplaySize.height).clamp(0.0, 1.0),
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

    setState(() => _isVerifying = false);

    if (mounted) {
      // Возвращаем результат проверки
      Navigator.pop(context, BBoxDialogResult(
        detected: result.detected,
        imageData: _currentImage,
        boundingBox: normalizedBox,
        confidence: result.confidence,
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
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final fillPaint = Paint()
      ..color = Colors.red.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    canvas.drawRect(boundingBox, fillPaint);
    canvas.drawRect(boundingBox, paint);
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) {
    return oldDelegate.boundingBox != boundingBox;
  }
}

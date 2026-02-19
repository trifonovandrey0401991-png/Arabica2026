import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../services/loyalty_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class LoyaltyScannerPage extends StatefulWidget {
  const LoyaltyScannerPage({super.key});

  @override
  State<LoyaltyScannerPage> createState() => _LoyaltyScannerPageState();
}

class _LoyaltyScannerPageState extends State<LoyaltyScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  LoyaltyInfo? _client;
  bool _isProcessing = false;
  String? _errorMessage;
  String? _lastQr;

  // Градиенты и цвета
  static final _primaryColor = AppColors.primaryGreen;
  static final _accentColor = Color(0xFF00897B);
  static final _gradientColors = [AppColors.primaryGreen, Color(0xFF00796B)];
  static final _bonusGradient = [Color(0xFFFF6B35), Color(0xFFF7C200)];
  static final _successGradient = [Color(0xFF00b09b), Color(0xFF96c93d)];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final String? code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty || code == _lastQr) {
      return;
    }
    _lastQr = code;
    _processScan(code);
  }

  Future<void> _processScan(String qr) async {
    if (mounted) setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    try {
      final client = await LoyaltyService.addPoint(qr);
      if (mounted) {
        setState(() {
          _client = client;
        });
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Ошибка при обработке QR-кода';
        final errorString = e.toString().toLowerCase();

        if (errorString.contains('не найден') ||
            errorString.contains('not found') ||
            errorString.contains('клиент не найден')) {
          errorMessage = 'Клиент с таким QR-кодом не найден';
        } else if (errorString.contains('failed to fetch') ||
                   errorString.contains('connection') ||
                   errorString.contains('network')) {
          errorMessage = 'Ошибка подключения к серверу';
        } else if (errorString.contains('timeout')) {
          errorMessage = 'Превышено время ожидания';
        }

        if (mounted) setState(() {
          _errorMessage = errorMessage;
          _client = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _redeem() async {
    final qr = _client?.qr;
    if (qr == null) return;

    if (mounted) setState(() {
      _isProcessing = true;
    });
    try {
      final client = await LoyaltyService.redeem(qr);
      if (mounted) {
        setState(() {
          _client = client;
          _errorMessage = null;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(Icons.check_circle, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text(
                  'Баллы списаны, напиток выдан!',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: _successGradient[0],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Ошибка при списании баллов';
        final errorString = e.toString().toLowerCase();

        if (errorString.contains('failed to fetch') ||
            errorString.contains('connection') ||
            errorString.contains('network')) {
          errorMessage = 'Ошибка подключения к серверу';
        } else if (errorString.contains('timeout')) {
          errorMessage = 'Превышено время ожидания';
        } else if (errorString.contains('недостаточно') ||
                   errorString.contains('not enough')) {
          errorMessage = 'Недостаточно баллов для списания';
        }

        if (mounted) setState(() {
          _errorMessage = errorMessage;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text(errorMessage),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _resetScan() {
    if (mounted) setState(() {
      _client = null;
      _lastQr = null;
      _errorMessage = null;
    });
  }

  /// Диалог для ручного ввода QR-кода (для тестирования)
  void _showManualQrDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _gradientColors),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(Icons.qr_code_scanner, color: Colors.white, size: 24),
            ),
            SizedBox(width: 12),
            Text('Ввод QR-кода'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Введите QR-код клиента для тестирования:',
              style: TextStyle(fontSize: 14.sp, color: Colors.grey[600]),
            ),
            SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: _primaryColor.withOpacity(0.3)),
              ),
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'QR-код',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  hintText: 'например: 2d3b4112-1366-4404-...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16.w),
                  prefixIcon: Icon(Icons.qr_code, color: _primaryColor.withOpacity(0.5)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Отмена',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: _gradientColors),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: ElevatedButton(
              onPressed: () {
                final qr = controller.text.trim();
                if (qr.isNotEmpty) {
                  Navigator.pop(dialogContext);
                  _processScan(qr);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
              ),
              child: Text(
                'Начислить балл',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('Бонусы'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Кнопка ручного ввода QR (для тестирования)
          IconButton(
            icon: Icon(Icons.edit_note),
            tooltip: 'Ввести QR вручную',
            onPressed: _showManualQrDialog,
          ),
          ValueListenableBuilder(
            valueListenable: _controller.torchState,
            builder: (context, state, child) {
              return IconButton(
                icon: Icon(
                  state == TorchState.on ? Icons.flash_on : Icons.flash_off,
                ),
                onPressed: () => _controller.toggleTorch(),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          )
        ],
      ),
      body: Column(
        children: [
          // Градиентный заголовок с камерой
          Flexible(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _primaryColor,
                    _primaryColor.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32.r),
                  bottomRight: Radius.circular(32.r),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 20,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20.r),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Stack(
                          children: [
                            MobileScanner(
                              controller: _controller,
                              onDetect: _onDetect,
                            ),
                            // Рамка сканирования
                            Center(
                              child: Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.5),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(16.r),
                                ),
                              ),
                            ),
                            // Уголки рамки
                            Center(
                              child: SizedBox(
                                width: 200,
                                height: 200,
                                child: Stack(
                                  children: [
                                    // Верхний левый
                                    Positioned(
                                      top: 0.h,
                                      left: 0.w,
                                      child: _buildCorner(true, true),
                                    ),
                                    // Верхний правый
                                    Positioned(
                                      top: 0.h,
                                      right: 0.w,
                                      child: _buildCorner(true, false),
                                    ),
                                    // Нижний левый
                                    Positioned(
                                      bottom: 0.h,
                                      left: 0.w,
                                      child: _buildCorner(false, true),
                                    ),
                                    // Нижний правый
                                    Positioned(
                                      bottom: 0.h,
                                      right: 0.w,
                                      child: _buildCorner(false, false),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                  ),
                // Подсказка
                Padding(
                  padding: EdgeInsets.only(bottom: 24.h),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          color: Colors.white.withOpacity(0.9),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Наведите на QR-код клиента',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14.sp,
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
          // Нижняя часть с информацией
          Expanded(
            child: _buildDetails(),
          ),
        ],
      ),
    );
  }

  Widget _buildCorner(bool isTop, bool isLeft) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        border: Border(
          top: isTop
              ? BorderSide(color: Colors.white, width: 4)
              : BorderSide.none,
          bottom: !isTop
              ? BorderSide(color: Colors.white, width: 4)
              : BorderSide.none,
          left: isLeft
              ? BorderSide(color: Colors.white, width: 4)
              : BorderSide.none,
          right: !isLeft
              ? BorderSide(color: Colors.white, width: 4)
              : BorderSide.none,
        ),
        borderRadius: BorderRadius.only(
          topLeft: isTop && isLeft ? Radius.circular(12.r) : Radius.zero,
          topRight: isTop && !isLeft ? Radius.circular(12.r) : Radius.zero,
          bottomLeft: !isTop && isLeft ? Radius.circular(12.r) : Radius.zero,
          bottomRight: !isTop && !isLeft ? Radius.circular(12.r) : Radius.zero,
        ),
      ),
    );
  }

  Widget _buildDetails() {
    if (_isProcessing && _client == null && _errorMessage == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.2),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: CircularProgressIndicator(
                color: _primaryColor,
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Обработка...',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16.sp,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24.w),
              decoration: BoxDecoration(
                color: Colors.red[50],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline, size: 56, color: Colors.red[400]),
            ),
            SizedBox(height: 20),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16.sp,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _gradientColors),
                borderRadius: BorderRadius.circular(14.r),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.4),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _resetScan,
                icon: Icon(Icons.qr_code_scanner, color: Colors.white),
                label: Text(
                  'Сканировать снова',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final client = _client;
    if (client == null) {
      return Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _primaryColor.withOpacity(0.1),
                    _accentColor.withOpacity(0.05),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.qr_code_2,
                size: 56,
                color: _primaryColor.withOpacity(0.5),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Сканируйте QR-код',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Наведите камеру на QR-код клиента,\nчтобы начислить балл',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    // Информация о клиенте
    return SingleChildScrollView(
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Карточка клиента
          Container(
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                // Аватар
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _gradientColors,
                    ),
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryColor.withOpacity(0.3),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      client.name.isNotEmpty ? client.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 26.sp,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                // Имя и телефон
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        client.name,
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3436),
                        ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.phone, size: 16, color: Colors.grey[500]),
                          SizedBox(width: 6),
                          Text(
                            client.phone,
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Иконка проверки
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: _successGradient[0].withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    Icons.verified,
                    color: _successGradient[0],
                    size: 24,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // Карточка баллов
          Container(
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _primaryColor.withOpacity(0.05),
                  _accentColor.withOpacity(0.02),
                ],
              ),
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: _primaryColor.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10.w),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: _bonusGradient),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Icon(Icons.stars, color: Colors.white, size: 20),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Баллы',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2D3436),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: _bonusGradient),
                        borderRadius: BorderRadius.circular(12.r),
                        boxShadow: [
                          BoxShadow(
                            color: _bonusGradient[0].withOpacity(0.3),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        '${client.points}/${client.pointsRequired}',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                // Прогресс-бар
                ClipRRect(
                  borderRadius: BorderRadius.circular(10.r),
                  child: LinearProgressIndicator(
                    value: (client.points.clamp(0, client.pointsRequired)) / client.pointsRequired,
                    backgroundColor: Colors.grey[200],
                    minHeight: 12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      client.readyForRedeem ? _bonusGradient[0] : _accentColor,
                    ),
                  ),
                ),
                SizedBox(height: 16),
                // Бесплатные напитки и акция
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoChip(
                        icon: Icons.local_cafe,
                        label: 'Бесплатных',
                        value: '${client.freeDrinks}',
                        color: _successGradient[0],
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoChip(
                        icon: Icons.card_giftcard,
                        label: 'Акция',
                        value: '${client.pointsRequired}+${client.drinksToGive}',
                        color: _bonusGradient[0],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: 24),

          // Кнопка действия
          if (client.readyForRedeem)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _bonusGradient),
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [
                  BoxShadow(
                    color: _bonusGradient[0].withOpacity(0.4),
                    blurRadius: 15,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _redeem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.symmetric(vertical: 18.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.card_giftcard, color: Colors.white, size: 24),
                    SizedBox(width: 12),
                    Text(
                      'Списать баллы и выдать ${client.drinksToGive} напиток${client.drinksToGive > 1 ? "а" : ""}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16.sp,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _gradientColors),
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.4),
                    blurRadius: 15,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _resetScan,
                icon: Icon(Icons.qr_code_scanner, color: Colors.white),
                label: Text(
                  'Сканировать следующий QR',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16.sp,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.symmetric(vertical: 18.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              SizedBox(width: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

extension on List<Barcode> {
  Barcode? get firstOrNull => isEmpty ? null : this[0];
}

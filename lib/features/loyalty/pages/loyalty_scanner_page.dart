import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/logger.dart';
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
  int? _pointsAdded; // How many points were added on last scan
  int? _newBalance; // New balance after adding points

  // Drink redemption state
  Map<String, dynamic>? _redemptionInfo;
  bool _redemptionConfirmed = false;

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

    // Check if this is a drink redemption QR
    if (code.startsWith('redemption_')) {
      _processRedemptionScan(code);
    } else {
      _processScan(code);
    }
  }

  Future<void> _processScan(String qr) async {
    if (mounted) setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _pointsAdded = null;
      _newBalance = null;
    });
    try {
      // Step 1: Fetch client by QR to get their info
      final client = await LoyaltyService.fetchByQr(qr);

      // Step 2: Get employee phone for the wallet call
      final prefs = await SharedPreferences.getInstance();
      final employeePhone = prefs.getString('user_phone') ?? '';

      // Step 3: Load promo settings to know how many points per scan
      final settings = await LoyaltyService.fetchPromoSettings();
      final pointsToAdd = settings.pointsPerScan;

      // Step 4: Add points via wallet API
      final walletResult = await LoyaltyService.walletAddPoints(
        clientPhone: client.phone,
        amount: pointsToAdd,
        employeePhone: employeePhone,
        description: 'QR-сканирование',
        sourceType: 'qr_scan',
      );

      if (mounted) {
        setState(() {
          _client = client;
          _pointsAdded = pointsToAdd;
          _newBalance = walletResult['balance'] ?? 0;
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

  /// Process a drink redemption QR (prefix: redemption_)
  Future<void> _processRedemptionScan(String qrToken) async {
    if (mounted) setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _pointsAdded = null;
      _newBalance = null;
      _redemptionInfo = null;
      _redemptionConfirmed = false;
    });
    try {
      final result = await LoyaltyService.scanRedemption(qrToken: qrToken);
      final redemption = result['redemption'] as Map<String, dynamic>?;
      if (redemption == null) throw Exception('Данные выкупа не получены');

      if (mounted) setState(() {
        _redemptionInfo = redemption;
      });
    } catch (e) {
      String errorMessage = 'Ошибка при сканировании';
      final s = e.toString().toLowerCase();
      if (s.contains('not found') || s.contains('не найден')) {
        errorMessage = 'Заявка не найдена или QR недействителен';
      } else if (s.contains('already confirmed') || s.contains('уже подтверждён')) {
        errorMessage = 'Этот напиток уже был выдан';
      }
      if (mounted) setState(() { _errorMessage = errorMessage; });
    } finally {
      if (mounted) setState(() { _isProcessing = false; });
    }
  }

  /// Confirm drink delivery — deducts points from client
  Future<void> _confirmRedemption() async {
    if (_redemptionInfo == null) return;
    final redemptionId = _redemptionInfo!['id'] as String?;
    if (redemptionId == null) return;

    if (mounted) setState(() { _isProcessing = true; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final employeePhone = prefs.getString('user_phone');

      final result = await LoyaltyService.confirmRedemption(
        redemptionId: redemptionId,
        employeePhone: employeePhone,
      );

      if (mounted) setState(() {
        _redemptionConfirmed = true;
        _newBalance = result['newBalance'] as int?;
      });
    } catch (e) {
      String errorMessage = 'Ошибка подтверждения';
      final s = e.toString().toLowerCase();
      if (s.contains('insufficient') || s.contains('недостаточно')) {
        errorMessage = 'У клиента недостаточно баллов';
      }
      if (mounted) setState(() { _errorMessage = errorMessage; });
    } finally {
      if (mounted) setState(() { _isProcessing = false; });
    }
  }

  // _redeem removed — points spend via DrinkRedemptionPage (Phase 2)
  Future<void> _redeemLegacy() async {
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
      _pointsAdded = null;
      _newBalance = null;
      _redemptionInfo = null;
      _redemptionConfirmed = false;
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

          // Карточка начисленных баллов
          if (_pointsAdded != null && _newBalance != null)
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: _successGradient[0].withOpacity(0.1),
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(color: _successGradient[0].withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Icon(Icons.check_circle, color: _successGradient[0], size: 48),
                  SizedBox(height: 12),
                  Text(
                    '+$_pointsAdded баллов',
                    style: TextStyle(
                      fontSize: 24.sp,
                      fontWeight: FontWeight.bold,
                      color: _successGradient[0],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Баланс: $_newBalance',
                    style: TextStyle(
                      fontSize: 16.sp,
                      color: Color(0xFF2D3436),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else
            // Баланс клиента (если баллы ещё не начислены — fallback)
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
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: _bonusGradient),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(Icons.account_balance_wallet, color: Colors.white, size: 20),
                  ),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Баланс',
                        style: TextStyle(fontSize: 13.sp, color: Colors.grey[600]),
                      ),
                      Text(
                        '${client.loyaltyPoints} баллов',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3436),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Drink redemption info (when employee scans client's redemption QR)
          if (_redemptionInfo != null && !_redemptionConfirmed)
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Color(0xFFD4AF37).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(color: Color(0xFFD4AF37).withOpacity(0.4)),
              ),
              child: Column(
                children: [
                  Icon(Icons.local_cafe_rounded, color: Color(0xFFD4AF37), size: 48),
                  SizedBox(height: 12),
                  Text(
                    'Выдача напитка',
                    style: TextStyle(fontSize: 14.sp, color: Colors.grey[600]),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _redemptionInfo!['recipeName'] ?? 'Напиток',
                    style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold, color: Color(0xFF2D3436)),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star_rounded, color: Color(0xFFD4AF37), size: 18),
                      SizedBox(width: 4),
                      Text(
                        '${_redemptionInfo!['pointsPrice'] ?? 0} баллов',
                        style: TextStyle(fontSize: 16.sp, color: Color(0xFFD4AF37), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _confirmRedemption,
                      icon: Icon(Icons.check_circle, color: Colors.white),
                      label: Text('Подтвердить выдачу', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.sp)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _successGradient[0],
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Redemption confirmed
          if (_redemptionConfirmed)
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: _successGradient[0].withOpacity(0.1),
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(color: _successGradient[0].withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Icon(Icons.check_circle, color: _successGradient[0], size: 48),
                  SizedBox(height: 12),
                  Text(
                    'Напиток выдан!',
                    style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold, color: _successGradient[0]),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _redemptionInfo?['recipeName'] ?? '',
                    style: TextStyle(fontSize: 16.sp, color: Color(0xFF2D3436)),
                  ),
                  if (_newBalance != null) ...[
                    SizedBox(height: 8),
                    Text('Баланс клиента: $_newBalance', style: TextStyle(fontSize: 14.sp, color: Colors.grey[600])),
                  ],
                ],
              ),
            ),

          SizedBox(height: 24),

          // Кнопка "Сканировать следующий"
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

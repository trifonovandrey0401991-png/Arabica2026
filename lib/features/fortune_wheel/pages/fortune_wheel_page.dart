import 'package:flutter/material.dart';
import '../models/fortune_wheel_model.dart';
import '../services/fortune_wheel_service.dart';
import '../widgets/animated_wheel_widget.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница Колеса Удачи - Премиум версия
class FortuneWheelPage extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const FortuneWheelPage({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<FortuneWheelPage> createState() => _FortuneWheelPageState();
}

class _FortuneWheelPageState extends State<FortuneWheelPage>
    with TickerProviderStateMixin {
  List<FortuneWheelSector> _sectors = [];
  int _availableSpins = 0;
  bool _isLoading = true;
  bool _isSpinning = false;
  WheelSpinResult? _lastResult;
  final GlobalKey<AnimatedWheelWidgetState> _wheelKey = GlobalKey();

  // Анимации для эффектов
  late AnimationController _pulseController;
  late AnimationController _shimmerController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadData();
  }

  void _initAnimations() {
    // Пульсация для кнопки
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Shimmer эффект
    _shimmerController = AnimationController(
      duration: Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);

    final settings = await FortuneWheelService.getSettings();
    final spins =
        await FortuneWheelService.getAvailableSpins(widget.employeeId);

    if (mounted) {
      setState(() {
        _sectors = settings?.sectors ?? [];
        _availableSpins = spins.availableSpins;
        _isLoading = false;
      });
    }
  }

  Future<void> _spin() async {
    if (_isSpinning || _availableSpins <= 0) return;

    if (mounted) setState(() => _isSpinning = true);

    final result = await FortuneWheelService.spin(
      employeeId: widget.employeeId,
      employeeName: widget.employeeName,
    );

    if (result != null) {
      _wheelKey.currentState?.spinToSector(result.sector.index);
      _lastResult = result;
    } else {
      if (mounted) setState(() => _isSpinning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('Ошибка при прокрутке колеса'),
              ],
            ),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        );
      }
    }
  }

  void _onSpinComplete() {
    if (mounted) setState(() {
      _isSpinning = false;
      _availableSpins = _lastResult?.remainingSpins ?? 0;
    });

    if (_lastResult != null) {
      _showResultDialog(_lastResult!);
    }
  }

  void _showResultDialog(WheelSpinResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildPremiumResultDialog(result),
    );
  }

  Widget _buildPremiumResultDialog(WheelSpinResult result) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.emeraldDark, AppColors.night],
          ),
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(
            width: 2,
            color: AppColors.gold.withOpacity(0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withOpacity(0.3),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Верхняя часть с конфетти эффектом
            Container(
              padding: EdgeInsets.all(24.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.gold.withOpacity(0.2),
                    Colors.transparent,
                  ],
                ),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(22.r),
                ),
              ),
              child: Column(
                children: [
                  // Звезды анимация
                  _AnimatedStars(),
                  SizedBox(height: 16),
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [AppColors.gold, Color(0xFFFFF8DC), AppColors.gold],
                    ).createShader(bounds),
                    child: Text(
                      'ПОЗДРАВЛЯЕМ!',
                      style: TextStyle(
                        fontSize: 28.sp,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Приз
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                children: [
                  Text(
                    'Вам выпало:',
                    style: TextStyle(
                      fontSize: 16.sp,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(20.w),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          result.sector.color.withOpacity(0.3),
                          result.sector.color.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(
                        color: result.sector.color,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: result.sector.color.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                result.sector.color,
                                result.sector.color.withOpacity(0.6),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: result.sector.color.withOpacity(0.5),
                                blurRadius: 15,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.card_giftcard,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          result.sector.text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Информация
            Padding(
              padding: EdgeInsets.all(24.w),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.white.withOpacity(0.6),
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Результат записан.\nАдминистратор свяжется с вами.',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: Colors.white.withOpacity(0.6),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25.r),
                        ),
                        elevation: 8,
                        shadowColor: AppColors.gold.withOpacity(0.5),
                      ),
                      child: Text(
                        'ОТЛИЧНО!',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.emerald,
              AppColors.emeraldDark,
              AppColors.night,
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? _buildLoadingState()
              : _sectors.isEmpty
                  ? _buildNoSectorsState()
                  : _buildWheelContent(),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.gold.withOpacity(0.8),
              ),
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Загрузка колеса...',
            style: TextStyle(
              fontSize: 16.sp,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSectorsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.grey[700]!,
                  Colors.grey[800]!,
                ],
              ),
            ),
            child: Icon(
              Icons.hourglass_empty,
              size: 50,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Колесо не настроено',
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Обратитесь к администратору',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          SizedBox(height: 32),
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back, color: AppColors.gold),
            label: Text(
              'Вернуться',
              style: TextStyle(color: AppColors.gold, fontSize: 16.sp),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWheelContent() {
    return Column(
      children: [
        // Кастомный AppBar
        _buildCustomAppBar(),

        // Контент
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 16),

                // Заголовок с эффектом
                _buildHeader(),

                SizedBox(height: 8),

                // Счетчик прокруток
                _buildSpinsCounter(),

                SizedBox(height: 24),

                // Колесо
                _buildWheelSection(),

                SizedBox(height: 24),

                // Кнопка прокрутки
                _buildSpinButton(),

                SizedBox(height: 32),

                // Информационные карточки
                _buildInfoCards(),

                SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                Icons.refresh,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Иконка колеса
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.gold, AppColors.darkGold],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            Icons.casino,
            color: Colors.white,
            size: 32,
          ),
        ),
        SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [AppColors.gold, Color(0xFFFFF8DC), AppColors.gold],
          ).createShader(bounds),
          child: Text(
            'КОЛЕСО УДАЧИ',
            style: TextStyle(
              fontSize: 28.sp,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 3,
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Испытай свою удачу!',
          style: TextStyle(
            fontSize: 16.sp,
            color: Colors.white.withOpacity(0.6),
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildSpinsCounter() {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 48.w),
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: _availableSpins > 0
                  ? [
                      AppColors.gold.withOpacity(0.2),
                      AppColors.gold.withOpacity(0.1),
                      AppColors.gold.withOpacity(0.2),
                    ]
                  : [
                      Colors.grey.withOpacity(0.2),
                      Colors.grey.withOpacity(0.1),
                      Colors.grey.withOpacity(0.2),
                    ],
            ),
            borderRadius: BorderRadius.circular(30.r),
            border: Border.all(
              color: _availableSpins > 0
                  ? AppColors.gold.withOpacity(0.5)
                  : Colors.grey.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _availableSpins > 0 ? Icons.stars : Icons.hourglass_empty,
                color: _availableSpins > 0 ? AppColors.gold : Colors.grey,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                _availableSpins > 0
                    ? 'Доступно прокруток: $_availableSpins'
                    : 'Прокрутки недоступны',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: _availableSpins > 0 ? AppColors.gold : Colors.grey,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWheelSection() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Внешнее свечение
          Container(
            width: MediaQuery.of(context).size.width * 0.85 + 40,
            height: MediaQuery.of(context).size.width * 0.85 + 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withOpacity(0.3),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
          ),
          // Декоративное кольцо
          Container(
            width: MediaQuery.of(context).size.width * 0.85 + 20,
            height: MediaQuery.of(context).size.width * 0.85 + 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.gold, AppColors.darkGold, AppColors.gold],
              ),
            ),
          ),
          // Колесо
          Padding(
            padding: EdgeInsets.all(10.w),
            child: AnimatedWheelWidget(
              key: _wheelKey,
              sectors: _sectors,
              isSpinning: _isSpinning,
              onSpinComplete: _onSpinComplete,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpinButton() {
    final bool canSpin = _availableSpins > 0 && !_isSpinning;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 48.w),
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: canSpin ? _pulseAnimation.value : 1.0,
            child: Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30.r),
                gradient: canSpin
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.gold, AppColors.darkGold],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.grey[600]!, Colors.grey[700]!],
                      ),
                boxShadow: canSpin
                    ? [
                        BoxShadow(
                          color: AppColors.gold.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: canSpin ? _spin : null,
                  borderRadius: BorderRadius.circular(30.r),
                  child: Center(
                    child: _isSpinning
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white.withOpacity(0.9),
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'ВРАЩАЕМ...',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                canSpin
                                    ? Icons.casino
                                    : Icons.lock_outline,
                                color: Colors.white,
                                size: 26,
                              ),
                              SizedBox(width: 12),
                              Text(
                                canSpin ? 'КРУТИТЬ!' : 'НЕТ ПРОКРУТОК',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white.withOpacity(
                                      canSpin ? 1.0 : 0.7),
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCards() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        children: [
          // Как получить прокрутки
          _buildInfoCard(
            icon: Icons.emoji_events,
            title: 'Как получить прокрутки?',
            description:
                'Войдите в топ-3 по эффективности за месяц и получите возможность крутить колесо удачи!',
            gradient: [AppColors.indigo, AppColors.purple],
          ),
          SizedBox(height: 12),
          // Призы
          _buildInfoCard(
            icon: Icons.card_giftcard,
            title: 'Призы',
            description:
                'Выигрывайте денежные бонусы, подарки и другие приятные сюрпризы!',
            gradient: [AppColors.emeraldGreen, AppColors.emeraldGreenLight],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
    required List<Color> gradient,
  }) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: gradient[0].withOpacity(0.4),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: Colors.white.withOpacity(0.6),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Анимированные звезды для диалога результата
class _AnimatedStars extends StatefulWidget {
  _AnimatedStars();

  @override
  State<_AnimatedStars> createState() => _AnimatedStarsState();
}

class _AnimatedStarsState extends State<_AnimatedStars>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: 100,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Большая звезда в центре
              Transform.scale(
                scale: 0.9 + (_controller.value * 0.2),
                child: Icon(
                  Icons.star,
                  color: AppColors.gold,
                  size: 50,
                ),
              ),
              // Маленькие звезды
              Positioned(
                left: 10.w,
                top: 5.h,
                child: Transform.scale(
                  scale: 0.8 + ((1 - _controller.value) * 0.3),
                  child: Icon(
                    Icons.star,
                    color: AppColors.gold.withOpacity(0.7),
                    size: 20,
                  ),
                ),
              ),
              Positioned(
                right: 10.w,
                top: 10.h,
                child: Transform.scale(
                  scale: 0.7 + (_controller.value * 0.3),
                  child: Icon(
                    Icons.star,
                    color: AppColors.gold.withOpacity(0.6),
                    size: 18,
                  ),
                ),
              ),
              Positioned(
                left: 20.w,
                bottom: 0.h,
                child: Transform.scale(
                  scale: 0.6 + ((1 - _controller.value) * 0.4),
                  child: Icon(
                    Icons.star,
                    color: AppColors.gold.withOpacity(0.5),
                    size: 14,
                  ),
                ),
              ),
              Positioned(
                right: 15.w,
                bottom: 5.h,
                child: Transform.scale(
                  scale: 0.75 + (_controller.value * 0.25),
                  child: Icon(
                    Icons.star,
                    color: AppColors.gold.withOpacity(0.65),
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'z_report_training_page.dart';
import 'cigarette_training_page.dart';
import 'shift_training_page.dart';
import 'training_settings_page.dart';
import '../../coffee_machine/pages/coffee_machine_template_management_page.dart';
import '../../employees/services/user_role_service.dart';
import '../../employees/models/user_role_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Главная страница обучения ИИ - Премиум версия
class AITrainingPage extends StatefulWidget {
  const AITrainingPage({super.key});

  @override
  State<AITrainingPage> createState() => _AITrainingPageState();
}

class _AITrainingPageState extends State<AITrainingPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminRole();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  Future<void> _checkAdminRole() async {
    final roleData = await UserRoleService.loadUserRole();
    if (mounted) {
      setState(() {
        _isAdmin = roleData?.role == UserRole.admin || roleData?.role == UserRole.developer;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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
              AppColors.darkNavy,
              AppColors.navy,
              AppColors.deepBlue,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              _buildCustomAppBar(),

              // Контент
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20.w),
                  child: Column(
                    children: [
                      // Анимированная иконка
                      _buildAnimatedHeader(),

                      SizedBox(height: 32),

                      // Карточки обучения
                      // Z-отчёт — только для управляющей и разработчиков
                      if (_isAdmin)
                        _buildTrainingCard(
                          title: 'Z-отчёт',
                          description: 'Обучение распознаванию кассовых Z-отчётов',
                          icon: Icons.receipt_long,
                          gradient: [AppColors.indigo, AppColors.purple],
                          stats: '3 шаблона',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ZReportTrainingPage(),
                              ),
                            );
                          },
                        ),

                      if (_isAdmin) SizedBox(height: 16),

                      _buildTrainingCard(
                        title: 'Подсчёт сигарет',
                        description: 'Распознавание и подсчёт пачек сигарет на витрине',
                        icon: Icons.grid_view_rounded,
                        gradient: [AppColors.emeraldGreen, AppColors.emeraldGreenLight],
                        stats: 'Обучение',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CigaretteTrainingPage(),
                            ),
                          );
                        },
                      ),

                      // Пересменка - только для админов
                      if (_isAdmin) ...[
                        SizedBox(height: 16),

                        _buildTrainingCard(
                          title: 'Пересменка',
                          description: 'ИИ проверка наличия товаров на полках при пересменке',
                          icon: Icons.swap_horiz_rounded,
                          gradient: [AppColors.warning, AppColors.warningLight],
                          stats: 'Товары',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ShiftTrainingPage(),
                              ),
                            );
                          },
                        ),

                        SizedBox(height: 16),

                        _buildTrainingCard(
                          title: 'Кофемашины',
                          description: 'Шаблоны счётчиков для разных типов кофемашин',
                          icon: Icons.coffee_outlined,
                          gradient: [AppColors.gold, Color(0xFFF0C850)],
                          stats: 'Шаблоны',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CoffeeMachineTemplateManagementPage(),
                              ),
                            );
                          },
                        ),
                      ],

                      SizedBox(height: 32),

                      // Информационные карточки
                      _buildInfoSection(),

                      SizedBox(height: 24),

                      // Кнопка настроек - только для админов
                      if (_isAdmin) _buildSettingsButton(),
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
          Expanded(
            child: Text(
              'Обучение ИИ',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildAnimatedHeader() {
    return Column(
      children: [
        // Анимированная иконка мозга
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.indigo, AppColors.purple],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.indigo.withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.psychology,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            );
          },
        ),

        SizedBox(height: 20),

        // Заголовок
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [AppColors.indigo, AppColors.purpleLight, AppColors.purple],
          ).createShader(bounds),
          child: Text(
            'Машинное зрение',
            style: TextStyle(
              fontSize: 28.sp,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1,
            ),
          ),
        ),

        SizedBox(height: 8),

        Text(
          'Обучайте ИИ распознавать документы',
          style: TextStyle(
            fontSize: 15.sp,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildTrainingCard({
    required String title,
    required String description,
    required IconData icon,
    required List<Color> gradient,
    required String stats,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20.r),
          child: Padding(
            padding: EdgeInsets.all(20.w),
            child: Row(
              children: [
                // Иконка с градиентом
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(
                        color: gradient[0].withOpacity(0.4),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 32),
                ),

                SizedBox(width: 16),

                // Текст
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: Colors.white.withOpacity(0.6),
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 4.h,
                        ),
                        decoration: BoxDecoration(
                          color: gradient[0].withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Text(
                          stats,
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color: gradient[1],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Стрелка
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white.withOpacity(0.5),
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Column(
      children: [
        _buildInfoCard(
          icon: Icons.auto_awesome,
          title: 'Как это работает?',
          description:
              'Загружайте фото документов, проверяйте распознанные данные и обучайте ИИ на своих примерах.',
          gradient: [AppColors.warning, AppColors.warningLight],
        ),
        SizedBox(height: 12),
        _buildInfoCard(
          icon: Icons.trending_up,
          title: 'Улучшение точности',
          description:
              'С каждым новым образцом система становится умнее и точнее распознаёт ваши документы.',
          gradient: [AppColors.emeraldGreen, AppColors.emeraldGreenLight],
        ),
      ],
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
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white.withOpacity(0.5),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TrainingSettingsPage(
                  products: null,
                  onSettingsChanged: null,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    Icons.settings,
                    color: Colors.white.withOpacity(0.7),
                    size: 22,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Настройки обучения',
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Паттерны распознавания и параметры',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(0.3),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

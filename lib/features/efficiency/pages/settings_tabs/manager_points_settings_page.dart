import 'package:flutter/material.dart';
import '../../models/points_settings_model.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Page for configuring manager points settings (Управляющие)
///
/// Упрощённая модель оценки:
/// - confirmedPoints — баллы за проверенный отчёт (+)
/// - rejectedPenalty — штраф за непроверенный отчёт (-)
///
/// Для 3 категорий: Пересменка, Пересчет, Сдать смену
class ManagerPointsSettingsPage extends StatefulWidget {
  const ManagerPointsSettingsPage({super.key});

  @override
  State<ManagerPointsSettingsPage> createState() =>
      _ManagerPointsSettingsPageState();
}

class _ManagerPointsSettingsPageState extends State<ManagerPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;

  // Editable values for shift (Пересменка)
  double _shiftConfirmedPoints = 1.0;
  double _shiftRejectedPenalty = -2.0;

  // Editable values for recount (Пересчет)
  double _recountConfirmedPoints = 1.0;
  double _recountRejectedPenalty = -2.0;

  // Editable values for shift handover (Сдать смену)
  double _shiftHandoverConfirmedPoints = 1.0;
  double _shiftHandoverRejectedPenalty = -2.0;

  // Expanded sections
  final Map<String, bool> _expandedSections = {
    'shift': true,
    'recount': false,
    'shiftHandover': false,
  };

  // Gradient colors for this page (purple theme for managers)
  static final _gradientColors = [Color(0xFF9C27B0), Color(0xFF673AB7)];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final settings = await PointsSettingsService.getManagerPointsSettings();
      if (!mounted) return;
      setState(() {
        // Shift settings
        _shiftConfirmedPoints = settings.shiftSettings.confirmedPoints;
        _shiftRejectedPenalty = settings.shiftSettings.rejectedPenalty;
        // Recount settings
        _recountConfirmedPoints = settings.recountSettings.confirmedPoints;
        _recountRejectedPenalty = settings.recountSettings.rejectedPenalty;
        // Shift handover settings
        _shiftHandoverConfirmedPoints = settings.shiftHandoverSettings.confirmedPoints;
        _shiftHandoverRejectedPenalty = settings.shiftHandoverSettings.rejectedPenalty;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки настроек: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    if (mounted) setState(() => _isSaving = true);

    try {
      final result = await PointsSettingsService.saveManagerPointsSettings(
        shiftSettings: ManagerCategorySettings(
          confirmedPoints: _shiftConfirmedPoints,
          rejectedPenalty: _shiftRejectedPenalty,
        ),
        recountSettings: ManagerCategorySettings(
          confirmedPoints: _recountConfirmedPoints,
          rejectedPenalty: _recountRejectedPenalty,
        ),
        shiftHandoverSettings: ManagerCategorySettings(
          confirmedPoints: _shiftHandoverConfirmedPoints,
          rejectedPenalty: _shiftHandoverRejectedPenalty,
        ),
      );

      if (result != null) {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Настройки сохранены'),
                ],
              ),
              backgroundColor: Colors.green[400],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
          );
        }
      } else {
        throw Exception('Не удалось сохранить настройки');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('Баллы управляющих'),
        backgroundColor: _gradientColors[0],
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _gradientColors[0]))
          : Column(
              children: [
                // Заголовок
                SettingsHeaderCard(
                  icon: Icons.supervisor_account_outlined,
                  title: 'Оценка работы управляющих',
                  subtitle: 'Баллы за проверку отчётов',
                  gradientColors: _gradientColors,
                ),
                // Контент
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(16.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Пояснение
                        _buildInfoCard(),
                        SizedBox(height: 16),

                        // Секция: Пересменка
                        _buildCategorySection(
                          key: 'shift',
                          title: 'Пересменка',
                          icon: Icons.swap_horiz_outlined,
                          gradientColors: [Color(0xFFf093fb), Color(0xFFf5576c)],
                          confirmedPoints: _shiftConfirmedPoints,
                          rejectedPenalty: _shiftRejectedPenalty,
                          onConfirmedPointsChanged: (v) => setState(() => _shiftConfirmedPoints = v),
                          onRejectedPenaltyChanged: (v) => setState(() => _shiftRejectedPenalty = v),
                        ),
                        SizedBox(height: 12),

                        // Секция: Пересчет
                        _buildCategorySection(
                          key: 'recount',
                          title: 'Пересчет',
                          icon: Icons.inventory_2_outlined,
                          gradientColors: [Color(0xFF4facfe), Color(0xFF00f2fe)],
                          confirmedPoints: _recountConfirmedPoints,
                          rejectedPenalty: _recountRejectedPenalty,
                          onConfirmedPointsChanged: (v) => setState(() => _recountConfirmedPoints = v),
                          onRejectedPenaltyChanged: (v) => setState(() => _recountRejectedPenalty = v),
                        ),
                        SizedBox(height: 12),

                        // Секция: Сдать смену
                        _buildCategorySection(
                          key: 'shiftHandover',
                          title: 'Сдать смену',
                          icon: Icons.assignment_turned_in_outlined,
                          gradientColors: [Color(0xFF30cfd0), Color(0xFF330867)],
                          confirmedPoints: _shiftHandoverConfirmedPoints,
                          rejectedPenalty: _shiftHandoverRejectedPenalty,
                          onConfirmedPointsChanged: (v) => setState(() => _shiftHandoverConfirmedPoints = v),
                          onRejectedPenaltyChanged: (v) => setState(() => _shiftHandoverRejectedPenalty = v),
                        ),
                        SizedBox(height: 24),

                        // Save button
                        SettingsSaveButton(
                          isSaving: _isSaving,
                          onPressed: _saveSettings,
                          gradientColors: _gradientColors,
                        ),
                        SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
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
                  color: _gradientColors[0].withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(
                  Icons.info_outline,
                  color: _gradientColors[0],
                  size: 22,
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Как рассчитываются баллы',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3436),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _buildInfoRow(
            Icons.check_circle_outline,
            'Отчёт проверен',
            'Баллы начисляются за каждый подтверждённый отчёт',
            Colors.green,
          ),
          SizedBox(height: 8),
          _buildInfoRow(
            Icons.cancel_outlined,
            'Отчёт не проверен',
            'Штраф за отклонённый или непроверенный отчёт',
            Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String subtitle, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySection({
    required String key,
    required String title,
    required IconData icon,
    required List<Color> gradientColors,
    required double confirmedPoints,
    required double rejectedPenalty,
    required ValueChanged<double> onConfirmedPointsChanged,
    required ValueChanged<double> onRejectedPenaltyChanged,
  }) {
    final isExpanded = _expandedSections[key] ?? false;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withOpacity(0.15),
            blurRadius: 15,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header (clickable)
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20.r),
            child: InkWell(
              onTap: () {
                if (mounted) setState(() {
                  _expandedSections[key] = !isExpanded;
                });
              },
              borderRadius: BorderRadius.circular(20.r),
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Row(
                  children: [
                    // Icon with gradient
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradientColors,
                        ),
                        borderRadius: BorderRadius.circular(14.r),
                        boxShadow: [
                          BoxShadow(
                            color: gradientColors[0].withOpacity(0.4),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 14),
                    // Title and summary
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 17.sp,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D3436),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '+${confirmedPoints.toStringAsFixed(1)} / ${rejectedPenalty.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Expand/collapse icon
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: Duration(milliseconds: 200),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.grey[600],
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Expandable content
          AnimatedCrossFade(
            firstChild: SizedBox.shrink(),
            secondChild: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 16.h),
              child: Column(
                children: [
                  Divider(),
                  SizedBox(height: 12),
                  // Confirmed Points
                  _buildSlider(
                    title: 'Отчёт проверен',
                    subtitle: 'Баллы за подтверждённый отчёт',
                    value: confirmedPoints,
                    min: 0,
                    max: 5,
                    onChanged: onConfirmedPointsChanged,
                    accentColor: Colors.green,
                    icon: Icons.check_circle_outline,
                  ),
                  SizedBox(height: 16),
                  // Rejected Penalty
                  _buildSlider(
                    title: 'Отчёт не проверен',
                    subtitle: 'Штраф за отклонённый/пропущенный отчёт',
                    value: rejectedPenalty,
                    min: -5,
                    max: 0,
                    onChanged: onRejectedPenaltyChanged,
                    accentColor: Colors.red,
                    icon: Icons.cancel_outlined,
                  ),
                ],
              ),
            ),
            crossFadeState:
                isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required Color accentColor,
    required IconData icon,
  }) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D3436),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  value >= 0 ? '+${value.toStringAsFixed(1)}' : value.toStringAsFixed(1),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14.sp,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              inactiveTrackColor: accentColor.withOpacity(0.2),
              thumbColor: accentColor,
              overlayColor: accentColor.withOpacity(0.2),
              trackHeight: 5,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: ((max - min) * 10).toInt(),
              onChanged: onChanged,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  min.toString(),
                  style: TextStyle(fontSize: 11.sp, color: Colors.grey[500]),
                ),
                Text(
                  max.toString(),
                  style: TextStyle(fontSize: 11.sp, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

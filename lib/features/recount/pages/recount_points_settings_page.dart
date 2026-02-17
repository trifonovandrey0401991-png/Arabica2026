import 'package:flutter/material.dart';
import '../models/recount_points_model.dart';
import '../models/recount_settings_model.dart';
import '../services/recount_points_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница настройки баллов сотрудников для пересчёта
class RecountPointsSettingsPage extends StatefulWidget {
  const RecountPointsSettingsPage({super.key});

  @override
  State<RecountPointsSettingsPage> createState() => _RecountPointsSettingsPageState();
}

class _RecountPointsSettingsPageState extends State<RecountPointsSettingsPage> {
  List<RecountPoints> _employeePoints = [];
  RecountSettings _settings = RecountSettings();
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RecountPoints> get _filteredEmployees {
    if (_searchQuery.isEmpty) return _employeePoints;
    final query = _searchQuery.toLowerCase();
    return _employeePoints.where((e) =>
      e.employeeName.toLowerCase().contains(query) ||
      e.phone.contains(query)
    ).toList();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        RecountPointsService.getAllPoints(),
        RecountPointsService.getSettings(),
      ]);

      setState(() {
        _employeePoints = results[0] as List<RecountPoints>;
        _settings = results[1] as RecountSettings;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки данных', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }

  Future<void> _initializeAllPoints() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: AppColors.emeraldDark,
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 24.h),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.emerald, AppColors.emeraldDark],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20.r),
                    topRight: Radius.circular(20.r),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(16.w),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.help_outline_rounded, color: AppColors.gold, size: 32),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Инициализировать баллы?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(20.w),
                child: Column(
                  children: [
                    Text(
                      'Всем сотрудникам без баллов будет установлено значение ${_settings.defaultPoints.toInt()} баллов.\n\nСуществующие баллы не будут изменены.',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.white.withOpacity(0.7),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 14.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              side: BorderSide(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.gold,
                              foregroundColor: AppColors.night,
                              padding: EdgeInsets.symmetric(vertical: 14.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              elevation: 0,
                            ),
                            child: Text('Инициализировать', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    final count = await RecountPointsService.initializeAllPoints();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Инициализировано: $count сотрудников'),
            ],
          ),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          margin: EdgeInsets.all(16.w),
        ),
      );
      _loadData();
    }
  }

  Future<void> _openSettingsDialog() async {
    final result = await showModalBottomSheet<RecountSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GeneralSettingsBottomSheet(settings: _settings),
    );

    if (result != null) {
      final success = await RecountPointsService.updateSettings(result);
      if (success && mounted) {
        setState(() => _settings = result);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Настройки сохранены'),
              ],
            ),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }

  Future<void> _editEmployeePoints(RecountPoints employee) async {
    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditPointsBottomSheet(
        employee: employee,
        settings: _settings,
      ),
    );

    if (result != null) {
      final success = await RecountPointsService.updatePoints(
        phone: employee.phone,
        points: result,
        adminName: 'Администратор',
        employeeName: employee.employeeName,
      );

      if (success && mounted) {
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Баллы обновлены'),
              ],
            ),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Загрузка данных...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14.sp,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Карточка общих настроек
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 8.h),
          child: _buildSettingsCard(),
        ),

        // Поиск
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          child: _buildSearchField(),
        ),

        // Статистика
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          child: _buildStatsRow(),
        ),

        // Список сотрудников
        Expanded(
          child: _filteredEmployees.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: AppColors.gold,
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                    itemCount: _filteredEmployees.length,
                    itemBuilder: (context, index) {
                      final employee = _filteredEmployees[index];
                      return _buildEmployeeCard(employee, index);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.emerald, AppColors.emeraldDark],
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openSettingsDialog,
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10.w),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Icon(
                        Icons.settings_outlined,
                        color: AppColors.gold,
                        size: 22,
                      ),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Общие настройки',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Нажмите для редактирования',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white.withOpacity(0.5),
                        size: 14,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                // Показатели
                Row(
                  children: [
                    _buildSettingStat(
                      icon: Icons.quiz_outlined,
                      value: '${_settings.questionsCount}',
                      label: 'вопросов',
                    ),
                    SizedBox(width: 10),
                    _buildSettingStat(
                      icon: Icons.camera_alt_outlined,
                      value: '${_settings.basePhotos}',
                      label: 'базовых фото',
                    ),
                    SizedBox(width: 10),
                    _buildSettingStat(
                      icon: Icons.stars_outlined,
                      value: '${_settings.defaultPoints.toInt()}',
                      label: 'баллов',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingStat({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.5), size: 18),
            SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 10.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: Colors.white, fontSize: 15.sp),
        decoration: InputDecoration(
          hintText: 'Поиск по имени или телефону...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
          prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close, color: Colors.white.withOpacity(0.5), size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        ),
        cursorColor: AppColors.gold,
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildStatsRow() {
    final highCount = _filteredEmployees.where((e) => e.points >= 80).length;
    final mediumCount = _filteredEmployees.where((e) => e.points >= 60 && e.points < 80).length;
    final lowCount = _filteredEmployees.where((e) => e.points < 60).length;

    return Row(
      children: [
        _buildStatChip(highCount, 'Высокие', Color(0xFF43A047)),
        SizedBox(width: 8),
        _buildStatChip(mediumCount, 'Средние', Color(0xFFFB8C00)),
        SizedBox(width: 8),
        _buildStatChip(lowCount, 'Низкие', Color(0xFFE53935)),
        Spacer(),
        // Кнопка инициализации
        Container(
          decoration: BoxDecoration(
            color: AppColors.gold.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _initializeAllPoints,
              borderRadius: BorderRadius.circular(12.r),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_circle_outline, size: 16, color: AppColors.gold),
                    SizedBox(width: 6),
                    Text(
                      'Добавить',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip(int count, String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 13.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(28.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(
              _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.people_outline_rounded,
              size: 48,
              color: AppColors.gold.withOpacity(0.6),
            ),
          ),
          SizedBox(height: 24),
          Text(
            _searchQuery.isNotEmpty
                ? 'Сотрудники не найдены'
                : 'Нет сотрудников с баллами',
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          SizedBox(height: 8),
          if (_searchQuery.isEmpty) ...[
            Text(
              'Нажмите кнопку ниже для инициализации',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _initializeAllPoints,
              icon: Icon(Icons.add_circle_outline),
              label: Text('Инициализировать баллы'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.night,
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                elevation: 0,
              ),
            ),
          ] else
            Text(
              'Попробуйте изменить запрос',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(RecountPoints employee, int index) {
    final pointsColor = _getPointsColor(employee.points);
    final requiredPhotos = _settings.calculateRequiredPhotos(employee.points);

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          onTap: () => _editEmployeePoints(employee),
          borderRadius: BorderRadius.circular(14.r),
          splashColor: pointsColor.withOpacity(0.08),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                // Аватар с баллами
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        pointsColor,
                        pointsColor.withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Center(
                    child: Text(
                      employee.points.toInt().toString(),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20.sp,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 14),
                // Информация
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.employeeName.isNotEmpty
                            ? employee.employeeName
                            : 'Сотрудник',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15.sp,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          // Фото
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.camera_alt_outlined,
                                  size: 12,
                                  color: AppColors.gold,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '$requiredPhotos фото',
                                  style: TextStyle(
                                    color: AppColors.gold,
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 8),
                          // Телефон
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone_outlined, size: 12, color: Colors.white.withOpacity(0.3)),
                              SizedBox(width: 4),
                              Text(
                                employee.phone,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 11.sp,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                // Кнопка редактирования
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    Icons.edit_outlined,
                    color: AppColors.gold,
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

  Color _getPointsColor(double points) {
    if (points >= 80) return Color(0xFF43A047);
    if (points >= 60) return Color(0xFFFB8C00);
    if (points >= 40) return Colors.deepOrange;
    return Color(0xFFE53935);
  }
}

/// Современный Bottom Sheet для общих настроек
class _GeneralSettingsBottomSheet extends StatefulWidget {
  final RecountSettings settings;

  _GeneralSettingsBottomSheet({required this.settings});

  @override
  State<_GeneralSettingsBottomSheet> createState() => _GeneralSettingsBottomSheetState();
}

class _GeneralSettingsBottomSheetState extends State<_GeneralSettingsBottomSheet> {
  late TextEditingController _defaultPointsController;
  late TextEditingController _basePhotosController;
  late TextEditingController _stepPointsController;
  late TextEditingController _maxPhotosController;
  late TextEditingController _correctBonusController;
  late TextEditingController _incorrectPenaltyController;
  late TextEditingController _questionsCountController;

  @override
  void initState() {
    super.initState();
    _defaultPointsController = TextEditingController(text: widget.settings.defaultPoints.toInt().toString());
    _basePhotosController = TextEditingController(text: widget.settings.basePhotos.toString());
    _stepPointsController = TextEditingController(text: widget.settings.stepPoints.toInt().toString());
    _maxPhotosController = TextEditingController(text: widget.settings.maxPhotos.toString());
    _correctBonusController = TextEditingController(text: widget.settings.correctPhotoBonus.toString());
    _incorrectPenaltyController = TextEditingController(text: widget.settings.incorrectPhotoPenalty.toString());
    _questionsCountController = TextEditingController(text: widget.settings.questionsCount.toString());
  }

  @override
  void dispose() {
    _defaultPointsController.dispose();
    _basePhotosController.dispose();
    _stepPointsController.dispose();
    _maxPhotosController.dispose();
    _correctBonusController.dispose();
    _incorrectPenaltyController.dispose();
    _questionsCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ручка
          Container(
            margin: EdgeInsets.only(top: 12.h),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          // Заголовок
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 0.h),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(Icons.settings_outlined, color: AppColors.gold),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Общие настройки пересчёта',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Настройте параметры системы',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Контент
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Основные настройки', Icons.tune_rounded),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildModernField('Начальные баллы', _defaultPointsController, Icons.stars_outlined)),
                      SizedBox(width: 12),
                      Expanded(child: _buildModernField('Кол-во вопросов', _questionsCountController, Icons.quiz_outlined)),
                    ],
                  ),
                  SizedBox(height: 24),
                  _buildSectionTitle('Настройки фотографий', Icons.camera_alt_outlined),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildModernField('Базовое кол-во', _basePhotosController, Icons.photo_library_outlined)),
                      SizedBox(width: 12),
                      Expanded(child: _buildModernField('Максимум', _maxPhotosController, Icons.photo_outlined)),
                    ],
                  ),
                  SizedBox(height: 12),
                  _buildModernField('Шаг (баллов для +1 фото)', _stepPointsController, Icons.trending_down_rounded),
                  SizedBox(height: 24),
                  _buildSectionTitle('Бонусы и штрафы', Icons.balance_rounded),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildModernField(
                          'За правильное',
                          _correctBonusController,
                          Icons.add_circle_outline,
                          prefixText: '+',
                          fieldColor: Color(0xFF43A047),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: _buildModernField(
                          'За неправильное',
                          _incorrectPenaltyController,
                          Icons.remove_circle_outline,
                          prefixText: '-',
                          fieldColor: Color(0xFFE53935),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // Кнопки
          Container(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 12.h + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      final settings = RecountSettings(
                        defaultPoints: double.tryParse(_defaultPointsController.text) ?? 85,
                        basePhotos: int.tryParse(_basePhotosController.text) ?? 3,
                        stepPoints: double.tryParse(_stepPointsController.text) ?? 5,
                        maxPhotos: int.tryParse(_maxPhotosController.text) ?? 20,
                        correctPhotoBonus: double.tryParse(_correctBonusController.text) ?? 0.2,
                        incorrectPhotoPenalty: double.tryParse(_incorrectPenaltyController.text) ?? 2.5,
                        questionsCount: int.tryParse(_questionsCountController.text) ?? 30,
                      );
                      Navigator.pop(context, settings);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.night,
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Сохранить настройки',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: AppColors.gold.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, size: 18, color: AppColors.gold),
        ),
        SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14.sp,
            color: AppColors.gold,
          ),
        ),
      ],
    );
  }

  Widget _buildModernField(
    String label,
    TextEditingController controller,
    IconData icon, {
    String? prefixText,
    Color? fieldColor,
  }) {
    final color = fieldColor ?? AppColors.gold;
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp),
          prefixIcon: Icon(icon, color: color, size: 20),
          prefixText: prefixText,
          prefixStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
        ),
        keyboardType: TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: color,
        ),
        cursorColor: color,
      ),
    );
  }
}

/// Современный Bottom Sheet для редактирования баллов
class _EditPointsBottomSheet extends StatefulWidget {
  final RecountPoints employee;
  final RecountSettings settings;

  _EditPointsBottomSheet({
    required this.employee,
    required this.settings,
  });

  @override
  State<_EditPointsBottomSheet> createState() => _EditPointsBottomSheetState();
}

class _EditPointsBottomSheetState extends State<_EditPointsBottomSheet> {
  late TextEditingController _pointsController;
  double _previewPoints = 0;

  @override
  void initState() {
    super.initState();
    _previewPoints = widget.employee.points;
    _pointsController = TextEditingController(text: widget.employee.points.toInt().toString());
    _pointsController.addListener(_onPointsChanged);
  }

  @override
  void dispose() {
    _pointsController.removeListener(_onPointsChanged);
    _pointsController.dispose();
    super.dispose();
  }

  void _onPointsChanged() {
    final value = double.tryParse(_pointsController.text);
    if (value != null) {
      setState(() => _previewPoints = value.clamp(0, 100));
    }
  }

  Color _getPointsColor(double points) {
    if (points >= 80) return Color(0xFF43A047);
    if (points >= 60) return Color(0xFFFB8C00);
    if (points >= 40) return Colors.deepOrange;
    return Color(0xFFE53935);
  }

  @override
  Widget build(BuildContext context) {
    final requiredPhotos = widget.settings.calculateRequiredPhotos(_previewPoints);
    final newColor = _getPointsColor(_previewPoints);
    final oldColor = _getPointsColor(widget.employee.points);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ручка
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 20),
            // Заголовок
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        oldColor,
                        oldColor.withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Center(
                    child: Icon(Icons.person_outline, color: Colors.white),
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.employee.employeeName.isNotEmpty
                            ? widget.employee.employeeName
                            : 'Сотрудник',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        widget.employee.phone,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 13.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 24),
            // Предпросмотр изменений
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Текущие баллы
                  Column(
                    children: [
                      Text(
                        'Было',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12.sp,
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: oldColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14.r),
                          border: Border.all(color: oldColor.withOpacity(0.3)),
                        ),
                        child: Center(
                          child: Text(
                            widget.employee.points.toInt().toString(),
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.bold,
                              color: oldColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Стрелка
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white.withOpacity(0.4),
                      size: 20,
                    ),
                  ),
                  // Новые баллы
                  Column(
                    children: [
                      Text(
                        'Станет',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12.sp,
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              newColor,
                              newColor.withOpacity(0.7),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                        child: Center(
                          child: Text(
                            _previewPoints.toInt().toString(),
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            // Поле ввода
            Container(
              decoration: BoxDecoration(
                color: newColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: newColor.withOpacity(0.2)),
              ),
              child: TextField(
                controller: _pointsController,
                decoration: InputDecoration(
                  labelText: 'Новые баллы (0-100)',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  prefixIcon: Icon(Icons.stars_outlined, color: newColor),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                ),
                keyboardType: TextInputType.number,
                autofocus: true,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: newColor,
                ),
                cursorColor: newColor,
              ),
            ),
            SizedBox(height: 16),
            // Информация о фото
            Container(
              padding: EdgeInsets.all(14.w),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.gold.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(
                      Icons.camera_alt_outlined,
                      color: AppColors.gold,
                      size: 18,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Требуется фотографий',
                          style: TextStyle(
                            color: AppColors.gold.withOpacity(0.7),
                            fontSize: 12.sp,
                          ),
                        ),
                        Text(
                          '$requiredPhotos шт.',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            // Кнопки
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      final points = double.tryParse(_pointsController.text);
                      if (points != null && points >= 0 && points <= 100) {
                        Navigator.pop(context, points);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Введите число от 0 до 100'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.night,
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Сохранить баллы',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

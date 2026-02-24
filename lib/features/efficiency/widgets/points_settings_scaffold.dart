import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import 'settings_save_button_widget.dart';

/// Scaffold для страниц настроек баллов эффективности.
///
/// Обрабатывает: загрузку данных, индикатор загрузки, кнопку сохранения,
/// SnackBar'ы успеха/ошибки. Страница передаёт слайдеры и виджеты через [bodyBuilder].
class PointsSettingsScaffold extends StatefulWidget {
  final String title;
  final IconData headerIcon;
  final String headerTitle;
  final String headerSubtitle;
  final List<Color> gradientColors;

  /// Вызывается один раз при инициализации. Устанавливайте поля состояния
  /// (без вызова setState — scaffold сам управляет перестройкой).
  final Future<void> Function() onLoad;

  /// Вызывается при нажатии "Сохранить". Вернуть true если успех.
  final Future<bool> Function() onSave;

  /// Строит виджеты тела (слайдеры, временные окна, превью и т.д.).
  /// Вызывается при каждой перестройке — читает актуальные значения полей.
  final List<Widget> Function(BuildContext context) bodyBuilder;

  /// Если true, Navigator.pop после успешного сохранения.
  final bool popOnSave;

  const PointsSettingsScaffold({
    super.key,
    required this.title,
    required this.headerIcon,
    required this.headerTitle,
    required this.headerSubtitle,
    required this.gradientColors,
    required this.onLoad,
    required this.onSave,
    required this.bodyBuilder,
    this.popOnSave = false,
  });

  @override
  State<PointsSettingsScaffold> createState() => _PointsSettingsScaffoldState();
}

class _PointsSettingsScaffoldState extends State<PointsSettingsScaffold> {
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.onLoad();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('Ошибка загрузки настроек')),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    if (mounted) setState(() => _isSaving = true);
    try {
      final ok = await widget.onSave();
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Настройки сохранены'),
              ],
            ),
            backgroundColor: AppColors.emeraldGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
        );
        if (widget.popOnSave && mounted) {
          Navigator.pop(context);
        }
      } else {
        throw Exception('Не удалось сохранить настройки');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('Ошибка сохранения')),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.gold),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: AppColors.gold,
              ),
            )
          : Column(
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),
                SettingsHeaderCard(
                  icon: widget.headerIcon,
                  title: widget.headerTitle,
                  subtitle: widget.headerSubtitle,
                  gradientColors: widget.gradientColors,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(16.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...widget.bodyBuilder(context),
                        SizedBox(height: 24),
                        SettingsSaveButton(
                          isSaving: _isSaving,
                          onPressed: _save,
                          gradientColors: widget.gradientColors,
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
}

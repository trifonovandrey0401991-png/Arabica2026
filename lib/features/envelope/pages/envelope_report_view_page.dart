import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/envelope_report_model.dart';
import '../models/envelope_question_model.dart';
import '../services/envelope_report_service.dart';
import '../services/envelope_question_service.dart';
import '../../../core/utils/logger.dart';
import '../../../core/constants/api_constants.dart';
import '../../employees/services/user_role_service.dart';
import '../../ai_training/services/z_report_service.dart';
import '../../ai_training/widgets/z_report_region_overlay.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

class EnvelopeReportViewPage extends StatefulWidget {
  final EnvelopeReport report;
  final bool isAdmin;

  const EnvelopeReportViewPage({
    super.key,
    required this.report,
    this.isAdmin = false,
  });

  @override
  State<EnvelopeReportViewPage> createState() => _EnvelopeReportViewPageState();
}

class _EnvelopeReportViewPageState extends State<EnvelopeReportViewPage> {
  late EnvelopeReport _report;
  bool _isLoading = false;
  int _selectedRating = 5;
  List<EnvelopeQuestion> _questions = [];

  @override
  void initState() {
    super.initState();
    _report = widget.report;
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      final qs = await EnvelopeQuestionService.getQuestions();
      if (mounted) setState(() => _questions = qs);
    } catch (e) { Logger.error('EnvelopeReportView', 'Failed to load questions', e); }
  }

  /// Returns reference photo URL for a photo question by section and position index.
  String? _getReferencePhoto(String section, int indexInSection) {
    final sectionPhotos = _questions
        .where((q) => q.type == 'photo' && q.section == section && q.isActive)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (indexInSection < sectionPhotos.length) {
      return sectionPhotos[indexInSection].referencePhotoUrl;
    }
    return null;
  }

  void _openPhotoFullscreen(BuildContext ctx, Widget photo) {
    showDialog(
      context: ctx,
      barrierColor: Colors.black87,
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.of(dialogContext).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: photo,
                ),
              ),
              Positioned(
                top: 40,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd.MM.yyyy HH:mm').format(date);
  }

  Future<void> _confirmReport() async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 16.h),
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    SizedBox(height: 16.h),
                    Text(
                      'Подтвердить отчет',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 16.h),
                    Text(
                      'Выберите оценку:',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14.sp),
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final rating = index + 1;
                        return IconButton(
                          icon: Icon(
                            rating <= _selectedRating ? Icons.star : Icons.star_border,
                            color: AppColors.gold,
                            size: 36,
                          ),
                          onPressed: () {
                            setDialogState(() => _selectedRating = rating);
                          },
                        );
                      }),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      'Оценка: $_selectedRating',
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold, fontSize: 16.sp),
                    ),
                    SizedBox(height: 20.h),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white.withOpacity(0.7),
                              side: BorderSide(color: Colors.white.withOpacity(0.2)),
                              padding: EdgeInsets.symmetric(vertical: 14.h),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                            ),
                            child: Text('Отмена', style: TextStyle(fontSize: 15.sp)),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                            ),
                            child: Text('Подтвердить', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp)),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    if (confirm == true && mounted) {
      if (mounted) setState(() => _isLoading = true);
      try {
        String adminName = 'Администратор';
        final prefs = await SharedPreferences.getInstance();

        final userEmployeeName = prefs.getString('user_employee_name');
        final userDisplayName = prefs.getString('user_display_name');
        final userName = prefs.getString('user_name');

        if (userEmployeeName != null && userEmployeeName.isNotEmpty) {
          adminName = userEmployeeName;
        } else if (userDisplayName != null && userDisplayName.isNotEmpty) {
          adminName = userDisplayName;
        } else if (userName != null && userName.isNotEmpty) {
          adminName = userName;
        } else {
          final roleData = await UserRoleService.loadUserRole();
          if (roleData != null && roleData.displayName.isNotEmpty) {
            adminName = roleData.displayName;
          }
        }

        Logger.debug('Podtverzhdeniye otcheta: $adminName');

        final updated = await EnvelopeReportService.confirmReport(
          _report.id,
          adminName,
          _selectedRating,
        );
        if (updated != null && mounted) {
          if (mounted) setState(() => _report = updated);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Отчет подтвержден!'),
              backgroundColor: AppColors.success,
            ),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Не удалось подтвердить отчет. Попробуйте ещё раз.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } catch (e) {
        Logger.error('Ошибка подтверждения отчета', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppColors.error),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _deleteReport() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        title: Text('Удалить отчет?', style: TextStyle(color: Colors.white)),
        content: Text('Это действие нельзя отменить.', style: TextStyle(color: Colors.white.withOpacity(0.7))),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      if (mounted) setState(() => _isLoading = true);
      try {
        final success = await EnvelopeReportService.deleteReport(_report.id);
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Отчет удален'), backgroundColor: AppColors.success),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        Logger.error('Ошибка удаления отчета', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppColors.error),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _showPhoto(String? url, String title, {
    Map<String, Map<String, double>>? fieldRegions,
    double revenue = 0,
    double cash = 0,
    int ofdNotSent = 0,
  }) {
    if (url == null) return;
    final hasRegions = fieldRegions != null && fieldRegions.isNotEmpty;

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: AppColors.emerald,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
              ),
              child: Row(
                children: [
                  Icon(Icons.photo, color: AppColors.gold, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.sp),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white.withOpacity(0.7), size: 20),
                    onPressed: () => Navigator.pop(dialogContext),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Photo
            ClipRRect(
              child: InteractiveViewer(
                child: hasRegions
                    ? Stack(
                        children: [
                          AppCachedImage(
                            imageUrl: url,
                            fit: BoxFit.contain,
                            errorWidget: (context, error, stackTrace) => SizedBox(
                              height: 200,
                              child: Center(child: Icon(Icons.error, size: 48, color: AppColors.error)),
                            ),
                          ),
                          Positioned.fill(
                            child: ZReportRegionOverlay(fieldRegions: fieldRegions),
                          ),
                        ],
                      )
                    : AppCachedImage(
                        imageUrl: url,
                        fit: BoxFit.contain,
                        errorWidget: (context, error, stackTrace) => SizedBox(
                          height: 200,
                          child: Center(child: Icon(Icons.error, size: 48, color: AppColors.error)),
                        ),
                      ),
              ),
            ),
            // AI training buttons (admin only + regions exist)
            if (widget.isAdmin && hasRegions)
              Padding(
                padding: EdgeInsets.all(12.w),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: Icon(Icons.close, size: 18),
                        label: Text('Отклонить'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white.withOpacity(0.5),
                          side: BorderSide(color: Colors.white.withOpacity(0.2)),
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _trainWithPhoto(
                          dialogContext,
                          url,
                          fieldRegions,
                          revenue,
                          cash,
                          ofdNotSent,
                        ),
                        icon: Icon(Icons.school, size: 18),
                        label: Text('Обучить'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.turquoise,
                          foregroundColor: AppColors.night,
                          padding: EdgeInsets.symmetric(vertical: 12.h),
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

  /// Скачать фото и сохранить как training sample для AI
  Future<void> _trainWithPhoto(
    BuildContext dialogContext,
    String photoUrl,
    Map<String, Map<String, double>> fieldRegions,
    double revenue,
    double cash,
    int ofdNotSent,
  ) async {
    showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: AppColors.gold)),
    );

    try {
      Logger.debug('Обучение AI: скачиваю фото $photoUrl');
      final response = await http.get(
        Uri.parse(photoUrl),
        headers: ApiConstants.headersWithApiKey,
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('Не удалось скачать фото (${response.statusCode})');
      }
      Logger.debug('Обучение AI: фото скачано, ${response.bodyBytes.length} байт');

      final compressedBase64 = await ZReportService.compressImage(response.bodyBytes);
      Logger.debug('Обучение AI: сжато, base64 длина ${compressedBase64.length}');

      final saved = await ZReportService.saveSample(
        imageBase64: compressedBase64,
        totalSum: revenue,
        cashSum: cash,
        ofdNotSent: ofdNotSent,
        resourceKeys: 0,
        shopAddress: _report.shopAddress,
        employeeName: _report.employeeName,
        fieldRegions: fieldRegions,
      );

      if (!mounted || !dialogContext.mounted) return;
      Navigator.of(dialogContext).pop(); // закрыть загрузку
      if (!dialogContext.mounted) return;
      Navigator.of(dialogContext).pop(); // закрыть фото-диалог

      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Фото сохранено для обучения AI'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        Logger.error('Обучение AI: saveSample вернул false');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось сохранить — проверьте подключение'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      Logger.error('Ошибка сохранения для обучения AI', e);
      if (mounted && dialogContext.mounted) {
        Navigator.of(dialogContext).pop(); // закрыть загрузку
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        title: Text('Отчет конверта'),
        backgroundColor: AppColors.emerald,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.isAdmin && _report.status == 'pending')
            IconButton(
              icon: Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: _isLoading ? null : _deleteReport,
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.gold))
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  SizedBox(height: 12.h),
                  _buildStatusCard(),
                  if (_report.hasEditedZReport) ...[
                    SizedBox(height: 12.h),
                    _buildEditedBadge(),
                  ],
                  SizedBox(height: 12.h),
                  _buildOOOSection(),
                  SizedBox(height: 12.h),
                  _buildIPSection(),
                  SizedBox(height: 12.h),
                  _buildTotalCard(),
                  SizedBox(height: 12.h),
                  _buildPhotosSection(),
                  SizedBox(height: 8.h),
                  if (widget.isAdmin && _report.status == 'pending')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _confirmReport,
                        icon: Icon(Icons.check_circle, size: 20),
                        label: Text('Подтвердить отчет', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: AppColors.night,
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        ),
                      ),
                    ),
                  SizedBox(height: 16.h),
                ],
              ),
            ),
    );
  }

  Widget _buildEditedBadge() {
    final parts = <String>[];
    if (_report.oooZReportEdited) parts.add('ООО');
    if (_report.ipZReportEdited) parts.add('ИП');

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note, color: AppColors.warning, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Z-отчёт исправлен вручную',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.sp,
                  ),
                ),
                Text(
                  'Секции: ${parts.join(', ')}',
                  style: TextStyle(
                    color: AppColors.warning.withOpacity(0.7),
                    fontSize: 11.sp,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.emerald, AppColors.emeraldDark],
        ),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.person, color: AppColors.gold, size: 22),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  _report.employeeName,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          _buildHeaderRow(
            Icons.store,
            _report.shopAddress,
            AppColors.turquoise,
          ),
          SizedBox(height: 6.h),
          _buildHeaderRow(
            _report.shiftType == 'morning' ? Icons.wb_sunny : Icons.nights_stay,
            '${_report.shiftTypeText} смена',
            _report.shiftType == 'morning' ? AppColors.gold : AppColors.purpleLight,
          ),
          SizedBox(height: 6.h),
          _buildHeaderRow(
            Icons.access_time,
            _formatDate(_report.createdAt),
            Colors.white.withOpacity(0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(IconData icon, String text, Color iconColor) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 18),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13.sp),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    final isConfirmed = _report.status == 'confirmed';
    final isExpired = _report.isExpired;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (isConfirmed) {
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle;
      statusText = _report.statusText;
    } else if (isExpired) {
      statusColor = AppColors.error;
      statusIcon = Icons.warning;
      statusText = 'Просрочен';
    } else {
      statusColor = AppColors.warning;
      statusIcon = Icons.pending;
      statusText = _report.statusText;
    }

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    fontSize: 15.sp,
                  ),
                ),
                if (isConfirmed && _report.confirmedByAdmin != null) ...[
                  SizedBox(height: 4.h),
                  Text(
                    'Подтвердил: ${_report.confirmedByAdmin}',
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.sp),
                  ),
                  if (_report.confirmedAt != null)
                    Text(
                      _formatDate(_report.confirmedAt!),
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11.sp),
                    ),
                ],
                if (_report.rating != null) ...[
                  SizedBox(height: 4.h),
                  Row(
                    children: [
                      Text('Оценка: ', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.sp)),
                      ...List.generate(5, (index) {
                        return Icon(
                          index < _report.rating! ? Icons.star : Icons.star_border,
                          color: AppColors.gold,
                          size: 16,
                        );
                      }),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOOOSection() {
    return _buildSection(
      title: 'ООО',
      accentColor: AppColors.turquoise,
      isEdited: _report.oooZReportEdited,
      zReportPhotoUrl: _report.oooZReportPhotoUrl,
      envelopePhotoUrl: _report.oooEnvelopePhotoUrl,
      fieldRegions: _report.oooFieldRegions,
      revenue: _report.oooRevenue,
      cash: _report.oooCash,
      ofdNotSent: _report.oooOfdNotSent,
      envelopeAmount: _report.oooEnvelopeAmount,
      zReportTitle: 'Z-отчет ООО',
      envelopeTitle: 'Конверт ООО',
    );
  }

  Widget _buildIPSection() {
    return _buildSection(
      title: 'ИП',
      accentColor: AppColors.purpleLight,
      isEdited: _report.ipZReportEdited,
      zReportPhotoUrl: _report.ipZReportPhotoUrl,
      envelopePhotoUrl: _report.ipEnvelopePhotoUrl,
      fieldRegions: _report.ipFieldRegions,
      revenue: _report.ipRevenue,
      cash: _report.ipCash,
      ofdNotSent: _report.ipOfdNotSent,
      envelopeAmount: _report.ipEnvelopeAmount,
      zReportTitle: 'Z-отчет ИП',
      envelopeTitle: 'Конверт ИП',
      expenses: _report.expenses,
      totalExpenses: _report.totalExpenses,
    );
  }

  Widget _buildSection({
    required String title,
    required Color accentColor,
    required bool isEdited,
    required String? zReportPhotoUrl,
    required String? envelopePhotoUrl,
    required Map<String, Map<String, double>>? fieldRegions,
    required double revenue,
    required double cash,
    required int ofdNotSent,
    required double envelopeAmount,
    required String zReportTitle,
    required String envelopeTitle,
    List<ExpenseItem>? expenses,
    double totalExpenses = 0,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.emeraldDark.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: accentColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
                if (isEdited) ...[
                  SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_note, color: AppColors.warning, size: 14),
                        SizedBox(width: 3),
                        Text(
                          'Исправлен',
                          style: TextStyle(color: AppColors.warning, fontSize: 10.sp, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
                Spacer(),
                if (zReportPhotoUrl != null)
                  _photoButton(
                    icon: Icons.receipt_long,
                    label: 'Z-отчет',
                    color: accentColor,
                    onPressed: () => _showPhoto(
                      zReportPhotoUrl,
                      zReportTitle,
                      fieldRegions: fieldRegions,
                      revenue: revenue,
                      cash: cash,
                      ofdNotSent: ofdNotSent,
                    ),
                  ),
                if (envelopePhotoUrl != null) ...[
                  SizedBox(width: 6),
                  _photoButton(
                    icon: Icons.mail,
                    label: 'Конверт',
                    color: accentColor,
                    onPressed: () => _showPhoto(envelopePhotoUrl, envelopeTitle),
                  ),
                ],
              ],
            ),
          ),
          // Data rows
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 14.h),
            child: Column(
              children: [
                _buildInfoRow('Выручка:', '${revenue.toStringAsFixed(0)} руб'),
                _buildInfoRow('Наличные:', '${cash.toStringAsFixed(0)} руб'),
                if (expenses != null && expenses.isNotEmpty) ...[
                  SizedBox(height: 8.h),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Расходы:',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.7), fontSize: 13.sp),
                    ),
                  ),
                  ...(expenses.map((e) => Padding(
                    padding: EdgeInsets.only(left: 12.w, top: 4.h),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '- ${e.supplierName}',
                                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13.sp),
                              ),
                              if (e.comment != null && e.comment!.isNotEmpty)
                                Text(
                                  e.comment!,
                                  style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.4)),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '-${e.amount.toStringAsFixed(0)} руб',
                          style: TextStyle(color: AppColors.errorLight, fontSize: 13.sp),
                        ),
                      ],
                    ),
                  ))),
                  SizedBox(height: 4.h),
                  _buildInfoRow(
                    'Итого расходов:',
                    '-${totalExpenses.toStringAsFixed(0)} руб',
                    color: AppColors.errorLight,
                  ),
                ],
                Padding(
                  padding: EdgeInsets.only(top: 8.h),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'В конверте:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                            fontSize: 14.sp,
                          ),
                        ),
                        Text(
                          '${envelopeAmount.toStringAsFixed(0)} руб',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                            fontSize: 16.sp,
                          ),
                        ),
                      ],
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

  Widget _photoButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11.sp, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ФОТО-ВОПРОСЫ
  // ──────────────────────────────────────────────────────────────────────────

  /// Строит блок со всеми фото-ответами сотрудника (аналог пересменки)
  Widget _buildPhotosSection() {
    // Собираем 4 элемента: title, photoUrl?, referencePhotoUrl?
    final items = <_PhotoItem>[
      _PhotoItem(
        title: 'ООО: Z-отчёт',
        photoUrl: _report.oooZReportPhotoUrl,
        referencePhotoUrl: _getReferencePhoto('ooo', 0),
      ),
      _PhotoItem(
        title: 'ООО: Конверт',
        photoUrl: _report.oooEnvelopePhotoUrl,
        referencePhotoUrl: _getReferencePhoto('ooo', 1),
      ),
      _PhotoItem(
        title: 'ИП: Z-отчёт',
        photoUrl: _report.ipZReportPhotoUrl,
        referencePhotoUrl: _getReferencePhoto('ip', 0),
      ),
      _PhotoItem(
        title: 'ИП: Конверт',
        photoUrl: _report.ipEnvelopePhotoUrl,
        referencePhotoUrl: _getReferencePhoto('ip', 1),
      ),
    ].where((i) => i.photoUrl != null).toList();

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 4.h),
          child: Row(
            children: [
              Icon(Icons.photo_library_outlined, color: AppColors.gold, size: 18),
              SizedBox(width: 8),
              Text(
                'Фотографии',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 6.h),
        ...items.map((item) => Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: _buildAnswerPhotoCard(item),
        )),
      ],
    );
  }

  Widget _buildAnswerPhotoCard(_PhotoItem item) {
    final hasReference = item.referencePhotoUrl != null && item.referencePhotoUrl!.isNotEmpty;

    final employeePhotoWidget = AppCachedImage(
      imageUrl: item.photoUrl!,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => Container(
        color: AppColors.emeraldDark,
        child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 40),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.emeraldDark.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок вопроса
          Padding(
            padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 10.h),
            child: Text(
              item.title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          if (hasReference)
            // Два фото рядом: слева эталон, справа от сотрудника
            Padding(
              padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 14.h),
              child: Row(
                children: [
                  // Эталонное фото
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Эталон',
                          style: TextStyle(color: Colors.white38, fontSize: 10.sp),
                        ),
                        SizedBox(height: 4.h),
                        GestureDetector(
                          onTap: () => _openPhotoFullscreen(
                            context,
                            AppCachedImage(
                              imageUrl: item.referencePhotoUrl!,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => Icon(Icons.broken_image_outlined, color: Colors.white38, size: 40),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.r),
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: AppCachedImage(
                                imageUrl: item.referencePhotoUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: AppColors.emeraldDark,
                                  child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 32),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 10.w),
                  // Фото сотрудника
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Фото',
                          style: TextStyle(color: Colors.white38, fontSize: 10.sp),
                        ),
                        SizedBox(height: 4.h),
                        GestureDetector(
                          onTap: () => _openPhotoFullscreen(context, employeePhotoWidget),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.r),
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: employeePhotoWidget,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            // Нет эталона — фото на всю ширину
            GestureDetector(
              onTap: () => _openPhotoFullscreen(context, employeePhotoWidget),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: employeePhotoWidget,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTotalCard() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.gold.withOpacity(0.15), AppColors.gold.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'ИТОГО:',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          Text(
            '${_report.totalEnvelopeAmount.toStringAsFixed(0)} руб',
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: Colors.white.withOpacity(0.6),
              fontSize: 13.sp,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? Colors.white,
              fontSize: 14.sp,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoItem {
  final String title;
  final String? photoUrl;
  final String? referencePhotoUrl;

  const _PhotoItem({
    required this.title,
    required this.photoUrl,
    this.referencePhotoUrl,
  });
}

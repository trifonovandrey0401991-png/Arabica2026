import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/coffee_machine_report_model.dart';
import '../services/coffee_machine_report_service.dart';
import '../../../core/constants/api_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../employees/services/user_role_service.dart';
import '../../../shared/widgets/app_cached_image.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Детальный просмотр отчёта по счётчику кофемашин
class CoffeeMachineReportViewPage extends StatefulWidget {
  final CoffeeMachineReport report;

  const CoffeeMachineReportViewPage({super.key, required this.report});

  @override
  State<CoffeeMachineReportViewPage> createState() => _CoffeeMachineReportViewPageState();
}

class _CoffeeMachineReportViewPageState extends State<CoffeeMachineReportViewPage> {
  bool _isConfirming = false;
  int _selectedRating = 0;
  final Set<String> _trainedReadings = {}; // templateIds уже обученных

  /// Получить полный URL фото (если уже полный — вернуть как есть)
  String _photoUrl(String? url) {
    if (url == null) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '${ApiConstants.serverUrl}$url';
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;

    return Scaffold(
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
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoCard(report),
                      SizedBox(height: 16),
                      _buildReadingsSection(report),
                      SizedBox(height: 16),
                      _buildComputerSection(report),
                      SizedBox(height: 16),
                      _buildVerificationSection(report),
                      if (report.status == 'pending') ...[
                        SizedBox(height: 24),
                        _buildConfirmSection(),
                      ],
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

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back, color: Colors.white),
          ),
          Icon(Icons.coffee_outlined, color: AppColors.gold, size: 22),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Отчёт по счётчику',
              style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
          ),
          // Статус
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: _getStatusColor().withOpacity(0.15),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              widget.report.statusText,
              style: TextStyle(color: _getStatusColor(), fontSize: 12.sp, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (widget.report.status) {
      case 'confirmed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'failed':
      case 'expired':
        return Colors.red;
      default:
        return AppColors.gold;
    }
  }

  Widget _buildInfoCard(CoffeeMachineReport report) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.person, 'Сотрудник', report.employeeName),
          _buildInfoRow(Icons.store, 'Магазин', report.shopAddress),
          _buildInfoRow(Icons.schedule, 'Смена', report.shiftTypeText),
          _buildInfoRow(Icons.calendar_today, 'Дата', report.date),
          Builder(builder: (_) {
            final lc = report.createdAt.toLocal();
            return _buildInfoRow(
              Icons.access_time,
              'Отправлен',
              '${lc.day.toString().padLeft(2, '0')}.${lc.month.toString().padLeft(2, '0')}.${lc.year}, '
              '${lc.hour.toString().padLeft(2, '0')}:${lc.minute.toString().padLeft(2, '0')}',
            );
          }),
          if (report.confirmedByAdmin != null)
            _buildInfoRow(Icons.verified, 'Проверил', report.confirmedByAdmin!),
          if (report.rating != null)
            _buildInfoRow(Icons.star, 'Оценка', '${report.rating}/5'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.4), size: 18),
          SizedBox(width: 8),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp)),
          Spacer(),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadingsSection(CoffeeMachineReport report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Показания машин',
          style: TextStyle(color: AppColors.gold, fontSize: 16.sp, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 10),
        ...report.readings.map((reading) => _buildReadingCard(reading)),
      ],
    );
  }

  Widget _buildReadingCard(CoffeeMachineReading reading) {
    final isTrained = _trainedReadings.contains(reading.templateId);
    final canTrain = reading.photoUrl != null &&
        (reading.wasManuallyEdited || reading.selectedRegion != null);

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: canTrain
              ? Colors.orange.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.coffee, color: AppColors.gold, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  reading.machineName,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp),
                ),
              ),
              Text(
                '${reading.confirmedNumber}',
                style: TextStyle(color: AppColors.gold, fontSize: 20.sp, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (reading.wasManuallyEdited) ...[
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6.r),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit, color: Colors.orange, size: 14),
                  SizedBox(width: 4),
                  Text(
                    reading.aiReadNumber != null
                        ? 'Исправлено вручную (ИИ: ${reading.aiReadNumber})'
                        : 'Введено вручную',
                    style: TextStyle(color: Colors.orange, fontSize: 12.sp),
                  ),
                ],
              ),
            ),
          ],
          if (reading.selectedRegion != null && !reading.wasManuallyEdited) ...[
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6.r),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.crop_free, color: Colors.blue, size: 14),
                  SizedBox(width: 4),
                  Text('Область выделена сотрудником', style: TextStyle(color: Colors.blue, fontSize: 12.sp)),
                ],
              ),
            ),
          ],
          // Фото с красным квадратом (selectedRegion)
          if (reading.photoUrl != null) ...[
            SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8.r),
              child: reading.selectedRegion != null
                  ? _buildPhotoWithRegion(reading.photoUrl!, reading.selectedRegion!)
                  : AppCachedImage(
                      imageUrl: _photoUrl(reading.photoUrl),
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        height: 80,
                        color: Colors.white.withOpacity(0.04),
                        child: Center(child: Icon(Icons.broken_image, color: Colors.white24)),
                      ),
                    ),
            ),
          ],
          // Кнопка "Обучить ИИ" — если есть что обучать
          if (canTrain && !isTrained) ...[
            SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _trainOcr(reading),
                icon: Icon(Icons.school, color: AppColors.gold, size: 18),
                label: Text('Обучить ИИ', style: TextStyle(color: AppColors.gold, fontSize: 13.sp)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.gold.withOpacity(0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                  padding: EdgeInsets.symmetric(vertical: 8.h),
                ),
              ),
            ),
          ],
          if (isTrained) ...[
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 16),
                SizedBox(width: 4),
                Text('Обучено', style: TextStyle(color: Colors.green, fontSize: 12.sp)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Фото с красным квадратом выделенной области
  Widget _buildPhotoWithRegion(String photoUrl, Map<String, double> region) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = 150.0;
        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              AppCachedImage(
                imageUrl: _photoUrl(photoUrl),
                height: height,
                width: width,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  height: 80,
                  color: Colors.white.withOpacity(0.04),
                  child: Center(child: Icon(Icons.broken_image, color: Colors.white24)),
                ),
              ),
              // Красный квадрат
              Positioned(
                left: (region['x'] ?? 0) * width,
                top: (region['y'] ?? 0) * height,
                width: (region['width'] ?? 0) * width,
                height: (region['height'] ?? 0) * height,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.red, width: 2.5),
                    color: Colors.red.withOpacity(0.1),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Обучить ИИ на этом фото
  Future<void> _trainOcr(CoffeeMachineReading reading) async {
    try {
      // Получить имя админа
      String adminName = 'Администратор';
      final prefs = await SharedPreferences.getInstance();
      adminName = prefs.getString('user_employee_name') ??
          prefs.getString('user_display_name') ??
          prefs.getString('user_name') ??
          'Администратор';

      final body = jsonEncode({
        'photoUrl': reading.photoUrl,
        'correctNumber': reading.confirmedNumber,
        'selectedRegion': reading.selectedRegion,
        'preset': 'standard', // дефолтный пресет, сервер уточнит по templateId
        'templateId': reading.templateId,
        'machineName': reading.machineName,
        'shopAddress': widget.report.shopAddress,
        'trainedBy': adminName,
      });

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/coffee-machine/training'),
        headers: ApiConstants.headersWithApiKey,
        body: body,
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) setState(() => _trainedReadings.add(reading.templateId));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Фото отправлено на обучение'), backgroundColor: Colors.green),
          );
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка обучения'), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildComputerSection(CoffeeMachineReport report) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.computer, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Text(
                'Компьютер',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp),
              ),
              Spacer(),
              Text(
                report.computerNumber.toStringAsFixed(2),
                style: TextStyle(color: Colors.blue, fontSize: 20.sp, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (report.computerPhotoUrl != null) ...[
            SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8.r),
              child: AppCachedImage(
                imageUrl: _photoUrl(report.computerPhotoUrl),
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  height: 80,
                  color: Colors.white.withOpacity(0.04),
                  child: Center(child: Icon(Icons.broken_image, color: Colors.white24)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerificationSection(CoffeeMachineReport report) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: report.hasDiscrepancy
            ? Colors.orange.withOpacity(0.1)
            : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: report.hasDiscrepancy
              ? Colors.orange.withOpacity(0.3)
              : Colors.green.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Сумма машин', style: TextStyle(color: Colors.white70, fontSize: 13.sp)),
              Text('+${report.sumOfMachines}', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Компьютер', style: TextStyle(color: Colors.white70, fontSize: 13.sp)),
              Text(report.computerNumber.toStringAsFixed(2), style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Итого', style: TextStyle(color: Colors.white70, fontSize: 13.sp)),
              Text(
                (report.computerNumber + report.sumOfMachines).toStringAsFixed(2),
                style: TextStyle(
                  color: report.hasDiscrepancy ? Colors.orange : Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Divider(color: Colors.white24, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                report.hasDiscrepancy ? Icons.warning_amber_rounded : Icons.check_circle,
                color: report.hasDiscrepancy ? Colors.orange : Colors.green,
                size: 22,
              ),
              SizedBox(width: 8),
              Text(
                report.hasDiscrepancy
                    ? 'Не сходится: ${report.discrepancyAmount.toStringAsFixed(2)}'
                    : 'Счётчик сходится!',
                style: TextStyle(
                  color: report.hasDiscrepancy ? Colors.orange : Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.sp,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmSection() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Оценка', style: TextStyle(color: AppColors.gold, fontSize: 16.sp, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          // Рейтинг
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starNum = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _selectedRating = starNum),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                  child: Icon(
                    starNum <= _selectedRating ? Icons.star : Icons.star_border,
                    color: AppColors.gold,
                    size: 36,
                  ),
                ),
              );
            }),
          ),
          SizedBox(height: 16),
          // Кнопки
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isConfirming ? null : _rejectReport,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red),
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                  ),
                  child: Text('Отклонить', style: TextStyle(color: Colors.red)),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isConfirming || _selectedRating == 0 ? null : _confirmReport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                  ),
                  child: _isConfirming
                      ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Подтвердить', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReport() async {
    if (mounted) setState(() => _isConfirming = true);
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
      final result = await CoffeeMachineReportService.confirmReport(
        widget.report.id,
        adminName,
        _selectedRating,
      );

      if (!mounted) return;
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Отчёт подтверждён'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка подтверждения'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  Future<void> _rejectReport() async {
    if (mounted) setState(() => _isConfirming = true);
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
      final result = await CoffeeMachineReportService.rejectReportWithPush(
        id: widget.report.id,
        adminName: adminName,
        employeePhone: '',
        comment: 'Отклонено',
      );

      if (!mounted) return;
      if (result) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Отчёт отклонён'), backgroundColor: Colors.orange),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shift_transfer_model.dart';
import '../models/work_schedule_model.dart';
import '../services/shift_transfer_service.dart';
import '../../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница заявок на передачу смен (для раздела Отчёты)
class ShiftTransferRequestsPage extends StatefulWidget {
  const ShiftTransferRequestsPage({super.key});

  @override
  State<ShiftTransferRequestsPage> createState() => _ShiftTransferRequestsPageState();
}

class _ShiftTransferRequestsPageState extends State<ShiftTransferRequestsPage> {
  List<ShiftTransferRequest> _notifications = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (mounted) setState(() {
      _isLoading = true;
    });

    try {
      final notifications = await ShiftTransferService.getAdminRequests();
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки заявок', e);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
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
              // Custom AppBar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Заявки на смены',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadNotifications,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : _notifications.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.check_circle_outline, size: 40, color: Colors.white.withOpacity(0.3)),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Нет заявок на передачу смен',
                                  style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.5)),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Здесь появятся заявки, требующие вашего одобрения',
                                  style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.3)),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadNotifications,
                            color: AppColors.gold,
                            backgroundColor: AppColors.emeraldDark,
                            child: ListView.builder(
                              padding: EdgeInsets.all(16.w),
                              itemCount: _notifications.length,
                              itemBuilder: (context, index) {
                                final request = _notifications[index];
                                return _buildNotificationCard(request);
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(ShiftTransferRequest request) {
    final isUnread = !request.isReadByAdmin;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isUnread ? AppColors.gold.withOpacity(0.5) : Colors.white.withOpacity(0.1),
          width: isUnread ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () async {
            if (isUnread) {
              final prefs = await SharedPreferences.getInstance();
              final phone = prefs.getString('user_phone') ?? prefs.getString('userPhone');
              await ShiftTransferService.markAsRead(request.id, phone: phone);
              _loadNotifications();
            }
          },
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Заголовок с индикатором непрочитанного
                Row(
                  children: [
                    if (isUnread)
                      Container(
                        width: 10,
                        height: 10,
                        margin: EdgeInsets.only(right: 8.w),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        'Заявка на передачу смены',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16.sp,
                          color: isUnread ? AppColors.gold : Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        'Ожидает одобрения',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Colors.orange[300],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Divider(color: Colors.white.withOpacity(0.1), height: 1),
                SizedBox(height: 12),

                // Информация о передаче
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Передаёт:',
                            style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.4)),
                          ),
                          SizedBox(height: 4),
                          Text(
                            request.fromEmployeeName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14.sp,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward, color: Colors.white.withOpacity(0.3)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            request.acceptedBy.length > 1 ? 'Принявшие:' : 'Принимает:',
                            style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.4)),
                          ),
                          SizedBox(height: 4),
                          if (request.acceptedBy.length > 1)
                            Text(
                              '${request.acceptedBy.length} чел.',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14.sp,
                                color: AppColors.gold,
                              ),
                              textAlign: TextAlign.right,
                            )
                          else
                            Text(
                              request.acceptedBy.isNotEmpty
                                  ? request.acceptedBy.first.employeeName
                                  : (request.acceptedByEmployeeName ?? 'Неизвестно'),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14.sp,
                                color: Colors.white.withOpacity(0.9),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Список принявших (если несколько)
                if (request.acceptedBy.length > 1) ...[
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.people, size: 16, color: AppColors.gold),
                            SizedBox(width: 8),
                            Text(
                              'Готовы принять смену:',
                              style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                                color: AppColors.gold,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        ...request.acceptedBy.map((accepted) => Padding(
                          padding: EdgeInsets.only(bottom: 4.h),
                          child: Row(
                            children: [
                              Icon(Icons.person, size: 14, color: Colors.white.withOpacity(0.4)),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  accepted.employeeName,
                                  style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.7)),
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: 12),

                // Детали смены
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        Icons.calendar_today,
                        'Дата:',
                        '${request.shiftDate.day}.${request.shiftDate.month.toString().padLeft(2, '0')}.${request.shiftDate.year}',
                      ),
                      SizedBox(height: 8),
                      _buildDetailRow(
                        Icons.access_time,
                        'Смена:',
                        request.shiftType.label,
                      ),
                      SizedBox(height: 8),
                      _buildDetailRow(
                        Icons.store,
                        'Магазин:',
                        request.shopName.isNotEmpty ? request.shopName : request.shopAddress,
                      ),
                    ],
                  ),
                ),

                // Комментарий
                if (request.comment != null && request.comment!.isNotEmpty) ...[
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.comment, size: 18, color: Colors.blue[300]),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            request.comment!,
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: Colors.blue[200],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                SizedBox(height: 16),

                // Кнопки действий
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _declineRequest(request),
                        icon: Icon(Icons.close, size: 18),
                        label: Text('Отклонить'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red[300],
                          side: BorderSide(color: Colors.red[300]!),
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _approveRequest(request),
                        icon: Icon(Icons.check, size: 18),
                        label: Text('Одобрить'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                        ),
                      ),
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white.withOpacity(0.3)),
        SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.4)),
        ),
        SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.8)),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Future<void> _approveRequest(ShiftTransferRequest request) async {
    if (request.acceptedBy.length > 1) {
      await _showSelectEmployeeDialog(request);
      return;
    }

    final employeeName = request.acceptedBy.isNotEmpty
        ? request.acceptedBy.first.employeeName
        : (request.acceptedByEmployeeName ?? 'Неизвестно');
    final employeeId = request.acceptedBy.isNotEmpty
        ? request.acceptedBy.first.employeeId
        : request.acceptedByEmployeeId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Одобрить заявку?'),
        content: SingleChildScrollView(
          child: Text(
            'Смена ${request.shiftDate.day}.${request.shiftDate.month} (${request.shiftType.label}) '
            'будет передана от ${request.fromEmployeeName} к $employeeName.\n\n'
            'График будет обновлен автоматически.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Одобрить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ShiftTransferService.approveRequest(
        request.id,
        selectedEmployeeId: employeeId,
      );
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Заявка одобрена, график обновлен'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadNotifications();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка одобрения заявки'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showSelectEmployeeDialog(ShiftTransferRequest request) async {
    final selectedEmployee = await showDialog<AcceptedByEmployee>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Выберите сотрудника'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Смену ${request.shiftDate.day}.${request.shiftDate.month} (${request.shiftType.label}) '
                'готовы взять ${request.acceptedBy.length} сотрудника.\n\n'
                'Выберите кому передать смену:',
                style: TextStyle(color: Colors.grey[700]),
              ),
              SizedBox(height: 16),
              ...request.acceptedBy.map((accepted) => Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: InkWell(
                  onTap: () => Navigator.pop(context, accepted),
                  borderRadius: BorderRadius.circular(8.r),
                  child: Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.green[100],
                          child: Icon(Icons.person, color: Colors.green[700], size: 20),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            accepted.employeeName,
                            style: TextStyle(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
                      ],
                    ),
                  ),
                ),
              )),
              SizedBox(height: 8),
              Text(
                'Остальным сотрудникам придёт уведомление об отклонении.',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey[500], fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'),
          ),
        ],
      ),
    );

    if (selectedEmployee == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Подтвердите выбор'),
        content: SingleChildScrollView(
          child: Text(
            'Смена ${request.shiftDate.day}.${request.shiftDate.month} (${request.shiftType.label}) '
            'будет передана от ${request.fromEmployeeName} к ${selectedEmployee.employeeName}.\n\n'
            'Остальные ${request.acceptedBy.length - 1} сотрудника получат уведомление об отклонении.\n\n'
            'График будет обновлен автоматически.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Подтвердить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ShiftTransferService.approveRequest(
        request.id,
        selectedEmployeeId: selectedEmployee.employeeId,
      );
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Смена передана ${selectedEmployee.employeeName}'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadNotifications();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка одобрения заявки'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _declineRequest(ShiftTransferRequest request) async {
    String acceptedText;
    if (request.acceptedBy.length > 1) {
      final names = request.acceptedBy.map((a) => a.employeeName).join(', ');
      acceptedText = '$names (${request.acceptedBy.length} чел.)';
    } else if (request.acceptedBy.isNotEmpty) {
      acceptedText = request.acceptedBy.first.employeeName;
    } else {
      acceptedText = request.acceptedByEmployeeName ?? 'Неизвестно';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Отклонить заявку?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Заявка на передачу смены ${request.shiftDate.day}.${request.shiftDate.month} '
                'от ${request.fromEmployeeName} будет отклонена.',
              ),
              if (request.acceptedBy.length > 1) ...[
                SizedBox(height: 12),
                Text(
                  'Следующие сотрудники получат уведомление об отклонении:',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13.sp),
                ),
                SizedBox(height: 8),
                ...request.acceptedBy.map((a) => Padding(
                  padding: EdgeInsets.only(left: 8.w, bottom: 4.h),
                  child: Text('• ${a.employeeName}', style: TextStyle(fontSize: 13.sp)),
                )),
              ] else ...[
                SizedBox(height: 8),
                Text(
                  'Принявший: $acceptedText',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13.sp),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Отклонить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ShiftTransferService.declineRequest(request.id);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Заявка отклонена'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        await _loadNotifications();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка отклонения заявки'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

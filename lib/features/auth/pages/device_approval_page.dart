import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/logger.dart';
import '../services/auth_service.dart';

/// Страница управления запросами на подтверждение устройств
///
/// Доступна только разработчику.
/// Показывает список ожидающих запросов с кнопками «Разрешить» / «Отказать».
class DeviceApprovalPage extends StatefulWidget {
  final bool embedded;
  const DeviceApprovalPage({super.key, this.embedded = false});

  @override
  State<DeviceApprovalPage> createState() => _DeviceApprovalPageState();
}

class _DeviceApprovalPageState extends State<DeviceApprovalPage> {
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (mounted) setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final requests = await _authService.getDeviceApprovalRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (e, st) {
      Logger.error('Error loading device approval requests', e, st);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ошибка загрузки запросов';
      });
    }
  }

  Future<void> _resolveRequest(String requestId, String action) async {
    try {
      final result = await _authService.resolveDeviceApproval(
        requestId: requestId,
        action: action,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'approve'
                  ? 'Устройство подтверждено'
                  : 'Запрос отклонён',
            ),
            backgroundColor: action == 'approve' ? Colors.green : Colors.orange,
          ),
        );
        _loadRequests(); // Refresh
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] as String? ?? 'Ошибка'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, st) {
      Logger.error('Error resolving device approval', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка обработки запроса'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatPhone(String phone) {
    if (phone.length == 11) {
      return '+${phone[0]} (${phone.substring(1, 4)}) ${phone.substring(4, 7)}-${phone.substring(7, 9)}-${phone.substring(9)}';
    }
    return phone;
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 1) return 'только что';
      if (diff.inMinutes < 60) return '${diff.inMinutes} мин. назад';
      if (diff.inHours < 24) return '${diff.inHours} ч. назад';
      return '${date.day}.${date.month.toString().padLeft(2, '0')} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
        ),
      );
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              style: TextStyle(color: Colors.white70),
            ),
            SizedBox(height: 16),
            TextButton(
              onPressed: _loadRequests,
              child: Text('Повторить'),
            ),
          ],
        ),
      );
    }
    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              color: Colors.white24,
              size: 64,
            ),
            SizedBox(height: 16),
            Text(
              'Нет ожидающих запросов',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 16.sp,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadRequests,
      color: AppColors.gold,
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: _requests.length,
        itemBuilder: (context, index) {
          final req = _requests[index];
          return _buildRequestCard(req);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Container(
        color: AppColors.night,
        child: _buildBody(),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        title: Text('Запросы на устройства'),
        backgroundColor: AppColors.emerald,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadRequests,
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final phone = req['phone'] as String? ?? '';
    final userName = req['user_name'] as String? ?? phone;
    final deviceName = req['device_name'] as String? ?? 'Unknown';
    final oldDeviceName = req['old_device_name'] as String?;
    final createdAt = req['created_at'] as String?;
    final requestId = req['id'] as String? ?? '';

    return Card(
      color: Colors.white.withOpacity(0.08),
      margin: EdgeInsets.only(bottom: 12.h),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
        side: BorderSide(color: AppColors.gold.withOpacity(0.2)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.emerald,
                  radius: 20.r,
                  child: Icon(Icons.person, color: Colors.white, size: 20),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _formatPhone(phone),
                        style: TextStyle(color: Colors.white54, fontSize: 13.sp),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: 12.h),

            // Old device info
            if (oldDeviceName != null) ...[
              Row(
                children: [
                  Icon(Icons.phone_android, color: Colors.white38, size: 16),
                  SizedBox(width: 8.w),
                  Text(
                    'Было: $oldDeviceName',
                    style: TextStyle(color: Colors.white38, fontSize: 13.sp),
                  ),
                ],
              ),
              SizedBox(height: 4.h),
            ],

            // New device info
            Row(
              children: [
                Icon(Icons.phone_android, color: AppColors.gold, size: 16),
                SizedBox(width: 8.w),
                Text(
                  oldDeviceName != null ? 'Стало: $deviceName' : deviceName,
                  style: TextStyle(color: Colors.white54, fontSize: 13.sp),
                ),
                Spacer(),
                Text(
                  _formatTime(createdAt),
                  style: TextStyle(color: Colors.white38, fontSize: 12.sp),
                ),
              ],
            ),

            SizedBox(height: 16.h),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _resolveRequest(requestId, 'reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                    ),
                    child: Text('Отказать'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _resolveRequest(requestId, 'approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                    ),
                    child: Text('Разрешить'),
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

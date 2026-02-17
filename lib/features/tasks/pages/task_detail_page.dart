import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница деталей задачи (для просмотра и проверки админом)
class TaskDetailPage extends StatefulWidget {
  final TaskAssignment assignment;

  const TaskDetailPage({super.key, required this.assignment});

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  bool _isLoading = false;
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _reviewTask(bool approved) async {
    final comment = _commentController.text.trim();

    // Подтверждение действия
    final confirmText = approved ? 'подтвердить' : 'отклонить';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.r),
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        title: Text(
          approved ? 'Подтвердить задачу?' : 'Отклонить задачу?',
          style: TextStyle(color: Colors.white.withOpacity(0.9)),
        ),
        content: Text(
          approved
              ? 'Сотрудник получит +1 балл за выполнение.'
              : 'Сотрудник получит -3 балла за отклоненную задачу.',
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: approved ? Colors.green.withOpacity(0.8) : Colors.red.withOpacity(0.8),
              foregroundColor: Colors.white,
            ),
            child: Text(confirmText.substring(0, 1).toUpperCase() + confirmText.substring(1)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await TaskService.reviewTask(
        assignmentId: widget.assignment.id,
        approved: approved,
        reviewedBy: 'admin',
        reviewComment: comment.isNotEmpty ? comment : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approved ? 'Задача подтверждена' : 'Задача отклонена', style: TextStyle(color: Colors.white)),
            backgroundColor: approved ? Colors.green : Colors.red,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.assignment.task;
    final assignment = widget.assignment;

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
                        padding: EdgeInsets.all(8.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.9), size: 20),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Детали задачи',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 20.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            assignment.status.displayName,
                            style: TextStyle(
                              color: AppColors.gold.withOpacity(0.7),
                              fontSize: 13.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : SingleChildScrollView(
                        padding: EdgeInsets.all(16.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Заголовок задачи
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(16.w),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task?.title ?? 'Задача',
                                      style: TextStyle(
                                        fontSize: 20.sp,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white.withOpacity(0.9),
                                      ),
                                    ),
                                    if (task?.description.isNotEmpty == true) ...[
                                      SizedBox(height: 8),
                                      Text(
                                        task!.description,
                                        style: TextStyle(color: Colors.white.withOpacity(0.6)),
                                      ),
                                    ],
                                    SizedBox(height: 12),
                                    _buildInfoRow(
                                      icon: Icons.person,
                                      label: 'Исполнитель',
                                      value: assignment.assigneeName,
                                    ),
                                    SizedBox(height: 8),
                                    _buildInfoRow(
                                      icon: Icons.access_time,
                                      label: 'Дедлайн',
                                      value: _formatDateTime(assignment.deadline),
                                      valueColor: DateTime.now().isAfter(assignment.deadline)
                                          ? Colors.red
                                          : null,
                                    ),
                                    SizedBox(height: 8),
                                    _buildInfoRow(
                                      icon: _getStatusIcon(assignment.status),
                                      label: 'Статус',
                                      value: assignment.status.displayName,
                                      valueColor: _getStatusColor(assignment.status),
                                    ),
                                    if (task != null) ...[
                                      SizedBox(height: 8),
                                      _buildInfoRow(
                                        icon: _getResponseTypeIcon(task.responseType),
                                        label: 'Тип ответа',
                                        value: _getResponseTypeText(task.responseType),
                                      ),
                                    ],
                                    // Прикрепленные фото от админа при создании задачи
                                    if (task?.attachments.isNotEmpty == true) ...[
                                      SizedBox(height: 12),
                                      Divider(color: Colors.white.withOpacity(0.1)),
                                      SizedBox(height: 8),
                                      Text(
                                        'Прикрепленные файлы (${task!.attachments.length}):',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white.withOpacity(0.9),
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      SizedBox(
                                        height: 100,
                                        child: ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: task.attachments.length,
                                          itemBuilder: (context, index) {
                                            final photoUrl = task.attachments[index];
                                            final fullUrl = photoUrl.startsWith('http')
                                                ? photoUrl
                                                : '${ApiConstants.serverUrl}/media/$photoUrl';

                                            return GestureDetector(
                                              onTap: () => _showFullImage(context, fullUrl),
                                              child: Container(
                                                width: 100,
                                                height: 100,
                                                margin: EdgeInsets.only(right: 8.w),
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(8.r),
                                                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                                                ),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(8.r),
                                                  child: AppCachedImage(
                                                    imageUrl: fullUrl,
                                                    fit: BoxFit.cover,
                                                    errorWidget: (_, __, ___) => Container(
                                                      color: Colors.white.withOpacity(0.06),
                                                      child: Icon(Icons.broken_image, color: Colors.white.withOpacity(0.3)),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),

                            SizedBox(height: 16),

                            // Ответ сотрудника (если есть)
                            if (assignment.respondedAt != null) ...[
                              Text(
                                'Ответ сотрудника',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                              SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(14.r),
                                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(16.w),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildInfoRow(
                                        icon: Icons.schedule,
                                        label: 'Время ответа',
                                        value: _formatDateTime(assignment.respondedAt!),
                                      ),

                                      // Текст ответа
                                      if (assignment.responseText?.isNotEmpty == true) ...[
                                        SizedBox(height: 12),
                                        Text(
                                          'Текст ответа:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white.withOpacity(0.9),
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Container(
                                          width: double.infinity,
                                          padding: EdgeInsets.all(12.w),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.04),
                                            borderRadius: BorderRadius.circular(8.r),
                                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                                          ),
                                          child: Text(
                                            assignment.responseText!,
                                            style: TextStyle(color: Colors.white.withOpacity(0.9)),
                                          ),
                                        ),
                                      ],

                                      // Фотографии
                                      if (assignment.responsePhotos.isNotEmpty) ...[
                                        SizedBox(height: 12),
                                        Text(
                                          'Фотографии (${assignment.responsePhotos.length}):',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white.withOpacity(0.9),
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        SizedBox(
                                          height: 120,
                                          child: ListView.builder(
                                            scrollDirection: Axis.horizontal,
                                            itemCount: assignment.responsePhotos.length,
                                            itemBuilder: (context, index) {
                                              final photoUrl = assignment.responsePhotos[index];
                                              final fullUrl = photoUrl.startsWith('http')
                                                  ? photoUrl
                                                  : '${ApiConstants.serverUrl}/media/$photoUrl';

                                              return GestureDetector(
                                                onTap: () => _showFullImage(context, fullUrl),
                                                child: Container(
                                                  width: 120,
                                                  height: 120,
                                                  margin: EdgeInsets.only(right: 8.w),
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(8.r),
                                                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(8.r),
                                                    child: AppCachedImage(
                                                      imageUrl: fullUrl,
                                                      fit: BoxFit.cover,
                                                      errorWidget: (_, __, ___) => Container(
                                                        color: Colors.white.withOpacity(0.06),
                                                        child: Icon(Icons.broken_image, color: Colors.white.withOpacity(0.3)),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: 16),
                            ],

                            // Информация о проверке (если уже проверено)
                            if (assignment.reviewedAt != null) ...[
                              Text(
                                'Результат проверки',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                              SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: assignment.status == TaskStatus.approved
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14.r),
                                  border: Border.all(
                                    color: assignment.status == TaskStatus.approved
                                        ? Colors.green.withOpacity(0.3)
                                        : Colors.red.withOpacity(0.3),
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(16.w),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            assignment.status == TaskStatus.approved
                                                ? Icons.check_circle
                                                : Icons.cancel,
                                            color: assignment.status == TaskStatus.approved
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            assignment.status == TaskStatus.approved
                                                ? 'Задача подтверждена'
                                                : 'Задача отклонена',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: assignment.status == TaskStatus.approved
                                                  ? Colors.green
                                                  : Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      _buildInfoRow(
                                        icon: Icons.person,
                                        label: 'Проверил',
                                        value: assignment.reviewedBy ?? 'Админ',
                                      ),
                                      SizedBox(height: 4),
                                      _buildInfoRow(
                                        icon: Icons.schedule,
                                        label: 'Время проверки',
                                        value: _formatDateTime(assignment.reviewedAt!),
                                      ),
                                      if (assignment.reviewComment?.isNotEmpty == true) ...[
                                        SizedBox(height: 8),
                                        Text(
                                          'Комментарий:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white.withOpacity(0.9),
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          assignment.reviewComment!,
                                          style: TextStyle(color: Colors.white.withOpacity(0.7)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],

                            // Информация об отказе работника
                            if (assignment.status == TaskStatus.declined) ...[
                              Text(
                                'Отказ от задачи',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                              SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14.r),
                                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(16.w),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.block, color: Colors.deepOrange),
                                          SizedBox(width: 8),
                                          Text(
                                            'Сотрудник отказался от задачи',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.deepOrange,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (assignment.declineReason?.isNotEmpty == true) ...[
                                        SizedBox(height: 8),
                                        Text(
                                          'Причина:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white.withOpacity(0.9),
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          assignment.declineReason!,
                                          style: TextStyle(color: Colors.white.withOpacity(0.7)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],

                            // Информация о просрочке
                            if (assignment.status == TaskStatus.expired) ...[
                              Text(
                                'Просрочено',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                              SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14.r),
                                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(16.w),
                                  child: Row(
                                    children: [
                                      Icon(Icons.timer_off, color: Colors.white.withOpacity(0.5)),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Задача не была выполнена в срок',
                                          style: TextStyle(color: Colors.white.withOpacity(0.5)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],

                            // Кнопки проверки (только для статуса submitted)
                            if (assignment.status == TaskStatus.submitted) ...[
                              SizedBox(height: 24),
                              Text(
                                'Проверка задачи',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                              SizedBox(height: 8),
                              TextField(
                                controller: _commentController,
                                style: TextStyle(color: Colors.white.withOpacity(0.9)),
                                decoration: InputDecoration(
                                  labelText: 'Комментарий (необязательно)',
                                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.r),
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.r),
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.r),
                                    borderSide: BorderSide(color: AppColors.gold.withOpacity(0.5)),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.04),
                                ),
                                maxLines: 2,
                              ),
                              SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _reviewTask(false),
                                      icon: Icon(Icons.cancel),
                                      label: Text('Отклонить'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red.withOpacity(0.15),
                                        foregroundColor: Colors.red,
                                        padding: EdgeInsets.symmetric(vertical: 12.h),
                                        side: BorderSide(color: Colors.red.withOpacity(0.3)),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12.r),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _reviewTask(true),
                                      icon: Icon(Icons.check_circle),
                                      label: Text('Подтвердить'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.gold,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(vertical: 12.h),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12.r),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.gold.withOpacity(0.7)),
        SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: valueColor ?? Colors.white.withOpacity(0.9),
            ),
          ),
        ),
      ],
    );
  }

  void _showFullImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.night,
        child: Stack(
          children: [
            InteractiveViewer(
              child: AppCachedImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => Center(
                  child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
                ),
              ),
            ),
            Positioned(
              top: 8.h,
              right: 8.w,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  IconData _getStatusIcon(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return Icons.hourglass_empty;
      case TaskStatus.submitted:
        return Icons.pending_actions;
      case TaskStatus.approved:
        return Icons.check_circle;
      case TaskStatus.rejected:
        return Icons.cancel;
      case TaskStatus.expired:
        return Icons.timer_off;
      case TaskStatus.declined:
        return Icons.block;
    }
  }

  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return Colors.orange;
      case TaskStatus.submitted:
        return Colors.blue;
      case TaskStatus.approved:
        return Colors.green;
      case TaskStatus.rejected:
        return Colors.red;
      case TaskStatus.expired:
        return Colors.grey;
      case TaskStatus.declined:
        return Colors.deepOrange;
    }
  }

  IconData _getResponseTypeIcon(TaskResponseType type) {
    switch (type) {
      case TaskResponseType.photo:
        return Icons.photo_camera;
      case TaskResponseType.photoAndText:
        return Icons.photo_library;
      case TaskResponseType.text:
        return Icons.text_fields;
    }
  }

  String _getResponseTypeText(TaskResponseType type) {
    switch (type) {
      case TaskResponseType.photo:
        return 'Только фото';
      case TaskResponseType.photoAndText:
        return 'Фото и текст';
      case TaskResponseType.text:
        return 'Только текст';
    }
  }
}

import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';
import '../../../core/constants/api_constants.dart';

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
        title: Text(approved ? 'Подтвердить задачу?' : 'Отклонить задачу?'),
        content: Text(
          approved
              ? 'Сотрудник получит +1 балл за выполнение.'
              : 'Сотрудник получит -3 балла за отклоненную задачу.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: approved ? Colors.green : Colors.red,
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
            content: Text(approved ? 'Задача подтверждена' : 'Задача отклонена', style: const TextStyle(color: Colors.white)),
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
            content: Text('Ошибка: $e', style: const TextStyle(color: Colors.white)),
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
      appBar: AppBar(
        title: const Text('Детали задачи'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок задачи
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task?.title ?? 'Задача',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (task?.description.isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            Text(
                              task!.description,
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            icon: Icons.person,
                            label: 'Исполнитель',
                            value: assignment.assigneeName,
                          ),
                          const SizedBox(height: 8),
                          _buildInfoRow(
                            icon: Icons.access_time,
                            label: 'Дедлайн',
                            value: _formatDateTime(assignment.deadline),
                            valueColor: DateTime.now().isAfter(assignment.deadline)
                                ? Colors.red
                                : null,
                          ),
                          const SizedBox(height: 8),
                          _buildInfoRow(
                            icon: _getStatusIcon(assignment.status),
                            label: 'Статус',
                            value: assignment.status.displayName,
                            valueColor: _getStatusColor(assignment.status),
                          ),
                          if (task != null) ...[
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              icon: _getResponseTypeIcon(task.responseType),
                              label: 'Тип ответа',
                              value: _getResponseTypeText(task.responseType),
                            ),
                          ],
                          // Прикрепленные фото от админа при создании задачи
                          if (task?.attachments.isNotEmpty == true) ...[
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 8),
                            Text(
                              'Прикрепленные файлы (${task!.attachments.length}):',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 8),
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
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey[300]!),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          fullUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            color: Colors.grey[200],
                                            child: const Icon(Icons.broken_image),
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

                  const SizedBox(height: 16),

                  // Ответ сотрудника (если есть)
                  if (assignment.respondedAt != null) ...[
                    const Text(
                      'Ответ сотрудника',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
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
                              const SizedBox(height: 12),
                              const Text(
                                'Текст ответа:',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(assignment.responseText!),
                              ),
                            ],

                            // Фотографии
                            if (assignment.responsePhotos.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Фотографии (${assignment.responsePhotos.length}):',
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 8),
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
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.grey[300]!),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            fullUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              color: Colors.grey[200],
                                              child: const Icon(Icons.broken_image),
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
                    const SizedBox(height: 16),
                  ],

                  // Информация о проверке (если уже проверено)
                  if (assignment.reviewedAt != null) ...[
                    const Text(
                      'Результат проверки',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      color: assignment.status == TaskStatus.approved
                          ? Colors.green[50]
                          : Colors.red[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
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
                                const SizedBox(width: 8),
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
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              icon: Icons.person,
                              label: 'Проверил',
                              value: assignment.reviewedBy ?? 'Админ',
                            ),
                            const SizedBox(height: 4),
                            _buildInfoRow(
                              icon: Icons.schedule,
                              label: 'Время проверки',
                              value: _formatDateTime(assignment.reviewedAt!),
                            ),
                            if (assignment.reviewComment?.isNotEmpty == true) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Комментарий:',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Text(assignment.reviewComment!),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Информация об отказе работника
                  if (assignment.status == TaskStatus.declined) ...[
                    const Text(
                      'Отказ от задачи',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      color: Colors.orange[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
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
                              const SizedBox(height: 8),
                              const Text(
                                'Причина:',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Text(assignment.declineReason!),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Информация о просрочке
                  if (assignment.status == TaskStatus.expired) ...[
                    const Text(
                      'Просрочено',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Card(
                      color: Color(0xFFFFF3E0),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.timer_off, color: Colors.grey),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Задача не была выполнена в срок',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Кнопки проверки (только для статуса submitted)
                  if (assignment.status == TaskStatus.submitted) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Проверка задачи',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _commentController,
                      decoration: InputDecoration(
                        labelText: 'Комментарий (необязательно)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _reviewTask(false),
                            icon: const Icon(Icons.cancel),
                            label: const Text('Отклонить'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _reviewTask(true),
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Подтвердить'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
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
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.grey[600]),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: valueColor,
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
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, size: 64),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
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

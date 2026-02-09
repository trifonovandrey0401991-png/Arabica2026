import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../models/task_model.dart';
import '../services/task_service.dart';
import '../../../core/services/media_upload_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/widgets/app_cached_image.dart';

/// Страница ответа на задачу (для работника)
class TaskResponsePage extends StatefulWidget {
  final TaskAssignment assignment;
  final VoidCallback? onUpdated;

  const TaskResponsePage({
    super.key,
    required this.assignment,
    this.onUpdated,
  });

  @override
  State<TaskResponsePage> createState() => _TaskResponsePageState();
}

class _TaskResponsePageState extends State<TaskResponsePage> {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  final _textController = TextEditingController();
  final List<File> _selectedPhotos = [];
  bool _isSubmitting = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _canRespond => widget.assignment.status == TaskStatus.pending;

  bool get _isFormValid {
    final type = widget.assignment.responseType;
    switch (type) {
      case TaskResponseType.photo:
        return _selectedPhotos.isNotEmpty;
      case TaskResponseType.photoAndText:
        return _selectedPhotos.isNotEmpty && _textController.text.trim().isNotEmpty;
      case TaskResponseType.text:
        return _textController.text.trim().isNotEmpty;
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      setState(() {
        _selectedPhotos.add(File(pickedFile.path));
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();

    setState(() {
      for (final file in pickedFiles) {
        _selectedPhotos.add(File(file.path));
      }
    });
  }

  void _removePhoto(int index) {
    setState(() {
      _selectedPhotos.removeAt(index);
    });
  }

  Future<void> _submitResponse() async {
    if (!_isFormValid || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      // Загружаем фото если есть
      List<String> photoUrls = [];
      if (_selectedPhotos.isNotEmpty) {
        for (final photo in _selectedPhotos) {
          final url = await MediaUploadService.uploadTaskPhoto(photo);
          if (url != null) {
            photoUrls.add(url);
          }
        }
      }

      final result = await TaskService.respondToTask(
        assignmentId: widget.assignment.id,
        responseText: _textController.text.trim().isNotEmpty ? _textController.text.trim() : null,
        responsePhotos: photoUrls,
      );

      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ответ отправлен на проверку', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green.shade800,
          ),
        );
        widget.onUpdated?.call();
        Navigator.pop(context);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ошибка при отправке ответа', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _declineTask() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _DeclineDialog(),
    );

    if (reason == null) return;

    setState(() => _isSubmitting = true);

    try {
      final result = await TaskService.declineTask(
        assignmentId: widget.assignment.id,
        reason: reason.isNotEmpty ? reason : null,
      );

      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Задача отклонена', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.orange.shade900,
          ),
        );
        widget.onUpdated?.call();
        Navigator.pop(context);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ошибка при отклонении задачи', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final assignment = widget.assignment;
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Задача',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Ответ на задание',
                            style: TextStyle(
                              color: _gold,
                              fontSize: 13,
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTaskInfoCard(assignment, dateFormat),
                      const SizedBox(height: 16),
                      if (_canRespond) ...[
                        _buildResponseSection(),
                        const SizedBox(height: 24),
                        _buildActionButtons(),
                      ] else ...[
                        _buildStatusInfoCard(assignment, dateFormat),
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

  Widget _buildTaskInfoCard(TaskAssignment assignment, DateFormat dateFormat) {
    final isOverdue = assignment.isOverdue && assignment.status == TaskStatus.pending;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              assignment.taskTitle,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
            if (assignment.taskDescription.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                assignment.taskDescription,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Divider(color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 18,
                  color: isOverdue ? Colors.red : Colors.white.withOpacity(0.5),
                ),
                const SizedBox(width: 8),
                Text(
                  'Срок: ${dateFormat.format(assignment.deadline)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: isOverdue ? Colors.red : Colors.white.withOpacity(0.6),
                    fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _getResponseTypeIcon(assignment.responseType),
                  size: 18,
                  color: Colors.white.withOpacity(0.5),
                ),
                const SizedBox(width: 8),
                Text(
                  'Тип ответа: ${assignment.responseType.displayName}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            if (isOverdue) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red[400]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Срок выполнения истек! Ответ всё ещё можно отправить.',
                        style: TextStyle(
                          color: Colors.red[400],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Прикрепленные фото от админа
            if (assignment.task?.attachments.isNotEmpty == true) ...[
              const SizedBox(height: 16),
              Divider(color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 12),
              Text(
                'Прикрепленные файлы:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: assignment.task!.attachments.length,
                  itemBuilder: (context, index) {
                    final photoUrl = assignment.task!.attachments[index];
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
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
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
    );
  }

  void _showFullImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _night,
        child: Stack(
          children: [
            InteractiveViewer(
              child: AppCachedImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, size: 64, color: Colors.white),
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

  IconData _getResponseTypeIcon(TaskResponseType type) {
    switch (type) {
      case TaskResponseType.photo:
        return Icons.photo_camera;
      case TaskResponseType.photoAndText:
        return Icons.photo_camera;
      case TaskResponseType.text:
        return Icons.text_fields;
    }
  }

  Widget _buildResponseSection() {
    final type = widget.assignment.responseType;
    final needsPhoto = type == TaskResponseType.photo || type == TaskResponseType.photoAndText;
    final needsText = type == TaskResponseType.text || type == TaskResponseType.photoAndText;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Ваш ответ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _gold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (needsPhoto) ...[
              _buildPhotoSection(),
              if (needsText) const SizedBox(height: 16),
            ],
            if (needsText) _buildTextSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Фотографии',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 8),
        if (_selectedPhotos.isNotEmpty) ...[
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedPhotos.length,
              itemBuilder: (context, index) => _buildPhotoPreview(index),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.camera_alt, color: _gold),
                label: const Text('Камера', style: TextStyle(color: _gold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _gold),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickFromGallery,
                icon: const Icon(Icons.photo_library, color: _gold),
                label: const Text('Галерея', style: TextStyle(color: _gold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _gold),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPhotoPreview(int index) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
            image: DecorationImage(
              image: FileImage(_selectedPhotos[index]),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 12,
          child: GestureDetector(
            onTap: () => _removePhoto(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Текст ответа',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _textController,
          maxLines: 5,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Введите ваш ответ...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _gold),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isFormValid && !_isSubmitting ? _submitResponse : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _night,
              disabledBackgroundColor: _gold.withOpacity(0.3),
              disabledForegroundColor: _night.withOpacity(0.5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_night),
                    ),
                  )
                : const Text(
                    'ОТПРАВИТЬ ОТВЕТ',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _isSubmitting ? null : _declineTask,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red[400],
              side: BorderSide(color: Colors.red[400]!),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'ОТКЛОНИТЬ ЗАДАЧУ',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusInfoCard(TaskAssignment assignment, DateFormat dateFormat) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusIcon(assignment.status),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Статус',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                      Text(
                        assignment.status.displayName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _getStatusColor(assignment.status),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (assignment.responseText != null && assignment.responseText!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 12),
              Text(
                'Ваш ответ:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                assignment.responseText!,
                style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
              ),
            ],
            if (assignment.responsePhotos.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Фото:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: assignment.responsePhotos.length,
                  itemBuilder: (context, index) => Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                      image: DecorationImage(
                        image: NetworkImage(assignment.responsePhotos[index]),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (assignment.reviewComment != null && assignment.reviewComment!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 12),
              Text(
                'Комментарий проверяющего:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                assignment.reviewComment!,
                style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
              ),
            ],
            if (assignment.reviewedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Проверено: ${dateFormat.format(assignment.reviewedAt!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(TaskStatus status) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _getStatusColor(status).withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getStatusColor(status).withOpacity(0.3)),
      ),
      child: Icon(
        _getStatusIconData(status),
        color: _getStatusColor(status),
        size: 28,
      ),
    );
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
        return Colors.purple;
    }
  }

  IconData _getStatusIconData(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return Icons.pending_actions;
      case TaskStatus.submitted:
        return Icons.hourglass_top;
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
}

/// Диалог для указания причины отклонения
class _DeclineDialog extends StatelessWidget {
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _gold = Color(0xFFD4AF37);

  final _reasonController = TextEditingController();

  _DeclineDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _emeraldDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text(
        'Отклонить задачу?',
        style: TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'При отклонении задачи будут начислены штрафные баллы (-3).',
            style: TextStyle(color: Colors.red[400]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Причина (необязательно)',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _gold),
              ),
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Отмена',
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _reasonController.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade800,
            foregroundColor: Colors.white,
          ),
          child: const Text('Отклонить'),
        ),
      ],
    );
  }
}

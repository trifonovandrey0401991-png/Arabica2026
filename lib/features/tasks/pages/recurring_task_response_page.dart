import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../models/recurring_task_model.dart';
import '../models/task_model.dart' show TaskResponseType, TaskResponseTypeExtension;
import '../services/recurring_task_service.dart';
import '../../../core/services/media_upload_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница ответа на циклическую задачу
class RecurringTaskResponsePage extends StatefulWidget {
  final RecurringTaskInstance instance;

  const RecurringTaskResponsePage({
    super.key,
    required this.instance,
  });

  @override
  State<RecurringTaskResponsePage> createState() =>
      _RecurringTaskResponsePageState();
}

class _RecurringTaskResponsePageState extends State<RecurringTaskResponsePage> {
  final _textController = TextEditingController();
  final List<File> _photos = [];
  bool _isSubmitting = false;

  RecurringTaskInstance get instance => widget.instance;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    switch (instance.responseType) {
      case TaskResponseType.photo:
        return _photos.isNotEmpty;
      case TaskResponseType.photoAndText:
        return _photos.isNotEmpty && _textController.text.trim().isNotEmpty;
      case TaskResponseType.text:
        return _textController.text.trim().isNotEmpty;
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera, maxWidth: 1280, imageQuality: 75);

    if (pickedFile != null && mounted) {
      setState(() {
        _photos.add(File(pickedFile.path));
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage(maxWidth: 1280, imageQuality: 75);

    if (!mounted) return;
    setState(() {
      for (final file in pickedFiles) {
        _photos.add(File(file.path));
      }
    });
  }

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
    });
  }

  Future<void> _completeTask() async {
    if (!_canSubmit) return;

    setState(() => _isSubmitting = true);

    try {
      // Загружаем фото
      List<String> photoUrls = [];
      if (_photos.isNotEmpty) {
        for (final photo in _photos) {
          final url = await MediaUploadService.uploadTaskPhoto(photo);
          if (url != null) {
            photoUrls.add(url);
          }
        }
      }

      await RecurringTaskService.completeInstance(
        instanceId: instance.id,
        responseText: _textController.text.trim().isNotEmpty
            ? _textController.text.trim()
            : null,
        responsePhotos: photoUrls.isNotEmpty ? photoUrls : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Задача выполнена!', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red.shade900,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildPhotoPreview(int index) {
    return Stack(
      children: [
        Container(
          margin: EdgeInsets.only(right: 8.w),
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            image: DecorationImage(
              image: FileImage(_photos[index]),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 4.h,
          right: 12.w,
          child: GestureDetector(
            onTap: () => _removePhoto(index),
            child: Container(
              padding: EdgeInsets.all(4.w),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Icon(
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

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    final needsPhoto = instance.responseType == TaskResponseType.photo ||
        instance.responseType == TaskResponseType.photoAndText;
    final needsText = instance.responseType == TaskResponseType.text ||
        instance.responseType == TaskResponseType.photoAndText;

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
                        child: Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Text(
                      'Выполнение задачи',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Body content
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Информация о задаче
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
                              Row(
                                children: [
                                  Icon(Icons.repeat, color: AppColors.gold),
                                  SizedBox(width: 8),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8.w,
                                      vertical: 2.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.gold.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8.r),
                                    ),
                                    child: Text(
                                      'Циклическая',
                                      style: TextStyle(
                                        fontSize: 11.sp,
                                        color: AppColors.gold,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              Text(
                                instance.title,
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                              if (instance.description.isNotEmpty) ...[
                                SizedBox(height: 8),
                                Text(
                                  instance.description,
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ),
                              ],
                              SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(Icons.access_time, size: 16, color: Colors.white.withOpacity(0.5)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Выполнить до: ${dateFormat.format(instance.deadline)}',
                                    style: TextStyle(
                                      fontSize: 13.sp,
                                      color: Colors.white.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    instance.isExpired
                                        ? Icons.warning
                                        : Icons.info_outline,
                                    size: 16,
                                    color: instance.isExpired ? Colors.red[400] : Colors.white.withOpacity(0.5),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    instance.isExpired
                                        ? 'Просрочено!'
                                        : 'Требуется: ${instance.responseType.displayName}',
                                    style: TextStyle(
                                      fontSize: 13.sp,
                                      color: instance.isExpired ? Colors.red[400] : Colors.white.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: 24),

                      // Фото (если нужно)
                      if (needsPhoto) ...[
                        Text(
                          'Фото *',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        SizedBox(height: 8),
                        if (_photos.isNotEmpty) ...[
                          SizedBox(
                            height: 100,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _photos.length,
                              itemBuilder: (context, index) => _buildPhotoPreview(index),
                            ),
                          ),
                          SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickPhoto,
                                icon: Icon(Icons.camera_alt, color: AppColors.gold),
                                label: Text('Камера', style: TextStyle(color: AppColors.gold)),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: AppColors.gold),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                  padding: EdgeInsets.symmetric(vertical: 12.h),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickFromGallery,
                                icon: Icon(Icons.photo_library, color: AppColors.gold),
                                label: Text('Галерея', style: TextStyle(color: AppColors.gold)),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: AppColors.gold),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                  padding: EdgeInsets.symmetric(vertical: 12.h),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 24),
                      ],

                      // Текст (если нужно)
                      if (needsText) ...[
                        Text(
                          'Комментарий ${needsPhoto ? "" : "*"}',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        SizedBox(height: 8),
                        TextFormField(
                          controller: _textController,
                          maxLines: 4,
                          style: TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Опишите выполнение задачи...',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.06),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: AppColors.gold.withOpacity(0.6)),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        SizedBox(height: 24),
                      ],

                      // Информация о баллах
                      Container(
                        padding: EdgeInsets.all(12.w),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green[400], size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'После нажатия "Выполнено" задача будет сразу закрыта без проверки',
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: Colors.green[300],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 32),

                      // Кнопка выполнения
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _canSubmit && !_isSubmitting && !instance.isExpired
                              ? _completeTask
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: AppColors.night,
                            disabledBackgroundColor: AppColors.gold.withOpacity(0.3),
                            disabledForegroundColor: AppColors.night.withOpacity(0.5),
                            padding: EdgeInsets.symmetric(vertical: 16.h),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
                          child: _isSubmitting
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.night),
                                  ),
                                )
                              : Text(
                                  'ВЫПОЛНЕНО',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),

                      if (instance.isExpired)
                        Padding(
                          padding: EdgeInsets.only(top: 16.h),
                          child: Container(
                            padding: EdgeInsets.all(12.w),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(color: Colors.red.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error, color: Colors.red[400], size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Задача просрочена. Вы получили -3 балла.',
                                    style: TextStyle(
                                      fontSize: 13.sp,
                                      color: Colors.red[300],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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
}

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../models/photo_template.dart';
import '../widgets/template_overlay_painter.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница камеры с overlay-схемой шаблона
class TemplateCameraPage extends StatefulWidget {
  final PhotoTemplate template;
  final String productName;

  const TemplateCameraPage({
    super.key,
    required this.template,
    required this.productName,
  });

  @override
  State<TemplateCameraPage> createState() => _TemplateCameraPageState();
}

class _TemplateCameraPageState extends State<TemplateCameraPage> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isTakingPhoto = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _error = 'Камера не найдена';
        });
        return;
      }

      // Используем заднюю камеру
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Ошибка инициализации камеры: $e';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isTakingPhoto) {
      return;
    }

    setState(() {
      _isTakingPhoto = true;
    });

    try {
      final XFile photo = await _controller!.takePicture();
      final Uint8List imageBytes = await File(photo.path).readAsBytes();

      if (!mounted) return;

      // Возвращаем байты фото
      Navigator.pop(context, imageBytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка съёмки: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.template.name,
              style: TextStyle(fontSize: 16.sp),
            ),
            Text(
              widget.productName,
              style: TextStyle(fontSize: 12.sp, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Назад'),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Column(
      children: [
        // Превью камеры с overlay
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Камера
              ClipRect(
                child: OverflowBox(
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.previewSize!.height,
                      height: _controller!.value.previewSize!.width,
                      child: CameraPreview(_controller!),
                    ),
                  ),
                ),
              ),

              // Overlay схема
              TemplateOverlayWidget(
                template: widget.template,
                color: Colors.yellow,
              ),

              // Подсказка снизу
              Positioned(
                left: 16.w,
                right: 16.w,
                bottom: 16.h,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.yellow, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.template.hint,
                          style: TextStyle(color: Colors.white, fontSize: 13.sp),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Кнопка съёмки
        Container(
          color: Colors.black,
          padding: EdgeInsets.symmetric(vertical: 24.h),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Кнопка отмены
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: Colors.white, size: 32),
                ),

                // Кнопка съёмки
                GestureDetector(
                  onTap: _isTakingPhoto ? null : _takePhoto,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: _isTakingPhoto ? Colors.grey : Colors.transparent,
                    ),
                    child: _isTakingPhoto
                        ? Padding(
                            padding: EdgeInsets.all(20.w),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Container(
                            margin: EdgeInsets.all(4.w),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),

                // Placeholder для симметрии
                SizedBox(width: 48),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

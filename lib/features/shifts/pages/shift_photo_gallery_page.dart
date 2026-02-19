import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/shift_report_model.dart';
import '../../../core/services/photo_upload_service.dart';
import 'package:arabica_app/shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница галереи фото из отчетов
class ShiftPhotoGalleryPage extends StatefulWidget {
  final List<ShiftReport> reports;
  final int initialIndex;

  const ShiftPhotoGalleryPage({
    super.key,
    required this.reports,
    this.initialIndex = 0,
  });

  @override
  State<ShiftPhotoGalleryPage> createState() => _ShiftPhotoGalleryPageState();
}

class _ShiftPhotoGalleryPageState extends State<ShiftPhotoGalleryPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<String> get _allPhotoPaths {
    final List<String> paths = [];
    for (var report in widget.reports) {
      for (var answer in report.answers) {
        // Приоритет: серверный URL (photoDriveId) > локальный путь (photoPath)
        if (answer.photoDriveId != null) {
          paths.add(answer.photoDriveId!);
        } else if (answer.photoPath != null) {
          paths.add(answer.photoPath!);
        }
      }
    }
    return paths;
  }

  Widget _buildAppBar(BuildContext context, {required String title}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 4.h),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(int total) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (index) {
          final isActive = index == _currentIndex;
          return AnimatedContainer(
            duration: Duration(milliseconds: 250),
            margin: EdgeInsets.symmetric(horizontal: 4.w),
            width: isActive ? 10 : 8,
            height: isActive ? 10 : 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AppColors.gold : Colors.white.withOpacity(0.3),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = _allPhotoPaths;

    if (photos.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.night,
        appBar: null,
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context, title: 'Фотографии'),
              Expanded(
                child: Center(
                  child: Text(
                    'Фотографии не найдены',
                    style: TextStyle(color: Colors.white70, fontSize: 16.sp),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: null,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, title: 'Фото ${_currentIndex + 1} из ${photos.length}'),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: photos.length,
                onPageChanged: (index) {
                  if (mounted) setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final photo = photos[index];

                  return Center(
                    child: kIsWeb
                        ? (photo.startsWith('data:') || photo.startsWith('http'))
                            ? AppCachedImage(
                                imageUrl: photo,
                                fit: BoxFit.contain,
                                errorWidget: (context, error, stackTrace) {
                                  return Center(
                                    child: Icon(Icons.error, size: 64, color: AppColors.gold.withOpacity(0.6)),
                                  );
                                },
                              )
                            : FutureBuilder<String>(
                                future: Future.value(PhotoUploadService.getPhotoUrl(photo)),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData) {
                                    return AppCachedImage(
                                      imageUrl: snapshot.data!,
                                      fit: BoxFit.contain,
                                      errorWidget: (context, error, stackTrace) {
                                        return Center(
                                          child: Icon(Icons.error, size: 64, color: AppColors.gold.withOpacity(0.6)),
                                        );
                                      },
                                    );
                                  }
                                  return Center(
                                    child: CircularProgressIndicator(color: AppColors.gold),
                                  );
                                },
                              )
                        : (photo.startsWith('http') || photo.contains('drive.google.com'))
                            ? AppCachedImage(
                                imageUrl: photo,
                                fit: BoxFit.contain,
                                errorWidget: (context, error, stackTrace) {
                                  return Center(
                                    child: Icon(Icons.error, size: 64, color: AppColors.gold.withOpacity(0.6)),
                                  );
                                },
                              )
                            : File(photo).existsSync()
                                ? Image.file(
                                    File(photo),
                                    fit: BoxFit.contain,
                                  )
                                : FutureBuilder<String>(
                                    future: Future.value(PhotoUploadService.getPhotoUrl(photo)),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData) {
                                        return AppCachedImage(
                                          imageUrl: snapshot.data!,
                                          fit: BoxFit.contain,
                                          errorWidget: (context, error, stackTrace) {
                                            return Center(
                                              child: Icon(Icons.error, size: 64, color: AppColors.gold.withOpacity(0.6)),
                                            );
                                          },
                                        );
                                      }
                                      return Center(
                                        child: CircularProgressIndicator(color: AppColors.gold),
                                      );
                                    },
                                  ),
                  );
                },
              ),
            ),
            if (photos.length > 1) _buildPageIndicator(photos.length),
          ],
        ),
      ),
    );
  }
}

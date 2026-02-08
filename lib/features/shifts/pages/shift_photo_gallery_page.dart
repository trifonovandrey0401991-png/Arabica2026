import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/shift_report_model.dart';
import '../../../core/services/photo_upload_service.dart';

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
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

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
        if (answer.photoPath != null) {
          paths.add(answer.photoPath!);
        } else if (answer.photoDriveId != null) {
          paths.add(answer.photoDriveId!);
        }
      }
    }
    return paths;
  }

  Widget _buildAppBar(BuildContext context, {required String title}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(int total) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (index) {
          final isActive = index == _currentIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 10 : 8,
            height: isActive ? 10 : 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? _gold : Colors.white.withOpacity(0.3),
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
        backgroundColor: _night,
        appBar: null,
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context, title: 'Фотографии'),
              const Expanded(
                child: Center(
                  child: Text(
                    'Фотографии не найдены',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _night,
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
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final photo = photos[index];

                  return Center(
                    child: kIsWeb
                        ? (photo.startsWith('data:') || photo.startsWith('http'))
                            ? Image.network(
                                photo,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Icon(Icons.error, size: 64, color: _gold.withOpacity(0.6)),
                                  );
                                },
                              )
                            : FutureBuilder<String>(
                                future: Future.value(PhotoUploadService.getPhotoUrl(photo)),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData) {
                                    return Image.network(
                                      snapshot.data!,
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Center(
                                          child: Icon(Icons.error, size: 64, color: _gold.withOpacity(0.6)),
                                        );
                                      },
                                    );
                                  }
                                  return const Center(
                                    child: CircularProgressIndicator(color: _gold),
                                  );
                                },
                              )
                        : (photo.startsWith('http') || photo.contains('drive.google.com'))
                            ? Image.network(
                                photo,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Icon(Icons.error, size: 64, color: _gold.withOpacity(0.6)),
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
                                        return Image.network(
                                          snapshot.data!,
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Center(
                                              child: Icon(Icons.error, size: 64, color: _gold.withOpacity(0.6)),
                                            );
                                          },
                                        );
                                      }
                                      return const Center(
                                        child: CircularProgressIndicator(color: _gold),
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

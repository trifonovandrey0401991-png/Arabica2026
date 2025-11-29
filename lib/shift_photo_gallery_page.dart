import 'dart:io';
import 'package:flutter/material.dart';
import 'shift_report_model.dart';
import 'google_drive_service.dart';

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
        if (answer.photoPath != null) {
          paths.add(answer.photoPath!);
        } else if (answer.photoDriveId != null) {
          paths.add(answer.photoDriveId!);
        }
      }
    }
    return paths;
  }

  @override
  Widget build(BuildContext context) {
    final photos = _allPhotoPaths;

    if (photos.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Фотографии'),
          backgroundColor: const Color(0xFF004D40),
        ),
        body: const Center(
          child: Text('Фотографии не найдены'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Фото ${_currentIndex + 1} из ${photos.length}'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: PageView.builder(
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
            child: photo.startsWith('http') || photo.contains('drive.google.com')
                ? Image.network(
                    photo,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(Icons.error, size: 64),
                      );
                    },
                  )
                : File(photo).existsSync()
                    ? Image.file(
                        File(photo),
                        fit: BoxFit.contain,
                      )
                    : FutureBuilder<String>(
                        future: Future.value(GoogleDriveService.getPhotoUrl(photo)),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return Image.network(
                              snapshot.data!,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Icon(Icons.error, size: 64),
                                );
                              },
                            );
                          }
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                      ),
          );
        },
      ),
    );
  }
}


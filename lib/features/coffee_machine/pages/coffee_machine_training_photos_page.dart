import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../shared/widgets/app_cached_image.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница просмотра и удаления обучающих фото для шаблона кофемашины
class CoffeeMachineTrainingPhotosPage extends StatefulWidget {
  final String machineName;
  final String? preset;

  const CoffeeMachineTrainingPhotosPage({
    super.key,
    required this.machineName,
    this.preset,
  });

  @override
  State<CoffeeMachineTrainingPhotosPage> createState() => _CoffeeMachineTrainingPhotosPageState();
}

class _CoffeeMachineTrainingPhotosPageState extends State<CoffeeMachineTrainingPhotosPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _samples = [];

  @override
  void initState() {
    super.initState();
    _loadSamples();
  }

  Future<void> _loadSamples() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final uri = Uri.parse(
        '${ApiConstants.serverUrl}/api/coffee-machine/training?machineName=${Uri.encodeComponent(widget.machineName)}',
      );
      final response = await http.get(uri, headers: ApiConstants.headersWithApiKey).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final all = (data['samples'] as List?) ?? [];
        if (!mounted) return;
        setState(() {
          _samples = all.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteSample(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Color(0xFF1A2E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Удалить фото?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Это фото будет удалено из обучения.\nСистема перестанет использовать его для распознавания.',
          style: TextStyle(color: Colors.white70, fontSize: 14.sp),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Удалить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final uri = Uri.parse('${ApiConstants.serverUrl}/api/coffee-machine/training/$id');
        final response = await http.delete(uri, headers: ApiConstants.headersWithApiKey).timeout(ApiConstants.defaultTimeout);

        if (response.statusCode == 200) {
          if (!mounted) return;
          setState(() {
            _samples.removeWhere((s) => s['id'] == id);
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Фото удалено'), backgroundColor: Colors.green),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  String _photoUrl(String? url) {
    if (url == null) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '${ApiConstants.serverUrl}$url';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              // Header
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Icon(Icons.school, color: AppColors.gold, size: 22),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.machineName,
                            style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Обучающие фото',
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _loadSamples,
                      icon: Icon(Icons.refresh, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              // Count badge
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library, color: AppColors.gold, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '${_samples.length} / 200 фото',
                        style: TextStyle(color: AppColors.gold, fontSize: 14.sp, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 8),
              // Content
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : _samples.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.photo_camera, size: 48, color: Colors.white.withOpacity(0.2)),
                                SizedBox(height: 12),
                                Text(
                                  'Нет обучающих фото',
                                  style: TextStyle(color: Colors.white.withOpacity(0.4)),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Фото появятся после нажатия "Обучить ИИ"\nв просмотре отчёта',
                                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12.sp),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.all(16.w),
                            itemCount: _samples.length,
                            itemBuilder: (_, i) => _buildSampleCard(_samples[i]),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSampleCard(Map<String, dynamic> sample) {
    final photoUrl = sample['photoUrl'] as String? ?? '';
    final correctNumber = sample['correctNumber'];
    final region = sample['selectedRegion'] as Map<String, dynamic>?;
    final trainedBy = sample['trainedBy'] as String? ?? '';
    final createdAt = sample['createdAt'] as String? ?? '';
    final id = sample['id'] as String? ?? '';

    // Форматирование даты
    String dateStr = '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      dateStr = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      dateStr = createdAt;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Фото с красным квадратом
          ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: Stack(
                children: [
                  AppCachedImage(
                    imageUrl: _photoUrl(photoUrl),
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      height: 180,
                      color: Colors.white.withOpacity(0.04),
                      child: Center(child: Icon(Icons.broken_image, color: Colors.white24, size: 40)),
                    ),
                  ),
                  if (region != null)
                    LayoutBuilder(
                      builder: (ctx, constraints) {
                        final w = constraints.maxWidth;
                        final h = 180.0;
                        return Positioned(
                          left: ((region['x'] as num?)?.toDouble() ?? 0) * w,
                          top: ((region['y'] as num?)?.toDouble() ?? 0) * h,
                          width: ((region['width'] as num?)?.toDouble() ?? 0) * w,
                          height: ((region['height'] as num?)?.toDouble() ?? 0) * h,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.red, width: 2.5),
                              color: Colors.red.withOpacity(0.1),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          // Информация
          Padding(
            padding: EdgeInsets.all(12.w),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Число: $correctNumber',
                            style: TextStyle(color: AppColors.gold, fontSize: 16.sp, fontWeight: FontWeight.bold),
                          ),
                          if (region != null) ...[
                            SizedBox(width: 8),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4.r),
                              ),
                              child: Text('Region', style: TextStyle(color: Colors.blue, fontSize: 10.sp)),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        '$dateStr  •  $trainedBy',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11.sp),
                      ),
                    ],
                  ),
                ),
                // Кнопка удалить
                IconButton(
                  onPressed: () => _deleteSample(id),
                  icon: Icon(Icons.delete_outline, color: Colors.red, size: 22),
                  tooltip: 'Удалить',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

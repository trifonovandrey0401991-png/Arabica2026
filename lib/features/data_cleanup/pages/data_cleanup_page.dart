import 'package:flutter/material.dart';
import '../models/cleanup_category.dart';
import '../services/cleanup_service.dart' show CleanupService, DiskInfo;
import '../widgets/cleanup_period_dialog.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/cache_manager.dart';

/// Страница очистки исторических данных сервера.
class DataCleanupPage extends StatefulWidget {
  const DataCleanupPage({super.key});

  @override
  State<DataCleanupPage> createState() => _DataCleanupPageState();
}

class _DataCleanupPageState extends State<DataCleanupPage> {
  List<CleanupCategory> _categories = [];
  DiskInfo? _diskInfo;
  bool _isLoading = true;
  String? _error;

  // Gradient colors — Dark Emerald + Gold theme
  static final _storageGreenGradient = [AppColors.emeraldGreen, AppColors.emeraldGreenLight];
  static final _storageOrangeGradient = [AppColors.warmAmber, AppColors.warmAmberLight];
  static final _storageRedGradient = [AppColors.error, AppColors.errorLight];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  static const _cacheKey = 'data_cleanup_stats';

  Future<void> _loadStats() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<Map<String, dynamic>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _categories = cached['categories'] as List<CleanupCategory>;
        _diskInfo = cached['diskInfo'] as DiskInfo?;
        _isLoading = false;
        _error = null;
      });
    }

    if (_categories.isEmpty && mounted) setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        CleanupService.getDataStats(),
        CleanupService.getDiskInfo(),
      ]);

      if (mounted) {
        final categories = results[0] as List<CleanupCategory>;
        final diskInfo = results[1] as DiskInfo?;
        setState(() {
          _categories = categories;
          _diskInfo = diskInfo;
          _isLoading = false;
        });
        // Step 3: Save to cache
        CacheManager.set(_cacheKey, {
          'categories': categories,
          'diskInfo': diskInfo,
        });
      }
    } catch (e) {
      if (mounted && _categories.isEmpty) {
        setState(() {
          _error = 'Ошибка загрузки данных';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showCleanupDialog(CleanupCategory category) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => CleanupPeriodDialog(category: category),
    );

    if (result == true) {
      // Refresh stats after cleanup
      _loadStats();
    }
  }

  List<Color> _getStorageGradient(double usagePercent) {
    if (usagePercent < 0.5) return _storageGreenGradient;
    if (usagePercent < 0.75) return _storageOrangeGradient;
    return _storageRedGradient;
  }

  Color _getCategoryAccent(int index) {
    const accents = [
      AppColors.gold,
      AppColors.emeraldGreenLight,
      AppColors.warmAmber,
      AppColors.info,
      AppColors.purpleLight,
      AppColors.goldLight,
    ];
    return accents[index % accents.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Очистка Историй'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Container(
            margin: EdgeInsets.only(right: 8.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: AppColors.gold),
              onPressed: _loadStats,
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
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
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Icon(Icons.error_outline, size: 36, color: AppColors.errorLight),
              ),
              SizedBox(height: 20),
              Text(
                _error!,
                style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.6)),
              ),
              SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.gold, AppColors.darkGold]),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: ElevatedButton(
                  onPressed: _loadStats,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 12.h),
                  ),
                  child: Text(
                    'Повторить',
                    style: TextStyle(color: AppColors.night, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_categories.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(color: AppColors.emeraldGreen.withOpacity(0.3)),
                ),
                child: Icon(Icons.check_circle_outline, size: 36, color: AppColors.emeraldGreenLight),
              ),
              SizedBox(height: 20),
              Text(
                'Нет данных для очистки',
                style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.6)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          _buildStorageWidget(),
          SizedBox(height: 16),
          // Section header
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.gold, AppColors.darkGold],
                    ),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Категории данных',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
          ...List.generate(_categories.length, (index) {
            return _buildCategoryCard(_categories[index], index);
          }),
        ],
      ),
    );
  }

  /// Виджет отображения заполненности сервера
  Widget _buildStorageWidget() {
    final totalFiles = _categories.fold<int>(
      0,
      (sum, cat) => sum + cat.count,
    );

    // Используем реальные данные о диске или fallback
    final int usedBytes;
    final int totalBytes;
    final double usagePercent;

    if (_diskInfo != null) {
      usedBytes = _diskInfo!.usedBytes;
      totalBytes = _diskInfo!.totalBytes;
      usagePercent = (usedBytes / totalBytes).clamp(0.0, 1.0);
    } else {
      // Fallback - используем сумму категорий
      usedBytes = _categories.fold<int>(0, (sum, cat) => sum + cat.sizeBytes);
      totalBytes = 10 * 1024 * 1024 * 1024; // 10 GB fallback
      usagePercent = (usedBytes / totalBytes).clamp(0.0, 1.0);
    }

    // Цвет в зависимости от заполненности
    String statusText;
    IconData statusIcon;
    if (usagePercent < 0.5) {
      statusText = 'Свободно';
      statusIcon = Icons.check_circle;
    } else if (usagePercent < 0.75) {
      statusText = 'Умеренно';
      statusIcon = Icons.info;
    } else if (usagePercent < 0.9) {
      statusText = 'Мало места';
      statusIcon = Icons.warning;
    } else {
      statusText = 'Критично!';
      statusIcon = Icons.error;
    }

    final storageGradient = _getStorageGradient(usagePercent);

    // Форматирование размеров
    String formatSize(int bytes) {
      if (bytes >= 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
      } else if (bytes >= 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Gradient header
          Container(
            padding: EdgeInsets.all(18.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: storageGradient,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20.r),
                topRight: Radius.circular(20.r),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      child: Icon(Icons.storage, color: Colors.white, size: 24),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Хранилище сервера',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(statusIcon, color: Colors.white.withOpacity(0.9), size: 14),
                              SizedBox(width: 5),
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Text(
                        '${(usagePercent * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                // Progress bar
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(5.r),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: usagePercent,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(5.r),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Занято: ${formatSize(usedBytes)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13.sp,
                      ),
                    ),
                    Text(
                      'Всего: ${formatSize(totalBytes)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13.sp,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Stats footer
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  icon: Icons.folder,
                  label: 'Категорий',
                  value: '${_categories.length}',
                  color: AppColors.gold,
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: Colors.white.withOpacity(0.1),
                ),
                _buildStatItem(
                  icon: Icons.insert_drive_file,
                  label: 'Файлов',
                  value: _formatNumber(totalFiles),
                  color: AppColors.emeraldGreenLight,
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: Colors.white.withOpacity(0.1),
                ),
                if (_diskInfo != null)
                  _buildStatItem(
                    icon: Icons.sd_storage,
                    label: 'Свободно',
                    value: formatSize(_diskInfo!.availableBytes),
                    color: AppColors.info,
                  )
                else
                  _buildStatItem(
                    icon: Icons.data_usage,
                    label: 'Данные',
                    value: formatSize(usedBytes),
                    color: AppColors.warmAmber,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 15.sp,
            fontWeight: FontWeight.bold,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.sp,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
      ],
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  Widget _buildCategoryCard(CleanupCategory category, int index) {
    final accent = _getCategoryAccent(index);

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          onTap: () => _showCleanupDialog(category),
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Icon(
                    Icons.folder_outlined,
                    color: accent,
                    size: 24,
                  ),
                ),
                SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          _buildInfoChip(
                            icon: Icons.storage,
                            label: category.formattedSize,
                            color: accent,
                          ),
                          SizedBox(width: 6),
                          _buildInfoChip(
                            icon: Icons.description_outlined,
                            label: '${category.count} файлов',
                            color: accent,
                          ),
                        ],
                      ),
                      if (category.oldestDate != null || category.newestDate != null) ...[
                        SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 12,
                              color: Colors.white.withOpacity(0.3),
                            ),
                            SizedBox(width: 5),
                            Text(
                              _formatDateRange(category.oldestDate, category.newestDate),
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Arrow
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    Icons.chevron_right,
                    color: accent,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.sp,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateRange(DateTime? oldest, DateTime? newest) {
    if (oldest == null && newest == null) return '';

    final dateFormat = (DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    if (oldest != null && newest != null) {
      return '${dateFormat(oldest)} — ${dateFormat(newest)}';
    } else if (oldest != null) {
      return 'с ${dateFormat(oldest)}';
    } else {
      return 'до ${dateFormat(newest!)}';
    }
  }
}

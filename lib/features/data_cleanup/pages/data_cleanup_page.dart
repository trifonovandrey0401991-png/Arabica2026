import 'package:flutter/material.dart';
import '../models/cleanup_category.dart';
import '../services/cleanup_service.dart' show CleanupService, DiskInfo;
import '../widgets/cleanup_period_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Загружаем данные параллельно
      final results = await Future.wait([
        CleanupService.getDataStats(),
        CleanupService.getDiskInfo(),
      ]);

      if (mounted) {
        setState(() {
          _categories = results[0] as List<CleanupCategory>;
          _diskInfo = results[1] as DiskInfo?;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Очистка Историй'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadStats,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green[400]),
            const SizedBox(height: 16),
            Text(
              'Нет данных для очистки',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _categories.length + 1, // +1 для виджета заполненности
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildStorageWidget();
          }
          final category = _categories[index - 1];
          return _buildCategoryCard(category);
        },
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
    Color progressColor;
    String statusText;
    if (usagePercent < 0.5) {
      progressColor = Colors.green;
      statusText = 'Свободно';
    } else if (usagePercent < 0.75) {
      progressColor = Colors.orange;
      statusText = 'Умеренно';
    } else if (usagePercent < 0.9) {
      progressColor = Colors.deepOrange;
      statusText = 'Мало места';
    } else {
      progressColor = Colors.red;
      statusText = 'Критично!';
    }

    // Форматирование размеров
    String formatSize(int bytes) {
      if (bytes >= 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
      } else if (bytes >= 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: progressColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.storage, color: progressColor, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Хранилище сервера',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 13,
                          color: progressColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatSize(usedBytes),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'из ${formatSize(totalBytes)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Прогресс-бар
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: usagePercent,
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            const SizedBox(height: 8),
            // Свободно места
            if (_diskInfo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Свободно: ${formatSize(_diskInfo!.availableBytes)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            // Статистика
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatItem(
                  icon: Icons.folder,
                  label: 'Категорий',
                  value: '${_categories.length}',
                ),
                _buildStatItem(
                  icon: Icons.insert_drive_file,
                  label: 'Файлов',
                  value: _formatNumber(totalFiles),
                ),
                _buildStatItem(
                  icon: Icons.pie_chart,
                  label: 'Занято',
                  value: '${(usagePercent * 100).toStringAsFixed(1)}%',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
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

  Widget _buildCategoryCard(CleanupCategory category) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF004D40).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.folder_outlined,
            color: Color(0xFF004D40),
          ),
        ),
        title: Text(
          category.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                _buildInfoChip(
                  icon: Icons.storage,
                  label: category.formattedSize,
                ),
                const SizedBox(width: 8),
                _buildInfoChip(
                  icon: Icons.description_outlined,
                  label: '${category.count} файлов',
                ),
              ],
            ),
            if (category.oldestDate != null || category.newestDate != null) ...[
              const SizedBox(height: 4),
              Text(
                _formatDateRange(category.oldestDate, category.newestDate),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showCleanupDialog(category),
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[700]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
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

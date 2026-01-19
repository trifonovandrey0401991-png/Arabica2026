import 'package:flutter/material.dart';
import '../models/cleanup_category.dart';
import '../services/cleanup_service.dart';
import '../widgets/cleanup_period_dialog.dart';

/// Страница очистки исторических данных сервера.
class DataCleanupPage extends StatefulWidget {
  const DataCleanupPage({super.key});

  @override
  State<DataCleanupPage> createState() => _DataCleanupPageState();
}

class _DataCleanupPageState extends State<DataCleanupPage> {
  List<CleanupCategory> _categories = [];
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
      final categories = await CleanupService.getDataStats();
      if (mounted) {
        setState(() {
          _categories = categories;
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
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          return _buildCategoryCard(category);
        },
      ),
    );
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

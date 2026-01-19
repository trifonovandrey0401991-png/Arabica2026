import 'package:flutter/material.dart';
import '../models/cigarette_training_model.dart';
import '../services/cigarette_vision_service.dart';
import '../../../core/constants/api_constants.dart';

/// Страница настроек обучения ИИ
/// Позволяет изменять количество требуемых фото и удалять некачественные фото
class TrainingSettingsPage extends StatefulWidget {
  final List<CigaretteProduct> products;
  final VoidCallback onSettingsChanged;

  const TrainingSettingsPage({
    super.key,
    required this.products,
    required this.onSettingsChanged,
  });

  @override
  State<TrainingSettingsPage> createState() => _TrainingSettingsPageState();
}

class _TrainingSettingsPageState extends State<TrainingSettingsPage> {
  TrainingSettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;

  int _requiredRecountPhotos = 10;
  int _requiredDisplayPhotos = 10;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final settings = await CigaretteVisionService.getSettings();

    if (mounted) {
      setState(() {
        _settings = settings;
        if (settings != null) {
          _requiredRecountPhotos = settings.requiredRecountPhotos;
          _requiredDisplayPhotos = settings.requiredDisplayPhotos;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    final updated = await CigaretteVisionService.updateSettings(
      requiredRecountPhotos: _requiredRecountPhotos,
      requiredDisplayPhotos: _requiredDisplayPhotos,
    );

    if (mounted) {
      setState(() => _isSaving = false);

      if (updated != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Настройки сохранены'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSettingsChanged();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка сохранения настроек'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Секция настроек количества фото
        _buildSettingsSection(),
        const SizedBox(height: 24),

        // Секция управления фото по товарам
        _buildPhotosManagementSection(),
      ],
    );
  }

  Widget _buildSettingsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, color: Color(0xFF004D40)),
                const SizedBox(width: 8),
                const Text(
                  'Количество фото для обучения',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Если распознавание работает неточно, увеличьте количество требуемых фото',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),

            // Крупный план
            _buildSettingRow(
              icon: Icons.crop_free,
              iconColor: Colors.blue,
              title: 'Крупный план (шаблоны)',
              subtitle: '1-3 пачки вблизи',
              value: _requiredRecountPhotos,
              min: 5,
              max: 30,
              onChanged: (value) {
                setState(() => _requiredRecountPhotos = value);
              },
            ),
            const Divider(),

            // Выкладка
            _buildSettingRow(
              icon: Icons.grid_view,
              iconColor: Colors.orange,
              title: 'Выкладка',
              subtitle: 'Фото витрины с 5-15 пачками',
              value: _requiredDisplayPhotos,
              min: 5,
              max: 30,
              onChanged: (value) {
                setState(() => _requiredDisplayPhotos = value);
              },
            ),
            const SizedBox(height: 16),

            // Кнопка сохранения
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'Сохранение...' : 'Сохранить настройки'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          // Кнопки -/+
          Row(
            children: [
              IconButton(
                onPressed: value > min
                    ? () => onChanged(value - 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: Colors.red,
              ),
              Container(
                width: 40,
                alignment: Alignment.center,
                child: Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: value < max
                    ? () => onChanged(value + 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
                color: Colors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotosManagementSection() {
    // Фильтруем товары с фото
    final productsWithPhotos = widget.products
        .where((p) => p.trainingPhotosCount > 0)
        .toList()
      ..sort((a, b) => b.trainingPhotosCount.compareTo(a.trainingPhotosCount));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_library, color: Color(0xFF004D40)),
                const SizedBox(width: 8),
                const Text(
                  'Управление фотографиями',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите на товар чтобы просмотреть и удалить некачественные фото',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),

            if (productsWithPhotos.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'Нет загруженных фото',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...productsWithPhotos.map((product) => _buildProductPhotoCard(product)),
          ],
        ),
      ),
    );
  }

  Widget _buildProductPhotoCard(CigaretteProduct product) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey[50],
      child: InkWell(
        onTap: () => _openProductSamples(product),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Иконка
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.photo_camera, color: Colors.blue),
              ),
              const SizedBox(width: 12),

              // Название и количество
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.productName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.crop_free, size: 14, color: Colors.blue[700]),
                        const SizedBox(width: 4),
                        Text(
                          '${product.recountPhotosCount}',
                          style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.grid_view, size: 14, color: Colors.orange[700]),
                        const SizedBox(width: 4),
                        Text(
                          '${product.displayPhotosCount}',
                          style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                        ),
                        const Spacer(),
                        Text(
                          'Всего: ${product.trainingPhotosCount}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Стрелка
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openProductSamples(CigaretteProduct product) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => _ProductSamplesPage(product: product),
      ),
    );

    if (result == true && mounted) {
      widget.onSettingsChanged();
    }
  }
}

/// Страница просмотра и удаления фото для конкретного товара
class _ProductSamplesPage extends StatefulWidget {
  final CigaretteProduct product;

  const _ProductSamplesPage({required this.product});

  @override
  State<_ProductSamplesPage> createState() => _ProductSamplesPageState();
}

class _ProductSamplesPageState extends State<_ProductSamplesPage> {
  List<TrainingSample> _samples = [];
  bool _isLoading = true;
  String? _selectedType;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadSamples();
  }

  Future<void> _loadSamples() async {
    setState(() => _isLoading = true);

    final samples = await CigaretteVisionService.getSamplesForProduct(
      widget.product.id,
    );

    if (mounted) {
      setState(() {
        _samples = samples;
        _isLoading = false;
      });
    }
  }

  List<TrainingSample> get _filteredSamples {
    if (_selectedType == null) return _samples;
    return _samples.where((s) => s.type.value == _selectedType).toList();
  }

  Future<void> _deleteSample(TrainingSample sample) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить фото?'),
        content: const Text(
          'Это действие нельзя отменить. '
          'Фото будет удалено из обучающей выборки.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await CigaretteVisionService.deleteSample(sample.id);

    if (mounted) {
      if (success) {
        setState(() {
          _samples.removeWhere((s) => s.id == sample.id);
          _hasChanges = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Фото удалено'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка удаления'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _hasChanges);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.product.productName,
            style: const TextStyle(fontSize: 16),
          ),
          backgroundColor: const Color(0xFF004D40),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _hasChanges),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_samples.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Нет фото для этого товара',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    final recountCount = _samples.where((s) => s.type == TrainingSampleType.recount).length;
    final displayCount = _samples.where((s) => s.type == TrainingSampleType.display).length;

    return Column(
      children: [
        // Фильтр по типу
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: _buildTypeFilterChip(
                  null,
                  'Все (${_samples.length})',
                  Icons.photo_library,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTypeFilterChip(
                  'recount',
                  'Крупный ($recountCount)',
                  Icons.crop_free,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTypeFilterChip(
                  'display',
                  'Выкладка ($displayCount)',
                  Icons.grid_view,
                ),
              ),
            ],
          ),
        ),

        // Сетка фото
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadSamples,
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _filteredSamples.length,
              itemBuilder: (context, index) {
                return _buildSampleCard(_filteredSamples[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeFilterChip(String? type, String label, IconData icon) {
    final isSelected = _selectedType == type;

    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      onSelected: (selected) {
        setState(() => _selectedType = selected ? type : null);
      },
      selectedColor: const Color(0xFF004D40).withOpacity(0.2),
      checkmarkColor: const Color(0xFF004D40),
    );
  }

  Widget _buildSampleCard(TrainingSample sample) {
    final imageUrl = '${ApiConstants.serverUrl}${sample.imageUrl}';
    final isRecount = sample.type == TrainingSampleType.recount;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Изображение
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: Colors.grey[200],
                child: const Center(child: CircularProgressIndicator()),
              );
            },
          ),

          // Тип фото (badge)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isRecount ? Colors.blue : Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isRecount ? Icons.crop_free : Icons.grid_view,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isRecount ? 'Крупный' : 'Выкладка',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Номер шаблона (если есть)
          if (sample.templateId != null)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.blue[700],
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${sample.templateId}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

          // Количество аннотаций
          if (sample.annotationCount > 0)
            Positioned(
              bottom: 40,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${sample.annotationCount} пачек',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ),
            ),

          // Кнопка удаления
          Positioned(
            bottom: 8,
            right: 8,
            child: Material(
              color: Colors.red,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () => _deleteSample(sample),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.delete, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),

          // Дата внизу слева
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDate(sample.createdAt),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
  }
}

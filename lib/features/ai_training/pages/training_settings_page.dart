import 'package:flutter/material.dart';
import '../models/cigarette_training_model.dart';
import '../services/cigarette_vision_service.dart';
import '../../../core/constants/api_constants.dart';

/// Страница настроек обучения ИИ
/// Позволяет изменять количество требуемых фото и удалять некачественные фото
class TrainingSettingsPage extends StatefulWidget {
  final List<CigaretteProduct>? products;
  final VoidCallback? onSettingsChanged;

  const TrainingSettingsPage({
    super.key,
    this.products,
    this.onSettingsChanged,
  });

  @override
  State<TrainingSettingsPage> createState() => _TrainingSettingsPageState();
}

class _TrainingSettingsPageState extends State<TrainingSettingsPage> {
  TrainingSettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;

  int _requiredRecountPhotos = 10;
  int _requiredDisplayPhotosPerShop = 3;
  String _catalogSource = 'recount-questions';

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
          _requiredDisplayPhotosPerShop = settings.requiredDisplayPhotosPerShop;
          _catalogSource = settings.catalogSource;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    final updated = await CigaretteVisionService.updateSettings(
      requiredRecountPhotos: _requiredRecountPhotos,
      requiredDisplayPhotosPerShop: _requiredDisplayPhotosPerShop,
      catalogSource: _catalogSource,
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
        widget.onSettingsChanged?.call();
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

  /// Проверка, открыта ли страница как отдельный экран (не как вкладка)
  bool get _isStandalonePage => widget.products == null;

  @override
  Widget build(BuildContext context) {
    final content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Секция источника каталога
              _buildCatalogSourceSection(),
              const SizedBox(height: 24),

              // Секция настроек количества фото
              _buildSettingsSection(),
              const SizedBox(height: 24),

              // Секция управления фото по товарам
              _buildPhotosManagementSection(),
            ],
          );

    // Если открыто как отдельная страница - оборачиваем в Scaffold с AppBar
    if (_isStandalonePage) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Настройки обучения'),
          backgroundColor: const Color(0xFF004D40),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: content,
      );
    }

    return content;
  }

  Widget _buildCatalogSourceSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_copy, color: Color(0xFF004D40)),
                const SizedBox(width: 8),
                const Text(
                  'Источник каталога товаров',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Выберите откуда брать список товаров для обучения',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),

            // Опция: Вопросы пересчёта (текущий)
            _buildCatalogSourceOption(
              value: 'recount-questions',
              title: 'Вопросы пересчёта',
              subtitle: 'Текущий каталог (список из пересчёта)',
              icon: Icons.quiz,
              iconColor: Colors.blue,
            ),
            const SizedBox(height: 8),

            // Опция: Мастер-каталог (новый)
            _buildCatalogSourceOption(
              value: 'master-catalog',
              title: 'Мастер-каталог',
              subtitle: 'Единый каталог для всех магазинов (в разработке)',
              icon: Icons.inventory_2,
              iconColor: Colors.orange,
              isDisabled: true, // Пока недоступен
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogSourceOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    bool isDisabled = false,
  }) {
    final isSelected = _catalogSource == value;

    return InkWell(
      onTap: isDisabled
          ? null
          : () {
              setState(() => _catalogSource = value);
            },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? const Color(0xFF004D40)
                : (isDisabled ? Colors.grey[300]! : Colors.grey[400]!),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? const Color(0xFF004D40).withOpacity(0.05)
              : (isDisabled ? Colors.grey[100] : null),
        ),
        child: Row(
          children: [
            // Radio button
            Radio<String>(
              value: value,
              groupValue: _catalogSource,
              onChanged: isDisabled
                  ? null
                  : (val) {
                      if (val != null) setState(() => _catalogSource = val);
                    },
              activeColor: const Color(0xFF004D40),
            ),

            // Icon
            Icon(
              icon,
              color: isDisabled ? Colors.grey : iconColor,
              size: 28,
            ),
            const SizedBox(width: 12),

            // Title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDisabled ? Colors.grey : null,
                        ),
                      ),
                      if (isDisabled) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Скоро',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDisabled ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            // Checkmark for selected
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF004D40),
              ),
          ],
        ),
      ),
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

            // Выкладка (на магазин)
            _buildSettingRow(
              icon: Icons.grid_view,
              iconColor: Colors.orange,
              title: 'Выкладка (на магазин)',
              subtitle: 'Каждый магазин должен добавить свои фото',
              value: _requiredDisplayPhotosPerShop,
              min: 1,
              max: 10,
              onChanged: (value) {
                setState(() => _requiredDisplayPhotosPerShop = value);
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
    final productsWithPhotos = (widget.products ?? [])
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
                        const SizedBox(width: 12),
                        Icon(Icons.calculate, size: 14, color: Colors.green[700]),
                        const SizedBox(width: 4),
                        Text(
                          '${product.countingPhotosCount}',
                          style: TextStyle(fontSize: 12, color: Colors.green[700]),
                        ),
                        // Показываем pending фото если есть
                        if (product.pendingCountingPhotosCount > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.amber[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.hourglass_empty, size: 10, color: Colors.amber[800]),
                                const SizedBox(width: 2),
                                Text(
                                  '${product.pendingCountingPhotosCount}',
                                  style: TextStyle(fontSize: 10, color: Colors.amber[800], fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          'Всего: ${product.trainingPhotosCount + product.countingPhotosCount}',
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
      widget.onSettingsChanged?.call();
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

    // Загружаем обычные образцы
    final samples = await CigaretteVisionService.getSamplesForProduct(
      widget.product.id,
    );

    // Загружаем pending образцы
    final pendingSamples = await CigaretteVisionService.getPendingCountingSamplesForProduct(
      widget.product.id,
    );

    if (mounted) {
      setState(() {
        _samples = [...samples, ...pendingSamples];
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

  /// Подтвердить pending фото (переместить в обучение)
  Future<void> _approvePendingSample(TrainingSample sample) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтвердить фото?'),
        content: const Text(
          'Фото будет добавлено в обучающую выборку.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await CigaretteVisionService.approvePendingCountingSample(sample.id);

    if (mounted) {
      if (success) {
        setState(() {
          _samples.removeWhere((s) => s.id == sample.id);
          _hasChanges = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Фото добавлено в обучение'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка подтверждения'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Отклонить pending фото (удалить)
  Future<void> _rejectPendingSample(TrainingSample sample) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отклонить фото?'),
        content: const Text(
          'Фото будет удалено и не попадёт в обучение.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Отклонить'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await CigaretteVisionService.rejectPendingCountingSample(sample.id);

    if (mounted) {
      if (success) {
        setState(() {
          _samples.removeWhere((s) => s.id == sample.id);
          _hasChanges = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Фото отклонено'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка отклонения'),
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
    final countingCount = _samples.where((s) => s.type == TrainingSampleType.counting).length;
    final pendingCount = _samples.where((s) => s.type == TrainingSampleType.countingPending).length;

    return Column(
      children: [
        // Фильтр по типу
        Container(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTypeFilterChip(
                null,
                'Все (${_samples.length})',
                Icons.photo_library,
              ),
              _buildTypeFilterChip(
                'recount',
                'Крупный ($recountCount)',
                Icons.crop_free,
              ),
              _buildTypeFilterChip(
                'display',
                'Выкладка ($displayCount)',
                Icons.grid_view,
              ),
              _buildTypeFilterChip(
                'counting',
                'Пересчёт ($countingCount)',
                Icons.calculate,
              ),
              // Ожидающие подтверждения (если есть)
              if (pendingCount > 0)
                _buildTypeFilterChip(
                  'counting-pending',
                  'Ожидание ($pendingCount)',
                  Icons.hourglass_empty,
                  badgeColor: Colors.amber,
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

  Widget _buildTypeFilterChip(String? type, String label, IconData icon, {Color? badgeColor}) {
    final isSelected = _selectedType == type;
    final chipColor = badgeColor ?? const Color(0xFF004D40);

    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: badgeColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: badgeColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      onSelected: (selected) {
        setState(() => _selectedType = selected ? type : null);
      },
      selectedColor: chipColor.withOpacity(0.2),
      checkmarkColor: chipColor,
    );
  }

  Widget _buildSampleCard(TrainingSample sample) {
    final imageUrl = '${ApiConstants.serverUrl}${sample.imageUrl}';

    // Определяем цвет, иконку и текст по типу
    final Color badgeColor;
    final IconData badgeIcon;
    final String badgeText;

    switch (sample.type) {
      case TrainingSampleType.recount:
        badgeColor = Colors.blue;
        badgeIcon = Icons.crop_free;
        badgeText = 'Крупный';
        break;
      case TrainingSampleType.display:
        badgeColor = Colors.orange;
        badgeIcon = Icons.grid_view;
        badgeText = 'Выкладка';
        break;
      case TrainingSampleType.counting:
        badgeColor = Colors.green;
        badgeIcon = Icons.calculate;
        badgeText = 'Пересчёт';
        break;
      case TrainingSampleType.countingPending:
        badgeColor = Colors.amber;
        badgeIcon = Icons.hourglass_empty;
        badgeText = 'Ожидание';
        break;
    }

    final isPending = sample.type == TrainingSampleType.countingPending;

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
                color: badgeColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    badgeIcon,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    badgeText,
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

          // Кнопки действий (approve/reject для pending, delete для остальных)
          Positioned(
            bottom: 8,
            right: 8,
            child: isPending
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Одобрить
                      Material(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          onTap: () => _approvePendingSample(sample),
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.check, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Отклонить
                      Material(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          onTap: () => _rejectPendingSample(sample),
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ],
                  )
                : Material(
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

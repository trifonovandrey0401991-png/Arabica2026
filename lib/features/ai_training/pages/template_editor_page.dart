import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/z_report_template_model.dart';
import '../widgets/region_selector_widget.dart';
import '../services/z_report_template_service.dart';

/// Страница создания/редактирования шаблона распознавания
class TemplateEditorPage extends StatefulWidget {
  final ZReportTemplate? existingTemplate;
  final String? shopId;
  final String? shopAddress;

  const TemplateEditorPage({
    super.key,
    this.existingTemplate,
    this.shopId,
    this.shopAddress,
  });

  @override
  State<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends State<TemplateEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _uuid = const Uuid();

  // Список наборов областей (форматов)
  List<RegionSet> _regionSets = [];
  int _currentSetIndex = 0;

  // Изображения для каждого набора
  Map<String, Uint8List> _setImages = {};

  String? _selectedField;
  String _cashRegisterType = CashRegisterTypes.atol;
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingTemplate != null) {
      _nameController.text = widget.existingTemplate!.name;
      _cashRegisterType =
          widget.existingTemplate!.cashRegisterType ?? CashRegisterTypes.atol;

      // Загружаем наборы областей
      if (widget.existingTemplate!.regionSets.isNotEmpty) {
        _regionSets = widget.existingTemplate!.regionSets
            .map((s) => s.copyWith(regions: List.from(s.regions)))
            .toList();
      } else {
        // Создаём первый формат
        _regionSets = [
          RegionSet(id: _uuid.v4(), name: 'Формат 1', regions: []),
        ];
      }

      // Загружаем изображение первого формата
      _loadTemplateImage();
    } else {
      // Новый шаблон — создаём первый формат
      _regionSets = [
        RegionSet(id: _uuid.v4(), name: 'Формат 1', regions: []),
      ];
    }
  }

  Future<void> _loadTemplateImage() async {
    if (widget.existingTemplate?.id == null ||
        widget.existingTemplate!.id.isEmpty) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Загружаем изображения для каждого формата
      for (final regionSet in _regionSets) {
        final imageBytes = await ZReportTemplateService.getRegionSetImage(
          widget.existingTemplate!.id,
          regionSet.id,
        );

        if (imageBytes != null && mounted) {
          setState(() {
            _setImages[regionSet.id] = imageBytes;
          });
        }
      }
    } catch (e) {
      print('Ошибка загрузки изображений шаблона: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Текущий набор областей
  RegionSet get _currentSet => _regionSets[_currentSetIndex];

  // Текущее изображение
  Uint8List? get _currentImage => _setImages[_currentSet.id];

  // Текущие области
  List<FieldRegion> get _currentRegions => _currentSet.regions;

  void _addNewFormat() {
    final newSet = RegionSet(
      id: _uuid.v4(),
      name: 'Формат ${_regionSets.length + 1}',
      regions: [],
    );
    setState(() {
      _regionSets.add(newSet);
      _currentSetIndex = _regionSets.length - 1;
      _selectedField = null;
    });
  }

  void _deleteCurrentFormat() {
    if (_regionSets.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нельзя удалить единственный формат'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить формат?'),
        content: Text('Формат "${_currentSet.name}" будет удалён.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _setImages.remove(_currentSet.id);
                _regionSets.removeAt(_currentSetIndex);
                if (_currentSetIndex >= _regionSets.length) {
                  _currentSetIndex = _regionSets.length - 1;
                }
              });
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _renameCurrentFormat() {
    final controller = TextEditingController(text: _currentSet.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать формат'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Название формата',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _regionSets[_currentSetIndex] =
                      _currentSet.copyWith(name: controller.text.trim());
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 2400,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _setImages[_currentSet.id] = bytes;
          // Сбрасываем области для текущего набора
          _regionSets[_currentSetIndex] =
              _currentSet.copyWith(regions: []);
        });
      }
    } catch (e) {
      _showError('Ошибка выбора изображения: $e');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 2400,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _setImages[_currentSet.id] = bytes;
          _regionSets[_currentSetIndex] =
              _currentSet.copyWith(regions: []);
        });
      }
    } catch (e) {
      _showError('Ошибка камеры: $e');
    }
  }

  void _selectField(String fieldName) {
    setState(() {
      _selectedField = _selectedField == fieldName ? null : fieldName;
    });
  }

  void _onRegionsChanged(List<FieldRegion> regions) {
    setState(() {
      _regionSets[_currentSetIndex] = _currentSet.copyWith(regions: regions);
    });
  }

  Future<void> _saveTemplate() async {
    if (!_formKey.currentState!.validate()) return;

    // Проверяем что есть хотя бы одно изображение
    if (_setImages.isEmpty) {
      _showError('Загрузите хотя бы одно фото Z-отчёта');
      return;
    }

    // Проверяем что хотя бы один набор имеет области
    final hasRegions = _regionSets.any((s) => s.regions.isNotEmpty);
    if (!hasRegions) {
      _showError('Выделите хотя бы одну область');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final template = ZReportTemplate(
        id: widget.existingTemplate?.id ?? '',
        name: _nameController.text.trim(),
        shopId: widget.shopId,
        shopAddress: widget.shopAddress,
        cashRegisterType: _cashRegisterType,
        regionSets: _regionSets,
        customPatterns: [],
        createdAt: widget.existingTemplate?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Берём изображение первого набора как основное
      Uint8List? mainImage;
      if (_regionSets.isNotEmpty && _setImages.containsKey(_regionSets[0].id)) {
        mainImage = _setImages[_regionSets[0].id];
      } else if (_setImages.isNotEmpty) {
        mainImage = _setImages.values.first;
      }

      final success = await ZReportTemplateService.saveTemplate(
        template: template,
        sampleImageBase64: mainImage,
        regionSetImages: _setImages, // Передаём все изображения форматов
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Шаблон сохранён'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        _showError('Не удалось сохранить шаблон');
      }
    } catch (e) {
      _showError('Ошибка: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingTemplate != null
            ? 'Редактировать шаблон'
            : 'Новый шаблон'),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveTemplate,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Форма настроек
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Название шаблона
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Название шаблона',
                      hintText: 'Например: АТОЛ Белопольского 2',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Введите название' : null,
                  ),
                  const SizedBox(height: 12),
                  // Тип кассы
                  DropdownButtonFormField<String>(
                    value: _cashRegisterType,
                    decoration: const InputDecoration(
                      labelText: 'Тип кассы',
                      border: OutlineInputBorder(),
                    ),
                    items: CashRegisterTypes.all
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _cashRegisterType = v);
                    },
                  ),
                ],
              ),
            ),

            // Переключатель форматов
            _buildFormatSelector(),

            // Кнопки выбора поля для выделения
            _buildFieldSelector(),
            const SizedBox(height: 8),

            // Область изображения
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _currentImage == null
                      ? _buildImagePlaceholder()
                      : RegionSelectorWidget(
                          imageBytes: _currentImage!,
                          initialRegions: _currentRegions,
                          currentField: _selectedField,
                          onRegionsChanged: _onRegionsChanged,
                        ),
            ),

            // Инструкция
            if (_currentImage != null && _selectedField != null)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.blue.shade50,
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Выделите область для "${FieldNames.getDisplayName(_selectedField!)}" на фото',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          // Выпадающий список форматов
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _currentSetIndex,
              decoration: InputDecoration(
                labelText: 'Формат чека',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: Colors.white,
              ),
              items: _regionSets.asMap().entries.map((entry) {
                final set = entry.value;
                final hasImage = _setImages.containsKey(set.id);
                final hasRegions = set.regions.isNotEmpty;
                return DropdownMenuItem(
                  value: entry.key,
                  child: Row(
                    children: [
                      Text(set.name),
                      const SizedBox(width: 8),
                      if (hasImage && hasRegions)
                        const Icon(Icons.check_circle,
                            size: 16, color: Colors.green)
                      else if (hasImage)
                        const Icon(Icons.image, size: 16, color: Colors.blue)
                      else
                        const Icon(Icons.add_photo_alternate,
                            size: 16, color: Colors.grey),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (index) {
                if (index != null) {
                  setState(() {
                    _currentSetIndex = index;
                    _selectedField = null;
                  });
                }
              },
            ),
          ),
          const SizedBox(width: 8),

          // Кнопка добавить формат
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.green),
            tooltip: 'Добавить формат',
            onPressed: _addNewFormat,
          ),

          // Меню для текущего формата
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'rename') {
                _renameCurrentFormat();
              } else if (value == 'delete') {
                _deleteCurrentFormat();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 20),
                    SizedBox(width: 8),
                    Text('Переименовать'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Удалить', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFieldSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text('Выделить: ', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              children: FieldNames.all.map((fieldName) {
                final isSelected = _selectedField == fieldName;
                final hasRegion =
                    _currentRegions.any((r) => r.fieldName == fieldName);

                return FilterChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(FieldNames.getDisplayName(fieldName)),
                      if (hasRegion) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.check, size: 14),
                      ],
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (_) => _selectField(fieldName),
                  selectedColor: Colors.blue.shade100,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Загрузите фото Z-отчёта\nдля формата "${_currentSet.name}"',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_library),
                label: const Text('Галерея'),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _takePhoto,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Камера'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

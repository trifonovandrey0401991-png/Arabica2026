import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../services/coffee_machine_template_service.dart';
import '../models/coffee_machine_template_model.dart';
import '../../shops/services/shop_service.dart';
import 'coffee_machine_training_photos_page.dart';

/// Управление счётчиком кофемашин: шаблоны, привязки, обучающие фото
class CoffeeMachineQuestionsManagementPage extends StatefulWidget {
  const CoffeeMachineQuestionsManagementPage({super.key});

  @override
  State<CoffeeMachineQuestionsManagementPage> createState() => _CoffeeMachineQuestionsManagementPageState();
}

class _CoffeeMachineQuestionsManagementPageState extends State<CoffeeMachineQuestionsManagementPage> {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  final _imagePicker = ImagePicker();

  bool _isLoading = true;
  List<CoffeeMachineTemplate> _templates = [];
  List<CoffeeMachineShopConfig> _shopConfigs = [];
  List<String> _shopAddresses = [];
  Map<String, int> _trainingCounts = {}; // machineName → count

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        CoffeeMachineTemplateService.getTemplates(),
        CoffeeMachineTemplateService.getAllShopConfigs(),
        ShopService.getShops().then((shops) => shops.map((s) => s.address).toList()),
        _loadTrainingStats(),
      ]);
      setState(() {
        _templates = results[0] as List<CoffeeMachineTemplate>;
        _shopConfigs = results[1] as List<CoffeeMachineShopConfig>;
        _shopAddresses = results[2] as List<String>;
        _trainingCounts = results[3] as Map<String, int>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, int>> _loadTrainingStats() async {
    try {
      final uri = Uri.parse('${ApiConstants.serverUrl}/api/coffee-machine/training/stats');
      final response = await http.get(uri, headers: ApiConstants.headersWithApiKey).timeout(ApiConstants.defaultTimeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final byMachine = data['byMachine'] as Map<String, dynamic>? ?? {};
        return byMachine.map((k, v) => MapEntry(k, (v as num).toInt()));
      }
    } catch (_) {}
    return {};
  }

  @override
  Widget build(BuildContext context) {
    final configuredShops = _shopConfigs.where((c) => c.machineTemplateIds.isNotEmpty).length;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const Icon(Icons.coffee_outlined, color: _gold, size: 22),
                    const SizedBox(width: 8),
                    const Text(
                      'Счётчик кофемашин',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: _gold))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Статистика
                            _buildStatsCard(configuredShops),
                            const SizedBox(height: 20),
                            // Шаблоны
                            Row(
                              children: [
                                Text(
                                  'Шаблоны машин',
                                  style: TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: _addTemplate,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _gold.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: _gold.withOpacity(0.3)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.add, color: _gold, size: 16),
                                        SizedBox(width: 4),
                                        Text('Создать', style: TextStyle(color: _gold, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (_templates.isEmpty)
                              _buildEmptyCard('Нет шаблонов. Нажмите "Создать"')
                            else
                              ..._templates.map(_buildTemplateCard),
                            const SizedBox(height: 20),
                            // Привязки к магазинам
                            Text(
                              'Привязки к магазинам',
                              style: TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            if (_shopAddresses.isEmpty)
                              _buildEmptyCard('Нет магазинов')
                            else
                              ..._shopAddresses.map(_buildShopCard),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard(int configuredShops) {
    final totalTraining = _trainingCounts.values.fold<int>(0, (s, v) => s + v);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('${_templates.length}', 'Шаблонов'),
          Container(width: 1, height: 30, color: Colors.white.withOpacity(0.1)),
          _buildStatItem('$configuredShops', 'Магазинов'),
          Container(width: 1, height: 30, color: Colors.white.withOpacity(0.1)),
          _buildStatItem('$totalTraining', 'Фото ИИ'),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: _gold, fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
      ],
    );
  }

  Widget _buildEmptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
    );
  }

  // ============ Шаблоны ============

  Widget _buildTemplateCard(CoffeeMachineTemplate template) {
    final trainingCount = _trainingCounts[template.name] ?? 0;

    return GestureDetector(
      onTap: () => _openTrainingPhotos(template),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.coffee, color: _gold, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        CoffeeMachineTypes.getDisplayName(template.machineType),
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        OcrPresets.getDisplayName(template.ocrPreset),
                        style: TextStyle(color: _gold.withOpacity(0.5), fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Бейдж с количеством обучающих фото
            if (trainingCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.school, color: Colors.green, size: 12),
                    const SizedBox(width: 3),
                    Text('$trainingCount', style: const TextStyle(color: Colors.green, fontSize: 11)),
                  ],
                ),
              ),
            if (trainingCount == 0)
              Text('0 фото', style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 11)),
            const SizedBox(width: 4),
            // Меню: редактировать/удалить
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.4), size: 20),
              color: const Color(0xFF1A2E2E),
              onSelected: (action) {
                if (action == 'edit') _editTemplate(template);
                if (action == 'delete') _deleteTemplate(template);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: Colors.white70, size: 18),
                      SizedBox(width: 8),
                      Text('Редактировать', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Удалить', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openTrainingPhotos(CoffeeMachineTemplate template) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoffeeMachineTrainingPhotosPage(
          machineName: template.name,
          preset: template.ocrPreset,
        ),
      ),
    ).then((_) => _loadData()); // Обновить счётчики после возврата
  }

  Future<void> _addTemplate() async {
    final result = await _showTemplateDialog();
    if (result != null) {
      final saved = await CoffeeMachineTemplateService.saveTemplate(
        template: result['template'] as CoffeeMachineTemplate,
        referenceImage: result['image'] as Uint8List?,
      );
      if (saved) _loadData();
    }
  }

  Future<void> _editTemplate(CoffeeMachineTemplate template) async {
    final result = await _showTemplateDialog(existing: template);
    if (result != null) {
      final saved = await CoffeeMachineTemplateService.updateTemplate(
        template: result['template'] as CoffeeMachineTemplate,
        referenceImage: result['image'] as Uint8List?,
      );
      if (saved) _loadData();
    }
  }

  Future<void> _deleteTemplate(CoffeeMachineTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Удалить шаблон?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Удалить "${template.name}"?\nОбучающие фото для этого шаблона останутся.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CoffeeMachineTemplateService.deleteTemplate(template.id);
      _loadData();
    }
  }

  Future<Map<String, dynamic>?> _showTemplateDialog({CoffeeMachineTemplate? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    String selectedType = existing?.machineType ?? CoffeeMachineTypes.wmf;
    if (!CoffeeMachineTypes.all.contains(selectedType)) {
      selectedType = CoffeeMachineTypes.other;
    }
    String selectedPreset = existing?.ocrPreset ?? OcrPresets.standard;
    Uint8List? imageBytes;

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A2E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              existing != null ? 'Редактировать шаблон' : 'Новый шаблон',
              style: const TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Название',
                      hintText: 'WMF 1500S',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _gold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    dropdownColor: const Color(0xFF1A2E2E),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Тип машины',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _gold),
                      ),
                    ),
                    items: CoffeeMachineTypes.all.map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(CoffeeMachineTypes.getDisplayName(type)),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedType = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedPreset,
                    dropdownColor: const Color(0xFF1A2E2E),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Пресет OCR',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _gold),
                      ),
                    ),
                    items: OcrPresets.all.map((preset) => DropdownMenuItem(
                      value: preset,
                      child: Text(OcrPresets.getDisplayName(preset)),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedPreset = v);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      OcrPresets.getDescription(selectedPreset),
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await _imagePicker.pickImage(
                        source: ImageSource.camera,
                        maxWidth: 1920,
                        imageQuality: 85,
                      );
                      if (picked != null) {
                        final bytes = await File(picked.path).readAsBytes();
                        setDialogState(() => imageBytes = bytes);
                      }
                    },
                    icon: Icon(
                      imageBytes != null ? Icons.check_circle : Icons.camera_alt,
                      color: imageBytes != null ? Colors.green : _gold,
                    ),
                    label: Text(
                      imageBytes != null ? 'Фото загружено' : 'Эталонное фото',
                      style: TextStyle(color: imageBytes != null ? Colors.green : _gold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: (imageBytes != null ? Colors.green : _gold).withOpacity(0.4)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.6))),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.isEmpty) return;
                  final template = CoffeeMachineTemplate(
                    id: existing?.id ?? 'tmpl_${DateTime.now().millisecondsSinceEpoch}',
                    name: nameController.text,
                    machineType: selectedType,
                    referencePhotoUrl: existing?.referencePhotoUrl,
                    counterRegion: existing?.counterRegion,
                    ocrPreset: selectedPreset,
                    createdAt: existing?.createdAt ?? DateTime.now(),
                    updatedAt: DateTime.now(),
                  );
                  Navigator.pop(context, {'template': template, 'image': imageBytes});
                },
                style: ElevatedButton.styleFrom(backgroundColor: _gold),
                child: const Text('Сохранить', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============ Магазины (привязки) ============

  Widget _buildShopCard(String address) {
    final config = _shopConfigs.where((c) => c.shopAddress == address).firstOrNull;
    final assignedCount = config?.machineTemplateIds.length ?? 0;
    final templateNames = config?.machineTemplateIds
        .map((id) {
          final t = _templates.where((t) => t.id == id).firstOrNull;
          return t?.name ?? id;
        })
        .join(', ') ?? '';

    return GestureDetector(
      onTap: () => _editShopConfig(address, config),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: assignedCount > 0 ? _gold.withOpacity(0.15) : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.store,
              color: assignedCount > 0 ? _gold : Colors.white30,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (assignedCount > 0)
                    Text(
                      templateNames,
                      style: TextStyle(color: _gold.withOpacity(0.7), fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      'Не настроено',
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _editShopConfig(String shopAddress, CoffeeMachineShopConfig? existing) async {
    final selected = Set<String>.from(existing?.machineTemplateIds ?? []);

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A2E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              shopAddress,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: _templates.isEmpty
                  ? const Text('Сначала создайте шаблоны', style: TextStyle(color: Colors.white70))
                  : ListView(
                      shrinkWrap: true,
                      children: _templates.map((t) {
                        final isSelected = selected.contains(t.id);
                        return CheckboxListTile(
                          value: isSelected,
                          title: Text(t.name, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            CoffeeMachineTypes.getDisplayName(t.machineType),
                            style: TextStyle(color: Colors.white.withOpacity(0.4)),
                          ),
                          activeColor: _gold,
                          checkColor: Colors.white,
                          onChanged: (v) {
                            setDialogState(() {
                              if (v == true) {
                                selected.add(t.id);
                              } else {
                                selected.remove(t.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.6))),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, selected),
                style: ElevatedButton.styleFrom(backgroundColor: _gold),
                child: const Text('Сохранить', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      final config = CoffeeMachineShopConfig(
        shopAddress: shopAddress,
        machineTemplateIds: result.toList(),
        hasComputerVerification: true,
      );
      await CoffeeMachineTemplateService.updateShopConfig(config);
      _loadData();
    }
  }
}

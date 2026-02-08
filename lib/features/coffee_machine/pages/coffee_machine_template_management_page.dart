import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/coffee_machine_template_model.dart';
import '../services/coffee_machine_template_service.dart';
import '../../shops/services/shop_service.dart';

/// Управление шаблонами кофемашин (только для developer)
/// Вкладка 1: Шаблоны машин (CRUD)
/// Вкладка 2: Привязка шаблонов к магазинам
class CoffeeMachineTemplateManagementPage extends StatefulWidget {
  const CoffeeMachineTemplateManagementPage({super.key});

  @override
  State<CoffeeMachineTemplateManagementPage> createState() => _CoffeeMachineTemplateManagementPageState();
}

class _CoffeeMachineTemplateManagementPageState extends State<CoffeeMachineTemplateManagementPage>
    with SingleTickerProviderStateMixin {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  late TabController _tabController;
  final _imagePicker = ImagePicker();

  bool _isLoading = true;
  List<CoffeeMachineTemplate> _templates = [];
  List<CoffeeMachineShopConfig> _shopConfigs = [];
  List<String> _shopAddresses = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        CoffeeMachineTemplateService.getTemplates(),
        CoffeeMachineTemplateService.getAllShopConfigs(),
        ShopService.getShops().then((shops) => shops.map((s) => s.address).toList()),
      ]);

      setState(() {
        _templates = results[0] as List<CoffeeMachineTemplate>;
        _shopConfigs = results[1] as List<CoffeeMachineShopConfig>;
        _shopAddresses = results[2] as List<String>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              _buildHeader(),
              TabBar(
                controller: _tabController,
                indicatorColor: _gold,
                labelColor: _gold,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(text: 'Шаблоны'),
                  Tab(text: 'Магазины'),
                ],
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: _gold))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildTemplatesList(),
                          _buildShopConfigsList(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _gold,
        onPressed: _addTemplate,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
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
            'Кофемашины',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  // ===== Вкладка 1: Шаблоны =====

  Widget _buildTemplatesList() {
    if (_templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.coffee, size: 48, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 12),
            Text('Нет шаблонов', style: TextStyle(color: Colors.white.withOpacity(0.4))),
            const SizedBox(height: 8),
            Text('Нажмите + чтобы добавить', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _templates.length,
      itemBuilder: (_, i) => _buildTemplateCard(_templates[i]),
    );
  }

  Widget _buildTemplateCard(CoffeeMachineTemplate template) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.coffee, color: _gold, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  CoffeeMachineTypes.getDisplayName(template.machineType),
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
                Text(
                  OcrPresets.getDisplayName(template.ocrPreset),
                  style: TextStyle(color: _gold.withOpacity(0.6), fontSize: 11),
                ),
                if (template.counterRegion != null)
                  Text(
                    'Область настроена',
                    style: TextStyle(color: Colors.green.withOpacity(0.7), fontSize: 11),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _editTemplate(template),
            icon: Icon(Icons.edit, color: Colors.white.withOpacity(0.5), size: 20),
          ),
          IconButton(
            onPressed: () => _deleteTemplate(template),
            icon: Icon(Icons.delete, color: Colors.red.withOpacity(0.5), size: 20),
          ),
        ],
      ),
    );
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
        title: const Text('Удалить шаблон?'),
        content: Text('Удалить "${template.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
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
    // Если machineType из сервера нет в списке — подставляем "other"
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
            title: Text(existing != null ? 'Редактировать шаблон' : 'Новый шаблон'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      hintText: 'WMF 1500S',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(labelText: 'Тип машины'),
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
                    decoration: const InputDecoration(labelText: 'Пресет OCR'),
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
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
                    icon: const Icon(Icons.camera_alt),
                    label: Text(imageBytes != null ? 'Фото загружено' : 'Эталонное фото'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
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
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===== Вкладка 2: Привязка к магазинам =====

  Widget _buildShopConfigsList() {
    if (_shopAddresses.isEmpty) {
      return Center(
        child: Text('Нет магазинов', style: TextStyle(color: Colors.white.withOpacity(0.4))),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _shopAddresses.length,
      itemBuilder: (_, i) {
        final address = _shopAddresses[i];
        final config = _shopConfigs.where((c) => c.shopAddress == address).firstOrNull;
        final assignedCount = config?.machineTemplateIds.length ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            tileColor: Colors.white.withOpacity(0.06),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: assignedCount > 0 ? _gold.withOpacity(0.15) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.store,
                color: assignedCount > 0 ? _gold : Colors.white30,
                size: 20,
              ),
            ),
            title: Text(
              address,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              assignedCount > 0 ? 'Машин: $assignedCount' : 'Не настроено',
              style: TextStyle(
                color: assignedCount > 0 ? _gold : Colors.white38,
                fontSize: 11,
              ),
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
            onTap: () => _editShopConfig(address, config),
          ),
        );
      },
    );
  }

  Future<void> _editShopConfig(String shopAddress, CoffeeMachineShopConfig? existing) async {
    final selected = Set<String>.from(existing?.machineTemplateIds ?? []);

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(shopAddress, style: const TextStyle(fontSize: 14)),
            content: SizedBox(
              width: double.maxFinite,
              child: _templates.isEmpty
                  ? const Text('Сначала создайте шаблоны')
                  : ListView(
                      shrinkWrap: true,
                      children: _templates.map((t) {
                        final isSelected = selected.contains(t.id);
                        return CheckboxListTile(
                          value: isSelected,
                          title: Text(t.name),
                          subtitle: Text(CoffeeMachineTypes.getDisplayName(t.machineType)),
                          activeColor: _gold,
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
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('Сохранить'),
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

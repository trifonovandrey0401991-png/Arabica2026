import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/coffee_machine_template_model.dart';
import '../services/coffee_machine_template_service.dart';
import '../../shops/services/shop_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/cache_manager.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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

  static const _cacheKey = 'coffee_templates';

  Future<void> _loadData() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<Map<String, dynamic>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _templates = cached['templates'] as List<CoffeeMachineTemplate>;
        _shopConfigs = cached['configs'] as List<CoffeeMachineShopConfig>;
        _shopAddresses = cached['addresses'] as List<String>;
        _isLoading = false;
      });
    }

    if (_templates.isEmpty && mounted) setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        CoffeeMachineTemplateService.getTemplates(),
        CoffeeMachineTemplateService.getAllShopConfigs(),
        ShopService.getShops().then((shops) => shops.map((s) => s.address).toList()),
      ]);

      if (!mounted) return;
      final templates = results[0] as List<CoffeeMachineTemplate>;
      final configs = results[1] as List<CoffeeMachineShopConfig>;
      final addresses = results[2] as List<String>;
      setState(() {
        _templates = templates;
        _shopConfigs = configs;
        _shopAddresses = addresses;
        _isLoading = false;
      });
      // Step 3: Save to cache
      CacheManager.set(_cacheKey, {
        'templates': templates,
        'configs': configs,
        'addresses': addresses,
      });
    } catch (e) {
      if (!mounted) return;
      if (_templates.isEmpty) setState(() => _isLoading = false);
    }
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
              _buildHeader(),
              TabBar(
                controller: _tabController,
                indicatorColor: AppColors.gold,
                labelColor: AppColors.gold,
                unselectedLabelColor: Colors.white54,
                tabs: [
                  Tab(text: 'Шаблоны'),
                  Tab(text: 'Магазины'),
                ],
              ),
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
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
        backgroundColor: AppColors.gold,
        onPressed: _addTemplate,
        child: Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back, color: Colors.white),
          ),
          Icon(Icons.coffee_outlined, color: AppColors.gold, size: 22),
          SizedBox(width: 8),
          Text(
            'Кофемашины',
            style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold),
          ),
          Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: Icon(Icons.refresh, color: Colors.white70),
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
            SizedBox(height: 12),
            Text('Нет шаблонов', style: TextStyle(color: Colors.white.withOpacity(0.4))),
            SizedBox(height: 8),
            Text('Нажмите + чтобы добавить', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12.sp)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: _templates.length,
      itemBuilder: (_, i) => _buildTemplateCard(_templates[i]),
    );
  }

  Widget _buildTemplateCard(CoffeeMachineTemplate template) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(Icons.coffee, color: AppColors.gold, size: 24),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.name,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15.sp),
                ),
                SizedBox(height: 2),
                Text(
                  CoffeeMachineTypes.getDisplayName(template.machineType),
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp),
                ),
                Text(
                  OcrPresets.getDisplayName(template.ocrPreset),
                  style: TextStyle(color: AppColors.gold.withOpacity(0.6), fontSize: 11.sp),
                ),
                if (template.counterRegion != null)
                  Text(
                    'Область настроена',
                    style: TextStyle(color: Colors.green.withOpacity(0.7), fontSize: 11.sp),
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
        title: Text('Удалить шаблон?'),
        content: Text('Удалить "${template.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Удалить', style: TextStyle(color: Colors.red)),
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

    final result = await showDialog<Map<String, dynamic>>(
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
                    decoration: InputDecoration(
                      labelText: 'Название',
                      hintText: 'WMF 1500S',
                    ),
                  ),
                  SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: InputDecoration(labelText: 'Тип машины'),
                    items: CoffeeMachineTypes.all.map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(CoffeeMachineTypes.getDisplayName(type)),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedType = v);
                    },
                  ),
                  SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedPreset,
                    decoration: InputDecoration(labelText: 'Пресет OCR'),
                    items: OcrPresets.all.map((preset) => DropdownMenuItem(
                      value: preset,
                      child: Text(OcrPresets.getDisplayName(preset)),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedPreset = v);
                    },
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 4.h),
                    child: Text(
                      OcrPresets.getDescription(selectedPreset),
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12.sp),
                    ),
                  ),
                  SizedBox(height: 12),
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
                    icon: Icon(Icons.camera_alt),
                    label: Text(imageBytes != null ? 'Фото загружено' : 'Эталонное фото'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Отмена')),
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
                child: Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
    return result;
  }

  // ===== Вкладка 2: Привязка к магазинам =====

  Widget _buildShopConfigsList() {
    if (_shopAddresses.isEmpty) {
      return Center(
        child: Text('Нет магазинов', style: TextStyle(color: Colors.white.withOpacity(0.4))),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: _shopAddresses.length,
      itemBuilder: (_, i) {
        final address = _shopAddresses[i];
        final config = _shopConfigs.where((c) => c.shopAddress == address).firstOrNull;
        final assignedCount = config?.machineTemplateIds.length ?? 0;

        return Container(
          margin: EdgeInsets.only(bottom: 10.h),
          child: ListTile(
            tileColor: Colors.white.withOpacity(0.06),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
              side: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: assignedCount > 0 ? AppColors.gold.withOpacity(0.15) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(
                Icons.store,
                color: assignedCount > 0 ? AppColors.gold : Colors.white30,
                size: 20,
              ),
            ),
            title: Text(
              address,
              style: TextStyle(color: Colors.white, fontSize: 13.sp),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              assignedCount > 0 ? 'Машин: $assignedCount' : 'Не настроено',
              style: TextStyle(
                color: assignedCount > 0 ? AppColors.gold : Colors.white38,
                fontSize: 11.sp,
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
            title: Text(shopAddress, style: TextStyle(fontSize: 14.sp)),
            content: SizedBox(
              width: double.maxFinite,
              child: _templates.isEmpty
                  ? Text('Сначала создайте шаблоны')
                  : ListView(
                      shrinkWrap: true,
                      children: _templates.map((t) {
                        final isSelected = selected.contains(t.id);
                        return CheckboxListTile(
                          value: isSelected,
                          title: Text(t.name),
                          subtitle: Text(CoffeeMachineTypes.getDisplayName(t.machineType)),
                          activeColor: AppColors.gold,
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
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Отмена')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, selected),
                child: Text('Сохранить'),
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

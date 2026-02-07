import 'package:flutter/material.dart';
import '../services/coffee_machine_template_service.dart';
import '../models/coffee_machine_template_model.dart';

/// Управление вопросами/настройками для счётчика кофемашин
/// (из Data Management → "Счётчик кофемашин")
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

  bool _isLoading = true;
  List<CoffeeMachineTemplate> _templates = [];
  List<CoffeeMachineShopConfig> _shopConfigs = [];

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
      ]);
      setState(() {
        _templates = results[0] as List<CoffeeMachineTemplate>;
        _shopConfigs = results[1] as List<CoffeeMachineShopConfig>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
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
                            Text(
                              'Шаблоны машин',
                              style: TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            if (_templates.isEmpty)
                              _buildEmptyCard('Нет шаблонов. Создайте их в Обучение ИИ → Кофемашины')
                            else
                              ..._templates.map(_buildTemplateInfo),
                            const SizedBox(height: 20),
                            // Привязки
                            Text(
                              'Настроенные магазины',
                              style: TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            if (configuredShops == 0)
                              _buildEmptyCard('Нет настроенных магазинов')
                            else
                              ..._shopConfigs
                                  .where((c) => c.machineTemplateIds.isNotEmpty)
                                  .map(_buildShopConfigInfo),
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
          _buildStatItem('${_shopConfigs.fold<int>(0, (s, c) => s + c.machineTemplateIds.length)}', 'Привязок'),
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

  Widget _buildTemplateInfo(CoffeeMachineTemplate template) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(Icons.coffee, color: _gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                  CoffeeMachineTypes.getDisplayName(template.machineType),
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                ),
              ],
            ),
          ),
          if (template.counterRegion != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('OCR', style: TextStyle(color: Colors.green, fontSize: 10)),
            ),
        ],
      ),
    );
  }

  Widget _buildShopConfigInfo(CoffeeMachineShopConfig config) {
    final templateNames = config.machineTemplateIds
        .map((id) {
          final t = _templates.where((t) => t.id == id).firstOrNull;
          return t?.name ?? id;
        })
        .join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            config.shopAddress,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            templateNames,
            style: TextStyle(color: _gold.withOpacity(0.7), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

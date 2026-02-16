import 'package:flutter/material.dart';
import '../models/execution_chain_model.dart';
import '../services/execution_chain_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница настройки цепочки выполнений (только для админа)
class ExecutionChainPage extends StatefulWidget {
  const ExecutionChainPage({super.key});

  @override
  State<ExecutionChainPage> createState() => _ExecutionChainPageState();
}

class _ExecutionChainPageState extends State<ExecutionChainPage> {
  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);
  static final Color _gold = Color(0xFFD4AF37);

  bool _isLoading = true;
  bool _isSaving = false;
  bool _enabled = false;

  /// Все доступные модули
  final List<_ModuleItem> _allModules = [
    _ModuleItem(id: 'attendance', name: 'Я на работе', icon: Icons.access_time_outlined),
    _ModuleItem(id: 'testing', name: 'Тестирование', icon: Icons.quiz_outlined),
    _ModuleItem(id: 'shift', name: 'Пересменка', icon: Icons.swap_horiz_rounded),
    _ModuleItem(id: 'recount', name: 'Пересчёт', icon: Icons.inventory_2_outlined),
    _ModuleItem(id: 'shift_handover', name: 'Сдать смену', icon: Icons.check_circle_outline_rounded),
    _ModuleItem(id: 'coffee_machine', name: 'Счётчик кофемашин', icon: Icons.coffee_outlined),
    _ModuleItem(id: 'envelope', name: 'Конверт', icon: Icons.mail_outlined),
    _ModuleItem(id: 'rko', name: 'РКО', icon: Icons.receipt_long_outlined),
  ];

  /// Активные шаги цепочки (в порядке выполнения)
  List<_ModuleItem> _activeSteps = [];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final config = await ExecutionChainService.getConfig();
      if (config != null && mounted) {
        setState(() {
          _enabled = config.enabled;
          // Восстанавливаем активные шаги в правильном порядке
          _activeSteps = [];
          for (final step in config.steps) {
            final module = _allModules.firstWhere(
              (m) => m.id == step.id,
              orElse: () => _ModuleItem(id: step.id, name: step.name, icon: Icons.help_outline),
            );
            _activeSteps.add(module);
          }
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      final steps = _activeSteps
          .asMap()
          .entries
          .map((e) => ExecutionChainStep(
                id: e.value.id,
                name: e.value.name,
                order: e.key + 1,
              ))
          .toList();

      final success = await ExecutionChainService.saveConfig(
        enabled: _enabled,
        steps: steps,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Сохранено' : 'Ошибка сохранения'),
            backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  bool _isModuleActive(String moduleId) {
    return _activeSteps.any((s) => s.id == moduleId);
  }

  void _toggleModule(_ModuleItem module) {
    setState(() {
      if (_isModuleActive(module.id)) {
        _activeSteps.removeWhere((s) => s.id == module.id);
      } else {
        _activeSteps.add(module);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: BoxDecoration(
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
              _buildAppBar(),
              if (_isLoading)
                Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: _gold),
                  ),
                )
              else
                Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 16.w, 8.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'Цепочка Выполнений',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: EdgeInsets.fromLTRB(20.w, 0.h, 20.w, 20.h),
      children: [
        // Переключатель активности
        _buildEnabledSwitch(),
        SizedBox(height: 20),

        // Секция: доступные модули
        _buildSectionTitle('Модули'),
        SizedBox(height: 8),
        ..._allModules.map(_buildModuleCheckbox),

        if (_activeSteps.isNotEmpty) ...[
          SizedBox(height: 24),
          _buildSectionTitle('Порядок выполнения'),
          SizedBox(height: 4),
          Text(
            'Перетащите для изменения порядка',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 13.sp,
            ),
          ),
          SizedBox(height: 8),
          _buildReorderableList(),
        ],

        SizedBox(height: 32),
        _buildSaveButton(),
      ],
    );
  }

  Widget _buildEnabledSwitch() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: _enabled ? _gold.withOpacity(0.4) : Colors.white.withOpacity(0.15),
        ),
        color: _enabled ? _gold.withOpacity(0.08) : Colors.transparent,
      ),
      child: Row(
        children: [
          Icon(
            _enabled ? Icons.link_rounded : Icons.link_off_rounded,
            color: _enabled ? _gold : Colors.white.withOpacity(0.5),
            size: 24,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              _enabled ? 'Цепочка активна' : 'Цепочка выключена',
              style: TextStyle(
                color: _enabled ? _gold : Colors.white.withOpacity(0.7),
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch(
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
            activeColor: _gold,
            activeTrackColor: _gold.withOpacity(0.3),
            inactiveThumbColor: Colors.white.withOpacity(0.5),
            inactiveTrackColor: Colors.white.withOpacity(0.1),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withOpacity(0.6),
        fontSize: 14.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildModuleCheckbox(_ModuleItem module) {
    final isActive = _isModuleActive(module.id);
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12.r),
        child: InkWell(
          onTap: () => _toggleModule(module),
          borderRadius: BorderRadius.circular(12.r),
          splashColor: Colors.white.withOpacity(0.1),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                color: isActive ? _gold.withOpacity(0.3) : Colors.white.withOpacity(0.1),
              ),
              color: isActive ? _gold.withOpacity(0.05) : Colors.transparent,
            ),
            child: Row(
              children: [
                Icon(
                  module.icon,
                  color: isActive ? _gold : Colors.white.withOpacity(0.5),
                  size: 22,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    module.name,
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.white.withOpacity(0.7),
                      fontSize: 15.sp,
                    ),
                  ),
                ),
                Checkbox(
                  value: isActive,
                  onChanged: (_) => _toggleModule(module),
                  activeColor: _gold,
                  checkColor: _night,
                  side: BorderSide(color: Colors.white.withOpacity(0.3)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReorderableList() {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: _activeSteps.length,
      proxyDecorator: (child, index, animation) {
        return Material(
          color: Colors.transparent,
          elevation: 4,
          shadowColor: _gold.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12.r),
          child: child,
        );
      },
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = _activeSteps.removeAt(oldIndex);
          _activeSteps.insert(newIndex, item);
        });
      },
      itemBuilder: (context, index) {
        final module = _activeSteps[index];
        return Container(
          key: ValueKey(module.id),
          margin: EdgeInsets.only(bottom: 6.h),
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: _gold.withOpacity(0.25)),
            color: _gold.withOpacity(0.06),
          ),
          child: Row(
            children: [
              // Номер шага
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _gold.withOpacity(0.2),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Icon(
                module.icon,
                color: _gold.withOpacity(0.8),
                size: 20,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  module.name,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.sp,
                  ),
                ),
              ),
              ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: Colors.white.withOpacity(0.3),
                  size: 22,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveConfig,
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: _night,
          disabledBackgroundColor: _gold.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
        ),
        child: _isSaving
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _night,
                ),
              )
            : Text(
                'Сохранить',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

/// Внутренняя модель модуля для UI
class _ModuleItem {
  final String id;
  final String name;
  final IconData icon;

  _ModuleItem({required this.id, required this.name, required this.icon});
}

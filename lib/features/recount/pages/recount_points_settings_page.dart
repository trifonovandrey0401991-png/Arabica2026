import 'package:flutter/material.dart';
import '../models/recount_points_model.dart';
import '../models/recount_settings_model.dart';
import '../services/recount_points_service.dart';

/// Страница настройки баллов сотрудников для пересчёта
class RecountPointsSettingsPage extends StatefulWidget {
  const RecountPointsSettingsPage({super.key});

  @override
  State<RecountPointsSettingsPage> createState() => _RecountPointsSettingsPageState();
}

class _RecountPointsSettingsPageState extends State<RecountPointsSettingsPage> {
  List<RecountPoints> _employeePoints = [];
  RecountSettings _settings = RecountSettings();
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  static const _primaryColor = Color(0xFF004D40);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RecountPoints> get _filteredEmployees {
    if (_searchQuery.isEmpty) return _employeePoints;
    final query = _searchQuery.toLowerCase();
    return _employeePoints.where((e) =>
      e.employeeName.toLowerCase().contains(query) ||
      e.phone.contains(query)
    ).toList();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        RecountPointsService.getAllPoints(),
        RecountPointsService.getSettings(),
      ]);

      setState(() {
        _employeePoints = results[0] as List<RecountPoints>;
        _settings = results[1] as RecountSettings;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки данных: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _initializeAllPoints() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Инициализировать баллы?'),
        content: Text(
          'Всем сотрудникам без баллов будет установлено значение ${_settings.defaultPoints.toInt()} баллов.\n\n'
          'Существующие баллы не будут изменены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Инициализировать'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final count = await RecountPointsService.initializeAllPoints();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Инициализировано: $count сотрудников'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    }
  }

  Future<void> _openSettingsDialog() async {
    final result = await showDialog<RecountSettings>(
      context: context,
      builder: (context) => _GeneralSettingsDialog(settings: _settings),
    );

    if (result != null) {
      final success = await RecountPointsService.updateSettings(result);
      if (success && mounted) {
        setState(() => _settings = result);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Настройки сохранены'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _editEmployeePoints(RecountPoints employee) async {
    final result = await showDialog<double>(
      context: context,
      builder: (context) => _EditPointsDialog(
        employee: employee,
        settings: _settings,
      ),
    );

    if (result != null) {
      final success = await RecountPointsService.updatePoints(
        phone: employee.phone,
        points: result,
        adminName: 'Администратор',
        employeeName: employee.employeeName,
      );

      if (success && mounted) {
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Баллы обновлены'),
            backgroundColor: Colors.green,
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

    return Column(
      children: [
        // Общие настройки
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.settings, color: _primaryColor),
              title: const Text('Общие настройки'),
              subtitle: Text(
                '${_settings.questionsCount} вопросов • ${_settings.basePhotos} фото • Баллы: ${_settings.defaultPoints.toInt()}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openSettingsDialog,
            ),
          ),
        ),

        // Поиск
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Поиск по имени или телефону...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        const SizedBox(height: 8),

        // Заголовок с количеством и кнопкой инициализации
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                'Сотрудников: ${_filteredEmployees.length}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _initializeAllPoints,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Добавить новых'),
                style: TextButton.styleFrom(foregroundColor: _primaryColor),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Список сотрудников
        Expanded(
          child: _filteredEmployees.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _searchQuery.isNotEmpty ? Icons.search_off : Icons.people_outline,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Сотрудники не найдены'
                            : 'Нет сотрудников с баллами',
                        style: const TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      if (_searchQuery.isEmpty) ...[
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _initializeAllPoints,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                          ),
                          child: const Text('Инициализировать баллы'),
                        ),
                      ],
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredEmployees.length,
                    itemBuilder: (context, index) {
                      final employee = _filteredEmployees[index];
                      final requiredPhotos = _settings.calculateRequiredPhotos(employee.points);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getPointsColor(employee.points),
                            child: Text(
                              employee.points.toInt().toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          title: Text(
                            employee.employeeName.isNotEmpty
                                ? employee.employeeName
                                : 'Сотрудник ${employee.phone}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Row(
                            children: [
                              Icon(
                                Icons.camera_alt,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$requiredPhotos фото',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              const SizedBox(width: 16),
                              Icon(
                                Icons.phone,
                                size: 14,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                employee.phone,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.edit, color: Colors.grey),
                          onTap: () => _editEmployeePoints(employee),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Color _getPointsColor(double points) {
    if (points >= 80) return Colors.green;
    if (points >= 60) return Colors.orange;
    if (points >= 40) return Colors.deepOrange;
    return Colors.red;
  }
}

/// Диалог общих настроек
class _GeneralSettingsDialog extends StatefulWidget {
  final RecountSettings settings;

  const _GeneralSettingsDialog({required this.settings});

  @override
  State<_GeneralSettingsDialog> createState() => _GeneralSettingsDialogState();
}

class _GeneralSettingsDialogState extends State<_GeneralSettingsDialog> {
  late TextEditingController _defaultPointsController;
  late TextEditingController _basePhotosController;
  late TextEditingController _stepPointsController;
  late TextEditingController _maxPhotosController;
  late TextEditingController _correctBonusController;
  late TextEditingController _incorrectPenaltyController;
  late TextEditingController _questionsCountController;

  @override
  void initState() {
    super.initState();
    _defaultPointsController = TextEditingController(text: widget.settings.defaultPoints.toInt().toString());
    _basePhotosController = TextEditingController(text: widget.settings.basePhotos.toString());
    _stepPointsController = TextEditingController(text: widget.settings.stepPoints.toInt().toString());
    _maxPhotosController = TextEditingController(text: widget.settings.maxPhotos.toString());
    _correctBonusController = TextEditingController(text: widget.settings.correctPhotoBonus.toString());
    _incorrectPenaltyController = TextEditingController(text: widget.settings.incorrectPhotoPenalty.toString());
    _questionsCountController = TextEditingController(text: widget.settings.questionsCount.toString());
  }

  @override
  void dispose() {
    _defaultPointsController.dispose();
    _basePhotosController.dispose();
    _stepPointsController.dispose();
    _maxPhotosController.dispose();
    _correctBonusController.dispose();
    _incorrectPenaltyController.dispose();
    _questionsCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Общие настройки пересчёта'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildField('Начальные баллы', _defaultPointsController, 'Значение для новых сотрудников'),
            const SizedBox(height: 16),
            _buildField('Кол-во вопросов', _questionsCountController, 'Вопросов в пересчёте (5-100)'),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Настройки фотографий',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _buildField('Базовое кол-во фото', _basePhotosController, 'Минимум фотографий'),
            const SizedBox(height: 16),
            _buildField('Шаг (баллов)', _stepPointsController, 'Снижение для +1 фото'),
            const SizedBox(height: 16),
            _buildField('Максимум фото', _maxPhotosController, 'Максимальное кол-во'),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Бонусы/Штрафы за верификацию фото',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _buildField('За правильное фото', _correctBonusController, '+баллы', prefix: '+'),
            const SizedBox(height: 16),
            _buildField('За неправильное', _incorrectPenaltyController, '-баллы', prefix: '-'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            final settings = RecountSettings(
              defaultPoints: double.tryParse(_defaultPointsController.text) ?? 85,
              basePhotos: int.tryParse(_basePhotosController.text) ?? 3,
              stepPoints: double.tryParse(_stepPointsController.text) ?? 5,
              maxPhotos: int.tryParse(_maxPhotosController.text) ?? 20,
              correctPhotoBonus: double.tryParse(_correctBonusController.text) ?? 0.2,
              incorrectPhotoPenalty: double.tryParse(_incorrectPenaltyController.text) ?? 2.5,
              questionsCount: int.tryParse(_questionsCountController.text) ?? 30,
            );
            Navigator.pop(context, settings);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF004D40),
          ),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget _buildField(String label, TextEditingController controller, String hint, {String? prefix}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
  }
}

/// Диалог редактирования баллов сотрудника
class _EditPointsDialog extends StatefulWidget {
  final RecountPoints employee;
  final RecountSettings settings;

  const _EditPointsDialog({
    required this.employee,
    required this.settings,
  });

  @override
  State<_EditPointsDialog> createState() => _EditPointsDialogState();
}

class _EditPointsDialogState extends State<_EditPointsDialog> {
  late TextEditingController _pointsController;
  double _previewPoints = 0;

  @override
  void initState() {
    super.initState();
    _previewPoints = widget.employee.points;
    _pointsController = TextEditingController(text: widget.employee.points.toInt().toString());
    _pointsController.addListener(_onPointsChanged);
  }

  @override
  void dispose() {
    _pointsController.removeListener(_onPointsChanged);
    _pointsController.dispose();
    super.dispose();
  }

  void _onPointsChanged() {
    final value = double.tryParse(_pointsController.text);
    if (value != null) {
      setState(() => _previewPoints = value.clamp(0, 100));
    }
  }

  @override
  Widget build(BuildContext context) {
    final requiredPhotos = widget.settings.calculateRequiredPhotos(_previewPoints);

    return AlertDialog(
      title: Text(
        widget.employee.employeeName.isNotEmpty
            ? widget.employee.employeeName
            : 'Сотрудник',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Текущие баллы
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Текущие', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      widget.employee.points.toInt().toString(),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Icon(Icons.arrow_forward, color: Colors.grey),
                Column(
                  children: [
                    const Text('Новые', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      _previewPoints.toInt().toString(),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _getPointsColor(_previewPoints),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Поле ввода
          TextField(
            controller: _pointsController,
            decoration: const InputDecoration(
              labelText: 'Новые баллы',
              border: OutlineInputBorder(),
              hintText: '0-100',
            ),
            keyboardType: TextInputType.number,
            autofocus: true,
          ),
          const SizedBox(height: 16),

          // Предпросмотр фото
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF004D40).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.camera_alt, color: Color(0xFF004D40)),
                const SizedBox(width: 8),
                Text(
                  'Требуется фото: $requiredPhotos',
                  style: const TextStyle(
                    color: Color(0xFF004D40),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            final points = double.tryParse(_pointsController.text);
            if (points != null && points >= 0 && points <= 100) {
              Navigator.pop(context, points);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Введите число от 0 до 100'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF004D40),
          ),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Color _getPointsColor(double points) {
    if (points >= 80) return Colors.green;
    if (points >= 60) return Colors.orange;
    if (points >= 40) return Colors.deepOrange;
    return Colors.red;
  }
}

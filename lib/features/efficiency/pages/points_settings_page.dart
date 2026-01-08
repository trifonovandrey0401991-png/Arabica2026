import 'package:flutter/material.dart';
import '../models/points_settings_model.dart';
import '../services/points_settings_service.dart';

/// Page for configuring efficiency points settings
class PointsSettingsPage extends StatefulWidget {
  const PointsSettingsPage({super.key});

  @override
  State<PointsSettingsPage> createState() => _PointsSettingsPageState();
}

class _PointsSettingsPageState extends State<PointsSettingsPage> {
  bool _isLoading = false;

  // Categories
  final List<_PointsCategory> _categories = [
    _PointsCategory(
      id: 'testing',
      title: 'Тестирование',
      icon: Icons.quiz,
      description: 'Баллы за прохождение тестов',
    ),
    _PointsCategory(
      id: 'attendance',
      title: 'Я на работе',
      icon: Icons.access_time,
      description: 'Баллы за пунктуальность',
    ),
    _PointsCategory(
      id: 'shift',
      title: 'Пересменка',
      icon: Icons.swap_horiz,
      description: 'Баллы за оценку пересменки',
    ),
    _PointsCategory(
      id: 'recount',
      title: 'Пересчет',
      icon: Icons.inventory,
      description: 'Баллы за оценку пересчета',
    ),
    _PointsCategory(
      id: 'rko',
      title: 'РКО',
      icon: Icons.receipt_long,
      description: 'Баллы за наличие РКО',
    ),
    _PointsCategory(
      id: 'shift_handover',
      title: 'Сдать смену',
      icon: Icons.assignment_turned_in,
      description: 'Баллы за оценку сдачи смены',
    ),
    _PointsCategory(
      id: 'reviews',
      title: 'Отзывы',
      icon: Icons.star_rate,
      description: 'Баллы за отзывы на магазин',
    ),
    _PointsCategory(
      id: 'product_search',
      title: 'Поиск товара',
      icon: Icons.search,
      description: 'Баллы за ответ на запрос товара',
    ),
    _PointsCategory(
      id: 'orders',
      title: 'Заказы клиентов',
      icon: Icons.shopping_cart,
      description: 'Баллы за обработку заказов',
    ),
  ];

  void _openCategorySettings(String categoryId) {
    if (categoryId == 'testing') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const TestPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'attendance') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const AttendancePointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'shift') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ShiftPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'recount') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const RecountPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'rko') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const RkoPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'shift_handover') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ShiftHandoverPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'reviews') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ReviewsPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'product_search') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ProductSearchPointsSettingsPage(),
        ),
      );
    } else if (categoryId == 'orders') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const OrdersPointsSettingsPage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Установка баллов'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(
                      category.icon,
                      color: const Color(0xFF004D40),
                      size: 32,
                    ),
                    title: Text(
                      category.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(category.description),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openCategorySettings(category.id),
                  ),
                );
              },
            ),
    );
  }
}

class _PointsCategory {
  final String id;
  final String title;
  final IconData icon;
  final String description;

  _PointsCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.description,
  });
}

/// Page for configuring test points settings
class TestPointsSettingsPage extends StatefulWidget {
  const TestPointsSettingsPage({super.key});

  @override
  State<TestPointsSettingsPage> createState() => _TestPointsSettingsPageState();
}

class _TestPointsSettingsPageState extends State<TestPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  TestPointsSettings? _settings;

  // Editable values
  double _minPoints = -2;
  int _zeroThreshold = 15;
  double _maxPoints = 1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings = await PointsSettingsService.getTestPointsSettings();
      setState(() {
        _settings = settings;
        _minPoints = settings.minPoints;
        _zeroThreshold = settings.zeroThreshold;
        _maxPoints = settings.maxPoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки настроек: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final result = await PointsSettingsService.saveTestPointsSettings(
        minPoints: _minPoints,
        zeroThreshold: _zeroThreshold,
        maxPoints: _maxPoints,
      );

      if (result != null) {
        setState(() {
          _settings = result;
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки сохранены'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Не удалось сохранить настройки');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Calculate points using current settings (local calculation)
  double _calculatePoints(int score) {
    if (score <= 0) return _minPoints;
    if (score >= 20) return _maxPoints;

    if (score <= _zeroThreshold) {
      return _minPoints + (0 - _minPoints) * (score / _zeroThreshold);
    } else {
      final range = 20 - _zeroThreshold;
      return 0 + (_maxPoints - 0) * ((score - _zeroThreshold) / range);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Баллы за тестирование'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Всего вопросов: 20\nПроходной балл: 16 правильных ответов',
                              style: TextStyle(color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Min points slider
                  _buildSliderSection(
                    title: 'Минимальные баллы',
                    subtitle: 'Штраф за 0-1 правильных ответов',
                    value: _minPoints,
                    min: -5,
                    max: 0,
                    divisions: 10,
                    onChanged: (value) {
                      setState(() => _minPoints = value);
                    },
                    valueLabel: _minPoints.toStringAsFixed(1),
                  ),
                  const SizedBox(height: 24),

                  // Zero threshold slider
                  _buildSliderSection(
                    title: 'Порог нуля',
                    subtitle: 'Количество правильных ответов для 0 баллов',
                    value: _zeroThreshold.toDouble(),
                    min: 5,
                    max: 19,
                    divisions: 14,
                    onChanged: (value) {
                      setState(() => _zeroThreshold = value.round());
                    },
                    valueLabel: _zeroThreshold.toString(),
                    isInteger: true,
                  ),
                  const SizedBox(height: 24),

                  // Max points slider
                  _buildSliderSection(
                    title: 'Максимальные баллы',
                    subtitle: 'Награда за 20/20 правильных ответов',
                    value: _maxPoints,
                    min: 0,
                    max: 5,
                    divisions: 10,
                    onChanged: (value) {
                      setState(() => _maxPoints = value);
                    },
                    valueLabel: '+${_maxPoints.toStringAsFixed(1)}',
                  ),
                  const SizedBox(height: 32),

                  // Preview section
                  const Text(
                    'Предпросмотр расчета баллов:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewTable(),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSliderSection({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
    bool isInteger = false,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF004D40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    valueLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: const Color(0xFF004D40),
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isInteger ? min.toInt().toString() : min.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  isInteger ? max.toInt().toString() : max.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTable() {
    final previewScores = [0, 5, 10, _zeroThreshold, 17, 18, 19, 20];

    return Card(
      elevation: 2,
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Правильных ответов',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Баллы эффективности',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          ...previewScores.map((score) {
            final points = _calculatePoints(score);
            final color = points < 0
                ? Colors.red
                : points > 0
                    ? Colors.green
                    : Colors.grey;
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '$score / 20',
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    points >= 0
                        ? '+${points.toStringAsFixed(2)}'
                        : points.toStringAsFixed(2),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// Page for configuring attendance points settings (Я на работе)
class AttendancePointsSettingsPage extends StatefulWidget {
  const AttendancePointsSettingsPage({super.key});

  @override
  State<AttendancePointsSettingsPage> createState() =>
      _AttendancePointsSettingsPageState();
}

class _AttendancePointsSettingsPageState
    extends State<AttendancePointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  AttendancePointsSettings? _settings;

  // Editable values
  double _onTimePoints = 0.5;
  double _latePoints = -1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings =
          await PointsSettingsService.getAttendancePointsSettings();
      setState(() {
        _settings = settings;
        _onTimePoints = settings.onTimePoints;
        _latePoints = settings.latePoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки настроек: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final result = await PointsSettingsService.saveAttendancePointsSettings(
        onTimePoints: _onTimePoints,
        latePoints: _latePoints,
      );

      if (result != null) {
        setState(() {
          _settings = result;
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки сохранены'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Не удалось сохранить настройки');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Баллы за посещаемость'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Баллы начисляются при отметке прихода на работу',
                              style: TextStyle(color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // On time points slider
                  _buildSliderSection(
                    title: 'Пришел вовремя',
                    subtitle: 'Награда за приход без опоздания',
                    value: _onTimePoints,
                    min: 0,
                    max: 2,
                    divisions: 20,
                    onChanged: (value) {
                      setState(() => _onTimePoints = value);
                    },
                    valueLabel: '+${_onTimePoints.toStringAsFixed(1)}',
                    valueColor: Colors.green,
                  ),
                  const SizedBox(height: 24),

                  // Late points slider
                  _buildSliderSection(
                    title: 'Опоздал',
                    subtitle: 'Штраф за опоздание',
                    value: _latePoints,
                    min: -3,
                    max: 0,
                    divisions: 30,
                    onChanged: (value) {
                      setState(() => _latePoints = value);
                    },
                    valueLabel: _latePoints.toStringAsFixed(1),
                    valueColor: Colors.red,
                  ),
                  const SizedBox(height: 32),

                  // Preview section
                  const Text(
                    'Предпросмотр:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewTable(),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSliderSection({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
    Color? valueColor,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: valueColor ?? const Color(0xFF004D40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    valueLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: valueColor ?? const Color(0xFF004D40),
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  min.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  max.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTable() {
    return Card(
      elevation: 2,
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Статус',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Баллы',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    const Text('Вовремя'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '+${_onTimePoints.toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    const Text('Опоздал'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _latePoints.toStringAsFixed(2),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Page for configuring shift points settings (Пересменка)
class ShiftPointsSettingsPage extends StatefulWidget {
  const ShiftPointsSettingsPage({super.key});

  @override
  State<ShiftPointsSettingsPage> createState() =>
      _ShiftPointsSettingsPageState();
}

class _ShiftPointsSettingsPageState extends State<ShiftPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  ShiftPointsSettings? _settings;

  // Editable values
  double _minPoints = -3;
  int _zeroThreshold = 7;
  double _maxPoints = 2;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings = await PointsSettingsService.getShiftPointsSettings();
      setState(() {
        _settings = settings;
        _minPoints = settings.minPoints;
        _zeroThreshold = settings.zeroThreshold;
        _maxPoints = settings.maxPoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки настроек: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final result = await PointsSettingsService.saveShiftPointsSettings(
        minPoints: _minPoints,
        zeroThreshold: _zeroThreshold,
        maxPoints: _maxPoints,
      );

      if (result != null) {
        setState(() {
          _settings = result;
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки сохранены'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Не удалось сохранить настройки');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Calculate points using current settings (local calculation)
  double _calculatePoints(int rating) {
    if (rating <= 1) return _minPoints;
    if (rating >= 10) return _maxPoints;

    if (rating <= _zeroThreshold) {
      // Interpolate from minPoints to 0 (rating: 1 -> zeroThreshold)
      final range = _zeroThreshold - 1;
      return _minPoints + (0 - _minPoints) * ((rating - 1) / range);
    } else {
      // Interpolate from 0 to maxPoints (rating: zeroThreshold -> 10)
      final range = 10 - _zeroThreshold;
      return 0 + (_maxPoints - 0) * ((rating - _zeroThreshold) / range);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Баллы за пересменку'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Баллы начисляются при оценке отчета пересменки (1-10)',
                              style: TextStyle(color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Min points slider (rating 1)
                  _buildSliderSection(
                    title: 'Минимальная оценка (1)',
                    subtitle: 'Штраф за плохую пересменку',
                    value: _minPoints,
                    min: -5,
                    max: 0,
                    divisions: 50,
                    onChanged: (value) {
                      setState(() => _minPoints = value);
                    },
                    valueLabel: _minPoints.toStringAsFixed(1),
                    valueColor: Colors.red,
                  ),
                  const SizedBox(height: 24),

                  // Zero threshold slider
                  _buildSliderSection(
                    title: 'Нулевая граница',
                    subtitle: 'Оценка, дающая 0 баллов',
                    value: _zeroThreshold.toDouble(),
                    min: 2,
                    max: 9,
                    divisions: 7,
                    onChanged: (value) {
                      setState(() => _zeroThreshold = value.round());
                    },
                    valueLabel: _zeroThreshold.toString(),
                    isInteger: true,
                  ),
                  const SizedBox(height: 24),

                  // Max points slider (rating 10)
                  _buildSliderSection(
                    title: 'Максимальная оценка (10)',
                    subtitle: 'Награда за отличную пересменку',
                    value: _maxPoints,
                    min: 0,
                    max: 5,
                    divisions: 50,
                    onChanged: (value) {
                      setState(() => _maxPoints = value);
                    },
                    valueLabel: '+${_maxPoints.toStringAsFixed(1)}',
                    valueColor: Colors.green,
                  ),
                  const SizedBox(height: 32),

                  // Preview section
                  const Text(
                    'Предпросмотр расчета баллов:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewTable(),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSliderSection({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
    Color? valueColor,
    bool isInteger = false,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: valueColor ?? const Color(0xFF004D40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    valueLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: valueColor ?? const Color(0xFF004D40),
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isInteger ? min.toInt().toString() : min.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  isInteger ? max.toInt().toString() : max.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTable() {
    final previewRatings = [1, 4, _zeroThreshold, 8, 10];

    return Card(
      elevation: 2,
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Оценка',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Баллы эффективности',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          ...previewRatings.map((rating) {
            final points = _calculatePoints(rating);
            final color = points < 0
                ? Colors.red
                : points > 0
                    ? Colors.green
                    : Colors.grey;
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '$rating / 10',
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    points >= 0
                        ? '+${points.toStringAsFixed(2)}'
                        : points.toStringAsFixed(2),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// Page for configuring recount points settings (Пересчет)
class RecountPointsSettingsPage extends StatefulWidget {
  const RecountPointsSettingsPage({super.key});

  @override
  State<RecountPointsSettingsPage> createState() =>
      _RecountPointsSettingsPageState();
}

class _RecountPointsSettingsPageState extends State<RecountPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  RecountPointsSettings? _settings;

  // Editable values
  double _minPoints = -3;
  int _zeroThreshold = 7;
  double _maxPoints = 1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings = await PointsSettingsService.getRecountPointsSettings();
      setState(() {
        _settings = settings;
        _minPoints = settings.minPoints;
        _zeroThreshold = settings.zeroThreshold;
        _maxPoints = settings.maxPoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки настроек: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final result = await PointsSettingsService.saveRecountPointsSettings(
        minPoints: _minPoints,
        zeroThreshold: _zeroThreshold,
        maxPoints: _maxPoints,
      );

      if (result != null) {
        setState(() {
          _settings = result;
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки сохранены'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Не удалось сохранить настройки');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Calculate points using current settings (local calculation)
  double _calculatePoints(int rating) {
    if (rating <= 1) return _minPoints;
    if (rating >= 10) return _maxPoints;

    if (rating <= _zeroThreshold) {
      // Interpolate from minPoints to 0 (rating: 1 -> zeroThreshold)
      final range = _zeroThreshold - 1;
      return _minPoints + (0 - _minPoints) * ((rating - 1) / range);
    } else {
      // Interpolate from 0 to maxPoints (rating: zeroThreshold -> 10)
      final range = 10 - _zeroThreshold;
      return 0 + (_maxPoints - 0) * ((rating - _zeroThreshold) / range);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Баллы за пересчет'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Баллы начисляются при оценке отчета пересчета (1-10)',
                              style: TextStyle(color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Min points slider (rating 1) - recount
                  _buildSliderSection(
                    title: 'Минимальная оценка (1)',
                    subtitle: 'Штраф за плохой пересчет',
                    value: _minPoints,
                    min: -5,
                    max: 0,
                    divisions: 50,
                    onChanged: (value) {
                      setState(() => _minPoints = value);
                    },
                    valueLabel: _minPoints.toStringAsFixed(1),
                    valueColor: Colors.red,
                  ),
                  const SizedBox(height: 24),

                  // Zero threshold slider
                  _buildSliderSection(
                    title: 'Нулевая граница',
                    subtitle: 'Оценка, дающая 0 баллов',
                    value: _zeroThreshold.toDouble(),
                    min: 2,
                    max: 9,
                    divisions: 7,
                    onChanged: (value) {
                      setState(() => _zeroThreshold = value.round());
                    },
                    valueLabel: _zeroThreshold.toString(),
                    isInteger: true,
                  ),
                  const SizedBox(height: 24),

                  // Max points slider (rating 10)
                  _buildSliderSection(
                    title: 'Максимальная оценка (10)',
                    subtitle: 'Награда за отличный пересчет',
                    value: _maxPoints,
                    min: 0,
                    max: 5,
                    divisions: 50,
                    onChanged: (value) {
                      setState(() => _maxPoints = value);
                    },
                    valueLabel: '+${_maxPoints.toStringAsFixed(1)}',
                    valueColor: Colors.green,
                  ),
                  const SizedBox(height: 32),

                  // Preview section
                  const Text(
                    'Предпросмотр расчета баллов:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewTable(),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSliderSection({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
    Color? valueColor,
    bool isInteger = false,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: valueColor ?? const Color(0xFF004D40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    valueLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: valueColor ?? const Color(0xFF004D40),
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isInteger ? min.toInt().toString() : min.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  isInteger ? max.toInt().toString() : max.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Preview table for recount ratings
  Widget _buildPreviewTable() {
    final previewRatings = [1, 4, _zeroThreshold, 8, 10];

    return Card(
      elevation: 2,
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Оценка',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Баллы эффективности',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          ...previewRatings.map((rating) {
            final points = _calculatePoints(rating);
            final color = points < 0
                ? Colors.red
                : points > 0
                    ? Colors.green
                    : Colors.grey;
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '$rating / 10',
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    points >= 0
                        ? '+${points.toStringAsFixed(2)}'
                        : points.toStringAsFixed(2),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// Page for configuring RKO points settings (РКО)
class RkoPointsSettingsPage extends StatefulWidget {
  const RkoPointsSettingsPage({super.key});

  @override
  State<RkoPointsSettingsPage> createState() => _RkoPointsSettingsPageState();
}

class _RkoPointsSettingsPageState extends State<RkoPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  RkoPointsSettings? _settings;

  // Editable values for RKO
  double _hasRkoPoints = 1;
  double _noRkoPoints = -3;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings = await PointsSettingsService.getRkoPointsSettings();
      setState(() {
        _settings = settings;
        _hasRkoPoints = settings.hasRkoPoints;
        _noRkoPoints = settings.noRkoPoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки настроек: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final result = await PointsSettingsService.saveRkoPointsSettings(
        hasRkoPoints: _hasRkoPoints,
        noRkoPoints: _noRkoPoints,
      );

      if (result != null) {
        setState(() {
          _settings = result;
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки сохранены'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Не удалось сохранить настройки');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Баллы за РКО'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card for RKO
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Баллы начисляются за наличие или отсутствие РКО (расходно-кассовый ордер)',
                              style: TextStyle(color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Has RKO points slider
                  _buildRkoSliderSection(
                    title: 'Есть РКО',
                    subtitle: 'Награда за наличие РКО',
                    value: _hasRkoPoints,
                    min: 0,
                    max: 5,
                    divisions: 50,
                    onChanged: (value) {
                      setState(() => _hasRkoPoints = value);
                    },
                    valueLabel: '+${_hasRkoPoints.toStringAsFixed(1)}',
                    valueColor: Colors.green,
                  ),
                  const SizedBox(height: 24),

                  // No RKO points slider
                  _buildRkoSliderSection(
                    title: 'Нет РКО',
                    subtitle: 'Штраф за отсутствие РКО',
                    value: _noRkoPoints,
                    min: -5,
                    max: 0,
                    divisions: 50,
                    onChanged: (value) {
                      setState(() => _noRkoPoints = value);
                    },
                    valueLabel: _noRkoPoints.toStringAsFixed(1),
                    valueColor: Colors.red,
                  ),
                  const SizedBox(height: 32),

                  // Preview section for RKO
                  const Text(
                    'Предпросмотр:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRkoPreviewTable(),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRkoSliderSection({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
    Color? valueColor,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: valueColor ?? const Color(0xFF004D40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    valueLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: valueColor ?? const Color(0xFF004D40),
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  min.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  max.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRkoPreviewTable() {
    return Card(
      elevation: 2,
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Статус РКО',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Баллы',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    const Text('Есть РКО'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '+${_hasRkoPoints.toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cancel, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    const Text('Нет РКО'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _noRkoPoints.toStringAsFixed(2),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Page for configuring shift handover points settings (Сдать смену)
class ShiftHandoverPointsSettingsPage extends StatefulWidget {
  const ShiftHandoverPointsSettingsPage({super.key});

  @override
  State<ShiftHandoverPointsSettingsPage> createState() =>
      _ShiftHandoverPointsSettingsPageState();
}

class _ShiftHandoverPointsSettingsPageState
    extends State<ShiftHandoverPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  ShiftHandoverPointsSettings? _settings;

  // Editable values for shift handover
  double _minPoints = -3;
  int _zeroThreshold = 7;
  double _maxPoints = 1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings =
          await PointsSettingsService.getShiftHandoverPointsSettings();
      setState(() {
        _settings = settings;
        _minPoints = settings.minPoints;
        _zeroThreshold = settings.zeroThreshold;
        _maxPoints = settings.maxPoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки настроек: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final result =
          await PointsSettingsService.saveShiftHandoverPointsSettings(
        minPoints: _minPoints,
        zeroThreshold: _zeroThreshold,
        maxPoints: _maxPoints,
      );

      if (result != null) {
        setState(() {
          _settings = result;
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки сохранены'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Не удалось сохранить настройки');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Calculate points using current settings (local calculation)
  double _calculatePoints(int rating) {
    if (rating <= 1) return _minPoints;
    if (rating >= 10) return _maxPoints;

    if (rating <= _zeroThreshold) {
      // Interpolate from minPoints to 0 (rating: 1 -> zeroThreshold)
      final range = _zeroThreshold - 1;
      return _minPoints + (0 - _minPoints) * ((rating - 1) / range);
    } else {
      // Interpolate from 0 to maxPoints (rating: zeroThreshold -> 10)
      final range = 10 - _zeroThreshold;
      return 0 + (_maxPoints - 0) * ((rating - _zeroThreshold) / range);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Баллы за сдачу смены'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card for shift handover
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Баллы начисляются при оценке отчета сдачи смены (1-10)',
                              style: TextStyle(color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Min points slider (rating 1) - shift handover
                  _buildShiftHandoverSliderSection(
                    title: 'Минимальная оценка (1)',
                    subtitle: 'Штраф за плохую сдачу смены',
                    value: _minPoints,
                    min: -5,
                    max: 0,
                    divisions: 50,
                    onChanged: (value) {
                      setState(() => _minPoints = value);
                    },
                    valueLabel: _minPoints.toStringAsFixed(1),
                    valueColor: Colors.red,
                  ),
                  const SizedBox(height: 24),

                  // Zero threshold slider
                  _buildShiftHandoverSliderSection(
                    title: 'Нулевая граница',
                    subtitle: 'Оценка, дающая 0 баллов',
                    value: _zeroThreshold.toDouble(),
                    min: 2,
                    max: 9,
                    divisions: 7,
                    onChanged: (value) {
                      setState(() => _zeroThreshold = value.round());
                    },
                    valueLabel: _zeroThreshold.toString(),
                    isInteger: true,
                  ),
                  const SizedBox(height: 24),

                  // Max points slider (rating 10)
                  _buildShiftHandoverSliderSection(
                    title: 'Максимальная оценка (10)',
                    subtitle: 'Награда за отличную сдачу смены',
                    value: _maxPoints,
                    min: 0,
                    max: 5,
                    divisions: 50,
                    onChanged: (value) {
                      setState(() => _maxPoints = value);
                    },
                    valueLabel: '+${_maxPoints.toStringAsFixed(1)}',
                    valueColor: Colors.green,
                  ),
                  const SizedBox(height: 32),

                  // Preview section for shift handover
                  const Text(
                    'Предпросмотр расчета баллов:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildShiftHandoverPreviewTable(),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildShiftHandoverSliderSection({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
    Color? valueColor,
    bool isInteger = false,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: valueColor ?? const Color(0xFF004D40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    valueLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: valueColor ?? const Color(0xFF004D40),
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isInteger ? min.toInt().toString() : min.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  isInteger ? max.toInt().toString() : max.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Preview table for shift handover ratings
  Widget _buildShiftHandoverPreviewTable() {
    final previewRatings = [1, 4, _zeroThreshold, 8, 10];

    return Card(
      elevation: 2,
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Оценка',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Баллы эффективности',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          ...previewRatings.map((rating) {
            final points = _calculatePoints(rating);
            final color = points < 0
                ? Colors.red
                : points > 0
                    ? Colors.green
                    : Colors.grey;
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '$rating / 10',
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    points >= 0
                        ? '+${points.toStringAsFixed(2)}'
                        : points.toStringAsFixed(2),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// Page for configuring reviews points settings (Отзывы)
class ReviewsPointsSettingsPage extends StatefulWidget {
  const ReviewsPointsSettingsPage({super.key});

  @override
  State<ReviewsPointsSettingsPage> createState() =>
      _ReviewsPointsSettingsPageState();
}

class _ReviewsPointsSettingsPageState
    extends State<ReviewsPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  ReviewsPointsSettings? _settings;

  // Editable values for reviews
  double _positivePoints = 3;
  double _negativePoints = -5;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings =
          await PointsSettingsService.getReviewsPointsSettings();
      setState(() {
        _settings = settings;
        _positivePoints = settings.positivePoints;
        _negativePoints = settings.negativePoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки настроек: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final result =
          await PointsSettingsService.saveReviewsPointsSettings(
        positivePoints: _positivePoints,
        negativePoints: _negativePoints,
      );

      if (result != null) {
        setState(() {
          _settings = result;
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки сохранены'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Не удалось сохранить настройки');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Баллы за отзывы'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card for reviews
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Баллы начисляются за отзывы клиентов на магазин',
                              style: TextStyle(color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Positive review points slider
                  _buildReviewsSliderSection(
                    title: 'Положительный отзыв',
                    subtitle: 'Награда за хороший отзыв',
                    value: _positivePoints,
                    min: 0,
                    max: 10,
                    divisions: 100,
                    onChanged: (value) {
                      setState(() => _positivePoints = value);
                    },
                    valueLabel: '+${_positivePoints.toStringAsFixed(1)}',
                    valueColor: Colors.green,
                  ),
                  const SizedBox(height: 24),

                  // Negative review points slider
                  _buildReviewsSliderSection(
                    title: 'Отрицательный отзыв',
                    subtitle: 'Штраф за плохой отзыв',
                    value: _negativePoints,
                    min: -10,
                    max: 0,
                    divisions: 100,
                    onChanged: (value) {
                      setState(() => _negativePoints = value);
                    },
                    valueLabel: _negativePoints.toStringAsFixed(1),
                    valueColor: Colors.red,
                  ),
                  const SizedBox(height: 32),

                  // Preview section for reviews
                  const Text(
                    'Предпросмотр:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildReviewsPreviewTable(),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildReviewsSliderSection({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
    Color? valueColor,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: valueColor ?? const Color(0xFF004D40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    valueLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: valueColor ?? const Color(0xFF004D40),
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  min.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  max.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewsPreviewTable() {
    return Card(
      elevation: 2,
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Тип отзыва',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Баллы',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.thumb_up, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    const Text('Положительный'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '+${_positivePoints.toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.thumb_down, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    const Text('Отрицательный'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _negativePoints.toStringAsFixed(2),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Page for configuring product search points settings (Поиск товара)
class ProductSearchPointsSettingsPage extends StatefulWidget {
  const ProductSearchPointsSettingsPage({super.key});

  @override
  State<ProductSearchPointsSettingsPage> createState() =>
      _ProductSearchPointsSettingsPageState();
}

class _ProductSearchPointsSettingsPageState
    extends State<ProductSearchPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  ProductSearchPointsSettings? _settings;

  // Editable values for product search
  double _answeredPoints = 0.2;
  double _notAnsweredPoints = -3;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings =
          await PointsSettingsService.getProductSearchPointsSettings();
      setState(() {
        _settings = settings;
        _answeredPoints = settings.answeredPoints;
        _notAnsweredPoints = settings.notAnsweredPoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки настроек: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final result =
          await PointsSettingsService.saveProductSearchPointsSettings(
        answeredPoints: _answeredPoints,
        notAnsweredPoints: _notAnsweredPoints,
      );

      if (result != null) {
        setState(() {
          _settings = result;
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки сохранены'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Не удалось сохранить настройки');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Баллы за поиск товара'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card for product search
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Баллы начисляются за ответы на запросы поиска товара',
                              style: TextStyle(color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Answered points slider
                  _buildProductSearchSliderSection(
                    title: 'Ответили вовремя',
                    subtitle: 'Награда за своевременный ответ',
                    value: _answeredPoints,
                    min: 0,
                    max: 5,
                    divisions: 50,
                    onChanged: (value) {
                      setState(() => _answeredPoints = value);
                    },
                    valueLabel: '+${_answeredPoints.toStringAsFixed(1)}',
                    valueColor: Colors.green,
                  ),
                  const SizedBox(height: 24),

                  // Not answered points slider
                  _buildProductSearchSliderSection(
                    title: 'Не ответили',
                    subtitle: 'Штраф за отсутствие ответа',
                    value: _notAnsweredPoints,
                    min: -10,
                    max: 0,
                    divisions: 100,
                    onChanged: (value) {
                      setState(() => _notAnsweredPoints = value);
                    },
                    valueLabel: _notAnsweredPoints.toStringAsFixed(1),
                    valueColor: Colors.red,
                  ),
                  const SizedBox(height: 32),

                  // Preview section for product search
                  const Text(
                    'Предпросмотр:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildProductSearchPreviewTable(),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildProductSearchSliderSection({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
    Color? valueColor,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: valueColor ?? const Color(0xFF004D40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    valueLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: valueColor ?? const Color(0xFF004D40),
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  min.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  max.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductSearchPreviewTable() {
    return Card(
      elevation: 2,
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Статус ответа',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Баллы',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    const Text('Ответили'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '+${_answeredPoints.toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cancel, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    const Text('Не ответили'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _notAnsweredPoints.toStringAsFixed(2),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Page for configuring orders points settings (Заказы клиентов)
class OrdersPointsSettingsPage extends StatefulWidget {
  const OrdersPointsSettingsPage({super.key});

  @override
  State<OrdersPointsSettingsPage> createState() =>
      _OrdersPointsSettingsPageState();
}

class _OrdersPointsSettingsPageState
    extends State<OrdersPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  OrdersPointsSettings? _settings;

  // Editable values for orders
  double _acceptedPoints = 0.2;
  double _rejectedPoints = -3;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings =
          await PointsSettingsService.getOrdersPointsSettings();
      setState(() {
        _settings = settings;
        _acceptedPoints = settings.acceptedPoints;
        _rejectedPoints = settings.rejectedPoints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки настроек: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final result =
          await PointsSettingsService.saveOrdersPointsSettings(
        acceptedPoints: _acceptedPoints,
        rejectedPoints: _rejectedPoints,
      );

      if (result != null) {
        setState(() {
          _settings = result;
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройки сохранены'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Не удалось сохранить настройки');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Баллы за заказы'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card for orders
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Баллы начисляются за обработку заказов клиентов',
                              style: TextStyle(color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Accepted order points slider
                  _buildOrdersSliderSection(
                    title: 'Приняли заказ',
                    subtitle: 'Награда за принятие заказа',
                    value: _acceptedPoints,
                    min: 0,
                    max: 5,
                    divisions: 50,
                    onChanged: (value) {
                      setState(() => _acceptedPoints = value);
                    },
                    valueLabel: '+${_acceptedPoints.toStringAsFixed(1)}',
                    valueColor: Colors.green,
                  ),
                  const SizedBox(height: 24),

                  // Rejected order points slider
                  _buildOrdersSliderSection(
                    title: 'Отказали в заказе',
                    subtitle: 'Штраф за отказ',
                    value: _rejectedPoints,
                    min: -10,
                    max: 0,
                    divisions: 100,
                    onChanged: (value) {
                      setState(() => _rejectedPoints = value);
                    },
                    valueLabel: _rejectedPoints.toStringAsFixed(1),
                    valueColor: Colors.red,
                  ),
                  const SizedBox(height: 32),

                  // Preview section for orders
                  const Text(
                    'Предпросмотр:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildOrdersPreviewTable(),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildOrdersSliderSection({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
    Color? valueColor,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: valueColor ?? const Color(0xFF004D40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    valueLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: valueColor ?? const Color(0xFF004D40),
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  min.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  max.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersPreviewTable() {
    return Card(
      elevation: 2,
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Статус заказа',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Баллы',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    const Text('Принят'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '+${_acceptedPoints.toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cancel, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    const Text('Отказ'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _rejectedPoints.toStringAsFixed(2),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

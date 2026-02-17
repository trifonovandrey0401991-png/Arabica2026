import 'package:flutter/material.dart';
import '../models/fortune_wheel_model.dart';
import '../services/fortune_wheel_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница настроек секторов Колеса Удачи (для админа)
class WheelSettingsPage extends StatefulWidget {
  const WheelSettingsPage({super.key});

  @override
  State<WheelSettingsPage> createState() => _WheelSettingsPageState();
}

class _WheelSettingsPageState extends State<WheelSettingsPage> {
  List<FortuneWheelSector> _sectors = [];
  int _topEmployeesCount = 3; // Количество топ-сотрудников (1-10)
  bool _isLoading = true;
  bool _isSaving = false;

  final List<TextEditingController> _textControllers = [];
  final List<TextEditingController> _probControllers = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    for (final c in _textControllers) {
      c.dispose();
    }
    for (final c in _probControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final settings = await FortuneWheelService.getSettings();

    if (mounted) {
      _textControllers.clear();
      _probControllers.clear();

      final sectors = settings?.sectors ?? [];

      for (final sector in sectors) {
        _textControllers.add(TextEditingController(text: sector.text));
        _probControllers.add(
          TextEditingController(text: (sector.probability * 100).toStringAsFixed(1)),
        );
      }

      setState(() {
        _sectors = sectors;
        _topEmployeesCount = settings?.topEmployeesCount ?? 3; // Читаем topEmployeesCount
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    // Валидация topEmployeesCount
    if (_topEmployeesCount < 1 || _topEmployeesCount > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Количество должно быть от 1 до 10'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isSaving = false);
      return;
    }

    // Собираем обновлённые секторы
    final updatedSectors = <FortuneWheelSector>[];
    for (int i = 0; i < _sectors.length; i++) {
      final prob = double.tryParse(_probControllers[i].text) ?? 6.67;
      updatedSectors.add(_sectors[i].copyWith(
        text: _textControllers[i].text,
        probability: prob / 100,
      ));
    }

    // Создаём настройки с topEmployeesCount
    final updatedSettings = FortuneWheelSettings(
      topEmployeesCount: _topEmployeesCount,
      sectors: updatedSectors,
    );

    final success = await FortuneWheelService.updateSettings(updatedSettings);

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Настройки сохранены' : 'Ошибка сохранения'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );

      if (success) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Настройка Колеса Удачи'),
        backgroundColor: AppColors.primaryGreen,
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _isSaving ? null : _saveSettings,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Настройка количества топ-сотрудников
                Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withOpacity(0.1),
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Заголовок
                      Row(
                        children: [
                          Icon(Icons.emoji_events, color: AppColors.primaryGreen, size: 24),
                          SizedBox(width: 12),
                          Text(
                            'Количество призовых мест',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryGreen,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),

                      // Кнопки выбора количества
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: [
                          for (int i = 1; i <= 10; i++)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _topEmployeesCount = i;
                                });
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: _topEmployeesCount == i
                                      ? LinearGradient(
                                          colors: [Color(0xFF00695C), AppColors.primaryGreen],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        )
                                      : null,
                                  color: _topEmployeesCount == i ? null : Colors.white,
                                  borderRadius: BorderRadius.circular(10.r),
                                  border: Border.all(
                                    color: _topEmployeesCount == i
                                        ? AppColors.primaryGreen
                                        : Colors.grey.shade300,
                                    width: _topEmployeesCount == i ? 2.5 : 1.5,
                                  ),
                                  boxShadow: [
                                    if (_topEmployeesCount == i)
                                      BoxShadow(
                                        color: AppColors.primaryGreen.withOpacity(0.3),
                                        blurRadius: 6,
                                        offset: Offset(0, 3),
                                      ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    '$i',
                                    style: TextStyle(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.bold,
                                      color: _topEmployeesCount == i
                                          ? Colors.white
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),

                      SizedBox(height: 12),

                      // Предпросмотр распределения
                      Container(
                        padding: EdgeInsets.all(12.w),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Распределение прокруток:',
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[700],
                              ),
                            ),
                            SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                for (int i = 0; i < _topEmployeesCount; i++)
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: i == 0
                                            ? [Color(0xFFFFD700), Color(0xFFFFA500)] // Золото
                                            : i == 1
                                                ? [Color(0xFFE8E8E8), Color(0xFFC0C0C0)] // Серебро
                                                : i == 2
                                                    ? [Color(0xFFCD7F32), Color(0xFF8B4513)] // Бронза
                                                    : [Color(0xFF64B5F6), AppColors.blue], // Синий
                                      ),
                                      borderRadius: BorderRadius.circular(18.r),
                                      border: Border.all(
                                        color: i == 0
                                            ? Color(0xFFFFD700)
                                            : i == 1
                                                ? Color(0xFFC0C0C0)
                                                : i == 2
                                                    ? Color(0xFFCD7F32)
                                                    : Color(0xFF1976D2),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (i == 0
                                                  ? Color(0xFFFFD700)
                                                  : i == 1
                                                      ? Color(0xFFC0C0C0)
                                                      : i == 2
                                                          ? Color(0xFFCD7F32)
                                                          : Color(0xFF1976D2))
                                              .withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '${i + 1}',
                                          style: TextStyle(fontSize: 14.sp),
                                        ),
                                        SizedBox(width: 5),
                                        Text(
                                          '${i == 0 ? 2 : 1} спин${i == 0 ? 'а' : ''}',
                                          style: TextStyle(
                                            fontSize: 11.sp,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black.withOpacity(0.25),
                                                offset: Offset(0, 1),
                                                blurRadius: 1,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Инфо
                Container(
                  padding: EdgeInsets.all(16.w),
                  color: Colors.amber[50],
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber[800]),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Сумма вероятностей должна быть 100%.\n'
                          'Текущая сумма: ${_calculateTotalProbability().toStringAsFixed(1)}%',
                          style: TextStyle(color: Colors.amber[900]),
                        ),
                      ),
                    ],
                  ),
                ),

                // Список секторов
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.all(16.w),
                    itemCount: _sectors.length,
                    itemBuilder: (context, index) {
                      return _buildSectorCard(index);
                    },
                  ),
                ),

                // Кнопка сохранения
                Padding(
                  padding: EdgeInsets.all(16.w),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: _isSaving
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Сохранить',
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectorCard(int index) {
    final sector = _sectors[index];

    return Card(
      margin: EdgeInsets.only(bottom: 12.h),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок с цветом
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: sector.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: sector.color.withOpacity(0.3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Сектор ${index + 1}',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),

            // Текст приза
            TextField(
              controller: _textControllers[index],
              decoration: InputDecoration(
                labelText: 'Текст приза',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            SizedBox(height: 12),

            // Вероятность
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _probControllers[index],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Вероятность (%)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(width: 12),
                // Быстрые кнопки
                IconButton(
                  icon: Icon(Icons.remove_circle_outline),
                  color: Colors.red,
                  onPressed: () {
                    final current = double.tryParse(_probControllers[index].text) ?? 0;
                    if (current > 0) {
                      _probControllers[index].text = (current - 1).toStringAsFixed(1);
                      setState(() {});
                    }
                  },
                ),
                IconButton(
                  icon: Icon(Icons.add_circle_outline),
                  color: Colors.green,
                  onPressed: () {
                    final current = double.tryParse(_probControllers[index].text) ?? 0;
                    _probControllers[index].text = (current + 1).toStringAsFixed(1);
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _calculateTotalProbability() {
    double total = 0;
    for (final c in _probControllers) {
      total += double.tryParse(c.text) ?? 0;
    }
    return total;
  }
}

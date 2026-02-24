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
    if (mounted) setState(() => _isLoading = true);

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

      if (mounted) setState(() {
        _sectors = sectors;
        _topEmployeesCount = settings?.topEmployeesCount ?? 3; // Читаем topEmployeesCount
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (mounted) setState(() => _isSaving = true);

    // Валидация topEmployeesCount
    if (_topEmployeesCount < 1 || _topEmployeesCount > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Количество должно быть от 1 до 10'),
          backgroundColor: Colors.red,
        ),
      );
      if (mounted) setState(() => _isSaving = false);
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

    if (mounted) setState(() => _isSaving = false);

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
      backgroundColor: AppColors.night,
      appBar: AppBar(
        title: Text('Настройка Колеса Удачи', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.emeraldDark,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.gold),
        actions: [
          IconButton(
            icon: Icon(Icons.save, color: AppColors.gold),
            onPressed: _isSaving ? null : _saveSettings,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.gold))
          : Column(
              children: [
                // Настройка количества топ-сотрудников
                Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldDark,
                    border: Border(
                      bottom: BorderSide(color: AppColors.emerald.withOpacity(0.3)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Заголовок
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.gold.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10.r),
                            ),
                            child: Icon(Icons.emoji_events, color: AppColors.gold, size: 22),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Призовые места',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),

                      // Кнопки выбора количества — горизонтальная полоса
                      Container(
                        padding: EdgeInsets.all(4.w),
                        decoration: BoxDecoration(
                          color: AppColors.night.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Row(
                          children: [
                            for (int i = 1; i <= 10; i++)
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    if (mounted) setState(() {
                                      _topEmployeesCount = i;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: Duration(milliseconds: 200),
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: _topEmployeesCount == i
                                          ? AppColors.gold
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(9.r),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '$i',
                                        style: TextStyle(
                                          fontSize: 14.sp,
                                          fontWeight: FontWeight.bold,
                                          color: _topEmployeesCount == i
                                              ? AppColors.night
                                              : Colors.white.withOpacity(0.5),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      SizedBox(height: 16),

                      // Предпросмотр распределения — таблица
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.night.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: AppColors.emerald.withOpacity(0.2)),
                        ),
                        child: Column(
                          children: [
                            // Шапка
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                              decoration: BoxDecoration(
                                color: AppColors.emerald.withOpacity(0.15),
                                borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text('Место', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.6))),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text('Прокрутки', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.6))),
                                  ),
                                ],
                              ),
                            ),
                            // Строки мест
                            for (int i = 0; i < _topEmployeesCount; i++)
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                                decoration: BoxDecoration(
                                  border: i < _topEmployeesCount - 1
                                      ? Border(bottom: BorderSide(color: AppColors.emerald.withOpacity(0.1)))
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    // Место (с медалью для топ-3)
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: i == 0
                                                  ? AppColors.gold.withOpacity(0.2)
                                                  : i == 1
                                                      ? Color(0xFFC0C0C0).withOpacity(0.2)
                                                      : i == 2
                                                          ? Color(0xFFCD7F32).withOpacity(0.2)
                                                          : AppColors.emerald.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(8.r),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '${i + 1}',
                                                style: TextStyle(
                                                  fontSize: 13.sp,
                                                  fontWeight: FontWeight.bold,
                                                  color: i == 0
                                                      ? AppColors.gold
                                                      : i == 1
                                                          ? Color(0xFFC0C0C0)
                                                          : i == 2
                                                              ? Color(0xFFCD7F32)
                                                              : Colors.white.withOpacity(0.7),
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            i == 0 ? 'место' : i == 1 ? 'место' : i == 2 ? 'место' : 'место',
                                            style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.7)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Количество спинов
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                                            decoration: BoxDecoration(
                                              color: i == 0
                                                  ? AppColors.gold.withOpacity(0.15)
                                                  : AppColors.emerald.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(8.r),
                                              border: Border.all(
                                                color: i == 0
                                                    ? AppColors.gold.withOpacity(0.3)
                                                    : AppColors.emerald.withOpacity(0.3),
                                              ),
                                            ),
                                            child: Text(
                                              '${i == 0 ? 2 : 1} спин${i == 0 ? 'а' : ''}',
                                              style: TextStyle(
                                                fontSize: 13.sp,
                                                fontWeight: FontWeight.bold,
                                                color: i == 0 ? AppColors.gold : Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
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
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    border: Border(
                      bottom: BorderSide(color: AppColors.emerald.withOpacity(0.3)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Сумма вероятностей должна быть 100%.\n'
                          'Текущая сумма: ${_calculateTotalProbability().toStringAsFixed(1)}%',
                          style: TextStyle(color: Colors.amber[300]),
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

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
      ),
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
                    border: Border.all(color: AppColors.emerald.withOpacity(0.5), width: 2),
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
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),

            // Текст приза
            TextField(
              controller: _textControllers[index],
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Текст приза',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                ),
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
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Вероятность (%)',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.emerald.withOpacity(0.5)),
                      ),
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
                      if (mounted) setState(() {});
                    }
                  },
                ),
                IconButton(
                  icon: Icon(Icons.add_circle_outline),
                  color: Colors.green,
                  onPressed: () {
                    final current = double.tryParse(_probControllers[index].text) ?? 0;
                    _probControllers[index].text = (current + 1).toStringAsFixed(1);
                    if (mounted) setState(() {});
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

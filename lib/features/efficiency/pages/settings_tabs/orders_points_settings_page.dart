import 'package:flutter/material.dart';
import '../../models/points_settings_model.dart';
import '../../services/points_settings_service.dart';
import '../../widgets/settings_widgets.dart';
import '../../../orders/services/order_timeout_settings_service.dart';

/// Page for configuring orders points settings (Заказы клиентов)
class OrdersPointsSettingsPage extends StatefulWidget {
  const OrdersPointsSettingsPage({super.key});

  @override
  State<OrdersPointsSettingsPage> createState() =>
      _OrdersPointsSettingsPageState();
}

class _OrdersPointsSettingsPageState extends State<OrdersPointsSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  OrdersPointsSettings? _settings;

  double _acceptedPoints = 0.2;
  double _rejectedPoints = -3;

  // Настройки таймаута для пропущенных заказов
  int _timeoutMinutes = 15;
  double _missedOrderPenalty = -2;

  // Gradient colors for this page (green theme for orders)
  static const _gradientColors = [Color(0xFF11998e), Color(0xFF38ef7d)];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      // Загружаем настройки баллов за принятие/отклонение
      final settings = await PointsSettingsService.getOrdersPointsSettings();

      // Загружаем настройки таймаута для пропущенных заказов
      final timeoutSettings = await OrderTimeoutSettingsService.getSettings();

      setState(() {
        _settings = settings;
        _acceptedPoints = settings.acceptedPoints;
        _rejectedPoints = settings.rejectedPoints;
        _timeoutMinutes = timeoutSettings.timeoutMinutes;
        _missedOrderPenalty = timeoutSettings.missedOrderPenalty.toDouble();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки настроек: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      // Сохраняем настройки баллов за принятие/отклонение
      final result = await PointsSettingsService.saveOrdersPointsSettings(
        acceptedPoints: _acceptedPoints,
        rejectedPoints: _rejectedPoints,
      );

      // Сохраняем настройки таймаута для пропущенных заказов
      final timeoutResult = await OrderTimeoutSettingsService.saveSettings(
        timeoutMinutes: _timeoutMinutes,
        missedOrderPenalty: _missedOrderPenalty.toInt(),
      );

      if (result != null && timeoutResult) {
        setState(() { _settings = result; _isSaving = false; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Настройки сохранены'),
                ],
              ),
              backgroundColor: Colors.green[400],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Баллы за заказы'),
        backgroundColor: _gradientColors[0],
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _gradientColors[0]))
          : Column(
              children: [
                // Заголовок
                SettingsHeaderCard(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Заказы клиентов',
                  subtitle: 'Баллы за обработку заказов',
                  gradientColors: _gradientColors,
                ),
                // Контент
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Accepted points slider
                        SettingsSliderWidget(
                          title: 'Заказ принят',
                          subtitle: 'Награда за принятие заказа',
                          value: _acceptedPoints,
                          min: 0,
                          max: 2,
                          divisions: 20,
                          onChanged: (value) => setState(() => _acceptedPoints = value),
                          valueLabel: '+${_acceptedPoints.toStringAsFixed(1)}',
                          accentColor: Colors.green,
                          icon: Icons.check_circle_outline,
                        ),
                        const SizedBox(height: 16),

                        // Rejected points slider
                        SettingsSliderWidget(
                          title: 'Заказ отклонен',
                          subtitle: 'Штраф за отклонение заказа',
                          value: _rejectedPoints,
                          min: -5,
                          max: 0,
                          divisions: 50,
                          onChanged: (value) => setState(() => _rejectedPoints = value),
                          valueLabel: _rejectedPoints.toStringAsFixed(1),
                          accentColor: Colors.red,
                          icon: Icons.cancel_outlined,
                        ),
                        const SizedBox(height: 24),

                        // Divider section for timeout settings
                        SettingsSectionTitle(
                          title: 'Пропущенные заказы',
                          gradientColors: _gradientColors,
                        ),
                        const SizedBox(height: 12),

                        // Timeout info card
                        SettingsInfoBox(
                          text: 'Если заказ не принят вовремя, штраф получают ВСЕ сотрудники на смене',
                          color: Colors.orange,
                          icon: Icons.info_outline,
                        ),
                        const SizedBox(height: 16),

                        // Timeout dropdown
                        _buildDropdownSection(
                          title: 'Таймаут на принятие',
                          subtitle: 'Время ожидания принятия заказа',
                          value: _timeoutMinutes,
                          items: const [5, 10, 15, 20, 30],
                          onChanged: (value) => setState(() => _timeoutMinutes = value ?? 15),
                          valueLabel: '$_timeoutMinutes мин',
                          accentColor: Colors.orange,
                          icon: Icons.timer_outlined,
                        ),
                        const SizedBox(height: 16),

                        // Missed order penalty slider
                        SettingsSliderWidget(
                          title: 'Штраф за пропуск',
                          subtitle: 'Штраф за не принятый вовремя заказ',
                          value: _missedOrderPenalty,
                          min: -5,
                          max: 0,
                          divisions: 50,
                          onChanged: (value) => setState(() => _missedOrderPenalty = value),
                          valueLabel: _missedOrderPenalty.toStringAsFixed(1),
                          accentColor: Colors.orange,
                          icon: Icons.timer_off_outlined,
                        ),
                        const SizedBox(height: 24),

                        // Preview section
                        SettingsSectionTitle(
                          title: 'Предпросмотр',
                          gradientColors: _gradientColors,
                        ),
                        const SizedBox(height: 12),
                        _buildPreviewTable(),
                        const SizedBox(height: 24),

                        // Save button
                        SettingsSaveButton(
                          isSaving: _isSaving,
                          onPressed: _saveSettings,
                          gradientColors: _gradientColors,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDropdownSection({
    required String title,
    required String subtitle,
    required int value,
    required List<int> items,
    required ValueChanged<int?> onChanged,
    required String valueLabel,
    Color accentColor = const Color(0xFF11998e),
    IconData icon = Icons.tune,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3436),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accentColor.withOpacity(0.3)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: value,
                  isExpanded: true,
                  icon: Icon(Icons.keyboard_arrow_down, color: accentColor),
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  items: items.map((item) => DropdownMenuItem(
                    value: item,
                    child: Text('$item минут'),
                  )).toList(),
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _gradientColors,
                ),
              ),
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      'Статус заказа',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Баллы',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            // Accepted row
            _buildPreviewRow(
              icon: Icons.check_circle,
              iconColor: Colors.green,
              label: 'Принят',
              points: _acceptedPoints,
              isPositive: true,
              backgroundColor: Colors.grey[50]!,
            ),
            // Rejected row
            _buildPreviewRow(
              icon: Icons.cancel,
              iconColor: Colors.red,
              label: 'Отклонён',
              points: _rejectedPoints,
              isPositive: false,
              backgroundColor: Colors.white,
            ),
            // Missed row
            _buildPreviewRow(
              icon: Icons.timer_off,
              iconColor: Colors.orange,
              label: 'Пропущен',
              points: _missedOrderPenalty,
              isPositive: false,
              backgroundColor: Colors.orange.withOpacity(0.05),
              pointsColor: Colors.orange,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required double points,
    required bool isPositive,
    required Color backgroundColor,
    Color? pointsColor,
    bool isLast = false,
  }) {
    final color = pointsColor ?? (isPositive ? Colors.green : Colors.red);
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isPositive ? '+${points.toStringAsFixed(2)}' : points.toStringAsFixed(2),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

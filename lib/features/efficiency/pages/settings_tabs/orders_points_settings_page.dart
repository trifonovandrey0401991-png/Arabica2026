import 'package:flutter/material.dart';
import '../../models/points_settings_model.dart';
import '../../services/points_settings_service.dart';
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
            const SnackBar(content: Text('Настройки сохранены'), backgroundColor: Colors.green),
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
                  _buildSliderSection(
                    title: 'Заказ принят',
                    subtitle: 'Награда за принятие заказа',
                    value: _acceptedPoints,
                    min: 0,
                    max: 2,
                    divisions: 20,
                    onChanged: (value) => setState(() => _acceptedPoints = value),
                    valueLabel: '+${_acceptedPoints.toStringAsFixed(1)}',
                    valueColor: Colors.green,
                  ),
                  const SizedBox(height: 24),
                  _buildSliderSection(
                    title: 'Заказ отклонен',
                    subtitle: 'Штраф за отклонение заказа',
                    value: _rejectedPoints,
                    min: -5,
                    max: 0,
                    divisions: 50,
                    onChanged: (value) => setState(() => _rejectedPoints = value),
                    valueLabel: _rejectedPoints.toStringAsFixed(1),
                    valueColor: Colors.red,
                  ),
                  const SizedBox(height: 32),
                  // Разделитель
                  const Divider(thickness: 2),
                  const SizedBox(height: 16),
                  // Секция настроек таймаута
                  Card(
                    color: Colors.orange[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.timer_off, color: Colors.orange[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Если заказ не принят в течение указанного времени, сотрудникам на смене будет назначен штраф',
                              style: TextStyle(color: Colors.orange[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Выбор таймаута
                  _buildDropdownSection(
                    title: 'Таймаут на принятие',
                    subtitle: 'Время ожидания принятия заказа',
                    value: _timeoutMinutes,
                    items: const [5, 10, 15, 20, 30],
                    onChanged: (value) => setState(() => _timeoutMinutes = value ?? 15),
                    valueLabel: '$_timeoutMinutes мин',
                    valueColor: Colors.orange,
                  ),
                  const SizedBox(height: 24),
                  _buildSliderSection(
                    title: 'Штраф за пропуск заказа',
                    subtitle: 'Штраф ВСЕМ сотрудникам на смене за не принятый вовремя заказ',
                    value: _missedOrderPenalty,
                    min: -5,
                    max: 0,
                    divisions: 50,
                    onChanged: (value) => setState(() => _missedOrderPenalty = value),
                    valueLabel: _missedOrderPenalty.toStringAsFixed(1),
                    valueColor: Colors.orange,
                  ),
                  const SizedBox(height: 32),
                  const Text('Предпросмотр:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildPreviewTable(),
                  const SizedBox(height: 32),
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
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                          : const Text('Сохранить', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: valueColor ?? const Color(0xFF004D40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(valueLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(value: value, min: min, max: max, divisions: divisions, activeColor: valueColor ?? const Color(0xFF004D40), onChanged: onChanged),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(min.toString(), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text(max.toString(), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ],
        ),
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
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: valueColor ?? const Color(0xFF004D40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(valueLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: valueColor ?? Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: value,
                  isExpanded: true,
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
    return Card(
      elevation: 2,
      child: Table(
        border: TableBorder.all(color: Colors.grey[300]!),
        columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: const [
              Padding(padding: EdgeInsets.all(12), child: Text('Статус заказа', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
              Padding(padding: EdgeInsets.all(12), child: Text('Баллы', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Icon(Icons.check_circle, color: Colors.green, size: 20), const SizedBox(width: 8), const Text('Принят')],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('+${_acceptedPoints.toStringAsFixed(2)}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Icon(Icons.cancel, color: Colors.red, size: 20), const SizedBox(width: 8), const Text('Отклонен')],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_rejectedPoints.toStringAsFixed(2), textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          TableRow(
            decoration: BoxDecoration(color: Colors.orange[50]),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Icon(Icons.timer_off, color: Colors.orange, size: 20), const SizedBox(width: 8), const Flexible(child: Text('Не подтверждён', overflow: TextOverflow.ellipsis))],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_missedOrderPenalty.toStringAsFixed(2), textAlign: TextAlign.center, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

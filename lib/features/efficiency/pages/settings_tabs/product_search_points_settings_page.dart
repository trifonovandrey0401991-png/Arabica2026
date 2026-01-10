import 'package:flutter/material.dart';
import '../../models/points_settings_model.dart';
import '../../services/points_settings_service.dart';

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
      final settings = await PointsSettingsService.getProductSearchPointsSettings();
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
          SnackBar(content: Text('Ошибка загрузки настроек: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final result = await PointsSettingsService.saveProductSearchPointsSettings(
        answeredPoints: _answeredPoints,
        notAnsweredPoints: _notAnsweredPoints,
      );
      if (result != null) {
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
                              'Баллы начисляются за ответ на запрос клиента о наличии товара',
                              style: TextStyle(color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSliderSection(
                    title: 'Ответил вовремя',
                    subtitle: 'Награда за своевременный ответ',
                    value: _answeredPoints,
                    min: 0,
                    max: 2,
                    divisions: 20,
                    onChanged: (value) => setState(() => _answeredPoints = value),
                    valueLabel: '+${_answeredPoints.toStringAsFixed(1)}',
                    valueColor: Colors.green,
                  ),
                  const SizedBox(height: 24),
                  _buildSliderSection(
                    title: 'Не ответил',
                    subtitle: 'Штраф за отсутствие ответа',
                    value: _notAnsweredPoints,
                    min: -5,
                    max: 0,
                    divisions: 50,
                    onChanged: (value) => setState(() => _notAnsweredPoints = value),
                    valueLabel: _notAnsweredPoints.toStringAsFixed(1),
                    valueColor: Colors.red,
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
              Padding(padding: EdgeInsets.all(12), child: Text('Статус ответа', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
              Padding(padding: EdgeInsets.all(12), child: Text('Баллы', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Icon(Icons.check_circle, color: Colors.green, size: 20), const SizedBox(width: 8), const Text('Ответил')],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('+${_answeredPoints.toStringAsFixed(2)}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Icon(Icons.cancel, color: Colors.red, size: 20), const SizedBox(width: 8), const Text('Не ответил')],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_notAnsweredPoints.toStringAsFixed(2), textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

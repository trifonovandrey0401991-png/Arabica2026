import 'package:flutter/material.dart';
import '../../models/points_settings_model.dart';
import '../../services/points_settings_service.dart';
import '../../../../core/utils/logger.dart';

class RegularTaskPointsSettingsPage extends StatefulWidget {
  const RegularTaskPointsSettingsPage({super.key});

  @override
  State<RegularTaskPointsSettingsPage> createState() => _RegularTaskPointsSettingsPageState();
}

class _RegularTaskPointsSettingsPageState extends State<RegularTaskPointsSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;

  // Controllers
  late TextEditingController _completionController;
  late TextEditingController _penaltyController;

  @override
  void initState() {
    super.initState();
    _completionController = TextEditingController();
    _penaltyController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _completionController.dispose();
    _penaltyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final settings = await PointsSettingsService.getRegularTaskPointsSettings();
      _completionController.text = settings.completionPoints.toString();
      _penaltyController.text = settings.penaltyPoints.toString();
    } catch (e) {
      Logger.error('Ошибка загрузки настроек обычных задач', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final completion = double.parse(_completionController.text);
      final penalty = double.parse(_penaltyController.text);

      await PointsSettingsService.saveRegularTaskPointsSettings(
        completionPoints: completion,
        penaltyPoints: penalty,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Настройки сохранены')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      Logger.error('Ошибка сохранения настроек обычных задач', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Обычные задачи'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Настройка баллов за обычные задачи',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Установите баллы, которые сотрудник получит или потеряет при выполнении/невыполнении обычных задач.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),

                    // Премия за выполнение
                    _buildPointsField(
                      controller: _completionController,
                      label: 'Премия за выполнение',
                      hint: 'Баллы за выполненную задачу',
                      icon: Icons.check_circle,
                      iconColor: Colors.green,
                    ),
                    const SizedBox(height: 16),

                    // Штраф за невыполнение
                    _buildPointsField(
                      controller: _penaltyController,
                      label: 'Штраф за невыполнение',
                      hint: 'Баллы за просроченную/отклонённую задачу (отрицательное число)',
                      icon: Icons.cancel,
                      iconColor: Colors.red,
                    ),
                    const SizedBox(height: 24),

                    // Info box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Новые правила будут применяться только к новым задачам. Существующие задачи сохранят прежние баллы.',
                              style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF004D40),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Сохранить', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPointsField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: iconColor),
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Введите значение';
        }
        final number = double.tryParse(value);
        if (number == null) {
          return 'Введите корректное число';
        }
        if (number < -100 || number > 100) {
          return 'Значение должно быть от -100 до 100';
        }
        return null;
      },
    );
  }
}

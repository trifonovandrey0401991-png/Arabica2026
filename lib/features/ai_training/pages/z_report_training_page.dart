import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/z_report_service.dart';
import '../services/z_report_template_service.dart';
import '../models/z_report_sample_model.dart';
import '../models/z_report_template_model.dart';
import 'template_editor_page.dart';

/// Страница обучения ИИ распознаванию Z-отчётов
class ZReportTrainingPage extends StatefulWidget {
  const ZReportTrainingPage({super.key});

  @override
  State<ZReportTrainingPage> createState() => _ZReportTrainingPageState();
}

class _ZReportTrainingPageState extends State<ZReportTrainingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Обучение Z-отчётов'),
        backgroundColor: const Color(0xFF004D40),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.add_a_photo), text: 'Обучить'),
            Tab(icon: Icon(Icons.grid_view), text: 'Шаблоны'),
            Tab(icon: Icon(Icons.analytics), text: 'Статистика'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _TrainingSampleTab(),
          _TemplatesTab(),
          _StatsTab(),
        ],
      ),
    );
  }
}

// ==================== Вкладка обучения ====================

class _TrainingSampleTab extends StatefulWidget {
  const _TrainingSampleTab();

  @override
  State<_TrainingSampleTab> createState() => _TrainingSampleTabState();
}

class _TrainingSampleTabState extends State<_TrainingSampleTab> {
  File? _selectedImage;
  String? _imageBase64;
  bool _isLoading = false;
  bool _isParsing = false;
  ZReportParseResult? _parseResult;

  // Список шаблонов и выбранный шаблон
  List<ZReportTemplate> _templates = [];
  ZReportTemplate? _selectedTemplate;
  bool _isLoadingTemplates = true;

  final _totalSumController = TextEditingController();
  final _cashSumController = TextEditingController();
  final _ofdNotSentController = TextEditingController();
  final _resourceKeysController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    try {
      final templates = await ZReportTemplateService.getTemplates();
      setState(() {
        _templates = templates;
        _isLoadingTemplates = false;
        // Если есть шаблоны, выбираем первый по умолчанию
        if (templates.isNotEmpty) {
          _selectedTemplate = templates.first;
        }
      });
    } catch (e) {
      setState(() => _isLoadingTemplates = false);
    }
  }

  @override
  void dispose() {
    _totalSumController.dispose();
    _cashSumController.dispose();
    _ofdNotSentController.dispose();
    _resourceKeysController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final bytes = await file.readAsBytes();
      final base64 = base64Encode(bytes);

      setState(() {
        _selectedImage = file;
        _imageBase64 = base64;
        _parseResult = null;
      });

      await _parseImage();
    }
  }

  Future<void> _parseImage() async {
    if (_imageBase64 == null) return;

    setState(() => _isParsing = true);

    try {
      ZReportParseResult result;

      // Если выбран шаблон с областями - используем распознавание по шаблону
      if (_selectedTemplate != null && _selectedTemplate!.regions.isNotEmpty) {
        final response = await ZReportTemplateService.parseWithTemplate(
          imageBase64: _imageBase64!,
          templateId: _selectedTemplate!.id,
        );

        if (response['success'] == true && response['data'] != null) {
          final data = response['data'] as Map<String, dynamic>;
          result = ZReportParseResult(
            success: true,
            rawText: response['rawText'] ?? '',
            data: ZReportData(
              totalSum: data['totalSum']?.toDouble(),
              cashSum: data['cashSum']?.toDouble(),
              ofdNotSent: data['ofdNotSent'],
              resourceKeys: data['resourceKeys'],
              confidence: Map<String, String>.from(data['confidence'] ?? {}),
            ),
          );
        } else {
          result = ZReportParseResult(
            success: false,
            error: response['error'] ?? 'Ошибка распознавания по шаблону',
          );
        }
      } else {
        // Обычное распознавание без шаблона
        result = await ZReportService.parseZReport(_imageBase64!);
      }

      setState(() {
        _parseResult = result;
        _isParsing = false;
      });

      if (result.success && result.data != null) {
        if (result.data!.totalSum != null) {
          _totalSumController.text = result.data!.totalSum!.toStringAsFixed(2);
        }
        if (result.data!.cashSum != null) {
          _cashSumController.text = result.data!.cashSum!.toStringAsFixed(2);
        }
        if (result.data!.ofdNotSent != null) {
          _ofdNotSentController.text = result.data!.ofdNotSent.toString();
        }
        if (result.data!.resourceKeys != null) {
          _resourceKeysController.text = result.data!.resourceKeys.toString();
        }
      }
    } catch (e) {
      setState(() {
        _isParsing = false;
        _parseResult = ZReportParseResult(success: false, error: 'Ошибка: $e');
      });
    }
  }

  Future<void> _saveSample() async {
    if (_imageBase64 == null) {
      _showSnackBar('Сначала сфотографируйте Z-отчёт', Colors.orange);
      return;
    }

    final totalSum = double.tryParse(_totalSumController.text);
    final cashSum = double.tryParse(_cashSumController.text);
    final ofdNotSent = int.tryParse(_ofdNotSentController.text);
    final resourceKeys = int.tryParse(_resourceKeysController.text);

    if (totalSum == null) {
      _showSnackBar('Введите корректную общую сумму', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Сохраняем образец для обучения с информацией о том, что было исправлено
      final success = await ZReportTemplateService.saveTrainingSample(
        imageBase64: _imageBase64!,
        rawText: _parseResult?.rawText ?? '',
        correctData: {
          'totalSum': totalSum,
          'cashSum': cashSum ?? 0,
          'ofdNotSent': ofdNotSent ?? 0,
          'resourceKeys': resourceKeys ?? 0,
        },
        recognizedData: {
          'totalSum': _parseResult?.data?.totalSum,
          'cashSum': _parseResult?.data?.cashSum,
          'ofdNotSent': _parseResult?.data?.ofdNotSent,
          'resourceKeys': _parseResult?.data?.resourceKeys,
        },
      );

      if (success) {
        // Формируем сообщение с результатом обучения
        final learningResult = ZReportTemplateService.lastLearningResult;
        String message = 'Образец сохранён для обучения';

        if (learningResult != null) {
          final newPatterns = learningResult['newPatterns'] ?? 0;
          final totalPatterns = learningResult['totalPatterns'];
          if (newPatterns > 0) {
            message = 'Выучено $newPatterns новых паттернов!';
          } else if (totalPatterns != null) {
            final total = (totalPatterns['totalSum'] ?? 0) +
                         (totalPatterns['cashSum'] ?? 0) +
                         (totalPatterns['ofdNotSent'] ?? 0) +
                         (totalPatterns['resourceKeys'] ?? 0);
            message = 'Образец сохранён. Всего паттернов: $total';
          }
        }

        _showSnackBar(message, Colors.green);
        setState(() {
          _selectedImage = null;
          _imageBase64 = null;
          _parseResult = null;
        });
        _totalSumController.clear();
        _cashSumController.clear();
        _ofdNotSentController.clear();
        _resourceKeysController.clear();
      } else {
        _showSnackBar('Ошибка сохранения образца', Colors.red);
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Инструкция с градиентом
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal.shade50, Colors.blue.shade50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.shade200, width: 1),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.school, color: Colors.teal.shade700, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Выберите шаблон, сфотографируйте Z-отчёт, проверьте данные. '
                    'Это поможет ИИ лучше распознавать такие чеки.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Выбор шаблона
          if (_isLoadingTemplates)
            const Center(child: CircularProgressIndicator())
          else if (_templates.isNotEmpty) ...[
            const Text('Выберите шаблон:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<ZReportTemplate>(
              value: _selectedTemplate,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: _templates.map((template) {
                return DropdownMenuItem(
                  value: template,
                  child: Text(
                    '${template.name} (${template.regions.length} обл.)',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (template) {
                setState(() => _selectedTemplate = template);
                // Если уже есть изображение - перераспознаём с новым шаблоном
                if (_imageBase64 != null) {
                  _parseImage();
                }
              },
            ),
            const SizedBox(height: 16),
          ] else
            Card(
              color: Colors.orange[50],
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Нет шаблонов. Создайте шаблон во вкладке "Шаблоны" для лучшего распознавания.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Кнопки с улучшенным дизайном
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00695C), Color(0xFF004D40)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF004D40).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isLoading || _isParsing ? null : () => _pickImage(ImageSource.camera),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.camera_alt, color: Colors.white, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              'Камера',
                              style: TextStyle(
                                color: _isLoading || _isParsing ? Colors.white54 : Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blueGrey.shade600, Colors.blueGrey.shade800],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueGrey.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isLoading || _isParsing ? null : () => _pickImage(ImageSource.gallery),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.photo_library, color: Colors.white, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              'Галерея',
                              style: TextStyle(
                                color: _isLoading || _isParsing ? Colors.white54 : Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Превью
          if (_selectedImage != null) ...[
            Card(
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Image.file(
                    _selectedImage!,
                    height: 250,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                  if (_isParsing)
                    Container(
                      height: 250,
                      color: Colors.black54,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 16),
                            Text('Распознавание...', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Результат с улучшенным дизайном
          if (_parseResult != null) ...[
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _parseResult!.success
                      ? [Colors.green.shade50, Colors.teal.shade50]
                      : [Colors.red.shade50, Colors.orange.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _parseResult!.success ? Colors.green.shade200 : Colors.red.shade200,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _parseResult!.success
                              ? Colors.green.shade100
                              : Colors.red.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _parseResult!.success ? Icons.check_circle : Icons.error_outline,
                          color: _parseResult!.success ? Colors.green.shade700 : Colors.red.shade700,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _parseResult!.success ? 'Текст распознан' : 'Ошибка распознавания',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: _parseResult!.success ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                            if (_parseResult!.success && _selectedTemplate != null)
                              Text(
                                'Шаблон: ${_selectedTemplate!.name}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_parseResult!.error != null) ...[
                    const SizedBox(height: 10),
                    Text(_parseResult!.error!, style: TextStyle(color: Colors.red.shade700)),
                  ],
                  if (_parseResult!.data != null) ...[
                    const SizedBox(height: 12),
                    _buildConfidenceInfo(_parseResult!.data!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Форма
          const Text('Проверьте и исправьте данные:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          _buildTextField(_totalSumController, 'Общая сумма *', Icons.currency_ruble, true),
          const SizedBox(height: 12),
          _buildTextField(_cashSumController, 'Сумма наличных', Icons.payments_outlined, true),
          const SizedBox(height: 12),
          _buildTextField(_ofdNotSentController, 'Не передано в ОФД', Icons.cloud_off, false),
          const SizedBox(height: 12),
          _buildTextField(_resourceKeysController, 'Ресурс ключей', Icons.key, false),
          const SizedBox(height: 24),

          // Кнопка сохранения с градиентом
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isLoading || _isParsing || _imageBase64 == null
                    ? [Colors.grey.shade400, Colors.grey.shade500]
                    : [Colors.teal.shade600, const Color(0xFF004D40)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: _isLoading || _isParsing || _imageBase64 == null
                  ? []
                  : [
                      BoxShadow(
                        color: const Color(0xFF004D40).withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isLoading || _isParsing || _imageBase64 == null ? null : _saveSample,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isLoading)
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      else
                        const Icon(Icons.save_alt, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        _isLoading ? 'Сохранение...' : 'Сохранить образец',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon, bool decimal) {
    final bool isMoney = icon == Icons.currency_ruble || icon == Icons.payments_outlined;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade600),
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMoney ? Colors.teal.shade50 : Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: isMoney ? Colors.teal.shade700 : Colors.blueGrey.shade700,
              size: 20,
            ),
          ),
          suffixText: isMoney ? '₽' : null,
          suffixStyle: TextStyle(
            color: Colors.teal.shade700,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.teal.shade400, width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildConfidenceInfo(ZReportData data) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Распознанные значения:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          _buildConfidenceRow('Общая сумма', data.totalSum, data.confidence['totalSum'], true),
          _buildConfidenceRow('Наличные', data.cashSum, data.confidence['cashSum'], true),
          _buildConfidenceRow(
              'Не передано в ОФД', data.ofdNotSent?.toDouble(), data.confidence['ofdNotSent'], false),
          _buildConfidenceRow(
              'Ресурс ключей', data.resourceKeys?.toDouble(), data.confidence['resourceKeys'], false),
        ],
      ),
    );
  }

  Widget _buildConfidenceRow(String label, double? value, String? confidence, bool isMoney) {
    final isFound = confidence == 'high' || confidence == 'medium';
    final isHigh = confidence == 'high';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isFound
                  ? (isHigh ? Colors.green.shade100 : Colors.orange.shade100)
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              isFound ? (isHigh ? Icons.check : Icons.help_outline) : Icons.close,
              size: 14,
              color: isFound
                  ? (isHigh ? Colors.green.shade700 : Colors.orange.shade700)
                  : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
          Text(
            value != null
                ? (isMoney ? '${value.toStringAsFixed(2)} ₽' : value.toStringAsFixed(0))
                : '—',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isFound
                  ? (isHigh ? Colors.green.shade800 : Colors.orange.shade800)
                  : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== Вкладка шаблонов ====================

class _TemplatesTab extends StatefulWidget {
  const _TemplatesTab();

  @override
  State<_TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends State<_TemplatesTab> {
  List<ZReportTemplate> _templates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    try {
      final templates = await ZReportTemplateService.getTemplates();
      setState(() {
        _templates = templates;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteTemplate(ZReportTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить шаблон?'),
        content: Text('Шаблон "${template.name}" будет удалён.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ZReportTemplateService.deleteTemplate(template.id);
      _loadTemplates();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Кнопка создания
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (context) => const TemplateEditorPage()),
              );
              if (result == true) _loadTemplates();
            },
            icon: const Icon(Icons.add),
            label: const Text('Создать шаблон'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),

        // Инструкция
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            color: Colors.amber[50],
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.amber),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Создайте шаблон для кассы, выделив области где находятся нужные данные. '
                      'Это улучшит точность распознавания.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Список
        Expanded(
          child: _templates.isEmpty
              ? const Center(
                  child: Text('Шаблонов пока нет', style: TextStyle(color: Colors.grey)),
                )
              : RefreshIndicator(
                  onRefresh: _loadTemplates,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _templates.length,
                    itemBuilder: (context, index) {
                      final template = _templates[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF004D40),
                            child: Text(
                              template.cashRegisterType?.substring(0, 1) ?? '?',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(template.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (template.cashRegisterType != null)
                                Text('Касса: ${template.cashRegisterType}'),
                              Text(
                                'Использований: ${template.usageCount}, '
                                'Успех: ${(template.successRate * 100).toStringAsFixed(0)}%',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                              Text(
                                'Областей: ${template.regions.length}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton(
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                              const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Удалить', style: TextStyle(color: Colors.red))),
                            ],
                            onSelected: (value) {
                              if (value == 'edit') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        TemplateEditorPage(existingTemplate: template),
                                  ),
                                ).then((result) {
                                  if (result == true) _loadTemplates();
                                });
                              } else if (value == 'delete') {
                                _deleteTemplate(template);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

// ==================== Вкладка статистики ====================

class _StatsTab extends StatefulWidget {
  const _StatsTab();

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final stats = await ZReportTemplateService.getTrainingStats();
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalSamples = _stats['totalSamples'] ?? 0;
    final totalTemplates = _stats['totalTemplates'] ?? 0;
    final avgSuccessRate = (_stats['avgSuccessRate'] ?? 0).toDouble();
    final corrections = _stats['correctionsByField'] as Map<String, dynamic>? ?? {};

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Основные показатели
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Образцов',
                    totalSamples.toString(),
                    Icons.photo_library,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Шаблонов',
                    totalTemplates.toString(),
                    Icons.grid_view,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              'Средняя точность',
              '${(avgSuccessRate * 100).toStringAsFixed(1)}%',
              Icons.analytics,
              Colors.purple,
            ),
            const SizedBox(height: 24),

            // Исправления по полям
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.edit_note, color: Colors.orange.shade700, size: 20),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Исправления по полям',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Поля, требующие корректировки',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildCorrectionBar('Общая сумма', corrections['totalSum'] ?? 0, totalSamples),
            const SizedBox(height: 8),
            _buildCorrectionBar('Наличные', corrections['cashSum'] ?? 0, totalSamples),
            const SizedBox(height: 8),
            _buildCorrectionBar('Не передано в ОФД', corrections['ofdNotSent'] ?? 0, totalSamples),
            const SizedBox(height: 8),
            _buildCorrectionBar('Ресурс ключей', corrections['resourceKeys'] ?? 0, totalSamples),

            const SizedBox(height: 24),

            // Подсказка с улучшенным дизайном
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade50, Colors.teal.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200, width: 1),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.lightbulb_outline, color: Colors.green.shade700, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Чем больше образцов с исправлениями — тем точнее будет распознавание. '
                      'Создавайте шаблоны для разных типов касс.',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 28, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorrectionBar(String label, int count, int total) {
    final percent = total > 0 ? count / total : 0.0;
    final color = percent > 0.5 ? Colors.red : (percent > 0.2 ? Colors.orange : Colors.green);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

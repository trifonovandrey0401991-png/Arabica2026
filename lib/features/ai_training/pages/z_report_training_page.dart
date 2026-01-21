import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/z_report_service.dart';
import '../services/z_report_template_service.dart';
import '../models/z_report_sample_model.dart';
import '../models/z_report_template_model.dart';
import 'template_editor_page.dart';

/// Страница обучения ИИ распознаванию Z-отчётов - Премиум версия
class ZReportTrainingPage extends StatefulWidget {
  const ZReportTrainingPage({super.key});

  @override
  State<ZReportTrainingPage> createState() => _ZReportTrainingPageState();
}

class _ZReportTrainingPageState extends State<ZReportTrainingPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  bool _isAdmin = false;
  bool _isInitialized = false;

  // Цвета для градиентов
  static const _purpleGradient = [Color(0xFF6366F1), Color(0xFF8B5CF6)];
  static const _greenGradient = [Color(0xFF10B981), Color(0xFF34D399)];
  static const _orangeGradient = [Color(0xFFF59E0B), Color(0xFFFBBF24)];

  /// Количество вкладок зависит от роли: админ видит 3 вкладки, остальные - 2
  int get _tabCount => _isAdmin ? 3 : 2;

  @override
  void initState() {
    super.initState();
    _initTabController();
  }

  Future<void> _initTabController() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? '';

    if (mounted) {
      setState(() {
        _isAdmin = role == 'admin';
        _tabController = TabController(length: _tabCount, vsync: this);
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
              Color(0xFF0F3460),
            ],
          ),
        ),
        child: SafeArea(
          child: !_isInitialized || _tabController == null
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : Column(
                  children: [
                    // Custom AppBar
                    _buildCustomAppBar(),

                    // TabBar
                    _buildTabBar(),

                    // TabBarView
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          const _TrainingSampleTab(),
                          if (_isAdmin) const _TemplatesTab(),
                          const _StatsTab(),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'Обучение Z-отчётов',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    if (_tabController == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: const LinearGradient(colors: _purpleGradient),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _purpleGradient[0].withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withOpacity(0.5),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        dividerColor: Colors.transparent,
        tabs: [
          const Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_a_photo, size: 18),
                SizedBox(width: 6),
                Text('Обучить'),
              ],
            ),
          ),
          if (_isAdmin)
            const Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.grid_view, size: 18),
                  SizedBox(width: 6),
                  Text('Шаблоны'),
                ],
              ),
            ),
          const Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.analytics, size: 18),
                SizedBox(width: 6),
                Text('Статистика'),
              ],
            ),
          ),
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

  List<ZReportTemplate> _templates = [];
  ZReportTemplate? _selectedTemplate;
  bool _isLoadingTemplates = true;

  final _totalSumController = TextEditingController();
  final _cashSumController = TextEditingController();
  final _ofdNotSentController = TextEditingController();
  final _resourceKeysController = TextEditingController();

  // Цвета
  static const _purpleGradient = [Color(0xFF6366F1), Color(0xFF8B5CF6)];
  static const _greenGradient = [Color(0xFF10B981), Color(0xFF34D399)];

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

        _showSnackBar(message, _greenGradient[0]);
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
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == Colors.red ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Инструкция
          _buildInfoCard(
            icon: Icons.school,
            title: 'Как обучать ИИ',
            description:
                'Выберите шаблон, сфотографируйте Z-отчёт, проверьте данные. '
                'Это поможет ИИ лучше распознавать такие чеки.',
            gradient: _purpleGradient,
          ),
          const SizedBox(height: 16),

          // Выбор шаблона
          if (_isLoadingTemplates)
            Center(
              child: CircularProgressIndicator(
                color: _purpleGradient[0],
              ),
            )
          else if (_templates.isNotEmpty) ...[
            Text(
              'Выберите шаблон',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: DropdownButtonFormField<ZReportTemplate>(
                value: _selectedTemplate,
                dropdownColor: const Color(0xFF1A1A2E),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: _purpleGradient),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.grid_view, color: Colors.white, size: 18),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                items: _templates.map((template) {
                  return DropdownMenuItem(
                    value: template,
                    child: Text(
                      '${template.name} (${template.regions.length} обл.)',
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (template) {
                  setState(() => _selectedTemplate = template);
                  if (_imageBase64 != null) {
                    _parseImage();
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
          ] else
            _buildWarningCard(),
          const SizedBox(height: 16),

          // Кнопки
          Row(
            children: [
              Expanded(
                child: _buildGradientButton(
                  icon: Icons.camera_alt,
                  label: 'Камера',
                  gradient: _purpleGradient,
                  onTap: _isLoading || _isParsing
                      ? null
                      : () => _pickImage(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildGradientButton(
                  icon: Icons.photo_library,
                  label: 'Галерея',
                  gradient: const [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                  onTap: _isLoading || _isParsing
                      ? null
                      : () => _pickImage(ImageSource.gallery),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Превью
          if (_selectedImage != null) ...[
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
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
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              color: _purpleGradient[0],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Распознавание...',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Результат
          if (_parseResult != null) ...[
            _buildResultCard(_parseResult!),
            const SizedBox(height: 16),
          ],

          // Форма
          Text(
            'Проверьте и исправьте данные',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 12),

          _buildDarkTextField(_totalSumController, 'Общая сумма *', Icons.currency_ruble, true),
          const SizedBox(height: 12),
          _buildDarkTextField(_cashSumController, 'Сумма наличных', Icons.payments_outlined, true),
          const SizedBox(height: 12),
          _buildDarkTextField(_ofdNotSentController, 'Не передано в ОФД', Icons.cloud_off, false),
          const SizedBox(height: 12),
          _buildDarkTextField(_resourceKeysController, 'Ресурс ключей', Icons.key, false),
          const SizedBox(height: 24),

          // Кнопка сохранения
          _buildGradientButton(
            icon: _isLoading ? null : Icons.save_alt,
            label: _isLoading ? 'Сохранение...' : 'Сохранить образец',
            gradient: _imageBase64 == null || _isLoading || _isParsing
                ? [Colors.grey.shade600, Colors.grey.shade700]
                : _greenGradient,
            onTap: _isLoading || _isParsing || _imageBase64 == null ? null : _saveSample,
            isLoading: _isLoading,
            height: 56,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
    required List<Color> gradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: gradient[0].withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Нет шаблонов. Создайте шаблон во вкладке "Шаблоны".',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientButton({
    IconData? icon,
    required String label,
    required List<Color> gradient,
    VoidCallback? onTap,
    bool isLoading = false,
    double height = 50,
  }) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(12),
        boxShadow: onTap != null
            ? [
                BoxShadow(
                  color: gradient[0].withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else if (icon != null)
                  Icon(icon, color: Colors.white, size: 20),
                if (icon != null || isLoading) const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: onTap != null ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDarkTextField(
      TextEditingController controller, String label, IconData icon, bool isMoney) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: isMoney
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isMoney ? _purpleGradient : [Colors.blueGrey, Colors.blueGrey.shade700],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          suffixText: isMoney ? '₽' : null,
          suffixStyle: TextStyle(
            color: _purpleGradient[1],
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildResultCard(ZReportParseResult result) {
    final isSuccess = result.success;
    final gradient = isSuccess ? _greenGradient : [Colors.red, Colors.red.shade300];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: gradient[0].withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradient),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isSuccess ? Icons.check_circle : Icons.error_outline,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSuccess ? 'Текст распознан' : 'Ошибка распознавания',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                    if (isSuccess && _selectedTemplate != null)
                      Text(
                        'Шаблон: ${_selectedTemplate!.name}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (result.error != null) ...[
            const SizedBox(height: 10),
            Text(
              result.error!,
              style: TextStyle(color: Colors.red.shade300),
            ),
          ],
          if (result.data != null) ...[
            const SizedBox(height: 12),
            _buildConfidenceInfo(result.data!),
          ],
        ],
      ),
    );
  }

  Widget _buildConfidenceInfo(ZReportData data) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
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
              color: Colors.white.withOpacity(0.7),
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
    final color = isFound ? (isHigh ? _greenGradient[0] : Colors.orange) : Colors.grey;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              isFound ? (isHigh ? Icons.check : Icons.help_outline) : Icons.close,
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          ),
          Text(
            value != null
                ? (isMoney ? '${value.toStringAsFixed(2)} ₽' : value.toStringAsFixed(0))
                : '—',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isFound ? color : Colors.white.withOpacity(0.4),
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

  static const _purpleGradient = [Color(0xFF6366F1), Color(0xFF8B5CF6)];

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
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Удалить шаблон?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Шаблон "${template.name}" будет удалён.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
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
      return Center(
        child: CircularProgressIndicator(color: _purpleGradient[0]),
      );
    }

    return Column(
      children: [
        // Кнопка создания
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: _purpleGradient),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _purpleGradient[0].withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (context) => const TemplateEditorPage()),
                  );
                  if (result == true) _loadTemplates();
                },
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Создать шаблон',
                        style: TextStyle(
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
        ),

        // Инструкция
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.amber.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.lightbulb_outline, color: Colors.amber, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Создайте шаблон для кассы, выделив области где находятся нужные данные.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Список
        Expanded(
          child: _templates.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.grid_view,
                          size: 40,
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Шаблонов пока нет',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTemplates,
                  color: _purpleGradient[0],
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _templates.length,
                    itemBuilder: (context, index) {
                      final template = _templates[index];
                      return _buildTemplateCard(template);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildTemplateCard(ZReportTemplate template) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final result = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (context) => TemplateEditorPage(existingTemplate: template),
              ),
            );
            if (result == true) _loadTemplates();
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: _purpleGradient),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      template.cashRegisterType?.substring(0, 1) ?? '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (template.cashRegisterType != null)
                        Text(
                          'Касса: ${template.cashRegisterType}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildStatChip(
                            '${template.usageCount}',
                            Icons.analytics,
                            Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          _buildStatChip(
                            '${(template.successRate * 100).toStringAsFixed(0)}%',
                            Icons.check_circle,
                            Colors.green,
                          ),
                          const SizedBox(width: 8),
                          _buildStatChip(
                            '${template.regions.length}',
                            Icons.grid_view,
                            Colors.purple,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _deleteTemplate(template),
                  icon: Icon(
                    Icons.delete_outline,
                    color: Colors.red.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
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

  static const _purpleGradient = [Color(0xFF6366F1), Color(0xFF8B5CF6)];
  static const _greenGradient = [Color(0xFF10B981), Color(0xFF34D399)];
  static const _blueGradient = [Color(0xFF3B82F6), Color(0xFF60A5FA)];

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
      return Center(
        child: CircularProgressIndicator(color: _purpleGradient[0]),
      );
    }

    final totalSamples = _stats['totalSamples'] ?? 0;
    final totalTemplates = _stats['totalTemplates'] ?? 0;
    final avgSuccessRate = (_stats['avgSuccessRate'] ?? 0).toDouble();
    final corrections = _stats['correctionsByField'] as Map<String, dynamic>? ?? {};

    return RefreshIndicator(
      onRefresh: _loadStats,
      color: _purpleGradient[0],
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
                    _blueGradient,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Шаблонов',
                    totalTemplates.toString(),
                    Icons.grid_view,
                    _greenGradient,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              'Средняя точность',
              '${(avgSuccessRate * 100).toStringAsFixed(1)}%',
              Icons.analytics,
              _purpleGradient,
            ),
            const SizedBox(height: 24),

            // Исправления по полям
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.edit_note, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Исправления по полям',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Поля, требующие корректировки',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
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

            // Подсказка
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _greenGradient[0].withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: _greenGradient),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.lightbulb_outline, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Чем больше образцов с исправлениями — тем точнее будет распознавание.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.6),
                        height: 1.3,
                      ),
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

  Widget _buildStatCard(String label, String value, IconData icon, List<Color> gradient) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: gradient[0].withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: gradient[0].withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, size: 28, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: gradient[1],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.5),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorrectionBar(String label, int count, int total) {
    final percent = total > 0 ? count / total : 0.0;
    final color = percent > 0.5
        ? Colors.red
        : (percent > 0.2 ? Colors.orange : _greenGradient[0]);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
          width: 1,
        ),
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
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
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
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

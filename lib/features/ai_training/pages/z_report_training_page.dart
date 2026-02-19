import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:image_picker/image_picker.dart';
import '../services/z_report_service.dart';
import '../../employees/services/user_role_service.dart';
import '../services/z_report_template_service.dart';
import '../models/z_report_sample_model.dart';
import '../models/z_report_template_model.dart';
import 'template_editor_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  static final _purpleGradient = [AppColors.indigo, AppColors.purple];

  /// Количество вкладок зависит от роли: админ видит 3 вкладки, остальные - 2
  int get _tabCount => _isAdmin ? 3 : 2;

  @override
  void initState() {
    super.initState();
    _initTabController();
  }

  Future<void> _initTabController() async {
    final roleData = await UserRoleService.loadUserRole();
    final role = roleData?.role ?? '';

    if (mounted) {
      setState(() {
        _isAdmin = role == 'admin' || role == 'developer';
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.darkNavy,
              AppColors.navy,
              AppColors.deepBlue,
            ],
          ),
        ),
        child: SafeArea(
          child: !_isInitialized || _tabController == null
              ? Center(
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
                          _TrainingSampleTab(),
                          if (_isAdmin) _TemplatesTab(),
                          _StatsTab(),
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
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Обучение Z-отчётов',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    if (_tabController == null) {
      return SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LinearGradient(colors: _purpleGradient),
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: _purpleGradient[0].withOpacity(0.4),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: EdgeInsets.all(4.w),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withOpacity(0.5),
        labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.sp),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 13.sp),
        dividerColor: Colors.transparent,
        tabs: [
          Tab(
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
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.grid_view, size: 18),
                  SizedBox(width: 6),
                  Text('Шаблоны'),
                ],
              ),
            ),
          Tab(
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
  _TrainingSampleTab();

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
  static final _purpleGradient = [AppColors.indigo, AppColors.purple];
  static final _greenGradient = [AppColors.emeraldGreen, AppColors.emeraldGreenLight];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    try {
      final templates = await ZReportTemplateService.getTemplates();
      if (mounted) {
        setState(() {
          _templates = templates;
          _isLoadingTemplates = false;
          if (templates.isNotEmpty) {
            _selectedTemplate = templates.first;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingTemplates = false);
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

      if (mounted) {
        setState(() {
          _parseResult = result;
          _isParsing = false;
        });
      }

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
      if (mounted) {
        setState(() {
          _isParsing = false;
          _parseResult = ZReportParseResult(success: false, error: 'Ошибка: $e');
        });
      }
    }
  }

  Future<void> _saveSample() async {
    if (_imageBase64 == null) {
      _showSnackBar('Сначала сфотографируйте Z-отчёт', AppColors.warning);
      return;
    }

    final totalSum = double.tryParse(_totalSumController.text);
    final cashSum = double.tryParse(_cashSumController.text);
    final ofdNotSent = int.tryParse(_ofdNotSentController.text);
    final resourceKeys = int.tryParse(_resourceKeysController.text);

    if (totalSum == null) {
      _showSnackBar('Введите корректную общую сумму', AppColors.warning);
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
        if (mounted) {
          setState(() {
            _selectedImage = null;
            _imageBase64 = null;
            _parseResult = null;
          });
        }
        _totalSumController.clear();
        _cashSumController.clear();
        _ofdNotSentController.clear();
        _resourceKeysController.clear();
      } else {
        _showSnackBar('Ошибка сохранения образца', AppColors.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == AppColors.error ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
            ),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        margin: EdgeInsets.all(16.w),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
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
          SizedBox(height: 16),

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
                fontSize: 15.sp,
              ),
            ),
            SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: DropdownButtonFormField<ZReportTemplate>(
                value: _selectedTemplate,
                dropdownColor: AppColors.darkNavy,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  prefixIcon: Container(
                    margin: EdgeInsets.all(8.w),
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: _purpleGradient),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(Icons.grid_view, color: Colors.white, size: 18),
                  ),
                ),
                style: TextStyle(color: Colors.white),
                items: _templates.map((template) {
                  return DropdownMenuItem(
                    value: template,
                    child: Text(
                      '${template.name} (${template.regions.length} обл.)',
                      style: TextStyle(color: Colors.white),
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
            SizedBox(height: 16),
          ] else
            _buildWarningCard(),
          SizedBox(height: 16),

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
              SizedBox(width: 12),
              Expanded(
                child: _buildGradientButton(
                  icon: Icons.photo_library,
                  label: 'Галерея',
                  gradient: [AppColors.info, AppColors.infoLight],
                  onTap: _isLoading || _isParsing
                      ? null
                      : () => _pickImage(ImageSource.gallery),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),

          // Превью
          if (_selectedImage != null) ...[
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16.r),
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
                            SizedBox(height: 16),
                            Text(
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
            SizedBox(height: 16),
          ],

          // Результат
          if (_parseResult != null) ...[
            _buildResultCard(_parseResult!),
            SizedBox(height: 16),
          ],

          // Форма
          Text(
            'Проверьте и исправьте данные',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          SizedBox(height: 12),

          _buildDarkTextField(_totalSumController, 'Общая сумма *', Icons.currency_ruble, true),
          SizedBox(height: 12),
          _buildDarkTextField(_cashSumController, 'Сумма наличных', Icons.payments_outlined, true),
          SizedBox(height: 12),
          _buildDarkTextField(_ofdNotSentController, 'Не передано в ОФД', Icons.cloud_off, false),
          SizedBox(height: 12),
          _buildDarkTextField(_resourceKeysController, 'Ресурс ключей', Icons.key, false),
          SizedBox(height: 24),

          // Кнопка сохранения
          _buildGradientButton(
            icon: _isLoading ? null : Icons.save_alt,
            label: _isLoading ? 'Сохранение...' : 'Сохранить образец',
            gradient: _imageBase64 == null || _isLoading || _isParsing
                ? [const Color(0xFF757575), const Color(0xFF616161)]
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
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16.r),
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
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12.sp,
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
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: AppColors.warning.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(Icons.warning_amber, color: AppColors.warning, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Нет шаблонов. Создайте шаблон во вкладке "Шаблоны".',
              style: TextStyle(
                fontSize: 12.sp,
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
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: onTap != null
            ? [
                BoxShadow(
                  color: gradient[0].withOpacity(0.4),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12.r),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else if (icon != null)
                  Icon(icon, color: Colors.white, size: 20),
                if (icon != null || isLoading) SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: onTap != null ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 15.sp,
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
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: isMoney
            ? TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        style: TextStyle(
          fontSize: 16.sp,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
          prefixIcon: Container(
            margin: EdgeInsets.all(8.w),
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isMoney ? _purpleGradient : [Colors.blueGrey, Colors.blueGrey.shade700],
              ),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          suffixText: isMoney ? 'руб' : null,
          suffixStyle: TextStyle(
            color: _purpleGradient[1],
            fontWeight: FontWeight.bold,
            fontSize: 16.sp,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        ),
      ),
    );
  }

  Widget _buildResultCard(ZReportParseResult result) {
    final isSuccess = result.success;
    final gradient = isSuccess ? _greenGradient : [AppColors.error, AppColors.errorLight];

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16.r),
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
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradient),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  isSuccess ? Icons.check_circle : Icons.error_outline,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSuccess ? 'Текст распознан' : 'Ошибка распознавания',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15.sp,
                        color: Colors.white,
                      ),
                    ),
                    if (isSuccess && _selectedTemplate != null)
                      Text(
                        'Шаблон: ${_selectedTemplate!.name}',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (result.error != null) ...[
            SizedBox(height: 10),
            Text(
              result.error!,
              style: TextStyle(color: AppColors.errorLight),
            ),
          ],
          if (result.data != null) ...[
            SizedBox(height: 12),
            _buildConfidenceInfo(result.data!),
          ],
        ],
      ),
    );
  }

  Widget _buildConfidenceInfo(ZReportData data) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Распознанные значения:',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          SizedBox(height: 8),
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
    final color = isFound ? (isHigh ? _greenGradient[0] : AppColors.warning) : AppColors.neutral;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(4.w),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4.r),
            ),
            child: Icon(
              isFound ? (isHigh ? Icons.check : Icons.help_outline) : Icons.close,
              size: 14,
              color: color,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          ),
          Text(
            value != null
                ? (isMoney ? '${value.toStringAsFixed(2)} руб' : value.toStringAsFixed(0))
                : '—',
            style: TextStyle(
              fontSize: 14.sp,
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
  _TemplatesTab();

  @override
  State<_TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends State<_TemplatesTab> {
  List<ZReportTemplate> _templates = [];
  bool _isLoading = true;

  static final _purpleGradient = [AppColors.indigo, AppColors.purple];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    try {
      final templates = await ZReportTemplateService.getTemplates();
      if (mounted) {
        setState(() {
          _templates = templates;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteTemplate(ZReportTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Удалить шаблон?', style: TextStyle(color: Colors.white)),
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
            child: Text('Удалить', style: TextStyle(color: AppColors.error)),
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
          padding: EdgeInsets.all(16.w),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: _purpleGradient),
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: _purpleGradient[0].withOpacity(0.4),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (context) => TemplateEditorPage()),
                  );
                  if (result == true) _loadTemplates();
                },
                borderRadius: BorderRadius.circular(12.r),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 14.h),
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
                          fontSize: 16.sp,
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
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: AppColors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                color: AppColors.amber.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(Icons.lightbulb_outline, color: AppColors.amber, size: 20),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Создайте шаблон для кассы, выделив области где находятся нужные данные.',
                    style: TextStyle(
                      fontSize: 12.sp,
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
                      SizedBox(height: 16),
                      Text(
                        'Шаблонов пока нет',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 16.sp,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTemplates,
                  color: _purpleGradient[0],
                  child: ListView.builder(
                    padding: EdgeInsets.all(16.w),
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
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16.r),
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
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _purpleGradient),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Center(
                    child: Text(
                      template.cashRegisterType?.substring(0, 1) ?? '?',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20.sp,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      if (template.cashRegisterType != null)
                        Text(
                          'Касса: ${template.cashRegisterType}',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          _buildStatChip(
                            '${template.usageCount}',
                            Icons.analytics,
                            AppColors.info,
                          ),
                          SizedBox(width: 8),
                          _buildStatChip(
                            '${(template.successRate * 100).toStringAsFixed(0)}%',
                            Icons.check_circle,
                            AppColors.success,
                          ),
                          SizedBox(width: 8),
                          _buildStatChip(
                            '${template.regions.length}',
                            Icons.grid_view,
                            AppColors.purple,
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
                    color: AppColors.error.withOpacity(0.7),
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
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.sp,
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
  _StatsTab();

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  static final _purpleGradient = [AppColors.indigo, AppColors.purple];
  static final _greenGradient = [AppColors.emeraldGreen, AppColors.emeraldGreenLight];
  static final _blueGradient = [AppColors.info, AppColors.infoLight];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final stats = await ZReportTemplateService.getTrainingStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16.w),
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
                SizedBox(width: 12),
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
            SizedBox(height: 12),
            _buildStatCard(
              'Средняя точность',
              '${(avgSuccessRate * 100).toStringAsFixed(1)}%',
              Icons.analytics,
              _purpleGradient,
            ),
            SizedBox(height: 24),

            // Исправления по полям
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.warning, AppColors.warningLight],
                    ),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(Icons.edit_note, color: Colors.white, size: 20),
                ),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Исправления по полям',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Поля, требующие корректировки',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 16),

            _buildCorrectionBar('Общая сумма', corrections['totalSum'] ?? 0, totalSamples),
            SizedBox(height: 8),
            _buildCorrectionBar('Наличные', corrections['cashSum'] ?? 0, totalSamples),
            SizedBox(height: 8),
            _buildCorrectionBar('Не передано в ОФД', corrections['ofdNotSent'] ?? 0, totalSamples),
            SizedBox(height: 8),
            _buildCorrectionBar('Ресурс ключей', corrections['resourceKeys'] ?? 0, totalSamples),

            SizedBox(height: 24),

            // Подсказка
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(16.r),
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
                      gradient: LinearGradient(colors: _greenGradient),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(Icons.lightbulb_outline, color: Colors.white, size: 22),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Чем больше образцов с исправлениями — тем точнее будет распознавание.',
                      style: TextStyle(
                        fontSize: 13.sp,
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
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: gradient[0].withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(14.r),
              boxShadow: [
                BoxShadow(
                  color: gradient[0].withOpacity(0.4),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, size: 28, color: Colors.white),
          ),
          SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 28.sp,
              fontWeight: FontWeight.bold,
              color: gradient[1],
            ),
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
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
        ? AppColors.error
        : (percent > 0.2 ? AppColors.warning : _greenGradient[0]);

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12.r),
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
                      borderRadius: BorderRadius.circular(5.r),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
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

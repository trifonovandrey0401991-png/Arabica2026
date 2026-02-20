import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import 'package:image_picker/image_picker.dart';
import '../services/z_report_service.dart';
import '../../employees/models/user_role_model.dart';
import '../../employees/services/user_role_service.dart';
import '../../shops/services/shop_service.dart';
import '../../shops/models/shop_model.dart';
import '../services/z_report_template_service.dart';
import '../models/z_report_sample_model.dart';
import '../models/z_report_template_model.dart';
import '../widgets/z_report_recognition_dialog.dart';
import '../widgets/z_report_region_overlay.dart';
import '../widgets/z_report_region_selector.dart';
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

  /// Количество вкладок: админ видит 3 (Обучить, Фото, Стат), остальные - 2
  int get _tabCount => _isAdmin ? 3 : 2;

  @override
  void initState() {
    super.initState();
    _initTabController();
  }

  Future<void> _initTabController() async {
    final roleData = await UserRoleService.loadUserRole();
    final role = roleData?.role;

    if (mounted) {
      setState(() {
        _isAdmin = role == UserRole.admin || role == UserRole.developer;
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
                          if (_isAdmin) _PhotosTab(),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_a_photo, size: 16),
                SizedBox(width: 4),
                Text('Обучить'),
              ],
            ),
          ),
          if (_isAdmin)
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library, size: 16),
                  SizedBox(width: 4),
                  Text('Фото'),
                ],
              ),
            ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.analytics, size: 16),
                SizedBox(width: 4),
                Text('Статистика'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== Вкладка обучения (пошаговый flow) ====================

/// Шаги обучения
enum _TrainingStep {
  selectShop,
  photo,
  recognizing,
  confirm,
  drawRegions,
  reRecognizing,
  confirm2,
  manualInput,
  saving,
  done,
}

class _TrainingSampleTab extends StatefulWidget {
  @override
  State<_TrainingSampleTab> createState() => _TrainingSampleTabState();
}

class _TrainingSampleTabState extends State<_TrainingSampleTab> {
  _TrainingStep _step = _TrainingStep.selectShop;
  bool _dialogShown = false; // Защита от множественных диалогов при rebuild

  // Данные по шагам
  List<Shop> _shops = [];
  bool _isLoadingShops = true;
  Shop? _selectedShop;
  String? _imageBase64;
  ZReportParseResult? _parseResult;
  Map<String, Map<String, double>>? _fieldRegions;

  static final _purpleGradient = [AppColors.indigo, AppColors.purple];
  static final _greenGradient = [AppColors.emeraldGreen, AppColors.emeraldGreenLight];

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    try {
      final shops = await ShopService.getShops();
      if (mounted) {
        setState(() {
          _shops = shops;
          _isLoadingShops = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingShops = false);
    }
  }

  void _reset() {
    if (mounted) {
      setState(() {
        _step = _TrainingStep.selectShop;
        _selectedShop = null;
        _imageBase64 = null;
        _parseResult = null;
        _fieldRegions = null;
      });
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final bytes = await File(picked.path).readAsBytes();
    final compressedBase64 = await ZReportService.compressImage(bytes);

    if (mounted) {
      setState(() {
        _imageBase64 = compressedBase64;
        _step = _TrainingStep.recognizing;
      });
    }

    await _runOCR();
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final bytes = await File(picked.path).readAsBytes();
    final compressedBase64 = await ZReportService.compressImage(bytes);

    if (mounted) {
      setState(() {
        _imageBase64 = compressedBase64;
        _step = _TrainingStep.recognizing;
      });
    }

    await _runOCR();
  }

  Future<void> _runOCR({Map<String, Map<String, double>>? explicitRegions}) async {
    if (_imageBase64 == null) return;

    try {
      final result = await ZReportService.parseZReport(
        _imageBase64!,
        shopAddress: _selectedShop?.address,
        explicitRegions: explicitRegions,
      );

      if (!mounted) return;

      final hasData = result.success &&
          result.data != null &&
          (result.data!.totalSum != null || result.data!.cashSum != null);

      if (hasData) {
        // OCR распознал — показываем подтверждение
        setState(() {
          _parseResult = result;
          _step = _fieldRegions == null
              ? _TrainingStep.confirm
              : _TrainingStep.confirm2;
        });
      } else {
        // OCR не распознал — сразу ручной ввод
        setState(() {
          _parseResult = result;
          _step = _TrainingStep.manualInput;
        });
        _showManualInput(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _step = _TrainingStep.photo);
        _showSnackBar('Ошибка распознавания: $e', AppColors.error);
      }
    }
  }

  Future<void> _showConfirmDialog() async {
    if (_parseResult?.data == null) return;

    final confirmed = await ZReportConfirmDialog.show(
      context,
      data: _parseResult!.data!,
      expectedRanges: _parseResult!.expectedRanges,
    );
    if (!mounted) return;

    if (confirmed == true) {
      // Пользователь подтвердил — сохраняем
      await _saveSample(
        totalSum: _parseResult!.data!.totalSum ?? 0,
        cashSum: _parseResult!.data!.cashSum ?? 0,
        ofdNotSent: _parseResult!.data!.ofdNotSent ?? 0,
        resourceKeys: _parseResult!.data!.resourceKeys ?? 0,
      );
    } else if (confirmed == false) {
      if (_fieldRegions == null) {
        // Первый раз — рисуем регионы
        if (mounted) setState(() => _step = _TrainingStep.drawRegions);
        _showRegionSelector();
      } else {
        // Второй раз — ручной ввод
        if (mounted) setState(() => _step = _TrainingStep.manualInput);
        _showManualInput(_parseResult);
      }
    }
  }

  Future<void> _showRegionSelector() async {
    if (_imageBase64 == null) return;

    final regions = await ZReportRegionSelector.show(
      context,
      imageBase64: _imageBase64!,
    );
    if (regions == null || !mounted) {
      if (mounted) setState(() => _step = _TrainingStep.photo);
      return;
    }

    setState(() {
      _fieldRegions = regions;
      _step = _TrainingStep.reRecognizing;
    });

    await _runOCR(explicitRegions: regions);
  }

  Future<void> _showManualInput(ZReportParseResult? result) async {
    if (_imageBase64 == null) return;

    final manualResult = await ZReportRecognitionDialog.show(
      context,
      imageBase64: _imageBase64!,
      recognizedData: result?.data,
      shopAddress: _selectedShop?.address,
      expectedRanges: result?.expectedRanges,
      isSecondAttempt: true,
      secondAttemptFailed: true,
    );

    if (manualResult != null && mounted) {
      await _saveSample(
        totalSum: manualResult.revenue,
        cashSum: manualResult.cash,
        ofdNotSent: manualResult.ofdNotSent,
        resourceKeys: manualResult.resourceKeys,
      );
    } else if (mounted) {
      setState(() => _step = _TrainingStep.photo);
    }
  }

  Future<void> _saveSample({
    required double totalSum,
    required double cashSum,
    required int ofdNotSent,
    required int resourceKeys,
  }) async {
    if (_imageBase64 == null) return;

    if (mounted) setState(() => _step = _TrainingStep.saving);

    try {
      await ZReportService.saveSample(
        imageBase64: _imageBase64!,
        totalSum: totalSum,
        cashSum: cashSum,
        ofdNotSent: ofdNotSent,
        resourceKeys: resourceKeys,
        shopAddress: _selectedShop?.address,
        fieldRegions: _fieldRegions,
      );

      if (mounted) {
        setState(() => _step = _TrainingStep.done);
        _showSnackBar('Образец сохранён для обучения', _greenGradient[0]);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Ошибка сохранения: $e', AppColors.error);
        setState(() => _step = _TrainingStep.photo);
      }
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
          // Прогресс-бар
          _buildProgressBar(),
          SizedBox(height: 20),

          // Содержимое шага
          _buildStepContent(),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final steps = ['Магазин', 'Фото', 'ИИ', 'Готово'];
    int activeIndex;
    switch (_step) {
      case _TrainingStep.selectShop:
        activeIndex = 0;
        break;
      case _TrainingStep.photo:
        activeIndex = 1;
        break;
      case _TrainingStep.recognizing:
      case _TrainingStep.confirm:
      case _TrainingStep.drawRegions:
      case _TrainingStep.reRecognizing:
      case _TrainingStep.confirm2:
      case _TrainingStep.manualInput:
      case _TrainingStep.saving:
        activeIndex = 2;
        break;
      case _TrainingStep.done:
        activeIndex = 3;
        break;
    }

    return Row(
      children: List.generate(steps.length, (i) {
        final isActive = i <= activeIndex;
        final isCurrent = i == activeIndex;

        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  if (i > 0)
                    Expanded(
                      child: Container(
                        height: 3,
                        color: isActive
                            ? _purpleGradient[0]
                            : Colors.white.withOpacity(0.1),
                      ),
                    ),
                  Container(
                    width: isCurrent ? 32 : 24,
                    height: isCurrent ? 32 : 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isActive
                          ? LinearGradient(colors: _purpleGradient)
                          : null,
                      color: isActive ? null : Colors.white.withOpacity(0.1),
                      boxShadow: isCurrent
                          ? [BoxShadow(color: _purpleGradient[0].withOpacity(0.4), blurRadius: 8)]
                          : null,
                    ),
                    child: Center(
                      child: i < activeIndex
                          ? Icon(Icons.check, color: Colors.white, size: 14)
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: isActive ? Colors.white : Colors.white38,
                                fontSize: 11.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  if (i < steps.length - 1)
                    Expanded(
                      child: Container(
                        height: 3,
                        color: i < activeIndex
                            ? _purpleGradient[0]
                            : Colors.white.withOpacity(0.1),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 6),
              Text(
                steps[i],
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white38,
                  fontSize: 11.sp,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case _TrainingStep.selectShop:
        return _buildSelectShopStep();
      case _TrainingStep.photo:
        return _buildPhotoStep();
      case _TrainingStep.recognizing:
      case _TrainingStep.reRecognizing:
        return _buildRecognizingStep();
      case _TrainingStep.confirm:
      case _TrainingStep.confirm2:
        return _buildConfirmStep();
      case _TrainingStep.drawRegions:
        return _buildDrawRegionsStep();
      case _TrainingStep.manualInput:
        return _buildManualInputStep();
      case _TrainingStep.saving:
        return _buildSavingStep();
      case _TrainingStep.done:
        return _buildDoneStep();
    }
  }

  Widget _buildSelectShopStep() {
    if (_isLoadingShops) {
      return Center(child: CircularProgressIndicator(color: _purpleGradient[0]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Инструкция
        _buildInfoCard(
          icon: Icons.store,
          title: 'Выберите магазин',
          description: 'ИИ будет использовать данные этого магазина для лучшего распознавания.',
        ),
        SizedBox(height: 16),

        // Список магазинов
        ..._shops.map((shop) => Padding(
          padding: EdgeInsets.only(bottom: 8.h),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (mounted) {
                    setState(() {
                      _selectedShop = shop;
                      _step = _TrainingStep.photo;
                    });
                  }
                },
                borderRadius: BorderRadius.circular(12.r),
                child: Padding(
                  padding: EdgeInsets.all(14.w),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: _purpleGradient),
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Icon(Icons.store, color: Colors.white, size: 20),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shop.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14.sp,
                              ),
                            ),
                            Text(
                              shop.address,
                              style: TextStyle(color: Colors.white54, fontSize: 12.sp),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.white38),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildPhotoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Выбранный магазин
        _buildSelectedShopChip(),
        SizedBox(height: 16),

        _buildInfoCard(
          icon: Icons.camera_alt,
          title: 'Сфотографируйте Z-отчёт',
          description: 'Сделайте чёткое фото Z-отчёта кассового аппарата.',
        ),
        SizedBox(height: 24),

        _buildGradientButton(
          icon: Icons.camera_alt,
          label: 'Камера',
          gradient: _purpleGradient,
          onTap: _pickPhoto,
        ),
        SizedBox(height: 12),
        _buildGradientButton(
          icon: Icons.photo_library,
          label: 'Галерея',
          gradient: [AppColors.info, AppColors.infoLight],
          onTap: _pickFromGallery,
        ),
      ],
    );
  }

  Widget _buildRecognizingStep() {
    return Column(
      children: [
        _buildSelectedShopChip(),
        SizedBox(height: 40),
        CircularProgressIndicator(color: _purpleGradient[0]),
        SizedBox(height: 20),
        Text(
          _step == _TrainingStep.reRecognizing
              ? 'Повторное распознавание...'
              : 'Распознавание Z-отчёта...',
          style: TextStyle(color: Colors.white, fontSize: 16.sp),
        ),
        SizedBox(height: 8),
        Text(
          'Подождите, ИИ анализирует фото',
          style: TextStyle(color: Colors.white54, fontSize: 13.sp),
        ),
      ],
    );
  }

  Widget _buildConfirmStep() {
    // Автоматически показываем диалог (с защитой от повторного вызова при rebuild)
    if (!_dialogShown) {
      _dialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (_step == _TrainingStep.confirm || _step == _TrainingStep.confirm2)) {
          _showConfirmDialog();
        }
        _dialogShown = false;
      });
    }

    return Column(
      children: [
        _buildSelectedShopChip(),
        SizedBox(height: 40),
        CircularProgressIndicator(color: _purpleGradient[0]),
        SizedBox(height: 20),
        Text('Проверка данных...', style: TextStyle(color: Colors.white, fontSize: 16.sp)),
      ],
    );
  }

  Widget _buildDrawRegionsStep() {
    // Автоматически показываем region selector (с защитой от повторного вызова)
    if (!_dialogShown) {
      _dialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _step == _TrainingStep.drawRegions) {
          _showRegionSelector();
        }
        _dialogShown = false;
      });
    }

    return Column(
      children: [
        _buildSelectedShopChip(),
        SizedBox(height: 40),
        CircularProgressIndicator(color: _purpleGradient[0]),
        SizedBox(height: 20),
        Text('Выделение областей...', style: TextStyle(color: Colors.white, fontSize: 16.sp)),
      ],
    );
  }

  Widget _buildManualInputStep() {
    return Column(
      children: [
        _buildSelectedShopChip(),
        SizedBox(height: 40),
        CircularProgressIndicator(color: _purpleGradient[0]),
        SizedBox(height: 20),
        Text('Ручной ввод...', style: TextStyle(color: Colors.white, fontSize: 16.sp)),
      ],
    );
  }

  Widget _buildSavingStep() {
    return Column(
      children: [
        SizedBox(height: 40),
        CircularProgressIndicator(color: _greenGradient[0]),
        SizedBox(height: 20),
        Text('Сохранение образца...', style: TextStyle(color: Colors.white, fontSize: 16.sp)),
      ],
    );
  }

  Widget _buildDoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 20),
        Container(
          padding: EdgeInsets.all(32.w),
          decoration: BoxDecoration(
            color: _greenGradient[0].withOpacity(0.1),
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: _greenGradient[0].withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: _greenGradient),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check, color: Colors.white, size: 36),
              ),
              SizedBox(height: 16),
              Text(
                'Образец сохранён!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'ИИ стал умнее для магазина "${_selectedShop?.name ?? ""}"',
                style: TextStyle(color: Colors.white60, fontSize: 14.sp),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        SizedBox(height: 24),
        _buildGradientButton(
          icon: Icons.add_a_photo,
          label: 'Обучить ещё',
          gradient: _purpleGradient,
          onTap: _reset,
        ),
      ],
    );
  }

  Widget _buildSelectedShopChip() {
    if (_selectedShop == null) return SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: _purpleGradient[0].withOpacity(0.15),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: _purpleGradient[0].withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.store, color: _purpleGradient[1], size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedShop!.address,
              style: TextStyle(color: Colors.white, fontSize: 13.sp),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_step == _TrainingStep.photo)
            GestureDetector(
              onTap: () {
                if (mounted) setState(() => _step = _TrainingStep.selectShop);
              },
              child: Icon(Icons.edit, color: Colors.white38, size: 16),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: _purpleGradient[0].withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: _purpleGradient),
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
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5), height: 1.3),
                ),
              ],
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
  }) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: onTap != null
            ? [BoxShadow(color: gradient[0].withOpacity(0.4), blurRadius: 12, offset: Offset(0, 4))]
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
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15.sp),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== Вкладка Фото (training samples по магазинам) ====================

class _PhotosTab extends StatefulWidget {
  @override
  State<_PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends State<_PhotosTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _shops = [];

  // Детальный просмотр магазина
  String? _selectedShopId;
  List<Map<String, dynamic>> _shopSamples = [];
  bool _isLoadingShopSamples = false;

  static final _purpleGradient = [AppColors.indigo, AppColors.purple];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      // Загружаем статистику и все семплы параллельно
      final futures = await Future.wait([
        ZReportTemplateService.getTrainingSamples(),
        _loadIntelligenceStats(),
      ]);

      final samples = futures[0];
      final shopStats = futures[1];

      // Группируем семплы по магазинам
      final samplesByShop = <String, int>{};
      for (final s in samples) {
        final shopId = (s['shopId'] ?? 'Без магазина').toString();
        samplesByShop[shopId] = (samplesByShop[shopId] ?? 0) + 1;
      }

      // Объединяем с accuracy из intelligence
      final mergedShops = <Map<String, dynamic>>[];
      final processedShops = <String>{};

      for (final stat in shopStats) {
        final addr = stat['shopAddress'] as String? ?? '';
        if (addr.isEmpty) continue;
        processedShops.add(addr);

        final accuracy = stat['accuracy'] as Map<String, dynamic>? ?? {};
        final totalReports = stat['totalReports'] ?? 0;

        // Средняя точность по полям
        int totalChecks = 0;
        int correctChecks = 0;
        for (final field in accuracy.values) {
          if (field is Map) {
            totalChecks += (field['total'] ?? 0) as int;
            correctChecks += (field['correct'] ?? 0) as int;
          }
        }
        final avgAccuracy = totalChecks > 0 ? correctChecks / totalChecks : 0.0;

        mergedShops.add({
          'shopAddress': addr,
          'photoCount': samplesByShop[addr] ?? 0,
          'totalReports': totalReports,
          'accuracy': avgAccuracy,
          'hasLearnedRegions': stat['hasLearnedRegions'] ?? false,
        });
      }

      // Добавляем магазины из семплов, которых нет в intelligence
      for (final entry in samplesByShop.entries) {
        if (!processedShops.contains(entry.key)) {
          mergedShops.add({
            'shopAddress': entry.key,
            'photoCount': entry.value,
            'totalReports': 0,
            'accuracy': 0.0,
            'hasLearnedRegions': false,
          });
        }
      }

      // Сортируем: больше фото — выше
      mergedShops.sort((a, b) => (b['photoCount'] as int).compareTo(a['photoCount'] as int));

      if (mounted) {
        setState(() {
          _shops = mergedShops;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadIntelligenceStats() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/intelligence/stats'),
        headers: ApiConstants.headersWithApiKey,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['shops'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  Future<void> _openShop(String shopAddress) async {
    if (mounted) {
      setState(() {
        _selectedShopId = shopAddress;
        _isLoadingShopSamples = true;
      });
    }
    try {
      final samples = await ZReportTemplateService.getTrainingSamples(shopId: shopAddress);
      if (mounted) {
        setState(() {
          _shopSamples = samples;
          _isLoadingShopSamples = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingShopSamples = false);
    }
  }

  Future<void> _deleteSample(String sampleId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Удалить фото?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Фото будет удалено из обучающих данных.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Удалить', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await ZReportTemplateService.deleteTrainingSample(sampleId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Фото удалено'), backgroundColor: AppColors.success),
        );
        // Обновляем список фото магазина
        if (_selectedShopId != null) {
          _openShop(_selectedShopId!);
        }
        // Обновляем общие данные
        _loadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: _purpleGradient[0]));
    }

    // Если выбран магазин — показываем его фото
    if (_selectedShopId != null) {
      return _buildShopDetail();
    }

    // Список магазинов
    return _buildShopList();
  }

  Widget _buildShopList() {
    if (_shops.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 64, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              'Нет обучающих фото',
              style: TextStyle(color: Colors.white54, fontSize: 16.sp),
            ),
            SizedBox(height: 8),
            Text(
              'Сфотографируйте Z-отчёт во вкладке "Обучить"',
              style: TextStyle(color: Colors.white38, fontSize: 13.sp),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _purpleGradient[0],
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: _shops.length,
        itemBuilder: (context, index) {
          final shop = _shops[index];
          final accuracy = (shop['accuracy'] as double) * 100;
          final photoCount = shop['photoCount'] as int;
          final totalReports = shop['totalReports'] as int;

          Color accuracyColor;
          if (accuracy >= 80) {
            accuracyColor = AppColors.emeraldGreen;
          } else if (accuracy >= 50) {
            accuracyColor = AppColors.warning;
          } else {
            accuracyColor = AppColors.error;
          }

          return Container(
            margin: EdgeInsets.only(bottom: 12.h),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: photoCount > 0 ? () => _openShop(shop['shopAddress']) : null,
                borderRadius: BorderRadius.circular(16.r),
                child: Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Row(
                    children: [
                      // Accuracy circle
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: accuracyColor, width: 3),
                          color: accuracyColor.withOpacity(0.1),
                        ),
                        child: Center(
                          child: Text(
                            totalReports > 0
                                ? '${accuracy.toStringAsFixed(0)}%'
                                : '—',
                            style: TextStyle(
                              color: accuracyColor,
                              fontWeight: FontWeight.bold,
                              fontSize: totalReports > 0 ? 14.sp : 18.sp,
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
                              shop['shopAddress'],
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _buildChip(Icons.photo, '$photoCount фото', AppColors.info),
                                if (totalReports > 0)
                                  _buildChip(Icons.receipt, '$totalReports отчётов', Colors.white38),
                                if (shop['hasLearnedRegions'] == true)
                                  _buildChip(Icons.crop, 'Регионы', AppColors.emeraldGreen),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (photoCount > 0)
                        Icon(Icons.chevron_right, color: Colors.white38),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChip(IconData icon, String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11.sp, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildShopDetail() {
    return Column(
      children: [
        // Шапка с кнопкой назад
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  if (mounted) setState(() => _selectedShopId = null);
                },
                icon: Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
              ),
              Expanded(
                child: Text(
                  _selectedShopId ?? '',
                  style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${_shopSamples.length} фото',
                style: TextStyle(color: Colors.white54, fontSize: 13.sp),
              ),
            ],
          ),
        ),

        // Фото
        Expanded(
          child: _isLoadingShopSamples
              ? Center(child: CircularProgressIndicator(color: _purpleGradient[0]))
              : _shopSamples.isEmpty
                  ? Center(
                      child: Text('Нет фото', style: TextStyle(color: Colors.white54)),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(12.w),
                      itemCount: _shopSamples.length,
                      itemBuilder: (context, index) {
                        final sample = _shopSamples[index];
                        return _buildSampleCard(sample);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildSampleCard(Map<String, dynamic> sample) {
    final id = sample['id'] ?? '';
    final createdAt = sample['createdAt'] != null
        ? DateTime.tryParse(sample['createdAt'].toString())?.toLocal()
        : null;
    final correctedFields = List<String>.from(sample['correctedFields'] ?? []);
    final correctData = sample['correctData'] as Map<String, dynamic>? ?? {};
    final imageUrl = ZReportTemplateService.getTrainingSampleImageUrl(id);

    // Парсим fieldRegions для overlay
    final rawRegions = sample['fieldRegions'];
    Map<String, Map<String, double>>? fieldRegions;
    if (rawRegions is Map) {
      fieldRegions = {};
      for (final entry in rawRegions.entries) {
        if (entry.value is Map) {
          final region = <String, double>{};
          for (final re in (entry.value as Map).entries) {
            if (re.value is num) {
              region[re.key.toString()] = (re.value as num).toDouble();
            }
          }
          if (region.isNotEmpty) fieldRegions[entry.key.toString()] = region;
        }
      }
      if (fieldRegions.isEmpty) fieldRegions = null;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Фото с областями (fill — чтобы overlay совпадал с картинкой)
          ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    imageUrl,
                    fit: BoxFit.fill,
                    headers: ApiConstants.headersWithApiKey,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white.withOpacity(0.05),
                      child: Center(child: Icon(Icons.broken_image, color: Colors.white24, size: 48)),
                    ),
                  ),
                  if (fieldRegions != null)
                    ZReportRegionOverlay(fieldRegions: fieldRegions),
                ],
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.all(12.w),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (createdAt != null)
                        Text(
                          '${createdAt.day.toString().padLeft(2, '0')}.${createdAt.month.toString().padLeft(2, '0')}.${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(color: Colors.white54, fontSize: 12.sp),
                        ),
                      SizedBox(height: 4),
                      // Данные
                      if (correctData['totalSum'] != null)
                        Text(
                          'Выручка: ${correctData['totalSum']}  Наличные: ${correctData['cashSum'] ?? 0}',
                          style: TextStyle(color: Colors.white70, fontSize: 12.sp),
                        ),
                      if (correctedFields.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 4.h),
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 12, color: AppColors.warning),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Исправлено: ${correctedFields.join(", ")}',
                                  style: TextStyle(color: AppColors.warning, fontSize: 11.sp),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Кнопка удаления
                IconButton(
                  onPressed: () => _deleteSample(id),
                  icon: Icon(Icons.delete_outline, color: AppColors.error.withOpacity(0.7)),
                ),
              ],
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
    if (mounted) setState(() => _isLoading = true);
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
      if (mounted) _loadTemplates();
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
  bool _dataLoaded = false;

  static final _purpleGradient = [AppColors.indigo, AppColors.purple];
  static final _greenGradient = [AppColors.emeraldGreen, AppColors.emeraldGreenLight];
  static final _blueGradient = [AppColors.info, AppColors.infoLight];

  @override
  void initState() {
    super.initState();
    // Ленивая загрузка — данные грузятся при первом build
  }

  void _ensureDataLoaded() {
    if (!_dataLoaded) {
      _dataLoaded = true;
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    if (mounted) setState(() => _isLoading = true);
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
    _ensureDataLoaded();

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Исправления по полям',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Поля, требующие корректировки',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white.withOpacity(0.5),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
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
              Expanded(
                child: Row(
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
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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

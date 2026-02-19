import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;
import 'dart:typed_data';
import 'dart:io';
import '../models/recount_question_model.dart';
import '../services/recount_question_service.dart';
import 'recount_points_settings_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница с вкладками для управления пересчётом
/// Содержит вкладки: Товары и Настройка баллов
class RecountManagementTabsPage extends StatefulWidget {
  const RecountManagementTabsPage({super.key});

  @override
  State<RecountManagementTabsPage> createState() => _RecountManagementTabsPageState();
}

class _RecountManagementTabsPageState extends State<RecountManagementTabsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Для вкладки товаров
  List<RecountQuestion> _products = [];
  bool _isProductsLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadProducts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<RecountQuestion> get _filteredProducts {
    if (_searchQuery.isEmpty) return _products;
    final query = _searchQuery.toLowerCase();
    return _products.where((p) =>
      p.barcode.toLowerCase().contains(query) ||
      p.productName.toLowerCase().contains(query) ||
      p.productGroup.toLowerCase().contains(query)
    ).toList();
  }

  Future<void> _loadProducts() async {
    if (mounted) setState(() => _isProductsLoading = true);

    try {
      final products = await RecountQuestionService.getQuestions();
      if (!mounted) return;
      setState(() {
        _products = products;
        _isProductsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProductsLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки товаров', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }

  /// Показать диалог выбора режима загрузки
  Future<void> _showUploadModeDialog() async {
    final mode = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: AppColors.emeraldDark,
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Заголовок
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(20.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.emerald, AppColors.emeraldDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20.r),
                    topRight: Radius.circular(20.r),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10.w),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Icon(Icons.upload_file, color: AppColors.gold, size: 24),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Загрузка из Excel',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Формат: .xlsx',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(20.w),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Text(
                        'Столбец 1: Баркод\nСтолбец 2: Группа товара\nСтолбец 3: Наименование\nСтолбец 4: Грейд (1, 2 или 3)',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white.withOpacity(0.5),
                          height: 1.5,
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    // Кнопка "Заменить все"
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, 'replace'),
                        icon: Icon(Icons.refresh, size: 20),
                        label: Text('Заменить все'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[700],
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Удалить текущие и загрузить новые',
                      style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.4)),
                    ),
                    SizedBox(height: 14),
                    // Кнопка "Добавить новые"
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, 'add_new'),
                        icon: Icon(Icons.add, size: 20),
                        label: Text('Добавить новые'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: AppColors.night,
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Только товары с новыми баркодами',
                      style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.4)),
                    ),
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          side: BorderSide(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Text(
                          'Отмена',
                          style: TextStyle(color: Colors.white.withOpacity(0.7)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (mode != null) {
      _uploadFromExcel(mode);
    }
  }

  Future<void> _uploadFromExcel(String mode) async {
    try {
      FilePickerResult? pickerResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
      );

      if (pickerResult == null || pickerResult.files.single.path == null) {
        return;
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Container(
              padding: EdgeInsets.all(24.w),
              decoration: BoxDecoration(
                color: AppColors.emeraldDark,
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
              ),
            ),
          ),
        );
      }

      final file = pickerResult.files.single;
      Uint8List bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      } else {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось прочитать файл'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final fileName = file.name.toLowerCase();
      if (fileName.endsWith('.xls') && !fileName.endsWith('.xlsx')) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Формат .xls не поддерживается.\nСохраните файл в формате .xlsx'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      excel.Excel excelFile;
      try {
        excelFile = excel.Excel.decodeBytes(bytes);
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка чтения файла'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      if (excelFile.tables.isEmpty) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Excel файл не содержит листов'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final sheet = excelFile.tables[excelFile.tables.keys.first]!;
      final products = <Map<String, dynamic>>[];

      for (var rowIndex = 0; rowIndex < sheet.maxRows; rowIndex++) {
        final row = sheet.rows[rowIndex];
        if (row.isEmpty || row[0]?.value == null) continue;

        final barcode = row[0]?.value?.toString().trim();
        if (barcode == null || barcode.isEmpty) continue;

        final productGroup = row.length > 1 ? row[1]?.value?.toString().trim() ?? '' : '';
        final productName = row.length > 2 ? row[2]?.value?.toString().trim() ?? '' : '';

        dynamic gradeValue = row.length > 3 ? row[3]?.value : null;
        int grade = 1;
        if (gradeValue != null) {
          if (gradeValue is int) {
            grade = gradeValue;
          } else if (gradeValue is double) {
            grade = gradeValue.toInt();
          } else {
            grade = int.tryParse(gradeValue.toString().trim()) ?? 1;
          }
        }
        if (grade < 1 || grade > 3) grade = 1;

        products.add({
          'barcode': barcode,
          'productGroup': productGroup,
          'productName': productName,
          'grade': grade,
        });
      }

      if (products.isEmpty) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Excel файл не содержит валидных товаров'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      if (mounted) Navigator.pop(context);

      if (!mounted) return;

      // Подтверждение
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: AppColors.emeraldDark,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 24.h),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: mode == 'replace'
                          ? [Colors.orange[400]!, Colors.orange[700]!]
                          : [AppColors.emerald, AppColors.emeraldDark],
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20.r),
                      topRight: Radius.circular(20.r),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          mode == 'replace' ? Icons.swap_horiz_rounded : Icons.add_circle_outline,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        mode == 'replace' ? 'Заменить все товары?' : 'Добавить новые товары?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(20.w),
                  child: Column(
                    children: [
                      Text(
                        mode == 'replace'
                            ? 'Найдено ${products.length} товаров.\nВсе существующие товары будут удалены.'
                            : 'Найдено ${products.length} товаров.\nБудут добавлены только товары с новыми баркодами.',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.white.withOpacity(0.7),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context, false),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 14.h),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                side: BorderSide(color: Colors.white.withOpacity(0.2)),
                              ),
                              child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: mode == 'replace' ? Colors.orange[700] : AppColors.gold,
                                foregroundColor: mode == 'replace' ? Colors.white : AppColors.night,
                                padding: EdgeInsets.symmetric(vertical: 14.h),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                mode == 'replace' ? 'Заменить' : 'Добавить',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
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
        ),
      );

      if (!mounted) return;

      if (confirmed != true) return;

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Container(
              padding: EdgeInsets.all(24.w),
              decoration: BoxDecoration(
                color: AppColors.emeraldDark,
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
              ),
            ),
          ),
        );
      }

      if (mode == 'replace') {
        final uploadResult = await RecountQuestionService.bulkUploadProducts(products);
        if (mounted) Navigator.pop(context);

        if (uploadResult != null) {
          await _loadProducts();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Загружено ${uploadResult.length} товаров'),
                  ],
                ),
                backgroundColor: Colors.green[600],
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                margin: EdgeInsets.all(16.w),
              ),
            );
          }
        }
      } else {
        final addResult = await RecountQuestionService.bulkAddNewProducts(products);
        if (mounted) Navigator.pop(context);

        if (addResult != null) {
          await _loadProducts();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Добавлено ${addResult.added}, пропущено ${addResult.skipped}'),
                  ],
                ),
                backgroundColor: Colors.green[600],
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                margin: EdgeInsets.all(16.w),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteProduct(RecountQuestion product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: AppColors.emeraldDark,
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 24.h),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red[400]!, Colors.red[600]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20.r),
                    topRight: Radius.circular(20.r),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(16.w),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.delete_forever_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Удалить товар?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(20.w),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(14.w),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            product.productName,
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: Colors.white.withOpacity(0.8),
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Баркод: ${product.barcode}',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: Colors.white.withOpacity(0.5),
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 14.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              side: BorderSide(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[500],
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 14.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              elevation: 0,
                            ),
                            child: Text('Удалить', style: TextStyle(fontWeight: FontWeight.w600)),
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
      ),
    );

    if (confirmed == true) {
      final success = await RecountQuestionService.deleteQuestion(product.id);
      if (success) {
        await _loadProducts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Товар успешно удален'),
                ],
              ),
              backgroundColor: Colors.green[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
              margin: EdgeInsets.all(16.w),
            ),
          );
        }
      }
    }
  }

  Color _getGradeColor(int grade) {
    switch (grade) {
      case 1: return Color(0xFFE53935);
      case 2: return Color(0xFFFB8C00);
      case 3: return Color(0xFF43A047);
      default: return Colors.grey;
    }
  }

  String _getGradeLabel(int grade) {
    switch (grade) {
      case 1: return 'Важный';
      case 2: return 'Средний';
      case 3: return 'Обычный';
      default: return '?';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildCustomAppBar(),
              _buildCustomTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildProductsTab(),
                    RecountPointsSettingsPage(),
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
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 0.h),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Вопросы пересчета',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, child) {
                    return Text(
                      _tabController.index == 0
                          ? '${_products.length} товаров'
                          : 'Настройка баллов',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13.sp,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, child) {
              if (_tabController.index == 0) {
                return Row(
                  children: [
                    _buildActionButton(
                      icon: Icons.upload_file,
                      onPressed: _showUploadModeDialog,
                      tooltip: 'Загрузить из Excel',
                    ),
                    SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.refresh,
                      onPressed: _loadProducts,
                      tooltip: 'Обновить',
                    ),
                  ],
                );
              }
              return SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white.withOpacity(0.8), size: 20),
        onPressed: onPressed,
        tooltip: tooltip,
        constraints: BoxConstraints(minWidth: 44, minHeight: 44),
      ),
    );
  }

  Widget _buildCustomTabBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: AppColors.gold.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: AppColors.gold, width: 1.5),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: EdgeInsets.all(4.w),
          dividerColor: Colors.transparent,
          labelColor: AppColors.gold,
          unselectedLabelColor: Colors.white.withOpacity(0.6),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13.sp,
          ),
          unselectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 13.sp,
          ),
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 20),
                  SizedBox(width: 8),
                  Text('Товары'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bar_chart_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Баллы'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsTab() {
    if (_isProductsLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Загрузка товаров...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14.sp,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Поиск
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 8.h),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: Colors.white, fontSize: 15.sp),
              decoration: InputDecoration(
                hintText: 'Поиск по баркоду или названию...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, color: Colors.white.withOpacity(0.5), size: 20),
                        onPressed: () {
                          _searchController.clear();
                          if (mounted) setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              ),
              cursorColor: AppColors.gold,
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        ),
        // Статистика по грейдам
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          child: Row(
            children: [
              _buildGradeChip(1, 'Важных'),
              SizedBox(width: 8),
              _buildGradeChip(2, 'Средних'),
              SizedBox(width: 8),
              _buildGradeChip(3, 'Обычных'),
              Spacer(),
              if (_searchQuery.isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    'Найдено: ${_filteredProducts.length}',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Список
        Expanded(
          child: _filteredProducts.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadProducts,
                  color: AppColors.gold,
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = _filteredProducts[index];
                      return _buildProductCard(product, index);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildGradeChip(int grade, String label) {
    final count = _filteredProducts.where((p) => p.grade == grade).length;
    final color = _getGradeColor(grade);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 13.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(28.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(
              _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.inventory_2_outlined,
              size: 48,
              color: AppColors.gold.withOpacity(0.6),
            ),
          ),
          SizedBox(height: 24),
          Text(
            _searchQuery.isNotEmpty ? 'Товары не найдены' : 'Нет товаров',
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          SizedBox(height: 8),
          if (_searchQuery.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 48.w),
              child: Text(
                'Нажмите кнопку загрузки\nчтобы добавить товары из Excel',
                style: TextStyle(
                  fontSize: 15.sp,
                  color: Colors.white.withOpacity(0.5),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            Text(
              'Попробуйте изменить запрос',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductCard(RecountQuestion product, int index) {
    final gradeColor = _getGradeColor(product.grade);

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () {},
          splashColor: gradeColor.withOpacity(0.08),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                // Индикатор грейда
                Container(
                  width: 4,
                  height: 70,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        gradeColor,
                        gradeColor.withOpacity(0.4),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
                SizedBox(width: 14),
                // Информация о товаре
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Баркод
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: Text(
                          product.barcode,
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            color: Colors.white.withOpacity(0.6),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      // Название
                      Text(
                        product.productName.isNotEmpty
                            ? product.productName
                            : '(без названия)',
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w500,
                          color: product.productName.isNotEmpty
                              ? Colors.white.withOpacity(0.9)
                              : Colors.white.withOpacity(0.4),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Группа
                      if (product.productGroup.isNotEmpty) ...[
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.folder_outlined, size: 14, color: Colors.white.withOpacity(0.3)),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                product.productGroup,
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: Colors.white.withOpacity(0.4),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 10),
                // Грейд и кнопка удаления
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Бейдж грейда
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                      decoration: BoxDecoration(
                        color: gradeColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(
                          color: gradeColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            product.grade == 1
                                ? Icons.priority_high_rounded
                                : product.grade == 2
                                    ? Icons.remove_rounded
                                    : Icons.check_rounded,
                            size: 14,
                            color: gradeColor,
                          ),
                          SizedBox(width: 4),
                          Text(
                            _getGradeLabel(product.grade),
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                              color: gradeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12),
                    // Кнопка удаления
                    InkWell(
                      onTap: () => _deleteProduct(product),
                      borderRadius: BorderRadius.circular(8.r),
                      child: Container(
                        padding: EdgeInsets.all(8.w),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red[400],
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

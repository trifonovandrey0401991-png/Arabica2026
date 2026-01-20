import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;
import 'dart:typed_data';
import 'dart:io';
import '../models/recount_question_model.dart';
import '../services/recount_question_service.dart';
import 'recount_points_settings_page.dart';

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

  // Цвета градиента для современного дизайна
  static const _primaryColor = Color(0xFF004D40);
  static const _gradientStart = Color(0xFF00695C);
  static const _gradientEnd = Color(0xFF004D40);

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
    setState(() => _isProductsLoading = true);

    try {
      final products = await RecountQuestionService.getQuestions();
      setState(() {
        _products = products;
        _isProductsLoading = false;
      });
    } catch (e) {
      setState(() => _isProductsLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки товаров: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Показать диалог выбора режима загрузки
  Future<void> _showUploadModeDialog() async {
    final mode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Загрузка из Excel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Формат файла: только .xlsx\n\nСтолбец 1: Баркод\nСтолбец 2: Группа товара\nСтолбец 3: Наименование\nСтолбец 4: Грейд (1, 2 или 3)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, 'replace'),
                icon: const Icon(Icons.refresh),
                label: const Text('Заменить все'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Удалить текущие товары и загрузить новые из файла',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, 'add_new'),
                icon: const Icon(Icons.add),
                label: const Text('Добавить новые'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Добавить только товары с новыми баркодами',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
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
          builder: (context) => const Center(child: CircularProgressIndicator()),
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
            const SnackBar(content: Text('Не удалось прочитать файл'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final fileName = file.name.toLowerCase();
      if (fileName.endsWith('.xls') && !fileName.endsWith('.xlsx')) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
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
            const SnackBar(content: Text('Ошибка чтения файла'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      if (excelFile.tables.isEmpty) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel файл не содержит листов'), backgroundColor: Colors.red),
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
            const SnackBar(content: Text('Excel файл не содержит валидных товаров'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      if (mounted) Navigator.pop(context);

      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(mode == 'replace' ? 'Заменить все товары?' : 'Добавить новые товары?'),
          content: Text(
            mode == 'replace'
                ? 'Найдено ${products.length} товаров.\n\nВсе существующие товары будут удалены.'
                : 'Найдено ${products.length} товаров.\n\nБудут добавлены только товары с новыми баркодами.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(mode == 'replace' ? 'Заменить' : 'Добавить'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (confirmed != true) return;

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );
      }

      if (mode == 'replace') {
        final uploadResult = await RecountQuestionService.bulkUploadProducts(products);
        if (mounted) Navigator.pop(context);

        if (uploadResult != null) {
          await _loadProducts();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Загружено ${uploadResult.length} товаров'), backgroundColor: Colors.green),
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
                content: Text('Добавлено ${addResult.added} новых товаров\nПропущено ${addResult.skipped}'),
                backgroundColor: Colors.green,
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
      builder: (context) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: Text('Баркод: ${product.barcode}\n${product.productName}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await RecountQuestionService.deleteQuestion(product.id);
      if (success) {
        await _loadProducts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Товар удален'), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  Color _getGradeColor(int grade) {
    switch (grade) {
      case 1: return Colors.red;
      case 2: return Colors.orange;
      case 3: return Colors.green;
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_gradientStart, _gradientEnd],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Кастомный AppBar с градиентом
              _buildCustomAppBar(),
              // Кастомный TabBar
              _buildCustomTabBar(),
              // Контент
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildProductsTab(),
                        const RecountPointsSettingsPage(),
                      ],
                    ),
                  ),
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
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          // Кнопка назад
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          // Заголовок
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Вопросы пересчета',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
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
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // Кнопки действий
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
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.refresh,
                      onPressed: _loadProducts,
                      tooltip: 'Обновить',
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
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
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onPressed,
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      ),
    );
  }

  Widget _buildCustomTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.all(4),
          dividerColor: Colors.transparent,
          labelColor: _primaryColor,
          unselectedLabelColor: Colors.white.withOpacity(0.85),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          tabs: const [
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
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Загрузка товаров...',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Поиск с улучшенным дизайном
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск по баркоду или названию...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                suffixIcon: _searchQuery.isNotEmpty
                    ? Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: const Icon(Icons.close, size: 18, color: Colors.grey),
                        ),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        ),
        // Статистика по грейдам
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildGradeChip(1, 'Важных'),
              const SizedBox(width: 8),
              _buildGradeChip(2, 'Средних'),
              const SizedBox(width: 8),
              _buildGradeChip(3, 'Обычных'),
              const Spacer(),
              if (_searchQuery.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Найдено: ${_filteredProducts.length}',
                    style: const TextStyle(
                      color: _primaryColor,
                      fontSize: 12,
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
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: _filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = _filteredProducts[index];
                    return _buildProductCard(product, index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildGradeChip(int grade, String label) {
    final count = _filteredProducts.where((p) => p.grade == grade).length;
    final color = _getGradeColor(grade);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
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
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 13,
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
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.inventory_2_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _searchQuery.isNotEmpty ? 'Товары не найдены' : 'Нет товаров',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          if (_searchQuery.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                'Нажмите кнопку загрузки\nчтобы добавить товары из Excel',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            Text(
              'Попробуйте изменить запрос',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductCard(RecountQuestion product, int index) {
    final gradeColor = _getGradeColor(product.grade);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradeColor.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Можно добавить детали товара
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                        gradeColor.withOpacity(0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 14),
                // Информация о товаре
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Баркод
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          product.barcode,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            color: Colors.grey[700],
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Название
                      Text(
                        product.productName.isNotEmpty
                            ? product.productName
                            : '(без названия)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: product.productName.isNotEmpty
                              ? Colors.black87
                              : Colors.grey[400],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Группа
                      if (product.productGroup.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.folder_outlined, size: 14, color: Colors.grey[400]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                product.productGroup,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
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
                const SizedBox(width: 10),
                // Грейд и кнопка удаления
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Бейдж грейда
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            gradeColor.withOpacity(0.15),
                            gradeColor.withOpacity(0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
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
                          const SizedBox(width: 4),
                          Text(
                            _getGradeLabel(product.grade),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: gradeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Кнопка удаления
                    InkWell(
                      onTap: () => _deleteProduct(product),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red[300],
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

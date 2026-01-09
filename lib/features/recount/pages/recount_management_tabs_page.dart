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

  static const _primaryColor = Color(0xFF004D40);

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
      appBar: AppBar(
        title: const Text('Вопросы пересчета'),
        backgroundColor: _primaryColor,
        actions: [
          // Кнопки только для вкладки товаров
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, child) {
              if (_tabController.index == 0) {
                return Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.upload_file),
                      onPressed: _showUploadModeDialog,
                      tooltip: 'Загрузить из Excel',
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2), text: 'Товары'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Настройка Баллов'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Вкладка товаров
          _buildProductsTab(),
          // Вкладка настройки баллов
          const RecountPointsSettingsPage(),
        ],
      ),
    );
  }

  Widget _buildProductsTab() {
    if (_isProductsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Поиск
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Поиск по баркоду или названию...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        // Счетчик
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('Товаров: ${_filteredProducts.length}', style: TextStyle(color: Colors.grey[600])),
              if (_searchQuery.isNotEmpty && _filteredProducts.length != _products.length)
                Text(' из ${_products.length}', style: TextStyle(color: Colors.grey[400])),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Список
        Expanded(
          child: _filteredProducts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _searchQuery.isNotEmpty ? Icons.search_off : Icons.inventory_2_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty ? 'Товары не найдены' : 'Нет товаров',
                        style: const TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      if (_searchQuery.isEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Нажмите иконку загрузки чтобы добавить товары из Excel',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = _filteredProducts[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 60,
                              decoration: BoxDecoration(
                                color: _getGradeColor(product.grade),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.barcode,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    product.productName.isNotEmpty ? product.productName : '(без названия)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: product.productName.isNotEmpty ? Colors.black87 : Colors.grey,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (product.productGroup.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      product.productGroup,
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getGradeColor(product.grade).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _getGradeLabel(product.grade),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: _getGradeColor(product.grade),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () => _deleteProduct(product),
                                  child: Icon(Icons.delete_outline, color: Colors.grey[400], size: 20),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

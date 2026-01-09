import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;
import 'dart:typed_data';
import 'dart:io';
import '../models/recount_question_model.dart';
import '../services/recount_question_service.dart';

/// Страница управления товарами пересчета
class RecountQuestionsManagementPage extends StatefulWidget {
  const RecountQuestionsManagementPage({super.key});

  @override
  State<RecountQuestionsManagementPage> createState() => _RecountQuestionsManagementPageState();
}

class _RecountQuestionsManagementPageState extends State<RecountQuestionsManagementPage> {
  List<RecountQuestion> _products = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  static const _primaryColor = Color(0xFF004D40);

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
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
    setState(() {
      _isLoading = true;
    });

    try {
      final products = await RecountQuestionService.getQuestions();
      setState(() {
        _products = products;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки товаров: $e', style: const TextStyle(color: Colors.white)),
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
      // Выбор файла
      FilePickerResult? pickerResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
      );

      if (pickerResult == null || pickerResult.files.single.path == null) {
        return;
      }

      // Показываем индикатор загрузки
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // Читаем файл
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
            const SnackBar(
              content: Text('Не удалось прочитать файл', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Проверяем формат файла - .xls не поддерживается
      final fileName = file.name.toLowerCase();
      if (fileName.endsWith('.xls') && !fileName.endsWith('.xlsx')) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Формат .xls не поддерживается.\nСохраните файл в формате .xlsx',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
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
            SnackBar(
              content: Text(
                'Ошибка чтения файла.\nУбедитесь, что файл в формате .xlsx',
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      if (excelFile.tables.isEmpty) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Excel файл не содержит листов', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final sheet = excelFile.tables[excelFile.tables.keys.first]!;
      final products = <Map<String, dynamic>>[];

      // Парсим данные (формат: баркод, группа, название, грейд)
      for (var rowIndex = 0; rowIndex < sheet.maxRows; rowIndex++) {
        final row = sheet.rows[rowIndex];

        if (row.isEmpty || row[0]?.value == null) {
          continue;
        }

        // Столбец 0: Баркод
        final barcode = row[0]?.value?.toString().trim();
        if (barcode == null || barcode.isEmpty) {
          continue;
        }

        // Столбец 1: Группа товара
        final productGroup = row.length > 1 ? row[1]?.value?.toString().trim() ?? '' : '';

        // Столбец 2: Наименование
        final productName = row.length > 2 ? row[2]?.value?.toString().trim() ?? '' : '';

        // Столбец 3: Грейд
        dynamic gradeValue = row.length > 3 ? row[3]?.value : null;
        int grade = 1;

        if (gradeValue != null) {
          if (gradeValue is int) {
            grade = gradeValue;
          } else if (gradeValue is double) {
            grade = gradeValue.toInt();
          } else {
            final gradeStr = gradeValue.toString().trim();
            grade = int.tryParse(gradeStr) ?? 1;
          }
        }

        // Валидация грейда
        if (grade < 1 || grade > 3) {
          grade = 1;
        }

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
            const SnackBar(
              content: Text('Excel файл не содержит валидных товаров', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Закрываем индикатор загрузки
      if (mounted) {
        Navigator.pop(context);
      }

      // Показываем диалог подтверждения
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(mode == 'replace' ? 'Заменить все товары?' : 'Добавить новые товары?'),
          content: Text(
            mode == 'replace'
                ? 'Найдено ${products.length} товаров.\n\nВсе существующие товары будут удалены и заменены новыми из файла.'
                : 'Найдено ${products.length} товаров.\n\nБудут добавлены только товары с баркодами, которых нет в базе.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: mode == 'replace' ? Colors.orange : _primaryColor,
              ),
              child: Text(mode == 'replace' ? 'Заменить' : 'Добавить'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }

      // Показываем индикатор загрузки
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // Отправляем данные на сервер
      if (mode == 'replace') {
        final uploadResult = await RecountQuestionService.bulkUploadProducts(products);

        if (mounted) Navigator.pop(context);

        if (uploadResult != null) {
          await _loadProducts();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Загружено ${uploadResult.length} товаров', style: const TextStyle(color: Colors.white)),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Ошибка загрузки товаров', style: TextStyle(color: Colors.white)),
                backgroundColor: Colors.red,
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
                content: Text(
                  'Добавлено ${addResult.added} новых товаров\nПропущено ${addResult.skipped} (уже есть в базе)',
                  style: const TextStyle(color: Colors.white),
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Ошибка добавления товаров', style: TextStyle(color: Colors.white)),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при обработке Excel файла: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteProduct(RecountQuestion product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: Text('Вы уверены, что хотите удалить:\n"${product.productName}"?\n\nБаркод: ${product.barcode}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
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
            const SnackBar(
              content: Text('Товар успешно удален', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка удаления товара', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Color _getGradeColor(int grade) {
    switch (grade) {
      case 1:
        return Colors.red;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getGradeLabel(int grade) {
    switch (grade) {
      case 1:
        return 'Важный';
      case 2:
        return 'Средний';
      case 3:
        return 'Обычный';
      default:
        return '?';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Товары пересчета'),
        backgroundColor: _primaryColor,
        actions: [
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Поиск по баркоду/названию
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                // Счетчик товаров
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        'Товаров: ${_filteredProducts.length}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      if (_searchQuery.isNotEmpty && _filteredProducts.length != _products.length)
                        Text(
                          ' из ${_products.length}',
                          style: TextStyle(color: Colors.grey[400], fontSize: 14),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Список товаров
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
                                _searchQuery.isNotEmpty
                                    ? 'Товары не найдены'
                                    : 'Нет товаров',
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
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    // Грейд
                                    Container(
                                      width: 8,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: _getGradeColor(product.grade),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Информация о товаре
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Баркод
                                          Text(
                                            product.barcode,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          // Наименование
                                          Text(
                                            product.productName.isNotEmpty
                                                ? product.productName
                                                : '(без названия)',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: product.productName.isNotEmpty
                                                  ? Colors.black87
                                                  : Colors.grey,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (product.productGroup.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            // Группа товара
                                            Text(
                                              product.productGroup,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Грейд чип + удаление
                                    Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
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
                                          child: Icon(
                                            Icons.delete_outline,
                                            color: Colors.grey[400],
                                            size: 20,
                                          ),
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
            ),
    );
  }
}

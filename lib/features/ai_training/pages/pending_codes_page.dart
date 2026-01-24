import 'package:flutter/material.dart';
import '../models/pending_code_model.dart';
import '../models/master_product_model.dart';
import '../services/master_catalog_service.dart';
import '../../../core/utils/logger.dart';

/// Страница управления новыми кодами товаров (pending codes)
class PendingCodesPage extends StatefulWidget {
  final VoidCallback? onCodeApproved;

  const PendingCodesPage({super.key, this.onCodeApproved});

  @override
  State<PendingCodesPage> createState() => _PendingCodesPageState();
}

class _PendingCodesPageState extends State<PendingCodesPage> {
  List<PendingCode> _pendingCodes = [];
  bool _isLoading = true;
  String? _error;

  // Цвета
  static const _greenGradient = [Color(0xFF10B981), Color(0xFF34D399)];
  static const _blueGradient = [Color(0xFF3B82F6), Color(0xFF60A5FA)];
  static const _orangeGradient = [Color(0xFFF59E0B), Color(0xFFFBBF24)];
  static const _redGradient = [Color(0xFFEF4444), Color(0xFFF87171)];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final codes = await MasterCatalogService.getPendingCodes();

      if (mounted) {
        setState(() {
          _pendingCodes = codes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Ошибка загрузки: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null) {
      return _buildErrorView();
    }

    if (_pendingCodes.isEmpty) {
      return _buildEmptyView();
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _greenGradient[0],
      backgroundColor: const Color(0xFF1A1A2E),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingCodes.length + 1, // +1 для заголовка
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildHeader();
          }
          return _buildCodeCard(_pendingCodes[index - 1]);
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: _orangeGradient),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.new_releases, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Новые коды (${_pendingCodes.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Добавьте их в мастер-каталог',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard(PendingCode code) {
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
          onTap: () => _showApproveDialog(code),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Иконка
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: _blueGradient),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.qr_code_2,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),

                // Информация
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code.primaryName.isNotEmpty ? code.primaryName : code.kod,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        code.kod,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.store,
                            size: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Магазинов: ${code.shopCount}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            code.formattedDate,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Кнопки
                Column(
                  children: [
                    _buildIconButton(
                      icon: Icons.check,
                      color: _greenGradient[0],
                      onTap: () => _showApproveDialog(code),
                    ),
                    const SizedBox(height: 8),
                    _buildIconButton(
                      icon: Icons.close,
                      color: _redGradient[0],
                      onTap: () => _rejectCode(code),
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

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: _greenGradient),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.check_circle, size: 36, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text(
              'Все коды обработаны',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Новые коды товаров будут\nпоявляться при синхронизации DBF',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.red.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: _redGradient),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.error_outline, size: 32, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Неизвестная ошибка',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _greenGradient[0],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Диалог подтверждения кода
  void _showApproveDialog(PendingCode code) {
    final nameController = TextEditingController(text: code.primaryName);
    String selectedGroup = code.primaryGroup;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: _greenGradient),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.add_circle, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Добавить в каталог',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Штрих-код
                  Text(
                    'Штрих-код',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code, color: Colors.white.withOpacity(0.5), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          code.kod,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Выбор названия (если есть варианты)
                  if (code.allNames.length > 1) ...[
                    Text(
                      'Выберите название:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...code.sources.map((source) => GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          nameController.text = source.name;
                          if (source.group.isNotEmpty) {
                            selectedGroup = source.group;
                          }
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: nameController.text == source.name
                              ? _blueGradient[0].withOpacity(0.2)
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: nameController.text == source.name
                                ? _blueGradient[0]
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Radio<String>(
                              value: source.name,
                              groupValue: nameController.text,
                              onChanged: (val) {
                                setDialogState(() {
                                  nameController.text = val!;
                                  if (source.group.isNotEmpty) {
                                    selectedGroup = source.group;
                                  }
                                });
                              },
                              activeColor: _blueGradient[0],
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    source.name,
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                  ),
                                  Text(
                                    source.shopName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withOpacity(0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                    const SizedBox(height: 8),
                  ],

                  // Поле ввода названия
                  Text(
                    'Или введите своё:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Название товара',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _blueGradient[0]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Группа
                  Text(
                    'Группа товара',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedGroup.isNotEmpty ? selectedGroup : null,
                        hint: Text(
                          'Выберите группу',
                          style: TextStyle(color: Colors.white.withOpacity(0.5)),
                        ),
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1A1A2E),
                        icon: Icon(Icons.expand_more, color: Colors.white.withOpacity(0.5)),
                        items: code.allGroups.map((group) => DropdownMenuItem(
                          value: group,
                          child: Text(group, style: const TextStyle(color: Colors.white)),
                        )).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedGroup = val ?? '';
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Кнопки
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Отмена',
                            style: TextStyle(color: Colors.white.withOpacity(0.6)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _approveCode(
                            code,
                            nameController.text,
                            selectedGroup,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _greenGradient[0],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Добавить'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Подтвердить код
  Future<void> _approveCode(PendingCode code, String name, String group) async {
    if (name.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите название товара'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.pop(context); // Закрыть диалог

    setState(() => _isLoading = true);

    try {
      final product = await MasterCatalogService.approveCode(
        kod: code.kod,
        name: name.trim(),
        group: group,
      );

      if (product != null) {
        Logger.info('Код ${code.kod} добавлен в мастер-каталог как: ${product.name}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Товар "${product.name}" добавлен в каталог'),
              backgroundColor: _greenGradient[0],
            ),
          );
        }

        widget.onCodeApproved?.call();
        _loadData();
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка добавления товара'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Отклонить код
  Future<void> _rejectCode(PendingCode code) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Отклонить код?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Код ${code.kod} будет удалён из списка ожидания.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Отмена',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _redGradient[0],
              foregroundColor: Colors.white,
            ),
            child: const Text('Отклонить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final success = await MasterCatalogService.rejectCode(code.kod);

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Код отклонён'),
              backgroundColor: Colors.grey,
            ),
          );
        }
        _loadData();
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка удаления кода'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

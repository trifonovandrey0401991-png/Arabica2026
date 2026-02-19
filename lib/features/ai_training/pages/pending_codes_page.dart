import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/pending_code_model.dart';
import '../services/master_catalog_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  static final _greenGradient = [AppColors.emeraldGreen, AppColors.emeraldGreenLight];
  static final _blueGradient = [AppColors.info, AppColors.infoLight];
  static final _orangeGradient = [AppColors.warning, AppColors.warningLight];
  static final _redGradient = [AppColors.error, AppColors.errorLight];

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
      return Center(
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
      backgroundColor: AppColors.darkNavy,
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
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
      margin: EdgeInsets.only(bottom: 16.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16.r),
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
              gradient: LinearGradient(colors: _orangeGradient),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(Icons.new_releases, color: Colors.white, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Новые коды (${_pendingCodes.length})',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Добавьте их в мастер-каталог',
                  style: TextStyle(
                    fontSize: 13.sp,
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
          onTap: () => _showApproveDialog(code),
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                // Иконка
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _blueGradient),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Icon(
                    Icons.qr_code_2,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                SizedBox(width: 14),

                // Информация
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code.primaryName.isNotEmpty ? code.primaryName : code.kod,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4),
                      Text(
                        code.kod,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white.withOpacity(0.5),
                          fontFamily: 'monospace',
                        ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.store,
                            size: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Магазинов: ${code.shopCount}',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                          SizedBox(width: 12),
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          SizedBox(width: 4),
                          Text(
                            code.formattedDate,
                            style: TextStyle(
                              fontSize: 11.sp,
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
                    SizedBox(height: 8),
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
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Container(
        margin: EdgeInsets.all(24.w),
        padding: EdgeInsets.all(32.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20.r),
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
                gradient: LinearGradient(colors: _greenGradient),
                borderRadius: BorderRadius.circular(18.r),
              ),
              child: Icon(Icons.check_circle, size: 36, color: Colors.white),
            ),
            SizedBox(height: 20),
            Text(
              'Все коды обработаны',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Новые коды товаров будут\nпоявляться при синхронизации DBF',
              style: TextStyle(
                fontSize: 14.sp,
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
        margin: EdgeInsets.all(24.w),
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: AppColors.error.withOpacity(0.3),
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
                gradient: LinearGradient(colors: _redGradient),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Icon(Icons.error_outline, size: 32, color: Colors.white),
            ),
            SizedBox(height: 16),
            Text(
              _error ?? 'Неизвестная ошибка',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14.sp,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: Icon(Icons.refresh),
              label: Text('Повторить'),
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

  /// Показать выбор действия для pending кода
  void _showApproveDialog(PendingCode code) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkNavy,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.only(bottom: 16.h),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            Text(
              'Код: ${code.kod}',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFamily: 'monospace',
              ),
            ),
            SizedBox(height: 4),
            Text(
              code.primaryName,
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
            SizedBox(height: 24),

            // Две кнопки
            Row(
              children: [
                // В карточку
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.playlist_add,
                    label: 'В карточку',
                    gradient: _blueGradient,
                    onTap: () {
                      Navigator.pop(context);
                      _showAssignToExistingDialog(code);
                    },
                  ),
                ),
                SizedBox(width: 12),
                // Новая карточка
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.add_circle_outline,
                    label: 'Новая карточка',
                    gradient: _greenGradient,
                    onTap: () {
                      Navigator.pop(context);
                      _showCreateNewCardDialog(code);
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 20.h),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Диалог "В карточку" — поиск существующего товара
  void _showAssignToExistingDialog(PendingCode code) {
    showDialog(
      context: context,
      builder: (context) => _AssignToExistingDialog(
        code: code,
        onAssigned: () {
          widget.onCodeApproved?.call();
          _loadData();
        },
      ),
    );
  }

  /// Диалог "Новая карточка" — создание нового товара
  void _showCreateNewCardDialog(PendingCode code) {
    final nameController = TextEditingController(text: code.primaryName);
    String selectedGroup = code.primaryGroup;
    List<String> groups = code.allGroups.toList();
    final groupTextController = TextEditingController();
    bool useCustomGroup = false;
    List<AssignSearchProduct> nameSuggestions = [];
    Timer? debounce;

    // Загрузим группы из API
    MasterCatalogService.getGroups().then((apiGroups) {
      if (apiGroups.isNotEmpty) {
        groups = {...groups, ...apiGroups}.toList()..sort();
      }
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: AppColors.darkNavy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
          child: Container(
            padding: EdgeInsets.all(24.w),
            constraints: BoxConstraints(maxWidth: 400),
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
                          gradient: LinearGradient(colors: _greenGradient),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Icon(Icons.add_circle, color: Colors.white, size: 24),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Новая карточка',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),

                  // Штрих-код
                  Text('Штрих-код', style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.6))),
                  SizedBox(height: 4),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code, color: Colors.white.withOpacity(0.5), size: 20),
                        SizedBox(width: 8),
                        Text(code.kod, style: TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 14.sp)),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),

                  // Выбор названия из магазинов
                  if (code.allNames.length > 1) ...[
                    Text('Варианты из магазинов:', style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.6))),
                    SizedBox(height: 8),
                    ...code.sources.map((source) => GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          nameController.text = source.name;
                          if (source.group.isNotEmpty) selectedGroup = source.group;
                        });
                      },
                      child: Container(
                        margin: EdgeInsets.only(bottom: 6.h),
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: nameController.text == source.name
                              ? _blueGradient[0].withOpacity(0.2) : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10.r),
                          border: Border.all(
                            color: nameController.text == source.name ? _blueGradient[0] : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Radio<String>(
                              value: source.name,
                              groupValue: nameController.text,
                              onChanged: (val) => setDialogState(() {
                                nameController.text = val!;
                                if (source.group.isNotEmpty) selectedGroup = source.group;
                              }),
                              activeColor: _blueGradient[0],
                            ),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(source.name, style: TextStyle(color: Colors.white, fontSize: 13.sp)),
                                Text(source.shopName, style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5))),
                              ],
                            )),
                          ],
                        ),
                      ),
                    )),
                    SizedBox(height: 8),
                  ],

                  // Поле ввода названия с подсказками
                  Text('Название товара', style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.6))),
                  SizedBox(height: 4),
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: Colors.white),
                    onChanged: (value) {
                      debounce?.cancel();
                      debounce = Timer(Duration(milliseconds: 400), () async {
                        if (value.length >= 2) {
                          final results = await MasterCatalogService.searchForAssign(value);
                          setDialogState(() => nameSuggestions = results);
                        } else {
                          setDialogState(() => nameSuggestions = []);
                        }
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Введите название',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: _blueGradient[0])),
                    ),
                  ),
                  // Подсказки похожих товаров
                  if (nameSuggestions.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Container(
                      constraints: BoxConstraints(maxHeight: 120),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: nameSuggestions.length,
                        itemBuilder: (ctx, i) {
                          final s = nameSuggestions[i];
                          return ListTile(
                            dense: true,
                            title: Text(s.name, style: TextStyle(color: Colors.white, fontSize: 12.sp)),
                            subtitle: Text('${s.group} (${s.barcodesCount} шт-кодов)', style: TextStyle(fontSize: 10.sp, color: Colors.white.withOpacity(0.5))),
                            onTap: () => setDialogState(() {
                              nameController.text = s.name;
                              if (s.group.isNotEmpty) selectedGroup = s.group;
                              nameSuggestions = [];
                            }),
                          );
                        },
                      ),
                    ),
                  ],
                  SizedBox(height: 16),

                  // Группа товара
                  Text('Группа товара', style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.6))),
                  SizedBox(height: 4),
                  if (!useCustomGroup)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: groups.contains(selectedGroup) ? selectedGroup : null,
                                hint: Text('Выберите группу', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                                isExpanded: true,
                                dropdownColor: AppColors.darkNavy,
                                icon: Icon(Icons.expand_more, color: Colors.white.withOpacity(0.5)),
                                items: groups.map((g) => DropdownMenuItem(
                                  value: g,
                                  child: Text(g, style: TextStyle(color: Colors.white)),
                                )).toList(),
                                onChanged: (val) => setDialogState(() => selectedGroup = val ?? ''),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.edit, color: Colors.white.withOpacity(0.5), size: 18),
                            onPressed: () => setDialogState(() {
                              useCustomGroup = true;
                              groupTextController.text = selectedGroup;
                            }),
                            tooltip: 'Ввести вручную',
                          ),
                        ],
                      ),
                    )
                  else
                    TextField(
                      controller: groupTextController,
                      style: TextStyle(color: Colors.white),
                      onChanged: (val) => selectedGroup = val,
                      decoration: InputDecoration(
                        hintText: 'Название группы',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: _blueGradient[0])),
                        suffixIcon: IconButton(
                          icon: Icon(Icons.list, color: Colors.white.withOpacity(0.5), size: 18),
                          onPressed: () => setDialogState(() => useCustomGroup = false),
                        ),
                      ),
                    ),
                  SizedBox(height: 24),

                  // Кнопки
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _approveCode(code, nameController.text, useCustomGroup ? groupTextController.text : selectedGroup),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _greenGradient[0],
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 14.h),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                          ),
                          child: Text('Создать'),
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
    ).then((_) {
      nameController.dispose();
      groupTextController.dispose();
      debounce?.cancel();
    });
  }

  /// Подтвердить код
  Future<void> _approveCode(PendingCode code, String name, String group) async {
    if (name.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Введите название товара'),
          backgroundColor: AppColors.warning,
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
            SnackBar(
              content: Text('Ошибка добавления товара'),
              backgroundColor: AppColors.error,
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
            backgroundColor: AppColors.error,
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
        backgroundColor: AppColors.darkNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text(
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
            child: Text('Отклонить'),
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
            SnackBar(
              content: Text('Код отклонён'),
              backgroundColor: AppColors.neutral,
            ),
          );
        }
        _loadData();
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка удаления кода'),
              backgroundColor: AppColors.error,
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
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

/// Диалог поиска существующего товара для привязки кода
class _AssignToExistingDialog extends StatefulWidget {
  final PendingCode code;
  final VoidCallback onAssigned;

  _AssignToExistingDialog({
    required this.code,
    required this.onAssigned,
  });

  @override
  State<_AssignToExistingDialog> createState() => _AssignToExistingDialogState();
}

class _AssignToExistingDialogState extends State<_AssignToExistingDialog> {
  final _searchController = TextEditingController();
  List<AssignSearchProduct> _results = [];
  bool _isSearching = false;
  bool _isAssigning = false;
  Timer? _debounce;

  static final _blueGradient = [AppColors.info, AppColors.infoLight];
  static final _greenGradient = [AppColors.emeraldGreen, AppColors.emeraldGreenLight];

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: 300), () async {
      if (query.length < 2) {
        setState(() => _results = []);
        return;
      }
      setState(() => _isSearching = true);
      final results = await MasterCatalogService.searchForAssign(query);
      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _assignToProduct(AssignSearchProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Подтвердите', style: TextStyle(color: Colors.white)),
        content: Text(
          'Добавить код ${widget.code.kod} в карточку "${product.name}"?',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _greenGradient[0], foregroundColor: Colors.white),
            child: Text('Добавить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isAssigning = true);

    final success = await MasterCatalogService.assignCodeToProduct(
      kod: widget.code.kod,
      targetProductId: product.id,
    );

    if (mounted) {
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Код ${widget.code.kod} добавлен в "${product.name}"'),
            backgroundColor: _greenGradient[0],
          ),
        );
        widget.onAssigned();
      } else {
        setState(() => _isAssigning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка привязки кода'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.darkNavy,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      insetPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 40.h),
      child: Container(
        constraints: BoxConstraints(maxWidth: 500, maxHeight: 500),
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _blueGradient),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(Icons.search, color: Colors.white, size: 22),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Найти карточку', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                      Text('Код: ${widget.code.kod}', style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5), fontFamily: 'monospace')),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white.withOpacity(0.5)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Поле поиска
            TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(color: Colors.white),
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Введите название товара...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
                suffixIcon: _isSearching
                    ? Padding(
                        padding: EdgeInsets.all(12.w),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      )
                    : _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: Colors.white.withOpacity(0.5)),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _results = []);
                            },
                          )
                        : null,
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: _blueGradient[0])),
              ),
            ),
            SizedBox(height: 12),

            // Результаты
            Flexible(
              child: _isAssigning
                  ? Center(child: CircularProgressIndicator(color: Colors.white))
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            _searchController.text.length < 2
                                ? 'Введите минимум 2 символа'
                                : 'Ничего не найдено',
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13.sp),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (ctx, i) {
                            final product = _results[i];
                            return Container(
                              margin: EdgeInsets.only(bottom: 8.h),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _assignToProduct(product),
                                  borderRadius: BorderRadius.circular(12.r),
                                  child: Padding(
                                    padding: EdgeInsets.all(12.w),
                                    child: Row(
                                      children: [
                                        // Фото или иконка
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(10.r),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: product.productPhotoUrl != null
                                              ? AppCachedImage(
                                                  imageUrl: '${ApiConstants.serverUrl}${product.productPhotoUrl}',
                                                  width: 40,
                                                  height: 40,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (_, __, ___) => Icon(Icons.inventory_2, color: Colors.white54, size: 20),
                                                )
                                              : Icon(Icons.inventory_2, color: Colors.white54, size: 20),
                                        ),
                                        SizedBox(width: 12),
                                        // Название + группа
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                product.name,
                                                style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w500),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Row(
                                                children: [
                                                  if (product.group.isNotEmpty)
                                                    Text(product.group, style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5))),
                                                  if (product.barcodesCount > 1) ...[
                                                    if (product.group.isNotEmpty)
                                                      Text(' \u2022 ', style: TextStyle(color: Colors.white.withOpacity(0.3))),
                                                    Text('${product.barcodesCount} шт-кодов', style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5))),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.3), size: 14),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

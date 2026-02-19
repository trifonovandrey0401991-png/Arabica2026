import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/shift_question_model.dart';
import '../services/shift_question_service.dart';
import '../../shops/models/shop_model.dart';
import '../../../core/utils/logger.dart';
import 'package:arabica_app/shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница управления вопросами пересменки
class ShiftQuestionsManagementPage extends StatefulWidget {
  const ShiftQuestionsManagementPage({super.key});

  @override
  State<ShiftQuestionsManagementPage> createState() => _ShiftQuestionsManagementPageState();
}

class _ShiftQuestionsManagementPageState extends State<ShiftQuestionsManagementPage> {
  List<ShiftQuestion> _questions = [];
  List<ShiftQuestion> _filteredQuestions = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedTypeFilter;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    _filteredQuestions = _questions.where((q) {
      // Фильтр по тексту
      final matchesSearch = _searchQuery.isEmpty ||
          q.question.toLowerCase().contains(_searchQuery.toLowerCase());

      // Фильтр по типу
      bool matchesType = true;
      if (_selectedTypeFilter != null) {
        switch (_selectedTypeFilter) {
          case 'photo':
            matchesType = q.isPhotoOnly;
            break;
          case 'yesno':
            matchesType = q.isYesNo;
            break;
          case 'number':
            matchesType = q.isNumberOnly;
            break;
          case 'text':
            matchesType = !q.isPhotoOnly && !q.isYesNo && !q.isNumberOnly;
            break;
        }
      }

      return matchesSearch && matchesType;
    }).toList();
  }

  Future<void> _loadQuestions() async {
    if (mounted) setState(() {
      _isLoading = true;
    });

    try {
      final questions = await ShiftQuestionService.getQuestions();
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки вопросов: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showAddQuestionDialog() async {
    final result = await showDialog<ShiftQuestion>(
      context: context,
      builder: (context) => ShiftQuestionFormDialog(),
    );

    if (result != null) {
      await _loadQuestions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Вопрос успешно добавлен'),
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

  Future<void> _showEditQuestionDialog(ShiftQuestion question) async {
    final result = await showDialog<ShiftQuestion>(
      context: context,
      builder: (context) => ShiftQuestionFormDialog(question: question),
    );

    if (result != null) {
      await _loadQuestions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Вопрос успешно обновлен'),
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

  Future<void> _deleteQuestion(ShiftQuestion question) async {
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
              // Иконка предупреждения
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
                        size: 36,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Удалить вопрос?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Контент
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
                      child: Text(
                        question.question,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.white.withOpacity(0.7),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Это действие невозможно отменить',
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              // Кнопки
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 0.h, 20.w, 20.h),
                child: Row(
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
                        child: Text(
                          'Отмена',
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
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
                        child: Text(
                          'Удалить',
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                          ),
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

    if (confirmed == true) {
      final success = await ShiftQuestionService.deleteQuestion(question.id);
      if (success) {
        await _loadQuestions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Вопрос успешно удален'),
                ],
              ),
              backgroundColor: Colors.green[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
              margin: EdgeInsets.all(16.w),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Ошибка удаления вопроса'),
                ],
              ),
              backgroundColor: Colors.red[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
              margin: EdgeInsets.all(16.w),
            ),
          );
        }
      }
    }
  }

  String _getAnswerTypeLabel(ShiftQuestion question) {
    if (question.isPhotoOnly) return 'Фото';
    if (question.isYesNo) return 'Да/Нет';
    if (question.isNumberOnly) return 'Число';
    return 'Текст';
  }

  IconData _getAnswerTypeIcon(ShiftQuestion question) {
    if (question.isPhotoOnly) return Icons.camera_alt;
    if (question.isYesNo) return Icons.check_circle;
    if (question.isNumberOnly) return Icons.numbers;
    return Icons.text_fields;
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.emeraldDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    Icons.filter_list,
                    color: AppColors.gold,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Фильтр по типу ответа',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Spacer(),
                if (_selectedTypeFilter != null)
                  TextButton(
                    onPressed: () {
                      if (mounted) setState(() {
                        _selectedTypeFilter = null;
                        _applyFilters();
                      });
                      Navigator.pop(context);
                    },
                    child: Text('Сбросить', style: TextStyle(color: AppColors.gold)),
                  ),
              ],
            ),
            SizedBox(height: 20),
            // Опции фильтра
            _buildFilterOption(
              icon: Icons.check_circle,
              label: 'Да/Нет',
              value: 'yesno',
              color: Color(0xFF0288D1),
              count: _questions.where((q) => q.isYesNo).length,
            ),
            _buildFilterOption(
              icon: Icons.numbers,
              label: 'Число',
              value: 'number',
              color: Color(0xFFE65100),
              count: _questions.where((q) => q.isNumberOnly).length,
            ),
            _buildFilterOption(
              icon: Icons.camera_alt,
              label: 'Фото',
              value: 'photo',
              color: Color(0xFF7B1FA2),
              count: _questions.where((q) => q.isPhotoOnly).length,
            ),
            _buildFilterOption(
              icon: Icons.text_fields,
              label: 'Текст',
              value: 'text',
              color: Color(0xFF2E7D32),
              count: _questions.where((q) => !q.isPhotoOnly && !q.isYesNo && !q.isNumberOnly).length,
            ),
            SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOption({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required int count,
  }) {
    final isSelected = _selectedTypeFilter == value;
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: isSelected ? color.withOpacity(0.15) : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () {
            if (mounted) setState(() {
              _selectedTypeFilter = isSelected ? null : value;
              _applyFilters();
            });
            Navigator.pop(context);
          },
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(
                color: isSelected ? color : Colors.white.withOpacity(0.1),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? color : Colors.white.withOpacity(0.8),
                  ),
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                if (isSelected) ...[
                  SizedBox(width: 8),
                  Icon(Icons.check_circle, color: color, size: 22),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveFiltersBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_alt, size: 18, color: Colors.white.withOpacity(0.5)),
          SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_searchQuery.isNotEmpty)
                    _buildFilterChip(
                      label: 'Поиск: "$_searchQuery"',
                      onRemove: () {
                        _searchController.clear();
                        if (mounted) setState(() {
                          _searchQuery = '';
                          _applyFilters();
                        });
                      },
                    ),
                  if (_selectedTypeFilter != null)
                    _buildFilterChip(
                      label: 'Тип: ${_getTypeFilterLabel(_selectedTypeFilter!)}',
                      color: _getTypeFilterColor(_selectedTypeFilter!),
                      onRemove: () {
                        if (mounted) setState(() {
                          _selectedTypeFilter = null;
                          _applyFilters();
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          SizedBox(width: 8),
          Text(
            '${_filteredQuestions.length} из ${_questions.length}',
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

  Widget _buildFilterChip({
    required String label,
    required VoidCallback onRemove,
    Color? color,
  }) {
    return Container(
      margin: EdgeInsets.only(right: 8.w),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color?.withOpacity(0.15) ?? AppColors.gold.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: color?.withOpacity(0.3) ?? AppColors.gold.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: color ?? AppColors.gold,
            ),
          ),
          SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 16,
              color: color ?? AppColors.gold,
            ),
          ),
        ],
      ),
    );
  }

  String _getTypeFilterLabel(String type) {
    switch (type) {
      case 'photo':
        return 'Фото';
      case 'yesno':
        return 'Да/Нет';
      case 'number':
        return 'Число';
      case 'text':
        return 'Текст';
      default:
        return type;
    }
  }

  Color _getTypeFilterColor(String type) {
    switch (type) {
      case 'photo':
        return Color(0xFF7B1FA2);
      case 'yesno':
        return Color(0xFF0288D1);
      case 'number':
        return Color(0xFFE65100);
      case 'text':
        return Color(0xFF2E7D32);
      default:
        return AppColors.gold;
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
              // Custom AppBar
              _buildCustomAppBar(),
              // Контент
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddQuestionDialog,
        backgroundColor: AppColors.gold,
        elevation: 0,
        icon: Icon(Icons.add_rounded, color: AppColors.night),
        label: Text(
          'Добавить',
          style: TextStyle(
            color: AppColors.night,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 0.h),
      child: Column(
        children: [
          Row(
            children: [
              // Кнопка назад
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
              // Заголовок
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Вопросы сдачи смены',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_questions.length} вопросов',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13.sp,
                      ),
                    ),
                  ],
                ),
              ),
              // Кнопки действий
              _buildActionButton(
                icon: Icons.filter_list,
                onPressed: _showFilterDialog,
                tooltip: 'Фильтр',
                hasActiveFilter: _selectedTypeFilter != null,
              ),
              SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.refresh,
                onPressed: _loadQuestions,
                tooltip: 'Обновить',
              ),
            ],
          ),
          SizedBox(height: 16),
          // Поле поиска
          Container(
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
                hintText: 'Поиск по вопросам...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, color: Colors.white.withOpacity(0.5), size: 20),
                        onPressed: () {
                          _searchController.clear();
                          if (mounted) setState(() {
                            _searchQuery = '';
                            _applyFilters();
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              ),
              cursorColor: AppColors.gold,
              onChanged: (value) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    setState(() {
                      _searchQuery = value;
                      _applyFilters();
                    });
                  }
                });
              },
            ),
          ),
          SizedBox(height: 16),
          // Статистика по типам
          _buildTypeStatsRow(),
          SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    bool hasActiveFilter = false,
  }) {
    return Stack(
      children: [
        Container(
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
        ),
        if (hasActiveFilter)
          Positioned(
            top: 6.h,
            right: 6.w,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.gold,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.emeraldDark, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTypeStatsRow() {
    final yesNoCount = _questions.where((q) => q.isYesNo).length;
    final photoCount = _questions.where((q) => q.isPhotoOnly).length;
    final numberCount = _questions.where((q) => q.isNumberOnly).length;
    final textCount = _questions.where((q) => !q.isPhotoOnly && !q.isYesNo && !q.isNumberOnly).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildTypeChip(
            icon: Icons.check_circle_outline,
            label: 'Да/Нет',
            count: yesNoCount,
            color: Color(0xFF0288D1),
            isSelected: _selectedTypeFilter == 'yesno',
            onTap: () => _toggleTypeFilter('yesno'),
          ),
          SizedBox(width: 8),
          _buildTypeChip(
            icon: Icons.camera_alt_outlined,
            label: 'Фото',
            count: photoCount,
            color: Color(0xFF7B1FA2),
            isSelected: _selectedTypeFilter == 'photo',
            onTap: () => _toggleTypeFilter('photo'),
          ),
          SizedBox(width: 8),
          _buildTypeChip(
            icon: Icons.tag,
            label: 'Число',
            count: numberCount,
            color: Color(0xFFE65100),
            isSelected: _selectedTypeFilter == 'number',
            onTap: () => _toggleTypeFilter('number'),
          ),
          SizedBox(width: 8),
          _buildTypeChip(
            icon: Icons.text_fields,
            label: 'Текст',
            count: textCount,
            color: Color(0xFF2E7D32),
            isSelected: _selectedTypeFilter == 'text',
            onTap: () => _toggleTypeFilter('text'),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.gold.withOpacity(0.2) : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20.r),
          border: isSelected ? Border.all(color: AppColors.gold, width: 1.5) : Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.7),
            ),
            SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleTypeFilter(String type) {
    if (mounted) setState(() {
      if (_selectedTypeFilter == type) {
        _selectedTypeFilter = null;
      } else {
        _selectedTypeFilter = type;
      }
      _applyFilters();
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (mounted) setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _questions.removeAt(oldIndex);
      _questions.insert(newIndex, item);
      _applyFilters();
    });

    // Отправляем новый порядок на сервер
    final orders = <Map<String, dynamic>>[];
    for (var i = 0; i < _questions.length; i++) {
      orders.add({'id': _questions[i].id, 'order': i + 1});
    }
    ShiftQuestionService.reorderQuestions(orders).then((success) {
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Порядок сохранён', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green[700],
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  Widget _buildContent() {
    if (_isLoading) {
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
              'Загрузка вопросов...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14.sp,
              ),
            ),
          ],
        ),
      );
    }

    if (_questions.isEmpty) {
      return _buildEmptyState();
    }

    if (_filteredQuestions.isEmpty) {
      return _buildNoResultsState();
    }

    final bool hasActiveFilter = _selectedTypeFilter != null || _searchQuery.isNotEmpty;

    return Column(
      children: [
        // Показать активные фильтры
        if (hasActiveFilter)
          _buildActiveFiltersBar(),
        // Список вопросов
        Expanded(
          child: hasActiveFilter
              // При активном фильтре — обычный список (без drag-and-drop)
              ? ListView.builder(
                  padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 100.h),
                  itemCount: _filteredQuestions.length,
                  itemBuilder: (context, index) {
                    final question = _filteredQuestions[index];
                    final originalIndex = _questions.indexOf(question);
                    return _buildQuestionCard(question, originalIndex, showDragHandle: false);
                  },
                )
              // Без фильтра — drag-and-drop для изменения порядка
              : ReorderableListView.builder(
                  padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 100.h),
                  itemCount: _filteredQuestions.length,
                  proxyDecorator: (child, index, animation) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, child) {
                        final animValue = Curves.easeInOut.transform(animation.value);
                        final elevation = 4.0 + animValue * 8.0;
                        final scale = 1.0 + animValue * 0.02;
                        return Transform.scale(
                          scale: scale,
                          child: Material(
                            color: Colors.transparent,
                            elevation: elevation,
                            shadowColor: AppColors.gold.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(14.r),
                            child: child,
                          ),
                        );
                      },
                      child: child,
                    );
                  },
                  onReorder: _onReorder,
                  itemBuilder: (context, index) {
                    final question = _filteredQuestions[index];
                    return _buildQuestionCard(
                      question, index,
                      key: ValueKey(question.id),
                      showDragHandle: true,
                    );
                  },
                ),
        ),
      ],
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
              Icons.question_answer_outlined,
              size: 56,
              color: AppColors.gold.withOpacity(0.6),
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Нет вопросов',
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 48.w),
            child: Text(
              'Нажмите кнопку "Добавить"\nчтобы создать первый вопрос',
              style: TextStyle(
                fontSize: 15.sp,
                color: Colors.white.withOpacity(0.5),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Ничего не найдено',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Попробуйте изменить параметры поиска',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          SizedBox(height: 20),
          TextButton.icon(
            onPressed: () {
              _searchController.clear();
              if (mounted) setState(() {
                _searchQuery = '';
                _selectedTypeFilter = null;
                _applyFilters();
              });
            },
            icon: Icon(Icons.refresh),
            label: Text('Сбросить фильтры'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.gold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(ShiftQuestion question, int index, {Key? key, bool showDragHandle = false}) {
    final Color typeColor = _getAnswerTypeColor(question);

    return Container(
      key: key,
      margin: EdgeInsets.only(bottom: 12.h),
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
          onTap: () => _showEditQuestionDialog(question),
          splashColor: typeColor.withOpacity(0.08),
          child: Column(
            children: [
              // Верхняя часть карточки
              Padding(
                padding: EdgeInsets.fromLTRB(showDragHandle ? 4 : 16, 14, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle (только без фильтра)
                    if (showDragHandle)
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: EdgeInsets.only(right: 4.w, top: 6.h),
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: Colors.white.withOpacity(0.3),
                            size: 22,
                          ),
                        ),
                      ),
                    // Номер вопроса
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [typeColor, typeColor.withOpacity(0.8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16.sp,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    // Контент
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Тип ответа
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                            decoration: BoxDecoration(
                              color: typeColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20.r),
                              border: Border.all(
                                color: typeColor.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getAnswerTypeIcon(question),
                                  size: 14,
                                  color: typeColor,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  _getAnswerTypeLabel(question),
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w600,
                                    color: typeColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 10),
                          // Текст вопроса
                          Text(
                            question.question,
                            style: TextStyle(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.9),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8),
                    // Кнопки действий
                    Column(
                      children: [
                        _buildCardActionButton(
                          icon: Icons.edit_rounded,
                          color: AppColors.gold,
                          onTap: () => _showEditQuestionDialog(question),
                        ),
                        SizedBox(height: 6),
                        _buildCardActionButton(
                          icon: Icons.delete_outline_rounded,
                          color: Colors.red[400]!,
                          onTap: () => _deleteQuestion(question),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Метаданные внизу
              if ((question.shops != null && question.shops!.isNotEmpty) ||
                  (question.isPhotoOnly && question.referencePhotos != null && question.referencePhotos!.isNotEmpty))
                Container(
                  padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 12.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(14.r),
                      bottomRight: Radius.circular(14.r),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Магазины
                      if (question.shops != null && question.shops!.isNotEmpty)
                        _buildMetadataBadge(
                          icon: Icons.store_rounded,
                          text: '${question.shops!.length} магазин${_getShopEnding(question.shops!.length)}',
                          color: Colors.amber[700]!,
                          bgColor: Colors.amber.withOpacity(0.12),
                        ),
                      if (question.shops != null && question.shops!.isNotEmpty &&
                          question.isPhotoOnly && question.referencePhotos != null && question.referencePhotos!.isNotEmpty)
                        SizedBox(width: 10),
                      // Эталонные фото
                      if (question.isPhotoOnly && question.referencePhotos != null && question.referencePhotos!.isNotEmpty)
                        _buildMetadataBadge(
                          icon: Icons.photo_library_rounded,
                          text: '${question.referencePhotos!.length} эталон${_getPhotoEnding(question.referencePhotos!.length)}',
                          color: Colors.green[700]!,
                          bgColor: Colors.green.withOpacity(0.12),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.r),
      child: Container(
        padding: EdgeInsets.all(8.w),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  Widget _buildMetadataBadge({
    required IconData icon,
    required String text,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: color.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 13.sp,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _getShopEnding(int count) {
    if (count == 1) return '';
    if (count >= 2 && count <= 4) return 'а';
    return 'ов';
  }

  String _getPhotoEnding(int count) {
    if (count == 1) return '';
    if (count >= 2 && count <= 4) return 'а';
    return 'ов';
  }

  Color _getAnswerTypeColor(ShiftQuestion question) {
    if (question.isPhotoOnly) return Color(0xFF7B1FA2); // Purple
    if (question.isYesNo) return Color(0xFF0288D1); // Blue
    if (question.isNumberOnly) return Color(0xFFE65100); // Orange
    return Color(0xFF2E7D32); // Green for text
  }
}

/// Диалог для добавления/редактирования вопроса
class ShiftQuestionFormDialog extends StatefulWidget {
  final ShiftQuestion? question;

  const ShiftQuestionFormDialog({super.key, this.question});

  @override
  State<ShiftQuestionFormDialog> createState() => _ShiftQuestionFormDialogState();
}

class _ShiftQuestionFormDialogState extends State<ShiftQuestionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  String? _selectedAnswerType; // 'photo', 'yesno', 'number', 'text'
  bool _isSaving = false;
  bool _isForAllShops = false; // Задавать всем магазинам
  bool _isAiCheck = false; // Проверять ли ИИ фото этого вопроса
  List<Shop> _allShops = [];
  Set<String> _selectedShopAddresses = {}; // Выбранные адреса магазинов
  Map<String, String> _referencePhotoUrls = {}; // URL эталонных фото для каждого магазина
  final Map<String, File?> _referencePhotoFiles = {}; // Локальные файлы эталонных фото
  bool _isLoadingShops = true;
  bool _isUploadingPhotos = false;

  @override
  void initState() {
    super.initState();
    if (widget.question != null) {
      _questionController.text = widget.question!.question;
      // Определяем тип ответа из существующего вопроса
      if (widget.question!.isPhotoOnly) {
        _selectedAnswerType = 'photo';
      } else if (widget.question!.isYesNo) {
        _selectedAnswerType = 'yesno';
      } else if (widget.question!.isNumberOnly) {
        _selectedAnswerType = 'number';
      } else {
        _selectedAnswerType = 'text';
      }

      // Загружаем выбранные магазины и эталонные фото
      if (widget.question!.shops == null) {
        _isForAllShops = true;
      } else {
        _selectedShopAddresses = widget.question!.shops!.toSet();
      }

      if (widget.question!.referencePhotos != null) {
        _referencePhotoUrls = Map<String, String>.from(widget.question!.referencePhotos!);
      }

      // Загружаем флаг ИИ проверки
      _isAiCheck = widget.question!.isAiCheck;
    } else {
      _selectedAnswerType = 'text'; // По умолчанию текст
    }
    _loadShops();
  }

  Future<void> _loadShops() async {
    try {
      if (mounted) setState(() => _isLoadingShops = true);
      final shops = await Shop.loadShopsFromServer();
      if (!mounted) return;
      setState(() {
        _allShops = shops;
        _isLoadingShops = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingShops = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки магазинов: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickReferencePhoto(String shopAddress) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image != null) {
        // Создаем веб-совместимый файл
        final File photoFile;
        if (kIsWeb) {
          // На веб создаем файл из байтов
          final bytes = await image.readAsBytes();
          photoFile = _XFileWrapper(image.path, bytes);
        } else {
          // На мобильных используем обычный File
          photoFile = File(image.path);
        }

        if (!mounted) return;
        setState(() {
          _referencePhotoFiles[shopAddress] = photoFile;
        });

        // Загружаем фото на сервер, если вопрос уже создан
        if (widget.question != null) {
          await _uploadReferencePhoto(widget.question!.id, shopAddress, photoFile);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора фото: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadReferencePhoto(String questionId, String shopAddress, File photoFile) async {
    try {
      if (mounted) setState(() => _isUploadingPhotos = true);

      final photoUrl = await ShiftQuestionService.uploadReferencePhoto(
        questionId: questionId,
        shopAddress: shopAddress,
        photoFile: photoFile,
      );

      if (photoUrl != null) {
        if (!mounted) return;
        setState(() {
          _referencePhotoUrls[shopAddress] = photoUrl;
        });

        // КРИТИЧЕСКИ ВАЖНО: Обновляем вопрос с новым URL эталонного фото
        Logger.info('Обновление вопроса с новым эталонным фото: $questionId');
        Logger.debug('   Магазин: $shopAddress');
        Logger.debug('   URL фото: $photoUrl');

        final updatedQuestion = await ShiftQuestionService.updateQuestion(
          id: questionId,
          referencePhotos: _referencePhotoUrls,
        );

        if (updatedQuestion != null) {
          Logger.success('Вопрос успешно обновлен с эталонным фото');
          if (mounted) setState(() => _isUploadingPhotos = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Эталонное фото успешно загружено'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          Logger.error('Не удалось обновить вопрос с эталонным фото');
          if (mounted) setState(() => _isUploadingPhotos = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Фото загружено, но не удалось обновить вопрос'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        if (mounted) setState(() => _isUploadingPhotos = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка загрузки эталонного фото'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('Исключение при загрузке эталонного фото', e);
      if (mounted) setState(() => _isUploadingPhotos = false);
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

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (mounted) setState(() {
      _isSaving = true;
    });

    try {
      String? answerFormatB;
      String? answerFormatC;

      // Устанавливаем формат ответа в зависимости от выбранного типа
      switch (_selectedAnswerType) {
        case 'photo':
          answerFormatB = 'photo';
          answerFormatC = null;
          break;
        case 'yesno':
          answerFormatB = null;
          answerFormatC = null;
          break;
        case 'number':
          answerFormatB = null;
          answerFormatC = 'число';
          break;
        case 'text':
        default:
          // Для текста устанавливаем 'text', чтобы не конфликтовать с isYesNo
          // isTextOnly вернет true, так как не соответствует другим типам
          answerFormatB = 'text';
          answerFormatC = null;
          break;
      }

      // Определяем shops: null если для всех, иначе список выбранных адресов
      List<String>? shops = _isForAllShops ? null : _selectedShopAddresses.toList();

      // Для нового вопроса сначала создаем вопрос, затем загружаем фото
      ShiftQuestion? result;
      if (widget.question != null) {
        // Обновление существующего вопроса
        result = await ShiftQuestionService.updateQuestion(
          id: widget.question!.id,
          question: _questionController.text.trim(),
          answerFormatB: answerFormatB,
          answerFormatC: answerFormatC,
          shops: shops,
          referencePhotos: _referencePhotoUrls.isNotEmpty ? _referencePhotoUrls : null,
          isAiCheck: _selectedAnswerType == 'photo' ? _isAiCheck : false,
        );

        // Загружаем новые эталонные фото, если есть
        if (result != null && _selectedAnswerType == 'photo') {
          for (final entry in _referencePhotoFiles.entries) {
            if (entry.value != null && !_referencePhotoUrls.containsKey(entry.key)) {
              await _uploadReferencePhoto(result.id, entry.key, entry.value!);
            }
          }
          // Перезагружаем вопрос с обновленными фото
          final updatedResult = await ShiftQuestionService.getQuestion(result.id);
          if (updatedResult != null) {
            result = updatedResult;
          }
        }
      } else {
        // Создание нового вопроса
        result = await ShiftQuestionService.createQuestion(
          question: _questionController.text.trim(),
          answerFormatB: answerFormatB,
          answerFormatC: answerFormatC,
          shops: shops,
          referencePhotos: null, // Фото загрузим отдельно
          isAiCheck: _selectedAnswerType == 'photo' ? _isAiCheck : false,
        );

        // Загружаем эталонные фото для нового вопроса
        if (result != null && _selectedAnswerType == 'photo') {
          final Map<String, String> uploadedPhotos = {};
          for (final entry in _referencePhotoFiles.entries) {
            if (entry.value != null) {
              final photoUrl = await ShiftQuestionService.uploadReferencePhoto(
                questionId: result.id,
                shopAddress: entry.key,
                photoFile: entry.value!,
              );
              if (photoUrl != null) {
                uploadedPhotos[entry.key] = photoUrl;
              }
            }
          }

          // Обновляем вопрос с загруженными фото
          if (uploadedPhotos.isNotEmpty) {
            final updatedResult = await ShiftQuestionService.updateQuestion(
              id: result.id,
              referencePhotos: uploadedPhotos,
            );
            if (updatedResult != null) {
              result = updatedResult;
            }
          }
        }
      }

      if (result != null && mounted) {
        Navigator.pop(context, result);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка сохранения вопроса'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.question != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: AppColors.emeraldDark,
          borderRadius: BorderRadius.circular(24.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Красивый заголовок
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.emerald, AppColors.emeraldDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24.r),
                  topRight: Radius.circular(24.r),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Icon(
                      isEditing ? Icons.edit_note : Icons.add_circle_outline,
                      color: AppColors.gold,
                      size: 28,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing ? 'Редактировать вопрос' : 'Новый вопрос',
                          style: TextStyle(
                            fontSize: 22.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          isEditing ? 'Измените параметры вопроса' : 'Заполните все поля',
                          style: TextStyle(
                            fontSize: 14.sp,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20.w),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Секция: Текст вопроса
                      _buildSectionHeader(
                        icon: Icons.help_outline,
                        title: 'Текст вопроса',
                        color: AppColors.gold,
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: _questionController,
                        decoration: InputDecoration(
                          hintText: 'Введите текст вопроса...',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14.r),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14.r),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14.r),
                            borderSide: BorderSide(color: AppColors.gold, width: 2),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14.r),
                            borderSide: BorderSide(color: Colors.red, width: 1),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14.r),
                            borderSide: BorderSide(color: Colors.red, width: 2),
                          ),
                          contentPadding: EdgeInsets.all(16.w),
                        ),
                        maxLines: 3,
                        style: TextStyle(fontSize: 16.sp, height: 1.4, color: Colors.white.withOpacity(0.9)),
                        cursorColor: AppColors.gold,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Пожалуйста, введите текст вопроса';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 28),
                      // Секция: Тип ответа
                      _buildSectionHeader(
                        icon: Icons.format_list_bulleted,
                        title: 'Тип ответа',
                        color: Color(0xFF7B1FA2),
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildAnswerTypeOption(
                              icon: Icons.camera_alt_outlined,
                              label: 'Фото',
                              value: 'photo',
                              color: Color(0xFF7B1FA2),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: _buildAnswerTypeOption(
                              icon: Icons.check_circle_outline,
                              label: 'Да/Нет',
                              value: 'yesno',
                              color: Color(0xFF0288D1),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildAnswerTypeOption(
                              icon: Icons.tag,
                              label: 'Число',
                              value: 'number',
                              color: Color(0xFFE65100),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: _buildAnswerTypeOption(
                              icon: Icons.text_fields,
                              label: 'Текст',
                              value: 'text',
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 28),
                      // Секция: Магазины
                      _buildSectionHeader(
                        icon: Icons.store_mall_directory_outlined,
                        title: 'Магазины',
                        color: Color(0xFFEF6C00),
                      ),
                      SizedBox(height: 12),
                      if (_isLoadingShops)
                        Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.w),
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                            ),
                          ),
                        )
                      else ...[
                        // Переключатель "Все магазины"
                        Container(
                          decoration: BoxDecoration(
                            color: _isForAllShops ? AppColors.gold.withOpacity(0.1) : Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(
                              color: _isForAllShops ? AppColors.gold.withOpacity(0.3) : Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: CheckboxListTile(
                            title: Text(
                              'Задавать всем магазинам',
                              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.9)),
                            ),
                            subtitle: Text(
                              'Вопрос будет задан на всех точках',
                              style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.5)),
                            ),
                            value: _isForAllShops,
                            onChanged: (value) {
                              if (mounted) setState(() {
                                _isForAllShops = value ?? false;
                                if (_isForAllShops) {
                                  _selectedShopAddresses.clear();
                                }
                              });
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: AppColors.gold,
                            checkColor: AppColors.night,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14.r),
                            ),
                          ),
                        ),
                        if (!_isForAllShops) ...[
                          SizedBox(height: 12),
                          Container(
                            constraints: BoxConstraints(maxHeight: 200),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                              borderRadius: BorderRadius.circular(14.r),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14.r),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _allShops.length,
                                itemBuilder: (context, index) {
                                  final shop = _allShops[index];
                                  final isSelected = _selectedShopAddresses.contains(shop.address);
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppColors.gold.withOpacity(0.08) : Colors.transparent,
                                      border: Border(
                                        bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
                                      ),
                                    ),
                                    child: CheckboxListTile(
                                      title: Text(
                                        shop.name,
                                        style: TextStyle(
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                          color: Colors.white.withOpacity(0.9),
                                        ),
                                      ),
                                      subtitle: Text(
                                        shop.address,
                                        style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5)),
                                      ),
                                      value: isSelected,
                                      onChanged: (value) {
                                        if (mounted) setState(() {
                                          if (value ?? false) {
                                            _selectedShopAddresses.add(shop.address);
                                          } else {
                                            _selectedShopAddresses.remove(shop.address);
                                            _referencePhotoFiles.remove(shop.address);
                                            _referencePhotoUrls.remove(shop.address);
                                          }
                                        });
                                      },
                                      controlAffinity: ListTileControlAffinity.leading,
                                      activeColor: AppColors.gold,
                                      checkColor: AppColors.night,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          if (_selectedShopAddresses.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 8.h),
                              child: Text(
                                'Выбрано: ${_selectedShopAddresses.length} магазин(ов)',
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: Colors.white.withOpacity(0.5),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                        // Проверка ИИ (только для вопросов с фото)
                        if (_selectedAnswerType == 'photo') ...[
                          SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              color: _isAiCheck
                                  ? AppColors.warning.withOpacity(0.1)
                                  : Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                color: _isAiCheck
                                    ? AppColors.warning
                                    : Colors.white.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            child: CheckboxListTile(
                              value: _isAiCheck,
                              onChanged: (value) {
                                if (mounted) setState(() => _isAiCheck = value ?? false);
                              },
                              title: Text(
                                'Проверка ИИ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15.sp,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                              subtitle: Text(
                                'ИИ будет проверять товары на фото этого вопроса при пересменке',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                              activeColor: AppColors.warning,
                              checkColor: AppColors.night,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              secondary: Icon(
                                Icons.psychology,
                                color: _isAiCheck
                                    ? AppColors.warning
                                    : Colors.white.withOpacity(0.4),
                              ),
                            ),
                          ),
                        ],

                        // Эталонные фото (только для вопросов с фото)
                        if (_selectedAnswerType == 'photo') ...[
                          SizedBox(height: 28),
                          _buildSectionHeader(
                            icon: Icons.photo_library_outlined,
                            title: 'Эталонные фото',
                            color: Color(0xFF388E3C),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Добавьте образцы, чтобы сотрудники знали, как должно выглядеть фото',
                            style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.5)),
                          ),
                          SizedBox(height: 12),
                          if (_isForAllShops)
                            ..._allShops.map((shop) => _buildReferencePhotoSection(shop.address, shop.name))
                          else
                            ..._selectedShopAddresses.map((address) {
                              final shop = _allShops.firstWhere(
                                (s) => s.address == address,
                                orElse: () => Shop(
                                  id: '',
                                  name: address,
                                  address: address,
                                  icon: Icons.store,
                                ),
                              );
                              return _buildReferencePhotoSection(address, shop.name);
                            }),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Красивые кнопки действий
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24.r),
                  bottomRight: Radius.circular(24.r),
                ),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Text(
                        'Отмена',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveQuestion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.night,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.night),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isEditing ? Icons.save : Icons.add_circle,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  isEditing ? 'Сохранить' : 'Добавить',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildAnswerTypeOption({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    final isSelected = _selectedAnswerType == value;
    final cardColor = color ?? AppColors.gold;

    return GestureDetector(
      onTap: () {
        if (mounted) setState(() {
          _selectedAnswerType = value;
        });
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 12.w),
        decoration: BoxDecoration(
          color: isSelected ? cardColor.withOpacity(0.15) : Colors.white.withOpacity(0.06),
          border: Border.all(
            color: isSelected ? cardColor : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14.r),
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: Duration(milliseconds: 200),
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: isSelected ? cardColor.withOpacity(0.2) : Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? cardColor : Colors.white.withOpacity(0.5),
                size: 28,
              ),
            ),
            SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? cardColor : Colors.white.withOpacity(0.7),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13.sp,
              ),
            ),
            if (isSelected)
              Padding(
                padding: EdgeInsets.only(top: 6.h),
                child: Container(
                  width: 20,
                  height: 3,
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferencePhotoSection(String shopAddress, String shopName) {
    final hasPhoto = _referencePhotoUrls.containsKey(shopAddress) ||
                     _referencePhotoFiles.containsKey(shopAddress);
    final photoFile = _referencePhotoFiles[shopAddress];
    final photoUrl = _referencePhotoUrls[shopAddress];

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок магазина
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(Icons.store, size: 18, color: Colors.orange[700]),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    shopName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),
                if (hasPhoto)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 14, color: Colors.green[600]),
                        SizedBox(width: 4),
                        Text(
                          'Загружено',
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[600],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            SizedBox(height: 12),
            // Превью фото или кнопка добавления
            if (hasPhoto) ...[
              Stack(
                children: [
                  Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12.r),
                      child: photoFile != null
                          ? kIsWeb
                              ? AppCachedImage(
                                  imageUrl: photoFile.path,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, error, stackTrace) {
                                    return Center(
                                      child: Icon(Icons.error_outline, size: 40, color: Colors.red[300]),
                                    );
                                  },
                                )
                              : Image.file(
                                  photoFile,
                                  fit: BoxFit.cover,
                                )
                          : photoUrl != null
                              ? AppCachedImage(
                                  imageUrl: photoUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, error, stackTrace) {
                                    return Center(
                                      child: Icon(Icons.error_outline, size: 40, color: Colors.red[300]),
                                    );
                                  },
                                )
                              : Center(child: Icon(Icons.image, size: 40, color: Colors.white.withOpacity(0.3))),
                    ),
                  ),
                  // Кнопки поверх фото
                  Positioned(
                    top: 8.h,
                    right: 8.w,
                    child: Row(
                      children: [
                        _buildPhotoActionButton(
                          icon: Icons.refresh,
                          onPressed: _isUploadingPhotos ? null : () => _pickReferencePhoto(shopAddress),
                          tooltip: 'Заменить',
                        ),
                        SizedBox(width: 6),
                        _buildPhotoActionButton(
                          icon: Icons.delete_outline,
                          onPressed: () {
                            if (mounted) setState(() {
                              _referencePhotoFiles.remove(shopAddress);
                              _referencePhotoUrls.remove(shopAddress);
                            });
                          },
                          tooltip: 'Удалить',
                          isDestructive: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Зона добавления фото
              InkWell(
                onTap: _isUploadingPhotos ? null : () => _pickReferencePhoto(shopAddress),
                borderRadius: BorderRadius.circular(12.r),
                child: Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 36,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Добавить эталонное фото',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: Colors.white.withOpacity(0.5),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoActionButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    bool isDestructive = false,
  }) {
    return Material(
      color: isDestructive ? Colors.red[900]!.withOpacity(0.8) : AppColors.emeraldDark.withOpacity(0.9),
      borderRadius: BorderRadius.circular(8.r),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8.r),
        child: Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isDestructive ? Colors.red[300] : Colors.white.withOpacity(0.8),
          ),
        ),
      ),
    );
  }
}

/// Класс-обертка для работы с XFile на веб-платформе
/// Имитирует интерфейс File, но хранит данные в памяти
class _XFileWrapper implements File {
  final String _path;
  final Uint8List _bytes;

  _XFileWrapper(String path, List<int> bytes)
      : _path = path,
        _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  @override
  String get path => _path;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Uint8List readAsBytesSync() => _bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

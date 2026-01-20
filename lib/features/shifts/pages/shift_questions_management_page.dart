import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/shift_question_model.dart';
import '../services/shift_question_service.dart';
import '../../shops/models/shop_model.dart';
import '../../../core/utils/logger.dart';

/// Страница управления вопросами пересменки
class ShiftQuestionsManagementPage extends StatefulWidget {
  const ShiftQuestionsManagementPage({super.key});

  @override
  State<ShiftQuestionsManagementPage> createState() => _ShiftQuestionsManagementPageState();
}

class _ShiftQuestionsManagementPageState extends State<ShiftQuestionsManagementPage> {
  // Цвета для современного дизайна
  static const _primaryColor = Color(0xFF004D40);
  static const _gradientStart = Color(0xFF00695C);
  static const _gradientEnd = Color(0xFF004D40);

  List<ShiftQuestion> _questions = [];
  List<ShiftQuestion> _filteredQuestions = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedTypeFilter;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
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
    setState(() {
      _isLoading = true;
    });

    try {
      final questions = await ShiftQuestionService.getQuestions();
      setState(() {
        _questions = questions;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
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
      builder: (context) => const ShiftQuestionFormDialog(),
    );

    if (result != null) {
      await _loadQuestions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Вопрос успешно добавлен'),
              ],
            ),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
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
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Вопрос успешно обновлен'),
              ],
            ),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
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
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Иконка предупреждения
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red[400]!, Colors.red[600]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delete_forever_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Удалить вопрос?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Контент
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Text(
                        question.question,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Это действие невозможно отменить',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              // Кнопки
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                        child: Text(
                          'Отмена',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[500],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Удалить',
                          style: TextStyle(
                            fontSize: 15,
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
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Вопрос успешно удален'),
                ],
              ),
              backgroundColor: Colors.green[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Ошибка удаления вопроса'),
                ],
              ),
              backgroundColor: Colors.red[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(16),
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
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF004D40).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.filter_list,
                    color: Color(0xFF004D40),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Фильтр по типу ответа',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_selectedTypeFilter != null)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedTypeFilter = null;
                        _applyFilters();
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Сбросить'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // Опции фильтра
            _buildFilterOption(
              icon: Icons.check_circle,
              label: 'Да/Нет',
              value: 'yesno',
              color: const Color(0xFF0288D1),
              count: _questions.where((q) => q.isYesNo).length,
            ),
            _buildFilterOption(
              icon: Icons.numbers,
              label: 'Число',
              value: 'number',
              color: const Color(0xFFE65100),
              count: _questions.where((q) => q.isNumberOnly).length,
            ),
            _buildFilterOption(
              icon: Icons.camera_alt,
              label: 'Фото',
              value: 'photo',
              color: const Color(0xFF7B1FA2),
              count: _questions.where((q) => q.isPhotoOnly).length,
            ),
            _buildFilterOption(
              icon: Icons.text_fields,
              label: 'Текст',
              value: 'text',
              color: const Color(0xFF2E7D32),
              count: _questions.where((q) => !q.isPhotoOnly && !q.isYesNo && !q.isNumberOnly).length,
            ),
            const SizedBox(height: 10),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? color.withOpacity(0.12) : Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            setState(() {
              _selectedTypeFilter = isSelected ? null : value;
              _applyFilters();
            });
            Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? color : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? color : Colors.grey[800],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
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
                  const SizedBox(width: 8),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_alt, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
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
                        setState(() {
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
                        setState(() {
                          _selectedTypeFilter = null;
                          _applyFilters();
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_filteredQuestions.length} из ${_questions.length}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
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
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color?.withOpacity(0.15) ?? const Color(0xFF004D40).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color?.withOpacity(0.3) ?? const Color(0xFF004D40).withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color ?? const Color(0xFF004D40),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 16,
              color: color ?? const Color(0xFF004D40),
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
        return const Color(0xFF7B1FA2);
      case 'yesno':
        return const Color(0xFF0288D1);
      case 'number':
        return const Color(0xFFE65100);
      case 'text':
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF004D40);
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
                    child: _buildContent(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddQuestionDialog,
        backgroundColor: _primaryColor,
        elevation: 4,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'Добавить',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        children: [
          Row(
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
                      'Вопросы сдачи смены',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_questions.length} вопросов',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
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
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.refresh,
                onPressed: _loadQuestions,
                tooltip: 'Обновить',
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Поле поиска
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Поиск по вопросам...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.7)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, color: Colors.white.withOpacity(0.7), size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _applyFilters();
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              cursorColor: Colors.white,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _applyFilters();
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          // Статистика по типам
          _buildTypeStatsRow(),
          const SizedBox(height: 16),
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
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 20),
            onPressed: onPressed,
            tooltip: tooltip,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ),
        if (hasActiveFilter)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
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
            color: const Color(0xFF0288D1),
            isSelected: _selectedTypeFilter == 'yesno',
            onTap: () => _toggleTypeFilter('yesno'),
          ),
          const SizedBox(width: 8),
          _buildTypeChip(
            icon: Icons.camera_alt_outlined,
            label: 'Фото',
            count: photoCount,
            color: const Color(0xFF7B1FA2),
            isSelected: _selectedTypeFilter == 'photo',
            onTap: () => _toggleTypeFilter('photo'),
          ),
          const SizedBox(width: 8),
          _buildTypeChip(
            icon: Icons.tag,
            label: 'Число',
            count: numberCount,
            color: const Color(0xFFE65100),
            isSelected: _selectedTypeFilter == 'number',
            onTap: () => _toggleTypeFilter('number'),
          ),
          const SizedBox(width: 8),
          _buildTypeChip(
            icon: Icons.text_fields,
            label: 'Текст',
            count: textCount,
            color: const Color(0xFF2E7D32),
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
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: isSelected ? Border.all(color: color, width: 2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? color : Colors.white.withOpacity(0.9),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelected ? color : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleTypeFilter(String type) {
    setState(() {
      if (_selectedTypeFilter == type) {
        _selectedTypeFilter = null;
      } else {
        _selectedTypeFilter = type;
      }
      _applyFilters();
    });
  }

  Widget _buildContent() {
    if (_isLoading) {
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
              'Загрузка вопросов...',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
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

    return Column(
      children: [
        // Показать активные фильтры
        if (_selectedTypeFilter != null || _searchQuery.isNotEmpty)
          _buildActiveFiltersBar(),
        // Список вопросов
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: _filteredQuestions.length,
            itemBuilder: (context, index) {
              final question = _filteredQuestions[index];
              final originalIndex = _questions.indexOf(question);
              return _buildQuestionCard(question, originalIndex);
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
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.1),
                  blurRadius: 30,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.question_answer_outlined,
              size: 56,
              color: _primaryColor.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Нет вопросов',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Нажмите кнопку "Добавить"\nчтобы создать первый вопрос',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[600],
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
              Icons.search_off_rounded,
              size: 48,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Ничего не найдено',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Попробуйте изменить параметры поиска',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _selectedTypeFilter = null;
                _applyFilters();
              });
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Сбросить фильтры'),
            style: TextButton.styleFrom(
              foregroundColor: _primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(ShiftQuestion question, int index) {
    final Color typeColor = _getAnswerTypeColor(question);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: typeColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showEditQuestionDialog(question),
          splashColor: typeColor.withOpacity(0.08),
          child: Column(
            children: [
              // Верхняя часть карточки
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: typeColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Контент
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Тип ответа
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: typeColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: typeColor.withOpacity(0.2),
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
                                const SizedBox(width: 6),
                                Text(
                                  _getAnswerTypeLabel(question),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: typeColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Текст вопроса
                          Text(
                            question.question,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1A1A1A),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Кнопки действий
                    Column(
                      children: [
                        _buildCardActionButton(
                          icon: Icons.edit_rounded,
                          color: _primaryColor,
                          onTap: () => _showEditQuestionDialog(question),
                        ),
                        const SizedBox(height: 6),
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
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
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
                        const SizedBox(width: 10),
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
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
    if (question.isPhotoOnly) return const Color(0xFF7B1FA2); // Purple
    if (question.isYesNo) return const Color(0xFF0288D1); // Blue
    if (question.isNumberOnly) return const Color(0xFFE65100); // Orange
    return const Color(0xFF2E7D32); // Green for text
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
  List<Shop> _allShops = [];
  Set<String> _selectedShopAddresses = {}; // Выбранные адреса магазинов
  Map<String, String> _referencePhotoUrls = {}; // URL эталонных фото для каждого магазина
  Map<String, File?> _referencePhotoFiles = {}; // Локальные файлы эталонных фото
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
    } else {
      _selectedAnswerType = 'text'; // По умолчанию текст
    }
    _loadShops();
  }
  
  Future<void> _loadShops() async {
    try {
      setState(() => _isLoadingShops = true);
      final shops = await Shop.loadShopsFromServer();
      setState(() {
        _allShops = shops;
        _isLoadingShops = false;
      });
    } catch (e) {
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
      setState(() => _isUploadingPhotos = true);

      final photoUrl = await ShiftQuestionService.uploadReferencePhoto(
        questionId: questionId,
        shopAddress: shopAddress,
        photoFile: photoFile,
      );

      if (photoUrl != null) {
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
          setState(() => _isUploadingPhotos = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Эталонное фото успешно загружено'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          Logger.error('Не удалось обновить вопрос с эталонным фото');
          setState(() => _isUploadingPhotos = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Фото загружено, но не удалось обновить вопрос'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        setState(() => _isUploadingPhotos = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка загрузки эталонного фото'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('Исключение при загрузке эталонного фото', e);
      setState(() => _isUploadingPhotos = false);
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

    setState(() {
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
            const SnackBar(
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Красивый заголовок
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF004D40), Color(0xFF00695C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isEditing ? Icons.edit_note : Icons.add_circle_outline,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing ? 'Редактировать вопрос' : 'Новый вопрос',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isEditing ? 'Измените параметры вопроса' : 'Заполните все поля',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.15),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
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
                        color: const Color(0xFF004D40),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _questionController,
                        decoration: InputDecoration(
                          hintText: 'Введите текст вопроса...',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF004D40), width: 2),
                          ),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        maxLines: 3,
                        style: const TextStyle(fontSize: 16, height: 1.4),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Пожалуйста, введите текст вопроса';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),
                      // Секция: Тип ответа
                      _buildSectionHeader(
                        icon: Icons.format_list_bulleted,
                        title: 'Тип ответа',
                        color: const Color(0xFF7B1FA2),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildAnswerTypeOption(
                              icon: Icons.camera_alt_outlined,
                              label: 'Фото',
                              value: 'photo',
                              color: const Color(0xFF7B1FA2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildAnswerTypeOption(
                              icon: Icons.check_circle_outline,
                              label: 'Да/Нет',
                              value: 'yesno',
                              color: const Color(0xFF0288D1),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildAnswerTypeOption(
                              icon: Icons.tag,
                              label: 'Число',
                              value: 'number',
                              color: const Color(0xFFE65100),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildAnswerTypeOption(
                              icon: Icons.text_fields,
                              label: 'Текст',
                              value: 'text',
                              color: const Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      // Секция: Магазины
                      _buildSectionHeader(
                        icon: Icons.store_mall_directory_outlined,
                        title: 'Магазины',
                        color: const Color(0xFFEF6C00),
                      ),
                      const SizedBox(height: 12),
                      if (_isLoadingShops)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF004D40)),
                            ),
                          ),
                        )
                      else ...[
                        // Переключатель "Все магазины"
                        Container(
                          decoration: BoxDecoration(
                            color: _isForAllShops ? const Color(0xFF004D40).withOpacity(0.1) : Colors.grey[50],
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _isForAllShops ? const Color(0xFF004D40).withOpacity(0.3) : Colors.grey[300]!,
                            ),
                          ),
                          child: CheckboxListTile(
                            title: const Text(
                              'Задавать всем магазинам',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Вопрос будет задан на всех точках',
                              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                            ),
                            value: _isForAllShops,
                            onChanged: (value) {
                              setState(() {
                                _isForAllShops = value ?? false;
                                if (_isForAllShops) {
                                  _selectedShopAddresses.clear();
                                }
                              });
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: const Color(0xFF004D40),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        if (!_isForAllShops) ...[
                          const SizedBox(height: 12),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 200),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _allShops.length,
                                itemBuilder: (context, index) {
                                  final shop = _allShops[index];
                                  final isSelected = _selectedShopAddresses.contains(shop.address);
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFF004D40).withOpacity(0.05) : Colors.white,
                                      border: Border(
                                        bottom: BorderSide(color: Colors.grey[200]!),
                                      ),
                                    ),
                                    child: CheckboxListTile(
                                      title: Text(
                                        shop.name,
                                        style: TextStyle(
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                      ),
                                      subtitle: Text(
                                        shop.address,
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      ),
                                      value: isSelected,
                                      onChanged: (value) {
                                        setState(() {
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
                                      activeColor: const Color(0xFF004D40),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          if (_selectedShopAddresses.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Выбрано: ${_selectedShopAddresses.length} магазин(ов)',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                        // Эталонные фото (только для вопросов с фото)
                        if (_selectedAnswerType == 'photo') ...[
                          const SizedBox(height: 28),
                          _buildSectionHeader(
                            icon: Icons.photo_library_outlined,
                            title: 'Эталонные фото',
                            color: const Color(0xFF388E3C),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Добавьте образцы, чтобы сотрудники знали, как должно выглядеть фото',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 12),
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
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[400]!),
                      ),
                      child: Text(
                        'Отмена',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveQuestion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isEditing ? Icons.save : Icons.add_circle,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isEditing ? 'Сохранить' : 'Добавить',
                                  style: const TextStyle(
                                    fontSize: 16,
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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
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
    final cardColor = color ?? const Color(0xFF004D40);

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedAnswerType = value;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? cardColor.withOpacity(0.12) : Colors.grey[50],
          border: Border.all(
            color: isSelected ? cardColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cardColor.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? cardColor.withOpacity(0.15) : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? cardColor : Colors.grey[500],
                size: 28,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? cardColor : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 20,
                  height: 3,
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(2),
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок магазина
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.store, size: 18, color: Colors.orange[700]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    shopName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (hasPhoto)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 14, color: Colors.green[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Загружено',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Превью фото или кнопка добавления
            if (hasPhoto) ...[
              Stack(
                children: [
                  Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: photoFile != null
                          ? kIsWeb
                              ? Image.network(
                                  photoFile.path,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
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
                              ? Image.network(
                                  photoUrl,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded /
                                                loadingProgress.expectedTotalBytes!
                                            : null,
                                        strokeWidth: 2,
                                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF004D40)),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Center(
                                      child: Icon(Icons.error_outline, size: 40, color: Colors.red[300]),
                                    );
                                  },
                                )
                              : Center(child: Icon(Icons.image, size: 40, color: Colors.grey[400])),
                    ),
                  ),
                  // Кнопки поверх фото
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Row(
                      children: [
                        _buildPhotoActionButton(
                          icon: Icons.refresh,
                          onPressed: _isUploadingPhotos ? null : () => _pickReferencePhoto(shopAddress),
                          tooltip: 'Заменить',
                        ),
                        const SizedBox(width: 6),
                        _buildPhotoActionButton(
                          icon: Icons.delete_outline,
                          onPressed: () {
                            setState(() {
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
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey[300]!,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 36,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Добавить эталонное фото',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
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
      color: isDestructive ? Colors.red[50] : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 18,
            color: isDestructive ? Colors.red[600] : Colors.grey[700],
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


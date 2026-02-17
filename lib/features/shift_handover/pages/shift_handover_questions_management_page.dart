import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/shift_handover_question_model.dart';
import '../services/shift_handover_question_service.dart';
import '../../shops/models/shop_model.dart';
import '../../envelope/models/envelope_question_model.dart';
import '../../envelope/services/envelope_question_service.dart';
import 'package:arabica_app/shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница управления вопросами сдачи смены
class ShiftHandoverQuestionsManagementPage extends StatefulWidget {
  const ShiftHandoverQuestionsManagementPage({super.key});

  @override
  State<ShiftHandoverQuestionsManagementPage> createState() => _ShiftHandoverQuestionsManagementPageState();
}

class _ShiftHandoverQuestionsManagementPageState extends State<ShiftHandoverQuestionsManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Вопросы сдачи смены
  List<ShiftHandoverQuestion> _questions = [];
  bool _isLoading = true;

  // Вопросы формирования конверта
  List<EnvelopeQuestion> _envelopeQuestions = [];
  bool _isLoadingEnvelope = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      // Перестроить UI когда вкладка меняется
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadQuestions();
    _loadEnvelopeQuestions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEnvelopeQuestions() async {
    setState(() {
      _isLoadingEnvelope = true;
    });

    try {
      final questions = await EnvelopeQuestionService.getQuestions();
      setState(() {
        _envelopeQuestions = questions;
        _isLoadingEnvelope = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingEnvelope = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки вопросов конверта: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final questions = await ShiftHandoverQuestionService.getQuestions();
      setState(() {
        _questions = questions;
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
    final result = await showDialog<ShiftHandoverQuestion>(
      context: context,
      builder: (context) => ShiftHandoverQuestionFormDialog(),
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

  Future<void> _showEditQuestionDialog(ShiftHandoverQuestion question) async {
    final result = await showDialog<ShiftHandoverQuestion>(
      context: context,
      builder: (context) => ShiftHandoverQuestionFormDialog(question: question),
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

  Future<void> _deleteQuestion(ShiftHandoverQuestion question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: AppColors.emeraldDark,
            borderRadius: BorderRadius.circular(20.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 30,
                offset: Offset(0, 10),
              ),
            ],
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
                        color: Colors.white.withOpacity(0.4),
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
      final success = await ShiftHandoverQuestionService.deleteQuestion(question.id);
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

  String _getAnswerTypeLabel(ShiftHandoverQuestion question) {
    if (question.isPhotoOnly) return 'Фото';
    if (question.isScreenshotOnly) return 'Скриншот';
    if (question.isYesNo) return 'Да/Нет';
    if (question.isNumberOnly) return 'Число';
    return 'Текст';
  }

  IconData _getAnswerTypeIcon(ShiftHandoverQuestion question) {
    if (question.isPhotoOnly) return Icons.camera_alt;
    if (question.isScreenshotOnly) return Icons.screenshot;
    if (question.isYesNo) return Icons.check_circle;
    if (question.isNumberOnly) return Icons.numbers;
    return Icons.text_fields;
  }

  Future<void> _showEditEnvelopeQuestionDialog(EnvelopeQuestion question) async {
    final result = await showDialog<EnvelopeQuestion>(
      context: context,
      builder: (context) => EnvelopeQuestionFormDialog(question: question),
    );

    if (result != null) {
      await _loadEnvelopeQuestions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Вопрос успешно обновлен'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _toggleEnvelopeQuestionActive(EnvelopeQuestion question) async {
    final updated = question.copyWith(isActive: !question.isActive);
    final result = await EnvelopeQuestionService.updateQuestion(updated);

    if (result != null) {
      await _loadEnvelopeQuestions();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка обновления вопроса'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              // Кастомный AppBar с градиентом
              _buildCustomAppBar(),
              // Кастомный TabBar
              _buildCustomTabBar(),
              // Контент
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24.r),
                    topRight: Radius.circular(24.r),
                  ),
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildShiftHandoverQuestionsTab(),
                      _buildEnvelopeQuestionsTab(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          if (_tabController.index == 0) {
            return FloatingActionButton.extended(
              onPressed: _showAddQuestionDialog,
              backgroundColor: AppColors.gold,
              elevation: 4,
              icon: Icon(Icons.add_rounded, color: Colors.white),
              label: Text(
                'Добавить',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }
          return SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 0.h),
      child: Row(
        children: [
          // Кнопка назад
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
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
                  'Вопросы (Сдать Смену)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, child) {
                    return Text(
                      _tabController.index == 0
                          ? '${_questions.length} вопросов'
                          : '${_envelopeQuestions.length} вопросов',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13.sp,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // Кнопка обновления
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.white, size: 20),
              onPressed: () {
                _loadQuestions();
                _loadEnvelopeQuestions();
              },
              tooltip: 'Обновить',
              constraints: BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ),
        ],
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
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: AppColors.gold.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12.r),
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
                  Icon(Icons.assignment_turned_in_outlined, size: 20),
                  SizedBox(width: 8),
                  Text('Сдача смены'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mail_outline_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Конверт'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftHandoverQuestionsTab() {
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(28.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.assignment_turned_in_outlined,
                size: 56,
                color: Colors.white.withOpacity(0.3),
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Нет вопросов',
              style: TextStyle(
                fontSize: 22.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.9),
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

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 100.h),
      itemCount: _questions.length,
      itemBuilder: (context, index) {
        final question = _questions[index];
        return _buildQuestionCard(question, index);
      },
    );
  }

  Widget _buildQuestionCard(ShiftHandoverQuestion question, int index) {
    final Color typeColor = _getAnswerTypeColor(question);
    final String targetRoleLabel = _getTargetRoleLabel(question.targetRole);
    final IconData targetRoleIcon = _getTargetRoleIcon(question.targetRole);

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(16.r),
          onTap: () => _showEditQuestionDialog(question),
          splashColor: typeColor.withOpacity(0.08),
          child: Column(
            children: [
              // Верхняя часть карточки
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 14.h, 12.w, 12.h),
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
                        borderRadius: BorderRadius.circular(12.r),
                        boxShadow: [
                          BoxShadow(
                            color: typeColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
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
                          // Бейджи типа и роли
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
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
                              // Целевая роль
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20.r),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      targetRoleIcon,
                                      size: 14,
                                      color: Colors.blueGrey[300],
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      targetRoleLabel,
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.blueGrey[300],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(16.r),
                      bottomRight: Radius.circular(16.r),
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
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: color.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.sp,
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

  Color _getAnswerTypeColor(ShiftHandoverQuestion question) {
    if (question.isPhotoOnly) return Color(0xFF7B1FA2); // Purple
    if (question.isYesNo) return Color(0xFF0288D1); // Blue
    if (question.isNumberOnly) return Color(0xFFE65100); // Orange
    return Color(0xFF2E7D32); // Green for text
  }

  String _getTargetRoleLabel(String? targetRole) {
    switch (targetRole) {
      case 'manager':
        return 'Заведующая';
      case 'employee':
        return 'Сотрудник';
      case 'all':
      default:
        return 'Все';
    }
  }

  IconData _getTargetRoleIcon(String? targetRole) {
    switch (targetRole) {
      case 'manager':
        return Icons.business_center;
      case 'employee':
        return Icons.person;
      case 'all':
      default:
        return Icons.groups;
    }
  }

  Widget _buildEnvelopeQuestionsTab() {
    if (_isLoadingEnvelope) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Загрузка вопросов конверта...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14.sp,
              ),
            ),
          ],
        ),
      );
    }

    if (_envelopeQuestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(28.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mail_outline_rounded,
                size: 56,
                color: Colors.white.withOpacity(0.3),
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Нет вопросов',
              style: TextStyle(
                fontSize: 22.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Вопросы конверта не загружены',
              style: TextStyle(
                fontSize: 15.sp,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
      itemCount: _envelopeQuestions.length,
      itemBuilder: (context, index) {
        final question = _envelopeQuestions[index];
        return _buildEnvelopeQuestionCard(question);
      },
    );
  }

  Widget _buildEnvelopeQuestionCard(EnvelopeQuestion question) {
    final sectionColor = _getSectionColor(question.section);

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(16.r),
          onTap: () => _showEditEnvelopeQuestionDialog(question),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Номер порядка
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: question.isActive
                          ? [sectionColor, sectionColor.withOpacity(0.8)]
                          : [Colors.grey[400]!, Colors.grey[300]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Center(
                    child: Text(
                      '${question.order}',
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
                      // Бейджи
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: sectionColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Text(
                              question.sectionText,
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: sectionColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getEnvelopeTypeIcon(question.type),
                                  size: 12,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  question.typeText,
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      // Заголовок
                      Text(
                        question.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15.sp,
                          color: question.isActive ? Colors.white.withOpacity(0.9) : Colors.white.withOpacity(0.4),
                        ),
                      ),
                      if (question.description.isNotEmpty) ...[
                        SizedBox(height: 4),
                        Text(
                          question.description,
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 8),
                // Переключатель и кнопка редактирования
                Column(
                  children: [
                    Transform.scale(
                      scale: 0.85,
                      child: Switch(
                        value: question.isActive,
                        onChanged: (value) => _toggleEnvelopeQuestionActive(question),
                        activeColor: AppColors.gold,
                      ),
                    ),
                    _buildCardActionButton(
                      icon: Icons.edit_rounded,
                      color: AppColors.gold,
                      onTap: () => _showEditEnvelopeQuestionDialog(question),
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

  Color _getSectionColor(String section) {
    switch (section) {
      case 'ooo':
        return Colors.blue;
      case 'ip':
        return Colors.orange;
      case 'general':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getEnvelopeTypeIcon(String type) {
    switch (type) {
      case 'photo':
        return Icons.camera_alt;
      case 'numbers':
        return Icons.dialpad;
      case 'expenses':
        return Icons.receipt_long;
      case 'shift_select':
        return Icons.schedule;
      case 'summary':
        return Icons.summarize;
      default:
        return Icons.help_outline;
    }
  }
}

/// Диалог для добавления/редактирования вопроса
class ShiftHandoverQuestionFormDialog extends StatefulWidget {
  final ShiftHandoverQuestion? question;

  const ShiftHandoverQuestionFormDialog({super.key, this.question});

  @override
  State<ShiftHandoverQuestionFormDialog> createState() => _ShiftHandoverQuestionFormDialogState();
}

class _ShiftHandoverQuestionFormDialogState extends State<ShiftHandoverQuestionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  String? _selectedAnswerType;
  String? _selectedTargetRole; // 'manager' или 'employee'
  bool _isSaving = false;
  bool _isForAllShops = false;
  List<Shop> _allShops = [];
  Set<String> _selectedShopAddresses = {};
  Map<String, String> _referencePhotoUrls = {};
  final Map<String, File?> _referencePhotoFiles = {};
  final Map<String, Uint8List?> _referencePhotoBytes = {}; // Для веб-платформы
  bool _isLoadingShops = true;
  bool _isUploadingPhotos = false;

  @override
  void initState() {
    super.initState();
    if (widget.question != null) {
      _questionController.text = widget.question!.question;
      if (widget.question!.isPhotoOnly) {
        _selectedAnswerType = 'photo';
      } else if (widget.question!.isScreenshotOnly) {
        _selectedAnswerType = 'screenshot';
      } else if (widget.question!.isYesNo) {
        _selectedAnswerType = 'yesno';
      } else if (widget.question!.isNumberOnly) {
        _selectedAnswerType = 'number';
      } else {
        _selectedAnswerType = 'text';
      }

      if (widget.question!.shops == null) {
        _isForAllShops = true;
      } else {
        _selectedShopAddresses = widget.question!.shops!.toSet();
      }

      if (widget.question!.referencePhotos != null) {
        _referencePhotoUrls = Map<String, String>.from(widget.question!.referencePhotos!);
      }

      _selectedTargetRole = widget.question!.targetRole ?? 'all';
    } else {
      _selectedAnswerType = 'text';
      _selectedTargetRole = 'all'; // По умолчанию "Всем"
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
        // Читаем bytes для веб-платформы
        final bytes = await image.readAsBytes();

        // Создаем веб-совместимый файл
        final File photoFile;
        if (kIsWeb) {
          // На веб создаем файл из байтов
          photoFile = _XFileWrapper(image.path, bytes);
        } else {
          // На мобильных используем обычный File
          photoFile = File(image.path);
        }

        setState(() {
          _referencePhotoFiles[shopAddress] = photoFile;
          _referencePhotoBytes[shopAddress] = bytes;
        });

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

      final photoUrl = await ShiftHandoverQuestionService.uploadReferencePhoto(
        questionId: questionId,
        shopAddress: shopAddress,
        photoFile: photoFile,
      );

      if (photoUrl != null) {
        setState(() {
          _referencePhotoUrls[shopAddress] = photoUrl;
          _isUploadingPhotos = false;
        });
      } else {
        setState(() => _isUploadingPhotos = false);
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

      switch (_selectedAnswerType) {
        case 'photo':
          answerFormatB = 'photo';
          answerFormatC = null;
          break;
        case 'screenshot':
          answerFormatB = 'screenshot';
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
          answerFormatB = 'text';
          answerFormatC = null;
          break;
      }

      List<String>? shops = _isForAllShops ? null : _selectedShopAddresses.toList();

      ShiftHandoverQuestion? result;
      if (widget.question != null) {
        result = await ShiftHandoverQuestionService.updateQuestion(
          id: widget.question!.id,
          question: _questionController.text.trim(),
          answerFormatB: answerFormatB,
          answerFormatC: answerFormatC,
          shops: shops,
          referencePhotos: _referencePhotoUrls.isNotEmpty ? _referencePhotoUrls : null,
          targetRole: _selectedTargetRole,
        );

        if (result != null && _selectedAnswerType == 'photo') {
          for (final entry in _referencePhotoFiles.entries) {
            if (entry.value != null && !_referencePhotoUrls.containsKey(entry.key)) {
              await _uploadReferencePhoto(result.id, entry.key, entry.value!);
            }
          }
          final updatedResult = await ShiftHandoverQuestionService.getQuestion(result.id);
          if (updatedResult != null) {
            result = updatedResult;
          }
        }
      } else {
        result = await ShiftHandoverQuestionService.createQuestion(
          question: _questionController.text.trim(),
          answerFormatB: answerFormatB,
          answerFormatC: answerFormatC,
          shops: shops,
          referencePhotos: null,
          targetRole: _selectedTargetRole,
        );

        if (result != null && _selectedAnswerType == 'photo') {
          final Map<String, String> uploadedPhotos = {};
          for (final entry in _referencePhotoFiles.entries) {
            if (entry.value != null) {
              final photoUrl = await ShiftHandoverQuestionService.uploadReferencePhoto(
                questionId: result.id,
                shopAddress: entry.key,
                photoFile: entry.value!,
              );
              if (photoUrl != null) {
                uploadedPhotos[entry.key] = photoUrl;
              }
            }
          }

          if (uploadedPhotos.isNotEmpty) {
            final updatedResult = await ShiftHandoverQuestionService.updateQuestion(
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 30,
              offset: Offset(0, 10),
            ),
          ],
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
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Icon(
                      isEditing ? Icons.edit_note : Icons.add_circle_outline,
                      color: Colors.white,
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
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
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
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Пожалуйста, введите текст вопроса';
                  }
                  return null;
                },
              ),
              SizedBox(height: 28),
              // Секция: Кому задавать
              _buildSectionHeader(
                icon: Icons.people_alt_outlined,
                title: 'Кому задавать вопрос',
                color: AppColors.blue,
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTargetRoleOption(
                      icon: Icons.business_center,
                      label: 'Заведующая',
                      value: 'manager',
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _buildTargetRoleOption(
                      icon: Icons.person,
                      label: 'Сотрудник',
                      value: 'employee',
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _buildTargetRoleOption(
                      icon: Icons.groups,
                      label: 'Всем',
                      value: 'all',
                    ),
                  ),
                ],
              ),
              SizedBox(height: 28),
              // Секция: Тип ответа
              _buildSectionHeader(
                icon: Icons.format_list_bulleted,
                title: 'Тип ответа',
                color: Color(0xFFCE93D8),
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
              SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildAnswerTypeOption(
                      icon: Icons.screenshot,
                      label: 'Скриншот',
                      value: 'screenshot',
                      color: Color(0xFF5E35B1),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(child: SizedBox()), // Пустое место для выравнивания
                ],
              ),
              SizedBox(height: 28),
              // Секция: Магазины
              _buildSectionHeader(
                icon: Icons.store_mall_directory_outlined,
                title: 'Магазины',
                color: Color(0xFFFFB74D),
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
                    color: _isForAllShops ? AppColors.gold.withOpacity(0.12) : Colors.white.withOpacity(0.06),
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
                      setState(() {
                        _isForAllShops = value ?? false;
                        if (_isForAllShops) {
                          _selectedShopAddresses.clear();
                        }
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.gold,
                    checkColor: Colors.white,
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
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: _allShops.map((shop) {
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
                                  setState(() {
                                    if (value ?? false) {
                                      _selectedShopAddresses.add(shop.address);
                                    } else {
                                      _selectedShopAddresses.remove(shop.address);
                                      _referencePhotoFiles.remove(shop.address);
                                      _referencePhotoBytes.remove(shop.address);
                                      _referencePhotoUrls.remove(shop.address);
                                    }
                                  });
                                },
                                controlAffinity: ListTileControlAffinity.leading,
                                activeColor: AppColors.gold,
                                checkColor: Colors.white,
                              ),
                            );
                          }).toList(),
                        ),
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
                if (_selectedAnswerType == 'photo') ...[
                  SizedBox(height: 28),
                  _buildSectionHeader(
                    icon: Icons.photo_library_outlined,
                    title: 'Эталонные фото',
                    color: Color(0xFF66BB6A),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Добавьте образцы, чтобы сотрудники знали, как должно выглядеть фото',
                    style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.5)),
                  ),
                  SizedBox(height: 12),
                  Container(
                    constraints: BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Column(
                        children: _isForAllShops
                            ? _allShops.map((shop) => _buildReferencePhotoSection(shop.address, shop.name)).toList()
                            : _selectedShopAddresses.map((address) {
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
                              }).toList(),
                      ),
                    ),
                  ),
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
                color: AppColors.emeraldDark,
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
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        elevation: 2,
                      ),
                      child: _isSaving
                          ? SizedBox(
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
    final cardColor = color ?? AppColors.emerald;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedAnswerType = value;
        });
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 12.w),
        decoration: BoxDecoration(
          color: isSelected ? cardColor.withOpacity(0.2) : Colors.white.withOpacity(0.06),
          border: Border.all(
            color: isSelected ? cardColor : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14.r),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cardColor.withOpacity(0.2),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: Duration(milliseconds: 200),
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: isSelected ? cardColor.withOpacity(0.25) : Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? cardColor : Colors.white.withOpacity(0.4),
                size: 28,
              ),
            ),
            SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? cardColor : Colors.white.withOpacity(0.6),
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
                     _referencePhotoFiles.containsKey(shopAddress) ||
                     _referencePhotoBytes.containsKey(shopAddress);
    final photoFile = _referencePhotoFiles[shopAddress];
    final photoBytes = _referencePhotoBytes[shopAddress];
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
                            color: Colors.green[700],
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
                      child: photoBytes != null
                          ? Image.memory(
                              photoBytes,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Icon(Icons.error_outline, size: 40, color: Colors.red[300]),
                                );
                              },
                            )
                          : photoFile != null && !kIsWeb
                              ? Image.file(
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
                            setState(() {
                              _referencePhotoFiles.remove(shopAddress);
                              _referencePhotoBytes.remove(shopAddress);
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
      color: isDestructive ? Colors.red[900]!.withOpacity(0.8) : AppColors.emeraldDark,
      borderRadius: BorderRadius.circular(8.r),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8.r),
        child: Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
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

  Widget _buildTargetRoleOption({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final isSelected = _selectedTargetRole == value;
    final cardColor = AppColors.blue;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTargetRole = value;
        });
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 10.w),
        decoration: BoxDecoration(
          color: isSelected ? cardColor.withOpacity(0.2) : Colors.white.withOpacity(0.06),
          border: Border.all(
            color: isSelected ? cardColor : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14.r),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cardColor.withOpacity(0.2),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: Duration(milliseconds: 200),
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: isSelected ? cardColor.withOpacity(0.25) : Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? cardColor : Colors.white.withOpacity(0.4),
                size: 24,
              ),
            ),
            SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? cardColor : Colors.white.withOpacity(0.6),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12.sp,
              ),
              textAlign: TextAlign.center,
            ),
            if (isSelected)
              Padding(
                padding: EdgeInsets.only(top: 6.h),
                child: Icon(
                  Icons.check_circle,
                  color: cardColor,
                  size: 16,
                ),
              ),
          ],
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

/// Диалог для редактирования вопроса формирования конверта
class EnvelopeQuestionFormDialog extends StatefulWidget {
  final EnvelopeQuestion question;

  const EnvelopeQuestionFormDialog({super.key, required this.question});

  @override
  State<EnvelopeQuestionFormDialog> createState() => _EnvelopeQuestionFormDialogState();
}

class _EnvelopeQuestionFormDialogState extends State<EnvelopeQuestionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  String? _referencePhotoUrl;
  File? _selectedPhotoFile;
  Uint8List? _selectedPhotoBytes;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.question.title);
    _descriptionController = TextEditingController(text: widget.question.description);
    _referencePhotoUrl = widget.question.referencePhotoUrl;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickReferencePhoto() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();

        setState(() {
          _selectedPhotoBytes = bytes;
          if (!kIsWeb) {
            _selectedPhotoFile = File(image.path);
          }
        });

        // Загружаем фото сразу
        await _uploadPhoto();
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

  Future<void> _uploadPhoto() async {
    if (_selectedPhotoFile == null && _selectedPhotoBytes == null) return;

    setState(() {
      _isUploadingPhoto = true;
    });

    try {
      File photoFile;
      if (_selectedPhotoFile != null) {
        photoFile = _selectedPhotoFile!;
      } else {
        // Создаем временный файл для веб
        photoFile = _XFileWrapper('temp.jpg', _selectedPhotoBytes!);
      }

      final url = await EnvelopeQuestionService.uploadReferencePhoto(
        questionId: widget.question.id,
        photoFile: photoFile,
      );

      if (url != null) {
        setState(() {
          _referencePhotoUrl = url;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка загрузки фото'),
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
          _isUploadingPhoto = false;
        });
      }
    }
  }

  void _removePhoto() {
    setState(() {
      _referencePhotoUrl = null;
      _selectedPhotoFile = null;
      _selectedPhotoBytes = null;
    });
  }

  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final updated = widget.question.copyWith(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        referencePhotoUrl: _referencePhotoUrl,
      );

      final result = await EnvelopeQuestionService.updateQuestion(updated);

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
    final isPhotoType = widget.question.type == 'photo';
    final hasPhoto = _referencePhotoUrl != null || _selectedPhotoBytes != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: AppColors.emeraldDark,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: AppColors.emerald,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16.r),
                  topRight: Radius.circular(16.r),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getTypeIcon(widget.question.type),
                    color: AppColors.gold,
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Редактирование шага',
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.white.withOpacity(0.1)),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16.w),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: _getSectionColor(widget.question.section).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Text(
                              widget.question.sectionText,
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: _getSectionColor(widget.question.section),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Text(
                              widget.question.typeText,
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.white.withOpacity(0.5),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      TextFormField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: 'Название шага',
                          labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide(color: AppColors.gold, width: 2),
                          ),
                          hintText: 'Введите название',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        ),
                        style: TextStyle(color: Colors.white.withOpacity(0.9)),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Пожалуйста, введите название';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: InputDecoration(
                          labelText: 'Описание',
                          labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide(color: AppColors.gold, width: 2),
                          ),
                          hintText: 'Введите описание для сотрудника',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        ),
                        style: TextStyle(color: Colors.white.withOpacity(0.9)),
                        maxLines: 3,
                      ),
                      // Эталонное фото (только для типа photo)
                      if (isPhotoType) ...[
                        SizedBox(height: 20),
                        Text(
                          'Эталонное фото:',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Сотрудник увидит это фото как образец',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                        SizedBox(height: 12),
                        if (hasPhoto)
                          Container(
                            height: 150,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12.r),
                                  child: _selectedPhotoBytes != null
                                      ? Image.memory(
                                          _selectedPhotoBytes!,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                        )
                                      : _referencePhotoUrl != null
                                          ? AppCachedImage(
                                              imageUrl: _referencePhotoUrl!,
                                              fit: BoxFit.cover,
                                              width: double.infinity,
                                              height: double.infinity,
                                              errorWidget: (_, __, ___) => Center(
                                                child: Icon(Icons.error, size: 48, color: Colors.red),
                                              ),
                                            )
                                          : SizedBox(),
                                ),
                                if (_isUploadingPhoto)
                                  Container(
                                    color: Colors.black.withOpacity(0.5),
                                    child: Center(
                                      child: CircularProgressIndicator(color: Colors.white),
                                    ),
                                  ),
                                Positioned(
                                  top: 8.h,
                                  right: 8.w,
                                  child: IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red),
                                    onPressed: _isUploadingPhoto ? null : _removePhoto,
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.emeraldDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            height: 100,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white.withOpacity(0.1), style: BorderStyle.solid),
                              borderRadius: BorderRadius.circular(12.r),
                              color: Colors.white.withOpacity(0.04),
                            ),
                            child: InkWell(
                              onTap: _isUploadingPhoto ? null : _pickReferencePhoto,
                              borderRadius: BorderRadius.circular(12.r),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate, size: 40, color: Colors.white.withOpacity(0.3)),
                                  SizedBox(height: 8),
                                  Text(
                                    'Добавить эталонное фото',
                                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (hasPhoto)
                          Padding(
                            padding: EdgeInsets.only(top: 8.h),
                            child: ElevatedButton.icon(
                              onPressed: _isUploadingPhoto ? null : _pickReferencePhoto,
                              icon: Icon(Icons.photo_camera, size: 18),
                              label: Text('Изменить фото'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.gold,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: Colors.white.withOpacity(0.1)),
            // Actions
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: Text(
                      'Отмена',
                      style: TextStyle(color: Colors.white.withOpacity(0.6)),
                    ),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: (_isSaving || _isUploadingPhoto) ? null : _saveQuestion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.white,
                    ),
                    child: _isSaving
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text('Сохранить'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'photo':
        return Icons.camera_alt;
      case 'numbers':
        return Icons.dialpad;
      case 'expenses':
        return Icons.receipt_long;
      case 'shift_select':
        return Icons.schedule;
      case 'summary':
        return Icons.summarize;
      default:
        return Icons.help_outline;
    }
  }

  Color _getSectionColor(String section) {
    switch (section) {
      case 'ooo':
        return Colors.blue;
      case 'ip':
        return Colors.orange;
      case 'general':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}

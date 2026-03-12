import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../models/shift_report_model.dart';
import '../models/shift_question_model.dart';
import '../services/shift_question_service.dart';
import '../../shops/models/shop_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/cache_manager.dart';

/// Страница сводного отчёта по пересменке (таблица вопросы x магазины)
class ShiftSummaryReportPage extends StatefulWidget {
  final DateTime date;
  final String shiftType;
  final String shiftName;
  final List<ShiftReport> reports;
  final List<Shop> allShops;

  const ShiftSummaryReportPage({
    super.key,
    required this.date,
    required this.shiftType,
    required this.shiftName,
    required this.reports,
    required this.allShops,
  });

  @override
  State<ShiftSummaryReportPage> createState() => _ShiftSummaryReportPageState();
}

class _ShiftSummaryReportPageState extends State<ShiftSummaryReportPage> {
  static const _cacheKey = 'shift_summary';
  List<ShiftQuestion> _questions = [];
  bool _isLoading = true;

  // Map: shopAddress -> ShiftReport
  final Map<String, ShiftReport> _reportsByShop = {};

  // Контроллеры для синхронного скролла
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyScrollController = ScrollController();
  bool _isSyncingScroll = false; // Флаг для предотвращения рекурсивной синхронизации

  static final _months = [
    '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
  ];

  @override
  void initState() {
    super.initState();
    _loadData();

    // Синхронизация скролла заголовка и тела (с защитой от рекурсии)
    _headerScrollController.addListener(() {
      if (_isSyncingScroll) return;
      _isSyncingScroll = true;
      if (_bodyScrollController.hasClients) {
        _bodyScrollController.jumpTo(_headerScrollController.offset);
      }
      _isSyncingScroll = false;
    });
    _bodyScrollController.addListener(() {
      if (_isSyncingScroll) return;
      _isSyncingScroll = true;
      if (_headerScrollController.hasClients) {
        _headerScrollController.jumpTo(_bodyScrollController.offset);
      }
      _isSyncingScroll = false;
    });
  }

  @override
  void dispose() {
    _headerScrollController.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Check cache first
    final cached = CacheManager.get<List<ShiftQuestion>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _questions = cached.where((q) => q.isYesNo || q.isNumberOnly).toList();
        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = true);
    }

    try {
      // Загружаем вопросы
      final questions = await ShiftQuestionService.getQuestions();

      // Показываем только вопросы с форматом да/нет и числовым — остальные (фото, текст) скрываем
      final filteredQuestions = questions.where((q) => q.isYesNo || q.isNumberOnly).toList();

      // Создаём map отчётов по магазинам.
      // Включаем только реально пройденные (не pending/failed) — только у них есть ответы.
      // Список отсортирован новейшими первыми, берём первый подходящий для каждого магазина.
      for (final report in widget.reports) {
        if (report.status != 'pending' &&
            report.status != 'failed' &&
            report.employeeName.isNotEmpty) {
          final key = report.shopAddress.toLowerCase().trim();
          _reportsByShop.putIfAbsent(key, () => report);
        }
      }

      // Save to cache
      CacheManager.set(_cacheKey, questions);

      if (!mounted) return;
      setState(() {
        _questions = filteredQuestions;
        _isLoading = false;
      });
    } catch (e) {
      Logger.warning('Failed to load shift summary data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Получить название магазина для вертикального отображения
  String _getShopName(String address) {
    // Убираем "г. " или "г." в начале
    var name = address.replaceFirst(RegExp(r'^г\.?\s*'), '');
    return name.trim();
  }

  @override
  Widget build(BuildContext context) {
    final isMorning = widget.shiftType == 'morning';

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
              _buildAppBar(context, isMorning),
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isMorning) {
    final dateStr = '${widget.date.day} ${_months[widget.date.month]}';
    final shiftColor = isMorning
        ? AppColors.warning.withOpacity(0.25)
        : AppColors.indigo.withOpacity(0.25);
    final shiftBorderColor = isMorning
        ? AppColors.warning.withOpacity(0.3)
        : AppColors.indigo.withOpacity(0.3);

    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 4.h),
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
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: shiftColor,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: shiftBorderColor),
              ),
              child: Text(
                '${widget.shiftName} - $dateStr',
                style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_questions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz_outlined, size: 64, color: Colors.white.withOpacity(0.25)),
            SizedBox(height: 16),
            Text(
              'Нет вопросов для отображения',
              style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }

    if (widget.allShops.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_outlined, size: 64, color: Colors.white.withOpacity(0.25)),
            SizedBox(height: 16),
            Text(
              'Нет магазинов для отображения',
              style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Статистика
        _buildStatisticsHeader(),
        // Таблица
        Expanded(child: _buildTable()),
      ],
    );
  }

  /// Заголовок со статистикой (компактный)
  Widget _buildStatisticsHeader() {
    // Только реально пройденные (не pending/failed) с заполненным именем сотрудника
    final passedCount = widget.reports.where((r) =>
      r.status != 'pending' && r.status != 'failed' && r.employeeName.isNotEmpty
    ).length;
    final totalCount = widget.allShops.length;
    final notPassedCount = totalCount - passedCount;

    return Container(
      margin: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 6.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(Icons.store, 'Всего', '$totalCount', AppColors.info),
          Container(width: 1, height: 24, color: Colors.white.withOpacity(0.1)),
          _buildStatItem(Icons.check_circle, 'Прошли', '$passedCount', AppColors.successLight),
          Container(width: 1, height: 24, color: Colors.white.withOpacity(0.1)),
          _buildStatItem(Icons.cancel, 'Не прошли', '$notPassedCount', AppColors.errorLight),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: color),
        ),
        SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5))),
      ],
    );
  }

  // Ширина столбца с вопросами (фиксированная)
  static double _questionColumnWidth = 140.0;
  // Ширина столбца магазина
  static double _shopColumnWidth = 28.0;
  // Высота заголовка с вертикальными названиями (увеличена для полных названий)
  static double _headerHeight = 140.0;
  // Высота строки вопроса
  static double _rowHeight = 44.0;

  /// Построить таблицу с фиксированным столбцом вопросов
  Widget _buildTable() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 0.h, 8.w, 8.h),
      child: Column(
        children: [
          // Заголовок таблицы (вопрос + магазины)
          _buildTableHeader(),
          // Тело таблицы (вопросы + ответы)
          Expanded(child: _buildTableBody()),
        ],
      ),
    );
  }

  /// Заголовок таблицы
  Widget _buildTableHeader() {
    return Container(
      height: _headerHeight,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          // Фиксированный заголовок "Вопрос"
          Container(
            width: _questionColumnWidth,
            height: _headerHeight,
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              border: Border(right: BorderSide(color: Colors.white.withOpacity(0.15), width: 2)),
            ),
            alignment: Alignment.center,
            child: Text(
              'Вопрос',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp, color: Colors.white.withOpacity(0.9)),
            ),
          ),
          // Скроллируемые заголовки магазинов
          Expanded(
            child: SingleChildScrollView(
              controller: _headerScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.allShops.map((shop) {
                  final shopKey = shop.address.toLowerCase().trim();
                  final hasPassed = _reportsByShop.containsKey(shopKey);
                  return _buildShopHeader(shop, hasPassed);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Заголовок магазина (вертикальный текст)
  Widget _buildShopHeader(Shop shop, bool hasPassed) {
    return Container(
      width: _shopColumnWidth,
      height: _headerHeight,
      decoration: BoxDecoration(
        color: hasPassed
            ? AppColors.success.withOpacity(0.12)
            : AppColors.error.withOpacity(0.12),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      child: Column(
        children: [
          // Иконка статуса
          Padding(
            padding: EdgeInsets.only(top: 2.h),
            child: Icon(
              hasPassed ? Icons.check_circle : Icons.cancel,
              color: hasPassed ? AppColors.successLight : AppColors.errorLight,
              size: 12,
            ),
          ),
          // Вертикальный текст (полное название)
          Expanded(
            child: RotatedBox(
              quarterTurns: 3, // 270 градусов (снизу вверх)
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                child: Text(
                  _getShopName(shop.address),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 8.sp,
                    color: hasPassed ? AppColors.successLight : AppColors.errorLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Тело таблицы
  Widget _buildTableBody() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(14.r)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Фиксированный столбец с вопросами
            Column(
              children: _questions.asMap().entries.map((entry) {
                final index = entry.key;
                final question = entry.value;
                final isEven = index % 2 == 0;
                return _buildQuestionCell(question, isEven);
              }).toList(),
            ),
            // Единый горизонтально-скроллируемый блок ответов
            Expanded(
              child: SingleChildScrollView(
                controller: _bodyScrollController,
                scrollDirection: Axis.horizontal,
                child: Column(
                  children: _questions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final question = entry.value;
                    final isEven = index % 2 == 0;
                    return _buildAnswerRow(question, isEven);
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Фиксированная ячейка с вопросом (левый столбец)
  Widget _buildQuestionCell(ShiftQuestion question, bool isEven) {
    return Container(
      width: _questionColumnWidth,
      height: _rowHeight,
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: isEven ? Colors.white.withOpacity(0.03) : Colors.transparent,
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.15), width: 2),
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        question.question,
        style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.8)),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Строка ответов (скроллируемая часть — без своего ScrollController)
  Widget _buildAnswerRow(ShiftQuestion question, bool isEven) {
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: isEven ? Colors.white.withOpacity(0.03) : Colors.transparent,
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: widget.allShops.map((shop) {
          return _buildAnswerCell(shop, question);
        }).toList(),
      ),
    );
  }

  /// Ячейка с ответом
  Widget _buildAnswerCell(Shop shop, ShiftQuestion question) {
    final shopKey = shop.address.toLowerCase().trim();
    final report = _reportsByShop[shopKey];

    Color bgColor = Colors.transparent;
    String displayAnswer = '-';
    Color textColor = Colors.white.withOpacity(0.7);

    if (report == null) {
      // Магазин не прошёл пересменку
      bgColor = AppColors.error.withOpacity(0.15);
      textColor = AppColors.errorLight;
    } else {
      // Ищем ответ на этот вопрос
      final answer = report.answers.firstWhere(
        (a) => a.question.toLowerCase().trim() == question.question.toLowerCase().trim(),
        orElse: () => ShiftAnswer(question: question.question),
      );

      if (answer.textAnswer != null && answer.textAnswer!.isNotEmpty) {
        displayAnswer = answer.textAnswer!;
        // Если Да/Нет, подсвечиваем
        if (displayAnswer.toLowerCase() == 'да') {
          bgColor = AppColors.success.withOpacity(0.15);
          textColor = AppColors.successLight;
        } else if (displayAnswer.toLowerCase() == 'нет') {
          bgColor = AppColors.warning.withOpacity(0.15);
          textColor = AppColors.warningLight;
        }
      } else if (answer.numberAnswer != null) {
        displayAnswer = answer.numberAnswer!.toStringAsFixed(
          answer.numberAnswer! == answer.numberAnswer!.roundToDouble() ? 0 : 1
        );
      }
    }

    return Container(
      width: _shopColumnWidth,
      height: _rowHeight,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(right: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      alignment: Alignment.center,
      child: Text(
        displayAnswer,
        style: TextStyle(
          fontSize: 10.sp,
          fontWeight: report == null ? FontWeight.bold : FontWeight.normal,
          color: textColor,
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/shift_report_model.dart';
import '../models/shift_question_model.dart';
import '../services/shift_question_service.dart';
import '../../shops/models/shop_model.dart';

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
  List<ShiftQuestion> _questions = [];
  bool _isLoading = true;

  // Map: shopAddress -> ShiftReport
  Map<String, ShiftReport> _reportsByShop = {};

  // Контроллеры для синхронного скролла
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyScrollController = ScrollController();

  static const _months = [
    '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
  ];

  @override
  void initState() {
    super.initState();
    _loadData();

    // Синхронизация скролла заголовка и тела
    _headerScrollController.addListener(() {
      if (_bodyScrollController.hasClients) {
        _bodyScrollController.jumpTo(_headerScrollController.offset);
      }
    });
    _bodyScrollController.addListener(() {
      if (_headerScrollController.hasClients) {
        _headerScrollController.jumpTo(_bodyScrollController.offset);
      }
    });
  }

  @override
  void dispose() {
    _headerScrollController.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Загружаем вопросы
    final questions = await ShiftQuestionService.getQuestions();

    // Фильтруем вопросы без фото (исключаем photo-only)
    final filteredQuestions = questions.where((q) => !q.isPhotoOnly).toList();

    // Создаём map отчётов по магазинам
    for (final report in widget.reports) {
      _reportsByShop[report.shopAddress.toLowerCase().trim()] = report;
    }

    setState(() {
      _questions = filteredQuestions;
      _isLoading = false;
    });
  }

  /// Получить название магазина для вертикального отображения
  String _getShopName(String address) {
    // Убираем "г. " или "г." в начале
    var name = address.replaceFirst(RegExp(r'^г\.?\s*'), '');
    return name.trim();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = '${widget.date.day} ${_months[widget.date.month]}';
    final isMorning = widget.shiftType == 'morning';

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.shiftName} - $dateStr'),
        backgroundColor: isMorning ? Colors.orange.shade700 : Colors.indigo.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isMorning
                ? [Colors.orange.shade50, Colors.white]
                : [Colors.indigo.shade50, Colors.white],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_questions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Нет вопросов для отображения',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
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
            Icon(Icons.store_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Нет магазинов для отображения',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
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
    final passedCount = widget.reports.length;
    final totalCount = widget.allShops.length;
    final notPassedCount = totalCount - passedCount;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(Icons.store, 'Всего', '$totalCount', Colors.blue),
          Container(width: 1, height: 24, color: Colors.grey.shade300),
          _buildStatItem(Icons.check_circle, 'Прошли', '$passedCount', Colors.green),
          Container(width: 1, height: 24, color: Colors.grey.shade300),
          _buildStatItem(Icons.cancel, 'Не прошли', '$notPassedCount', Colors.red),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  // Ширина столбца с вопросами (фиксированная)
  static const double _questionColumnWidth = 140.0;
  // Ширина столбца магазина
  static const double _shopColumnWidth = 28.0;
  // Высота заголовка с вертикальными названиями (увеличена для полных названий)
  static const double _headerHeight = 140.0;
  // Высота строки вопроса
  static const double _rowHeight = 44.0;

  /// Построить таблицу с фиксированным столбцом вопросов
  Widget _buildTable() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
        color: Colors.grey.shade100,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          // Фиксированный заголовок "Вопрос"
          Container(
            width: _questionColumnWidth,
            height: _headerHeight,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              border: Border(right: BorderSide(color: Colors.grey.shade400, width: 2)),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Вопрос',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
        color: hasPassed ? Colors.green.shade50 : Colors.red.shade50,
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        children: [
          // Иконка статуса
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              hasPassed ? Icons.check_circle : Icons.cancel,
              color: hasPassed ? Colors.green : Colors.red,
              size: 12,
            ),
          ),
          // Вертикальный текст (полное название)
          Expanded(
            child: RotatedBox(
              quarterTurns: 3, // 270 градусов (снизу вверх)
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _getShopName(shop.address),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 8,
                    color: hasPassed ? Colors.green.shade700 : Colors.red.shade700,
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
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Column(
          children: _questions.asMap().entries.map((entry) {
            final index = entry.key;
            final question = entry.value;
            final isEven = index % 2 == 0;
            return _buildTableRow(question, isEven);
          }).toList(),
        ),
      ),
    );
  }

  /// Строка таблицы (вопрос + ответы)
  Widget _buildTableRow(ShiftQuestion question, bool isEven) {
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: isEven ? Colors.white : Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // Фиксированный столбец с вопросом
          Container(
            width: _questionColumnWidth,
            height: _rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: isEven ? Colors.white : Colors.grey.shade50,
              border: Border(right: BorderSide(color: Colors.grey.shade400, width: 2)),
            ),
            alignment: Alignment.centerLeft,
            child: Text(
              question.question,
              style: const TextStyle(fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Скроллируемые ответы
          Expanded(
            child: SingleChildScrollView(
              controller: _bodyScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.allShops.map((shop) {
                  return _buildAnswerCell(shop, question);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Ячейка с ответом
  Widget _buildAnswerCell(Shop shop, ShiftQuestion question) {
    final shopKey = shop.address.toLowerCase().trim();
    final report = _reportsByShop[shopKey];

    Color bgColor = Colors.transparent;
    String displayAnswer = '-';
    Color textColor = Colors.black87;

    if (report == null) {
      // Магазин не прошёл пересменку
      bgColor = Colors.red.shade100;
      textColor = Colors.red;
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
          bgColor = Colors.green.shade100;
          textColor = Colors.green.shade800;
        } else if (displayAnswer.toLowerCase() == 'нет') {
          bgColor = Colors.orange.shade100;
          textColor = Colors.orange.shade800;
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
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      alignment: Alignment.center,
      child: Text(
        displayAnswer,
        style: TextStyle(
          fontSize: 10,
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

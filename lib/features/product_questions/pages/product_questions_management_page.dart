import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../models/product_question_model.dart';
import '../services/product_question_service.dart';
import 'product_question_answer_page.dart';
import 'product_question_employee_dialog_page.dart';
import '../../shops/models/shop_model.dart';

class ProductQuestionsManagementPage extends StatefulWidget {
  const ProductQuestionsManagementPage({super.key});

  @override
  State<ProductQuestionsManagementPage> createState() => _ProductQuestionsManagementPageState();
}

class _ProductQuestionsManagementPageState extends State<ProductQuestionsManagementPage> with SingleTickerProviderStateMixin {
  // Цветовая схема
  static const _primaryColor = Color(0xFF004D40);
  static const _accentColor = Color(0xFF00897B);
  static const _gradientColors = [Color(0xFF004D40), Color(0xFF00796B)];
  static const _orangeGradient = [Color(0xFFFF6B35), Color(0xFFF7C200)];
  static const _redGradient = [Color(0xFFE53935), Color(0xFFFF5252)];
  static const _greenGradient = [Color(0xFF00b09b), Color(0xFF96c93d)];

  List<ProductQuestion> _allQuestions = [];
  List<PersonalProductDialog> _personalDialogs = [];
  List<Shop> _shops = [];
  bool _isLoading = true;
  String? _selectedShopAddress;
  late TabController _tabController;
  Timer? _refreshTimer;

  // Роль пользователя
  String _userRole = 'employee';
  bool get _isAdmin => _userRole == 'admin';

  // Таймаут для "Не отвеченные" - 30 минут
  static const int _expiredMinutes = 30;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserRole();
    _loadData();
    // Автообновление каждые 10 секунд
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadDataSilent());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('user_role') ?? 'employee';
    });
  }

  Future<void> _loadDataSilent() async {
    try {
      await _loadQuestions();
      await _loadPersonalDialogs();
    } catch (e) {
      // Игнорируем ошибки автообновления
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final shops = await Shop.loadShopsFromServer();
      await _loadQuestions();
      await _loadPersonalDialogs();

      setState(() {
        _shops = shops;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        _showFloatingSnackBar('Ошибка загрузки: $e', isError: true);
      }
    }
  }

  Future<void> _loadPersonalDialogs() async {
    try {
      List<PersonalProductDialog> dialogs;
      if (_selectedShopAddress != null) {
        dialogs = await ProductQuestionService.getShopPersonalDialogs(_selectedShopAddress!);
      } else {
        dialogs = await ProductQuestionService.getAllPersonalDialogs();
      }

      setState(() {
        _personalDialogs = dialogs;
      });
    } catch (e) {
      if (mounted) {
        _showFloatingSnackBar('Ошибка загрузки диалогов: $e', isError: true);
      }
    }
  }

  Future<void> _loadQuestions() async {
    try {
      final questions = await ProductQuestionService.getQuestions(
        shopAddress: _selectedShopAddress,
      );

      setState(() {
        _allQuestions = questions;
      });
    } catch (e) {
      if (mounted) {
        _showFloatingSnackBar('Ошибка загрузки вопросов: $e', isError: true);
      }
    }
  }

  void _showFloatingSnackBar(String message, {bool isError = false, bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : (isSuccess ? Icons.check_circle : Icons.info_outline),
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red[700] : (isSuccess ? Colors.green[700] : _primaryColor),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  bool _isExpired(ProductQuestion question) {
    try {
      final questionTime = DateTime.parse(question.timestamp);
      final now = DateTime.now();
      final difference = now.difference(questionTime);
      return difference.inMinutes >= _expiredMinutes;
    } catch (e) {
      return false;
    }
  }

  List<Shop> _getUnansweredShops(ProductQuestion question) {
    final answeredShops = question.messages
        .where((m) => m.senderType == 'employee' && m.shopAddress != null)
        .map((m) => m.shopAddress!)
        .toSet();

    return _shops.where((shop) =>
      !answeredShops.contains(shop.address)
    ).toList();
  }

  Future<Shop?> _showShopSelectionDialog(ProductQuestion question) async {
    final unansweredShops = _getUnansweredShops(question);

    if (unansweredShops.isEmpty) {
      _showFloatingSnackBar('Все магазины уже ответили на этот вопрос');
      return null;
    }

    return await showDialog<Shop>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: _orangeGradient),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.store, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Выберите магазин',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // Shop list
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: unansweredShops.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final shop = unansweredShops[index];
                  return InkWell(
                    onTap: () => Navigator.pop(context, shop),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: _orangeGradient),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.storefront,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shop.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  shop.address,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Colors.grey[400],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // Cancel button
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                ),
                child: const Text('Отмена'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasUnansweredShops(ProductQuestion question) {
    if (!question.isAnswered) {
      return true;
    }
    return false;
  }

  List<ProductQuestion> get _pendingQuestions {
    return _allQuestions.where((q) => !q.isAnswered && !_isExpired(q)).toList();
  }

  List<ProductQuestion> get _expiredQuestions {
    return _allQuestions.where((q) => (!q.isAnswered || _hasUnansweredShops(q)) && _isExpired(q)).toList();
  }

  List<ProductQuestion> get _answeredQuestions {
    return _allQuestions.where((q) => q.isAnswered && !_hasUnansweredShops(q)).toList();
  }

  String _formatTimestamp(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      return '${date.day}.${date.month}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp;
    }
  }

  String _formatTimeRemaining(ProductQuestion question) {
    try {
      final questionTime = DateTime.parse(question.timestamp);
      final expireTime = questionTime.add(const Duration(minutes: _expiredMinutes));
      final now = DateTime.now();
      final remaining = expireTime.difference(now);

      if (remaining.isNegative) return 'Истекло';

      final minutes = remaining.inMinutes;
      if (minutes < 1) return '< 1 мин';
      return '$minutes мин.';
    } catch (e) {
      return '';
    }
  }

  int get _unreadDialogsCount => _personalDialogs.where((d) => d.hasUnreadFromClient).length;
  int get _pendingCount => _pendingQuestions.length;
  int get _expiredCount => _expiredQuestions.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Ответы (поиск товара)'),
        backgroundColor: _primaryColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadQuestions();
              _loadPersonalDialogs();
            },
            tooltip: 'Обновить',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: _primaryColor,
              indicatorWeight: 3,
              labelColor: _primaryColor,
              unselectedLabelColor: Colors.grey[600],
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              tabs: [
                _buildModernTab('Ожидают', _pendingCount + _unreadDialogsCount, _orangeGradient),
                _buildModernTab('Не отвечено', _expiredCount, _redGradient),
                _buildModernTab('Отвеченные', _answeredQuestions.length, _greenGradient),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCombinedPendingTab(),
          _buildQuestionsTab(_expiredQuestions, isExpired: true),
          _buildQuestionsTab(_answeredQuestions, isAnswered: true),
        ],
      ),
    );
  }

  Widget _buildModernTab(String text, int count, List<Color> gradientColors) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: gradientColors[0].withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestionsTab(List<ProductQuestion> questions, {
    bool isPending = false,
    bool isExpired = false,
    bool isAnswered = false,
    List<PersonalProductDialog>? personalDialogs,
  }) {
    return Column(
      children: [
        // Modern shop filter
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.store, color: _accentColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedShopAddress,
                    hint: const Text('Все магазины'),
                    isExpanded: true,
                    icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[600]),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Все магазины'),
                      ),
                      ..._shops.map((shop) => DropdownMenuItem<String>(
                        value: shop.address,
                        child: Text(
                          shop.address,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedShopAddress = value;
                      });
                      _loadQuestions();
                      _loadPersonalDialogs();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // Warning for expired tab
        if (isExpired && !_isAdmin)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red[50]!, Colors.red[100]!],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.warning_amber_rounded, color: Colors.red[700], size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Время ответа истекло. Только администратор может отвечать.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.red[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Questions list
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                  ),
                )
              : (questions.isEmpty && (personalDialogs == null || personalDialogs.isEmpty))
                  ? _buildEmptyState(isPending, isExpired, isAnswered)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: (personalDialogs?.length ?? 0) + questions.length,
                      itemBuilder: (context, index) {
                        if (personalDialogs != null && index < personalDialogs.length) {
                          final dialog = personalDialogs[index];
                          return _buildModernPersonalDialogCard(dialog);
                        }

                        final questionIndex = index - (personalDialogs?.length ?? 0);
                        final question = questions[questionIndex];
                        return _buildModernQuestionCard(
                          question,
                          isPending: isPending,
                          isExpired: isExpired,
                          isAnswered: isAnswered,
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isPending, bool isExpired, bool isAnswered) {
    IconData icon;
    String title;
    String subtitle;
    List<Color> gradientColors;

    if (isPending) {
      icon = Icons.hourglass_empty;
      title = 'Нет ожидающих вопросов';
      subtitle = 'Все вопросы обработаны или истекли';
      gradientColors = _orangeGradient;
    } else if (isExpired) {
      icon = Icons.timer_off;
      title = 'Нет просроченных вопросов';
      subtitle = 'Отлично! Все вопросы отвечены вовремя';
      gradientColors = _redGradient;
    } else {
      icon = Icons.check_circle_outline;
      title = 'Нет отвеченных вопросов';
      subtitle = 'Отвеченные вопросы появятся здесь';
      gradientColors = _greenGradient;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradientColors.map((c) => c.withOpacity(0.15)).toList()),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 48,
              color: gradientColors[0],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernQuestionCard(ProductQuestion question, {
    bool isPending = false,
    bool isExpired = false,
    bool isAnswered = false,
  }) {
    final canAnswer = isPending || (_isAdmin && isExpired);

    List<Color> statusGradient;
    IconData statusIcon;

    if (isAnswered) {
      statusGradient = _greenGradient;
      statusIcon = Icons.check_circle;
    } else if (isExpired) {
      statusGradient = _redGradient;
      statusIcon = Icons.timer_off;
    } else {
      statusGradient = _orangeGradient;
      statusIcon = Icons.schedule;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            if (isExpired && !_isAdmin) {
              _showFloatingSnackBar('Время ответа истекло. Только администратор может отвечать.', isError: true);
              return;
            }

            String shopAddressForAnswer;

            if (!question.isNetworkWide) {
              shopAddressForAnswer = question.shopAddress;
            } else {
              final selectedShop = await _showShopSelectionDialog(question);
              if (selectedShop == null) return;
              shopAddressForAnswer = selectedShop.address;
            }

            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProductQuestionAnswerPage(
                  questionId: question.id,
                  shopAddress: shopAddressForAnswer,
                  canAnswer: canAnswer,
                ),
              ),
            );
            _loadQuestions();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: statusGradient),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: statusGradient[0].withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        statusIcon,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            question.clientName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            question.clientPhone,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status badge
                    if (isPending)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: _orangeGradient),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer, color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              _formatTimeRemaining(question),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (isExpired)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: _redGradient),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Просрочено',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!canAnswer && !isAnswered)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.lock, size: 16, color: Colors.grey[500]),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Shop info
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.store, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          question.shopAddress,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (question.isNetworkWide) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Вся сеть',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Question text
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Text(
                    question.questionText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[800],
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Footer
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      _formatTimestamp(question.timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                    if (question.isAnswered && question.answeredByName != null) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, size: 12, color: Colors.green[700]),
                            const SizedBox(width: 4),
                            Text(
                              question.answeredByName!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: Colors.grey[400],
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

  Widget _buildModernPersonalDialogCard(PersonalProductDialog dialog) {
    final hasUnread = dialog.hasUnreadFromClient;
    final lastMessage = dialog.getLastMessage();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: hasUnread ? Border.all(color: Colors.orange[300]!, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: hasUnread
                ? Colors.orange.withOpacity(0.15)
                : Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProductQuestionEmployeeDialogPage(
                  dialogId: dialog.id,
                  shopAddress: dialog.shopAddress,
                  clientName: dialog.clientName,
                ),
              ),
            );
            _loadPersonalDialogs();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: hasUnread ? _orangeGradient : [_primaryColor, _accentColor],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: (hasUnread ? Colors.orange : _primaryColor).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.chat_bubble,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        if (hasUnread)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: _redGradient),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Center(
                                child: Text(
                                  '!',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  dialog.clientName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dialog.clientPhone,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasUnread)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: _orangeGradient),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mark_unread_chat_alt, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Новое',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Shop info
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.store, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          dialog.shopAddress,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (lastMessage != null) ...[
                  const SizedBox(height: 12),
                  // Last message
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasUnread ? Colors.orange[50] : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hasUnread ? Colors.orange[200]! : Colors.grey[200]!,
                      ),
                    ),
                    child: Text(
                      lastMessage.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: hasUnread ? Colors.orange[900] : Colors.grey[800],
                        fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Timestamp
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        _formatTimestamp(lastMessage.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: Colors.grey[400],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCombinedPendingTab() {
    final unreadDialogs = _personalDialogs.where((d) => d.hasUnreadFromClient).toList();

    return _buildQuestionsTab(
      _pendingQuestions,
      isPending: true,
      personalDialogs: unreadDialogs,
    );
  }
}

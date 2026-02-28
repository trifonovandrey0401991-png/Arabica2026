import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../models/product_question_model.dart';
import '../services/product_question_service.dart';
import 'product_question_answer_page.dart';
import 'product_question_employee_dialog_page.dart';
import '../../shops/models/shop_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

class ProductQuestionsManagementPage extends StatefulWidget {
  const ProductQuestionsManagementPage({super.key});

  @override
  State<ProductQuestionsManagementPage> createState() => _ProductQuestionsManagementPageState();
}

class _ProductQuestionsManagementPageState extends State<ProductQuestionsManagementPage>
    with WidgetsBindingObserver {
  List<ProductQuestion> _allQuestions = [];
  List<PersonalProductDialog> _personalDialogs = [];
  List<Shop> _shops = [];
  bool _isLoading = true;
  String? _selectedShopAddress;
  Timer? _refreshTimer;

  // 0 = Ожидают, 1 = Не отвечено, 2 = Отвеченные
  int _selectedTab = 0;

  // Роль пользователя
  String _userRole = 'employee';
  bool get _isAdmin => _userRole == 'admin' || _userRole == 'developer';

  // Таймаут для "Не отвеченные" - 30 минут
  static const int _expiredMinutes = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserRole();
    _loadData();
    _refreshTimer = Timer.periodic(Duration(seconds: 10), (_) => _loadDataSilent());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      _refreshTimer ??= Timer.periodic(Duration(seconds: 10), (_) => _loadDataSilent());
      _loadDataSilent();
    }
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
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
    if (mounted) setState(() {
      _isLoading = true;
    });

    try {
      final shops = await Shop.loadShopsFromServer();
      await _loadQuestions();
      await _loadPersonalDialogs();

      if (!mounted) return;
      setState(() {
        _shops = shops;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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

      if (mounted) setState(() {
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

      if (mounted) setState(() {
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
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red[700] : (isSuccess ? Colors.green[700] : AppColors.emerald),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        margin: EdgeInsets.all(16.w),
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
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: AppColors.emerald,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
                border: Border(bottom: BorderSide(color: AppColors.gold.withOpacity(0.3))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                    ),
                    child: Icon(Icons.store, color: AppColors.gold, size: 24),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Выберите магазин',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18.sp,
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
                padding: EdgeInsets.symmetric(vertical: 8.h),
                itemCount: unansweredShops.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: Colors.white.withOpacity(0.08),
                ),
                itemBuilder: (context, index) {
                  final shop = unansweredShops[index];
                  return InkWell(
                    onTap: () => Navigator.pop(context, shop),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.emerald.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                            ),
                            child: Icon(Icons.storefront, color: AppColors.gold, size: 24),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shop.name,
                                  style: TextStyle(
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  shop.address,
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: Colors.white.withOpacity(0.5),
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
                            color: AppColors.gold.withOpacity(0.5),
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
              padding: EdgeInsets.all(16.w),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: AppColors.gold),
                child: Text('Отмена'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasUnansweredShops(ProductQuestion question) {
    if (!question.isAnswered) return true;
    if (question.isNetworkWide) {
      final answeredShops = question.messages
          .where((m) => m.senderType == 'employee' && m.shopAddress != null)
          .map((m) => m.shopAddress!)
          .toSet();
      return _shops.any((shop) => !answeredShops.contains(shop.address));
    }
    return false;
  }

  List<ProductQuestion> get _pendingQuestions {
    return _allQuestions.where((q) =>
      (!q.isAnswered && !_isExpired(q)) || q.hasUnreadFromClient
    ).toList();
  }

  List<ProductQuestion> get _expiredQuestions {
    return _allQuestions.where((q) =>
      (!q.isAnswered || _hasUnansweredShops(q)) && _isExpired(q) && !q.hasUnreadFromClient
    ).toList();
  }

  List<ProductQuestion> get _answeredQuestions {
    return _allQuestions.where((q) =>
      q.isAnswered && !_hasUnansweredShops(q) && !q.hasUnreadFromClient
    ).toList();
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
      final expireTime = questionTime.add(Duration(minutes: _expiredMinutes));
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
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.15, 0.4],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AppBar
              Padding(
                padding: EdgeInsets.fromLTRB(4.w, 8.h, 4.w, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white.withOpacity(0.8),
                        size: 22,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Поиск товара',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        _loadQuestions();
                        _loadPersonalDialogs();
                      },
                      icon: Icon(
                        Icons.refresh_rounded,
                        color: AppColors.gold.withOpacity(0.7),
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
              // 3 tabs
              Padding(
                padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 4.h),
                child: Row(
                  children: [
                    Expanded(child: _buildTopTab(0, 'Ожидают', _pendingCount + _unreadDialogsCount, Color(0xFFFF6B35))),
                    SizedBox(width: 6.w),
                    Expanded(child: _buildTopTab(1, 'Не отвечено', _expiredCount, Color(0xFFE53935))),
                    SizedBox(width: 6.w),
                    Expanded(child: _buildTopTab(2, 'Отвеченные', _answeredQuestions.length, Color(0xFF00b09b))),
                  ],
                ),
              ),
              // Shop filter
              Padding(
                padding: EdgeInsets.only(top: 4.h),
                child: _buildShopFilter(),
              ),
              // Content area
              Expanded(
                child: _selectedTab == 2
                    ? _buildAnsweredContent()
                    : _selectedTab == 0
                        ? _buildPendingContent()
                        : _buildExpiredContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopTab(int index, String label, int count, Color accentColor) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.emerald.withOpacity(0.8) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected ? AppColors.gold.withOpacity(0.6) : Colors.white.withOpacity(0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
                fontSize: 11.sp,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (count > 0) ...[
              SizedBox(width: 6.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShopFilter() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(Icons.store_rounded, color: AppColors.gold.withOpacity(0.7), size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                canvasColor: AppColors.emeraldDark,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedShopAddress,
                  hint: Text('Все магазины', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                  isExpanded: true,
                  icon: Icon(Icons.keyboard_arrow_down, color: AppColors.gold.withOpacity(0.5)),
                  dropdownColor: AppColors.emeraldDark,
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14.sp),
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text('Все магазины', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    ),
                    ..._shops.map((shop) => DropdownMenuItem<String>(
                      value: shop.address,
                      child: Text(
                        shop.address,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(color: Colors.white.withOpacity(0.9)),
                      ),
                    )),
                  ],
                  onChanged: (value) {
                    if (mounted) setState(() {
                      _selectedShopAddress = value;
                    });
                    _loadQuestions();
                    _loadPersonalDialogs();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingContent() {
    final unreadDialogs = _personalDialogs.where((d) => d.hasUnreadFromClient).toList();
    return _buildQuestionsList(
      _pendingQuestions,
      isPending: true,
      personalDialogs: unreadDialogs,
    );
  }

  Widget _buildExpiredContent() {
    return Column(
      children: [
        // Warning for expired tab (non-admin)
        if (!_isAdmin)
          Container(
            margin: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red[300], size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Время ответа истекло. Только администратор может отвечать.',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.red[300],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _buildQuestionsList(_expiredQuestions, isExpired: true),
        ),
      ],
    );
  }

  Widget _buildAnsweredContent() {
    return _buildQuestionsList(_answeredQuestions, isAnswered: true);
  }

  Widget _buildQuestionsList(
    List<ProductQuestion> questions, {
    bool isPending = false,
    bool isExpired = false,
    bool isAnswered = false,
    List<PersonalProductDialog>? personalDialogs,
  }) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppColors.gold));
    }

    final totalCount = (personalDialogs?.length ?? 0) + questions.length;
    if (totalCount == 0) {
      return _buildEmptyState(isPending, isExpired, isAnswered);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
        itemCount: totalCount,
        itemBuilder: (context, index) {
          if (personalDialogs != null && index < personalDialogs.length) {
            return _buildPersonalDialogCard(personalDialogs[index]);
          }
          final questionIndex = index - (personalDialogs?.length ?? 0);
          return _buildQuestionCard(
            questions[questionIndex],
            isPending: isPending,
            isExpired: isExpired,
            isAnswered: isAnswered,
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isPending, bool isExpired, bool isAnswered) {
    IconData icon;
    String title;

    if (isPending) {
      icon = Icons.hourglass_empty_rounded;
      title = 'Нет ожидающих вопросов';
    } else if (isExpired) {
      icon = Icons.timer_off_rounded;
      title = 'Нет просроченных вопросов';
    } else {
      icon = Icons.check_circle_outline_rounded;
      title = 'Нет отвеченных вопросов';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(color: AppColors.gold.withOpacity(0.3)),
            ),
            child: Icon(icon, size: 32, color: AppColors.gold.withOpacity(0.5)),
          ),
          SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(ProductQuestion question, {
    bool isPending = false,
    bool isExpired = false,
    bool isAnswered = false,
  }) {
    final hasClientReply = question.hasUnreadFromClient;
    final canAnswer = isPending || hasClientReply || (_isAdmin && isExpired);

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: hasClientReply
            ? AppColors.emerald.withOpacity(0.4)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: hasClientReply
              ? AppColors.gold.withOpacity(0.6)
              : Colors.white.withOpacity(0.1),
          width: hasClientReply ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(16.r),
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

            if (!mounted) return;
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
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    // Status icon
                    Container(
                      padding: EdgeInsets.all(9.w),
                      decoration: BoxDecoration(
                        color: hasClientReply
                            ? Color(0xFFFF6B35).withOpacity(0.2)
                            : isAnswered
                                ? Color(0xFF00b09b).withOpacity(0.2)
                                : isExpired
                                    ? Colors.red.withOpacity(0.2)
                                    : AppColors.gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: hasClientReply
                              ? Color(0xFFFF6B35).withOpacity(0.4)
                              : isAnswered
                                  ? Color(0xFF00b09b).withOpacity(0.4)
                                  : isExpired
                                      ? Colors.red.withOpacity(0.4)
                                      : AppColors.gold.withOpacity(0.3),
                        ),
                      ),
                      child: Icon(
                        hasClientReply
                            ? Icons.mark_unread_chat_alt
                            : isAnswered
                                ? Icons.check_circle
                                : isExpired
                                    ? Icons.timer_off
                                    : Icons.schedule,
                        color: hasClientReply
                            ? Color(0xFFFF6B35)
                            : isAnswered
                                ? Color(0xFF96c93d)
                                : isExpired
                                    ? Colors.red[300]
                                    : AppColors.gold,
                        size: 20,
                      ),
                    ),
                    SizedBox(width: 10),
                    // Client info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            question.clientName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15.sp,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                          Text(
                            question.clientPhone,
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: Colors.white.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status badges
                    if (hasClientReply)
                      _buildBadge('Ответ клиента', Color(0xFFFF6B35)),
                    if (isPending && !hasClientReply)
                      _buildBadge(_formatTimeRemaining(question), AppColors.gold),
                    if (isExpired && !hasClientReply)
                      _buildBadge('Просрочено', Colors.red),
                    if (!canAnswer && !isAnswered)
                      Container(
                        padding: EdgeInsets.all(6.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Icon(Icons.lock, size: 16, color: Colors.white.withOpacity(0.3)),
                      ),
                  ],
                ),
                SizedBox(height: 10),
                // Shop info
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.store_rounded, size: 14, color: AppColors.gold.withOpacity(0.6)),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          question.shopAddress,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.white.withOpacity(0.5),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (question.isNetworkWide) ...[
                        SizedBox(width: 8),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: Colors.tealAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4.r),
                            border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
                          ),
                          child: Text(
                            'Вся сеть',
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: Colors.tealAccent.withOpacity(0.8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 10),
                // Question text
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Text(
                    question.questionText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.white.withOpacity(0.7),
                      height: 1.4,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                // Footer
                Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 14, color: Colors.white.withOpacity(0.3)),
                    SizedBox(width: 4),
                    Text(
                      _formatTimestamp(question.timestamp),
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                    if (question.isAnswered && question.answeredByName != null) ...[
                      SizedBox(width: 10),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                        decoration: BoxDecoration(
                          color: Color(0xFF00b09b).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, size: 12, color: Color(0xFF96c93d)),
                            SizedBox(width: 4),
                            Text(
                              question.answeredByName!,
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: Color(0xFF96c93d),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Spacer(),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: AppColors.gold.withOpacity(0.4),
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

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10.sp,
        ),
      ),
    );
  }

  Widget _buildPersonalDialogCard(PersonalProductDialog dialog) {
    final hasUnread = dialog.hasUnreadFromClient;
    final lastMessage = dialog.getLastMessage();

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: hasUnread
            ? AppColors.emerald.withOpacity(0.4)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: hasUnread
              ? AppColors.gold.withOpacity(0.6)
              : Colors.white.withOpacity(0.1),
          width: hasUnread ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(16.r),
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
            padding: EdgeInsets.all(14.w),
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
                          padding: EdgeInsets.all(9.w),
                          decoration: BoxDecoration(
                            color: hasUnread
                                ? Color(0xFFFF6B35).withOpacity(0.2)
                                : AppColors.emerald.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: hasUnread
                                  ? Color(0xFFFF6B35).withOpacity(0.4)
                                  : AppColors.gold.withOpacity(0.3),
                            ),
                          ),
                          child: Icon(
                            Icons.chat_bubble_rounded,
                            color: hasUnread ? Color(0xFFFF6B35) : AppColors.gold,
                            size: 20,
                          ),
                        ),
                        if (hasUnread)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.night, width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  '!',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.sp,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dialog.clientName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15.sp,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                          Text(
                            dialog.clientPhone,
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: Colors.white.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasUnread)
                      _buildBadge('Новое', Color(0xFFFF6B35)),
                  ],
                ),
                SizedBox(height: 10),
                // Shop info
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.store_rounded, size: 14, color: AppColors.gold.withOpacity(0.6)),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          dialog.shopAddress,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.white.withOpacity(0.5),
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
                  SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      color: hasUnread
                          ? AppColors.gold.withOpacity(0.08)
                          : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(
                        color: hasUnread
                            ? AppColors.gold.withOpacity(0.2)
                            : Colors.white.withOpacity(0.06),
                      ),
                    ),
                    child: Text(
                      lastMessage.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: Colors.white.withOpacity(hasUnread ? 0.8 : 0.6),
                        fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                        height: 1.4,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded, size: 14, color: Colors.white.withOpacity(0.3)),
                      SizedBox(width: 4),
                      Text(
                        _formatTimestamp(lastMessage.timestamp),
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                      Spacer(),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: AppColors.gold.withOpacity(0.4),
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
}

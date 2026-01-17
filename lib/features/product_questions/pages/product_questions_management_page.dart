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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadPersonalDialogs() async {
    try {
      List<PersonalProductDialog> dialogs;
      print('📋 DEBUG: Loading personal dialogs, _selectedShopAddress = $_selectedShopAddress');
      if (_selectedShopAddress != null) {
        print('📋 DEBUG: Calling getShopPersonalDialogs for shop: $_selectedShopAddress');
        dialogs = await ProductQuestionService.getShopPersonalDialogs(_selectedShopAddress!);
      } else {
        print('📋 DEBUG: Calling getAllPersonalDialogs');
        dialogs = await ProductQuestionService.getAllPersonalDialogs();
      }

      print('📋 DEBUG: Loaded ${dialogs.length} personal dialogs');
      for (var dialog in dialogs) {
        print('  - Dialog: ${dialog.id}, shop: ${dialog.shopAddress}, client: ${dialog.clientName}');
      }

      setState(() {
        _personalDialogs = dialogs;
      });
    } catch (e) {
      print('❌ DEBUG: Error loading personal dialogs: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки диалогов: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadQuestions() async {
    try {
      // Загружаем все вопросы без фильтра
      final questions = await ProductQuestionService.getQuestions(
        shopAddress: _selectedShopAddress,
      );

      setState(() {
        _allQuestions = questions;
      });
    } catch (e) {
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

  /// Проверяет, истёк ли срок ответа (более 30 минут)
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

  /// Получить список магазинов, которые еще не ответили на вопрос
  List<Shop> _getUnansweredShops(ProductQuestion question) {
    // Получить список магазинов, которые уже ответили (из сообщений от сотрудников)
    final answeredShops = question.messages
        .where((m) => m.senderType == 'employee' && m.shopAddress != null)
        .map((m) => m.shopAddress!)
        .toSet();

    // Вернуть только те магазины, которые НЕ ответили
    return _shops.where((shop) =>
      !answeredShops.contains(shop.address)
    ).toList();
  }

  /// Показать диалог выбора магазина
  Future<Shop?> _showShopSelectionDialog(ProductQuestion question) async {
    final unansweredShops = _getUnansweredShops(question);

    if (unansweredShops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Все магазины уже ответили на этот вопрос'),
          backgroundColor: Colors.orange,
        ),
      );
      return null;
    }

    return await showDialog<Shop>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.store, color: Colors.orange[700], size: 24),
            const SizedBox(width: 8),
            const Text('Выберите магазин'),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: unansweredShops.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final shop = unansweredShops[index];
              return InkWell(
                onTap: () => Navigator.pop(context, shop),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Colors.orange[700]!,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.orange[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.storefront,
                          color: Colors.orange[700],
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
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              shop.address,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[700],
            ),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  /// Проверить есть ли неотвеченные магазины
  bool _hasUnansweredShops(ProductQuestion question) {
    // Если вопрос не отвечен вообще, значит есть неотвеченные магазины
    if (!question.isAnswered) {
      return true;
    }

    // Для network-wide вопросов, проверяем сообщения
    // Если есть хотя бы один магазин который не ответил - возвращаем true
    // Пока упрощенная логика - если есть ответ, считаем что все магазины ответили
    return false;
  }

  /// Вопросы, ожидающие ответа (неотвеченные, менее 30 минут)
  List<ProductQuestion> get _pendingQuestions {
    return _allQuestions.where((q) => !q.isAnswered && !_isExpired(q)).toList();
  }

  /// Не отвеченные вопросы (более 30 минут без ответа ИЛИ частично отвеченные)
  List<ProductQuestion> get _expiredQuestions {
    return _allQuestions.where((q) => (!q.isAnswered || _hasUnansweredShops(q)) && _isExpired(q)).toList();
  }

  /// Отвеченные вопросы (полностью - все магазины ответили)
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

  /// Форматирует оставшееся время до истечения
  String _formatTimeRemaining(ProductQuestion question) {
    try {
      final questionTime = DateTime.parse(question.timestamp);
      final expireTime = questionTime.add(const Duration(minutes: _expiredMinutes));
      final now = DateTime.now();
      final remaining = expireTime.difference(now);

      if (remaining.isNegative) return 'Истекло';

      final minutes = remaining.inMinutes;
      if (minutes < 1) return 'Менее минуты';
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
      appBar: AppBar(
        title: const Text('Ответы (поиск товара)'),
        backgroundColor: const Color(0xFF004D40),
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          isScrollable: true,
          tabs: [
            _buildTabWithBadge('Ожидают', _pendingCount + _unreadDialogsCount, Colors.orange),
            _buildTabWithBadge('Не отвечено', _expiredCount, Colors.red),
            const Tab(text: 'Отвеченные'),
          ],
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

  Widget _buildTabWithBadge(String text, int count, Color badgeColor) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(10),
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
        // Фильтр по магазину
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: DropdownButtonFormField<String>(
            value: _selectedShopAddress,
            decoration: const InputDecoration(
              labelText: 'Магазин',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Все магазины'),
              ),
              ..._shops.map((shop) => DropdownMenuItem<String>(
                value: shop.address,
                child: Text(shop.address),
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
        // Предупреждение для вкладки "Не отвеченные"
        if (isExpired && !_isAdmin)
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.red[50],
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.red[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Время ответа истекло. Только администратор может отвечать на эти вопросы.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Список вопросов и персональных диалогов
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : (questions.isEmpty && (personalDialogs == null || personalDialogs.isEmpty))
                  ? Center(
                      child: Text(
                        isPending ? 'Нет ожидающих вопросов' :
                        isExpired ? 'Нет просроченных вопросов' :
                        'Нет отвеченных вопросов',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: (personalDialogs?.length ?? 0) + questions.length,
                      itemBuilder: (context, index) {
                        // Сначала показываем персональные диалоги
                        if (personalDialogs != null && index < personalDialogs.length) {
                          final dialog = personalDialogs[index];
                          return _buildPersonalDialogCard(dialog);
                        }

                        // Потом обычные вопросы
                        final questionIndex = index - (personalDialogs?.length ?? 0);
                        final question = questions[questionIndex];
                        return _buildQuestionCard(
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

  Widget _buildQuestionCard(ProductQuestion question, {
    bool isPending = false,
    bool isExpired = false,
    bool isAnswered = false,
  }) {
    // Можно отвечать только если:
    // 1. Вопрос в "Ожидают ответа" (isPending)
    // 2. Или админ на любой вкладке с неотвеченными
    final canAnswer = isPending || (_isAdmin && isExpired);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isExpired ? Colors.red[50] : (isPending ? Colors.orange[50] : null),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isAnswered ? Colors.green : (isExpired ? Colors.red : Colors.orange),
          child: Icon(
            isAnswered ? Icons.check : (isExpired ? Icons.timer_off : Icons.schedule),
            color: Colors.white,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${question.shopAddress} | ${question.clientName}',
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isPending)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatTimeRemaining(question),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            if (isExpired)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Просрочено',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (question.isNetworkWide)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Вся сеть',
                  style: TextStyle(fontSize: 10, color: Colors.blue),
                ),
              ),
            Text(
              question.clientPhone,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              question.questionText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _formatTimestamp(question.timestamp),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
                if (question.isAnswered && question.answeredByName != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• Ответил: ${question.answeredByName}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.green,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: canAnswer || isAnswered
            ? const Icon(Icons.arrow_forward_ios, size: 16)
            : Icon(Icons.lock, size: 16, color: Colors.grey[400]),
        onTap: () async {
          // Если просрочено и не админ - показываем сообщение
          if (isExpired && !_isAdmin) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Время ответа истекло. Только администратор может отвечать.'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }

          String shopAddressForAnswer;

          // Если вопрос задан конкретному магазину (не "Вся сеть") - сразу переходим к ответу
          if (!question.isNetworkWide) {
            // Берём адрес магазина из вопроса
            shopAddressForAnswer = question.shopAddress;
          } else {
            // Для вопросов "Вся сеть" - показываем диалог выбора магазина
            final selectedShop = await _showShopSelectionDialog(question);
            if (selectedShop == null) return; // Пользователь отменил
            shopAddressForAnswer = selectedShop.address;
          }

          // Перейти на страницу ответа с выбранным магазином
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
          _loadQuestions(); // Обновляем после возврата
        },
      ),
    );
  }

  Widget _buildPersonalDialogCard(PersonalProductDialog dialog) {
    final hasUnread = dialog.hasUnreadFromClient;
    final lastMessage = dialog.getLastMessage();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: hasUnread ? Colors.orange[50] : null,
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundColor: hasUnread ? Colors.orange : const Color(0xFF004D40),
              child: const Icon(
                Icons.chat,
                color: Colors.white,
              ),
            ),
            if (hasUnread)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      '!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            const Icon(Icons.person, size: 16, color: Colors.grey),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${dialog.shopAddress} | ${dialog.clientName}',
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dialog.clientPhone,
              style: const TextStyle(fontSize: 12),
            ),
            if (lastMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                lastMessage.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                  color: hasUnread ? Colors.orange[800] : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatTimestamp(lastMessage.timestamp),
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                ),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
          _loadPersonalDialogs(); // Обновляем после возврата
        },
      ),
    );
  }

  Widget _buildPersonalDialogsTab() {
    return Column(
      children: [
        // Фильтр по магазину
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: DropdownButtonFormField<String>(
            value: _selectedShopAddress,
            decoration: const InputDecoration(
              labelText: 'Магазин',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Все магазины'),
              ),
              ..._shops.map((shop) => DropdownMenuItem<String>(
                value: shop.address,
                child: Text(shop.address),
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
        // Список персональных диалогов
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _personalDialogs.isEmpty
                  ? const Center(
                      child: Text(
                        'Нет персональных диалогов',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _personalDialogs.length,
                      itemBuilder: (context, index) {
                        final dialog = _personalDialogs[index];
                        final hasUnread = dialog.hasUnreadFromClient;
                        final lastMessage = dialog.getLastMessage();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          color: hasUnread ? Colors.orange[50] : null,
                          child: ListTile(
                            leading: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                CircleAvatar(
                                  backgroundColor: hasUnread
                                      ? Colors.orange
                                      : const Color(0xFF004D40),
                                  child: const Icon(
                                    Icons.chat,
                                    color: Colors.white,
                                  ),
                                ),
                                if (hasUnread)
                                  Positioned(
                                    right: -4,
                                    top: -4,
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Center(
                                        child: Text(
                                          '!',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${dialog.shopAddress} | ${dialog.clientName}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dialog.clientPhone,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (lastMessage != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    lastMessage.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                                      color: hasUnread ? Colors.orange[800] : null,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTimestamp(lastMessage.timestamp),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
                              _loadPersonalDialogs(); // Обновляем после возврата
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  /// Объединённая вкладка "Ожидают" с обычными вопросами и персональными диалогами
  Widget _buildCombinedPendingTab() {
    // Список непрочитанных персональных диалогов
    final unreadDialogs = _personalDialogs.where((d) => d.hasUnreadFromClient).toList();

    return _buildQuestionsTab(
      _pendingQuestions,
      isPending: true,
      personalDialogs: unreadDialogs,
    );
  }
}

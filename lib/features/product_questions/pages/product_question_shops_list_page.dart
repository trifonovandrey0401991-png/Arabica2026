import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../models/product_question_model.dart';
import '../services/product_question_service.dart';
import 'product_question_dialog_page.dart';
import 'product_question_client_dialog_page.dart';
import 'product_question_personal_dialog_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница списка магазинов для поиска товара
class ProductQuestionShopsListPage extends StatefulWidget {
  const ProductQuestionShopsListPage({super.key});

  @override
  State<ProductQuestionShopsListPage> createState() => _ProductQuestionShopsListPageState();
}

class _ProductQuestionShopsListPageState extends State<ProductQuestionShopsListPage> {
  // Dark emerald + gold palette
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  ProductQuestionGroupedData? _groupedData;
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(Duration(seconds: 5), (_) => _loadData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';

    if (phone.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final data = await ProductQuestionService.getClientGroupedDialogs(phone);
      if (mounted) {
        setState(() {
          _groupedData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.15, 0.4],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AppBar
              Padding(
                padding: EdgeInsets.fromLTRB(4.w, 8.h, 4.w, 8.h),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Поиск товара',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17.sp,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            'Мои диалоги',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: _gold.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: _gold))
                    : _groupedData == null || (_groupedData!.byShop.isEmpty && _groupedData!.networkWideQuestions.isEmpty)
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(18.r),
                                    border: Border.all(color: _gold.withOpacity(0.3)),
                                  ),
                                  child: Icon(
                                    Icons.forum_outlined,
                                    size: 32,
                                    color: _gold.withOpacity(0.5),
                                  ),
                                ),
                                SizedBox(height: 20),
                                Text(
                                  'Нет диалогов',
                                  style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadData,
                            color: _gold,
                            backgroundColor: _emeraldDark,
                            child: ListView(
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                              children: [
                                if (_groupedData!.networkWideQuestions.isNotEmpty)
                                  _buildNetworkWideCard(),
                                ..._buildShopCards(),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkWideCard() {
    final unread = _groupedData!.networkWideUnreadCount;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: unread > 0 ? _emerald.withOpacity(0.4) : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: unread > 0 ? _gold.withOpacity(0.5) : Colors.white.withOpacity(0.1),
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        leading: Stack(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _emerald.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: _gold.withOpacity(0.3)),
              ),
              child: Icon(Icons.public_rounded, size: 28, color: _gold),
            ),
            if (unread > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: EdgeInsets.all(4.w),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: _night, width: 2),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : unread.toString(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          'Вся сеть',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
        subtitle: Text(
          '${_groupedData!.networkWideQuestions.length} вопрос(ов)',
          style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.5)),
        ),
        trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: _gold.withOpacity(0.5)),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductQuestionClientDialogPage(),
            ),
          );
          _loadData();
        },
      ),
    );
  }

  List<Widget> _buildShopCards() {
    final sortedShops = _groupedData!.getSortedShops();

    return sortedShops.map((shopAddress) {
      final group = _groupedData!.byShop[shopAddress]!;
      final unread = group.unreadCount;
      final lastMessage = group.getLastMessage();

      return Container(
        margin: EdgeInsets.only(bottom: 8.h),
        decoration: BoxDecoration(
          color: unread > 0 ? _emerald.withOpacity(0.4) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: unread > 0 ? _gold.withOpacity(0.5) : Colors.white.withOpacity(0.1),
          ),
        ),
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          leading: Stack(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _emerald.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: _gold.withOpacity(0.3)),
                ),
                child: Icon(Icons.store_rounded, size: 28, color: _gold),
              ),
              if (unread > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: EdgeInsets.all(4.w),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: _night, width: 2),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : unread.toString(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            shopAddress,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.9),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: lastMessage != null
              ? Padding(
                  padding: EdgeInsets.only(top: 4.h),
                  child: Row(
                    children: [
                      Icon(
                        lastMessage.senderType == 'client'
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 14,
                        color: lastMessage.senderType == 'client'
                            ? _gold.withOpacity(0.7)
                            : Colors.tealAccent.withOpacity(0.7),
                      ),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          lastMessage.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.white.withOpacity(unread > 0 ? 0.8 : 0.5),
                            fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Text(
                  '${group.questions.length + group.dialogs.length} сообщени(й/я)',
                  style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.5)),
                ),
          trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: _gold.withOpacity(0.5)),
          onTap: () async {
            if (group.dialogs.isNotEmpty) {
              final personalDialog = group.dialogs.last;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProductQuestionPersonalDialogPage(
                    dialogId: personalDialog.id,
                    shopAddress: shopAddress,
                  ),
                ),
              );
              _loadData();
            } else if (group.questions.isNotEmpty) {
              final questionId = group.questions.last.id;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProductQuestionDialogPage(
                    questionId: questionId,
                  ),
                ),
              );
              _loadData();
            }
          },
        ),
      );
    }).toList();
  }
}

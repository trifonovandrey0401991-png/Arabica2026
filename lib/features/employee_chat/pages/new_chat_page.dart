import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/employee_chat_model.dart';
import '../services/employee_chat_service.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/pages/employees_page.dart' show Employee;
import '../../shops/services/shop_service.dart';
import '../../shops/models/shop_model.dart';
import 'create_group_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница создания нового чата — dark emerald стиль
class NewChatPage extends StatefulWidget {
  final String userPhone;
  final String userName;
  final bool isAdmin;

  const NewChatPage({
    super.key,
    required this.userPhone,
    required this.userName,
    this.isAdmin = false,
  });

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Employee> _employees = [];
  List<Shop> _shops = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchFocusNode = FocusNode();

  int get _tabCount => widget.isAdmin ? 4 : 3;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final employees = await EmployeeService.getEmployees();
      final shops = await ShopService.getShops();

      if (mounted) {
        setState(() {
          _employees = employees.where((e) => e.phone != widget.userPhone).toList();
          _shops = shops;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Ошибка загрузки данных')),
              ],
            ),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }

  Future<void> _openGeneralChat() async {
    HapticFeedback.lightImpact();
    final chat = EmployeeChat(
      id: 'general',
      type: EmployeeChatType.general,
      name: 'Общий чат',
    );
    if (mounted) {
      Navigator.pop(context, chat);
    }
  }

  Future<void> _openPrivateChat(Employee employee) async {
    HapticFeedback.selectionClick();
    setState(() => _isLoading = true);

    try {
      final chat = await EmployeeChatService.getOrCreatePrivateChat(
        widget.userPhone,
        employee.phone ?? '',
      );

      if (chat != null && mounted) {
        final chatWithName = EmployeeChat(
          id: chat.id,
          type: chat.type,
          name: employee.name,
          participants: chat.participants,
        );
        Navigator.pop(context, chatWithName);
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Ошибка создания чата'),
                ],
              ),
              backgroundColor: Colors.red[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        );
      }
    }
  }

  Future<void> _openShopChat(Shop shop) async {
    HapticFeedback.selectionClick();
    setState(() => _isLoading = true);

    try {
      final chat = await EmployeeChatService.getOrCreateShopChat(shop.address, phone: widget.userPhone);

      if (chat != null && mounted) {
        Navigator.pop(context, chat);
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Ошибка создания чата'),
                ],
              ),
              backgroundColor: Colors.red[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        );
      }
    }
  }

  Future<void> _openCreateGroup() async {
    HapticFeedback.lightImpact();
    final result = await Navigator.push<EmployeeChat>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => CreateGroupPage(
          creatorPhone: widget.userPhone,
          creatorName: widget.userName,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    );

    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  List<Employee> get _filteredEmployees {
    if (_searchQuery.isEmpty) return _employees;
    final query = _searchQuery.toLowerCase();
    return _employees.where((e) {
      return e.name.toLowerCase().contains(query) ||
             (e.phone?.contains(query) ?? false);
    }).toList();
  }

  List<Shop> get _filteredShops {
    if (_searchQuery.isEmpty) return _shops;
    final query = _searchQuery.toLowerCase();
    return _shops.where((s) {
      return s.address.toLowerCase().contains(query);
    }).toList();
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
              // AppBar
              _buildAppBar(),
              // TabBar
              _buildTabBar(),
              // Content
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 20),
                            Text(
                              'Загрузка...',
                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16.sp),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          // Поиск
                          _buildSearchField(),
                          // Вкладки
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _buildGeneralTab(),
                                _buildPrivateTab(),
                                _buildShopTab(),
                                if (widget.isAdmin) _buildGroupTab(),
                              ],
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
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 0.h),
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
            child: Center(
              child: Text(
                'Новый чат',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: AppColors.emerald,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        dividerHeight: 0,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withOpacity(0.4),
        labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 11.sp),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w400, fontSize: 11.sp),
        tabs: [
          Tab(icon: Icon(Icons.public_rounded, size: 20), text: 'Общий'),
          Tab(icon: Icon(Icons.person_rounded, size: 20), text: 'Личный'),
          Tab(icon: Icon(Icons.store_rounded, size: 20), text: 'Магазин'),
          if (widget.isAdmin)
            Tab(icon: Icon(Icons.group_add_rounded, size: 20), text: 'Группа'),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: TextField(
          focusNode: _searchFocusNode,
          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15.sp),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'Поиск сотрудника или магазина...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 15.sp),
            prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.4), size: 22),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear_rounded, color: Colors.white.withOpacity(0.4), size: 20),
                    onPressed: () => setState(() => _searchQuery = ''),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          ),
          onChanged: (value) => setState(() => _searchQuery = value),
        ),
      ),
    );
  }

  Widget _buildGeneralTab() {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 600),
              curve: Curves.easeOutBack,
              builder: (context, value, child) => Transform.scale(scale: value, child: child),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Icon(Icons.public_rounded, size: 48, color: Colors.blue[300]),
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Общий чат',
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.95),
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Text(
                'Чат для всех сотрудников компании',
                style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.6)),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 32),
            GestureDetector(
              onTap: _openGeneralChat,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 36.w, vertical: 16.h),
                decoration: BoxDecoration(
                  color: AppColors.emerald,
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_rounded, color: Colors.white.withOpacity(0.9), size: 22),
                    SizedBox(width: 12),
                    Text(
                      'Открыть чат',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivateTab() {
    final employees = _filteredEmployees;

    if (employees.isEmpty) {
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
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Icon(
                _searchQuery.isEmpty ? Icons.people_outline_rounded : Icons.search_off_rounded,
                size: 32,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
            SizedBox(height: 20),
            Text(
              _searchQuery.isEmpty ? 'Нет сотрудников' : 'Ничего не найдено',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.8)),
            ),
            SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty ? 'Список сотрудников пуст' : 'Попробуйте изменить запрос',
              style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.4)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 16.w),
      itemCount: employees.length,
      itemBuilder: (context, index) {
        final employee = employees[index];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 200 + (index * 50).clamp(0, 300)),
          builder: (context, value, child) => Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: Opacity(opacity: value, child: child),
          ),
          child: GestureDetector(
            onTap: () => _openPrivateChat(employee),
            child: Container(
              margin: EdgeInsets.only(bottom: 8.h),
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        employee.name.isNotEmpty ? employee.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[300],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.name,
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.95),
                          ),
                        ),
                        SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.phone_outlined, size: 13, color: Colors.white.withOpacity(0.35)),
                            SizedBox(width: 4),
                            Text(
                              employee.phone ?? 'Нет телефона',
                              style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.4)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: Colors.white.withOpacity(0.6),
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShopTab() {
    final shops = _filteredShops;

    if (shops.isEmpty) {
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
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Icon(
                _searchQuery.isEmpty ? Icons.store_mall_directory_outlined : Icons.search_off_rounded,
                size: 32,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
            SizedBox(height: 20),
            Text(
              _searchQuery.isEmpty ? 'Нет магазинов' : 'Ничего не найдено',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.8)),
            ),
            SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty ? 'Список магазинов пуст' : 'Попробуйте изменить запрос',
              style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.4)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 16.w),
      itemCount: shops.length,
      itemBuilder: (context, index) {
        final shop = shops[index];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 200 + (index * 50).clamp(0, 300)),
          builder: (context, value, child) => Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: Opacity(opacity: value, child: child),
          ),
          child: GestureDetector(
            onTap: () => _openShopChat(shop),
            child: Container(
              margin: EdgeInsets.only(bottom: 8.h),
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Icon(Icons.store_rounded, size: 24, color: Colors.orange[300]),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shop.address,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.95),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.people_outline_rounded, size: 13, color: Colors.white.withOpacity(0.35)),
                            SizedBox(width: 4),
                            Text(
                              'Чат магазина',
                              style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.4)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: Colors.orange[300],
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupTab() {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 600),
              curve: Curves.easeOutBack,
              builder: (context, value, child) => Transform.scale(scale: value, child: child),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.purple.withOpacity(0.3)),
                ),
                child: Icon(Icons.groups_rounded, size: 48, color: Colors.purple[300]),
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Создать группу',
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.95),
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(color: Colors.purple.withOpacity(0.2)),
              ),
              child: Text(
                'Группа с любыми участниками:\nсотрудниками и клиентами',
                style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.6), height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 24),
            // Преимущества
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                children: [
                  _buildFeatureRow(Icons.group_add_rounded, 'Добавляйте участников'),
                  Divider(height: 20, color: Colors.white.withOpacity(0.08)),
                  _buildFeatureRow(Icons.image_rounded, 'Загружайте фото группы'),
                  Divider(height: 20, color: Colors.white.withOpacity(0.08)),
                  _buildFeatureRow(Icons.edit_rounded, 'Редактируйте название'),
                ],
              ),
            ),
            SizedBox(height: 28),
            GestureDetector(
              onTap: _openCreateGroup,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 36.w, vertical: 16.h),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.purple.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white.withOpacity(0.9), size: 22),
                    SizedBox(width: 12),
                    Text(
                      'Создать группу',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, color: Colors.purple[300], size: 20),
        ),
        SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.7)),
          ),
        ),
        Icon(Icons.check_circle_rounded, color: Colors.green[400], size: 20),
      ],
    );
  }
}

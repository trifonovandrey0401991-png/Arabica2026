import 'package:flutter/material.dart';
import '../services/employee_chat_service.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/pages/employees_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница управления участниками чата магазина — dark emerald стиль
class ShopChatMembersPage extends StatefulWidget {
  final String shopAddress;
  final String userPhone;

  const ShopChatMembersPage({
    super.key,
    required this.shopAddress,
    required this.userPhone,
  });

  @override
  State<ShopChatMembersPage> createState() => _ShopChatMembersPageState();
}

class _ShopChatMembersPageState extends State<ShopChatMembersPage> {
  // Dark emerald palette
  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);

  List<ShopChatMember> _members = [];
  List<Employee> _allEmployees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        EmployeeChatService.getShopChatMembers(widget.shopAddress),
        EmployeeService.getEmployees(),
      ]);

      if (mounted) {
        setState(() {
          _members = results[0] as List<ShopChatMember>;
          _allEmployees = results[1] as List<Employee>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          ),
        );
      }
    }
  }

  List<Employee> get _availableEmployees {
    final memberPhones = _members.map((m) => m.phone).toSet();
    return _allEmployees
        .where((e) => e.phone != null && !memberPhones.contains(e.phone))
        .toList();
  }

  Future<void> _showAddMembersDialog() async {
    final available = _availableEmployees;

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Все сотрудники уже добавлены в чат'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        ),
      );
      return;
    }

    final selectedPhones = <String>{};

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _night.withOpacity(0.98),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          title: Text('Добавить сотрудников',
              style: TextStyle(color: Colors.white.withOpacity(0.9))),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: available.length,
              itemBuilder: (context, index) {
                final employee = available[index];
                final isSelected = selectedPhones.contains(employee.phone);

                return CheckboxListTile(
                  value: isSelected,
                  title: Text(employee.name,
                      style: TextStyle(color: Colors.white.withOpacity(0.9))),
                  subtitle: Text(employee.phone ?? '',
                      style: TextStyle(color: Colors.white.withOpacity(0.4))),
                  activeColor: _emerald,
                  checkColor: Colors.white,
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true && employee.phone != null) {
                        selectedPhones.add(employee.phone!);
                      } else {
                        selectedPhones.remove(employee.phone);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
            ),
            ElevatedButton(
              onPressed: selectedPhones.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await _addMembers(selectedPhones.toList());
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _emerald,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
              ),
              child: Text('Добавить (${selectedPhones.length})'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMembers(List<String> phones) async {
    final success = await EmployeeChatService.addShopChatMembers(
      widget.shopAddress,
      phones,
    );

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Добавлено ${phones.length} сотрудников'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        ),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка добавления сотрудников'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        ),
      );
    }
  }

  Future<void> _removeMember(ShopChatMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _night.withOpacity(0.98),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Удалить участника?',
            style: TextStyle(color: Colors.white.withOpacity(0.9))),
        content: Text('Удалить ${member.name} из чата магазина?',
            style: TextStyle(color: Colors.white.withOpacity(0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
            ),
            child: Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await EmployeeChatService.removeShopChatMember(
        widget.shopAddress,
        member.phone,
        requesterPhone: widget.userPhone,
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.name} удалён из чата'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          ),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка удаления'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          ),
        );
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
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AppBar
              Padding(
                padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 8.h),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white.withOpacity(0.8), size: 22),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Участники чата',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.95),
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          Text(
                            widget.shopAddress,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 12.sp,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded,
                          color: Colors.white.withOpacity(0.7), size: 22),
                      onPressed: _loadData,
                    ),
                  ],
                ),
              ),
              // Body
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: Colors.white))
                    : _members.isEmpty
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
                                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                                  ),
                                  child: Icon(Icons.group_off, size: 32,
                                      color: Colors.white.withOpacity(0.4)),
                                ),
                                SizedBox(height: 20),
                                Text(
                                  'Нет участников',
                                  style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Добавьте сотрудников в чат магазина',
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: Colors.white.withOpacity(0.4),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadData,
                            color: Colors.white,
                            backgroundColor: _emerald,
                            child: ListView.builder(
                              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 80.h),
                              itemCount: _members.length,
                              itemBuilder: (context, index) {
                                final member = _members[index];
                                return Container(
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
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.2),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            member.name.isNotEmpty
                                                ? member.name[0].toUpperCase()
                                                : '?',
                                            style: TextStyle(
                                              color: Colors.orange[300],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18.sp,
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
                                              member.name,
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.95),
                                                fontSize: 15.sp,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              member.phone,
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.4),
                                                fontSize: 12.sp,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.remove_circle, color: Colors.red),
                                        onPressed: () => _removeMember(member),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: GestureDetector(
        onTap: _showAddMembersDialog,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: _emerald,
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add, color: Colors.white.withOpacity(0.9), size: 22),
              SizedBox(width: 10),
              Text(
                'Добавить',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w500,
                  fontSize: 14.sp,
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

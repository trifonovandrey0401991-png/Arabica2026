import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/employee_chat_model.dart';
import '../services/employee_chat_service.dart';
import '../../employees/pages/employees_page.dart' show Employee;
import '../../employees/services/employee_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница информации о группе — dark emerald стиль
class GroupInfoPage extends StatefulWidget {
  final EmployeeChat chat;
  final String currentUserPhone;

  const GroupInfoPage({
    super.key,
    required this.chat,
    required this.currentUserPhone,
  });

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  late EmployeeChat _chat;
  final _nameController = TextEditingController();
  bool _isEditing = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _chat = widget.chat;
    _nameController.text = _chat.name;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isCreator => _chat.isCreator(widget.currentUserPhone);

  Future<void> _updateGroupName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == _chat.name) {
      setState(() => _isEditing = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final updated = await EmployeeChatService.updateGroup(
        groupId: _chat.id,
        requesterPhone: widget.currentUserPhone,
        name: newName,
      );
      if (updated != null && mounted) {
        setState(() {
          _chat = updated;
          _isEditing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Название обновлено'),
            backgroundColor: AppColors.emerald,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (pickedFile == null) return;

    setState(() => _isLoading = true);
    try {
      final imageUrl = await EmployeeChatService.uploadGroupPhoto(File(pickedFile.path));
      if (imageUrl == null) throw Exception('Ошибка загрузки фото');

      final updated = await EmployeeChatService.updateGroup(
        groupId: _chat.id,
        requesterPhone: widget.currentUserPhone,
        imageUrl: imageUrl,
      );

      if (updated != null && mounted) {
        setState(() => _chat = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Фото обновлено'),
            backgroundColor: AppColors.emerald,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addMembers() async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddMembersSheet(
        existingParticipants: _chat.participants,
      ),
    );

    if (result == null || result.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final success = await EmployeeChatService.addGroupMembers(
        groupId: _chat.id,
        requesterPhone: widget.currentUserPhone,
        phones: result,
      );

      if (success && mounted) {
        final updated = await EmployeeChatService.getGroupInfo(_chat.id);
        if (updated != null) {
          setState(() => _chat = updated);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Добавлено участников: ${result.length}'),
            backgroundColor: AppColors.emerald,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeMember(String phone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.night.withOpacity(0.98),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Удалить участника?', style: TextStyle(color: Colors.white.withOpacity(0.9))),
        content: Text(
          'Удалить ${_chat.getParticipantName(phone)} из группы?',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final success = await EmployeeChatService.removeGroupMember(
        groupId: _chat.id,
        requesterPhone: widget.currentUserPhone,
        phone: phone,
      );

      if (success && mounted) {
        final updated = await EmployeeChatService.getGroupInfo(_chat.id);
        if (updated != null) {
          setState(() => _chat = updated);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Участник удалён'),
            backgroundColor: AppColors.emerald,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.night.withOpacity(0.98),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Выйти из группы?', style: TextStyle(color: Colors.white.withOpacity(0.9))),
        content: Text(
          'Вы уверены, что хотите покинуть эту группу?',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final success = await EmployeeChatService.leaveGroup(
        _chat.id,
        widget.currentUserPhone,
      );

      if (success && mounted) {
        Navigator.pop(context, 'left');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.night.withOpacity(0.98),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Удалить группу?', style: TextStyle(color: Colors.white.withOpacity(0.9))),
        content: Text(
          'Группа будет удалена для всех участников. Это действие нельзя отменить.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final success = await EmployeeChatService.deleteGroup(
        _chat.id,
        widget.currentUserPhone,
      );

      if (success && mounted) {
        Navigator.pop(context, 'deleted');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                      child: Center(
                        child: Text(
                          'О группе',
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
              ),
              // Body
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: Colors.white))
                    : ListView(
                        children: [
                          _buildHeader(),
                          Divider(color: Colors.white.withOpacity(0.08)),
                          _buildParticipantsSection(),
                          Divider(color: Colors.white.withOpacity(0.08)),
                          _buildActionsSection(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(16.w),
      child: Column(
        children: [
          // Аватар
          GestureDetector(
            onTap: _isCreator ? _changePhoto : null,
            child: Stack(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                    image: _chat.imageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_chat.imageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _chat.imageUrl == null
                      ? Icon(Icons.group, size: 50, color: Colors.white.withOpacity(0.4))
                      : null,
                ),
                if (_isCreator)
                  Positioned(
                    bottom: 0.h,
                    right: 0.w,
                    child: Container(
                      padding: EdgeInsets.all(6.w),
                      decoration: BoxDecoration(
                        color: AppColors.emerald,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 16),
          // Название
          if (_isEditing)
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: TextField(
                      controller: _nameController,
                      autofocus: true,
                      style: TextStyle(color: Colors.white.withOpacity(0.9)),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        hintText: 'Название группы',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.check, color: Colors.green[400]),
                  onPressed: _updateGroupName,
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white.withOpacity(0.5)),
                  onPressed: () {
                    _nameController.text = _chat.name;
                    setState(() => _isEditing = false);
                  },
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _chat.name,
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.95),
                  ),
                ),
                if (_isCreator)
                  IconButton(
                    icon: Icon(Icons.edit, size: 20, color: Colors.white.withOpacity(0.5)),
                    onPressed: () => setState(() => _isEditing = true),
                  ),
              ],
            ),
          SizedBox(height: 8),
          Text(
            '${_chat.participantsCount} участников',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
          if (_chat.creatorName != null)
            Text(
              'Создатель: ${_chat.creatorName}',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.sp),
            ),
        ],
      ),
    );
  }

  Widget _buildParticipantsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(16.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Участники (${_chat.participantsCount})',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              if (_isCreator)
                GestureDetector(
                  onTap: _addMembers,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: AppColors.emerald.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_add, size: 16, color: Colors.white.withOpacity(0.8)),
                        SizedBox(width: 6),
                        Text('Добавить',
                            style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.8))),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        ..._chat.participants.map((phone) => _buildParticipantTile(phone)),
      ],
    );
  }

  Widget _buildParticipantTile(String phone) {
    final name = _chat.getParticipantName(phone);
    final isCreator = phone == _chat.creatorPhone;
    final isMe = phone.replaceAll(RegExp(r'[\s\+]'), '') ==
        widget.currentUserPhone.replaceAll(RegExp(r'[\s\+]'), '');

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCreator ? AppColors.emerald : Colors.white.withOpacity(0.08),
          child: Icon(
            isCreator ? Icons.star : Icons.person,
            color: isCreator ? Colors.white : Colors.white.withOpacity(0.5),
          ),
        ),
        title: Row(
          children: [
            Text(name, style: TextStyle(color: Colors.white.withOpacity(0.9))),
            if (isMe)
              Text(' (Вы)',
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.sp)),
          ],
        ),
        subtitle: isCreator
            ? Text('Создатель', style: TextStyle(color: Colors.white.withOpacity(0.4)))
            : null,
        trailing: _isCreator && !isCreator
            ? IconButton(
                icon: Icon(Icons.remove_circle_outline, color: Colors.red),
                onPressed: () => _removeMember(phone),
              )
            : null,
      ),
    );
  }

  Widget _buildActionsSection() {
    return Column(
      children: [
        if (!_isCreator)
          ListTile(
            leading: Icon(Icons.exit_to_app, color: Colors.orange),
            title: Text('Выйти из группы',
                style: TextStyle(color: Colors.white.withOpacity(0.9))),
            onTap: _leaveGroup,
          ),
        if (_isCreator)
          ListTile(
            leading: Icon(Icons.delete, color: Colors.red),
            title: Text('Удалить группу', style: TextStyle(color: Colors.red)),
            onTap: _deleteGroup,
          ),
      ],
    );
  }
}

/// Шит для добавления участников — dark emerald стиль
class _AddMembersSheet extends StatefulWidget {
  final List<String> existingParticipants;

  _AddMembersSheet({required this.existingParticipants});

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final _searchController = TextEditingController();
  final List<String> _selected = [];
  List<Employee> _employees = [];
  List<ChatClient> _clients = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadParticipants();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadParticipants() async {
    try {
      final results = await Future.wait([
        EmployeeService.getEmployees(),
        EmployeeChatService.getClientsForGroupSelection(),
      ]);

      final normalizedExisting = widget.existingParticipants
          .map((p) => p.replaceAll(RegExp(r'[\s\+]'), ''))
          .toSet();

      _employees = (results[0] as List<Employee>).where((e) {
        final phone = (e.phone ?? '').replaceAll(RegExp(r'[\s\+]'), '');
        return !normalizedExisting.contains(phone);
      }).toList();

      _clients = (results[1] as List<ChatClient>).where((c) {
        final phone = c.phone.replaceAll(RegExp(r'[\s\+]'), '');
        return !normalizedExisting.contains(phone);
      }).toList();
    } catch (e) {
      // Ignore
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: AppColors.night.withOpacity(0.98),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.symmetric(vertical: 12.h),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          // Header
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Добавить участников',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                GestureDetector(
                  onTap: _selected.isEmpty ? null : () => Navigator.pop(context, _selected),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: _selected.isEmpty ? Colors.grey[700] : AppColors.emerald,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      'Добавить (${_selected.length})',
                      style: TextStyle(
                        color: Colors.white.withOpacity(_selected.isEmpty ? 0.4 : 0.9),
                        fontSize: 13.sp,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                style: TextStyle(color: Colors.white.withOpacity(0.9)),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: 'Поиск...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.4)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                ),
              ),
            ),
          ),
          SizedBox(height: 8),
          // List
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: Colors.white))
                : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final filteredEmployees = _employees.where((e) {
      final name = e.name.toLowerCase();
      final phone = (e.phone ?? '').toLowerCase();
      return name.contains(_searchQuery) || phone.contains(_searchQuery);
    }).toList();

    final filteredClients = _clients.where((c) {
      final name = (c.name ?? '').toLowerCase();
      final phone = c.phone.toLowerCase();
      return name.contains(_searchQuery) || phone.contains(_searchQuery);
    }).toList();

    if (filteredEmployees.isEmpty && filteredClients.isEmpty) {
      return Center(
        child: Text('Нет доступных участников',
            style: TextStyle(color: Colors.white.withOpacity(0.4))),
      );
    }

    return ListView(
      children: [
        if (filteredEmployees.isNotEmpty) ...[
          Container(
            color: Colors.white.withOpacity(0.04),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            child: Text('Сотрудники',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.7))),
          ),
          ...filteredEmployees.map((e) {
            final phone = (e.phone ?? '').replaceAll(RegExp(r'[\s\+]'), '');
            final isSelected = _selected.contains(phone);
            return CheckboxListTile(
              value: isSelected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(phone);
                  } else {
                    _selected.remove(phone);
                  }
                });
              },
              title: Text(e.name,
                  style: TextStyle(color: Colors.white.withOpacity(0.9))),
              subtitle: Text(e.position ?? '',
                  style: TextStyle(color: Colors.white.withOpacity(0.4))),
              secondary: CircleAvatar(
                backgroundColor: AppColors.emerald,
                child: Icon(Icons.badge, color: Colors.white.withOpacity(0.8)),
              ),
              activeColor: AppColors.emerald,
              checkColor: Colors.white,
            );
          }),
        ],
        if (filteredClients.isNotEmpty) ...[
          Container(
            color: Colors.white.withOpacity(0.04),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            child: Text('Клиенты',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[400])),
          ),
          ...filteredClients.map((c) {
            final phone = c.phone.replaceAll(RegExp(r'[\s\+]'), '');
            final isSelected = _selected.contains(phone);
            return CheckboxListTile(
              value: isSelected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(phone);
                  } else {
                    _selected.remove(phone);
                  }
                });
              },
              title: Text(c.displayName,
                  style: TextStyle(color: Colors.white.withOpacity(0.9))),
              subtitle: Text('Баллы: ${c.points}',
                  style: TextStyle(color: Colors.white.withOpacity(0.4))),
              secondary: CircleAvatar(
                backgroundColor: Colors.green.withOpacity(0.3),
                child: Icon(Icons.person, color: Colors.white.withOpacity(0.8)),
              ),
              activeColor: AppColors.emerald,
              checkColor: Colors.white,
            );
          }),
        ],
      ],
    );
  }
}

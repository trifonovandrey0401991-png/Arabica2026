import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/contact_model.dart';
import '../services/messenger_service.dart';
import 'messenger_chat_page.dart';

class GroupCreatePage extends StatefulWidget {
  final String userPhone;
  final String userName;
  final List<MessengerContact> selectedContacts;

  const GroupCreatePage({
    super.key,
    required this.userPhone,
    required this.userName,
    required this.selectedContacts,
  });

  @override
  State<GroupCreatePage> createState() => _GroupCreatePageState();
}

class _GroupCreatePageState extends State<GroupCreatePage> {
  final _nameController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название группы')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final participants = widget.selectedContacts
          .map((c) => {'phone': c.phone, 'name': c.name ?? c.phone})
          .toList();

      final conversation = await MessengerService.createGroup(
        creatorPhone: widget.userPhone,
        creatorName: widget.userName,
        name: name,
        participants: participants,
      );

      if (conversation != null && mounted) {
        // Убираем все предыдущие страницы поиска, переходим сразу в чат
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MessengerChatPage(
              conversation: conversation,
              userPhone: widget.userPhone,
              userName: widget.userName,
            ),
          ),
          (route) => route.isFirst, // оставляем только первую страницу (MessengerListPage)
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.emerald,
        foregroundColor: Colors.white,
        title: const Text('Новая группа'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Название группы
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Название группы',
                labelStyle: const TextStyle(color: AppColors.emerald),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.emerald, width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),

            const SizedBox(height: 24),

            Text(
              'Участники (${widget.selectedContacts.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.emerald),
            ),
            const SizedBox(height: 8),

            // Список участников
            Expanded(
              child: ListView.builder(
                itemCount: widget.selectedContacts.length,
                itemBuilder: (context, index) {
                  final contact = widget.selectedContacts[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.emeraldLight,
                      child: Text(
                        contact.displayName[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(contact.displayName),
                    subtitle: Text(contact.phone, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  );
                },
              ),
            ),

            // Кнопка создания
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isCreating ? null : _createGroup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isCreating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Создать группу', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../services/messenger_service.dart';

/// Bottom sheet for picking/managing message templates (quick replies).
class TemplatePicker extends StatefulWidget {
  final ValueChanged<String> onSelect;

  const TemplatePicker({super.key, required this.onSelect});

  @override
  State<TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<TemplatePicker> {
  List<Map<String, dynamic>> _templates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final templates = await MessengerService.getTemplates();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _isLoading = false;
    });
  }

  Future<void> _addTemplate() async {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        title: const Text('Новый шаблон', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Название (напр. "Приветствие")',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Текст сообщения',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Сохранить', style: TextStyle(color: AppColors.gold)),
          ),
        ],
      ),
    );

    if (result == true && titleCtrl.text.trim().isNotEmpty && contentCtrl.text.trim().isNotEmpty) {
      await MessengerService.createTemplate(
        title: titleCtrl.text.trim(),
        content: contentCtrl.text.trim(),
      );
      _load();
    }

    titleCtrl.dispose();
    contentCtrl.dispose();
  }

  Future<void> _deleteTemplate(int id) async {
    await MessengerService.deleteTemplate(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      decoration: BoxDecoration(
        color: AppColors.night,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text(
                  'Шаблоны',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.add, color: AppColors.gold),
                  onPressed: _addTemplate,
                  tooltip: 'Добавить шаблон',
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          // List
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else if (_templates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Нет шаблонов.\nНажмите + чтобы создать.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _templates.length,
                itemBuilder: (context, index) {
                  final t = _templates[index];
                  return ListTile(
                    title: Text(
                      t['title'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: Text(
                      t['content'] ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: Colors.white.withOpacity(0.3), size: 20),
                      onPressed: () => _deleteTemplate(t['id'] as int),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onSelect(t['content'] as String);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

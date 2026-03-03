import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Page to create a new poll.
/// Returns a Map with 'question', 'options', 'multipleChoice', 'anonymous'.
class CreatePollPage extends StatefulWidget {
  const CreatePollPage({super.key});

  @override
  State<CreatePollPage> createState() => _CreatePollPageState();
}

class _CreatePollPageState extends State<CreatePollPage> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _multipleChoice = false;
  bool _anonymous = false;

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= 10) return;
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);
    });
  }

  void _submit() {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;

    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (options.length < 2) return;

    Navigator.pop(context, {
      'question': question,
      'options': options,
      'multipleChoice': _multipleChoice,
      'anonymous': _anonymous,
    });
  }

  @override
  Widget build(BuildContext context) {
    final validOptions = _optionControllers
        .where((c) => c.text.trim().isNotEmpty)
        .length;
    final canSubmit = _questionController.text.trim().isNotEmpty && validOptions >= 2;

    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: AppColors.night,
        title: const Text('Новый опрос', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: canSubmit ? _submit : null,
            child: Text(
              'Создать',
              style: TextStyle(
                color: canSubmit ? AppColors.turquoise : Colors.white24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Question
          TextField(
            controller: _questionController,
            style: const TextStyle(color: Colors.white),
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Вопрос',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: AppColors.turquoise),
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 16),

          // Options
          ...List.generate(_optionControllers.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _optionControllers[index],
                      style: const TextStyle(color: Colors.white),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Вариант ${index + 1}',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: AppColors.turquoise),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  if (_optionControllers.length > 2)
                    IconButton(
                      icon: Icon(Icons.close, size: 18, color: Colors.white.withOpacity(0.3)),
                      onPressed: () => _removeOption(index),
                    ),
                ],
              ),
            );
          }),

          // Add option button
          if (_optionControllers.length < 10)
            TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add, color: AppColors.turquoise, size: 18),
              label: const Text('Добавить вариант', style: TextStyle(color: AppColors.turquoise)),
            ),

          const SizedBox(height: 16),

          // Settings
          SwitchListTile(
            value: _multipleChoice,
            onChanged: (v) => setState(() => _multipleChoice = v),
            title: Text('Несколько ответов', style: TextStyle(color: Colors.white.withOpacity(0.8))),
            activeColor: AppColors.turquoise,
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v),
            title: Text('Анонимный', style: TextStyle(color: Colors.white.withOpacity(0.8))),
            activeColor: AppColors.turquoise,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

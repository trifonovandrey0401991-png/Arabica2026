import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/training_model.dart';
import '../services/training_article_service.dart';

/// Страница управления статьями обучения
class TrainingArticlesManagementPage extends StatefulWidget {
  const TrainingArticlesManagementPage({super.key});

  @override
  State<TrainingArticlesManagementPage> createState() => _TrainingArticlesManagementPageState();
}

class _TrainingArticlesManagementPageState extends State<TrainingArticlesManagementPage> {
  List<TrainingArticle> _articles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadArticles();
  }

  Future<void> _loadArticles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final articles = await TrainingArticleService.getArticles();
      setState(() {
        _articles = articles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки статей: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openArticleUrl(String url) async {
    try {
      // Очищаем URL от лишних пробелов
      final cleanUrl = url.trim();
      
      // Проверяем, что URL не пустой
      if (cleanUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ссылка не указана'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Парсим URL
      Uri uri;
      try {
        uri = Uri.parse(cleanUrl);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Некорректный формат ссылки: $cleanUrl'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Если нет схемы, добавляем https://
      if (!uri.hasScheme) {
        uri = Uri.parse('https://$cleanUrl');
      }

      // Проверяем, можно ли открыть URL
      if (await canLaunchUrl(uri)) {
        // Пытаемся открыть в браузере
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        
        if (!launched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось открыть ссылку. Проверьте, установлен ли браузер.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Не удалось открыть ссылку: $uri'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка открытия ссылки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showAddArticleDialog() async {
    final result = await showDialog<TrainingArticle>(
      context: context,
      builder: (context) => const TrainingArticleFormDialog(),
    );

    if (result != null) {
      await _loadArticles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Статья успешно добавлена'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _showEditArticleDialog(TrainingArticle article) async {
    final result = await showDialog<TrainingArticle>(
      context: context,
      builder: (context) => TrainingArticleFormDialog(article: article),
    );

    if (result != null) {
      await _loadArticles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Статья успешно обновлена'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _deleteArticle(TrainingArticle article) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить статью?'),
        content: Text('Вы уверены, что хотите удалить статью:\n"${article.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await TrainingArticleService.deleteArticle(article.id);
      if (success) {
        await _loadArticles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Статья успешно удалена'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка удаления статьи'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Map<String, List<TrainingArticle>> _groupArticles() {
    final Map<String, List<TrainingArticle>> grouped = {};
    for (var article in _articles) {
      final group = article.group.isEmpty ? 'Без группы' : article.group;
      if (!grouped.containsKey(group)) {
        grouped[group] = [];
      }
      grouped[group]!.add(article);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статьи обучения'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadArticles,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _articles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.article, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'Нет статей',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Нажмите + чтобы добавить первую статью',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : _buildGroupedList(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddArticleDialog,
        backgroundColor: const Color(0xFF004D40),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildGroupedList() {
    final grouped = _groupArticles();
    final groups = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final group = groups[groupIndex];
        final groupArticles = grouped[group]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 12, top: groupIndex > 0 ? 24 : 0),
              child: Text(
                group,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            ...groupArticles.map((article) => Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(
                      Icons.article,
                      color: Color(0xFF004D40),
                    ),
                    title: Text(article.title),
                    subtitle: Text(
                      article.url,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.open_in_new, color: Color(0xFF004D40)),
                          onPressed: () => _openArticleUrl(article.url),
                          tooltip: 'Открыть статью',
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Color(0xFF004D40)),
                          onPressed: () => _showEditArticleDialog(article),
                          tooltip: 'Редактировать',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteArticle(article),
                          tooltip: 'Удалить',
                        ),
                      ],
                    ),
                    onTap: () => _openArticleUrl(article.url),
                  ),
                )),
          ],
        );
      },
    );
  }
}

/// Диалог для добавления/редактирования статьи обучения
class TrainingArticleFormDialog extends StatefulWidget {
  final TrainingArticle? article;

  const TrainingArticleFormDialog({super.key, this.article});

  @override
  State<TrainingArticleFormDialog> createState() => _TrainingArticleFormDialogState();
}

class _TrainingArticleFormDialogState extends State<TrainingArticleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _groupController = TextEditingController();
  final _urlController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.article != null) {
      _titleController.text = widget.article!.title;
      _groupController.text = widget.article!.group;
      _urlController.text = widget.article!.url;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _groupController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  Future<void> _saveArticle() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      TrainingArticle? result;
      if (widget.article != null) {
        // Обновление существующей статьи
        result = await TrainingArticleService.updateArticle(
          id: widget.article!.id,
          group: _groupController.text.trim(),
          title: _titleController.text.trim(),
          url: _urlController.text.trim(),
        );
      } else {
        // Создание новой статьи
        result = await TrainingArticleService.createArticle(
          group: _groupController.text.trim(),
          title: _titleController.text.trim(),
          url: _urlController.text.trim(),
        );
      }

      if (result != null && mounted) {
        Navigator.pop(context, result);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка сохранения статьи'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.article == null ? 'Добавить статью' : 'Редактировать статью'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Название статьи',
                  border: OutlineInputBorder(),
                  hintText: 'Введите название статьи',
                  helperText: 'Это название будет отображаться как название кнопки',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Пожалуйста, введите название статьи';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _groupController,
                decoration: const InputDecoration(
                  labelText: 'Группа статьи',
                  border: OutlineInputBorder(),
                  hintText: 'Введите название группы',
                  helperText: 'Статьи будут сгруппированы по этому полю',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Пожалуйста, введите группу статьи';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Ссылка на статью',
                  border: OutlineInputBorder(),
                  hintText: 'https://example.com/article',
                  helperText: 'При нажатии на статью откроется эта ссылка',
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Пожалуйста, введите ссылку на статью';
                  }
                  if (!_isValidUrl(value.trim())) {
                    return 'Пожалуйста, введите валидный URL (начинается с http:// или https://)';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveArticle,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF004D40),
          ),
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}


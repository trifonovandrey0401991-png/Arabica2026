import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/training_model.dart';
import '../services/training_article_service.dart';
import 'training_article_view_page.dart';
import 'training_article_editor_page.dart';

/// Страница управления статьями обучения
class TrainingArticlesManagementPage extends StatefulWidget {
  const TrainingArticlesManagementPage({super.key});

  @override
  State<TrainingArticlesManagementPage> createState() => _TrainingArticlesManagementPageState();
}

class _TrainingArticlesManagementPageState extends State<TrainingArticlesManagementPage> {
  // Dark Emerald цвета
  static const _emerald = Color(0xFF1A4D4D);
  static const _emeraldDark = Color(0xFF0D2E2E);
  static const _night = Color(0xFF051515);
  static const _gold = Color(0xFFD4AF37);

  List<TrainingArticle> _articles = [];
  List<TrainingArticle> _filteredArticles = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedGroupFilter;

  @override
  void initState() {
    super.initState();
    _loadArticles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    _filteredArticles = _articles.where((article) {
      // Фильтр по поиску
      final matchesSearch = _searchQuery.isEmpty ||
          article.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          article.group.toLowerCase().contains(_searchQuery.toLowerCase());

      // Фильтр по группе
      final articleGroup = article.group.isEmpty ? 'Без группы' : article.group;
      final matchesGroup = _selectedGroupFilter == null || articleGroup == _selectedGroupFilter;

      return matchesSearch && matchesGroup;
    }).toList();
  }

  Future<void> _loadArticles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final articles = await TrainingArticleService.getArticles();
      setState(() {
        _articles = articles;
        _applyFilters();
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

  /// Открыть статью для просмотра
  void _openArticle(TrainingArticle article) {
    // Если есть контент - открываем страницу просмотра
    // Если только URL - открываем в браузере
    if (article.hasContent) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TrainingArticleViewPage(article: article),
        ),
      );
    } else if (article.hasUrl) {
      _openArticleUrl(article.url!);
    } else {
      // Нет ни контента, ни URL - открываем страницу просмотра с пустым контентом
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TrainingArticleViewPage(article: article),
        ),
      );
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
    final result = await Navigator.push<TrainingArticle>(
      context,
      MaterialPageRoute(
        builder: (context) => const TrainingArticleEditorPage(),
      ),
    );

    if (result != null) {
      await _loadArticles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Статья успешно добавлена'),
              ],
            ),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  Future<void> _showEditArticleDialog(TrainingArticle article) async {
    final result = await Navigator.push<TrainingArticle>(
      context,
      MaterialPageRoute(
        builder: (context) => TrainingArticleEditorPage(article: article),
      ),
    );

    if (result != null) {
      await _loadArticles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Статья успешно обновлена'),
              ],
            ),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  Future<void> _deleteArticle(TrainingArticle article) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: _emeraldDark,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Иконка предупреждения
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red[400]!, Colors.red[600]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delete_forever_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Удалить статью?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Контент
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Text(
                        article.title,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Это действие невозможно отменить',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              // Кнопки
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Text(
                          'Отмена',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[500],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Удалить',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

    if (confirmed == true) {
      final success = await TrainingArticleService.deleteArticle(article.id);
      if (success) {
        await _loadArticles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Статья успешно удалена'),
                ],
              ),
              backgroundColor: Colors.green[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Ошибка удаления статьи'),
                ],
              ),
              backgroundColor: Colors.red[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(16),
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
      body: Container(
        decoration: const BoxDecoration(
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
              // Кастомный AppBar
              _buildCustomAppBar(),
              // Контент
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _gold.withOpacity(0.4)),
          color: _gold.withOpacity(0.2),
        ),
        child: FloatingActionButton.extended(
          onPressed: _showAddArticleDialog,
          backgroundColor: Colors.transparent,
          elevation: 0,
          highlightElevation: 0,
          icon: const Icon(Icons.add_rounded, color: _gold),
          label: const Text(
            'Добавить',
            style: TextStyle(
              color: _gold,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        children: [
          Row(
            children: [
              // Кнопка назад
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 12),
              // Заголовок
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Статьи обучения',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_articles.length} ${_getArticleEnding(_articles.length)}',
                      style: TextStyle(
                        color: _gold.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              // Кнопка обновить
              _buildActionButton(
                icon: Icons.refresh,
                onPressed: _loadArticles,
                tooltip: 'Обновить',
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Поле поиска
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Поиск по статьям...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, color: Colors.white.withOpacity(0.5), size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _applyFilters();
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              cursorColor: _gold,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _applyFilters();
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          // Статистика по группам
          _buildGroupStatsRow(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onPressed,
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      ),
    );
  }

  Widget _buildGroupStatsRow() {
    final grouped = _groupArticles();
    final groups = grouped.keys.toList()..sort();

    if (groups.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Чип "Все"
          _buildGroupChip(
            group: null,
            label: 'Все',
            count: _articles.length,
            isSelected: _selectedGroupFilter == null,
          ),
          const SizedBox(width: 8),
          // Чипы групп
          ...groups.map((group) {
            final count = grouped[group]!.length;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildGroupChip(
                group: group,
                label: group,
                count: count,
                isSelected: _selectedGroupFilter == group,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildGroupChip({
    required String? group,
    required String label,
    required int count,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedGroupFilter = group;
          _applyFilters();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _gold.withOpacity(0.15) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _gold.withOpacity(0.4) : Colors.white.withOpacity(0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              group == null ? Icons.apps_rounded : Icons.folder_outlined,
              size: 16,
              color: isSelected ? _gold : Colors.white.withOpacity(0.6),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? _gold : Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getArticleEnding(int count) {
    if (count % 100 >= 11 && count % 100 <= 19) return 'статей';
    switch (count % 10) {
      case 1: return 'статья';
      case 2:
      case 3:
      case 4: return 'статьи';
      default: return 'статей';
    }
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_gold),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Загрузка статей...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_articles.isEmpty) {
      return _buildEmptyState();
    }

    if (_filteredArticles.isEmpty && (_searchQuery.isNotEmpty || _selectedGroupFilter != null)) {
      return _buildNoResultsState();
    }

    return _buildGroupedList();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: _gold.withOpacity(0.2)),
            ),
            child: Icon(
              Icons.article_outlined,
              size: 56,
              color: _gold.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Нет статей',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Нажмите кнопку "Добавить"\nчтобы создать первую статью',
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withOpacity(0.5),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Ничего не найдено',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Попробуйте изменить параметры поиска',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _selectedGroupFilter = null;
                _applyFilters();
              });
            },
            icon: const Icon(Icons.refresh, color: _gold),
            label: const Text('Сбросить фильтры'),
            style: TextButton.styleFrom(
              foregroundColor: _gold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList() {
    // Используем _filteredArticles для фильтрации (учитывает и поиск и группу)
    final articlesToShow = (_searchQuery.isNotEmpty || _selectedGroupFilter != null)
        ? _filteredArticles
        : _articles;
    final Map<String, List<TrainingArticle>> grouped = {};
    for (var article in articlesToShow) {
      final group = article.group.isEmpty ? 'Без группы' : article.group;
      if (!grouped.containsKey(group)) {
        grouped[group] = [];
      }
      grouped[group]!.add(article);
    }
    final groups = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final group = groups[groupIndex];
        final groupArticles = grouped[group]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок группы
            Container(
              margin: EdgeInsets.only(bottom: 8, top: groupIndex > 0 ? 16 : 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_gold.withOpacity(0.15), _gold.withOpacity(0.05)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _gold.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_rounded,
                    color: _gold,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _gold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${groupArticles.length}',
                      style: const TextStyle(
                        color: _gold,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Статьи в группе
            ...groupArticles.asMap().entries.map((entry) {
              final index = entry.key;
              final article = entry.value;
              return _buildArticleCard(article, index);
            }),
          ],
        );
      },
    );
  }

  Widget _buildArticleCard(TrainingArticle article, int index) {
    final isManagersOnly = article.visibility == 'managers';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isManagersOnly
              ? Colors.orange.withOpacity(0.3)
              : Colors.white.withOpacity(0.08),
          width: isManagersOnly ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openArticle(article),
          splashColor: _gold.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Иконка статьи
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isManagersOnly
                        ? Colors.orange.withOpacity(0.15)
                        : _gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isManagersOnly
                          ? Colors.orange.withOpacity(0.3)
                          : _gold.withOpacity(0.3),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      isManagersOnly ? Icons.supervisor_account_rounded : Icons.article_rounded,
                      color: isManagersOnly ? Colors.orange[300] : _gold,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Контент
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isManagersOnly)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.orange.withOpacity(0.3)),
                            ),
                            child: Text(
                              'Только заведующие',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[300],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Кнопки действий
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildCardActionButton(
                      icon: article.hasContent ? Icons.visibility_rounded : Icons.open_in_new_rounded,
                      color: Colors.blue[300]!,
                      onTap: () => _openArticle(article),
                    ),
                    const SizedBox(width: 4),
                    _buildCardActionButton(
                      icon: Icons.edit_rounded,
                      color: _gold,
                      onTap: () => _showEditArticleDialog(article),
                    ),
                    const SizedBox(width: 4),
                    _buildCardActionButton(
                      icon: Icons.delete_outline_rounded,
                      color: Colors.red[300]!,
                      onTap: () => _deleteArticle(article),
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

  Widget _buildCardActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
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
  // Dark Emerald цвета
  static const _emerald = Color(0xFF1A4D4D);
  static const _emeraldDark = Color(0xFF0D2E2E);
  static const _night = Color(0xFF051515);
  static const _gold = Color(0xFFD4AF37);

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _groupController = TextEditingController();
  final _contentController = TextEditingController();
  final _urlController = TextEditingController();
  bool _isSaving = false;
  bool _showUrlField = false;

  @override
  void initState() {
    super.initState();
    if (widget.article != null) {
      _titleController.text = widget.article!.title;
      _groupController.text = widget.article!.group;
      _contentController.text = widget.article!.content;
      _urlController.text = widget.article!.url ?? '';
      _showUrlField = widget.article!.hasUrl;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _groupController.dispose();
    _contentController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  bool _isValidUrl(String url) {
    if (url.isEmpty) return true; // URL опционален
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
      final url = _showUrlField ? _urlController.text.trim() : null;

      if (widget.article != null) {
        // Обновление существующей статьи
        result = await TrainingArticleService.updateArticle(
          id: widget.article!.id,
          group: _groupController.text.trim(),
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          url: url,
        );
      } else {
        // Создание новой статьи
        result = await TrainingArticleService.createArticle(
          group: _groupController.text.trim(),
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          url: url,
        );
      }

      if (result != null && mounted) {
        Navigator.pop(context, result);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Ошибка сохранения статьи'),
                ],
              ),
              backgroundColor: Colors.red[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Ошибка: $e')),
              ],
            ),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
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
    final isEditing = widget.article != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        decoration: BoxDecoration(
          color: _emeraldDark,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок с градиентом
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_emerald, _emeraldDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _gold.withOpacity(0.3)),
                    ),
                    child: Icon(
                      isEditing ? Icons.edit_rounded : Icons.add_rounded,
                      color: _gold,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEditing ? 'Редактировать статью' : 'Добавить статью',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        isEditing ? 'Измените данные статьи' : 'Заполните данные новой статьи',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Форма
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Поле названия
                      _buildTextField(
                        controller: _titleController,
                        label: 'Название статьи',
                        hint: 'Введите название статьи',
                        icon: Icons.title_rounded,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Введите название статьи';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Поле группы
                      _buildTextField(
                        controller: _groupController,
                        label: 'Группа статьи',
                        hint: 'Введите название группы',
                        icon: Icons.folder_rounded,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Введите группу статьи';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Поле контента статьи
                      _buildContentField(),
                      const SizedBox(height: 16),
                      // Чекбокс для внешней ссылки
                      InkWell(
                        onTap: () {
                          setState(() {
                            _showUrlField = !_showUrlField;
                            if (!_showUrlField) {
                              _urlController.clear();
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _showUrlField ? _gold.withOpacity(0.1) : Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _showUrlField ? _gold.withOpacity(0.3) : Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _showUrlField ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                color: _showUrlField ? _gold : Colors.white.withOpacity(0.4),
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Добавить внешнюю ссылку',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: _showUrlField ? _gold : Colors.white.withOpacity(0.7),
                                      ),
                                    ),
                                    Text(
                                      'Опционально: ссылка на дополнительный источник',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white.withOpacity(0.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Поле ссылки (показывается если включён чекбокс)
                      if (_showUrlField) ...[
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _urlController,
                          label: 'Ссылка на источник',
                          hint: 'https://example.com/article',
                          icon: Icons.link_rounded,
                          keyboardType: TextInputType.url,
                          validator: (value) {
                            if (value != null && value.trim().isNotEmpty && !_isValidUrl(value.trim())) {
                              return 'Введите валидный URL (http:// или https://)';
                            }
                            return null;
                          },
                        ),
                      ],
                      // Подсказки
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _emerald.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _gold.withOpacity(0.15)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: _gold.withOpacity(0.7),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Контент статьи будет отображаться прямо в приложении',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.6),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Кнопки
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _night,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Text(
                        'Отмена',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : _saveArticle,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: _gold.withOpacity(0.4)),
                        backgroundColor: _gold.withOpacity(0.15),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(_gold),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isEditing ? Icons.save_rounded : Icons.add_rounded,
                                  size: 18,
                                  color: _gold,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isEditing ? 'Сохранить' : 'Добавить',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: _gold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.article_rounded, color: _gold, size: 20),
            const SizedBox(width: 8),
            Text(
              'Контент статьи',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _contentController,
          maxLines: 8,
          minLines: 5,
          style: TextStyle(fontSize: 14, height: 1.5, color: Colors.white.withOpacity(0.9)),
          decoration: InputDecoration(
            hintText: 'Введите текст статьи...\n\nМожно использовать несколько абзацев для удобного чтения.',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), height: 1.5),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _gold.withOpacity(0.5), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.red[300]!),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.red[400]!, width: 2),
            ),
            contentPadding: const EdgeInsets.all(16),
            errorStyle: TextStyle(color: Colors.red[300]),
          ),
          cursorColor: _gold,
          validator: (value) {
            if ((value == null || value.trim().isEmpty) && !_showUrlField) {
              return 'Введите контент статьи или добавьте внешнюю ссылку';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.9)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        prefixIcon: Container(
          margin: const EdgeInsets.only(left: 12, right: 8),
          child: Icon(icon, color: _gold, size: 22),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _gold.withOpacity(0.5), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red[300]!),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red[400]!, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        errorStyle: TextStyle(color: Colors.red[300]),
      ),
      cursorColor: _gold,
      validator: validator,
    );
  }
}

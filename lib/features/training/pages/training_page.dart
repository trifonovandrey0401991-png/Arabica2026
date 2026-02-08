import 'dart:math';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/utils/logger.dart';
import '../models/training_model.dart';
import 'training_article_view_page.dart';
import '../../employees/pages/employees_page.dart';
import '../../employees/services/employee_service.dart';

/// Страница обучения
class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key});

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  late Future<List<TrainingArticle>> _articlesFuture;
  bool _isManager = false;
  List<TrainingArticle> _allArticles = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // Единая палитра приложения
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _articlesFuture = _loadFilteredArticles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Загрузить статьи с фильтрацией по роли пользователя
  Future<List<TrainingArticle>> _loadFilteredArticles() async {
    _isManager = await _checkIsManager();
    Logger.debug('👤 Пользователь является заведующим: $_isManager');

    final allArticles = await TrainingArticle.loadArticles();

    final filteredArticles = allArticles.where((article) {
      if (article.visibility == 'managers') {
        return _isManager;
      }
      return true;
    }).toList();

    Logger.debug('📚 Загружено статей: ${allArticles.length}, после фильтрации: ${filteredArticles.length}');
    _allArticles = filteredArticles;
    return filteredArticles;
  }

  /// Проверить, является ли текущий пользователь заведующим
  Future<bool> _checkIsManager() async {
    try {
      final employeeId = await EmployeesPage.getCurrentEmployeeId();
      if (employeeId == null) {
        Logger.debug('⚠️ ID сотрудника не найден');
        return false;
      }

      final employees = await EmployeeService.getEmployees();
      final employee = employees.firstWhere(
        (e) => e.id == employeeId,
        orElse: () => Employee(id: '', name: ''),
      );

      return employee.isManager == true;
    } catch (e) {
      Logger.error('Ошибка проверки роли заведующего', e);
      return false;
    }
  }

  /// Получить полный текст статьи для поиска
  String _getArticleSearchText(TrainingArticle article) {
    final buffer = StringBuffer();
    buffer.write(article.title);
    buffer.write(' ');
    buffer.write(article.group);
    buffer.write(' ');
    buffer.write(article.content);
    for (final block in article.contentBlocks) {
      if (block.type.name == 'text') {
        buffer.write(' ');
        buffer.write(block.content);
      }
      if (block.caption != null) {
        buffer.write(' ');
        buffer.write(block.caption);
      }
    }
    return buffer.toString().toLowerCase();
  }

  /// Нечёткий поиск — проверяет, содержит ли текст слово с допуском ошибок
  bool _fuzzyContains(String text, String query) {
    if (query.isEmpty) return true;
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase().trim();

    // Разбиваем запрос на слова
    final queryWords = lowerQuery.split(RegExp(r'\s+'));

    for (final word in queryWords) {
      if (word.isEmpty) continue;

      // Точное вхождение подстроки
      if (lowerText.contains(word)) continue;

      // Нечёткий поиск — ищем похожее слово в тексте
      if (!_fuzzyWordMatch(lowerText, word)) return false;
    }
    return true;
  }

  /// Нечёткое сопоставление слова в тексте
  bool _fuzzyWordMatch(String text, String word) {
    if (word.length <= 2) return text.contains(word);

    // Допустимое расстояние: 1 ошибка для коротких слов, 2 для длинных
    final maxDist = word.length <= 4 ? 1 : 2;

    // Разбиваем текст на слова и проверяем каждое
    final textWords = text.split(RegExp(r'[^а-яёa-z0-9]+'));
    for (final tw in textWords) {
      if (tw.isEmpty) continue;
      // Если длины сильно различаются — пропускаем
      if ((tw.length - word.length).abs() > maxDist) continue;
      if (_levenshtein(tw, word) <= maxDist) return true;
    }

    // Также проверяем, есть ли подстрока с допуском
    // (для случаев когда слово — часть длинного слова)
    for (final tw in textWords) {
      if (tw.length >= word.length && tw.length <= word.length + 3) {
        // Проверяем начало слова
        if (word.length >= 3) {
          final prefix = word.substring(0, min(word.length, tw.length));
          if (_levenshtein(tw.substring(0, min(prefix.length, tw.length)), prefix) <= maxDist) {
            return true;
          }
        }
      }
    }

    return false;
  }

  /// Расстояние Левенштейна
  int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final la = a.length;
    final lb = b.length;

    // Оптимизация: используем только две строки
    var prev = List<int>.generate(lb + 1, (i) => i);
    var curr = List<int>.filled(lb + 1, 0);

    for (var i = 1; i <= la; i++) {
      curr[0] = i;
      for (var j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = min(min(prev[j] + 1, curr[j - 1] + 1), prev[j - 1] + cost);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[lb];
  }

  /// Найти фрагмент текста, содержащий совпадение
  String? _findMatchSnippet(TrainingArticle article, String query) {
    if (query.isEmpty) return null;
    final lowerQuery = query.toLowerCase().trim();
    final queryWords = lowerQuery.split(RegExp(r'\s+'));
    final firstWord = queryWords.first;
    if (firstWord.isEmpty) return null;

    // Ищем в контенте (не в заголовке)
    String fullText = article.content;
    for (final block in article.contentBlocks) {
      if (block.type.name == 'text') {
        fullText += ' ${block.content}';
      }
    }

    final lowerFull = fullText.toLowerCase();
    final idx = lowerFull.indexOf(firstWord);
    if (idx == -1) {
      // Нечёткий поиск — ищем похожее слово
      final words = lowerFull.split(RegExp(r'[^а-яёa-z0-9]+'));
      final maxDist = firstWord.length <= 4 ? 1 : 2;
      for (final w in words) {
        if (w.isEmpty || (w.length - firstWord.length).abs() > maxDist) continue;
        if (_levenshtein(w, firstWord) <= maxDist) {
          final wIdx = lowerFull.indexOf(w);
          if (wIdx != -1) {
            return _extractSnippet(fullText, wIdx, w.length);
          }
        }
      }
      return null;
    }

    return _extractSnippet(fullText, idx, firstWord.length);
  }

  /// Извлечь фрагмент текста вокруг позиции
  String _extractSnippet(String text, int matchIdx, int matchLen) {
    // Берём контекст вокруг совпадения
    final start = max(0, matchIdx - 40);
    final end = min(text.length, matchIdx + matchLen + 80);
    var snippet = text.substring(start, end).replaceAll('\n', ' ').trim();
    if (start > 0) snippet = '...$snippet';
    if (end < text.length) snippet = '$snippet...';
    return snippet;
  }

  /// Получить отфильтрованные статьи по поисковому запросу
  List<TrainingArticle> _getSearchResults() {
    if (_searchQuery.isEmpty) return [];
    return _allArticles.where((article) {
      final searchText = _getArticleSearchText(article);
      return _fuzzyContains(searchText, _searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
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
              _buildAppBar(),
              _buildSearchBar(),
              Expanded(
                child: _searchQuery.isNotEmpty
                    ? _buildSearchResults()
                    : _buildArticlesList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArticlesList() {
    return FutureBuilder<List<TrainingArticle>>(
      future: _articlesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmptyState();
        }

        final articles = snapshot.data!;

        // Группируем статьи по группам
        final Map<String, List<TrainingArticle>> grouped = {};
        for (var article in articles) {
          if (!grouped.containsKey(article.group)) {
            grouped[article.group] = [];
          }
          grouped[article.group]!.add(article);
        }

        final groups = grouped.keys.toList()..sort();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          itemCount: groups.length,
          itemBuilder: (context, groupIndex) {
            final group = groups[groupIndex];
            final groupArticles = grouped[group]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (groupIndex > 0) const SizedBox(height: 16),
                _buildGroupHeader(group, groupArticles.length),
                const SizedBox(height: 8),
                ...groupArticles.map((article) => _buildArticleCard(article)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSearchResults() {
    final results = _getSearchResults();

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Ничего не найдено',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Попробуйте другой запрос',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Найдено: ${results.length} ${_getArticlesText(results.length)}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          );
        }
        return _buildSearchResultCard(results[index - 1]);
      },
    );
  }

  Widget _buildSearchResultCard(TrainingArticle article) {
    final snippet = _findMatchSnippet(article, _searchQuery);

    return GestureDetector(
      onTap: () => _openArticle(article),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
          color: Colors.white.withOpacity(0.06),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _emerald.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.article_rounded,
                    color: Colors.white.withOpacity(0.8),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        article.group,
                        style: TextStyle(
                          fontSize: 11,
                          color: _gold.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.3),
                  size: 20,
                ),
              ],
            ),
            if (snippet != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  snippet,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.08),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Icon(
                Icons.search_rounded,
                color: Colors.white.withOpacity(0.4),
                size: 20,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Поиск по статьям...',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                  _searchFocus.unfocus();
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withOpacity(0.4),
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
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
          const Expanded(
            child: Text(
              'Обучение',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(
              Icons.school_outlined,
              size: 32,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Статьи не найдены',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Материалы для обучения пока не добавлены',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(String group, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withOpacity(0.5)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _gold.withOpacity(0.15),
            _gold.withOpacity(0.05),
          ],
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_rounded,
            color: _gold,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              group,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _gold,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count ${_getArticlesText(count)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _gold.withOpacity(0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getArticlesText(int count) {
    if (count == 1) return 'статья';
    if (count >= 2 && count <= 4) return 'статьи';
    return 'статей';
  }

  void _openArticle(TrainingArticle article) async {
    if (article.hasContent) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TrainingArticleViewPage(article: article),
        ),
      );
    } else if (article.hasUrl) {
      final uri = Uri.parse(article.url!);
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        Logger.error('Ошибка открытия ссылки', e);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Не удалось открыть ссылку: ${article.url}'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TrainingArticleViewPage(article: article),
        ),
      );
    }
  }

  Widget _buildArticleCard(TrainingArticle article) {
    final hasContent = article.hasContent;

    return GestureDetector(
      onTap: () => _openArticle(article),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
          color: Colors.white.withOpacity(0.04),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hasContent
                    ? _emerald.withOpacity(0.4)
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                hasContent ? Icons.article_rounded : Icons.open_in_new_rounded,
                color: hasContent
                    ? Colors.white.withOpacity(0.8)
                    : Colors.white.withOpacity(0.5),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasContent ? 'Просмотр' : 'Внешняя ссылка',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              hasContent ? Icons.chevron_right_rounded : Icons.open_in_new_rounded,
              color: Colors.white.withOpacity(0.3),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

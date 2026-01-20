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

  // Основные цвета
  static const _primaryColor = Color(0xFF004D40);
  static const _primaryColorLight = Color(0xFF00695C);
  static const _backgroundColor = Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    _articlesFuture = _loadFilteredArticles();
  }

  /// Загрузить статьи с фильтрацией по роли пользователя
  Future<List<TrainingArticle>> _loadFilteredArticles() async {
    // Сначала проверяем, является ли пользователь заведующим
    _isManager = await _checkIsManager();
    Logger.debug('👤 Пользователь является заведующим: $_isManager');

    // Загружаем все статьи
    final allArticles = await TrainingArticle.loadArticles();

    // Фильтруем статьи по видимости
    final filteredArticles = allArticles.where((article) {
      if (article.visibility == 'managers') {
        // Статьи для заведующих показываем только заведующим
        return _isManager;
      }
      // Статьи с visibility == 'all' показываем всем
      return true;
    }).toList();

    Logger.debug('📚 Загружено статей: ${allArticles.length}, после фильтрации: ${filteredArticles.length}');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Обучение',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<List<TrainingArticle>>(
        future: _articlesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: _primaryColor),
                  SizedBox(height: 16),
                  Text(
                    'Загрузка статей...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Статьи не найдены',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
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
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            itemBuilder: (context, groupIndex) {
              final group = groups[groupIndex];
              final groupArticles = grouped[group]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (groupIndex > 0) const SizedBox(height: 20),
                  // Заголовок группы
                  _buildGroupHeader(group, groupArticles.length),
                  const SizedBox(height: 10),
                  // Статьи группы
                  ...groupArticles.map((article) => _buildArticleCard(article)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildGroupHeader(String group, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _primaryColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.folder_rounded,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              group,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count ${_getArticlesText(count)}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
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

  Widget _buildArticleCard(TrainingArticle article) {
    final hasUrl = article.hasUrl;
    final hasContent = article.hasContent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            // Если есть контент - открываем страницу просмотра
            if (hasContent) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TrainingArticleViewPage(article: article),
                ),
              );
            } else if (hasUrl) {
              // Если только URL - открываем в браузере
              final uri = Uri.parse(article.url!);
              try {
                await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
              } catch (e) {
                Logger.error('Ошибка открытия ссылки', e);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Не удалось открыть ссылку: ${article.url}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            } else {
              // Нет ни контента, ни URL
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TrainingArticleViewPage(article: article),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Иконка статьи
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: hasContent
                        ? _primaryColor.withOpacity(0.1)
                        : _primaryColorLight.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    hasContent ? Icons.article_rounded : Icons.open_in_new_rounded,
                    color: hasContent ? _primaryColor : _primaryColorLight,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                // Информация о статье
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasContent ? 'Просмотр' : 'Внешняя ссылка',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                // Стрелка
                Icon(
                  hasContent ? Icons.chevron_right : Icons.open_in_new,
                  color: _primaryColor,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/training_model.dart';

/// Страница обучения
class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key});

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  late Future<List<TrainingArticle>> _articlesFuture;

  @override
  void initState() {
    super.initState();
    _articlesFuture = TrainingArticle.loadArticles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Обучение'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40), // Темно-бирюзовый фон (fallback)
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6, // Прозрачность фона для хорошей видимости логотипа
          ),
        ),
        child: FutureBuilder<List<TrainingArticle>>(
        future: _articlesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Загрузка статей...'),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text('Статьи не найдены'),
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
                  Padding(
                    padding: EdgeInsets.only(bottom: 12, top: groupIndex > 0 ? 24 : 0),
                    child: Text(
                      group,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  ...groupArticles.map((article) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(Icons.article, color: Color(0xFF004D40)),
                      title: Text(
                        article.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () async {
                        final uri = Uri.parse(article.url);
                        try {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (e) {
                          print('❌ Ошибка открытия ссылки: $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Не удалось открыть ссылку: ${article.url}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  )),
                ],
              );
            },
          );
        },
      ),
        ),
    );
  }
}


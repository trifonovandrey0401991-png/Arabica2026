import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Модель статьи обучения
class TrainingArticle {
  final String group;
  final String title;
  final String url;

  TrainingArticle({
    required this.group,
    required this.title,
    required this.url,
  });

  /// Загрузить статьи обучения из Google Sheets
  static Future<List<TrainingArticle>> loadArticles() async {
    try {
      const sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Статьи_Обучения';
      
      print('📥 Загружаем статьи обучения из Google Sheets...');
      final response = await http.get(Uri.parse(sheetUrl));
      
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      final List<TrainingArticle> articles = [];

      // Пропускаем заголовок (первая строка)
      for (var i = 1; i < lines.length; i++) {
        try {
          final row = _parseCsvLine(lines[i]);
          
          if (row.length >= 3) {
            final group = row[0].trim().replaceAll('"', '');
            final url = row[1].trim().replaceAll('"', '');
            final title = row[2].trim().replaceAll('"', '');
            
            if (group.isNotEmpty && title.isNotEmpty && url.isNotEmpty) {
              articles.add(TrainingArticle(
                group: group,
                title: title,
                url: url,
              ));
            }
          }
        } catch (e) {
          continue;
        }
      }

      print('✅ Загружено статей: ${articles.length}');
      return articles;
    } catch (e) {
      print('⚠️ Ошибка загрузки статей: $e');
      return [];
    }
  }

  static List<String> _parseCsvLine(String line) {
    final List<String> result = [];
    String current = '';
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(current);
        current = '';
      } else {
        current += char;
      }
    }
    result.add(current);
    return result;
  }
}


















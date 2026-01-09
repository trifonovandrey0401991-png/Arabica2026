import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/job_application_model.dart';

class JobApplicationService {
  static const String _baseUrl = ApiConstants.serverUrl;

  /// Создать заявку на трудоустройство
  static Future<JobApplication?> create({
    required String fullName,
    required String phone,
    required String preferredShift,
    required List<String> shopAddresses,
  }) async {
    try {
      Logger.debug('📤 Создание заявки на работу: $fullName');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/job-applications'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'fullName': fullName,
          'phone': phone,
          'preferredShift': preferredShift,
          'shopAddresses': shopAddresses,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['application'] != null) {
          Logger.info('✅ Заявка создана успешно');
          return JobApplication.fromJson(data['application']);
        }
      }

      Logger.error('❌ Ошибка создания заявки: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка при создании заявки: $e');
      return null;
    }
  }

  /// Получить все заявки (для админа)
  static Future<List<JobApplication>> getAll() async {
    try {
      Logger.debug('📥 Загрузка заявок на работу...');

      final response = await http.get(
        Uri.parse('$_baseUrl/api/job-applications'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> applications = data['applications'] ?? [];

        final result = applications
            .map((json) => JobApplication.fromJson(json))
            .toList();

        // Сортируем по дате (новые сверху)
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        Logger.info('✅ Загружено ${result.length} заявок');
        return result;
      }

      Logger.error('❌ Ошибка загрузки заявок: ${response.statusCode}');
      return [];
    } catch (e) {
      Logger.error('❌ Ошибка при загрузке заявок: $e');
      return [];
    }
  }

  /// Получить количество непросмотренных заявок
  static Future<int> getUnviewedCount() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/job-applications/unviewed-count'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['count'] ?? 0;
      }

      return 0;
    } catch (e) {
      Logger.error('❌ Ошибка получения количества непросмотренных: $e');
      return 0;
    }
  }

  /// Отметить заявку как просмотренную
  static Future<bool> markAsViewed(String id, String adminName) async {
    try {
      Logger.debug('📤 Отметка заявки $id как просмотренной');

      final response = await http.patch(
        Uri.parse('$_baseUrl/api/job-applications/$id/view'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'adminName': adminName,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        Logger.info('✅ Заявка отмечена как просмотренная');
        return true;
      }

      Logger.error('❌ Ошибка отметки заявки: ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка при отметке заявки: $e');
      return false;
    }
  }
}
